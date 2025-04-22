import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// GIF动画播放器组件
/// 用于播放GIF动画，支持从文件或内存加载
class GifPlayer extends StatefulWidget {
  /// GIF文件路径（与gifBytes二选一提供）
  final String? filePath;

  /// GIF字节数据（与filePath二选一提供）
  final Uint8List? gifBytes;

  /// 显示方式
  final BoxFit fit;

  /// 是否自动播放
  final bool autoPlay;

  /// 图片质量
  final FilterQuality filterQuality;

  const GifPlayer({
    super.key,
    this.filePath,
    this.gifBytes,
    this.fit = BoxFit.cover,
    this.autoPlay = true,
    this.filterQuality = FilterQuality.low,
  }) : assert(
            filePath != null || gifBytes != null, "必须提供filePath或gifBytes其中之一");

  @override
  State<GifPlayer> createState() => _GifPlayerState();
}

class _GifPlayerState extends State<GifPlayer>
    with SingleTickerProviderStateMixin {
  late final Image _gifImage;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initGifImage();
    if (widget.autoPlay) {
      _startPlaying();
    }
  }

  void _initGifImage() {
    if (widget.filePath != null) {
      _gifImage = Image.file(
        File(widget.filePath!),
        fit: widget.fit,
        filterQuality: widget.filterQuality,
        cacheHeight: null, // 不设置缓存高度，以允许GIF动画
        cacheWidth: null, // 不设置缓存宽度，以允许GIF动画
        gaplessPlayback: true,
      );
    } else {
      _gifImage = Image.memory(
        widget.gifBytes!,
        fit: widget.fit,
        filterQuality: widget.filterQuality,
        cacheHeight: null, // 不设置缓存高度，以允许GIF动画
        cacheWidth: null, // 不设置缓存宽度，以允许GIF动画
        gaplessPlayback: true,
      );
    }
  }

  void _startPlaying() {
    // 通过设置state触发重建，使GIF开始播放
    setState(() {
      _isPlaying = true;
    });
  }

  void _stopPlaying() {
    // 通过设置state触发重建，使GIF停止播放
    setState(() {
      _isPlaying = false;
    });
  }

  @override
  void dispose() {
    // 清理资源
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_isPlaying) {
          _stopPlaying();
        } else {
          _startPlaying();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // GIF图像
          _gifImage,

          // 播放暂停指示器（仅在暂停时显示）
          if (!_isPlaying)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
