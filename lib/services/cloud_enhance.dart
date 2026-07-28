import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/photo.dart';
import '../utils/constants.dart';
import 'log_service.dart';

/// 单个模型配置
class ModelConfig {
  String modelName;
  String apiBaseUrl;
  String apiKey;

  ModelConfig({
    this.modelName = '',
    this.apiBaseUrl = '',
    this.apiKey = '',
  });

  bool get isEnabled => apiKey.isNotEmpty && apiBaseUrl.isNotEmpty && modelName.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'model': modelName,
        'baseUrl': apiBaseUrl,
        'apiKey': apiKey,
      };

  factory ModelConfig.fromJson(Map<String, dynamic> json) => ModelConfig(
        modelName: json['model'] as String? ?? '',
        apiBaseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
      );
}

/// 云端增强服务（可选）
/// 支持配置最多5个模型，批量解析时自动分配到各模型并行处理
class CloudEnhanceService {
  static const _keyModels = 'cloud_models';
  static const _keyExcludedFolders = 'excluded_folders';
  static const _keyTempShareDuration = 'temp_share_duration';
  static const _keyModelName = 'cloud_model_name';
  static const _keyApiBaseUrl = 'cloud_api_base_url';
  static const _keyApiKey = 'cloud_api_key';
  static const _keyCustomPrompt = 'custom_prompt';
  static const _keyDebugEnabled = 'debug_enabled';
  static const _keyFailureLogs = 'failure_logs';

  static const int maxModels = 5;
  static const int _maxLogEntries = 50;

  static const String _defaultPrompt = '详细分析这张图片，生成搜索关键词标签，逗号分隔。\n'
      '\n'
      '必须包含以下维度：\n'
      '1. 场景/地点/氛围：如 室内, 户外, 海滩, 夜晚, 雨天, 夕阳\n'
      '2. 主要物体/元素：如 汽车, 蛋糕, 书本, 手机, 花朵\n'
      '3. 人物特征（有人物时必写）：\n'
      '   - 性别/年龄：如 少女, 青年男性, 老人, 小孩\n'
      '   - 发色/发型：如 金发, 黑长直, 短发, 双马尾, 白发\n'
      '   - 瞳色：如 蓝瞳, 红瞳, 绿瞳\n'
      '   - 服装：如 校服, 连衣裙, 西装, 和服, 卫衣, 泳装\n'
      '   - 配饰：如 眼镜, 耳机, 帽子, 耳环\n'
      '   - 姿态/动作：如 微笑, 挥手, 奔跑, 坐姿, 回头\n'
      '4. 角色名（确定认识时写）：如 初音未来, 哆啦A梦, 路飞\n'
      '5. 图中文字（OCR）：所有出现的文字逐条写出\n'
      '6. 主色调：如 蓝色调, 暖色调, 黑白\n'
      '\n'
      '规则：\n'
      '- 只输出标签，逗号分隔，不要序号、解释、换行\n'
      '- 每个标签尽量具体，如用"粉色连衣裙"而非"衣服"\n'
      '- 不确定的特征不要编造';

  List<ModelConfig> models = [];
  Set<String> excludedFolders = {};
  int tempShareDurationSec = 10;

  String? _customPrompt;
  bool debugEnabled = false;
  List<DebugLogEntry> failureLogs = [];

  /// 获取当前生效的提示词（自定义 > 默认）
  String get effectivePrompt =>
      (_customPrompt != null && _customPrompt!.trim().isNotEmpty)
          ? _customPrompt!
          : _defaultPrompt;

  /// 获取默认提示词（供 UI 重置用）
  String get defaultPrompt => _defaultPrompt;

  CloudEnhanceService() {
    models = [ModelConfig()];
  }

  // HTTP 取消支持
  http.Client? _activeClient;
  bool _httpCancelled = false;

