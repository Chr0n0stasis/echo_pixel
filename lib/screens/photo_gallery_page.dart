import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:echo_pixel/screens/image_viewer_page.dart';
import 'package:echo_pixel/screens/video_player_page.dart';
import 'package:echo_pixel/screens/webdav_settings.dart';
import 'package:echo_pixel/services/media_cache_service.dart';
import 'package:echo_pixel/services/mobile_media_scanner.dart'; // 导入移动端扫描器
// 移除 VideoPlayerCache 引用
import 'package:echo_pixel/services/video_thumbnail_service.dart'; // 导入视频缩略图服务
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart' as crypto;
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
// 导入 media_kit 相关包，仅用于视频播放页面
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/media_index.dart';
import '../services/media_sync_service.dart';
import '../services/webdav_service.dart';
import '../services/desktop_media_scanner.dart'; // 导入桌面端扫描器

class PhotoGalleryPage extends StatefulWidget {
  final Function()? onSyncRequest; // 同步请求回调
  final Function()? onWebDavSettingsRequest; // 打开WebDAV设置回调
  final Function()? onRefreshRequest; // 刷新请求回调

  // 创建一个控制器，用于从外部访问相册页面的功能
  static final PhotoGalleryController controller = PhotoGalleryController();

  const PhotoGalleryPage({
    super.key,
    this.onSyncRequest,
    this.onWebDavSettingsRequest,
    this.onRefreshRequest,
  });

  @override
  State<PhotoGalleryPage> createState() => PhotoGalleryPageState();
}

// 控制器类，用于从外部访问相册页面的功能
class PhotoGalleryController {
  PhotoGalleryPageState? _state;

  // 注册状态
  void _registerState(PhotoGalleryPageState state) {
    _state = state;
  }

  // 注销状态
  void _unregisterState() {
    _state = null;
  }

  // 执行同步
  void syncWithWebDav() {
    _state?._syncWithWebDav();
  }

  // 打开WebDAV设置
  void openWebDavSettings() {
    _state?._openWebDavSettings();
  }

  // 开始加载/刷新
  void refresh() {
    _state?._startLoading();
  }

  // 获取WebDAV连接状态
  bool get isWebDavConnected => _state?._webdavService.isConnected ?? false;

  // 获取同步状态
  bool get isSyncing => _state?._isSyncing ?? false;

  // 获取同步进度
  int get syncProgress => _state?._syncProgress ?? 0;
}

// 声明公开的状态类，用于公共接口访问
class PhotoGalleryPageState extends State<PhotoGalleryPage> {
  final WebDavService _webdavService = WebDavService();
  late final MediaSyncService _mediaSyncService;

  // 移动端扫描器
  late final MobileMediaScanner _mobileScanner;

  // 桌面端扫描器
  // 注意：目前桌面端扫描器未使用，未来实现桌面端扫描时会用到
  late final DesktopMediaScanner _desktopScanner;

  // 视频缩略图缓存
  final Map<String, Uint8List?> _videoThumbnailCache = {};

  // 视频播放器管理映射 - 管理每个视频路径对应的播放器实例
  final Map<String, Player> _videoPlayers = {};

  // 同步进度定时器
  Timer? _syncProgressTimer;

  // 扫描进度定时器
  Timer? _scanProgressTimer;

  // 媒体服务初始化状态
  bool _isMediaServiceInitialized = false;

  // 是否正在加载
  bool _isLoading = true;

  // 是否正在增量加载更多
  bool _isLoadingMore = false;

  // 是否正在同步
  bool _isSyncing = false;

  // 是否正在扫描
  bool _isScanning = false;

  // 同步进度
  int _syncProgress = 0;

  // 扫描进度
  int _scanProgress = 0;

  // 错误消息
  String? _errorMsg;

  // 同步错误消息
  String? _syncError;

  // 扫描错误消息
  String? _scanError;

  // 当前正在上传的文件信息
  String? _currentUploadInfo;

  // 当前扫描状态信息
  String? _currentScanInfo;

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

  // 初始化变量
  late final MediaCacheService _mediaCacheService = MediaCacheService();
  bool _isFirstLoad = true;
  bool _isCacheLoaded = false;

  // 公开方法供外部调用
  void syncWithWebDav(BuildContext context) {
    _syncWithWebDav();
  }

  void openWebDavSettings() {
    _openWebDavSettings();
  }

