import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:echo_pixel/screens/video_player_page.dart';
import 'package:echo_pixel/screens/webdav_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart' as crypto;
import 'package:shared_preferences/shared_preferences.dart';
// 导入 media_kit 相关包
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/media_index.dart';
import '../services/media_sync_service.dart';
import '../services/webdav_service.dart';

class PhotoGalleryPage extends StatefulWidget {
  const PhotoGalleryPage({super.key});

  @override
  State<PhotoGalleryPage> createState() => _PhotoGalleryPageState();
}

class _PhotoGalleryPageState extends State<PhotoGalleryPage> {
  final WebDavService _webdavService = WebDavService();
  late final MediaSyncService _mediaSyncService;

  // 视频缩略图缓存
  final Map<String, Uint8List?> _videoThumbnailCache = {};

  // 视频播放器管理映射 - 管理每个视频路径对应的播放器实例
  final Map<String, Player> _videoPlayers = {};

  // 同步进度定时器
  Timer? _syncProgressTimer;

  // 是否正在加载
  bool _isLoading = true;

  // 是否正在增量加载更多
  bool _isLoadingMore = false;

  // 是否正在同步
  bool _isSyncing = false;

  // 同步进度
  int _syncProgress = 0;

  // 错误消息
  String? _errorMsg;

  // 同步错误消息
  String? _syncError;

  // 当前正在上传的文件信息
  String? _currentUploadInfo;

  // 按日期排序的媒体索引
  final List<MediaIndex> _sortedIndices = [];

  // 待处理的文件夹和文件
  final List<Directory> _pendingFolders = [];
  final List<File> _pendingFiles = [];

  // 当前加载进度
  double _loadProgress = 0.0;

  // 最大缩略图大小（用于限制加载大图片）
  static const int _maxThumbnailSize = 10 * 1024 * 1024; // 10MB

  // 批量加载大小
  static const int _batchSize = 20;

  @override
  void initState() {
    super.initState();
    _mediaSyncService = MediaSyncService(_webdavService);

    // 尝试初始化WebDAV服务（如果有保存的配置）
    _initializeWebDav();

    _startLoading();
  }

