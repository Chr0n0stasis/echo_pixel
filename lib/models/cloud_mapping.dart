import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

/// 云端媒体映射表
/// 记录本地媒体文件与云端存储的映射关系
class CloudMediaMapping {
  /// 设备UUID
  final String deviceId;

  /// 设备名称
  final String deviceName;

  /// 上次更新时间
  final DateTime lastUpdated;

  /// 媒体文件映射记录
  final List<MediaMapping> mappings;

  CloudMediaMapping({
    required this.deviceId,
    required this.deviceName,
    required this.lastUpdated,
    required this.mappings,
  });

  /// 查找特定媒体文件ID的映射
  MediaMapping? findMappingById(String mediaId) {
    try {
      return mappings.firstWhere((mapping) => mapping.mediaId == mediaId);
    } catch (e) {
      return null;
    }
  }

  /// 添加或更新映射
  void addOrUpdateMapping(MediaMapping mapping) {
    final index = mappings.indexWhere((m) => m.mediaId == mapping.mediaId);
    if (index >= 0) {
      mappings[index] = mapping;
    } else {
      mappings.add(mapping);
    }
  }

  /// 删除映射
  bool removeMapping(String mediaId) {
    final initialLength = mappings.length;
    mappings.removeWhere((mapping) => mapping.mediaId == mediaId);
    return mappings.length < initialLength;
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'lastUpdated': lastUpdated.toIso8601String(),
      'mappings': mappings.map((mapping) => mapping.toJson()).toList(),
    };
  }

  /// 序列化为JSON字符串
  String toJsonString() {
    return jsonEncode(toJson());
  }

  /// 从JSON创建对象
  factory CloudMediaMapping.fromJson(Map<String, dynamic> json) {
    final List<dynamic> mappingsList = json['mappings'];
    return CloudMediaMapping(
      deviceId: json['deviceId'],
      deviceName: json['deviceName'],
      lastUpdated: DateTime.parse(json['lastUpdated']),
      mappings: mappingsList
          .map((mappingJson) => MediaMapping.fromJson(mappingJson))
          .toList(),
    );
  }

  /// 从JSON字符串创建对象
  factory CloudMediaMapping.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return CloudMediaMapping.fromJson(json);
  }
}

/// 单个媒体文件的映射关系
class MediaMapping {
  /// 媒体文件ID (基于文件内容的哈希)
  final String mediaId;

  /// 本地文件路径
  final String localPath;

  /// 云端存储路径
  final String cloudPath;

  /// 相对路径(yy/mm/dd/filename)
  String get relativePath {
    const prefix = 'EchoPixel/';
    final lastIndex = cloudPath.lastIndexOf(prefix);
    if (lastIndex != -1) {
      return cloudPath.substring(lastIndex + prefix.length);
    } else {
      return cloudPath;
    }
  }

  /// 媒体类型 (用于区分图片和视频)
  final String mediaType;

  /// 媒体创建时间
  final DateTime createdAt;

  /// 文件大小 (字节)
  final int fileSize;

  /// 上次同步时间
  final DateTime lastSynced;

  /// 同步状态
  final SyncStatus syncStatus;

  MediaMapping({
    required this.mediaId,
    required this.localPath,
    required this.cloudPath,
    required this.mediaType,
    required this.createdAt,
    required this.fileSize,
    required this.lastSynced,
    this.syncStatus = SyncStatus.synced,
  });

  /// 获取文件名
  String get fileName => path.basename(localPath);

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'mediaId': mediaId,
      'localPath': localPath,
      'cloudPath': cloudPath,
      'mediaType': mediaType,
      'createdAt': createdAt.toIso8601String(),
      'fileSize': fileSize,
      'lastSynced': lastSynced.toIso8601String(),
      'syncStatus': syncStatus.toString().split('.').last,
    };
  }

  /// 从JSON创建对象
  factory MediaMapping.fromJson(Map<String, dynamic> json) {
    return MediaMapping(
      mediaId: json['mediaId'],
      localPath: json['localPath'],
      cloudPath: json['cloudPath'],
      mediaType: json['mediaType'],
      createdAt: DateTime.parse(json['createdAt']),
      fileSize: json['fileSize'],
      lastSynced: DateTime.parse(json['lastSynced']),
      syncStatus: _syncStatusFromString(json['syncStatus']),
    );
  }

  /// 从字符串解析同步状态
  static SyncStatus _syncStatusFromString(String statusStr) {
    switch (statusStr) {
      case 'synced':
        return SyncStatus.synced;
      case 'pendingUpload':
        return SyncStatus.pendingUpload;
      case 'pendingDownload':
        return SyncStatus.pendingDownload;
      case 'conflict':
        return SyncStatus.conflict;
      case 'error':
        return SyncStatus.error;
      default:
        return SyncStatus.unknown;
    }
  }

  /// 创建已同步副本
  MediaMapping copyWithSyncStatus(SyncStatus newStatus) {
    return MediaMapping(
      mediaId: mediaId,
      localPath: localPath,
      cloudPath: cloudPath,
      mediaType: mediaType,
      createdAt: createdAt,
      fileSize: fileSize,
      lastSynced: DateTime.now(),
      syncStatus: newStatus,
    );
  }
}

/// 同步状态枚举
enum SyncStatus {
  /// 已完成同步
  synced,

  /// 等待上传到云端
  pendingUpload,

  /// 等待从云端下载
  pendingDownload,

  /// 存在冲突（本地和云端均有更改）
  conflict,

  /// 同步出错
  error,

  /// 未知状态
  unknown,
}

/// 同步状态颜色和图标
extension SyncStatusExtension on SyncStatus {
  /// 获取状态对应的颜色
  Color get color {
    switch (this) {
      case SyncStatus.synced:
        return Colors.green;
      case SyncStatus.pendingUpload:
        return Colors.blue;
      case SyncStatus.pendingDownload:
        return Colors.orange;
      case SyncStatus.conflict:
        return Colors.amber;
      case SyncStatus.error:
        return Colors.red;
      case SyncStatus.unknown:
        return Colors.grey;
    }
  }

  /// 获取状态对应的图标
  IconData get icon {
    switch (this) {
      case SyncStatus.synced:
        return Icons.check_circle;
      case SyncStatus.pendingUpload:
        return Icons.cloud_upload;
      case SyncStatus.pendingDownload:
        return Icons.cloud_download;
      case SyncStatus.conflict:
        return Icons.warning;
      case SyncStatus.error:
        return Icons.error;
      case SyncStatus.unknown:
        return Icons.help;
    }
  }
}