  void startLoading() {
    _startLoading();
  }

  // 添加refresh方法，与main.dart中的调用保持一致
  void refresh(BuildContext context) {
    _startLoading();
  }

  // WebDAV连接状态
  bool get isWebDavConnected => _webdavService.isConnected;

  // 同步状态
  bool get isSyncing => _isSyncing;

  // 同步进度
  int get syncProgress => _syncProgress;

  @override
  void initState() {
    super.initState();
    // 向控制器注册当前状态实例，这样按钮就能正常工作了
    PhotoGalleryPage.controller._registerState(this);

    _mediaSyncService = MediaSyncService(_webdavService);

    // 初始化移动端扫描器
    _mobileScanner = MobileMediaScanner(onProgressUpdate: (progress) {
      if (mounted) {
        setState(() {
          _scanProgress = progress;
        });
      }
    }, onScanComplete: (indices) {
      if (mounted) {
        setState(() {
          // 处理扫描结果
          _handleScanResults(indices);
          _isScanning = false;
          _currentScanInfo = "扫描完成，发现 ${indices.length} 个媒体分组";
        });
      }
    }, onScanError: (error) {
      if (mounted) {
        setState(() {
          _scanError = error;
          _isScanning = false;
        });
      }
    });

    // 初始化桌面端扫描器
    _desktopScanner = DesktopMediaScanner();

    // 立即尝试从缓存加载
    _loadFromCacheAndInitialize();
  }

  // 处理扫描结果，将其添加到现有的索引中
  void _handleScanResults(Map<String, MediaIndex> newIndices) {
    // 合并新索引到排序索引列表中
    for (final entry in newIndices.entries) {
      final existingIndex = _sortedIndices
          .firstWhereOrNull((index) => index.datePath == entry.key);

      if (existingIndex != null) {
        // 如果已存在该日期的索引，则合并媒体文件（避免重复）
        final existingIds = <String>{};
        for (final file in existingIndex.mediaFiles) {
          existingIds.add(file.id);
        }

        // 只添加不存在的媒体文件
        for (final file in entry.value.mediaFiles) {
          if (!existingIds.contains(file.id)) {
            existingIndex.mediaFiles.add(file);
          }
        }
      } else {
        // 如果不存在该日期的索引，则直接添加
        _sortedIndices.add(entry.value);
      }
    }

    // 重新组织和排序索引
    _reorganizeIndices();

    // 保存到缓存
    _saveToCache();
  }

  // 从缓存加载媒体索引并初始化必要服务
  Future<void> _loadFromCacheAndInitialize() async {
    // 初始化缓存服务和WebDAV服务
    await Future.wait([
      _mediaCacheService.initialize(),
      _initializeWebDav(),
    ]);

    // 尝试从缓存加载
    bool cacheLoaded = await _tryLoadFromCache();

    // 无论缓存是否加载成功，都初始化媒体服务
    await _mediaSyncService.initialize();

    setState(() {
      _isMediaServiceInitialized = true;
    });

    // 如果缓存加载失败，开始完整加载流程
    if (!cacheLoaded && _isFirstLoad) {
      _isFirstLoad = false;
      await _startFullLoading();
    }
  }

  // 尝试从缓存加载媒体索引
  Future<bool> _tryLoadFromCache() async {
    try {
      // 检查是否有缓存
      if (!await _mediaCacheService.hasCachedIndices()) {
        debugPrint('没有找到媒体缓存索引');
        return false;
      }

      setState(() {
        _isLoading = true;
        _errorMsg = null;
      });

      // 从缓存加载媒体索引
      final cachedIndices = await _mediaCacheService.loadCachedIndices();
      if (cachedIndices == null || cachedIndices.isEmpty) {
        debugPrint('媒体缓存索引为空');
        return false;
      }

      // 将缓存索引转换为列表
      final indexList = cachedIndices.values.toList();

      // 更新UI状态
      setState(() {
        _sortedIndices.clear();
        _sortedIndices.addAll(indexList);
        _reorganizeIndices();
        _isLoading = false;
        _isCacheLoaded = true;
      });

      debugPrint('成功从缓存加载了 ${_sortedIndices.length} 个媒体索引');

      // 检查上次扫描时间，如果超过30秒，启动后台增量扫描
      final lastScanTime = _mediaCacheService.lastScanTime;
      if (lastScanTime != null) {
        final secondsSinceLastScan =
            DateTime.now().difference(lastScanTime).inSeconds;
        if (secondsSinceLastScan > 30) {
          debugPrint('上次媒体扫描已经过去 $secondsSinceLastScan 秒，开始后台增量扫描');

          // 延迟一秒后在后台执行增量扫描
          Future.delayed(const Duration(seconds: 1), () {
            _startIncrementalScan();
          });
        }
      }

      return true;
    } catch (e) {
      debugPrint('从缓存加载媒体索引失败: $e');
      return false;
    }
  }

