/// 判断 [photoPath] 的**直接父目录**是否在 [folders] 中。
///
/// 子目录不算命中：`/a/b/c.jpg` 的父目录是 `/a/b`，若 [folders] 只含 `/a`
/// 则返回 false。这与 GalleryScreen 按直接父目录聚合文件夹的口径一致。
///
/// 放在 model 层是为了让 DatabaseHelper 和 CloudEnhanceService 共用同一实现。
bool isPathInFolders(String photoPath, Set<String> folders) {
  if (folders.isEmpty) return false;
  final i = photoPath.lastIndexOf('/');
  if (i <= 0) return false;
  return folders.contains(photoPath.substring(0, i));
}

/// 图片实体类
class Photo {
  final int? id;
  final String path;
  final int timestamp;
  final int width;
  final int height;

  /// 文件字节大小（字符串形式）。与文件名组合成指纹
  /// `文件名_大小`，用于在扫描时识别「被移动到别处的同一文件」，
  /// 从而保留其已有标签而不重新解析。
  /// 注意：不是内容哈希，历史上曾用 `hash` 列名存放该值。
  final String fileSize;

  final String? ocrText;
  final String? tags;
  final String? cloudData;

  const Photo({
    this.id,
    required this.path,
    required this.timestamp,
    required this.width,
    required this.height,
    required this.fileSize,
    this.ocrText,
    this.tags,
    this.cloudData,
  });

  Photo copyWith({
    int? id,
    String? path,
    int? timestamp,
    int? width,
    int? height,
    String? fileSize,
    String? ocrText,
    String? tags,
    String? cloudData,
  }) {
    return Photo(
      id: id ?? this.id,
      path: path ?? this.path,
      timestamp: timestamp ?? this.timestamp,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSize: fileSize ?? this.fileSize,
      ocrText: ocrText ?? this.ocrText,
      tags: tags ?? this.tags,
      cloudData: cloudData ?? this.cloudData,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'path': path,
      'timestamp': timestamp,
      'width': width,
      'height': height,
      'file_size': fileSize,
      'ocr_text': ocrText,
      'tags': tags,
      'cloud_data': cloudData,
    };
  }

  factory Photo.fromMap(Map<String, dynamic> map) {
    return Photo(
      id: map['id'] as int?,
      path: map['path'] as String,
      timestamp: map['timestamp'] as int,
      width: map['width'] as int,
      height: map['height'] as int,
      // v4 起使用 file_size；兼容仍可能读到旧 hash 列的场景
      fileSize: (map['file_size'] ?? map['hash'] ?? '') as String,
      ocrText: map['ocr_text'] as String?,
      tags: map['tags'] as String?,
      cloudData: map['cloud_data'] as String?,
    );
  }
}

/// 搜索结果条目
class SearchResult {
  final Photo photo;
  final double similarityScore;
  final double keywordScore;
  final double combinedScore;

  const SearchResult({
    required this.photo,
    required this.similarityScore,
    required this.keywordScore,
    required this.combinedScore,
  });
}
