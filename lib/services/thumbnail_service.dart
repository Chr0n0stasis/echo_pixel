import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'dart:convert';
import 'package:echo_pixel/services/preview_quality_service.dart';
import 'package:image/image.dart' as img;

/// 缩略图类型枚举
enum ThumbnailType { image, video }

/// 统一缩略图缓存服务
/// 负责生成、缓存和管理图片和视频的缩略图
class ThumbnailService {
  static final ThumbnailService _instance = ThumbnailService._internal();

  factory ThumbnailService() {
    return _instance;
  }

  ThumbnailService._internal() {
    _initialize();
  }

  // 视频缩略图生成器
  final FcNativeVideoThumbnail _videoThumbnailGenerator =
      FcNativeVideoThumbnail();

  /// 缩略图缓存目录
  Directory? _cacheDir;

  /// 是否正在初始化
  bool _isInitializing = false;

  /// 是否已初始化
  bool _isInitialized = false;

  /// 图片缩略图内存缓存
  final Map<String, Uint8List> _imageCache = {};

  /// 初始化服务
  Future<void> _initialize() async {
    if (_isInitialized || _isInitializing) return;

    _isInitializing = true;
    try {
      final cacheDir = await getApplicationCacheDirectory();
      _cacheDir = Directory('${cacheDir.path}/thumbnails');

      // 确保缓存目录存在
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('初始化缩略图服务失败: $e');
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

  /// 从文件路径生成缓存key，包含文件类型和质量标记
  String _generateCacheKey(
      String filePath, ThumbnailType type, bool isHighQuality) {
    final typeStr = type == ThumbnailType.image ? 'img' : 'vid';
    final qualitySuffix = isHighQuality ? '_hq' : '_lq';
    final bytes = utf8.encode('$typeStr:$filePath$qualitySuffix');
    final digest = crypto.sha1.convert(bytes);
    return digest.toString();
  }

  /// 获取视频缩略图
  /// [videoPath] 视频文件路径
  /// [previewQualityService] 预览质量服务（可选，默认使用高质量）
  /// 返回缩略图文件路径，如果生成失败则返回null
  Future<String?> getVideoThumbnail(String videoPath,
      {PreviewQualityService? previewQualityService}) async {
    await ensureInitialized();
    if (_cacheDir == null) return null;

    // 确定缩略图质量
    final bool isHighQuality = previewQualityService?.isHighQuality ?? true;

    // 根据质量设置确定尺寸和质量参数
    final int thumbnailWidth = isHighQuality ? 1080 : 480;
    final int thumbnailHeight = isHighQuality ? 1080 : 480;
    final int thumbnailQuality = previewQualityService?.videoThumbnailQuality ??
        (isHighQuality ? 80 : 40);

    try {
      // 缓存键包含质量信息
      final cacheKey =
          _generateCacheKey(videoPath, ThumbnailType.video, isHighQuality);
      final thumbnailPath = '${_cacheDir!.path}/$cacheKey.jpg';

      // 检查缓存是否存在
      final cacheFile = File(thumbnailPath);
      if (await cacheFile.exists()) {
        debugPrint('使用缓存${isHighQuality ? "高" : "低"}质量视频缩略图: $thumbnailPath');
        return thumbnailPath;
      }

      // 检查源视频文件是否存在
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        debugPrint('视频文件不存在: $videoPath');
        return null;
      }

      // 生成缩略图
      debugPrint(
          '生成${isHighQuality ? "高" : "低"}质量视频缩略图: $videoPath -> $thumbnailPath');
      final success = await _videoThumbnailGenerator.getVideoThumbnail(
        srcFile: videoPath,
        destFile: thumbnailPath,
        width: thumbnailWidth,
        height: thumbnailHeight,
        format: 'jpeg',
        quality: thumbnailQuality,
      );

      if (success) {
        debugPrint('视频缩略图生成成功: $thumbnailPath');
        return thumbnailPath;
      } else {
        debugPrint('无法生成视频缩略图: $videoPath');
        return null;
      }
    } catch (e) {
      debugPrint('生成视频缩略图失败: $e');
      return null;
    }
  }

  /// 获取图片缩略图
  /// [imagePath] 图片文件路径
  /// [previewQualityService] 预览质量服务（可选，默认使用高质量）
  /// 返回缩略图数据，如果生成失败则返回null
  Future<Uint8List?> getImageThumbnail(String imagePath,
      {PreviewQualityService? previewQualityService}) async {
    await ensureInitialized();
    if (_cacheDir == null) return null;

    // 确定缩略图质量
    final bool isHighQuality = previewQualityService?.isHighQuality ?? true;

    // 根据质量设置确定尺寸和质量参数
    final int thumbnailWidth = isHighQuality
        ? previewQualityService?.imageCacheWidth ?? 800
        : previewQualityService?.imageCacheWidth ?? 400;
    final int thumbnailHeight = isHighQuality
        ? previewQualityService?.imageCacheHeight ?? 800
        : previewQualityService?.imageCacheHeight ?? 400;
    final int thumbnailQuality = isHighQuality ? 80 : 40;

    try {
      // 生成唯一缓存键
      final cacheKey =
          _generateCacheKey(imagePath, ThumbnailType.image, isHighQuality);

      // 首先检查内存缓存
      if (_imageCache.containsKey(cacheKey)) {
        return _imageCache[cacheKey];
      }

      // 检查文件缓存
      final thumbnailPath = '${_cacheDir!.path}/$cacheKey.jpg';
      final cacheFile = File(thumbnailPath);
      if (await cacheFile.exists()) {
        final cachedData = await cacheFile.readAsBytes();
        // 添加到内存缓存
        _imageCache[cacheKey] = cachedData;
        debugPrint('使用缓存${isHighQuality ? "高" : "低"}质量图片缩略图: $thumbnailPath');
        return cachedData;
      }

      // 检查源图片文件是否存在
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        debugPrint('图片文件不存在: $imagePath');
        return null;
      }

      // 读取原始图片文件
      debugPrint('生成${isHighQuality ? "高" : "低"}质量图片缩略图: $imagePath');
      final bytes = await imageFile.readAsBytes();

      // 在隔离线程中处理图片以避免阻塞UI
      final thumbnailData = await compute(_resizeImage, {
        'bytes': bytes,
        'width': thumbnailWidth,
        'height': thumbnailHeight,
        'quality': thumbnailQuality
      });

      if (thumbnailData != null) {
        // 保存到文件缓存
        await cacheFile.writeAsBytes(thumbnailData);

        // 添加到内存缓存
        _imageCache[cacheKey] = thumbnailData;

        debugPrint('图片缩略图生成成功: $thumbnailPath');
        return thumbnailData;
      } else {
        debugPrint('无法生成图片缩略图: $imagePath');
        return null;
      }
    } catch (e) {
      debugPrint('生成图片缩略图失败: $imagePath - $e');

      // 如果处理失败，尝试直接返回原图（作为备选方案）
      try {
        final imageFile = File(imagePath);
        if (await imageFile.exists()) {
          return await imageFile.readAsBytes();
        }
      } catch (_) {}

      return null;
    }
  }

