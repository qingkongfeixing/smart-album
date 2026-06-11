/// 图片实体类
class Photo {
  final int? id;
  final String path;
  final int timestamp;
  final int width;
  final int height;
  final String hash;
  final String? ocrText;
  final String? tags;
  final String? cloudData;

  const Photo({
    this.id,
    required this.path,
    required this.timestamp,
    required this.width,
    required this.height,
    required this.hash,
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
    String? hash,
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
      hash: hash ?? this.hash,
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
      'hash': hash,
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
      hash: map['hash'] as String,
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