  // 后台增量扫描 - 只扫描新文件和变化
  Future<void> _startIncrementalScan() async {
    if (_isScanning) return; // 避免重复扫描

    _isScanning = true;
    debugPrint('开始增量扫描媒体文件...');

    try {
      // 创建已存在媒体文件的索引映射（用于快速查找）
      final Map<String, bool> existingFilePaths = {};
      final Map<String, DateTime> existingFileModTimes = {};

      // 收集所有现有文件路径和修改时间
      for (final index in _sortedIndices) {
        for (final file in index.mediaFiles) {
          existingFilePaths[file.originalPath] = true;
          existingFileModTimes[file.originalPath] = file.modifiedAt;
        }
      }

      List<Directory> foldersToScan = [];

      // 根据平台添加要扫描的目录
      if (Platform.isAndroid) {
        // Android平台使用PhotoManager增量扫描
        await _incrementalAndroidScan();
      } else {
        // 添加系统标准媒体目录
        final String homeDir = _getUserHomeDirectory();

        if (Platform.isWindows) {
          final Directory picturesDir =
              Directory(path.join(homeDir, 'Pictures'));
          final Directory videosDir = Directory(path.join(homeDir, 'Videos'));

          if (await picturesDir.exists()) foldersToScan.add(picturesDir);
          if (await videosDir.exists()) foldersToScan.add(videosDir);
        } else if (Platform.isMacOS || Platform.isLinux) {
          final Directory picturesDir =
              Directory(path.join(homeDir, 'Pictures'));
          final Directory videosDir = Directory(path.join(homeDir, 'Movies'));

          if (await picturesDir.exists()) foldersToScan.add(picturesDir);
          if (await videosDir.exists()) foldersToScan.add(videosDir);
        }

        // 对每个目录进行快速扫描
        for (final dir in foldersToScan) {
          await _scanFolderIncrementally(
              dir, existingFilePaths, existingFileModTimes);
        }
      }

      // 保存更新后的缓存
      await _saveToCache();

      debugPrint('增量扫描完成，媒体索引已更新');
    } catch (e) {
      debugPrint('增量扫描错误: $e');
    } finally {
      _isScanning = false;
    }
  }

