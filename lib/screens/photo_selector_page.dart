import 'dart:io';
import 'package:flutter/material.dart';
import '../models/media_index.dart';

class PhotoSelectorPage extends StatefulWidget {
  final Map<String, MediaIndex> mediaIndices;
  final List<String> initialSelection;
  final bool allowMultiple;

  const PhotoSelectorPage({
    super.key,
    required this.mediaIndices,
    this.initialSelection = const [],
    this.allowMultiple = true,
  });

  @override
  State<PhotoSelectorPage> createState() => _PhotoSelectorPageState();
}

class _PhotoSelectorPageState extends State<PhotoSelectorPage> {
  late Set<String> _selectedPhotoIds;

  @override
  void initState() {
    super.initState();
    _selectedPhotoIds = Set<String>.from(widget.initialSelection);
  }

  // 切换照片选择状态
  void _togglePhotoSelection(String photoId) {
    setState(() {
      if (_selectedPhotoIds.contains(photoId)) {
        _selectedPhotoIds.remove(photoId);
      } else {
        if (!widget.allowMultiple) {
          _selectedPhotoIds.clear();
        }
        _selectedPhotoIds.add(photoId);
      }
    });
  }

  // 完成选择
  void _completeSelection() {
    Navigator.of(context).pop(_selectedPhotoIds.toList());
  }

  // 构建所有照片的列表（按日期分组）
  List<MediaIndex> _getSortedIndices() {
    final indices = widget.mediaIndices.values.toList();

    // 排序索引（最新的日期在前面）
    indices.sort((a, b) {
      final dateA = MediaIndex.parseDatePath(a.datePath);
      final dateB = MediaIndex.parseDatePath(b.datePath);
      if (dateA == null || dateB == null) return 0;
      return dateB.compareTo(dateA);
    });

    return indices;
  }

  @override
  Widget build(BuildContext context) {
    final sortedIndices = _getSortedIndices();

    // 检查是否有可用的图片
    bool hasImages = false;
    for (final index in sortedIndices) {
      if (index.mediaFiles.any((file) => file.type == MediaType.image)) {
        hasImages = true;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择照片'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          TextButton.icon(
            onPressed: _completeSelection,
            icon: const Icon(Icons.check),
            label: Text('完成(${_selectedPhotoIds.length})'),
          ),
        ],
      ),
      body: !hasImages
          ? const Center(child: Text('没有可选择的照片'))
          : ListView.builder(
              itemCount: sortedIndices.length,
              itemBuilder: (context, index) {
                final mediaIndex = sortedIndices[index];
                return _buildDateSection(mediaIndex);
              },
            ),
    );
  }

  // 构建日期分组区块
  Widget _buildDateSection(MediaIndex mediaIndex) {
    // 只显示图片类型的文件
    final imageFiles = mediaIndex.mediaFiles
        .where((file) => file.type == MediaType.image)
        .toList();

    // 如果此日期没有图片，不显示该分组
    if (imageFiles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 日期标题
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            mediaIndex.readableDate,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        // 照片网格
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1.0,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: imageFiles.length,
          itemBuilder: (context, index) {
            final mediaFile = imageFiles[index];
            return _buildPhotoThumbnail(mediaFile);
          },
        ),
      ],
    );
  }

  // 构建照片缩略图
  Widget _buildPhotoThumbnail(MediaFileInfo mediaFile) {
    final isSelected = _selectedPhotoIds.contains(mediaFile.id);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 照片缩略图
        InkWell(
          onTap: () => _togglePhotoSelection(mediaFile.id),
          child: Image.file(
            File(mediaFile.originalPath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image),
            ),
          ),
        ),

        // 选择指示器
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surface.withOpacity(0.7),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: isSelected
                ? const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 16,
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
