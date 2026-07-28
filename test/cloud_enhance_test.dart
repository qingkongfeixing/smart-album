import 'package:flutter_test/flutter_test.dart';
import 'package:smart_album/services/cloud_enhance.dart';

void main() {
  group('isPhotoExcluded', () {
    late CloudEnhanceService svc;

    setUp(() {
      svc = CloudEnhanceService();
      svc.excludedFolders = {'/storage/emulated/0/Pictures/WeChat'};
    });

    test('排除文件夹下的图片被命中', () {
      expect(
        svc.isPhotoExcluded('/storage/emulated/0/Pictures/WeChat/a.jpg'),
        isTrue,
      );
    });

    test('其他文件夹不受影响', () {
      expect(
        svc.isPhotoExcluded('/storage/emulated/0/DCIM/Camera/a.jpg'),
        isFalse,
      );
    });

    test('不匹配前缀相同的兄弟文件夹（WeChatBackup）', () {
      expect(
        svc.isPhotoExcluded('/storage/emulated/0/Pictures/WeChatBackup/a.jpg'),
        isFalse,
        reason: '前缀相似但不是同一文件夹，不应被排除',
      );
    });

    test('不匹配排除文件夹的子目录', () {
      expect(
        svc.isPhotoExcluded('/storage/emulated/0/Pictures/WeChat/sub/a.jpg'),
        isFalse,
        reason: '排除只作用于直接父目录，与 gallery 的文件夹聚合口径一致',
      );
    });

    test('排除集合为空时一律不命中', () {
      svc.excludedFolders = {};
      expect(svc.isPhotoExcluded('/any/path/a.jpg'), isFalse);
    });

    test('无斜杠的路径不崩', () {
      expect(svc.isPhotoExcluded('a.jpg'), isFalse);
    });
  });

  group('CloudAnalyzeException 可重试标记', () {
    test('默认不可重试', () {
      const e = CloudAnalyzeException('boom');
      expect(e.retryable, isFalse);
    });

    test('toString 返回纯消息，无 Exception: 前缀', () {
      const e = CloudAnalyzeException('API Key 无效');
      expect(e.toString(), 'API Key 无效');
    });

    test('显式标记可重试', () {
      const e = CloudAnalyzeException('超时', retryable: true);
      expect(e.retryable, isTrue);
    });
  });
}
