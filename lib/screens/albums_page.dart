import 'dart:io';
import 'package:flutter/material.dart';
import '../models/photo_model.dart';
import '../models/media_index.dart';
import '../services/album_service.dart';
import '../services/media_sync_service.dart'; // 添加 MediaSyncService
import '../services/webdav_service.dart'; // 添加 WebDavService
import 'package:provider/provider.dart'; // 添加 Provider
import 'album_detail_page.dart';
import 'create_album_page.dart';

class AlbumsPage extends StatefulWidget {
  final Map<String, MediaIndex> mediaIndices;

  const AlbumsPage({
    super.key,
    required this.mediaIndices,
  });

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage>
    with SingleTickerProviderStateMixin {
  final AlbumService _albumService = AlbumService();
  bool _isLoading = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshAlbums();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 刷新相册列表
  Future<void> _refreshAlbums() async {
    setState(() {
      _isLoading = true;
    });

    await _albumService.loadAlbums();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 创建新相册
  void _createNewAlbum() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CreateAlbumPage(mediaIndices: widget.mediaIndices),
      ),
    ).then((_) {
      // 刷新页面以显示新相册
      _refreshAlbums();
    });
  }

  // 打开相册详情
  void _openAlbumDetail(Album album) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlbumDetailPage(
          albumId: album.id,
          mediaIndices: widget.mediaIndices,
        ),
      ),
    ).then((_) {
      // 刷新页面以更新相册状态
      _refreshAlbums();
    });
  }

  // 删除相册
  void _deleteAlbum(Album album) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除相册'),
        content: Text('确定要删除相册"${album.name}"吗？这不会删除相册中的照片。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _albumService.deleteAlbum(album.id);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已删除相册"${album.name}"')),
                );
                _refreshAlbums();
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // 查找相册封面照片
  MediaFileInfo? _findCoverPhoto(Album album) {
    if (album.coverPhotoId == null) return null;

    for (final index in widget.mediaIndices.values) {
      for (final media in index.mediaFiles) {
        if (media.id == album.coverPhotoId) {
          return media;
        }
      }
    }

    return null;
  }

  // 构建相册列表项
  Widget _buildAlbumItem(Album album) {
    final coverPhoto = _findCoverPhoto(album);
    final photoCount = album.photoIds.length;

    // 云相册同步状态标签
    Widget? syncStatusBadge;
    if (album.albumType == AlbumType.cloud) {
      if (!album.isSynced) {
        syncStatusBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.sync,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              const Text(
                '待同步',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }

      // 显示待下载照片计数
      if (album.pendingCloudPhotosCount != null &&
          album.pendingCloudPhotosCount! > 0) {
        syncStatusBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_download,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                '${album.pendingCloudPhotosCount} 张待下载',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () => _openAlbumDetail(album),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图像
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: coverPhoto != null
                      ? Image.file(
                          File(coverPhoto.originalPath),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: const Icon(Icons.broken_image, size: 48),
                          ),
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

                // 云相册图标
                if (album.albumType == AlbumType.cloud)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),

            // 相册信息
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                album.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (album.albumType == AlbumType.cloud &&
                                syncStatusBadge != null) ...[
                              const SizedBox(width: 8),
                              syncStatusBadge,
                            ],
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'delete') {
                            _deleteAlbum(album);
                          } else if (value == 'sync') {
                            _syncCloudAlbum(album);
                          }
                        },
                        itemBuilder: (context) => [
                          if (album.albumType == AlbumType.cloud &&
                              !album.isSynced)
                            const PopupMenuItem<String>(
                              value: 'sync',
                              child: Text('立即同步'),
                            ),
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('删除'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$photoCount 张照片',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (album.description != null &&
                      album.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      album.description!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('合集'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '本地相册'),
            Tab(text: '云相册'),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: _albumService,
        builder: (context, _) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // 本地相册标签页
              _buildAlbumsList(_albumService.localAlbums),

              // 云相册标签页
              _buildAlbumsList(_albumService.cloudAlbums),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewAlbum,
        tooltip: '创建相册',
        heroTag: 'albums_page_fab',
        child: const Icon(Icons.add),
      ),
    );
  }

  // 构建相册列表
  Widget _buildAlbumsList(List<Album> albums) {
    if (albums.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_album,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withAlpha(
                  (Theme.of(context).colorScheme.primary.alpha * 0.5).toInt()),
            ),
            const SizedBox(height: 16),
            Text(
              _tabController.index == 0 ? '暂无本地相册' : '暂无云相册',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(_tabController.index == 0
                ? '点击下方按钮创建新相册'
                : '连接云存储并同步照片后会自动创建云相册'),
            const SizedBox(height: 16),
            if (_tabController.index == 0)
              ElevatedButton.icon(
                onPressed: _createNewAlbum,
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('创建相册'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return _buildAlbumItem(album);
      },
    );
  }

  // 同步云相册
  Future<void> _syncCloudAlbum(Album album) async {
    if (album.albumType != AlbumType.cloud) return;

    try {
      // 显示加载中对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('同步云相册中...'),
              ],
            ),
          );
        },
      );

      // 获取 WebDavService 实例
      final webDavService = await _getWebDavService();
      if (webDavService == null) {
        if (mounted) {
          Navigator.pop(context); // 关闭加载对话框
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法获取云存储服务，请检查连接设置')),
          );
        }
        return;
      }

      // 创建 MediaSyncService 实例并同步云相册
      final mediaSyncService = MediaSyncService(webDavService);
      await mediaSyncService.initialize();

      // 标记相册为已同步
      await _albumService.updateCloudSyncStatus(album.id, true);

      // 关闭对话框
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('云相册"${album.name}"已同步')),
        );

        // 刷新相册列表
        _refreshAlbums();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步云相册失败: $e')),
        );
      }
    }
  }

  // 获取 WebDavService 实例
  Future<WebDavService?> _getWebDavService() async {
    try {
      final webDavService = Provider.of<WebDavService>(context, listen: false);
      return webDavService;
    } catch (e) {
      debugPrint('无法通过Provider获取WebDavService: $e');

      // 尝试手动创建新实例
      try {
        final webDavService = WebDavService();
        // 注意：这里假设初始化方法已经在应用启动时被调用
        // 如果没有，可能需要添加初始化逻辑
        return webDavService;
      } catch (e) {
        debugPrint('创建WebDavService失败: $e');
        return null;
      }
    }
  }
}
