import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/photo.dart';
import '../models/database_helper.dart';
import 'cloud_enhance.dart';
import 'notification_service.dart';

enum ScanState { idle, scanning, completed, error }

class ScanProgress {
  final int current;
  final int total;
  final String currentPath;
  const ScanProgress(this.current, this.total, this.currentPath);
}

class PhotoScanner {
  static const _channel = MethodChannel('com.smartalbum/mediastore');

  final DatabaseHelper _db = DatabaseHelper.instance;
  final CloudEnhanceService _cloudService;

  final _onProgress = ValueNotifier<ScanProgress?>(
      const ScanProgress(0, 0, ''));
  ValueNotifier<ScanProgress?> get onProgress => _onProgress;

  final _state = ValueNotifier<ScanState>(ScanState.idle);
  ValueNotifier<ScanState> get state => _state;

  PhotoScanner(this._cloudService);

  bool _scanning = false;
  bool _cancelled = false;
  DateTime _lastScanTime = DateTime(2000);

  void cancel() {
    _cancelled = true;
    debugPrint('[PhotoScanner] Cancel requested');
  }

  /// 通过原生 MediaStore ContentResolver 直接查询（毫秒级）
  Future<List<Map<String, dynamic>>> _nativeQuery({String? folder, bool incremental = true}) async {
    final args = <String, dynamic>{};
    if (incremental) {
      final existing = await _db.getAllPhotos();
      if (existing.isNotEmpty) {
        final maxTs = existing.map((p) => p.timestamp).reduce((a, b) => a > b ? a : b);
        args['since'] = maxTs;
      }
    }
    if (folder != null && folder.isNotEmpty) {
      args['folder'] = folder;
    }
    final json = await _channel.invokeMethod<String>('queryImages', args);
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  Future<int> scanPhotos() async {
    if (_scanning) return 0;
    if (DateTime.now().difference(_lastScanTime) < const Duration(seconds: 3)) {
      return 0;
    }
    _scanning = true;
    _cancelled = false;
    _lastScanTime = DateTime.now();
    _state.value = ScanState.scanning;
    _onProgress.value = const ScanProgress(0, 0, '');

    try {
      final images = await _nativeQuery(incremental: false);
      final result = await _processImages(images);
      final count = result.count;
      // 全量扫描后清理已不存在的文件记录
      final currentPaths = images.map((img) => img['path'] as String? ?? '').toSet();
      final dbPhotos = await _db.getAllPhotos();
      for (final p in dbPhotos) {
        if (!currentPaths.contains(p.path)) {
          await _db.deletePhoto(p.id!);
        }
      }
      _state.value = ScanState.completed;
      _scanning = false;
      return count;
    } catch (e) {
      debugPrint('[PhotoScanner] Scan error: $e');
      _state.value = ScanState.error;
      _scanning = false;
      return 0;
    }
  }

  Future<int> scanFolder(String folderName) async {
    if (_scanning) return 0;
    if (DateTime.now().difference(_lastScanTime) < const Duration(seconds: 3)) {
      return 0;
    }
    _scanning = true;
    _cancelled = false;
    _lastScanTime = DateTime.now();
    _state.value = ScanState.scanning;

    try {
      final images = await _nativeQuery(folder: folderName);
      final result = await _processImages(images);
      final count = result.count;
      _state.value = ScanState.completed;
      _scanning = false;
      return count;
    } catch (e) {
      debugPrint('[PhotoScanner] Scan folder error: $e');
      _state.value = ScanState.error;
      _scanning = false;
      return 0;
    }
  }

  Future<({int count, Set<String> movedPaths})> _processImages(List<Map<String, dynamic>> images) async {
    int processedCount = 0;
    final total = images.length;
    _onProgress.value = ScanProgress(0, total, '扫描中...');

    final existingPhotos = await _db.getAllPhotos();
    final existingPaths = existingPhotos.map((p) => p.path).toSet();
    final byFingerprint = <String, Photo>{};
    for (final p in existingPhotos) {
      final name = p.path.split('/').last;
      byFingerprint['${name}_${p.hash}'] = p;
    }

    final movedPaths = <String>{};
    final notify = NotificationService();
    int lastNotifyAt = 0;
    final pendingCloud = <Map<String, dynamic>>[];

    for (int i = 0; i < images.length; i++) {
      final img = images[i];
      final path = img['path'] as String?;
      if (path == null) continue;

      _onProgress.value = ScanProgress(i + 1, total, path);

      if (i - lastNotifyAt >= 50 || i == total - 1) {
        lastNotifyAt = i;
        notify.showProgress(
          id: 1,
          title: '扫描相册中',
          body: '${i + 1}/$total',
          progress: i + 1,
          maxProgress: total,
        );
      }

      if (existingPaths.contains(path)) continue;

      // 尝试通过文件名+大小匹配已移动的文件
      final fileName = path.split('/').last;
      final size = '${img['size'] ?? 0}';
      final fingerprint = '${fileName}_$size';
      final matched = byFingerprint[fingerprint];

      if (matched != null && matched.path != path) {
        await _db.updatePhoto(matched.copyWith(path: path));
        movedPaths.add(matched.path);
        processedCount++;
        continue;
      }

      final photo = Photo(
        path: path,
        timestamp: img['timestamp'] as int? ?? 0,
        width: img['width'] as int? ?? 0,
        height: img['height'] as int? ?? 0,
        hash: size,
      );

      final photoId = await _db.insertPhoto(photo);
      if (photoId > 0) {
        final folderName = img['folder'] as String? ?? '其他';
        await _db.updatePhoto(photo.copyWith(tags: folderName));
        pendingCloud.add({'id': photoId, 'path': path});
        processedCount++;
      }
    }

    // 并发云端解析
    if (_cloudService.isEnabled && pendingCloud.isNotEmpty) {
      const concurrency = 3;
      for (int i = 0; i < pendingCloud.length && !_cancelled; i += concurrency) {
        final batch = pendingCloud.skip(i).take(concurrency).toList();
        await Future.wait(batch.map((p) =>
            _processCloud((p['id'] as int), (p['path'] as String))));
      }
    }

    if (movedPaths.isNotEmpty) {
      debugPrint('[PhotoScanner] Moved files matched: ${movedPaths.length}');
    }

    notify.showCompleted(
      id: 1,
      title: '扫描完成',
      body: '新索引 $processedCount 张图片',
    );

    return (count: processedCount, movedPaths: movedPaths);
  }

  /// 仅云端标签+文字识别
  Future<void> _processCloud(int photoId, String filePath) async {
    if (!_cloudService.isEnabled) return;
    final photo = await _db.getPhotoById(photoId);
    if (photo == null) return;

    try {
      final cloudResult = await _cloudService.analyzeImage(filePath);
      final cloudTags = cloudResult['tags'] ?? '';
      final existing = photo.tags ?? '';

      final searchTags = [
        if (existing.isNotEmpty) existing,
        if (cloudTags.isNotEmpty) cloudTags,
      ].where((s) => s.isNotEmpty).join(', ');

      await _db.updatePhoto(photo.copyWith(tags: searchTags));
    } catch (e) {
      debugPrint('[PhotoScanner] Cloud error for id=$photoId: $e');
    }
  }

  Future<String> cloudAnalyzeAll() async {
    if (!_cloudService.isEnabled) return '请先在设置中启用云端解析';
    final photos = await _db.getAllPhotos();
    return _cloudAnalyzePhotos(photos, '云端解析中');
  }

  Future<String> cloudAnalyzePhotos(List<Photo> photos) async {
    if (!_cloudService.isEnabled) return '请先在设置中启用云端解析';
    return _cloudAnalyzePhotos(photos, '解析文件夹中');
  }

  Future<String> _cloudAnalyzePhotos(List<Photo> photos, String title) async {
    if (_scanning) return '正在解析中，请等待当前任务完成';
    if (photos.isEmpty) return '没有需要解析的图片';

    _scanning = true;
    _cancelled = false;
    _state.value = ScanState.scanning;
    final notify = NotificationService();
    final valid = photos.where((p) => p.id != null).toList();
    _onProgress.value = ScanProgress(0, valid.length, '准备上传...');
    int success = 0;
    int failed = 0;
    String? lastError;
    const concurrency = 3;

    final models = _cloudService.enabledModels;
    if (models.isEmpty) {
      _state.value = ScanState.completed;
      _scanning = false;
      return '请先在设置中至少配置一个模型';
    }

    // 立即显示初始通知
    final modelNames = models.map((m) => m.modelName).join(', ');
    await notify.showProgress(
      id: 0,
      title: title,
      body: '准备上传 ${valid.length} 张图片...',
      progress: 0,
      maxProgress: valid.length,
      channelId: NotificationService.cloudChannelId,
      channelName: '云端解析',
    );

    // 轮询分配图片到各模型
    final modelQueues = List.generate(models.length, (_) => <Photo>[]);
    for (int i = 0; i < valid.length; i++) {
      modelQueues[i % models.length].add(valid[i]);
    }

    int lastNotifyMs = 0;

    void updateProgress(Photo photo) {
      final total = success + failed;
      _onProgress.value = ScanProgress(total, valid.length, photo.path);

      // 节流：最多每 300ms 更新一次通知，或最后一张必更新
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastNotifyMs < 300 && total < valid.length) return;
      lastNotifyMs = now;

      notify.showProgress(
        id: 0,
        title: '$title [$modelNames]',
        body: '$total/${valid.length} ${photo.path.split('/').last}',
        progress: total,
        maxProgress: valid.length,
        channelId: NotificationService.cloudChannelId,
        channelName: '云端解析',
      );
    }

    // 所有模型并行处理
    await Future.wait(modelQueues.asMap().entries.map((entry) async {
      final queue = entry.value;
      final model = models[entry.key];

      for (int i = 0; i < queue.length && !_cancelled; i += concurrency) {
        final batch = queue.skip(i).take(concurrency).toList();
        final results = await Future.wait(batch.map((p) async {
          try {
            final result =
                await _cloudService.analyzeImage(p.path, model: model);
            return (p, result, null);
          } catch (e) {
            return (p, null, e.toString());
          }
        }));

        for (final (photo, result, error) in results) {
          if (error != null) {
            failed++;
            lastError = error.replaceFirst(RegExp(r'^Exception: '), '');
            continue;
          }
          if (result == null) continue;

          final cloudTags = result['tags'] ?? '';
          final existingTags = photo.tags ?? '';
          final searchTags = [
            if (existingTags.isNotEmpty) existingTags,
            if (cloudTags.isNotEmpty) cloudTags,
          ].where((s) => s.isNotEmpty).join(', ');
          await _db.updatePhoto(photo.copyWith(tags: searchTags));
          success++;

          updateProgress(photo);
        }
      }
    }));

    final body = failed == 0
        ? '解析完成，成功 $success 张'
        : success > 0
            ? '解析完成，成功 $success 张，失败 $failed 张'
            : '解析失败${lastError != null ? "：$lastError" : ""}';
    await notify.showCompleted(
      id: 0,
      title: '${title}完成',
      body: body,
      channelId: NotificationService.cloudChannelId,
      channelName: '云端解析',
    );

    _state.value = ScanState.completed;
    _scanning = false;
    return body;
  }

