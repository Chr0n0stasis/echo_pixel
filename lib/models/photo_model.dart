class Photo {
  final String id;
  final String path;
  final String? title;
  final String? description;
  final DateTime dateTime;
  final String? location;
  final List<String> tags;
  final bool isFavorite;
  final bool isSynced;

  Photo({
    required this.id,
    required this.path,
    this.title,
    this.description,
    required this.dateTime,
    this.location,
    this.tags = const [],
    this.isFavorite = false,
    this.isSynced = false,
  });

  Photo copyWith({
    String? path,
    String? title,
    String? description,
    DateTime? dateTime,
    String? location,
    List<String>? tags,
    bool? isFavorite,
    bool? isSynced,
  }) {
    return Photo(
      id: id,
      path: path ?? this.path,
      title: title ?? this.title,
      description: description ?? this.description,
      dateTime: dateTime ?? this.dateTime,
      location: location ?? this.location,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'title': title,
      'description': description,
      'dateTime': dateTime.toIso8601String(),
      'location': location,
      'tags': tags,
      'isFavorite': isFavorite,
      'isSynced': isSynced,
    };
  }

  factory Photo.fromJson(Map<String, dynamic> json) {
    return Photo(
      id: json['id'],
      path: json['path'],
      title: json['title'],
      description: json['description'],
      dateTime: DateTime.parse(json['dateTime']),
      location: json['location'],
      tags: List<String>.from(json['tags'] ?? []),
      isFavorite: json['isFavorite'] ?? false,
      isSynced: json['isSynced'] ?? false,
    );
  }
}

/// 相册类型枚举
enum AlbumType {
  /// 本地相册 - 存储在本地设备上的相册，与文件系统目录结构类似
  local,

  /// 云相册 - 存储在云端的相册，需要云同步才能完成更改
  cloud
}

class Album {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final List<String> photoIds;
  final String? coverPhotoId;
  final bool isSynced;

  /// 相册类型，默认为本地相册
  final AlbumType albumType;

  /// 对于本地相册，可以指定关联的本地文件夹路径
  final String? localFolderPath;

  /// 云相册可能有一些照片尚未下载到本地
  final int? pendingCloudPhotosCount;

  Album({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    this.photoIds = const [],
    this.coverPhotoId,
    this.isSynced = false,
    this.albumType = AlbumType.local,
    this.localFolderPath,
    this.pendingCloudPhotosCount,
  });

  Album copyWith({
    String? name,
    String? description,
    DateTime? createdAt,
    List<String>? photoIds,
    String? coverPhotoId,
    bool? isSynced,
    AlbumType? albumType,
    String? localFolderPath,
    int? pendingCloudPhotosCount,
  }) {
    return Album(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      photoIds: photoIds ?? this.photoIds,
      coverPhotoId: coverPhotoId ?? this.coverPhotoId,
      isSynced: isSynced ?? this.isSynced,
      albumType: albumType ?? this.albumType,
      localFolderPath: localFolderPath ?? this.localFolderPath,
      pendingCloudPhotosCount:
          pendingCloudPhotosCount ?? this.pendingCloudPhotosCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'photoIds': photoIds,
      'coverPhotoId': coverPhotoId,
      'isSynced': isSynced,
      'albumType': albumType.toString().split('.').last,
      'localFolderPath': localFolderPath,
      'pendingCloudPhotosCount': pendingCloudPhotosCount,
    };
  }

  factory Album.fromJson(Map<String, dynamic> json) {
    // 解析相册类型
    AlbumType type = AlbumType.local;
    if (json.containsKey('albumType')) {
      final typeStr = json['albumType'];
      if (typeStr == 'cloud') {
        type = AlbumType.cloud;
      }
    }

    return Album(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      createdAt: DateTime.parse(json['createdAt']),
      photoIds: List<String>.from(json['photoIds'] ?? []),
      coverPhotoId: json['coverPhotoId'],
      isSynced: json['isSynced'] ?? false,
      albumType: type,
      localFolderPath: json['localFolderPath'],
      pendingCloudPhotosCount: json['pendingCloudPhotosCount'],
    );
  }

  /// 检查相册是否为云相册
  bool get isCloudAlbum => albumType == AlbumType.cloud;

  /// 检查相册是否为本地相册
  bool get isLocalAlbum => albumType == AlbumType.local;
}