  /// 在隔离线程中调整图片大小的静态方法
  static Uint8List? _resizeImage(Map<String, dynamic> params) {
    try {
      final Uint8List bytes = params['bytes'];
      final int targetWidth = params['width'];
      final int targetHeight = params['height'];
      final int quality = params['quality'];

      // 解码图片
      final img.Image? original = img.decodeImage(bytes);
      if (original == null) return null;

      // 计算比例保持宽高比
      double ratio = original.width / original.height;
      int width, height;

      if (original.width > original.height) {
        width = targetWidth;
        height = (width / ratio).round();
      } else {
        height = targetHeight;
        width = (height * ratio).round();
      }

      // 调整图片大小
      final img.Image resized = img.copyResize(original,
          width: width,
          height: height,
          interpolation: img.Interpolation.average);

      // 编码为JPEG
      final jpegData = img.encodeJpg(resized, quality: quality);
      return Uint8List.fromList(jpegData);
    } catch (e) {
      debugPrint('图片处理错误: $e');
      return null;
    }
  }

  /// 预加载图片缩略图（可以用于提前缓存重要的图片）
  Future<bool> preloadImageThumbnail(String imagePath,
      {PreviewQualityService? previewQualityService}) async {
    final thumbnail = await getImageThumbnail(imagePath,
        previewQualityService: previewQualityService);
    return thumbnail != null;
  }

  /// 清除特定文件的缩略图缓存（包括高质量和低质量版本）
  Future<bool> clearFileThumbnailCache(
      String filePath, ThumbnailType type) async {
    await ensureInitialized();
    if (_cacheDir == null) return false;

    try {
      bool result = false;

      // 删除高质量缩略图
      final highQualityCacheKey = _generateCacheKey(filePath, type, true);
      final highQualityThumbnailPath =
          '${_cacheDir!.path}/$highQualityCacheKey.jpg';
      final highQualityCacheFile = File(highQualityThumbnailPath);
      if (await highQualityCacheFile.exists()) {
        await highQualityCacheFile.delete();
        result = true;
      }

      // 从内存缓存中移除
      if (type == ThumbnailType.image) {
        _imageCache.remove(highQualityCacheKey);
      }

      // 删除低质量缩略图
      final lowQualityCacheKey = _generateCacheKey(filePath, type, false);
      final lowQualityThumbnailPath =
          '${_cacheDir!.path}/$lowQualityCacheKey.jpg';
      final lowQualityCacheFile = File(lowQualityThumbnailPath);
      if (await lowQualityCacheFile.exists()) {
        await lowQualityCacheFile.delete();
        result = true;
      }

      // 从内存缓存中移除
      if (type == ThumbnailType.image) {
        _imageCache.remove(lowQualityCacheKey);
      }

      return result;
    } catch (e) {
      debugPrint('清除缩略图缓存失败: $e');
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

  /// 清理内存缓存（可在内存不足时调用）
  void clearMemoryCache() {
    _imageCache.clear();
  }
}