  /// 取消正在进行的 HTTP 请求（扫描/解析停止时调用）
  void cancelHttpRequests() {
    _httpCancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  /// 开始新批次前重置取消标记
  void resetForNewBatch() {
    _httpCancelled = false;
  }

  bool get isEnabled => models.any((m) => m.isEnabled);

  /// 第一个可用模型的 apiKey（向后兼容）
  String get apiKey => models.isNotEmpty ? models.first.apiKey : '';
  String get apiBaseUrl => models.isNotEmpty ? models.first.apiBaseUrl : '';
  String get modelName => models.isNotEmpty ? models.first.modelName : '';

  List<ModelConfig> get enabledModels =>
      models.where((m) => m.isEnabled).toList();

  bool isFolderExcluded(String folderPath) => excludedFolders.contains(folderPath);

  /// 判断某张图片的**文件路径**是否位于被排除的文件夹中。
  /// [excludedFolders] 存的是文件夹绝对路径，而 MediaStore 返回的 folder
  /// 字段只是 BUCKET_DISPLAY_NAME（文件夹名），所以必须从文件路径截父目录来比。
  bool isPhotoExcluded(String photoPath) =>
      isPathInFolders(photoPath, excludedFolders);

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final modelsJson = prefs.getString(_keyModels);
    if (modelsJson != null && modelsJson.isNotEmpty) {
      try {
        final list = jsonDecode(modelsJson) as List<dynamic>;
        models = list
            .map((e) => ModelConfig.fromJson(e as Map<String, dynamic>))
            .toList();
        if (models.isEmpty) models = [ModelConfig()];
      } catch (_) {
        models = [_migrateLegacy(prefs)];
      }
    } else {
      // 迁移旧版单模型配置
      models = [_migrateLegacy(prefs)];
    }
    tempShareDurationSec = prefs.getInt(_keyTempShareDuration) ?? 10;
    final excluded = prefs.getStringList(_keyExcludedFolders) ?? [];
    excludedFolders = excluded.toSet();

    // 调试设置
    _customPrompt = prefs.getString(_keyCustomPrompt);
    debugEnabled = prefs.getBool(_keyDebugEnabled) ?? false;
    final logsJson = prefs.getString(_keyFailureLogs);
    if (logsJson != null && logsJson.isNotEmpty) {
      try {
        final list = jsonDecode(logsJson) as List<dynamic>;
        failureLogs = list
            .map((e) => DebugLogEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        failureLogs = [];
      }
    }
  }

  ModelConfig _migrateLegacy(SharedPreferences prefs) {
    final name = prefs.getString(_keyModelName) ?? AppConstants.cloudModel;
    final url = prefs.getString(_keyApiBaseUrl) ?? AppConstants.cloudApiBaseUrl;
    final key = prefs.getString(_keyApiKey) ?? AppConstants.cloudApiKey;
    return ModelConfig(modelName: name, apiBaseUrl: url, apiKey: key);
  }

  Future<void> _saveModels() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyModels,
        jsonEncode(models.map((m) => m.toJson()).toList()));
  }

  Future<void> _saveExcludedFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyExcludedFolders, excludedFolders.toList());
  }

  Future<void> addExcludedFolder(String folderPath) async {
    excludedFolders.add(folderPath);
    await _saveExcludedFolders();
  }

  Future<void> setTempShareDuration(int seconds) async {
    tempShareDurationSec = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTempShareDuration, seconds);
  }

  Future<void> setCustomPrompt(String? prompt) async {
    _customPrompt = (prompt != null && prompt.trim().isNotEmpty) ? prompt : null;
    final prefs = await SharedPreferences.getInstance();
    if (_customPrompt != null) {
      await prefs.setString(_keyCustomPrompt, _customPrompt!);
    } else {
      await prefs.remove(_keyCustomPrompt);
    }
  }

  Future<void> setDebugEnabled(bool enabled) async {
    debugEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDebugEnabled, enabled);
  }

  Future<void> addFailureLog(DebugLogEntry entry) async {
    failureLogs.insert(0, entry);
    if (failureLogs.length > _maxLogEntries) {
      failureLogs = failureLogs.sublist(0, _maxLogEntries);
    }
    await _saveFailureLogs();
  }

  Future<void> clearFailureLogs() async {
    failureLogs.clear();
    await _saveFailureLogs();
  }

  Future<void> _saveFailureLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyFailureLogs,
        jsonEncode(failureLogs.map((e) => e.toJson()).toList()));
  }

  Future<void> removeExcludedFolder(String folderPath) async {
    excludedFolders.remove(folderPath);
    await _saveExcludedFolders();
  }

  /// 添加一个空模型配置
  void addModel() {
    if (models.length >= maxModels) return;
    models.add(ModelConfig());
  }

  /// 移除指定索引的模型配置
  Future<void> removeModel(int index) async {
    if (models.length <= 1) return;
    models.removeAt(index);
    await _saveModels();
  }

  Future<void> setModelName(int index, String name) async {
    models[index].modelName = name.trim();
    await _saveModels();
  }

  Future<void> setApiBaseUrl(int index, String url) async {
    models[index].apiBaseUrl = url.trim();
    await _saveModels();
  }

  Future<void> setApiKey(int index, String key) async {
    models[index].apiKey = key.trim();
    await _saveModels();
  }

  Future<String?> _imageToBase64Url(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final originalSize = await file.length();
      Uint8List? compressed;
      try {
        compressed = await FlutterImageCompress.compressWithFile(
          imagePath,
          minWidth: 1024,
          minHeight: 1024,
          quality: 70,
          format: CompressFormat.jpeg,
        ).timeout(const Duration(seconds: 15));
      } on TimeoutException {
        LogService.instance.warning('CloudEnhance',
            '图片压缩超时 (15s): $imagePath, 原始 ${(originalSize / 1024).toStringAsFixed(1)} KB');
        return null;
      } catch (e) {
        LogService.instance.warning('CloudEnhance',
            '图片压缩失败: $imagePath, 错误: $e');
        return null;
      }

      if (compressed == null) {
        LogService.instance.warning('CloudEnhance',
            '图片压缩返回 null: $imagePath, 原始 ${(originalSize / 1024).toStringAsFixed(1)} KB');
        return null;
      }

      LogService.instance.debug('CloudEnhance',
          '图片压缩: ${(originalSize / 1024).toStringAsFixed(1)} KB -> ${(compressed.length / 1024).toStringAsFixed(1)} KB ($imagePath)');

      final base64 = base64Encode(compressed);
      return 'data:image/jpeg;base64,$base64';
    } catch (e) {
      LogService.instance.warning('CloudEnhance',
          '图片处理异常: $imagePath, 错误: $e');
      return null;
    }
  }

  /// 发送单张图片到云端分析，返回 {tags}
  /// [model] 可选，不传则使用第一个可用模型
  Future<Map<String, String>> analyzeImage(String imagePath,
      {ModelConfig? model}) async {
    final cfg = model ??
        (models.isNotEmpty
            ? models.first
            : ModelConfig());
    if (cfg.apiKey.isEmpty) {
      throw const CloudAnalyzeException('API Key 未配置，请在设置中填写');
    }
    if (cfg.apiBaseUrl.isEmpty) {
      throw const CloudAnalyzeException('API Base URL 未配置，请在设置中填写');
    }

    final imageUrl = await _imageToBase64Url(imagePath);
    if (imageUrl == null) {
      // 压缩失败多为瞬时 IO/超时，可重试
      throw const CloudAnalyzeException('图片压缩或编码失败', retryable: true);
    }

    // 每个请求使用独立的 http.Client，避免并发请求互相取消
    final client = http.Client();

    int? lastStatusCode;
    String? lastResponseBody;
    String? rawContent;

    try {
      if (_httpCancelled) throw const CloudAnalyzeException('已取消');
      final response = await client.post(
        Uri.parse(cfg.apiBaseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${cfg.apiKey}',
        },
        body: jsonEncode({
          'model': cfg.modelName,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {'url': imageUrl},
                },
                {
                  'type': 'text',
                  'text': effectivePrompt,
                },
              ],
            },
          ],
        }),
      ).timeout(const Duration(seconds: 30));

      lastStatusCode = response.statusCode;
      lastResponseBody = response.body;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final choices = data['choices'] as List?;
        final content = choices
            ?.map((c) => c['message']?['content'] as String?)
            .where((s) => s != null && s.isNotEmpty)
            .join('\n');
        if (content != null && content.isNotEmpty) {
          rawContent = content;
          final result = _parseResult(content);
          LogService.instance.info('CloudEnhance',
              'API 成功 [${cfg.modelName}]: ${imagePath.split('/').last}, 标签: ${result['tags']}');
          // 成功时也记录一条 debug 日志（方便查看返回内容）
          if (debugEnabled) {
            await addFailureLog(DebugLogEntry(
              timestamp: DateTime.now(),
              imagePath: imagePath,
              modelName: cfg.modelName,
              httpStatusCode: 200,
              responseBody: _truncate(lastResponseBody, 500),
              rawAIResponse: _truncate(rawContent!, 1000),
              parsedTags: result['tags'],
              errorMessage: '',
            ));
          }
          return result;
        }
        // 空内容通常是模型能力问题，重试无意义
        throw const CloudAnalyzeException('API 返回了空内容，可能是模型不支持图片分析');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw CloudAnalyzeException(
            '模型 ${cfg.modelName} API Key 无效或无权访问 (HTTP ${response.statusCode})',
            statusCode: response.statusCode);
      } else if (response.statusCode == 404) {
        throw const CloudAnalyzeException(
            'API 地址无效 (HTTP 404)，请检查 Base URL',
            statusCode: 404);
      } else {
        final body = response.body.length > 200
            ? '${response.body.substring(0, 200)}...'
            : response.body;
        // 429 限流与 5xx 服务端错误值得重试
        final code = response.statusCode;
        final retryable = code == 429 || code >= 500;
        throw CloudAnalyzeException(
            '模型 ${cfg.modelName} 请求失败 (HTTP $code): $body',
            retryable: retryable,
            statusCode: code);
      }
    } catch (e) {
      final CloudAnalyzeException err;
      if (e is CloudAnalyzeException) {
        err = e;
      } else if (e is TimeoutException) {
        err = const CloudAnalyzeException('请求超时 (30s)', retryable: true);
      } else {
        // SocketException / HandshakeException / ClientException 等网络层故障
        err = CloudAnalyzeException('网络请求异常: $e', retryable: true);
      }
      final msg = err.message;
      LogService.instance.error('CloudEnhance',
          'API 失败 [${cfg.modelName}]: ${imagePath.split('/').last}, $msg');
      if (debugEnabled) {
        await addFailureLog(DebugLogEntry(
          timestamp: DateTime.now(),
          imagePath: imagePath,
          modelName: cfg.modelName,
          httpStatusCode: lastStatusCode,
          responseBody: _truncate(lastResponseBody ?? '', 500),
          rawAIResponse: _truncate(rawContent ?? '', 1000),
          parsedTags: null,
          errorMessage: msg,
        ));
      }
      throw err;
    } finally {
      client.close();
    }
  }

  /// 重试退避间隔：第 1 次失败等 1s，第 2 次等 3s
  static const List<Duration> _retryBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  /// 带重试与模型回退的单张解析。
  ///
  /// 策略：先用 [model] 重试至多 2 次（1s / 3s 退避），仍失败则依次换其他
  /// 已启用模型各试一次。仅 [CloudAnalyzeException.retryable] 为真的错误
  /// 才重试；401/403/404 等配置错误直接失败，但仍会换模型（另一个模型的
  /// Key 可能是好的）。
  Future<Map<String, String>> analyzeImageWithRetry(String imagePath,
      {ModelConfig? model}) async {
    final primary = model ??
        (enabledModels.isNotEmpty ? enabledModels.first : ModelConfig());

    // 候选模型：主模型优先，其余已启用模型作为回退
    final candidates = <ModelConfig>[
      primary,
      ...enabledModels.where((m) => !identical(m, primary)),
    ];

    final fileName = imagePath.split('/').last;
    CloudAnalyzeException? lastError;

    for (int mi = 0; mi < candidates.length; mi++) {
      final cfg = candidates[mi];
      // 主模型重试 2 次，回退模型各只试 1 次
      final maxAttempts = mi == 0 ? _retryBackoff.length + 1 : 1;

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (_httpCancelled) {
          throw const CloudAnalyzeException('已取消');
        }
        try {
          return await analyzeImage(imagePath, model: cfg);
        } on CloudAnalyzeException catch (e) {
          lastError = e;
          if (e.message == '已取消') rethrow;

          final hasNextAttempt = e.retryable && attempt + 1 < maxAttempts;
          if (hasNextAttempt) {
            final wait = _retryBackoff[attempt];
            LogService.instance.warning(
                'CloudEnhance',
                '重试 ${attempt + 1}/${maxAttempts - 1} [${cfg.modelName}] '
                '$fileName，${wait.inSeconds}s 后: ${e.message}');
            await Future.delayed(wait);
            continue;
          }
          break; // 不可重试或已用尽本模型的机会 → 换下一个模型
        }
      }

      if (mi + 1 < candidates.length) {
        LogService.instance.warning('CloudEnhance',
            '模型回退 [${cfg.modelName}] → [${candidates[mi + 1].modelName}]: $fileName');
      }
    }

    throw lastError ?? const CloudAnalyzeException('解析失败');
  }

  String _truncate(String s, int maxLen) =>
      s.length <= maxLen ? s : '${s.substring(0, maxLen)}...';

  /// 解析模型回复，提取标签
  Map<String, String> _parseResult(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\n\r]+'), ' ')
        // 统一所有常见中文分隔符为半角逗号
        .replaceAll('，', ',')  // 全角逗号 U+FF0C
        .replaceAll('、', ',')  // 顿号 U+3001
        .replaceAll('；', ',')  // 全角分号 U+FF1B
        .replaceAll(';', ',')   // 半角分号
        .trim();
    final tags = cleaned
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length < 30)
        .join(', ');
    return {'tags': tags};
  }
}

