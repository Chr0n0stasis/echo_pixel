import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/thumbnail_service.dart';

/// 懒加载图片缩略图组件 - 使用ThumbnailService生成缩略图
class LazyLoadingImageThumbnail extends StatefulWidget {
  final String imagePath;
  final BoxFit fit;

  const LazyLoadingImageThumbnail({
    required this.imagePath,
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
  bool _isGif = false;

  @override
  void initState() {
    super.initState();
    _checkIfGif();
    _loadThumbnail();
  }

  void _checkIfGif() {
    // 检查是否为GIF文件
    _isGif = widget.imagePath.toLowerCase().endsWith('.gif');
  }

  @override
  void didUpdateWidget(LazyLoadingImageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 如果图片路径发生变化，重新加载缩略图
    if (oldWidget.imagePath != widget.imagePath) {
      _checkIfGif();
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // 使用缩略图服务获取图片缩略图数据
      final thumbnailData = await _thumbnailService.getImageThumbnail(
        widget.imagePath,
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

    // 如果是GIF，则使用缩略图作为静态预览
    if (_isGif) {
      return Stack(
        alignment: Alignment.center,
        children: [
          // 显示缩略图作为背景
          Image.memory(
            _thumbnailData!,
            fit: widget.fit,
            filterQuality: FilterQuality.high,
          ),
          // 叠加GIF标志
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'GIF',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ],
      );
    }

    // 显示普通图片缩略图
    return Image.memory(
      _thumbnailData!,
      fit: widget.fit,
      filterQuality: FilterQuality.high,
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
