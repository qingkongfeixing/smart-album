import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'photo.dart';
import '../utils/constants.dart';

class DatabaseHelper {
  static DatabaseHelper? _instance;
  late Database _db;

  DatabaseHelper._();

  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._();
    return _instance!;
  }

  Database get db => _db;

  Future<void> init(String dbPath) async {
    _db = await openDatabase(
      p.join(dbPath, AppConstants.dbName),
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT UNIQUE NOT NULL,
        timestamp INTEGER NOT NULL,
        width INTEGER NOT NULL,
        height INTEGER NOT NULL,
        hash TEXT NOT NULL,
        ocr_text TEXT,
        tags TEXT,
        cloud_data TEXT
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_photos_tags ON photos(tags)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('DROP TABLE IF EXISTS photos_fts');
      } catch (_) {}
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_photos_tags ON photos(tags)');
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE photos ADD COLUMN cloud_data TEXT');
      } catch (_) {}
    }
  }

  // ── 图片 CRUD ──────────────────────────────────────────

  Future<int> insertPhoto(Photo photo) async {
    return await _db.insert('photos', photo.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> updatePhoto(Photo photo) async {
    if (photo.id == null) return;
    await _db.update('photos', photo.toMap(),
        where: 'id = ?', whereArgs: [photo.id]);
  }

  Future<Photo?> getPhotoByPath(String path) async {
    final rows = await _db.query('photos',
        where: 'path = ?', whereArgs: [path], limit: 1);
    if (rows.isEmpty) return null;
    return Photo.fromMap(rows.first);
  }

  Future<Photo?> getPhotoById(int id) async {
    final rows = await _db.query('photos',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Photo.fromMap(rows.first);
  }

  Future<List<Photo>> getAllPhotos() async {
    final rows =
        await _db.query('photos', orderBy: 'timestamp DESC');
    return rows.map(Photo.fromMap).toList();
  }

  Future<List<Photo>> getPhotosByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final placeholders = ids.map((_) => '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT * FROM photos WHERE id IN ($placeholders)',
      ids,
    );
    final map = <int, Photo>{};
    for (final row in rows) {
      final photo = Photo.fromMap(row);
      if (photo.id != null) map[photo.id!] = photo;
    }
    return ids.map((id) => map[id]).whereType<Photo>().toList();
  }

  Future<bool> photoExists(String path) async {
    final result = await _db.query('photos',
        columns: ['id'],
        where: 'path = ?',
        whereArgs: [path],
        limit: 1);
    return result.isNotEmpty;
  }

  Future<int> getPhotoCount() async {
    final result =
        await _db.rawQuery('SELECT COUNT(*) as count FROM photos');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ── 文件哈希去重 ────────────────────────────────────────

  // ── 标签聚合 ──────────────────────────────────────────

  /// 返回所有不重复标签及其出现次数，按次数降序
  Future<Map<String, int>> getAllTags() async {
    final rows = await _db.rawQuery(
      'SELECT tags FROM photos WHERE tags IS NOT NULL AND tags != \'\'',
    );
    final counts = <String, int>{};
    for (final row in rows) {
      final tagsStr = row['tags'] as String?;
      if (tagsStr == null || tagsStr.isEmpty) continue;
      for (final raw in tagsStr.split(',')) {
        final tag = raw.trim();
        if (tag.isNotEmpty && tag.length < 30) {
          counts[tag] = (counts[tag] ?? 0) + 1;
        }
      }
    }
    // 按次数降序排列
    final sorted = Map<String, int>.fromEntries(
      counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return sorted;
  }

  // ── 关键词搜索 (LIKE) ──────────────────────────────────
  // "。" 分隔多组查询，组间 OR；组内空格/逗号(，,) 分隔，组内 AND
  // "猫，橘。奶龙，黄" → (猫 AND 橘) OR (奶龙 AND 黄)
  // "黄色 奶龙"       → 黄色 AND 奶龙（单组，向后兼容）

  Future<List<int>> searchByKeyword(String query) async {
    // 先按 。/。 拆分组（组间 OR）
    final groups = query
        .split(RegExp(r'[。]'))
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty)
        .toList();
    if (groups.isEmpty) return [];

    final groupConditions = <String>[];
    final args = <String>[];

    for (final group in groups) {
      // 组内按空格/逗号拆分（组内 AND）
      final words = group
          .split(RegExp(r'[\s，,]+'))
          .map((w) => w.trim())
          .where((w) => w.isNotEmpty)
          .toList();
      if (words.isEmpty) continue;

      final wordConds = <String>[];
      for (final word in words) {
        wordConds.add('(tags LIKE ? OR ocr_text LIKE ?)');
        args.add('%$word%');
        args.add('%$word%');
      }
      groupConditions.add('(${wordConds.join(' AND ')})');
    }

    if (groupConditions.isEmpty) return [];

    final where = groupConditions.join(' OR ');

    final rows = await _db.rawQuery('''
      SELECT id FROM photos
      WHERE $where
      ORDER BY timestamp DESC
      LIMIT ?
    ''', [...args, AppConstants.defaultTopK]);

    return rows.map<int>((r) => r['id'] as int).toList();
  }

  // ── 清理 ─────────────────────────────────────────────

  Future<void> deletePhoto(int id) async {
    await _db.delete('photos', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    await _db.close();
  }
}
