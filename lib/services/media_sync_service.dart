import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

import '../models/cloud_mapping.dart';
import '../models/device_info.dart';
import '../models/media_index.dart';
import 'webdav_service.dart';
import 'desktop_media_scanner.dart';
import 'mobile_media_scanner.dart'; // 添加导入MobileMediaScanner

/// 传输任务状态
enum TransferStatus {
  pending, // 等待开始
  inProgress, // 正在进行
  completed, // 已完成
  failed, // 失败
}

/// 传输任务类型
enum TransferType {
  upload, // 上传
  download, // 下载
}

/// 传输任务信息
class TransferTask {
  final String id; // 任务ID
  final String fileName; // 文件名
  final String localPath; // 本地路径
  final String remotePath; // 远程路径
  final int fileSize; // 文件大小
  final TransferType type; // 传输类型
  TransferStatus status; // 传输状态
  String? errorMessage; // 错误信息
  DateTime startTime; // 开始时间
  DateTime? endTime; // 结束时间

  TransferTask({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.remotePath,
    required this.fileSize,
    required this.type,
    required this.status,
    this.errorMessage,
    required this.startTime,
    this.endTime,
  });

  // 计算传输持续时间
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  // 创建上传任务
  static TransferTask createUploadTask(MediaMapping mapping) {
    return TransferTask(
      id: mapping.mediaId,
      fileName: path.basename(mapping.localPath),
      localPath: mapping.localPath,
      remotePath: mapping.cloudPath,
      fileSize: mapping.fileSize,
      type: TransferType.upload,
      status: TransferStatus.pending,
      startTime: DateTime.now(),
    );
  }

  // 创建下载任务
  static TransferTask createDownloadTask(MediaMapping mapping) {
    return TransferTask(
      id: mapping.mediaId,
      fileName: path.basename(mapping.cloudPath),
      localPath: mapping.localPath,
      remotePath: mapping.cloudPath,
      fileSize: mapping.fileSize,
      type: TransferType.download,
      status: TransferStatus.pending,
      startTime: DateTime.now(),
    );
  }

  // 将任务标记为成功完成
  void markCompleted() {
    status = TransferStatus.completed;
    endTime = DateTime.now();
  }

  // 将任务标记为失败
  void markFailed(String error) {
    status = TransferStatus.failed;
    errorMessage = error;
    endTime = DateTime.now();
  }

  // 将任务标记为进行中
  void markInProgress() {
    status = TransferStatus.inProgress;
  }
}

/// 媒体同步服务
/// 负责扫描本地媒体、构建索引、与云端同步
class MediaSyncService {
  /// 最大并发上传/下载任务数
  final int _maxConcurrentTasks;

  /// WebDAV服务
  final WebDavService _webdavService;

  /// 桌面媒体扫描器
  final DesktopMediaScanner _desktopScanner = DesktopMediaScanner();

  /// 移动媒体扫描器
  late final MobileMediaScanner _mobileScanner;

  /// 设备信息
  DeviceInfo? _deviceInfo;

  /// 媒体索引（按日期分组）
  final Map<String, MediaIndex> _mediaIndices = {};

  /// 云端媒体映射
  CloudMediaMapping? _cloudMapping;

  /// 应用专属目录（存放从云端下载的文件）
  Directory? _appMediaDir;

  /// 同步锁，防止并发同步操作
  final Lock _syncLock = Lock();

  /// 初始化完成状态
  bool _initialized = false;

  /// 是否正在同步
  bool _isSyncing = false;

  /// 同步进度（0-100）
  int _syncProgress = 0;

  /// 同步错误信息
  String? _syncError;

  /// 当前同步状态信息
  String? _syncStatusInfo;

  /// 传输任务列表
  final List<TransferTask> _transferTasks = [];

  /// 当前活跃的任务列表 (正在进行的上传和下载)
  List<TransferTask> get activeTasks => _transferTasks
      .where((task) => task.status == TransferStatus.inProgress)
      .toList();

  /// 已完成的任务列表 (最近50个)
  List<TransferTask> get completedTasks {
    final completed = _transferTasks
        .where((task) =>
            task.status == TransferStatus.completed ||
            task.status == TransferStatus.failed)
        .toList();
    completed.sort((a, b) => b.endTime!.compareTo(a.endTime!)); // 按完成时间降序排序
    return completed.length > 50 ? completed.sublist(0, 50) : completed;
  }

