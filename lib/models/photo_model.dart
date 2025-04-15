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

class Album {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final List<String> photoIds;
  final String? coverPhotoId;
  final bool isSynced;

  Album({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    this.photoIds = const [],
    this.coverPhotoId,
    this.isSynced = false,
  });

  Album copyWith({
    String? name,
    String? description,
    DateTime? createdAt,
    List<String>? photoIds,
    String? coverPhotoId,
    bool? isSynced,
  }) {
    return Album(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      photoIds: photoIds ?? this.photoIds,
      coverPhotoId: coverPhotoId ?? this.coverPhotoId,
      isSynced: isSynced ?? this.isSynced,
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
    };
  }

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      createdAt: DateTime.parse(json['createdAt']),
      photoIds: List<String>.from(json['photoIds'] ?? []),
      coverPhotoId: json['coverPhotoId'],
      isSynced: json['isSynced'] ?? false,
    );
  }
}
