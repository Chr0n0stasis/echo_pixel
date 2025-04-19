import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_index.dart';

/// 媒体缓存服务
/// 负责持久化存储媒体索引，提供快速访问
class MediaCacheService {
  // 单例实例
  static final MediaCacheService _instance = MediaCacheService._internal();

  // 缓存文件名
  static const String _mediaCacheFileName = 'media_indices_cache.json';

  // 最后扫描时间的键
  static const String _lastScanTimeKey = 'last_media_scan_time';

  // 缓存文件路径
  String? _cachePath;

  // 媒体索引缓存
  Map<String, MediaIndex>? _cachedIndices;

  // 最后一次扫描时间
  DateTime? _lastScanTime;

  // 防抖计时器
  Timer? _debounceTimer;

  // 防抖延迟（毫秒）
  static const int _debounceDelayMs = 5000; // 5秒

  // 待保存的索引
  Map<String, MediaIndex>? _pendingSaveIndices;

  // 上次保存时间
  DateTime? _lastSaveTime;

  // 工厂构造函数
  factory MediaCacheService() {
    return _instance;
  }

  // 内部构造函数
  MediaCacheService._internal();

  /// 初始化缓存服务
  Future<void> initialize() async {
    try {
      if (_cachePath != null) return; // 已初始化

      // 获取应用文档目录
      final appDir = await getApplicationSupportDirectory();
      _cachePath =
          '${appDir.path}${Platform.pathSeparator}$_mediaCacheFileName';

      // 加载最后扫描时间
      final prefs = await SharedPreferences.getInstance();
      final lastScanTimeMillis = prefs.getInt(_lastScanTimeKey);

      if (lastScanTimeMillis != null) {
        _lastScanTime = DateTime.fromMillisecondsSinceEpoch(lastScanTimeMillis);
        debugPrint('上次媒体扫描时间: $_lastScanTime');
      }

      debugPrint('媒体缓存服务初始化完成，缓存路径: $_cachePath');
    } catch (e) {
      debugPrint('初始化媒体缓存服务失败: $e');
    }
  }

  // 取消所有防抖操作
  void cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  // 在实例销毁时清理资源
  void dispose() {
    cancelDebounce();
  }

  /// 加载缓存的媒体索引
  Future<Map<String, MediaIndex>?> loadCachedIndices() async {
    if (_cachedIndices != null) {
      return _cachedIndices;
    }

    try {
      if (_cachePath == null) {
        await initialize();
      }

      final cacheFile = File(_cachePath!);
      if (await cacheFile.exists()) {
        final String jsonString = await cacheFile.readAsString();
        final Map<String, dynamic> jsonMap = jsonDecode(jsonString);

        _cachedIndices = {};
        jsonMap.forEach((key, value) {
          _cachedIndices![key] = MediaIndex.fromJson(value);
        });

        debugPrint('已从缓存加载 ${_cachedIndices!.length} 个媒体索引');
        return _cachedIndices;
      } else {
        debugPrint('媒体索引缓存文件不存在');
        return null;
      }
    } catch (e) {
      debugPrint('加载媒体索引缓存失败: $e');
      return null;
    }
  }

  /// 保存媒体索引到缓存
  Future<bool> saveIndicesToCache(Map<String, MediaIndex> indices) async {
    try {
      if (_cachePath == null) {
        await initialize();
      }

      // 转换为JSON
      final Map<String, dynamic> jsonMap = {};
      indices.forEach((key, value) {
        jsonMap[key] = value.toJson();
      });

      final String jsonString = jsonEncode(jsonMap);

      // 写入缓存文件
      final cacheFile = File(_cachePath!);
      await cacheFile.writeAsString(jsonString);

      // 更新内存缓存
      _cachedIndices = Map.from(indices);

      // 更新最后扫描时间
      final now = DateTime.now();
      _lastScanTime = now;
      _lastSaveTime = now;

      // 保存最后扫描时间
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastScanTimeKey, now.millisecondsSinceEpoch);

      debugPrint('已保存 ${indices.length} 个媒体索引到缓存');
      return true;
    } catch (e) {
      debugPrint('保存媒体索引到缓存失败: $e');
      return false;
    }
  }

  /// 保存媒体索引到缓存（带防抖）
  Future<void> debouncedSaveIndicesToCache(
      Map<String, MediaIndex> indices) async {
    // 保存待处理的索引
    _pendingSaveIndices = Map.from(indices);

    // 取消之前的计时器（如果有）
    _debounceTimer?.cancel();

    // 检查是否需要立即保存（如果距离上次保存超过了30秒）
    final now = DateTime.now();
    if (_lastSaveTime == null ||
        now.difference(_lastSaveTime!).inSeconds > 30) {
      // 立即保存
      await _executeSave();
      return;
    }

    // 设置新的防抖计时器
    _debounceTimer = Timer(Duration(milliseconds: _debounceDelayMs), () async {
      await _executeSave();
    });
  }

  /// 执行实际的保存操作
  Future<void> _executeSave() async {
    if (_pendingSaveIndices != null) {
      await saveIndicesToCache(_pendingSaveIndices!);
      _pendingSaveIndices = null;
    }
  }

  /// 强制立即保存（忽略防抖）
  Future<bool> forceSaveIndicesToCache(Map<String, MediaIndex> indices) async {
    cancelDebounce();
    _pendingSaveIndices = null;
    return await saveIndicesToCache(indices);
  }

  /// 清除缓存
  Future<void> clearCache() async {
    try {
      if (_cachePath == null) {
        await initialize();
      }

      final cacheFile = File(_cachePath!);
      if (await cacheFile.exists()) {
        await cacheFile.delete();
        debugPrint('已清除媒体索引缓存');
      }

      // 清除最后扫描时间
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastScanTimeKey);

      _cachedIndices = null;
      _lastScanTime = null;
      _lastSaveTime = null;
    } catch (e) {
      debugPrint('清除媒体索引缓存失败: $e');
    }
  }

  /// 获取最后扫描时间
  DateTime? get lastScanTime => _lastScanTime;

  /// 获取最后保存时间
  DateTime? get lastSaveTime => _lastSaveTime;

  /// 是否有缓存
  Future<bool> hasCachedIndices() async {
    if (_cachedIndices != null && _cachedIndices!.isNotEmpty) {
      return true;
    }

    try {
      if (_cachePath == null) {
        await initialize();
      }

      final cacheFile = File(_cachePath!);
      return await cacheFile.exists();
    } catch (e) {
      debugPrint('检查媒体索引缓存失败: $e');
      return false;
    }
  }
}