  /// 排队等待的任务列表
  List<TransferTask> get pendingTasks => _transferTasks
      .where((task) => task.status == TransferStatus.pending)
      .toList();

  /// 同步状态信息更新回调
  Function(String)? onSyncStatusUpdate;

  /// 传输任务状态更新回调
  Function(List<TransferTask>)? onTransferTasksUpdate;

  MediaSyncService(this._webdavService, {int maxConcurrentTasks = 5})
      : _maxConcurrentTasks = maxConcurrentTasks {
    // 初始化移动媒体扫描器，提供进度更新回调
    _mobileScanner = MobileMediaScanner(onProgressUpdate: (progress) {
      _syncProgress = progress;
      // 可选：通过回调通知UI更新进度
      if (onSyncStatusUpdate != null) {
        onSyncStatusUpdate!('扫描进度: $progress%');
      }
    }, onScanComplete: (indices) {
      _mediaIndices.addAll(indices);
      if (onSyncStatusUpdate != null) {
        onSyncStatusUpdate!('扫描完成，发现 ${indices.length} 个媒体分组');
      }
    }, onScanError: (error) {
      _syncError = error;
      if (onSyncStatusUpdate != null) {
        onSyncStatusUpdate!('扫描错误: $error');
      }
    });
  }

  /// 获取同步状态
  bool get isSyncing => _isSyncing;

  /// 获取同步进度
  int get syncProgress => _syncProgress;

  /// 获取同步错误信息
  String? get syncError => _syncError;

  /// 获取当前同步状态信息
  String? get syncStatusInfo => _syncStatusInfo;

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 获取设备信息
      _deviceInfo = await DeviceInfo.getDeviceInfo();

      // 获取应用专属目录
      _appMediaDir = await getAppMediaDirectory();

      // 加载本地存储的云端映射表
      await _loadCloudMapping();

