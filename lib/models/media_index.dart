import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;

class MediaFile {
  MediaFileInfo info;
  bool isLocal;

  MediaFile({required this.info, this.isLocal = true});

  Map<String, dynamic> toJson() {
    return {
      'info': info.toJson(),
      'isLocal': isLocal,
    };
  }

  factory MediaFile.fromJson(Map<String, dynamic> json) {
    return MediaFile(
      info: MediaFileInfo.fromJson(json['info']),
      isLocal: json['isLocal'] ?? true,
    );
  }
}

/// 按时间索引的媒体文件结构
class MediaIndex {
  /// 使用年月日作为主键
  final String datePath;

  /// 当天的所有媒体文件
  final List<MediaFile> mediaFiles;

  MediaIndex({required this.datePath, required this.mediaFiles});

  /// 获取特定日期的格式化路径 (yyyy/MM/dd)
  static String getDatePath(DateTime dateTime) {
    final year = dateTime.year.toString();
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '$year/$month/$day';
  }

  /// 从日期字符串解析日期
  static DateTime? parseDatePath(String datePath) {
    final parts = datePath.split('/');
    if (parts.length != 3) return null;

    try {
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      return DateTime(year, month, day);
    } catch (e) {
      return null;
    }
  }

  /// 获取日期可读表示 (如：2025年4月14日)
  String get readableDate {
    final dateTime = parseDatePath(datePath);
    if (dateTime == null) return datePath;
    return DateFormat('yyyy年MM月dd日').format(dateTime);
  }

  Map<String, dynamic> toJson() {
    return {
      'datePath': datePath,
      'mediaFiles': mediaFiles.map((f) => f.toJson()).toList(),
    };
  }

  /// 从JSON创建对象
  factory MediaIndex.fromJson(Map<String, dynamic> json) {
    return MediaIndex(
      datePath: json['datePath'],
      mediaFiles: (json['mediaFiles'] as List)
          .map((item) => MediaFile.fromJson(item))
          .toList(),
    );
  }
}

/// 媒体文件类型
enum MediaType { image, video, unknown }

/// 媒体文件信息
class MediaFileInfo {
  /// 文件唯一标识符，基于文件内容的哈希
  final String id;

  /// 文件原始路径
  final String originalPath;

  /// 文件名（不含扩展名）
  final String name;

  /// 文件扩展名
  final String extension;

  /// 文件大小（字节）
  final int size;

  /// 文件类型（图片、视频）
  final MediaType type;

  /// 媒体创建时间
  final DateTime createdAt;

  /// 媒体修改时间
  final DateTime modifiedAt;

  /// 媒体分辨率（图片或视频）
  final MediaResolution? resolution;

  /// 媒体时长（适用于视频）
  final Duration? duration;

  /// 元数据（EXIF等）
  final Map<String, dynamic>? metadata;

  /// 是否已同步到云端
  bool isSynced;

  /// 是否为收藏
  bool isFavorite;

  /// 云端路径
  String? cloudPath;

  MediaFileInfo({
    required this.id,
    required this.originalPath,
    required this.name,
    required this.extension,
    required this.size,
    required this.type,
    required this.createdAt,
    required this.modifiedAt,
    this.resolution,
    this.duration,
    this.metadata,
    this.isSynced = false,
    this.isFavorite = false,
    this.cloudPath,
  });

  /// 获取完整文件名（含扩展名）
  String get fileName => '$name.$extension';

  /// 文件后缀是否为图片常见格式
  static bool isImageExtension(String ext) {
    final imageSuffixes = [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
      'heic',
      'heif',
    ];
    return imageSuffixes.contains(ext.toLowerCase());
  }

  /// 文件后缀是否为视频常见格式
  static bool isVideoExtension(String ext) {
    final videoSuffixes = [
      'mp4',
      'mov',
      'avi',
      'wmv',
      'flv',
      'mkv',
      '3gp',
      'webm',
    ];
    return videoSuffixes.contains(ext.toLowerCase());
  }

  /// 根据文件路径推断媒体类型
  static MediaType inferTypeFromPath(String filePath) {
    final ext = path.extension(filePath).replaceAll('.', '').toLowerCase();

    if (isImageExtension(ext)) {
      return MediaType.image;
    } else if (isVideoExtension(ext)) {
      return MediaType.video;
    } else {
      return MediaType.unknown;
    }
  }

  /// 根据文件内容生成唯一ID
  static Future<String> generateIdFromFile(Uint8List fileBytes) async {
    // 使用SHA-256生成哈希值
    final digest = sha256.convert(fileBytes);
    return digest.toString();
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalPath': originalPath,
      'name': name,
      'extension': extension,
      'size': size,
      'type': type.toString().split('.').last,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'resolution': resolution?.toJson(),
      'duration': duration?.inSeconds,
      'metadata': metadata,
      'isSynced': isSynced,
      'isFavorite': isFavorite,
      'cloudPath': cloudPath,
    };
  }

  /// 从JSON创建对象
  factory MediaFileInfo.fromJson(Map<String, dynamic> json) {
    return MediaFileInfo(
      id: json['id'],
      originalPath: json['originalPath'],
      name: json['name'],
      extension: json['extension'],
      size: json['size'],
      type: _mediaTypeFromString(json['type']),
      createdAt: DateTime.parse(json['createdAt']),
      modifiedAt: DateTime.parse(json['modifiedAt']),
      resolution: json['resolution'] != null
          ? MediaResolution.fromJson(json['resolution'])
          : null,
      duration:
          json['duration'] != null ? Duration(seconds: json['duration']) : null,
      metadata: json['metadata'],
      isSynced: json['isSynced'] ?? false,
      isFavorite: json['isFavorite'] ?? false,
      cloudPath: json['cloudPath'],
    );
  }

  /// 从字符串解析媒体类型
  static MediaType _mediaTypeFromString(String typeStr) {
    switch (typeStr) {
      case 'image':
        return MediaType.image;
      case 'video':
        return MediaType.video;
      default:
        return MediaType.unknown;
    }
  }
}

/// 媒体分辨率
class MediaResolution {
  final int width;
  final int height;

  MediaResolution({required this.width, required this.height});

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {'width': width, 'height': height};
  }

  /// 从JSON创建对象
  factory MediaResolution.fromJson(Map<String, dynamic> json) {
    return MediaResolution(width: json['width'], height: json['height']);
  }

  @override
  String toString() => '${width}x$height';
}