/// 云端解析异常。[retryable] 标记该错误是否值得重试：
/// 网络超时、5xx、429 等瞬时故障可重试；
/// 401/403/404 属配置错误，重试只会浪费时间和额度。
class CloudAnalyzeException implements Exception {
  final String message;
  final bool retryable;
  final int? statusCode;

  const CloudAnalyzeException(this.message,
      {this.retryable = false, this.statusCode});

  @override
  String toString() => message;
}

/// 云端解析调试日志条目
class DebugLogEntry {
  final DateTime timestamp;
  final String imagePath;
  final String modelName;
  final int? httpStatusCode;
  final String? responseBody;
  final String? rawAIResponse;
  final String? parsedTags;
  final String errorMessage;

  DebugLogEntry({
    required this.timestamp,
    required this.imagePath,
    required this.modelName,
    this.httpStatusCode,
    this.responseBody,
    this.rawAIResponse,
    this.parsedTags,
    required this.errorMessage,
  });

  bool get isSuccess => errorMessage.isEmpty;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.millisecondsSinceEpoch,
        'imagePath': imagePath,
        'modelName': modelName,
        'httpStatusCode': httpStatusCode,
        'responseBody': responseBody,
        'rawAIResponse': rawAIResponse,
        'parsedTags': parsedTags,
        'errorMessage': errorMessage,
      };

  factory DebugLogEntry.fromJson(Map<String, dynamic> json) => DebugLogEntry(
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int? ?? 0),
        imagePath: json['imagePath'] as String? ?? '',
        modelName: json['modelName'] as String? ?? '',
        httpStatusCode: json['httpStatusCode'] as int?,
        responseBody: json['responseBody'] as String?,
        rawAIResponse: json['rawAIResponse'] as String?,
        parsedTags: json['parsedTags'] as String?,
        errorMessage: json['errorMessage'] as String? ?? '',
      );
}
