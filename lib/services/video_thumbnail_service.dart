import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'dart:convert';

/// 视频缩略图缓存服务
/// 负责生成、缓存和管理视频缩略图
class VideoThumbnailService {
  static final VideoThumbnailService _instance =
      VideoThumbnailService._internal();

  factory VideoThumbnailService() {
    return _instance;
  }

  VideoThumbnailService._internal() {
    _initialize();
  }

  final FcNativeVideoThumbnail _thumbnailGenerator = FcNativeVideoThumbnail();

  /// 缩略图缓存目录
  Directory? _cacheDir;

  /// 缩略图宽度 - 提高到720px以适应现代高分辨率设备
  final int _thumbnailWidth = 720;

  /// 缩略图高度 - 提高到720px以适应现代高分辨率设备
  final int _thumbnailHeight = 720;

  /// 缩略图质量 - 使用最高质量100
  final int _thumbnailQuality = 100;

  /// 是否正在初始化
  bool _isInitializing = false;

  /// 是否已初始化
  bool _isInitialized = false;

  /// 初始化服务
  Future<void> _initialize() async {
    if (_isInitialized || _isInitializing) return;

    _isInitializing = true;
    try {
      final appDir = await getApplicationSupportDirectory();
      _cacheDir = Directory('${appDir.path}/video_thumbnails');

      // 确保缓存目录存在
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('初始化视频缩略图服务失败: $e');
    } finally {
      _isInitializing = false;
    }
  }

  /// 确保服务已初始化
  Future<void> ensureInitialized() async {
    if (!_isInitialized) {
      await _initialize();
    }
  }

  /// 从视频文件路径生成缓存key
  String _generateCacheKey(String videoPath) {
    final bytes = utf8.encode(videoPath);
    final digest = crypto.sha1.convert(bytes);
    return digest.toString();
  }

  /// 获取视频缩略图
  /// [videoPath] 视频文件路径
  /// 返回缩略图文件路径，如果生成失败则返回null
  Future<String?> getVideoThumbnail(String videoPath) async {
    await ensureInitialized();
    if (_cacheDir == null) return null;

    try {
      final cacheKey = _generateCacheKey(videoPath);
      final thumbnailPath = '${_cacheDir!.path}/$cacheKey.jpg';

      // 检查缓存是否存在
      final cacheFile = File(thumbnailPath);
      if (await cacheFile.exists()) {
        debugPrint('使用缓存缩略图: $thumbnailPath');
        return thumbnailPath;
      }

      // 检查源视频文件是否存在
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        debugPrint('视频文件不存在: $videoPath');
        return null;
      }

      // 生成缩略图
      debugPrint('生成视频缩略图: $videoPath -> $thumbnailPath');
      final success = await _thumbnailGenerator.getVideoThumbnail(
        srcFile: videoPath,
        destFile: thumbnailPath,
        width: _thumbnailWidth,
        height: _thumbnailHeight,
        format: 'jpeg',
        quality: _thumbnailQuality,
      );

      if (success) {
        debugPrint('缩略图生成成功: $thumbnailPath');
        return thumbnailPath;
      } else {
        debugPrint('无法生成缩略图: $videoPath');
        return null;
      }
    } catch (e) {
      debugPrint('生成视频缩略图失败: $e');
      return null;
    }
  }

  /// 清除特定视频的缩略图缓存
  Future<bool> clearThumbnailCache(String videoPath) async {
    await ensureInitialized();
    if (_cacheDir == null) return false;

    try {
      final cacheKey = _generateCacheKey(videoPath);
      final thumbnailPath = '${_cacheDir!.path}/$cacheKey.jpg';

      final cacheFile = File(thumbnailPath);
      if (await cacheFile.exists()) {
        await cacheFile.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('清除缩略图缓存失败: $e');
      return false;
    }
  }

  /// 清除所有缩略图缓存
  Future<bool> clearAllThumbnailCache() async {
    await ensureInitialized();
    if (_cacheDir == null) return false;

    try {
      // 删除并重新创建缓存目录
      await _cacheDir!.delete(recursive: true);
      await _cacheDir!.create(recursive: true);
      return true;
    } catch (e) {
      debugPrint('清除所有缩略图缓存失败: $e');
      return false;
    }
  }

  /// 获取缓存大小（字节）
  Future<int> getCacheSize() async {
    await ensureInitialized();
    if (_cacheDir == null) return 0;

    try {
      int totalSize = 0;
      final files = await _cacheDir!.list().toList();

      for (final file in files) {
        if (file is File) {
          totalSize += await file.length();
        }
      }

      return totalSize;
    } catch (e) {
      debugPrint('获取缓存大小失败: $e');
      return 0;
    }
  }
}
