import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

enum LogLevel { debug, info, warning, error }

extension LogLevelExt on LogLevel {
  String get label {
    switch (this) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARNING';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  int get severity {
    switch (this) {
      case LogLevel.debug:
        return 0;
      case LogLevel.info:
        return 1;
      case LogLevel.warning:
        return 2;
      case LogLevel.error:
        return 3;
    }
  }
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String module;
  final String message;
  final String? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.module,
    required this.message,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.millisecondsSinceEpoch,
        'level': level.index,
        'module': module,
        'message': message,
        'stackTrace': stackTrace ?? '',
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int? ?? 0),
        level: LogLevel.values[json['level'] as int? ?? 0],
        module: json['module'] as String? ?? '',
        message: json['message'] as String? ?? '',
        stackTrace: (json['stackTrace'] as String?)?.isEmpty == true
            ? null
            : json['stackTrace'] as String?,
      );

  String format() {
    final ts =
        '${timestamp.year.toString().padLeft(4, '0')}-'
        '${timestamp.month.toString().padLeft(2, '0')}-'
        '${timestamp.day.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
    final st = stackTrace != null ? '\n$stackTrace' : '';
    return '$ts [${level.label}] $module: $message$st';
  }
}

class LogService {
  static final LogService instance = LogService._();
  LogService._();

  bool _initialized = false;
  bool _enabled = true;
  String _logDir = '';
  final List<LogEntry> _buffer = [];
  int _pendingCount = 0;
  Timer? _flushTimer;
  File? _currentFile;
  String _currentDate = '';
  IOSink? _sink;

  static const int _maxBufferSize = 500;
  static const int _batchFlushSize = 10;
  static const int _maxRetentionDays = 7;

  // 原有的 debugPrint 引用
  DebugPrintCallback? _originalDebugPrint;

  bool get enabled => _enabled;

  List<LogEntry> get entries => List.unmodifiable(_buffer);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final appDir = await getApplicationDocumentsDirectory();
    _logDir = '${appDir.path}/logs';
    await Directory(_logDir).create(recursive: true);
    await _rotateLogs();

    // 加载启用状态（使用简单文件标记）
    final markerFile = File('$_logDir/.disabled');
    _enabled = !await markerFile.exists();

    // 全局错误捕获
    FlutterError.onError = (details) {
      error('Flutter', details.exceptionAsString(),
          stackTrace: details.stack?.toString());
    };

    PlatformDispatcher.instance.onError = (exception, stack) {
      error('Platform', exception.toString(), stackTrace: stack.toString());
      return true;
    };

    // 重定向 debugPrint
    _originalDebugPrint = debugPrint;
    debugPrint = _debugPrintRedirect;

    // 定期 flush
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) => _flush());
  }

  void _debugPrintRedirect(String? message, {int? wrapWidth}) {
    _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
    if (message != null && message.isNotEmpty) {
      debug('Flutter', message.trimRight());
    }
  }

  void setEnabled(bool value) async {
    _enabled = value;
    final markerFile = File('$_logDir/.disabled');
    if (value) {
      if (await markerFile.exists()) await markerFile.delete();
    } else {
      if (!await markerFile.exists()) await markerFile.create();
    }
  }

  void debug(String module, String message, {String? stackTrace}) =>
      _log(LogLevel.debug, module, message, stackTrace: stackTrace);

  void info(String module, String message, {String? stackTrace}) =>
      _log(LogLevel.info, module, message, stackTrace: stackTrace);

  void warning(String module, String message, {String? stackTrace}) =>
      _log(LogLevel.warning, module, message, stackTrace: stackTrace);

  void error(String module, String message, {String? stackTrace}) =>
      _log(LogLevel.error, module, message, stackTrace: stackTrace);

  void _log(LogLevel level, String module, String message,
      {String? stackTrace}) {
    if (!_enabled) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      module: module,
      message: message,
      stackTrace: stackTrace,
    );

    _buffer.add(entry);
    if (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }

    _pendingCount++;

    if (level == LogLevel.error) {
      _flush();
    } else if (_pendingCount >= _batchFlushSize) {
      _flush();
    }
  }

  Future<void> _flush() async {
    if (_pendingCount == 0) return;
    final toWrite = _buffer.sublist(_buffer.length - _pendingCount);
    _pendingCount = 0;

    try {
      await _ensureSink();
      for (final entry in toWrite) {
        _sink?.writeln(entry.format());
      }
      await _sink?.flush();
    } catch (_) {
      // 写入失败静默忽略，避免日志系统本身引发崩溃
    }
  }

  Future<void> _ensureSink() async {
    final today =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
    if (_sink != null && _currentDate == today) return;

    await _sink?.flush();
    await _sink?.close();
    _currentDate = today;
    _currentFile = File('$_logDir/app_$today.log');
    _sink = _currentFile!.openWrite(mode: FileMode.append);
  }

  /// 日志轮转：保留最近 7 天
  Future<void> _rotateLogs() async {
    try {
      final dir = Directory(_logDir);
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(Duration(days: _maxRetentionDays));
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.log')) {
          final name = entity.uri.pathSegments.last;
          final match = RegExp(r'^app_(\d{4}-\d{2}-\d{2})\.log$').firstMatch(name);
          if (match != null) {
            final date = DateTime.tryParse(match.group(1)!);
            if (date != null && date.isBefore(cutoff)) {
              await entity.delete();
            }
          }
        }
      }
    } catch (_) {}
  }

  /// 导出日志为文本文件
  Future<File> exportLogs() async {
    await _flush();
    try {
      final dir = Directory.systemTemp;
      final file = File(
          '${dir.path}/app_logs_${DateTime.now().millisecondsSinceEpoch}.txt');
      final buf = StringBuffer();
      buf.writeln('=== 随搜相册 应用日志 ===');
      buf.writeln('导出时间: ${DateTime.now().toString().substring(0, 19)}');
      buf.writeln('共 ${_buffer.length} 条记录');
      buf.writeln('');
      for (final entry in _buffer) {
        buf.writeln(entry.format());
      }
      await file.writeAsString(buf.toString());
      return file;
    } catch (e) {
      rethrow;
    }
  }

  /// 分享日志文件
  Future<void> shareLogs() async {
    final file = await exportLogs();
    await Share.shareXFiles([XFile(file.path)], text: '随搜相册应用日志');
  }

  /// 清空所有日志
  Future<void> clearAllLogs() async {
    _buffer.clear();
    _pendingCount = 0;
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    try {
      if (_currentFile != null && await _currentFile!.exists()) {
        await _currentFile!.delete();
      }
      // 同时清理所有日志文件
      final dir = Directory(_logDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.log')) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
    _currentDate = '';
    _currentFile = null;
  }

  /// 释放资源
  Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush();
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    if (_originalDebugPrint != null) {
      debugPrint = _originalDebugPrint!;
    }
  }
}
