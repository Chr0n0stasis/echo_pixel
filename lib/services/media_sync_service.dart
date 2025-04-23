import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:p_limit/p_limit.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/cloud_mapping.dart';
import '../models/device_info.dart';
import '../models/media_index.dart';
import 'webdav_service.dart';
import 'desktop_media_scanner.dart';
import 'mobile_media_scanner.dart'; // 添加导入MobileMediaScanner
import 'foreground_sync_service.dart'; // 导入前台任务服务

/// 同步步骤枚举，用于表示当前同步进度所处的阶段
enum SyncStep {
  preparing(0, '准备同步'),
  uploadingMapping(1, '上传本地映射表'),
  downloadingMappings(2, '下载并合并云端映射表'),
  creatingDirectories(3, '创建云端目录结构'),
  deletingFiles(4, '删除已标记的文件'), // 新增删除文件步骤
  uploadingFiles(5, '上传文件'),
  downloadingFiles(6, '下载文件'),
  savingState(7, '保存同步状态'),
  completed(8, '同步完成');

  final int stepIndex;
  final String description;

  const SyncStep(this.stepIndex, this.description);

  static SyncStep fromIndex(int stepIndex) {
    return SyncStep.values.firstWhere(
      (step) => step.stepIndex == stepIndex,
      orElse: () => SyncStep.preparing,
    );
  }