      _initialized = true;
    } catch (e) {
      _syncError = '初始化错误: $e';
      rethrow;
    }
  }

  /// 扫描本地媒体文件
  Future<void> scanLocalMedia() async {
    if (!_initialized) await initialize();

    try {
      // 清空旧的媒体索引
      _mediaIndices.clear();

      // 根据平台使用不同的扫描方法
      if (_isDesktopPlatform()) {
        // 桌面平台 - 使用桌面媒体扫描器
        final desktopIndices = await _desktopScanner.scanDesktopMedia();
        _mediaIndices.addAll(desktopIndices);
        _syncProgress = _desktopScanner.scanProgress;
        _syncError = _desktopScanner.scanError;
      } else {
        // 移动平台 - 使用优化的移动媒体扫描器
        await _scanMobileMedia();
      }

      // 更新本地的云端映射表
      await _updateCloudMapping();
    } catch (e) {
      _syncError = '扫描媒体错误: $e';
      rethrow;
    } finally {
      _syncProgress = 0;
    }
  }

  /// 判断是否为桌面平台
  bool _isDesktopPlatform() {
    return !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  }

  /// 扫描移动平台媒体 - 优化版本，使用MobileMediaScanner减少UI线程阻塞
  Future<void> _scanMobileMedia() async {
    try {
      if (onSyncStatusUpdate != null) {
        onSyncStatusUpdate!('开始扫描移动端媒体...');
      }

      // 使用MobileMediaScanner在隔离进程中执行扫描
      await _mobileScanner.scanMobileMedia();

      // 结果已在onScanComplete回调中添加到_mediaIndices
    } catch (e) {
      _syncError = '扫描媒体文件错误: $e';
      if (onSyncStatusUpdate != null) {
        onSyncStatusUpdate!('扫描出错: $e');
      }
      rethrow;
    }
  }

  /// 加载本地存储的云端映射表
  Future<void> _loadCloudMapping() async {
    try {
      if (_deviceInfo == null) return;

      final appDir = await getApplicationSupportDirectory();
      final mappingFile = File('${appDir.path}/cloud_mapping.json');

      if (await mappingFile.exists()) {
        final jsonString = await mappingFile.readAsString();
        _cloudMapping = CloudMediaMapping.fromJsonString(jsonString);
        debugPrint('已加载云端映射表，共${_cloudMapping!.mappings.length}个映射');
      } else {
        // 如果映射文件不存在，创建一个新的
        _cloudMapping = CloudMediaMapping(
          deviceId: _deviceInfo!.uuid,
          deviceName: _deviceInfo!.name,
          lastUpdated: DateTime.now(),
          mappings: [],
        );

        await _saveCloudMapping();
        debugPrint('已创建新的云端映射表');
      }
    } catch (e) {
      debugPrint('加载云端映射表错误：$e');
      // 创建一个新的映射表
      _cloudMapping = CloudMediaMapping(
        deviceId: _deviceInfo!.uuid,
        deviceName: _deviceInfo!.name,
        lastUpdated: DateTime.now(),
        mappings: [],
      );
    }
  }

  /// 保存云端映射表到本地
  Future<void> _saveCloudMapping() async {
    try {
      if (_cloudMapping == null) return;

      final appDir = await getApplicationSupportDirectory();
      final mappingFile = File('${appDir.path}/cloud_mapping.json');

      await mappingFile.writeAsString(_cloudMapping!.toJsonString());
      debugPrint('已保存云端映射表到本地');
    } catch (e) {
      debugPrint('保存云端映射表错误：$e');
    }
  }

  /// 更新本地的云端映射表
  Future<void> _updateCloudMapping() async {
    if (_deviceInfo == null || _cloudMapping == null) return;

    // 收集所有媒体文件
    final allMediaFiles = <MediaFileInfo>[];
    for (final index in _mediaIndices.values) {
      allMediaFiles.addAll(index.mediaFiles);
    }

    // 更新映射
    for (final media in allMediaFiles) {
      // 已在映射表中的跳过
      if (_cloudMapping!.findMappingById(media.id) != null) continue;

      // 创建云端路径
      final datePath = MediaIndex.getDatePath(media.createdAt);
      final cloudPath = '/EchoPixel/$datePath/${media.fileName}';

      // 创建新的映射
      final mapping = MediaMapping(
        mediaId: media.id,
        localPath: media.originalPath,
        cloudPath: cloudPath,
        mediaType: media.type.toString().split('.').last,
        createdAt: media.createdAt,
        fileSize: media.size,
        lastSynced: DateTime.now(),
        syncStatus: SyncStatus.pendingUpload, // 标记为待上传
      );

      _cloudMapping!.addOrUpdateMapping(mapping);
    }

    // 更新时间戳
    _cloudMapping = CloudMediaMapping(
      deviceId: _cloudMapping!.deviceId,
      deviceName: _cloudMapping!.deviceName,
      lastUpdated: DateTime.now(),
      mappings: _cloudMapping!.mappings,
    );

    // 保存更新后的映射表
    await _saveCloudMapping();
  }

  /// 与云端同步媒体文件和映射表
  Future<bool> syncWithCloud() async {
    // 使用锁确保不会并发同步
    return _syncLock.synchronized(() async {
      if (!_initialized) await initialize();
      if (!_webdavService.isConnected) {
        _syncError = 'WebDAV服务未连接';
        return false;
      }

      try {
        _isSyncing = true;
        _syncProgress = 0;
        _syncError = null;

        // 更新同步状态
        _updateSyncStatus('正在准备同步...');

        // 1. 上传本地映射表到云端
        _updateSyncStatus('正在上传本地映射表...');
        await _uploadMappingToCloud();
        _syncProgress = 10;

        // 2. 下载并合并云端的映射表
        _updateSyncStatus('正在下载并合并云端映射表...');
        await _downloadAndMergeMappings();
        _syncProgress = 20;

        // 3. 创建云端目录结构
        _updateSyncStatus('正在创建云端目录结构...');
        await _createCloudDirectories();
        _syncProgress = 30;

        // 4. 上传待上传的文件
        _updateSyncStatus('正在上传文件...');
        await _uploadPendingFiles();
        _syncProgress = 60;

        // 5. 下载需要的文件
        _updateSyncStatus('正在下载文件...');
        await _downloadNeededFiles();
        _syncProgress = 90;

        // 6. 再次上传更新后的映射表
        _updateSyncStatus('正在保存同步状态...');
        await _uploadMappingToCloud();
        _syncProgress = 100;

        _updateSyncStatus('同步完成');

        // 7. 更新设备同步时间
        if (_deviceInfo != null) {
          await _deviceInfo!.updateLastSyncTime(DateTime.now());
        }

        return true;
      } catch (e) {
        _syncError = '同步错误: $e';
        _updateSyncStatus('同步出错: ${e.toString()}');
        return false;
      } finally {
        _isSyncing = false;
      }
    });
  }

  /// 更新同步状态信息
  void _updateSyncStatus(String status) {
    _syncStatusInfo = status;

    // 调用回调通知UI
    if (onSyncStatusUpdate != null) {
      onSyncStatusUpdate!(status);
    }

    debugPrint('同步状态: $status');
  }

  /// 上传映射表到云端
  Future<void> _uploadMappingToCloud() async {
    if (_cloudMapping == null) return;

    try {
      // 确保设备目录存在
      final deviceDirPath = '/EchoPixel/.mappings/${_deviceInfo!.uuid}';
      await _ensureCloudDirectoryExists(deviceDirPath);

      // 将映射表转换为字节
      final mappingBytes = utf8.encode(_cloudMapping!.toJsonString());
      final mappingFilePath = '$deviceDirPath/mapping.json';

      // 创建临时文件
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_mapping.json');
      await tempFile.writeAsBytes(mappingBytes);

      // 上传到云端
      await _webdavService.uploadFile(mappingFilePath, tempFile);
      debugPrint('已上传映射表到云端');

      // 删除临时文件
      await tempFile.delete();
    } catch (e) {
      debugPrint('上传映射表错误：$e');
      rethrow;
    }
  }

  /// 下载并合并云端的所有映射表
  Future<void> _downloadAndMergeMappings() async {
    try {
      // 获取云端映射目录内容
      final mappingsDirPath = '/EchoPixel/.mappings';
      await _ensureCloudDirectoryExists(mappingsDirPath);

      final List<WebDavItem> items;
      try {
        items = await _webdavService.listDirectory(mappingsDirPath);
      } catch (e) {
        debugPrint('获取云端映射目录内容错误：$e');
        return;
      }

      // 筛选出设备目录
      final deviceDirs = items.where((item) => item.isDirectory).toList();

      // 打印详细日志，帮助调试
      debugPrint(
          'WebDAV目录列表结果: ${items.map((item) => "${item.path} (${item.isDirectory ? "目录" : "文件"})").join(", ")}');
      debugPrint(
          '找到${deviceDirs.length}个设备目录：${deviceDirs.map((d) => path.basename(d.path)).join(", ")}');

      if (deviceDirs.isEmpty) {
        debugPrint('警告: 未找到任何设备目录，可能是WebDAV路径问题');
        // 检查当前设备目录是否存在并创建
        final currentDevicePath = '$mappingsDirPath/${_deviceInfo!.uuid}';
        await _ensureCloudDirectoryExists(currentDevicePath);
        debugPrint('已确保当前设备目录存在: ${_deviceInfo!.uuid}');
        return;
      }

      // 遍历每个设备目录，下载并解析映射表
      for (final deviceDir in deviceDirs) {
        // 跳过当前设备的映射表，因为已经处理过
        final deviceId = path.basename(deviceDir.path);
        if (deviceId == _deviceInfo!.uuid) {
          debugPrint('跳过当前设备的映射表: $deviceId');
          continue;
        }

        debugPrint('正在处理设备映射表: $deviceId');

        try {
          // 列出设备目录
          final deviceItems =
              await _webdavService.listDirectory(deviceDir.path);
          debugPrint(
              '设备目录内容: ${deviceItems.map((i) => path.basename(i.path)).join(", ")}');

          // 查找映射文件
          final mappingFile = deviceItems.firstWhere(
            (item) =>
                !item.isDirectory &&
                path.basename(item.path).toLowerCase() == 'mapping.json',
            orElse: () {
              debugPrint('未找到映射文件: ${deviceDir.path}');
              return throw Exception('未找到映射文件');
            },
          );

          debugPrint('找到设备映射文件: ${mappingFile.path}');

          // 下载映射文件
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/temp_download_mapping.json');
          await _webdavService.downloadFile(mappingFile.path, tempFile.path);

          // 检查文件大小
          final fileSize = await tempFile.length();
          debugPrint('下载的映射文件大小: $fileSize 字节');

          if (fileSize == 0) {
            debugPrint('警告: 下载的映射文件为空');
            continue;
          }

          // 解析映射表
          final jsonString = await tempFile.readAsString();
          debugPrint(
              '映射文件内容前100字符: ${jsonString.substring(0, min(100, jsonString.length))}');

          final otherMapping = CloudMediaMapping.fromJsonString(jsonString);
          debugPrint('成功解析设备$deviceId的映射，包含${otherMapping.mappings.length}个项目');

          // 合并映射（只添加本地没有的媒体文件）
          await _mergeMappings(otherMapping);

          // 删除临时文件
          await tempFile.delete();
        } catch (e) {
          debugPrint('处理设备${deviceDir.path}的映射表错误：$e');
          // 继续处理下一个设备
          continue;
        }
      }
    } catch (e) {
      debugPrint('下载和合并映射表错误：$e');
      rethrow;
    }
  }

  /// 合并另一个设备的映射表
  Future<void> _mergeMappings(CloudMediaMapping otherMapping) async {
    if (_cloudMapping == null) return;

    // 获取所有本地已知的媒体ID
    final localMediaIds = Set<String>.from(
      _cloudMapping!.mappings.map((m) => m.mediaId),
    );

    // 找出本地没有的媒体文件
    final newMappings = otherMapping.mappings
        .where((mapping) => !localMediaIds.contains(mapping.mediaId))
        .toList();

    if (newMappings.isEmpty) return;

    // 标记为需要下载
    for (final mapping in newMappings) {
      // 创建本地路径（在应用专属目录）
      final fileName = path.basename(mapping.cloudPath);
      final datePath =
          path.dirname(mapping.cloudPath).replaceAll('/EchoPixel/', '');
      final localDir = Directory('${_appMediaDir!.path}/$datePath');
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

      _cloudMapping!.addOrUpdateMapping(newMapping);
    }

    // 保存更新后的映射表
    await _saveCloudMapping();
    debugPrint('已合并${newMappings.length}个新媒体文件的映射');
  }

  /// 确保云端目录结构存在 - 仅创建必要的根目录
  Future<void> _createCloudDirectories() async {
    try {
      // 只创建基础目录结构
      debugPrint('创建云端必要的目录结构');
      await _ensureCloudDirectoryExists('/EchoPixel');
      await _ensureCloudDirectoryExists('/EchoPixel/.mappings');
      await _ensureCloudDirectoryExists(
        '/EchoPixel/.mappings/${_deviceInfo!.uuid}',
      );

      // 不再预先创建所有日期目录，改为在上传文件时按需创建
    } catch (e) {
      debugPrint('创建云端基础目录结构错误：$e');
      rethrow;
    }
  }

  /// 确保云端目录存在
  Future<void> _ensureCloudDirectoryExists(String dirPath) async {
    try {
      // 尝试列出目录来检查是否存在
      try {
        await _webdavService.listDirectory(dirPath);
        debugPrint('目录已存在: $dirPath');
      } catch (e) {
        debugPrint('目录不存在，尝试创建: $dirPath');
        // 目录不存在，使用递归创建功能
        final success = await _webdavService.createDirectoryRecursive(dirPath);
        if (success) {
          debugPrint('成功创建目录: $dirPath');
        } else {
          throw Exception('无法创建目录: $dirPath');
        }
      }
    } catch (e) {
      debugPrint('确保目录存在时出错: $e');
      rethrow;
    }
  }

  /// 上传待上传的文件 - 并行版本
  Future<void> _uploadPendingFiles() async {
    if (_cloudMapping == null) return;

    // 获取所有待上传的映射
    final pendingUploads = _cloudMapping!.mappings
        .where((mapping) => mapping.syncStatus == SyncStatus.pendingUpload)
        .toList();

    if (pendingUploads.isEmpty) return;

    // 总文件大小（用于计算进度）
    final totalSize =
        pendingUploads.map((m) => m.fileSize).fold<int>(0, (a, b) => a + b);
    int uploadedSize = 0;
    final uploadProgress = ValueNotifier<int>(0);

    // 创建一个锁，用于保护上传进度的更新
    final progressLock = Lock();

    // 用于保存已更新的映射
    final updatedMappings = <MediaMapping>[];

    // 处理单个上传任务
    Future<void> processUpload(MediaMapping mapping) async {
      try {
        final localFile = File(mapping.localPath);
        if (!await localFile.exists()) {
          // 本地文件不存在，标记为错误
          await progressLock.synchronized(() {
            updatedMappings.add(mapping.copyWithSyncStatus(SyncStatus.error));
          });
          return;
        }

        // 显示当前上传文件信息
        final fileName = path.basename(mapping.localPath);
        if (onSyncStatusUpdate != null) {
          onSyncStatusUpdate!("$fileName -> ${mapping.cloudPath}");
        }

        // 创建上传任务
        final uploadTask = TransferTask.createUploadTask(mapping);
        _transferTasks.add(uploadTask);
        _updateTransferTasks();

        // 检查云端文件是否已存在
        try {
          final fileExists = await _webdavService.fileExists(mapping.cloudPath);
          if (fileExists) {
            // 文件已存在，标记为已同步并跳过上传
            debugPrint('文件已存在于云端，跳过上传: ${mapping.cloudPath}');
            await progressLock.synchronized(() {
              updatedMappings
                  .add(mapping.copyWithSyncStatus(SyncStatus.synced));
              uploadedSize += mapping.fileSize;
              final progress = 30 + ((uploadedSize / totalSize) * 30).round();
              uploadProgress.value = progress;
              _syncProgress = progress;
            });

            // 标记任务完成
            uploadTask.markCompleted();
            _updateTransferTasks();
            return;
          }
        } catch (e) {
          // 检查文件存在时出错，继续尝试上传
          debugPrint('检查云端文件是否存在时出错: $e');
        }

        try {
          // 尝试直接上传到云端
          uploadTask.markInProgress();
          _updateTransferTasks();
          await _webdavService.uploadFile(mapping.cloudPath, localFile);
        } catch (uploadError) {
          // 如果上传失败，检查是否因为目录不存在
          if (uploadError.toString().contains('not found') ||
              uploadError.toString().contains('not exist') ||
              uploadError.toString().contains('404') ||
              uploadError.toString().toLowerCase().contains('directory')) {
            // 获取目标目录路径
            final dirPath = path.dirname(mapping.cloudPath);
            debugPrint('目录不存在，尝试创建：$dirPath');

            // 创建目录（可能需要递归创建）
            await _ensureCloudDirectoryExists(dirPath);

            // 再次尝试上传
            await _webdavService.uploadFile(mapping.cloudPath, localFile);
          } else {
            // 其他错误，重新抛出
            rethrow;
          }
        }

        // 更新状态和进度
        await progressLock.synchronized(() {
          updatedMappings.add(mapping.copyWithSyncStatus(SyncStatus.synced));
          uploadedSize += mapping.fileSize;
          final progress = 30 + ((uploadedSize / totalSize) * 30).round();
          uploadProgress.value = progress;
          _syncProgress = progress;
        });

        // 标记任务完成
        uploadTask.markCompleted();
        _updateTransferTasks();
      } catch (e) {
        // 上传错误
        debugPrint('上传文件错误：${mapping.localPath}，${e.toString()}');
        await progressLock.synchronized(() {
          updatedMappings.add(mapping.copyWithSyncStatus(SyncStatus.error));
        });

        // 标记任务失败
        final uploadTask =
            _transferTasks.firstWhere((task) => task.id == mapping.mediaId);
        uploadTask.markFailed(e.toString());
        _updateTransferTasks();
      }
    }

    try {
      // 分批处理上传任务，每批最多 _maxConcurrentTasks 个任务
      for (var i = 0; i < pendingUploads.length; i += _maxConcurrentTasks) {
        final end = (i + _maxConcurrentTasks < pendingUploads.length)
            ? i + _maxConcurrentTasks
            : pendingUploads.length;
        final batch = pendingUploads.sublist(i, end);

        // 并行执行这一批的上传任务
        await Future.wait(
          batch.map((mapping) => processUpload(mapping)),
        );
      }
    } finally {
      // 更新所有映射
      for (final mapping in updatedMappings) {
        _cloudMapping!.addOrUpdateMapping(mapping);
      }

      // 保存更新后的映射表
      await _saveCloudMapping();
    }
  }

  /// 下载需要的文件 - 并行版本
  Future<void> _downloadNeededFiles() async {
    if (_cloudMapping == null) return;

    // 获取所有待下载的映射
    final pendingDownloads = _cloudMapping!.mappings
        .where(
          (mapping) => mapping.syncStatus == SyncStatus.pendingDownload,
        )
        .toList();

    if (pendingDownloads.isEmpty) return;

    // 总文件大小（用于计算进度）
    final totalSize =
        pendingDownloads.map((m) => m.fileSize).fold<int>(0, (a, b) => a + b);
    int downloadedSize = 0;
    final downloadProgress = ValueNotifier<int>(0);

    // 创建一个锁，用于保护下载进度的更新
    final progressLock = Lock();

    // 用于保存已更新的映射
    final updatedMappings = <MediaMapping>[];

    // 处理单个下载任务
    Future<void> processDownload(MediaMapping mapping) async {
      try {
        // 确保本地目录存在
        final localDir = path.dirname(mapping.localPath);
        await Directory(localDir).create(recursive: true);

        // 创建下载任务
        final downloadTask = TransferTask.createDownloadTask(mapping);
        _transferTasks.add(downloadTask);
        _updateTransferTasks();

        // 下载文件
        downloadTask.markInProgress();
        _updateTransferTasks();
        await _webdavService.downloadFile(mapping.cloudPath, mapping.localPath);

        // 更新状态和进度
        await progressLock.synchronized(() {
          updatedMappings.add(mapping.copyWithSyncStatus(SyncStatus.synced));
          downloadedSize += mapping.fileSize;
          final progress = 60 + ((downloadedSize / totalSize) * 30).round();
          downloadProgress.value = progress;
          _syncProgress = progress;
        });

        // 标记任务完成
        downloadTask.markCompleted();
        _updateTransferTasks();
      } catch (e) {
        // 下载错误
        debugPrint('下载文件错误：${mapping.cloudPath}，${e.toString()}');
        await progressLock.synchronized(() {
          updatedMappings.add(mapping.copyWithSyncStatus(SyncStatus.error));
        });

        // 标记任务失败
        final downloadTask =
            _transferTasks.firstWhere((task) => task.id == mapping.mediaId);
        downloadTask.markFailed(e.toString());
        _updateTransferTasks();
      }
    }

    try {
      // 分批处理下载任务，每批最多 _maxConcurrentTasks 个任务
      for (var i = 0; i < pendingDownloads.length; i += _maxConcurrentTasks) {
        final end = (i + _maxConcurrentTasks < pendingDownloads.length)
            ? i + _maxConcurrentTasks
            : pendingDownloads.length;
        final batch = pendingDownloads.sublist(i, end);

        // 并行执行这一批的下载任务
        await Future.wait(
          batch.map((mapping) => processDownload(mapping)),
        );
      }
    } finally {
      // 更新所有映射
      for (final mapping in updatedMappings) {
        _cloudMapping!.addOrUpdateMapping(mapping);
      }

      // 保存更新后的映射表
      await _saveCloudMapping();
    }
  }

  /// 获取按日期组织的媒体索引
  Map<String, MediaIndex> getMediaIndices() {
    return Map.unmodifiable(_mediaIndices);
  }

  /// 获取指定日期的媒体索引
  MediaIndex? getMediaIndexByDate(String datePath) {
    return _mediaIndices[datePath];
  }

  /// 获取所有媒体文件
  List<MediaFileInfo> getAllMediaFiles() {
    final allFiles = <MediaFileInfo>[];
    for (final index in _mediaIndices.values) {
      allFiles.addAll(index.mediaFiles);
    }
    return allFiles;
  }

  // 确保用户上传路径有效
  String _ensureValidPath(String? path) {
    if (path == null || path.isEmpty) {
      return '/';
    }

    // 确保路径以/开头
    String validPath = path.startsWith('/') ? path : '/$path';
    // 确保路径以/结尾
    if (!validPath.endsWith('/')) {
      validPath = '$validPath/';
    }
    return validPath;
  }

  /// 从外部设置媒体索引（用于避免重复扫描）
  Future<void> setMediaIndices(Map<String, MediaIndex> indices) async {
    if (!_initialized) await initialize();

    // 清空旧的媒体索引并添加新的
    _mediaIndices.clear();
    _mediaIndices.addAll(indices);

    // 更新本地的云端映射表
    await _updateCloudMapping();

    if (onSyncStatusUpdate != null) {
      onSyncStatusUpdate!('已导入 ${indices.length} 个媒体分组，无需重新扫描');
    }
  }

  /// 更新传输任务列表
  void _updateTransferTasks() {
    if (onTransferTasksUpdate != null) {
      onTransferTasksUpdate!(_transferTasks);
    }
  }
}

/// 获取应用专属媒体目录（存放从云端下载的文件）
Future<Directory> getAppMediaDirectory() async {
  Directory appDir;

  if (Platform.isAndroid || Platform.isIOS) {
    appDir = await getApplicationDocumentsDirectory();
  } else {
    appDir = await getApplicationSupportDirectory();
  }

  final mediaDir = Directory('${appDir.path}/media');
  if (!await mediaDir.exists()) {
    await mediaDir.create(recursive: true);
  }

  return mediaDir;
}
