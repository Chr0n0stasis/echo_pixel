import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media_index.dart';
import '../widgets/gif_player.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as path;

class ImageViewerPage extends StatefulWidget {
  final MediaFileInfo mediaFile;
  final List<MediaFileInfo>? mediaFiles; // 同一组中的所有媒体文件，用于左右滑动浏览
  final int initialIndex; // 初始显示的索引

  const ImageViewerPage({
    super.key,
    required this.mediaFile,
    this.mediaFiles,
    this.initialIndex = 0,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late PageController _pageController;
  late int _currentIndex;
  bool _isFullScreen = false;
  bool _isControlsVisible = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    // 延迟自动隐藏控制栏
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isControlsVisible = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    // 如果进入了全屏模式，确保退出时恢复状态栏
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _isControlsVisible = !_isControlsVisible;
    });
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      if (_isFullScreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });
  }

  void _shareImage() {
    final MediaFileInfo currentFile = widget.mediaFiles != null
        ? widget.mediaFiles![_currentIndex]
        : widget.mediaFile;

    Share.shareXFiles(
      [XFile(currentFile.originalPath)],
      text: 'Sharing ${path.basename(currentFile.originalPath)}',
    );
  }

  // 检查当前查看的文件是否为GIF
  bool _isGifFile(MediaFileInfo file) {
    return file.originalPath.toLowerCase().endsWith('.gif');
  }

  @override
  Widget build(BuildContext context) {
    // 如果提供了媒体文件列表，使用Gallery模式
    final bool isGalleryMode =
        widget.mediaFiles != null && widget.mediaFiles!.isNotEmpty;
    final List<MediaFileInfo> files =
        isGalleryMode ? widget.mediaFiles! : [widget.mediaFile];

    // 检查当前文件是否为GIF
    final bool isCurrentGif = _isGifFile(files[_currentIndex]);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isControlsVisible && !_isFullScreen
          ? AppBar(
              backgroundColor: Colors.black.withOpacity(0.5),
              foregroundColor: Colors.white,
              title: Text(
                path.basename(files[_currentIndex].originalPath),
                style: const TextStyle(fontSize: 16),
              ),
              actions: [
                // 如果是GIF，显示GIF标签
                if (isCurrentGif)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'GIF',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                IconButton(
                  icon: Icon(
                      _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
                  onPressed: _toggleFullScreen,
                  tooltip: '全屏',
                ),
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: _shareImage,
                  tooltip: '分享',
                ),
              ],
            )
          : null,
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: _toggleControls,
        child: isGalleryMode
            ? PhotoViewGallery.builder(
                scrollPhysics: const BouncingScrollPhysics(),
                builder: (context, index) {
                  final MediaFileInfo file = files[index];
                  final bool isGif = _isGifFile(file);

                  // 根据文件类型选择不同的显示组件
                  if (isGif) {
                    return PhotoViewGalleryPageOptions.customChild(
                      child: Center(
                        child: GifPlayer(
                          filePath: file.originalPath,
                          fit: BoxFit.contain,
                          autoPlay: true,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      minScale: PhotoViewComputedScale.contained * 0.8,
                      maxScale: PhotoViewComputedScale.covered * 2.0,
                      heroAttributes:
                          PhotoViewHeroAttributes(tag: 'media_${file.id}'),
                    );
                  } else {
                    // 普通图片使用标准PhotoView
                    return PhotoViewGalleryPageOptions(
                      imageProvider: FileImage(File(file.originalPath)),
                      initialScale: PhotoViewComputedScale.contained,
                      minScale: PhotoViewComputedScale.contained * 0.8,
                      maxScale: PhotoViewComputedScale.covered * 2.0,
                      heroAttributes:
                          PhotoViewHeroAttributes(tag: 'media_${file.id}'),
                    );
                  }
                },
                itemCount: files.length,
                loadingBuilder: (context, event) => Center(
                  child: SizedBox(
                    width: 20.0,
                    height: 20.0,
                    child: CircularProgressIndicator(
                      value: event == null
                          ? 0
                          : event.cumulativeBytesLoaded /
                              event.expectedTotalBytes!,
                    ),
                  ),
                ),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                pageController: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
              )
            : _buildSingleImageView(files[0]), // 单图模式
      ),
      bottomNavigationBar: _isControlsVisible && isGalleryMode && !_isFullScreen
          ? BottomAppBar(
              color: Colors.black.withOpacity(0.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_currentIndex + 1} / ${files.length}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  // 构建单图查看模式
  Widget _buildSingleImageView(MediaFileInfo file) {
    final bool isGif = _isGifFile(file);

    if (isGif) {
      // GIF文件使用GifPlayer
      return Center(
        child: GifPlayer(
          filePath: file.originalPath,
          fit: BoxFit.contain,
          autoPlay: true,
          filterQuality: FilterQuality.high,
        ),
      );
    } else {
      // 普通图片使用PhotoView
      return PhotoView(
        imageProvider: FileImage(File(file.originalPath)),
        initialScale: PhotoViewComputedScale.contained,
        minScale: PhotoViewComputedScale.contained * 0.8,
        maxScale: PhotoViewComputedScale.covered * 2.0,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        heroAttributes: PhotoViewHeroAttributes(tag: 'media_${file.id}'),
      );
    }
  }
}
