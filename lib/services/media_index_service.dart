import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import '../models/media_index.dart';
import 'mobile_media_scanner.dart';
import 'desktop_media_scanner.dart';
import 'media_cache_service.dart';

/// 媒体索引服务类
/// 提供单例模式的媒体索引管理，确保整个应用中使用相同的媒体索引数据
class MediaIndexService extends ChangeNotifier {
  static final MediaIndexService _instance = MediaIndexService._internal();

  factory MediaIndexService() {
    return _instance;
  }

  MediaIndexService._internal() {
    _initialize();
  }

  // 存储媒体索引的映射
  Map<String, MediaIndex> _mediaIndices = {};

  // 平台特定的扫描器
  late MobileMediaScanner _mobileScanner;
  late DesktopMediaScanner _desktopScanner;

  // 缓存服务
  late MediaCacheService _mediaCacheService;

  // 同步锁，确保不会同时进行多个扫描操作
  final Lock _scanLock = Lock();

  // 状态变量
  bool _isScanning = false;
  int _scanProgress = 0;
  String? _scanError;

  // 构造函数中不能使用async，所以使用单独的初始化方法
  Future<void> _initialize() async {
    _mediaCacheService = MediaCacheService();
    await _mediaCacheService.initialize();

    // 初始化扫描器
    _desktopScanner = DesktopMediaScanner();
    _mobileScanner = MobileMediaScanner(onProgressUpdate: (progress) {
      _scanProgress = progress;
    }, onScanComplete: (indices) {
      _handleScanResults(indices);
      _isScanning = false;
      notifyListeners();
    }, onScanError: (error) {
      _scanError = error;
      _isScanning = false;
      notifyListeners();
    });

    // 尝试从缓存加载
    await _tryLoadFromCache();
  }

  // 获取所有媒体索引的只读视图
  Map<String, MediaIndex> get indices => Map.unmodifiable(_mediaIndices);

  // 检查是否为空
  bool get isEmpty => _mediaIndices.isEmpty;

  // 扫描状态
  bool get isScanning => _isScanning;
  int get scanProgress => _scanProgress;
  String? get scanError => _scanError;

  // 获取媒体文件总数
  int get totalMediaCount {
    int count = 0;
    for (final index in _mediaIndices.values) {
      count += index.mediaFiles.length;
    }
    return count;
  }

  // 获取照片数量（仅图片类型）
  int get imageCount {
    int count = 0;
    for (final index in _mediaIndices.values) {
      count += index.mediaFiles
          .where((file) => file.info.type == MediaType.image)
          .length;
    }
    return count;
  }

  // 获取视频数量
  int get videoCount {
    int count = 0;
    for (final index in _mediaIndices.values) {
      count += index.mediaFiles
          .where((file) => file.info.type == MediaType.video)
          .length;
    }
    return count;
  }

  // 更新媒体索引
  void updateIndices(Map<String, MediaIndex> indices) {
    _mediaIndices = Map.from(indices);
    notifyListeners();
    debugPrint(
        '媒体索引已更新，共有 ${indices.length} 个日期组，$totalMediaCount 个媒体文件，$imageCount 张照片');

    // 保存到缓存
    _saveToCache();
  }

  // 根据ID查找媒体文件
  MediaFileInfo? findMediaById(String mediaId) {
    for (final index in _mediaIndices.values) {
      for (final media in index.mediaFiles) {
        if (media.info.id == mediaId) {
          return media.info;
        }
      }
    }
    return null;
  }

  // 获取特定类型的所有媒体文件ID
  List<String> getMediaIdsOfType(MediaType type) {
    final List<String> ids = [];
    for (final index in _mediaIndices.values) {
      for (final media in index.mediaFiles) {
        if (media.info.type == type) {
          ids.add(media.info.id);
        }
      }
    }
    return ids;
  }

  // 清空索引
  void clear() {
    _mediaIndices.clear();
    notifyListeners();
    debugPrint('媒体索引已清空');
  }

  // 新增方法：扫描媒体文件
  Future<bool> scanMedia() async {
    return _scanLock.synchronized(() async {
      if (_isScanning) {
        debugPrint('已有扫描任务在进行中，跳过');
        return false;
      }

      _isScanning = true;
      _scanProgress = 0;
      _scanError = null;
      notifyListeners();

      try {
        // 根据平台选择不同的扫描方法
        if (_isDesktopPlatform()) {
          await _scanDesktopMedia();
        } else {
          await _scanMobileMedia();
        }

        // 保存到缓存
        await _saveToCache();

        return true;
      } catch (e, stack) {
        _scanError = '$e\n$stack'; // 包含异常和堆栈信息
        debugPrint('扫描媒体文件出错: $_scanError');
        notifyListeners();
        return false;
      } finally {
        _isScanning = false;
        notifyListeners();
      }
    });
  }

