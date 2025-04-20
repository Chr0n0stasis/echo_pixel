import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
      _cacheDir =
          Directory('${cacheDir.path}${Platform.pathSeparator}thumbnails');

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

    // 确定缩略图质量 - UI线程中的轻量级操作
    final bool isHighQuality = previewQualityService?.isHighQuality ?? true;

    // 生成缓存键 - UI线程中的轻量级操作
    final cacheKey =
        _generateCacheKey(videoPath, ThumbnailType.video, isHighQuality);
    final thumbnailPath =
        '${_cacheDir!.path}${Platform.pathSeparator}$cacheKey.jpg';

    // 快速检查缓存是否存在 - 这个可以在UI线程，因为我们只是检查路径
    final cacheFile = File(thumbnailPath);
    if (await cacheFile.exists()) {
      debugPrint('使用缓存${isHighQuality ? "高" : "低"}质量视频缩略图: $thumbnailPath');
      return thumbnailPath;
    }

    // 将耗时处理移至后台线程
    try {
      // 获取RootIsolateToken，用于在隔离线程中访问平台通道
      final rootToken = RootIsolateToken.instance;
      if (rootToken == null) {
        debugPrint('无法获取RootIsolateToken，降级到主线程处理');
        return _processVideoThumbnailOnMainThread(
            videoPath, thumbnailPath, isHighQuality, previewQualityService);
      }

      return compute(_processVideoThumbnail, {
        'token': rootToken,
        'videoPath': videoPath,
        'thumbnailPath': thumbnailPath,
        'isHighQuality': isHighQuality,
        'thumbnailWidth': isHighQuality ? 1080 : 480,
        'thumbnailHeight': isHighQuality ? 1080 : 480,
        'thumbnailQuality': previewQualityService?.videoThumbnailQuality ??
            (isHighQuality ? 80 : 40),
      });
    } catch (e) {
      debugPrint('视频缩略图处理错误: $e');

      // 降级到主线程处理
      return _processVideoThumbnailOnMainThread(
          videoPath, thumbnailPath, isHighQuality, previewQualityService);
    }
  }

  /// 在主线程中处理视频缩略图（作为降级方案）
  Future<String?> _processVideoThumbnailOnMainThread(
      String videoPath,
      String thumbnailPath,
      bool isHighQuality,
      PreviewQualityService? previewQualityService) async {
    try {
      // 检查源视频文件是否存在
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        debugPrint('视频文件不存在: $videoPath');
        return null;
      }

      // 生成缩略图
      debugPrint('在主线程中生成视频缩略图 (降级方案): $videoPath');
      final success = await _videoThumbnailGenerator.getVideoThumbnail(
        srcFile: videoPath,
        destFile: thumbnailPath,
        width: isHighQuality ? 480 : 240, // 降低质量，以减轻主线程负担
        height: isHighQuality ? 480 : 240,
        format: 'jpeg',
        quality: (previewQualityService?.videoThumbnailQuality ??
                (isHighQuality ? 80 : 40)) -
            20,
      );

      if (success) {
        debugPrint('视频缩略图生成成功 (降级方案): $thumbnailPath');
        return thumbnailPath;
      }
    } catch (fallbackError) {
      debugPrint('降级方案也失败: $fallbackError');
    }

    return null;
  }

  /// 在隔离线程中处理视频缩略图
  static Future<String?> _processVideoThumbnail(
      Map<String, dynamic> params) async {
    final token = params['token'] as RootIsolateToken;
    final String videoPath = params['videoPath'];
    final String thumbnailPath = params['thumbnailPath'];
    final bool isHighQuality = params['isHighQuality'];
    final int thumbnailWidth = params['thumbnailWidth'];
    final int thumbnailHeight = params['thumbnailHeight'];
    final int thumbnailQuality = params['thumbnailQuality'];

    // 设置隔离线程的消息处理器，以允许访问平台通道
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);

    try {
      // 检查源视频文件是否存在
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        debugPrint('视频文件不存在: $videoPath');
        return null;
      }

      // 创建临时实例用于生成缩略图
      final videoThumbnailGenerator = FcNativeVideoThumbnail();

      // 生成缩略图 - 增加更多错误处理
      debugPrint(
          '生成${isHighQuality ? "高" : "低"}质量视频缩略图: $videoPath -> $thumbnailPath');

      try {
        final success = await videoThumbnailGenerator.getVideoThumbnail(
          srcFile: videoPath,
          destFile: thumbnailPath,
          width: thumbnailWidth,
          height: thumbnailHeight,
          format: 'jpeg',
          quality: thumbnailQuality,
        );

        if (success) {
          debugPrint('视频缩略图生成成功: $thumbnailPath');

          // 额外检查生成的文件是否真的存在
          final resultFile = File(thumbnailPath);
          if (await resultFile.exists()) {
            // 检查文件大小确保不是空文件或损坏文件
            final fileSize = await resultFile.length();
            if (fileSize > 100) {
              // 至少100字节才是有效的图片
              return thumbnailPath;
            } else {
              debugPrint('视频缩略图文件过小，可能已损坏: $fileSize 字节');
              // 尝试删除无效的缩略图
              try {
                await resultFile.delete();
              } catch (_) {}
              return null;
            }
          } else {
            debugPrint('虽然报告成功，但缩略图文件不存在');
            return null;
          }
        } else {
          debugPrint('无法生成视频缩略图: $videoPath');
          return null;
        }
      } catch (thumbError) {
        debugPrint('缩略图生成器异常: $thumbError');

        // 尝试使用更保守的参数重试一次
        try {
          debugPrint('使用降级参数重试视频缩略图生成');
          final retrySuccess = await videoThumbnailGenerator.getVideoThumbnail(
            srcFile: videoPath,
            destFile: thumbnailPath,
            width: thumbnailWidth ~/ 2, // 降低一半分辨率
            height: thumbnailHeight ~/ 2,
            format: 'jpeg',
            quality: thumbnailQuality - 10, // 降低质量
          );

          if (retrySuccess) {
            final resultFile = File(thumbnailPath);
            if (await resultFile.exists()) {
              return thumbnailPath;
            }
          }
        } catch (_) {}

        return null;
      }
    } catch (e) {
      debugPrint('生成视频缩略图失败: $videoPath - $e');
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

    // 确定缩略图质量 - 这个简单的判断可以在 UI 线程
    final bool isHighQuality = previewQualityService?.isHighQuality ?? true;

    // 生成唯一缓存键 - 这个计算量小，可以在 UI 线程
    final cacheKey =
        _generateCacheKey(imagePath, ThumbnailType.image, isHighQuality);

    // 首先检查内存缓存 - 这个操作很快，可以在 UI 线程
    if (_imageCache.containsKey(cacheKey)) {
      return _imageCache[cacheKey];
    }

    // 将剩余的所有缩略图处理工作移至后台隔离线程
    return compute(_processImageThumbnail, {
      'imagePath': imagePath,
      'cacheDir': _cacheDir!.path,
      'cacheKey': cacheKey,
      'isHighQuality': isHighQuality,
      'thumbnailWidth': isHighQuality
          ? previewQualityService?.imageCacheWidth ?? 800
          : previewQualityService?.imageCacheWidth ?? 400,
      'thumbnailHeight': isHighQuality
          ? previewQualityService?.imageCacheHeight ?? 800
          : previewQualityService?.imageCacheHeight ?? 400,
      'thumbnailQuality': isHighQuality ? 80 : 40,
    }).then((result) {
      // 如果成功生成缩略图，将其添加到内存缓存中
      if (result != null) {
        _imageCache[cacheKey] = result;
      }
      return result;
    });
  }

  /// 在隔离线程中处理图片缩略图
  static Future<Uint8List?> _processImageThumbnail(
      Map<String, dynamic> params) async {
    final String imagePath = params['imagePath'];
    final String cacheDirPath = params['cacheDir'];
    final String cacheKey = params['cacheKey'];
    final bool isHighQuality = params['isHighQuality'];
    final int thumbnailWidth = params['thumbnailWidth'];
    final int thumbnailHeight = params['thumbnailHeight'];
    final int thumbnailQuality = params['thumbnailQuality'];

    try {
      // 检查文件缓存
      final thumbnailPath =
          '$cacheDirPath${Platform.pathSeparator}$cacheKey.jpg';
      final cacheFile = File(thumbnailPath);
      if (await cacheFile.exists()) {
        debugPrint('使用缓存${isHighQuality ? "高" : "低"}质量图片缩略图: $thumbnailPath');
        return await cacheFile.readAsBytes();
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

      // 处理图片缩放
      final thumbnailData = _resizeImage({
        'bytes': bytes,
        'width': thumbnailWidth,
        'height': thumbnailHeight,
        'quality': thumbnailQuality
      });

      if (thumbnailData != null) {
        // 保存到文件缓存
        await cacheFile.writeAsBytes(thumbnailData);
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

      // 解码图片 - 添加更多错误处理
      img.Image? original;
      try {
        original = img.decodeImage(bytes);
      } catch (e) {
        // 尝试使用更安全的方式解码图片
        debugPrint('标准解码失败，尝试备用解码方法: $e');
        try {
          // 尝试以JPEG格式解码
          original = img.decodeJpg(bytes);
        } catch (_) {
          try {
            // 尝试以PNG格式解码
            original = img.decodePng(bytes);
          } catch (_) {
            // 所有解码方法都失败
            debugPrint('所有解码方法均失败');
            return null;
          }
        }
      }

      if (original == null) {
        debugPrint('无法解码图片');
        return null;
      }

      // 添加安全检查，确保图片尺寸合理
      if (original.width <= 0 ||
          original.height <= 0 ||
          original.width > 10000 ||
          original.height > 10000) {
        debugPrint('图片尺寸异常: ${original.width}x${original.height}');
        return null;
      }

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

      // 限制最大尺寸，避免内存问题
      if (width > 4000) {
        width = 4000;
        height = (width / ratio).round();
      }
      if (height > 4000) {
        height = 4000;
        width = (height * ratio).round();
      }

      // 确保尺寸至少为1x1
      width = width.clamp(1, 4000);
      height = height.clamp(1, 4000);

      // 安全调整图片大小
      img.Image resized;
      try {
        resized = img.copyResize(original,
            width: width,
            height: height,
            interpolation: img.Interpolation.average);
      } catch (e) {
        debugPrint('调整图片大小失败: $e');
        // 尝试使用不同的插值方法
        try {
          resized = img.copyResize(original,
              width: width,
              height: height,
              interpolation: img.Interpolation.nearest);
        } catch (e) {
          debugPrint('所有调整方法都失败: $e');
          return null;
        }
      }

      // 编码为JPEG，添加错误处理
      try {
        final jpegData = img.encodeJpg(resized, quality: quality);
        return Uint8List.fromList(jpegData);
      } catch (e) {
        debugPrint('JPEG编码失败: $e');
        // 尝试以较低质量重新编码
        try {
          final jpegData = img.encodeJpg(resized, quality: 60);
          return Uint8List.fromList(jpegData);
        } catch (_) {
          // 如果JPEG编码失败，尝试PNG格式
          try {
            final pngData = img.encodePng(resized);
            return Uint8List.fromList(pngData);
          } catch (e) {
            debugPrint('所有编码方法都失败: $e');
            return null;
          }
        }
      }
    } catch (e) {
      debugPrint('图片处理错误详情: $e');
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
          '${_cacheDir!.path}${Platform.pathSeparator}$highQualityCacheKey.jpg';
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
          '${_cacheDir!.path}/${Platform.pathSeparator}$lowQualityCacheKey.jpg';
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
