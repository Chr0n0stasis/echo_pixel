import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/cloud_mapping.dart';
import '../models/device_info.dart';
import '../services/webdav_service.dart';
import '../services/media_sync_service.dart';
import '../services/media_index_service.dart';

/// 设备管理页面 - 管理WebDAV上记录的设备
class DeviceManagementPage extends StatefulWidget {
  const DeviceManagementPage({super.key});

  @override
  State<DeviceManagementPage> createState() => _DeviceManagementPageState();
}

class _DeviceManagementPageState extends State<DeviceManagementPage> {
  // 当前设备信息
  DeviceInfo? _currentDevice;

  // WebDAV服务
  late WebDavService _webdavService;

  // 媒体同步服务
  late MediaSyncService _mediaSyncService;

  // 媒体索引服务
  late MediaIndexService _mediaIndexService;

  // 设备列表
  List<CloudMediaMapping> _deviceMappings = [];

  // 是否正在加载
  bool _isLoading = true;

  // 错误信息
  String? _errorMessage;

  // 是否正在处理设备删除
  bool _isProcessingDelete = false;

  @override
  void initState() {
    super.initState();
    _webdavService = Provider.of<WebDavService>(context, listen: false);
    _mediaSyncService = Provider.of<MediaSyncService>(context, listen: false);
    _mediaIndexService = Provider.of<MediaIndexService>(context, listen: false);

    _initializeDeviceManagement();
  }

  // 初始化设备管理
  Future<void> _initializeDeviceManagement() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 获取当前设备信息
      _currentDevice = await DeviceInfo.getDeviceInfo();

