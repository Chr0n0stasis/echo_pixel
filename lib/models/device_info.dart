import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 设备信息类，用于识别不同设备
class DeviceInfo {
  /// 设备唯一标识符
  final String uuid;

  /// 设备名称
  final String name;

  /// 设备类型
  final DeviceType type;

  /// 最后同步时间
  DateTime? lastSyncTime;

  DeviceInfo({
    required this.uuid,
    required this.name,
    required this.type,
    this.lastSyncTime,
  });

  /// 获取设备信息（首次使用时创建UUID）
  static Future<DeviceInfo> getDeviceInfo() async {
    final prefs = await SharedPreferences.getInstance();

    // 尝试获取已存储的UUID
    String? savedUuid = prefs.getString('device_uuid');
    String? savedName = prefs.getString('device_name');

    // 如果没有UUID，则创建并保存
    if (savedUuid == null) {
      savedUuid = const Uuid().v4();
      await prefs.setString('device_uuid', savedUuid);
    }

    // 确定设备类型和默认名称
    DeviceType deviceType;
    String defaultName;

    if (kIsWeb) {
      deviceType = DeviceType.web;
      defaultName = 'Web浏览器';
    } else if (Platform.isAndroid) {
      deviceType = DeviceType.android;
      defaultName = 'Android设备';
    } else if (Platform.isIOS) {
      deviceType = DeviceType.ios;
      defaultName = 'iOS设备';
    } else if (Platform.isWindows) {
      deviceType = DeviceType.windows;
      defaultName = 'Windows电脑';
    } else if (Platform.isMacOS) {
      deviceType = DeviceType.macos;
      defaultName = 'Mac电脑';
    } else if (Platform.isLinux) {
      deviceType = DeviceType.linux;
      defaultName = 'Linux电脑';
    } else {
      deviceType = DeviceType.other;
      defaultName = '未知设备';
    }

    // 如果没有设备名称，使用默认名称
    if (savedName == null) {
      savedName = defaultName;
      await prefs.setString('device_name', savedName);
    }

    // 尝试获取上次同步时间
    final lastSyncTimeStr = prefs.getString('last_sync_time');
    DateTime? lastSyncTime;
    if (lastSyncTimeStr != null) {
      lastSyncTime = DateTime.tryParse(lastSyncTimeStr);
    }

    return DeviceInfo(
      uuid: savedUuid,
      name: savedName,
      type: deviceType,
      lastSyncTime: lastSyncTime,
    );
  }

  /// 更新设备名称
  Future<bool> updateDeviceName(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final result = await prefs.setString('device_name', newName);
    return result;
  }

  /// 更新最后同步时间
  Future<bool> updateLastSyncTime(DateTime syncTime) async {
    final prefs = await SharedPreferences.getInstance();
    lastSyncTime = syncTime;
    final result = await prefs.setString(
      'last_sync_time',
      syncTime.toIso8601String(),
    );
    return result;
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'type': type.toString().split('.').last,
      'lastSyncTime': lastSyncTime?.toIso8601String(),
    };
  }

  /// 从JSON创建对象
  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      uuid: json['uuid'],
      name: json['name'],
      type: _deviceTypeFromString(json['type']),
      lastSyncTime:
          json['lastSyncTime'] != null
              ? DateTime.parse(json['lastSyncTime'])
              : null,
    );
  }

  /// 从字符串解析设备类型
  static DeviceType _deviceTypeFromString(String typeStr) {
    switch (typeStr) {
      case 'android':
        return DeviceType.android;
      case 'ios':
        return DeviceType.ios;
      case 'windows':
        return DeviceType.windows;
      case 'macos':
        return DeviceType.macos;
      case 'linux':
        return DeviceType.linux;
      case 'web':
        return DeviceType.web;
      default:
        return DeviceType.other;
    }
  }
}

/// 设备类型枚举
enum DeviceType { android, ios, windows, macos, linux, web, other }