  // 新增方法：扫描桌面媒体
  Future<void> _scanDesktopMedia() async {
    if (!_isDesktopPlatform()) {
      throw UnsupportedError('此方法仅支持桌面平台');
    }

    final indices = await _desktopScanner.scanDesktopMedia();
    _handleScanResults(indices);
  }

  // 新增方法：扫描移动端媒体
  Future<void> _scanMobileMedia() async {
    if (!_isMobilePlatform()) {
      throw UnsupportedError('此方法仅支持移动平台');
    }

    // 使用移动端扫描器
    await _mobileScanner.scanMobileMedia();
    // 结果会通过回调处理
  }

  // 新增方法：判断是否为桌面平台
  bool _isDesktopPlatform() {
    return !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  }

  // 新增方法：判断是否为移动平台
  bool _isMobilePlatform() {
    return !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  }

  // 新增方法：尝试扫描
  Future<bool> tryScan() async {
    return await _scanLock.synchronized(() async {
      if (_isScanning) {
        debugPrint('已有扫描任务在进行中，跳过扫描');
        return false;
      }

      _isScanning = true;
      notifyListeners();

      try {
        final lastScanTime = _mediaCacheService.lastScanTime;
        if (lastScanTime == null) {
          debugPrint('没有上次扫描时间记录，无法进行扫描');
          return false;
        }

        // 创建现有媒体文件的ID集合
        final Set<String> existingIds = {};
        for (final index in _mediaIndices.values) {
          for (final file in index.mediaFiles) {
            existingIds.add(file.info.id);
          }
        }

        if (_isMobilePlatform()) {
          await _scanMobileMedia();
          return true;
        } else if (_isDesktopPlatform()) {
          await _scanDesktopMedia();
          return true;
        }

        return false;
      } catch (e) {
        debugPrint('扫描错误: $e');
        _scanError = e.toString();
        return false;
      } finally {
        _isScanning = false;
        notifyListeners();
      }
    });
  }

  // 处理扫描结果
  void _handleScanResults(Map<String, MediaIndex> newIndices) {
    bool hasUpdates = false;

    for (final entry in newIndices.entries) {
      if (_mediaIndices.containsKey(entry.key)) {
        // 如果已存在该日期的索引，合并媒体文件（避免重复）
        final existingIndex = _mediaIndices[entry.key]!;
        final existingIds = <String>{};
        for (final file in existingIndex.mediaFiles) {
          existingIds.add(file.info.id);
        }

        // 只添加不存在的媒体文件
        for (final file in entry.value.mediaFiles) {
          if (!existingIds.contains(file.info.id)) {
            existingIndex.mediaFiles.add(file);
            hasUpdates = true;
          }
        }
      } else {
        // 如果不存在该日期的索引，则直接添加
        _mediaIndices[entry.key] = entry.value;
        hasUpdates = true;
      }
    }

    if (hasUpdates) {
      _reorganizeIndices();
      notifyListeners();

      // 使用防抖保存，而不是等待全部完成
      _debouncedSaveToCache();
    }
  }

  // 重新组织索引
  void _reorganizeIndices() {
    // 对每个日期中的文件进行排序
    for (final index in _mediaIndices.values) {
      index.mediaFiles
          .sort((a, b) => a.info.createdAt.compareTo(b.info.createdAt));
    }
  }

  // 使用防抖机制的保存方法
  void _debouncedSaveToCache() {
    _mediaCacheService.debouncedSaveIndicesToCache(_mediaIndices);
  }

  // 尝试从缓存加载索引
  Future<bool> _tryLoadFromCache() async {
    try {
      // 检查是否有缓存
      if (!await _mediaCacheService.hasCachedIndices()) {
        debugPrint('没有找到媒体缓存索引');
        return false;
      }

      // 从缓存加载媒体索引
      final cachedIndices = await _mediaCacheService.loadCachedIndices();
      if (cachedIndices == null || cachedIndices.isEmpty) {
        debugPrint('媒体缓存索引为空');
        return false;
      }

      // 更新索引
      _mediaIndices = Map.from(cachedIndices);

      // 重新组织索引
      _reorganizeIndices();

      debugPrint(
          '成功从缓存加载了 ${_mediaIndices.length} 个媒体索引，共 $totalMediaCount 个媒体文件');
      notifyListeners();

      return true;
    } catch (e) {
      debugPrint('从缓存加载媒体索引失败: $e');
      return false;
    }
  }

  // 将媒体索引保存到缓存
  Future<void> _saveToCache() async {
    try {
      // 使用强制保存，确保最终状态被持久化
      final success =
          await _mediaCacheService.forceSaveIndicesToCache(_mediaIndices);
      debugPrint('媒体索引${success ? '已' : '未'}保存到缓存');
    } catch (e) {
      debugPrint('保存媒体索引到缓存失败: $e');
    }
  }
}