      // 加载WebDAV上的设备列表
      await _loadDevicesFromWebDAV();
    } catch (e) {
      setState(() {
        _errorMessage = '初始化设备管理出错: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 从WebDAV加载设备列表
  Future<void> _loadDevicesFromWebDAV() async {
    if (!_webdavService.isConnected) {
      setState(() {
        _errorMessage = 'WebDAV服务未连接';
      });
      return;
    }

    try {
      // 获取云端映射目录内容
      final mappingsDirPath = '/EchoPixel/.mappings';

      // 确保目录存在
      try {
        await _webdavService.listDirectory(mappingsDirPath);
      } catch (e) {
        // 目录不存在，创建它
        await _webdavService.createDirectoryRecursive(mappingsDirPath);
        setState(() {
          _deviceMappings = [];
        });
        return;
      }

      final List<WebDavItem> items =
          await _webdavService.listDirectory(mappingsDirPath);

      // 筛选出设备目录
      final deviceDirs = items.where((item) => item.isDirectory).toList();

      if (deviceDirs.isEmpty) {
        setState(() {
          _deviceMappings = [];
        });
        return;
      }

      // 临时存储设备映射
      final List<CloudMediaMapping> mappings = [];

      // 遍历每个设备目录，下载并解析映射表
      for (final deviceDir in deviceDirs) {
        try {
          // 列出设备目录内容
          final deviceItems =
              await _webdavService.listDirectory(deviceDir.path);

          // 查找映射文件
          final mappingFile = deviceItems.firstWhere(
            (item) =>
                !item.isDirectory &&
                path.basename(item.path).toLowerCase() == 'mapping.json',
            orElse: () => throw Exception('未找到映射文件'),
          );

          // 下载映射文件
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/temp_device_mapping.json');
          await _webdavService.downloadFile(mappingFile.path, tempFile.path);

          // 解析映射表
          final fileContent = await tempFile.readAsString();
          final CloudMediaMapping deviceMapping =
              CloudMediaMapping.fromJsonString(fileContent);

          // 添加到列表
          mappings.add(deviceMapping);

          // 删除临时文件
          await tempFile.delete();
        } catch (e) {
          // 继续处理下一个设备
          debugPrint('处理设备${deviceDir.path}的映射表错误：$e');
        }
      }

      setState(() {
        _deviceMappings = mappings;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载设备列表出错: $e';
      });
    }
  }

  // 删除设备（包括云端文件）
  Future<void> _deleteDeviceWithFiles(CloudMediaMapping deviceMapping) async {
    if (_isProcessingDelete) return;

    setState(() {
      _isProcessingDelete = true;
    });

    try {
      // 显示进度对话框
      final progressDialog = _showProgressDialog('正在删除设备和云端文件...');

      // 遍历设备映射中的所有文件并从云端删除
      int totalFiles = deviceMapping.mappings.length;
      int processedFiles = 0;

      for (final mapping in deviceMapping.mappings) {
        try {
          // 删除云端文件
          await _webdavService.deleteFile(mapping.cloudPath);

          // 更新进度
          processedFiles++;
          if (processedFiles % 10 == 0) {
            // 每10个文件更新一次进度
            progressDialog
                .update('正在删除设备和云端文件 ($processedFiles/$totalFiles)...');
          }
        } catch (e) {
          // 文件不存在或删除失败，继续下一个
          debugPrint('删除文件错误：${mapping.cloudPath}，${e.toString()}');
        }
      }

      // 删除设备目录
      final deviceDirPath = '/EchoPixel/.mappings/${deviceMapping.deviceId}';
      try {
        await _webdavService.deleteDirectory(deviceDirPath);
      } catch (e) {
        debugPrint('删除设备目录错误：$deviceDirPath，${e.toString()}');
      }

      // 关闭进度对话框
      progressDialog.close();

      // 刷新设备列表
      await _loadDevicesFromWebDAV();

      // 添加mounted检查，确保组件仍然挂载
      if (mounted) {
        // 显示成功消息
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除设备"${deviceMapping.deviceName}"及其云端文件')),
        );
      }
    } catch (e) {
      // 添加mounted检查，确保组件仍然挂载
      if (mounted) {
        // 显示错误消息
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除设备出错: $e')),
        );
      }
    } finally {
      // 添加mounted检查，确保组件仍然挂载
      if (mounted) {
        setState(() {
          _isProcessingDelete = false;
        });
      }
    }
  }

  // 删除设备但合并映射表
  Future<void> _deleteDeviceAndMergeMappings(
      CloudMediaMapping deviceMapping) async {
    if (_isProcessingDelete) return;

    setState(() {
      _isProcessingDelete = true;
    });

    try {
      // 显示进度对话框
      final progressDialog = _showProgressDialog('正在合并映射表...');

      // 合并映射表到当前设备
      CloudMediaMapping? localMapping;
      bool hasMergedMappings = false;
      try {
        // 获取当前设备的映射表
        final localMappingFile = File(
            '${(await getApplicationSupportDirectory()).path}/cloud_mapping.json');
        if (!await localMappingFile.exists()) {
          throw Exception('本地映射表不存在');
        }

        // 加载当前设备映射表
        final localMappingJson = await localMappingFile.readAsString();
        localMapping = CloudMediaMapping.fromJsonString(localMappingJson);

        // 获取所有本地已知的媒体ID
        final localMediaIds = Set<String>.from(
          localMapping.mappings.map((m) => m.mediaId),
        );

        // 找出当前设备没有的媒体文件
        final newMappings = deviceMapping.mappings
            .where((mapping) => !localMediaIds.contains(mapping.mediaId))
            .toList();

        if (newMappings.isNotEmpty) {
          // 标记为需要下载
          for (final mapping in newMappings) {
            // 创建本地路径（在应用专属目录）
            final fileName = path.basename(mapping.cloudPath);
            final datePath =
                path.dirname(mapping.cloudPath).replaceAll('/EchoPixel/', '');
            final localDir =
                Directory('${(await getAppMediaDirectory()).path}/$datePath');
            await localDir.create(recursive: true);
            final localPath = '${localDir.path}/$fileName';

            // 添加到本地映射表，标记为待下载
            final newMapping = MediaMapping(
              mediaId: mapping.mediaId,
              localPath: localPath,
              cloudPath: mapping.cloudPath,
              mediaType: mapping.mediaType,
              createdAt: mapping.createdAt,
              fileSize: mapping.fileSize,
              lastSynced: DateTime.now(),
              syncStatus: SyncStatus.pendingDownload,
            );

            localMapping.addOrUpdateMapping(newMapping);
          }

          // 保存更新后的映射表
          await localMappingFile.writeAsString(localMapping.toJsonString());
          hasMergedMappings = true;

          // 通知用户同步状态
          progressDialog
              .update('已合并${newMappings.length}个新文件的映射，正在上传更新后的映射表...');
        } else {
          progressDialog.update('没有新文件需要合并，准备删除设备...');
        }
      } catch (e) {
        debugPrint('合并映射表错误：${e.toString()}');
        progressDialog.update('合并映射表出错: $e，将继续删除设备...');
        await Future.delayed(const Duration(seconds: 2)); // 允许用户阅读错误信息
      }

      // 如果成功合并了映射表，将更新后的映射表上传到云端
      if (hasMergedMappings && localMapping != null && _currentDevice != null) {
        try {
          progressDialog.update('正在上传更新后的映射表到云端...');

          // 确保当前设备的目录存在
          final deviceDirPath = '/EchoPixel/.mappings/${_currentDevice!.uuid}';
          await _webdavService.createDirectoryRecursive(deviceDirPath);

          // 创建临时文件
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/temp_updated_mapping.json');
          await tempFile.writeAsString(localMapping.toJsonString());

          // 上传到云端
          final mappingFilePath = '$deviceDirPath/mapping.json';
          await _webdavService.uploadFile(mappingFilePath, tempFile);

          // 删除临时文件
          await tempFile.delete();

          progressDialog.update('已上传更新后的映射表，准备删除设备...');
        } catch (e) {
          debugPrint('上传更新后的映射表错误：${e.toString()}');
          progressDialog.update('上传更新后的映射表出错: $e，将继续删除设备...');
          await Future.delayed(const Duration(seconds: 2)); // 允许用户阅读错误信息
        }
      }

      // 删除设备目录
      final deviceDirPath = '/EchoPixel/.mappings/${deviceMapping.deviceId}';
      try {
        await _webdavService.deleteDirectory(deviceDirPath);
      } catch (e) {
        debugPrint('删除设备目录错误：$deviceDirPath，${e.toString()}');
      }

      // 关闭进度对话框
      progressDialog.close();

      // 刷新设备列表
      await _loadDevicesFromWebDAV();

      // 添加mounted检查，确保组件仍然挂载
      if (mounted) {
        // 显示成功消息
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('已合并设备"${deviceMapping.deviceName}"的映射表并删除设备')),
        );
      }
    } catch (e) {
      // 添加mounted检查，确保组件仍然挂载
      if (mounted) {
        // 显示错误消息
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('合并映射表出错: $e')),
        );
      }
    } finally {
      // 添加mounted检查，确保组件仍然挂载
      if (mounted) {
        setState(() {
          _isProcessingDelete = false;
        });
      }
    }
  }

  // 显示进度对话框
  _ProgressDialogController _showProgressDialog(String message) {
    final controller = _ProgressDialogController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            controller._setState = setState;
            controller._message = message;
            controller._close = () {
              Navigator.of(context).pop();
            };

            return AlertDialog(
              title: const Text('处理中'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(controller._message),
                ],
              ),
            );
          },
        );
      },
    );

    return controller;
  }

  // 显示确认删除对话框
  Future<void> _showDeleteConfirmDialog(CloudMediaMapping deviceMapping) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除设备"${deviceMapping.deviceName}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请选择删除方式：'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.delete_forever),
              title: const Text('删除设备和云端文件'),
              subtitle: const Text('将从WebDAV中删除此设备上传的所有文件'),
              onTap: () {
                Navigator.of(context).pop('delete_with_files');
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.merge_type),
              title: const Text('合并映射表并删除设备'),
              subtitle: const Text('保留云端文件，将映射表合并到当前设备'),
              onTap: () {
                Navigator.of(context).pop('merge_and_delete');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop('cancel');
            },
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (result == 'delete_with_files') {
      await _deleteDeviceWithFiles(deviceMapping);
    } else if (result == 'merge_and_delete') {
      await _deleteDeviceAndMergeMappings(deviceMapping);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备管理'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorView()
              : _buildDeviceList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _initializeDeviceManagement,
        tooltip: '刷新设备列表',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  // 构建错误视图
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 60,
          ),
          const SizedBox(height: 16),
          Text(
            '出错了',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              _errorMessage ?? '未知错误',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _initializeDeviceManagement,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  // 构建设备列表
  Widget _buildDeviceList() {
    if (_deviceMappings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withAlpha(100),
            ),
            const SizedBox(height: 16),
            Text(
              '没有找到设备',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('WebDAV上没有发现任何设备记录'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _deviceMappings.length,
      itemBuilder: (context, index) {
        final deviceMapping = _deviceMappings[index];
        final bool isCurrentDevice =
            _currentDevice?.uuid == deviceMapping.deviceId;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: Icon(
              _getDeviceIcon(deviceMapping),
              color: isCurrentDevice
                  ? Theme.of(context).colorScheme.primary
                  : null,
              size: 32,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    deviceMapping.deviceName,
                    style: TextStyle(
                      fontWeight:
                          isCurrentDevice ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (isCurrentDevice)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '当前设备',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('设备ID: ${deviceMapping.deviceId.substring(0, 8)}...'),
                const SizedBox(height: 4),
                Text(
                  '上次更新: ${_formatDate(deviceMapping.lastUpdated)}',
                ),
                const SizedBox(height: 4),
                Text(
                  '${deviceMapping.mappings.length} 个媒体文件',
                ),
              ],
            ),
            isThreeLine: true,
            trailing: isCurrentDevice
                ? null
                : IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: '删除设备',
                    onPressed: _isProcessingDelete
                        ? null
                        : () => _showDeleteConfirmDialog(deviceMapping),
                  ),
            onTap: () {
              // 显示设备详情
              _showDeviceDetails(deviceMapping);
            },
          ),
        );
      },
    );
  }

  // 显示设备详情对话框
  void _showDeviceDetails(CloudMediaMapping deviceMapping) {
    final bool isCurrentDevice = _currentDevice?.uuid == deviceMapping.deviceId;

    // 计算一些统计数据
    int imageCount = 0;
    int videoCount = 0;
    int totalSize = 0;

    for (final mapping in deviceMapping.mappings) {
      if (mapping.mediaType.toLowerCase() == 'image') {
        imageCount++;
      } else if (mapping.mediaType.toLowerCase() == 'video') {
        videoCount++;
      }
      totalSize += mapping.fileSize;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('设备"${deviceMapping.deviceName}"详情'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isCurrentDevice)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '这是当前设备',
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              _detailItem(context, '设备ID', deviceMapping.deviceId),
              _detailItem(
                  context, '上次更新', _formatDate(deviceMapping.lastUpdated)),
              _detailItem(
                  context, '媒体文件数量', '${deviceMapping.mappings.length}'),
              _detailItem(context, '图片数量', '$imageCount'),
              _detailItem(context, '视频数量', '$videoCount'),
              _detailItem(context, '总大小', _formatSize(totalSize)),
            ],
          ),
        ),
        actions: [
          if (!isCurrentDevice) ...[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showDeleteConfirmDialog(deviceMapping);
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('删除设备'),
            ),
          ],
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // 详情项目组件
  Widget _detailItem(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  // 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
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
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  // 获取设备图标
  IconData _getDeviceIcon(CloudMediaMapping deviceMapping) {
    // 简单的启发式方法，根据设备名称猜测设备类型
    final name = deviceMapping.deviceName.toLowerCase();

    if (name.contains('android') ||
        name.contains('手机') ||
        name.contains('phone')) {
      return Icons.smartphone;
    } else if (name.contains('ios') ||
        name.contains('iphone') ||
        name.contains('ipad')) {
      return Icons.phone_iphone;
    } else if (name.contains('windows') ||
        name.contains('电脑') ||
        name.contains('pc')) {
      return Icons.computer;
    } else if (name.contains('mac') || name.contains('apple')) {
      return Icons.laptop_mac;
    } else if (name.contains('linux')) {
      return Icons.laptop;
    } else if (name.contains('web') ||
        name.contains('浏览器') ||
        name.contains('browser')) {
      return Icons.public;
    } else {
      return Icons.devices_other;
    }
  }
}

// 进度对话框控制器，用于在处理过程中更新进度消息
class _ProgressDialogController {
  String _message = '';
  late StateSetter _setState;
  late Function _close;

  // 更新进度消息
  void update(String message) {
    _setState(() {
      _message = message;
    });
  }

  // 关闭对话框
  void close() {
    _close();
  }
}