  // 开始加载流程
  Future<void> _startLoading() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMsg = null;
        _loadProgress = 0.0;
      });

      // 初始化媒体同步服务和获取目录
      await _mediaSyncService.initialize();

      // 获取要扫描的目录
      await _initializeScanning();

      // 开始增量加载（第一批）
      await _loadNextBatch();

      // 标记初始加载完成
      setState(() {
        _isLoading = false;
      });

      // 如果还有更多待处理的文件，继续在背景中加载
      if (_pendingFiles.isNotEmpty || _pendingFolders.isNotEmpty) {
        _loadMoreInBackground();
      }
    } catch (e) {
      setState(() {
        _errorMsg = '加载媒体文件时出错: $e';
        _isLoading = false;
      });
    }
  }

  // 初始化扫描，获取要扫描的目录和文件
  Future<void> _initializeScanning() async {
    // 清空旧的待处理队列
    _pendingFolders.clear();
    _pendingFiles.clear();

    // 获取用户目录中的Pictures和Videos文件夹
    final String homeDir = _getUserHomeDirectory();
    final Directory picturesDir = Directory('$homeDir\\Pictures');
    final Directory videosDir = Directory('$homeDir\\Videos');

    // 添加存在的目录到待处理队列
    if (await picturesDir.exists()) {
      _pendingFolders.add(picturesDir);
    }

    if (await videosDir.exists()) {
      _pendingFolders.add(videosDir);
    }

    if (_pendingFolders.isEmpty) {
      throw Exception('未找到Pictures或Videos文件夹');
    }
  }

  // 获取用户主目录
  String _getUserHomeDirectory() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '';
    } else {
      return Platform.environment['HOME'] ?? '';
    }
  }

  // 加载下一批文件
  Future<void> _loadNextBatch() async {
    // 如果没有待处理项目，直接返回
    if (_pendingFolders.isEmpty && _pendingFiles.isEmpty) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      // 处理待处理的文件
      final filesToProcess = <File>[];

      // 首先填充文件队列
      while (_pendingFolders.isNotEmpty && filesToProcess.length < _batchSize) {
        final currentDir = _pendingFolders.removeAt(0);
        try {
          final dirContents = await currentDir.list().toList();

          // 将子目录添加到待处理目录队列
          for (final entity in dirContents) {
            if (entity is Directory) {
              _pendingFolders.add(entity);
            } else if (entity is File) {
              // 检查是否为媒体文件
              final extension = path.extension(entity.path).toLowerCase();
              final ext = extension.replaceAll('.', '');
              if (MediaFileInfo.isImageExtension(ext) ||
                  MediaFileInfo.isVideoExtension(ext)) {
                filesToProcess.add(entity);
                if (filesToProcess.length >= _batchSize) break;
              }
            }
          }
        } catch (e) {
          debugPrint('无法处理目录 ${currentDir.path}: $e');
        }
      }

      // 如果文件队列不足，从待处理文件中补充
      while (_pendingFiles.isNotEmpty && filesToProcess.length < _batchSize) {
        filesToProcess.add(_pendingFiles.removeAt(0));
      }

      // 处理这批文件
      for (final file in filesToProcess) {
        await _processMediaFile(file);
      }

      // 重新组织和排序索引
      _reorganizeIndices();
    } catch (e) {
      debugPrint('批量加载错误: $e');
    } finally {
      setState(() {
        _isLoadingMore = false;
        // 更新总加载进度
        final totalPending =
            _pendingFiles.length + _pendingFolders.length * 10; // 估算值
        final totalProcessed = 100 - totalPending.clamp(0, 100);
        _loadProgress = totalProcessed / 100;
      });
    }
  }

  // 在后台继续加载更多文件
  Future<void> _loadMoreInBackground() async {
    // 如果已经没有待处理项，或者已经在加载中，直接返回
    if ((_pendingFolders.isEmpty && _pendingFiles.isEmpty) || _isLoadingMore) {
      return;
    }

    // 加载下一批
    await _loadNextBatch();

    // 如果还有更多，延迟一小段时间后继续加载（给UI留出响应时间）
    if (_pendingFolders.isNotEmpty || _pendingFiles.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 200));
      // 递归调用继续加载
      _loadMoreInBackground();
    }
  }

  // 处理单个媒体文件
  Future<void> _processMediaFile(File file) async {
    try {
      final filePath = file.path;
      final fileSize = await file.length();

      final String fileName = path.basename(filePath);
      final String nameWithoutExt = path.basenameWithoutExtension(filePath);
      final String extension =
          path.extension(filePath).replaceAll('.', '').toLowerCase();

      // 获取文件类型
      final MediaType mediaType = MediaFileInfo.inferTypeFromPath(filePath);

      // 如果不是受支持的媒体类型，跳过
      if (mediaType == MediaType.unknown) {
        return;
      }

      // 获取文件基本信息
      final FileStat stat = await file.stat();

      // 使用文件的修改时间作为创建时间
      final DateTime createdAt = stat.modified;
      final DateTime modifiedAt = stat.modified;

      // 对于小文件，读取内容生成哈希；对于大文件，使用路径和大小的组合作为ID
      String mediaId;
      if (fileSize < 50 * 1024 * 1024) {
        // 50MB以下的文件
        final bytes = await file.readAsBytes();
        final digest = await compute(_computeHash, bytes);
        mediaId = digest;
      } else {
        // 对于大文件，使用路径+大小+修改时间的哈希作为ID
        final idSource =
            '$filePath:$fileSize:${modifiedAt.millisecondsSinceEpoch}';
        mediaId = await compute(_computeStringHash, idSource);
      }

      // 获取日期路径
      final String datePath = MediaIndex.getDatePath(createdAt);

      // 创建媒体信息对象
      final MediaFileInfo mediaInfo = MediaFileInfo(
        id: mediaId,
        originalPath: filePath,
        name: nameWithoutExt,
        extension: extension,
        size: fileSize,
        type: mediaType,
        createdAt: createdAt,
        modifiedAt: modifiedAt,
      );

      // 将媒体信息添加到按日期索引的集合中
      if (mounted) {
        setState(() {
          // 将媒体文件添加到日期索引中
          final existingIndex = _sortedIndices.firstWhereOrNull(
            (index) => index.datePath == datePath,
          );

          if (existingIndex != null) {
            // 检查是否已经存在相同ID的媒体
            final exists = existingIndex.mediaFiles.any(
              (file) => file.id == mediaId,
            );
            if (!exists) {
              existingIndex.mediaFiles.add(mediaInfo);
            }
          } else {
            // 创建新的日期索引
            final newIndex = MediaIndex(
              datePath: datePath,
              mediaFiles: [mediaInfo],
            );
            _sortedIndices.add(newIndex);
          }
        });
      }
    } catch (e) {
      debugPrint('处理媒体文件错误: ${file.path}, $e');
    }
  }

  // 静态方法用于在isolate中计算哈希值
  static String _computeHash(Uint8List bytes) {
    final digest = crypto.sha256.convert(bytes);
    return digest.toString();
  }

  // 静态方法用于在isolate中计算字符串的哈希值
  static String _computeStringHash(String input) {
    final bytes = utf8.encode(input);
    final digest = crypto.sha256.convert(bytes);
    return digest.toString();
  }

  // 重新组织和排序索引
  void _reorganizeIndices() {
    if (!mounted) return;

    setState(() {
      // 按日期排序（最新的在前面）
      _sortedIndices.sort((a, b) {
        final dateA = MediaIndex.parseDatePath(a.datePath);
        final dateB = MediaIndex.parseDatePath(b.datePath);
        if (dateA == null || dateB == null) return 0;
        return dateB.compareTo(dateA); // 降序
      });

      // 对每个日期中的文件进行排序
      for (final index in _sortedIndices) {
        index.mediaFiles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    });
  }

  // 格式化文件大小
  String _formatSize(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size > 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)}${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('照片库'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // 同步按钮
          IconButton(
            tooltip: '同步媒体文件',
            onPressed: _isSyncing ? null : _syncWithWebDav,
            icon: _isSyncing
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      Text(
                        '$_syncProgress%',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : const Icon(Icons.sync),
          ),
          // WebDAV设置按钮
          IconButton(
            tooltip: 'WebDAV设置',
            onPressed: _openWebDavSettings,
            icon: Icon(
              Icons.cloud,
              color: _webdavService.isConnected ? Colors.lightBlueAccent : null,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _startLoading();
                  break;
                case 'settings':
                  // TODO: 添加应用设置页面
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('刷新'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings),
                    SizedBox(width: 8),
                    Text('设置'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  // 构建主体内容
  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('正在加载媒体文件...', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              '请稍候，这可能需要一些时间',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMsg != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMsg!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _startLoading, child: const Text('重试')),
          ],
        ),
      );
    }

    if (_sortedIndices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_album_outlined,
              size: 64,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            const Text(
              '没有找到照片',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text('添加照片或设置WebDAV同步', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startLoading,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // 主要内容
        RefreshIndicator(
          onRefresh: _startLoading,
          child: ListView.builder(
            itemCount: _sortedIndices.length,
            itemBuilder: (context, index) {
              final mediaIndex = _sortedIndices[index];
              return _buildDateSection(mediaIndex);
            },
          ),
        ),

        // 加载更多指示器
        if (_isLoadingMore)
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: _loadProgress,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('加载更多...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),

        // 同步进度显示
        if (_isSyncing)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '同步中 $_syncProgress%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    if (_currentUploadInfo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _currentUploadInfo!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_syncError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '错误: $_syncError',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // 构建日期分组区块
  Widget _buildDateSection(MediaIndex mediaIndex) {
    final sortedFiles = mediaIndex.mediaFiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 日期标题
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                mediaIndex.readableDate,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${sortedFiles.length})',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
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
          itemCount: sortedFiles.length,
          itemBuilder: (context, index) {
            final mediaFile = sortedFiles[index];
            return _buildMediaThumbnail(mediaFile);
          },
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  // 构建媒体文件缩略图
  Widget _buildMediaThumbnail(MediaFileInfo mediaFile) {
    // 使用一个唯一key确保当媒体文件更新时也能正确更新UI
    return Card(
      key: ValueKey('thumb_${mediaFile.id}'),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 缩略图/照片(使用Hero动画支持平滑转场)
          Hero(
            tag: 'media_${mediaFile.id}',
            child: _buildMediaPreview(mediaFile),
          ),

          // 视频标志
          if (mediaFile.type == MediaType.video)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),

          // 文件大小标签（对于大文件显示）
          if (mediaFile.size > _maxThumbnailSize)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatSize(mediaFile.size),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),

          // 云同步状态
          if (mediaFile.cloudPath != null)
            Positioned(
              right: 4,
              top: 4,
              child: Icon(
                mediaFile.isSynced ? Icons.cloud_done : Icons.cloud_upload,
                color: Colors.white,
                size: 16,
                shadows: [const Shadow(color: Colors.black54, blurRadius: 3)],
              ),
            ),

          // 点击事件
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _openMediaDetail(mediaFile);
              },
            ),
          ),
        ],
      ),
    );
  }

  // 构建媒体预览
  Widget _buildMediaPreview(MediaFileInfo mediaFile) {
    // 对于Web平台，暂不支持本地文件访问
    if (kIsWeb) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.image_not_supported),
      );
    }

    // 检查文件是否存在
    final file = File(mediaFile.originalPath);
    if (!file.existsSync()) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image),
      );
    }

    try {
      if (mediaFile.type == MediaType.image) {
        // 对于小图片，使用 Image.file 直接加载
        // 对于大图片，显示占位符
        if (mediaFile.size > _maxThumbnailSize) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.photo_size_select_actual,
                      size: 32,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '大图片',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        } else {
          // 小图片使用懒加载
          return Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: 300, // 限制内存中缓存的图片大小
            cacheHeight: 300,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image),
              );
            },
          );
        }
      } else if (mediaFile.type == MediaType.video) {
        // 视频预览 - 使用懒加载视频缩略图组件
        return LazyLoadingVideoThumbnail(videoPath: mediaFile.originalPath);
      } else {
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.help_outline),
        );
      }
    } catch (e) {
      return Container(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.2),
        child: const Icon(Icons.error_outline),
      );
    }
  }

  // 打开媒体详情
  void _openMediaDetail(MediaFileInfo mediaFile) {
    // 对于大文件特殊处理
    if (mediaFile.size > 100 * 1024 * 1024 &&
        mediaFile.type == MediaType.image) {
      // 大于100MB的图片文件，提示用户使用系统应用打开
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('文件过大 (${_formatSize(mediaFile.size)})，请使用系统应用打开'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // 根据媒体类型打开不同页面
    if (mediaFile.type == MediaType.video) {
      // 视频文件 - 使用 VideoPlayerPage
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerPage(mediaFile: mediaFile),
        ),
      );
    } else if (mediaFile.type == MediaType.image) {
      // 图片文件 - 后续可以实现图片查看器
      // TODO: 实现图片查看器
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('打开图片: ${mediaFile.fileName}'),
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      // 未知类型
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('不支持的文件类型: ${mediaFile.extension}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    // 清除视频缩略图内存缓存
    _videoThumbnailCache.clear();

    // 释放所有视频播放器资源
    for (final player in _videoPlayers.values) {
      player.dispose();
    }
    _videoPlayers.clear();

    super.dispose();
  }

  // 初始化WebDAV服务（使用保存的配置）
  Future<void> _initializeWebDav() async {
    try {
      // 从本地存储读取WebDAV配置
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? serverUrl = prefs.getString('webdav_server');
      final String? username = prefs.getString('webdav_username');
      final String? password = prefs.getString('webdav_password');
      final String uploadPath = prefs.getString('webdav_upload_path') ?? '/';

      // 如果有保存的配置，尝试连接
      if (serverUrl != null && username != null && password != null) {
        final bool connected = await _webdavService.initialize(serverUrl,
            username: username, password: password, uploadRootPath: uploadPath);

        if (connected) {
          debugPrint('WebDAV服务已自动连接');
        } else {
          debugPrint('无法使用保存的凭据连接到WebDAV服务');
        }
      }
    } catch (e) {
      debugPrint('初始化WebDAV服务错误: $e');
    }
  }

  // 执行WebDAV同步
  Future<void> _syncWithWebDav() async {
    // 如果WebDAV未连接，提示用户去设置
    if (!_webdavService.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('请先设置WebDAV连接'),
            action: SnackBarAction(
              label: '去设置',
              onPressed: () => _openWebDavSettings(),
            ),
          ),
        );
      }
      return;
    }

    // 如果已经在同步中，不执行
    if (_isSyncing) return;

    // 开始同步
    setState(() {
      _isSyncing = true;
      _syncProgress = 0;
      _syncError = null;
      _currentUploadInfo = null;
    });

    // 启动进度更新定时器 - 每500毫秒更新一次进度
    _syncProgressTimer?.cancel(); // 确保旧的定时器已取消
    _syncProgressTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted && _isSyncing) {
        setState(() {
          _syncProgress = _mediaSyncService.syncProgress;
        });
      } else {
        timer.cancel(); // 如果不再同步或者组件已销毁，取消定时器
      }
    });

    try {
      // 确保媒体服务已初始化
      await _mediaSyncService.initialize();

      // 设置同步状态信息更新回调
      _mediaSyncService.onSyncStatusUpdate = (statusInfo) {
        if (mounted) {
          setState(() {
            _currentUploadInfo = statusInfo;
          });
        }
      };

      // 先扫描本地媒体
      await _mediaSyncService.scanLocalMedia();

      // 执行同步
      final bool success = await _mediaSyncService.syncWithCloud();

      // 同步完成
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgress = _mediaSyncService.syncProgress;
          _syncError = _mediaSyncService.syncError;
          _currentUploadInfo = null;
        });

        // 取消进度更新定时器
        _syncProgressTimer?.cancel();
        _syncProgressTimer = null;

        // 显示结果提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '同步完成' : '同步失败: ${_syncError ?? "未知错误"}'),
            duration: const Duration(seconds: 3),
          ),
        );

        // 如果同步成功，刷新媒体列表
        if (success) {
          _startLoading();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncError = e.toString();
          _currentUploadInfo = null;
        });

        // 取消进度更新定时器
        _syncProgressTimer?.cancel();
        _syncProgressTimer = null;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步过程出错: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 打开WebDAV设置页面
  void _openWebDavSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WebDavSettingsScreen(),
      ),
    );

    // 如果设置页面返回了结果，刷新WebDAV状态
    if (result == true) {
      // 重新初始化WebDAV服务
      await _initializeWebDav();
    }
  }
}