  static int get count => SyncStep.values.length;
}

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
      for (var media in indices.values) {
        // 仅保留本地文件
        media.mediaFiles.retainWhere((file) => file.isLocal);
      }
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

  /// 当前同步步骤
  SyncStep _currentSyncStep = SyncStep.preparing;

  /// 获取当前同步步骤
  SyncStep get currentSyncStep => _currentSyncStep;

  /// 获取同步步骤总数
  int get syncStepCount => SyncStep.count;

  /// 获取当前同步步骤描述
  String get currentStepDescription => _currentSyncStep.description;

  /// 获取同步状态
  bool get isSyncing => _isSyncing;

  /// 获取同步进度
  int get syncProgress => _syncProgress;

  /// 获取同步错误信息
  String? get syncError => _syncError;

  /// 获取当前同步状态信息
  String? get syncStatusInfo => _syncStatusInfo;

  /// 取消标志，用于终止同步过程
  bool _cancelSync = false;

  /// 终止正在进行的同步
  Future<void> cancelSync() async {
    if (_isSyncing) {
      _cancelSync = true;
      _updateSyncStatus('正在终止同步...');
    }
  }

  /// 判断是否终止同步
  bool get isCancelRequested => _cancelSync;

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
        for (var media in desktopIndices.values) {
          // 仅保留本地文件
          media.mediaFiles.retainWhere((file) => file.isLocal);
        }
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

  /// 更新本地的云端映射表，包括检测本地已删除的文件
  Future<void> _updateCloudMapping() async {
    if (_deviceInfo == null || _cloudMapping == null) return;

    // 收集所有本地媒体文件ID，用于检测删除的文件
    final allLocalMediaIds = <String>{};
    for (final mediaIndex in _mediaIndices.values) {
      for (final media in mediaIndex.mediaFiles) {
        allLocalMediaIds.add(media.info.id);
      }
    }

    // 检测并标记已删除的文件
    for (final mapping in _cloudMapping!.mappings.toList()) {
      // 检查文件是否是本设备创建的（通过检查localPath是否在_appMediaDir内）
      final isLocallyCreated =
          !mapping.localPath.startsWith(_appMediaDir!.path);

      // 只处理本地创建的文件，且已同步到云端的文件
      if (isLocallyCreated &&
          mapping.syncStatus == SyncStatus.synced &&
          !allLocalMediaIds.contains(mapping.mediaId)) {
        // 本地文件已删除，但云端还存在，标记为待删除
        debugPrint('检测到本地已删除文件: ${mapping.mediaId}, 标记为待删除');
        _cloudMapping!.addOrUpdateMapping(
            mapping.copyWithSyncStatus(SyncStatus.pendingDelete));
      }
    }

    // 添加新文件的映射（原有逻辑）
    for (final mediaIndex in _mediaIndices.values) {
      for (final media in mediaIndex.mediaFiles) {
        // 已在映射表中的跳过
        if (_cloudMapping!.findMappingById(media.info.id) != null) continue;

        // 创建云端路径
        final datePath = MediaIndex.getDatePath(media.info.createdAt);
        final cloudPath = '/EchoPixel/$datePath/${media.info.fileName}';

        // 创建新的映射
        final mapping = MediaMapping(
          mediaId: media.info.id,
          localPath: media.info.originalPath,
          cloudPath: cloudPath,
          mediaType: media.info.type.toString().split('.').last,
          createdAt: media.info.createdAt,
          fileSize: media.info.size,
          lastSynced: DateTime.now(),
          syncStatus: SyncStatus.pendingUpload, // 标记为待上传
        );

        _cloudMapping!.addOrUpdateMapping(mapping);
      }
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
    // 在移动平台上启动前台任务
    bool foregroundTaskStarted = false;
    if (!_isDesktopPlatform()) {
      // 启动前台任务
      await ForegroundSyncService.startForegroundTask(
        title: 'Echo Pixel 同步',
        desc: '正在与云端同步媒体文件...',
        onProgressUpdate: (progress) {
          _syncProgress = progress;
        },
      );
      foregroundTaskStarted = true;
    } else {
      // 在桌面平台上使用唤醒锁
      WakelockPlus.toggle(enable: true);
    }

    // 使用锁确保不会并发同步
    final result = await _syncLock.synchronized(() async {
      if (!_initialized) await initialize();
      if (!_webdavService.isConnected) {
        _syncError = 'WebDAV服务未连接';
        return false;
      }

      try {
        // 重置取消标志
        _cancelSync = false;
        _isSyncing = true;
        _syncProgress = 0;
        _syncError = null;

        // 重置同步步骤
        _currentSyncStep = SyncStep.preparing;

        // 更新同步状态
        _updateSyncStatus('正在准备同步...');
        if (foregroundTaskStarted) {
          await ForegroundSyncService.updateNotification(
            title: 'Echo Pixel 同步',
            desc: '正在准备同步...',
          );
        }

        // 检查是否请求取消
        if (_cancelSync) {
          _syncError = '同步已被用户取消';
          _updateSyncStatus('同步已被用户取消');
          return false;
        }

        // 1. 上传本地映射表到云端
        _currentSyncStep = SyncStep.uploadingMapping;
        _updateSyncStatus('正在上传本地映射表...');
        if (foregroundTaskStarted) {
          await ForegroundSyncService.updateNotification(
            title: 'Echo Pixel 同步 (10%)',
            desc: '正在上传本地映射表...',
            progress: 10,
          );
        }
        await _uploadMappingToCloud();
        _syncProgress = 10;

        // 检查是否请求取消
        if (_cancelSync) {
          _syncError = '同步已被用户取消';
          _updateSyncStatus('同步已被用户取消');
          return false;
        }

        // 2. 下载并合并云端的映射表
        _currentSyncStep = SyncStep.downloadingMappings;
        _updateSyncStatus('正在下载并合并云端映射表...');
        if (foregroundTaskStarted) {
          await ForegroundSyncService.updateNotification(
            title: 'Echo Pixel 同步 (20%)',
            desc: '正在下载并合并云端映射表...',
            progress: 20,
          );
        }
        await _downloadAndMergeMappings();
        _syncProgress = 20;

        // 检查是否请求取消
        if (_cancelSync) {
          _syncError = '同步已被用户取消';
          _updateSyncStatus('同步已被用户取消');
          return false;
        }

        // 3. 创建云端目录结构
        _currentSyncStep = SyncStep.creatingDirectories;
        _updateSyncStatus('正在创建云端目录结构...');
        if (foregroundTaskStarted) {
          await ForegroundSyncService.updateNotification(
            title: 'Echo Pixel 同步 (30%)',
            desc: '正在创建云端目录结构...',
            progress: 30,
          );
        }
        await _createCloudDirectories();
        _syncProgress = 30;

        // 检查是否请求取消
        if (_cancelSync) {
          _syncError = '同步已被用户取消';
          _updateSyncStatus('同步已被用户取消');
          return false;
        }

        // 4. 删除已在本地删除的文件
        _currentSyncStep = SyncStep.deletingFiles;
        _updateSyncStatus('正在删除已标记的文件...');
        if (foregroundTaskStarted) {
          await ForegroundSyncService.updateNotification(
            title: 'Echo Pixel 同步 (40%)',
            desc: '正在删除已标记的文件...',
            progress: 40,
          );
        }
        await _deleteMarkedFiles();
        _syncProgress = 40;

        // 检查是否请求取消
        if (_cancelSync) {
          _syncError = '同步已被用户取消';
          _updateSyncStatus('同步已被用户取消');
          return false;
        }

        // 5. 上传待上传的文件
        _currentSyncStep = SyncStep.uploadingFiles;
        _updateSyncStatus('正在上传文件...');
        if (foregroundTaskStarted) {
          await ForegroundSyncService.updateNotification(
            title: 'Echo Pixel 同步 (50%)',
            desc: '正在上传文件...',
            progress: 50,
          );
        }
        await _uploadPendingFiles();
        _syncProgress = 70;
        if (foregroundTaskStarted) {
          await ForegroundSyncService.updateNotification(
            title: 'Echo Pixel 同步 (70%)',
            desc: '文件上传完成',
            progress: 70,
          );
        }

        // 检查是否请求取消
        if (_cancelSync) {
          _syncError = '同步已被用户取消';
          _updateSyncStatus('同步已被用户取消');
          return false;
        }

        // 6. 下载需要的文件
        _currentSyncStep = SyncStep.downloadingFiles;
        _updateSyncStatus('正在下载文件...');
        if (foregroundTaskStarted) {
          await ForegroundSyncService.updateNotification(
            title: 'Echo Pixel 同步 (80%)',
            desc: '正在下载文件...',
            progress: 80,
          );
        }
        await _downloadNeededFiles();
        _syncProgress = 90;
        if (foregroundTaskStarted) {
          await ForegroundSyncService.updateNotification(
            title: 'Echo Pixel 同步 (90%)',
            desc: '文件下载完成',
            progress: 90,
          );
        }

        // 检查是否请求取消
        if (_cancelSync) {
          _syncError = '同步已被用户取消';
          _updateSyncStatus('同步已被用户取消');
          return false;
        }

        // 7. 再次上传更新后的映射表
        _currentSyncStep = SyncStep.savingState;
        _updateSyncStatus('正在保存同步状态...');
        if (foregroundTaskStarted) {
          await ForegroundSyncService.updateNotification(
            title: 'Echo Pixel 同步 (95%)',
            desc: '正在保存同步状态...',
            progress: 95,
          );
        }
        await _uploadMappingToCloud();
        _syncProgress = 100;

        // 标记同步完成
        _currentSyncStep = SyncStep.completed;
        _updateSyncStatus('同步完成');
        if (foregroundTaskStarted) {
          await ForegroundSyncService.updateNotification(
            title: 'Echo Pixel 同步完成',
            desc: '所有文件已同步',
            progress: 100,
          );
        }

        // 8. 更新设备同步时间
        if (_deviceInfo != null) {
          await _deviceInfo!.updateLastSyncTime(DateTime.now());
        }

        return true;
      } catch (e) {
        _syncError = _cancelSync ? '同步已被用户取消' : '同步错误: $e';
        _updateSyncStatus(_cancelSync ? '同步已被用户取消' : '同步出错: ${e.toString()}');
        if (foregroundTaskStarted) {
          await ForegroundSyncService.updateNotification(
            title: 'Echo Pixel 同步',
            desc: _cancelSync ? '同步已被用户取消' : '同步出错: ${e.toString()}',
          );
        }
        return false;
      } finally {
        _isSyncing = false;
        _cancelSync = false; // 重置取消标志
      }
    });

    // 清理工作：停止前台任务或关闭屏幕唤醒
    if (foregroundTaskStarted) {
      // 延迟几秒钟后停止前台任务，让用户能看到完成通知
      await Future.delayed(const Duration(seconds: 5));
      await ForegroundSyncService.stopForegroundTask();
    } else if (_isDesktopPlatform()) {
      WakelockPlus.toggle(enable: false);
    }

    return result;
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
      final limit = PLimit<void>(_maxConcurrentTasks);
      final tasks =
          pendingUploads.map((mapping) => limit(() => processUpload(mapping)));
      await Future.wait(tasks);
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
      final limit = PLimit(_maxConcurrentTasks);
      final tasks = pendingDownloads
          .map((mapping) => limit(() => processDownload(mapping)));
      await Future.wait(tasks);
    } finally {
      // 更新所有映射
      for (final mapping in updatedMappings) {
        _cloudMapping!.addOrUpdateMapping(mapping);
      }

      // 保存更新后的映射表
      await _saveCloudMapping();
    }
  }

  /// 删除标记为待删除的文件
  Future<void> _deleteMarkedFiles() async {
    if (_cloudMapping == null) return;

    // 获取所有待删除的映射
    final pendingDeletes = _cloudMapping!.mappings
        .where((mapping) => mapping.syncStatus == SyncStatus.pendingDelete)
        .toList();

    if (pendingDeletes.isEmpty) {
      debugPrint('没有需要删除的文件');
      return;
    }

    debugPrint('需要删除 ${pendingDeletes.length} 个云端文件');

    // 用于保存已更新的映射和需要移除的映射ID
    final updatedMappings = <MediaMapping>[];
    final removedMappings = <String>[];

    // 处理单个删除任务
    Future<void> processDelete(MediaMapping mapping) async {
      try {
        final fileName = path.basename(mapping.cloudPath);
        debugPrint('删除云端文件: $fileName (${mapping.cloudPath})');

        if (onSyncStatusUpdate != null) {
          onSyncStatusUpdate!("删除: $fileName");
        }

        // 检查云端文件是否存在
        try {
          final fileExists = await _webdavService.fileExists(mapping.cloudPath);
          if (!fileExists) {
            debugPrint('文件在云端不存在，无需删除: ${mapping.cloudPath}');
            // 直接从映射中移除
            removedMappings.add(mapping.mediaId);
            return;
          }
        } catch (e) {
          debugPrint('检查云端文件是否存在时出错: $e');
          // 仍然尝试删除
        }

        // 删除文件
        await _webdavService.deleteFile(mapping.cloudPath);
        debugPrint('成功删除云端文件: ${mapping.cloudPath}');

        // 从映射中移除这个文件
        removedMappings.add(mapping.mediaId);
      } catch (e) {
        // 删除错误，标记为错误状态但保留映射
        debugPrint('删除文件错误：${mapping.cloudPath}，${e.toString()}');
        updatedMappings.add(mapping.copyWithSyncStatus(SyncStatus.error));
      }
    }

    try {
      final limit = PLimit<void>(_maxConcurrentTasks);
      final tasks =
          pendingDeletes.map((mapping) => limit(() => processDelete(mapping)));
      await Future.wait(tasks);
    } finally {
      // 更新所有映射
      for (final mapping in updatedMappings) {
        _cloudMapping!.addOrUpdateMapping(mapping);
      }

      // 从映射中移除已成功删除的文件
      for (final mediaId in removedMappings) {
        _cloudMapping!.removeMapping(mediaId);
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
    for (final stepIndex in _mediaIndices.values) {
      allFiles.addAll(stepIndex.mediaFiles.map((media) => media.info));
    }
    return allFiles;
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

  final mediaDir = Directory('${appDir.path}${Platform.pathSeparator}media');
  if (!await mediaDir.exists()) {
    await mediaDir.create(recursive: true);
  }

  return mediaDir;
}
