import 'dart:io';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../models/photo_model.dart';
import '../models/media_index.dart';
import '../services/album_service.dart';
import '../services/media_cache_service.dart';
import 'photo_selector_page.dart';
import 'image_viewer_page.dart';

class AlbumDetailPage extends StatefulWidget {
  final String albumId;
  final Map<String, MediaIndex> mediaIndices;

  const AlbumDetailPage({
    super.key,
    required this.albumId,
    required this.mediaIndices,
  });

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  final AlbumService _albumService = AlbumService();

  Album? _album;
  List<MediaFileInfo> _mediaFiles = [];
  bool _isLoading = true;
  bool _isSelectionMode = false;
  final Set<String> _selectedPhotoIds = {};

  final TextEditingController _titleController = TextEditingController();
  bool _isEditingTitle = false;

  @override
  void initState() {
    super.initState();
    _loadAlbumDetails();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  // 加载相册详情
  Future<void> _loadAlbumDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _album = _albumService.getAlbumById(widget.albumId);

      if (_album == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('相册不存在')),
          );

          Navigator.pop(context);
        }
        return;
      }

      _mediaFiles = _findMediaFiles(_album!.photoIds);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _titleController.text = _album!.name;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载相册失败: $e')),
        );
      }
    }
  }

  // 查找媒体文件
  List<MediaFileInfo> _findMediaFiles(List<String> photoIds) {
    final List<MediaFileInfo> mediaFiles = [];
    final Set<String> photoIdSet = Set<String>.from(photoIds);

    // 遍历所有MediaIndex查找匹配的媒体文件
    for (final index in widget.mediaIndices.values) {
      for (final file in index.mediaFiles) {
        // 只添加图片类型文件
        if (photoIdSet.contains(file.id) && file.type == MediaType.image) {
          mediaFiles.add(file);
        }
      }
    }

    return mediaFiles;
  }

  // 更新相册标题
  Future<void> _updateAlbumTitle() async {
    final newTitle = _titleController.text.trim();

    if (newTitle.isEmpty || _album == null) {
      _titleController.text = _album?.name ?? '';
      setState(() {
        _isEditingTitle = false;
      });
      return;
    }

    if (newTitle == _album!.name) {
      setState(() {
        _isEditingTitle = false;
      });
      return;
    }

    try {
      final updatedAlbum = _album!.copyWith(name: newTitle);
      await _albumService.updateAlbum(updatedAlbum);

      if (mounted) {
        setState(() {
          _album = updatedAlbum;
          _isEditingTitle = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('相册名称已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新相册名称失败: $e')),
        );
      }
    }
  }

  // 打开照片选择器添加照片
  Future<void> _openPhotoSelector() async {
    if (_album == null) return;

    // 获取当前相册中的照片ID列表
    final currentPhotoIds = _album!.photoIds;

    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoSelectorPage(
          mediaIndices: widget.mediaIndices,
          initialSelection: const [],
          allowMultiple: true,
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await _albumService.addPhotosToAlbum(_album!.id, result);

        // 重新加载相册
        _loadAlbumDetails();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已添加 ${result.length} 张照片')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('添加照片失败: $e')),
          );
        }
      }
    }
  }

  // 切换照片选择
  void _toggleSelectPhoto(String photoId) {
    setState(() {
      if (_selectedPhotoIds.contains(photoId)) {
        _selectedPhotoIds.remove(photoId);
      } else {
        _selectedPhotoIds.add(photoId);
      }
    });
  }

  // 移除选中的照片
  Future<void> _removeSelectedPhotos() async {
    if (_album == null || _selectedPhotoIds.isEmpty) return;

    try {
      await _albumService.removePhotosFromAlbum(
          _album!.id, _selectedPhotoIds.toList());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已从相册移除 ${_selectedPhotoIds.length} 张照片')),
        );

        // 退出选择模式
        setState(() {
          _isSelectionMode = false;
          _selectedPhotoIds.clear();
        });

        // 重新加载相册
        _loadAlbumDetails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移除照片失败: $e')),
        );
      }
    }
  }

  // 设置相册封面
  Future<void> _setAlbumCover(String photoId) async {
    if (_album == null) return;

    try {
      await _albumService.setAlbumCover(_album!.id, photoId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已更新相册封面')),
        );

        // 重新加载相册
        _loadAlbumDetails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置相册封面失败: $e')),
        );
      }
    }
  }

  // 删除相册
  Future<void> _deleteAlbum() async {
    if (_album == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除相册'),
        content: Text('确定要删除"${_album!.name}"相册吗？相册中的照片不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _albumService.deleteAlbum(_album!.id);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已删除"${_album!.name}"相册')),
                  );
                  Navigator.pop(context);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('删除相册失败: $e')),
                  );
                }
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // 打开图片查看器
  void _openImageViewer(MediaFileInfo mediaFile, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageViewerPage(
          mediaFile: mediaFile,
          mediaFiles: _mediaFiles,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('相册详情')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_album == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('相册详情')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64),
              const SizedBox(height: 16),
              const Text('无法加载相册数据', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadAlbumDetails,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _isEditingTitle
            ? TextField(
                controller: _titleController,
                autofocus: true,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '输入相册名称',
                ),
                onSubmitted: (_) => _updateAlbumTitle(),
              )
            : Text(_album!.name),
        actions: _buildAppBarActions(),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _buildBody(),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton(
              onPressed: _openPhotoSelector,
              tooltip: '添加照片',
              child: const Icon(Icons.add_photo_alternate),
            ),
    );
  }

  // 构建AppBar操作按钮
  List<Widget> _buildAppBarActions() {
    if (_isSelectionMode) {
      return [
        IconButton(
          icon: const Icon(Icons.delete),
          tooltip: '从相册中移除',
          onPressed: _selectedPhotoIds.isEmpty ? null : _removeSelectedPhotos,
        ),
        IconButton(
          icon: const Icon(Icons.cancel),
          tooltip: '取消选择',
          onPressed: () {
            setState(() {
              _isSelectionMode = false;
              _selectedPhotoIds.clear();
            });
          },
        ),
      ];
    } else {
      return [
        // 编辑标题图标
        IconButton(
          icon: const Icon(Icons.edit),
          tooltip: '编辑相册名称',
          onPressed: () {
            setState(() {
              _isEditingTitle = true;
            });
          },
        ),
        // 多选模式图标
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: '选择照片',
          onPressed: () {
            setState(() {
              _isSelectionMode = true;
            });
          },
        ),
        // 更多操作菜单
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') {
              _deleteAlbum();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: 'delete',
              child: Text('删除相册'),
            ),
          ],
        ),
      ];
    }
  }

  // 构建主体内容
  Widget _buildBody() {
    if (_mediaFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              '相册中没有照片',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text('点击右下角按钮添加照片'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _openPhotoSelector,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('添加照片'),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _mediaFiles.length,
      itemBuilder: (context, index) {
        final mediaFile = _mediaFiles[index];
        return _buildPhotoItem(mediaFile, index);
      },
    );
  }

  // 构建照片项
  Widget _buildPhotoItem(MediaFileInfo mediaFile, int index) {
    final isSelected = _selectedPhotoIds.contains(mediaFile.id);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 照片
        Card(
          clipBehavior: Clip.antiAlias,
          elevation: isSelected ? 5 : 2,
          child: InkWell(
            onTap: _isSelectionMode
                ? () => _toggleSelectPhoto(mediaFile.id)
                : () => _openImageViewer(mediaFile, index),
            onLongPress: () {
              if (!_isSelectionMode) {
                setState(() {
                  _isSelectionMode = true;
                  _selectedPhotoIds.add(mediaFile.id);
                });
              }
            },
            child: _buildMediaPreview(mediaFile),
          ),
        ),

        // 选择指示器
        if (_isSelectionMode)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSelected ? Icons.check : Icons.circle_outlined,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),

        // 封面标志
        if (mediaFile.id == _album!.coverPhotoId)
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text(
                    '封面',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 设置为封面按钮
        if (_isSelectionMode &&
            isSelected &&
            mediaFile.id != _album!.coverPhotoId)
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: IconButton(
                icon: const Icon(Icons.star_border, size: 16),
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                tooltip: '设为封面',
                onPressed: () => _setAlbumCover(mediaFile.id),
              ),
            ),
          ),
      ],
    );
  }

  // 构建媒体预览
  Widget _buildMediaPreview(MediaFileInfo mediaFile) {
    try {
      if (mediaFile.type == MediaType.image) {
        final file = File(mediaFile.originalPath);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image),
              );
            },
          );
        }
      } else if (mediaFile.type == MediaType.video) {
        // 视频缩略图处理逻辑
        return Container(
          color: Colors.black,
          child: const Center(
            child: Icon(Icons.play_arrow, color: Colors.white, size: 32),
          ),
        );
      }
    } catch (e) {
      // 错误处理
    }

    // 默认占位图
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.image),
    );
  }
}