  void dispose() {
    _onProgress.dispose();
    _state.dispose();
  }

  Future<bool> openFolder(String folderPath) async {
    try {
      await _channel.invokeMethod('openFolder', {'path': folderPath});
      return true;
    } catch (e) {
      debugPrint('[PhotoScanner] openFolder error: $e');
      return false;
    }
  }

  /// 将新文件注册到系统 MediaStore，返回 content URI
  Future<String?> scanFile(String filePath) async {
    try {
      final uri = await _channel.invokeMethod<String>('scanFile', {'path': filePath});
      return uri;
    } catch (e) {
      debugPrint('[PhotoScanner] scanFile error: $e');
      return null;
    }
  }

  /// 通过 content URI 删除文件（同时清除 MediaStore 记录 + 物理文件）
  Future<bool> deleteByUri(String uri) async {
    try {
      final ok = await _channel.invokeMethod<bool>('deleteByUri', {'uri': uri});
      return ok ?? false;
    } catch (e) {
      debugPrint('[PhotoScanner] deleteByUri error: $e');
      return false;
    }
  }

  /// 从系统 MediaStore 中移除文件记录（文件已从磁盘删除后调用）
  Future<void> removeFromMediaStore(String filePath) async {
    try {
      await _channel.invokeMethod('removeFromMediaStore', {'path': filePath});
    } catch (e) {
      debugPrint('[PhotoScanner] removeFromMediaStore error: $e');
    }
  }
}
