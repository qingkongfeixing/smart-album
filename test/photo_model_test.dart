import 'package:flutter_test/flutter_test.dart';
import 'package:smart_album/models/photo.dart';

void main() {
  group('isPathInFolders（DB 层与 service 层共用的排除判断）', () {
    const folders = {'/sd/Pictures/WeChat', '/sd/DCIM/Screenshots'};

    test('命中直接父目录', () {
      expect(isPathInFolders('/sd/Pictures/WeChat/a.jpg', folders), isTrue);
      expect(isPathInFolders('/sd/DCIM/Screenshots/b.png', folders), isTrue);
    });

    test('不命中其他目录', () {
      expect(isPathInFolders('/sd/DCIM/Camera/a.jpg', folders), isFalse);
    });

    test('不命中前缀相似的兄弟目录', () {
      expect(
        isPathInFolders('/sd/Pictures/WeChatBackup/a.jpg', folders),
        isFalse,
      );
    });

    test('不命中被排除目录的子目录', () {
      expect(
        isPathInFolders('/sd/Pictures/WeChat/sub/a.jpg', folders),
        isFalse,
      );
    });

    test('空集合恒为 false', () {
      expect(isPathInFolders('/sd/Pictures/WeChat/a.jpg', {}), isFalse);
    });

    test('无斜杠路径不抛异常', () {
      expect(isPathInFolders('a.jpg', folders), isFalse);
    });
  });

  group('Photo file_size 字段（v4 前叫 hash）', () {
    test('toMap 写 file_size，不再写 hash', () {
      const p = Photo(
        path: '/dcim/a.jpg',
        timestamp: 100,
        width: 10,
        height: 20,
        fileSize: '2048',
      );
      final m = p.toMap();
      expect(m['file_size'], '2048');
      expect(m.containsKey('hash'), isFalse);
    });

    test('fromMap 读 file_size', () {
      final p = Photo.fromMap({
        'id': 1,
        'path': '/dcim/a.jpg',
        'timestamp': 100,
        'width': 10,
        'height': 20,
        'file_size': '2048',
        'ocr_text': null,
        'tags': '猫',
        'cloud_data': null,
      });
      expect(p.fileSize, '2048');
      expect(p.tags, '猫');
    });

    test('fromMap 兼容仍带旧 hash 列的行', () {
      final p = Photo.fromMap({
        'id': 1,
        'path': '/dcim/a.jpg',
        'timestamp': 100,
        'width': 10,
        'height': 20,
        'hash': '4096',
      });
      expect(p.fileSize, '4096');
    });

    test('两列都缺时不抛异常，回落为空串', () {
      final p = Photo.fromMap({
        'id': 1,
        'path': '/dcim/a.jpg',
        'timestamp': 100,
        'width': 10,
        'height': 20,
      });
      expect(p.fileSize, '');
    });

    test('copyWith 保留 fileSize', () {
      const p = Photo(
        path: '/dcim/a.jpg',
        timestamp: 100,
        width: 10,
        height: 20,
        fileSize: '2048',
      );
      expect(p.copyWith(tags: '猫').fileSize, '2048');
      expect(p.copyWith(fileSize: '99').fileSize, '99');
    });
  });
}
