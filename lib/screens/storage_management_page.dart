import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class StorageManagementPage extends StatefulWidget {
  const StorageManagementPage({super.key});

  @override
  State<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends State<StorageManagementPage> {
  bool _isLoading = true;
  int _totalStorageUsed = 0;
  int _thumbnailCacheSize = 0;
  int _mediaCacheSize = 0;

  @override
  void initState() {
    super.initState();
    _calculateStorageUsage();
  }

  Future<void> _calculateStorageUsage() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取应用缓存目录
      final cacheDir = await getApplicationCacheDirectory();

      // 计算缩略图缓存大小（假设存储在缓存目录下的thumbnails文件夹中）
      final thumbnailDir = Directory('${cacheDir.path}/thumbnails');
      _thumbnailCacheSize = await _calculateDirectorySize(thumbnailDir);

      // 计算媒体缓存大小（假设存储在缓存目录下的media_cache文件夹中）
      final mediaCacheDir = Directory('${cacheDir.path}/media_cache');
      _mediaCacheSize = await _calculateDirectorySize(mediaCacheDir);

      // 计算总存储使用量
      _totalStorageUsed = _thumbnailCacheSize + _mediaCacheSize;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('计算存储使用量时出错: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<int> _calculateDirectorySize(Directory directory) async {
    try {
      if (!directory.existsSync()) return 0;

      int totalSize = 0;

      try {
        // 尝试获取目录内容
        final items = directory.listSync(recursive: false);

        for (var item in items) {
          if (item is File) {
            // 处理文件
            try {
              totalSize += await item.length();
            } catch (e) {
              // 静默处理单个文件的错误
              debugPrint('无法获取文件大小 ${item.path}: $e');
            }
          } else if (item is Directory) {
            // 处理子目录 - 递归调用，而不是使用recursive: true
            try {
              totalSize += await _calculateDirectorySize(item);
            } catch (e) {
              // 静默处理子目录的错误
              debugPrint('无法访问子目录 ${item.path}: $e');
            }
          }
        }
      } on FileSystemException catch (e) {
        // 处理目录列表权限错误
        debugPrint('目录访问被拒绝 ${directory.path}: ${e.message}');
        // 不抛出异常，而是返回当前已计算的大小
      }

      return totalSize;
    } catch (e) {
      debugPrint('计算目录大小时出错 ${directory.path}: $e');
      return 0;
    }
  }

  Future<void> _clearCache(String type) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final cacheDir = await getTemporaryDirectory();
      Directory targetDir;

      switch (type) {
        case 'thumbnails':
          targetDir = Directory('${cacheDir.path}/thumbnails');
          break;
        case 'media':
          targetDir = Directory('${cacheDir.path}/media_cache');
          break;
        case 'all':
          // 清除所有缓存
          targetDir = cacheDir;
          break;
        default:
          throw Exception('未知的缓存类型');
      }

      if (await targetDir.exists()) {
        if (type == 'all') {
          // 清除所有缓存时，我们需要保留一些重要目录
          final items = targetDir.listSync();
          for (var item in items) {
            try {
              if (item is Directory &&
                  (!path.basename(item.path).startsWith('.') &&
                      path.basename(item.path) != 'flutter_assets')) {
                await item.delete(recursive: true);
              } else if (item is File) {
                await item.delete();
              }
            } catch (e) {
              debugPrint('删除项目时出错 ${item.path}: $e');
            }
          }
        } else {
          // 对于特定类型的缓存，直接删除整个目录
          await targetDir.delete(recursive: true);
        }
      }

      // 重新计算存储使用量
      await _calculateStorageUsage();

      // 确保在显示SnackBar前检查组件是否仍在widget树中
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清除${_getCacheTypeName(type)}缓存')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除缓存失败: $e')),
        );
      }
    }
  }

  String _getCacheTypeName(String type) {
    switch (type) {
      case 'thumbnails':
        return '缩略图';
      case 'media':
        return '媒体';
      case 'all':
        return '所有';
      default:
        return '未知';
    }
  }

  String _formatSize(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size > 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('存储空间管理'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // 存储使用概览
                Card(
                  margin: const EdgeInsets.only(bottom: 16.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '存储使用概览',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('总存储使用量'),
                            Text(_formatSize(_totalStorageUsed)),
                          ],
                        ),
                        const Divider(),
                        StorageItem(
                          icon: Icons.image,
                          title: '缩略图缓存',
                          size: _thumbnailCacheSize,
                          formatSize: _formatSize,
                        ),
                        StorageItem(
                          icon: Icons.video_library,
                          title: '媒体缓存',
                          size: _mediaCacheSize,
                          formatSize: _formatSize,
                        ),
                      ],
                    ),
                  ),
                ),

                // 缓存管理
                Card(
                  margin: const EdgeInsets.only(bottom: 16.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '缓存管理',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ListTile(
                          title: const Text('清除缩略图缓存'),
                          leading: const Icon(Icons.image),
                          trailing: Text(_formatSize(_thumbnailCacheSize)),
                          onTap: _thumbnailCacheSize > 0
                              ? () => _clearCache('thumbnails')
                              : null,
                        ),
                        ListTile(
                          title: const Text('清除媒体缓存'),
                          leading: const Icon(Icons.video_library),
                          trailing: Text(_formatSize(_mediaCacheSize)),
                          onTap: _mediaCacheSize > 0
                              ? () => _clearCache('media')
                              : null,
                        ),
                        ListTile(
                          title: const Text('清除所有缓存'),
                          leading: const Icon(Icons.delete_sweep),
                          trailing: Text(_formatSize(_totalStorageUsed)),
                          onTap: _totalStorageUsed > 0
                              ? () => _showClearAllCacheConfirmation()
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),

                // 存储设置
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '存储设置',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('自动清除缓存'),
                          subtitle: const Text('应用退出时自动清除媒体缓存'),
                          value: false, // 从设置中读取
                          onChanged: (value) {
                            // 保存到设置
                          },
                        ),
                        SwitchListTile(
                          title: const Text('限制缓存大小'),
                          subtitle: const Text('当缓存超过设定的大小时自动清理'),
                          value: false, // 从设置中读取
                          onChanged: (value) {
                            // 保存到设置
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _showClearAllCacheConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所有缓存'),
        content: const Text('确定要清除所有缓存吗？这可能会暂时影响应用的性能，因为缓存需要重建。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _clearCache('all');
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class StorageItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final int size;
  final String Function(int) formatSize;

  const StorageItem({
    super.key,
    required this.icon,
    required this.title,
    required this.size,
    required this.formatSize,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                LinearProgressIndicator(
                  value: size > 0 ? size / (size * 2) : 0,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(formatSize(size)),
        ],
      ),
    );
  }
}