// 懒加载视频缩略图组件 - 使用 media_kit 的 Video 组件
class LazyLoadingVideoThumbnail extends StatefulWidget {
  final String videoPath;

  const LazyLoadingVideoThumbnail({
    required this.videoPath,
    super.key,
  });

  @override
  State<LazyLoadingVideoThumbnail> createState() =>
      _LazyLoadingVideoThumbnailState();
}

class _LazyLoadingVideoThumbnailState extends State<LazyLoadingVideoThumbnail> {
  // 创建一个Player实例控制播放
  late final Player _player;
  // 创建VideoController处理来自Player的视频输出
  late final VideoController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      // 创建Player实例
      _player = Player();
      // 创建并附加VideoController(这是解决缩略图问题的关键)
      _controller = VideoController(_player);

      // 打开视频文件，但不播放
      await _player.open(Media(widget.videoPath), play: false);
      // 跳到视频开始位置以加载第一帧
      await _player.seek(const Duration(milliseconds: 100));
      // 暂停播放，确保只显示静态帧
      await _player.pause();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('初始化视频缩略图失败: ${widget.videoPath} - $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      // 显示错误占位符
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Icon(Icons.error_outline, size: 32),
        ),
      );
    }

    if (!_isInitialized) {
      // 显示加载占位符
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // 显示视频的第一帧
    return Video(
      controller: _controller,
      fit: BoxFit.cover,
      controls: NoVideoControls, // 不显示控件
      wakelock: false, // 不保持屏幕常亮
    );
  }

  @override
  void dispose() {
    // 释放资源
    _player.dispose();
    super.dispose();
  }
}