  // 增量扫描文件夹，只处理新文件或修改过的文件
  Future<void> _scanFolderIncrementally(
      Directory folder,
      Map<String, bool> existingPaths,
      Map<String, DateTime> existingModTimes) async {
    try {
      // 使用更优化的方式扫描目录
      final fileQueue = <FileSystemEntity>[];
      final folders = <Directory>[folder];

      // 使用广度优先遍历
      while (folders.isNotEmpty) {
        final currentDir = folders.removeAt(0);

        try {
          final entities = await currentDir.list().toList();

          for (final entity in entities) {
            if (entity is Directory) {
              // 跳过隐藏文件夹
              if (!path.basename(entity.path).startsWith('.')) {
                folders.add(entity);
              }
            } else if (entity is File) {
              // 检查是否为媒体文件
              final extension = path.extension(entity.path).toLowerCase();
              final ext = extension.replaceAll('.', '');

              if (MediaFileInfo.isImageExtension(ext) ||
                  MediaFileInfo.isVideoExtension(ext)) {
                // 检查文件是否已存在
                if (!existingPaths.containsKey(entity.path)) {
                  // 新文件，需要处理
                  fileQueue.add(entity);
                } else {
                  // 检查文件是否被修改
                  final stat = await entity.stat();
                  final lastModified = stat.modified;
                  final existingModTime = existingModTimes[entity.path];

                  if (existingModTime != null &&
                      lastModified.isAfter(existingModTime)) {
                    // 文件已修改，需要重新处理
                    fileQueue.add(entity);
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('扫描目录出错: ${currentDir.path}: $e');
        }
      }

      // 处理发现的新文件或修改的文件
      int processed = 0;
      for (final file in fileQueue) {
        if (file is File) {
          await _processMediaFile(file);
          processed++;

          // 每处理20个文件，重新排序索引
          if (processed % 20 == 0) {
            _reorganizeIndices();
          }
        }
      }

      if (processed > 0) {
        debugPrint('增量扫描处理了 $processed 个新的或已修改的媒体文件');
        _reorganizeIndices();
      }
    } catch (e) {
      debugPrint('增量扫描目录错误: ${folder.path}, $e');
    }
  }

  // Android增量扫描
  Future<void> _incrementalAndroidScan() async {
    try {
      if (_isScanning) {
        debugPrint('已有扫描任务在进行，跳过增量扫描');
        return;
      }

      setState(() {
        _isScanning = true;
        _currentScanInfo = "正在进行增量扫描...";
        _scanProgress = 0;
      });

      // 获取上次扫描时间
      final lastScanTime = _mediaCacheService.lastScanTime;
      if (lastScanTime == null) {
        debugPrint('没有上次扫描时间记录，无法进行增量扫描');
        setState(() {
          _isScanning = false;
        });
        return;
      }

      // 创建已存在媒体文件的ID集合（用于快速查找）
      final Set<String> existingIds = {};
      for (final index in _sortedIndices) {
        for (final file in index.mediaFiles) {
          existingIds.add(file.id);
        }
      }

      // 启动扫描进度更新定时器
      _scanProgressTimer?.cancel();
      _scanProgressTimer =
          Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (mounted && _isScanning) {
          setState(() {
            _scanProgress = _mobileScanner.scanProgress;
          });
        } else {
          timer.cancel();
        }
      });

      // 使用移动端扫描器执行增量扫描，在单独的隔离进程中执行
      final Map<String, MediaIndex> newIndices =
          await _mobileScanner.incrementalScan(lastScanTime, existingIds);

      // 处理扫描结果
      if (newIndices.isNotEmpty) {
        _handleScanResults(newIndices);
        debugPrint('增量扫描处理了 ${newIndices.length} 个日期组的新媒体文件');

        // 保存更新后的缓存
        await _saveToCache();
      }

      setState(() {
        _isScanning = false;
        _currentScanInfo = newIndices.isEmpty
            ? "增量扫描完成，没有发现新文件"
            : "增量扫描完成，发现 ${_countNewFiles(newIndices)} 个新文件";
      });

      // 取消定时器
      _scanProgressTimer?.cancel();
      _scanProgressTimer = null;
    } catch (e) {
      debugPrint('Android增量扫描错误: $e');
      setState(() {
        _isScanning = false;
        _scanError = '增量扫描出错: $e';
      });

      // 取消定时器
      _scanProgressTimer?.cancel();
      _scanProgressTimer = null;
    }
  }

  // 计算新索引中的媒体文件总数
  int _countNewFiles(Map<String, MediaIndex> indices) {
    int count = 0;
    for (final index in indices.values) {
      count += index.mediaFiles.length;
    }
    return count;
  }

  // 开始完整加载流程
  Future<void> _startFullLoading({bool showLoadingIndicator = true}) async {
    try {
      if (showLoadingIndicator) {
        setState(() {
          _isLoading = true;
          _errorMsg = null;
          _loadProgress = 0.0;
        });
      }

      // 确保媒体服务已初始化
      if (!_isMediaServiceInitialized) {
        await _mediaSyncService.initialize();
        setState(() {
          _isMediaServiceInitialized = true;
        });
      }

      // 清空已有的媒体索引
      _sortedIndices.clear();
      _pendingFolders.clear();
      _pendingFiles.clear();

      // 获取要扫描的目录
      await _initializeScanning();

      // 开始增量加载（第一批）
      await _loadNextBatch();

      // 保存到缓存
      await _saveToCache();

      // 标记初始加载完成
      if (showLoadingIndicator) {
        setState(() {
          _isLoading = false;
        });
      } else {
        setState(() {
          _isCacheLoaded = true;
        });
      }

      // 如果还有更多待处理的文件，继续在背景中加载
      if (_pendingFiles.isNotEmpty || _pendingFolders.isNotEmpty) {
        _loadMoreInBackground();
      }
    } catch (e) {
      debugPrint('加载媒体文件时出错: $e');
      if (showLoadingIndicator) {
        setState(() {
          _errorMsg = '加载媒体文件时出错: $e';
          _isLoading = false;
        });
      }
    }
  }

  // 将媒体索引保存到缓存
  Future<void> _saveToCache() async {
    try {
      // 将列表转换为Map
      final Map<String, MediaIndex> indicesMap = {};
      for (final index in _sortedIndices) {
        indicesMap[index.datePath] = index;
      }

      // 保存到缓存
      final success = await _mediaCacheService.saveIndicesToCache(indicesMap);
      debugPrint('媒体索引${success ? '已' : '未'}保存到缓存');
    } catch (e) {
      debugPrint('保存媒体索引到缓存失败: $e');
    }
  }

  // 开始加载流程 - 兼容现有代码的入口点
  Future<void> _startLoading() async {
    if (_isFirstLoad) {
      _isFirstLoad = false;
      return _startFullLoading();
    } else {
      // 如果不是首次加载，先清除缓存，再进行完整加载
      await _mediaCacheService.clearCache();
      return _startFullLoading();
    }
  }

  // 初始化必要的服务
  Future<void> _initializeServices() async {
    try {
      // 初始化WebDAV服务（如果有保存的配置）
      await _initializeWebDav();

      // 初始化媒体同步服务
      await _mediaSyncService.initialize();

      // 标记媒体服务初始化完成
      setState(() {
        _isMediaServiceInitialized = true;
      });

      debugPrint('媒体服务初始化完成');
    } catch (e) {
      debugPrint('初始化服务错误: $e');
    }
  }

  // 初始化扫描，获取要扫描的目录和文件
  Future<void> _initializeScanning() async {
    // 清空旧的待处理队列
    _pendingFolders.clear();
    _pendingFiles.clear();

    if (Platform.isAndroid) {
      // Android 平台特殊处理
      try {
        debugPrint("Android设备: 开始获取媒体资源");

        // 请求权限
        final PermissionState result =
            await PhotoManager.requestPermissionExtend();
        if (!result.isAuth) {
          debugPrint("Android设备: 权限未授予，状态: ${result.toString()}");
          throw Exception('没有获得访问相册的权限，请在设置中开启存储权限');
        }

        debugPrint("Android设备: 权限已授予，开始获取相册列表");

        // 直接加载媒体文件而不是目录
        await _loadAndroidMediaWithPhotoManager();
        return;
      } catch (e) {
        debugPrint('Android媒体目录初始化错误: $e');
        throw Exception('初始化Android媒体目录失败: $e');
      }
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // 桌面平台处理 - 使用DesktopMediaScanner
      try {
        setState(() {
          _isScanning = true;
          _currentScanInfo = "正在扫描桌面媒体文件...";
          _scanProgress = 0;
        });

        // 启动扫描进度更新定时器
        _scanProgressTimer?.cancel();
        _scanProgressTimer =
            Timer.periodic(const Duration(milliseconds: 500), (timer) {
          if (mounted && _isScanning) {
            setState(() {
              _scanProgress = _desktopScanner.scanProgress;
              _loadProgress = _scanProgress / 100;
            });
          } else {
            timer.cancel();
          }
        });

        // 使用桌面媒体扫描器执行扫描
        final Map<String, MediaIndex> indices =
            await _desktopScanner.scanDesktopMedia();

        // 处理扫描结果
        _handleScanResults(indices);

        setState(() {
          _isScanning = false;
          _currentScanInfo = "扫描完成，发现 ${_countNewFiles(indices)} 个媒体文件";
        });

        // 取消定时器
        _scanProgressTimer?.cancel();
        _scanProgressTimer = null;

        return;
      } catch (e) {
        debugPrint('桌面平台媒体扫描错误: $e');
        setState(() {
          _isScanning = false;
          _scanError = '扫描桌面媒体出错: $e';
        });

        // 取消定时器
        _scanProgressTimer?.cancel();
        _scanProgressTimer = null;

        throw Exception('初始化桌面媒体目录失败: $e');
      }
    } else if (Platform.isIOS) {
      // iOS 平台
      try {
        await _loadIOSMediaWithPhotoManager();
        return;
      } catch (e) {
        debugPrint('iOS媒体初始化错误: $e');
        throw Exception('初始化媒体目录失败: $e');
      }
    } else {
      throw Exception('不支持的平台');
    }
  }

  // 使用 PhotoManager 加载 Android 媒体文件
  Future<void> _loadAndroidMediaWithPhotoManager() async {
    try {
      setState(() {
        _isScanning = true;
        _currentScanInfo = "正在扫描媒体库...";
        _scanProgress = 0;
      });

      // 启动扫描进度更新定时器
      _scanProgressTimer?.cancel();
      _scanProgressTimer =
          Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (mounted && _isScanning) {
          setState(() {
            _scanProgress = _mobileScanner.scanProgress;
            _loadProgress = _scanProgress / 100;
          });
        } else {
          timer.cancel();
        }
      });

      // 使用移动端扫描器执行扫描
      // 扫描器会通过回调函数更新UI和处理结果，不会阻塞UI线程
      await _mobileScanner.scanMobileMedia();

      // 扫描完成后的处理在回调函数中进行，这里不需要额外操作
    } catch (e) {
      debugPrint('加载移动端媒体错误: $e');
      setState(() {
        _errorMsg = '扫描媒体库出错: $e';
        _isScanning = false;
      });

      // 取消定时器
      _scanProgressTimer?.cancel();
      _scanProgressTimer = null;

      rethrow;
    }
  }

  // 为iOS/macOS加载媒体
  Future<void> _loadIOSMediaWithPhotoManager() async {
    // iOS的实现与Android类似
    await _loadAndroidMediaWithPhotoManager();
  }

  // 处理单个Android媒体资源
  Future<void> _processAndroidAsset(AssetEntity asset) async {
    try {
      // 获取媒体文件
      final File? mediaFile = await asset.file;
      if (mediaFile == null) {
        debugPrint('无法获取媒体文件: ${asset.id}');
        return;
      }

      final String originalPath = mediaFile.path;
      final String nameWithoutExt = path.basenameWithoutExtension(originalPath);
      final String extension =
          path.extension(originalPath).replaceAll('.', '').toLowerCase();

      // 确定媒体类型
      MediaType mediaType;
      if (asset.type == AssetType.image) {
        mediaType = MediaType.image;
      } else if (asset.type == AssetType.video) {
        mediaType = MediaType.video;
      } else {
        mediaType = MediaType.unknown;
        return; // 跳过未知类型
      }

      // 生成唯一ID (对于Android资产，我们使用资产ID作为唯一标识)
      final String mediaId = asset.id;

      // 创建分辨率信息
      final MediaResolution resolution = MediaResolution(
        width: asset.width,
        height: asset.height,
      );

      // 获取文件大小
      final int fileSize = await mediaFile.length();

      // 获取日期路径
      final String datePath = MediaIndex.getDatePath(asset.createDateTime);

      // 创建媒体文件信息对象
      final MediaFileInfo mediaInfo = MediaFileInfo(
        id: mediaId,
        originalPath: originalPath,
        name: nameWithoutExt,
        extension: extension,
        size: fileSize,
        type: mediaType,
        createdAt: asset.createDateTime,
        modifiedAt: asset.modifiedDateTime ?? asset.createDateTime,
        resolution: resolution,
        duration: asset.type == AssetType.video ? asset.videoDuration : null,
      );

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
      debugPrint('处理Android媒体资源错误: $e');
    }
  }

  // 添加 Android 标准媒体目录
  Future<bool> _addAndroidMediaDirectories() async {
    bool foundDirectory = false;
    final externalStorageDirs = await Directory('/storage/emulated/0').exists()
        ? [Directory('/storage/emulated/0')]
        : await getExternalStorageDirectories();

    if (externalStorageDirs == null || externalStorageDirs.isEmpty) {
      return false;
    }

    for (final dir in externalStorageDirs) {
      // 添加常见的 Android 媒体目录
      final dcimDir = Directory(path.join(dir.path, 'DCIM'));
      final picturesDir = Directory(path.join(dir.path, 'Pictures'));
      final cameraDir = Directory(path.join(dir.path, 'DCIM', 'Camera'));

      if (await dcimDir.exists()) {
        _pendingFolders.add(dcimDir);
        foundDirectory = true;
        debugPrint('已添加 Android DCIM 目录: ${dcimDir.path}');
      }

      if (await picturesDir.exists()) {
        _pendingFolders.add(picturesDir);
        foundDirectory = true;
        debugPrint('已添加 Android Pictures 目录: ${picturesDir.path}');
      }

      if (await cameraDir.exists()) {
        _pendingFolders.add(cameraDir);
        foundDirectory = true;
        debugPrint('已添加 Android Camera 目录: ${cameraDir.path}');
      }
    }

    return foundDirectory;
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
    return _buildBody();
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
          // 解决图片拉伸问题：使用Container包裹Image，设置背景色避免透明区域
          // 同时使用BoxFit.cover确保图片保持原比例并填满容器
          return Container(
            color: Colors.black, // 给图片设置背景色，避免透明区域
            child: Image.file(
              file,
              fit: BoxFit.cover, // 保持原始比例并填充整个容器
              cacheWidth: 720,
              cacheHeight: 720,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image),
                );
              },
            ),
          );
        }
      } else if (mediaFile.type == MediaType.video) {
        // 解决视频缩略图拉伸问题：使用Container包裹缩略图组件
        return Container(
          color: Colors.black, // 给视频缩略图设置背景色
          child: LazyLoadingVideoThumbnail(videoPath: mediaFile.originalPath),
        );
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
      // 查找当前图片所在的日期索引
      final currentDateIndex = _sortedIndices.firstWhereOrNull(
        (index) => index.mediaFiles.any((file) => file.id == mediaFile.id),
      );

      if (currentDateIndex != null) {
        // 过滤出该日期下的所有图片，以支持左右滑动浏览
        final imagesInSameGroup = currentDateIndex.mediaFiles
            .where((file) => file.type == MediaType.image)
            .toList();

        // 找到当前图片在列表中的索引
        final initialIndex = imagesInSameGroup.indexWhere(
          (file) => file.id == mediaFile.id,
        );

        if (initialIndex != -1) {
          // 打开图片查看器，传入当前图片和同组的所有图片
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ImageViewerPage(
                mediaFile: mediaFile,
                mediaFiles: imagesInSameGroup,
                initialIndex: initialIndex,
              ),
            ),
          );
          return;
        }
      }

      // 如果没有找到同组图片，则只打开单张图片
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ImageViewerPage(mediaFile: mediaFile),
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
    // 解除与控制器的关联
    PhotoGalleryPage.controller._unregisterState();

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
      _currentUploadInfo = "正在准备同步...";
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
      _updateSyncStatus("初始化媒体服务...");
      await _mediaSyncService.initialize();

      // 设置同步状态信息更新回调
      _mediaSyncService.onSyncStatusUpdate = (statusInfo) {
        _updateSyncStatus(statusInfo);
      };

      // 使用现有的媒体索引，而不是重新扫描
      _updateSyncStatus("正在准备媒体数据...");

      // 将现有的媒体索引列表转换为映射，以便传递给媒体同步服务
      final Map<String, MediaIndex> indicesMap = {};
      for (final index in _sortedIndices) {
        indicesMap[index.datePath] = index;
      }

      // 将已有索引传递给同步服务，避免重复扫描
      await _mediaSyncService.setMediaIndices(indicesMap);

      // 执行同步
      _updateSyncStatus("开始与云端同步...");
      final bool success = await _mediaSyncService.syncWithCloud();

      // 同步完成
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgress = _mediaSyncService.syncProgress;
          _syncError = _mediaSyncService.syncError;
          _currentUploadInfo = success ? "同步完成" : "同步失败";
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
          _currentUploadInfo = "同步出错: ${e.toString()}";
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

  // 更新同步状态信息到界面
  void _updateSyncStatus(String status) {
    if (mounted) {
      setState(() {
        _currentUploadInfo = status;
      });
    }
    debugPrint('同步状态: $status');
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

// 懒加载视频缩略图组件 - 使用 VideoThumbnailService 生成缩略图
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
  // 使用视频缩略图服务
  final VideoThumbnailService _thumbnailService = VideoThumbnailService();

  String? _thumbnailPath;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // 使用视频缩略图服务获取缩略图路径
      final thumbnailPath =
          await _thumbnailService.getVideoThumbnail(widget.videoPath);

      if (!mounted) return;

      setState(() {
        _thumbnailPath = thumbnailPath;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('生成视频缩略图错误: ${widget.videoPath} - $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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

    if (_hasError || _thumbnailPath == null) {
      // 显示错误占位符
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Icon(Icons.error_outline, size: 32),
        ),
      );
    }

    // 显示缩略图
    return Image.file(
      File(_thumbnailPath!),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image),
        );
      },
    );
  }
}
