import 'dart:io';
import 'package:flutter/material.dart';
import '../models/media_index.dart';
import '../services/album_service.dart';
import 'photo_selector_page.dart';

class CreateAlbumPage extends StatefulWidget {
  final Map<String, MediaIndex> mediaIndices;

  const CreateAlbumPage({
    super.key,
    required this.mediaIndices,
  });

  @override
  State<CreateAlbumPage> createState() => _CreateAlbumPageState();
}

class _CreateAlbumPageState extends State<CreateAlbumPage> {
  final AlbumService _albumService = AlbumService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  List<String> _selectedPhotoIds = [];
  String? _coverPhotoId;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // 选择照片
  void _selectPhotos() async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoSelectorPage(
          mediaIndices: widget.mediaIndices,
          initialSelection: _selectedPhotoIds,
          allowMultiple: true,
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _selectedPhotoIds = result;
        // 如果未设置封面，将第一张照片设为封面
        _coverPhotoId ??= result.first;
      });
    }
  }

  // 创建相册
  void _createAlbum() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入相册名称')),
      );
      return;
    }

    // 开始创建
    setState(() {
      _isCreating = true;
    });

    try {
      await _albumService.createAlbum(
        name: name,
        description: _descriptionController.text.trim(),
        photoIds: _selectedPhotoIds, // 修正参数名
        coverPhotoId: _coverPhotoId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('相册创建成功')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建相册失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  // 查找指定ID的照片
  MediaFileInfo? _findPhotoById(String photoId) {
    for (final index in widget.mediaIndices.values) {
      for (final media in index.mediaFiles) {
        if (media.id == photoId) {
          return media;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // 计算选中的照片数量
    final selectedPhotoCount = _selectedPhotoIds.length;

    // 获取封面照片（如果有）
    final coverPhoto =
        _coverPhotoId != null ? _findPhotoById(_coverPhotoId!) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('创建相册'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isCreating)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _createAlbum,
              child: const Text('创建'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 相册封面预览
            Card(
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: coverPhoto != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(coverPhoto.originalPath),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(Icons.broken_image, size: 48),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0),
                                  Colors.black.withOpacity(0.5),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 16,
                            left: 16,
                            child: Text(
                              '封面预览',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.5),
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: const Center(
                          child: Icon(Icons.photo_album, size: 48),
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 24),

            // 相册名称
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '相册名称',
                hintText: '输入相册名称',
                prefixIcon: Icon(Icons.title),
                border: OutlineInputBorder(),
              ),
              maxLength: 50,
            ),

            const SizedBox(height: 16),

            // 相册描述
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '相册描述（可选）',
                hintText: '输入相册描述',
                prefixIcon: Icon(Icons.description),
                border: OutlineInputBorder(),
              ),
              maxLength: 200,
              maxLines: 3,
            ),

            const SizedBox(height: 24),

            // 选择照片
            Card(
              child: InkWell(
                onTap: _selectPhotos,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_photo_alternate,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '选择照片',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              selectedPhotoCount > 0
                                  ? '已选择 $selectedPhotoCount 张照片'
                                  : '向相册添加照片',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),

            // 如果选择了照片，显示照片网格
            if (_selectedPhotoIds.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                '已选择照片',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount:
                    _selectedPhotoIds.length > 6 ? 6 : _selectedPhotoIds.length,
                itemBuilder: (context, index) {
                  final photoId = _selectedPhotoIds[index];
                  final photo = _findPhotoById(photoId);

                  if (photo == null) {
                    return Container(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image),
                    );
                  }

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(photo.originalPath),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
                      if (index == 5 && _selectedPhotoIds.length > 6)
                        Container(
                          color: Colors.black.withOpacity(0.5),
                          child: Center(
                            child: Text(
                              '+${_selectedPhotoIds.length - 6}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
