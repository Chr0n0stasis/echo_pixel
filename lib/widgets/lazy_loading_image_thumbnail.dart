import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/thumbnail_service.dart';
import '../services/preview_quality_service.dart';

/// 懒加载图片缩略图组件 - 使用ThumbnailService生成缩略图
class LazyLoadingImageThumbnail extends StatefulWidget {
  final String imagePath;
  final PreviewQualityService previewQualityService;
  final BoxFit fit;

  const LazyLoadingImageThumbnail({
    required this.imagePath,
    required this.previewQualityService,
    this.fit = BoxFit.cover,
    super.key,
  });

  @override
  State<LazyLoadingImageThumbnail> createState() =>
      _LazyLoadingImageThumbnailState();
}

class _LazyLoadingImageThumbnailState extends State<LazyLoadingImageThumbnail> {
  // 使用缩略图服务
  final ThumbnailService _thumbnailService = ThumbnailService();

  Uint8List? _thumbnailData;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(LazyLoadingImageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 如果图片路径或质量设置发生变化，重新加载缩略图
    if (oldWidget.imagePath != widget.imagePath ||
        oldWidget.previewQualityService.isHighQuality !=
            widget.previewQualityService.isHighQuality) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // 使用缩略图服务获取图片缩略图数据
      final thumbnailData = await _thumbnailService.getImageThumbnail(
        widget.imagePath,
        previewQualityService: widget.previewQualityService,
      );

      if (!mounted) return;

      setState(() {
        _thumbnailData = thumbnailData;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('生成图片缩略图错误: ${widget.imagePath} - $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // 显示加载占位符
      return Container(
        color: Colors.black,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_hasError || _thumbnailData == null) {
      // 显示错误占位符
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.white60, size: 32),
        ),
      );
    }

    // 显示缩略图
    return Image.memory(
      _thumbnailData!,
      fit: widget.fit,
      filterQuality: widget.previewQualityService.imageFilterQuality,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.black,
          child: const Center(
            child: Icon(Icons.broken_image, color: Colors.white60),
          ),
        );
      },
    );
  }
}
