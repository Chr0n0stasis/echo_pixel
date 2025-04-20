import 'dart:io';
import 'package:echo_pixel/services/media_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:p_limit/p_limit.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:crypto/crypto.dart';
import 'package:synchronized/synchronized.dart';

import '../models/media_index.dart';

/// 移动端媒体扫描服务
/// 专门用于扫描Android和iOS设备上的图片和视频
class MobileMediaScanner {
  /// 扫描进度（0-100）
  int _scanProgress = 0;

  /// 扫描错误信息
  String? _scanError;

  /// 是否正在扫描
  bool _isScanning = false;

  /// 媒体索引结果（按日期分组）
  final Map<String, MediaIndex> _mediaIndices = {};

  /// 进度回调
  final Function(int progress)? _onProgressUpdate;

  /// 扫描完成回调
  final Function(Map<String, MediaIndex> indices)? _onScanComplete;

  /// 错误回调
  final Function(String error)? _onScanError;

  /// 最大文件大小（处理哈希时采用块处理的阈值, 50MB）
  static const int _maxFileSize = 50 * 1024 * 1024;

  /// 要跳过的文件大小（超过此大小的文件将跳过处理, 1GB）
  static const int _skipFileSize = 1024 * 1024 * 1024;

  /// 构造函数
  MobileMediaScanner({
    Function(int progress)? onProgressUpdate,
    Function(Map<String, MediaIndex> indices)? onScanComplete,
    Function(String error)? onScanError,
  })  : _onProgressUpdate = onProgressUpdate,
        _onScanComplete = onScanComplete,
        _onScanError = onScanError;

  /// 获取扫描进度
  int get scanProgress => _scanProgress;

  /// 获取扫描错误
  String? get scanError => _scanError;

  /// 是否正在扫描
  bool get isScanning => _isScanning;

  /// 扫描移动设备上的图片和视频
  /// 使用 photo_manager 包访问媒体库
  Future<Map<String, MediaIndex>> scanMobileMedia() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('此方法仅支持移动平台');
    }

    if (_isScanning) {
      throw StateError('已经在扫描中，请等待当前扫描完成');
    }

    try {
      _isScanning = true;
      _scanProgress = 0;
      _scanError = null;
      _mediaIndices.clear();

      _updateProgress(0);

      // 委托给后台隔离进程执行扫描任务
      final result = await _scanMediaInBackground();

      _mediaIndices.addAll(result);
      _updateProgress(100);

      if (_onScanComplete != null) {
        _onScanComplete(_mediaIndices);
      }

      return _mediaIndices;
    } catch (e) {
      _scanError = '扫描出错: $e';
      if (_onScanError != null) {
        _onScanError(_scanError ?? '未知错误');
      }
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  /// 在后台执行实际的扫描任务
  Future<Map<String, MediaIndex>> _scanMediaInBackground() async {
    // 检查权限
    final permResult = await PhotoManager.requestPermissionExtend();
    if (!permResult.isAuth) {
      _scanError = '没有获得媒体访问权限';
      if (_onScanError != null) {
        _onScanError(_scanError ?? '未知错误');
      }
      throw Exception('没有获得媒体访问权限，请在设置中开启相应权限');
    }

    // 获取所有媒体资源路径
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
    );

    if (albums.isEmpty) {
      return {};
    }

    // 获取"全部"相册中的资源
    final allAlbum = albums.first;
    final int totalCount = await allAlbum.assetCountAsync;

    if (totalCount == 0) {
      return {};
    }

    // 使用计算隔离进程处理批量媒体资源
    // 分批次加载，避免一次加载过多导致内存压力
    final Map<String, MediaIndex> result = {};
    const int batchSize = 100;
    int processedCount = 0;

    for (int start = 0; start < totalCount; start += batchSize) {
      final int end =
          (start + batchSize > totalCount) ? totalCount : start + batchSize;

      // 加载这一批次的资源
      final batch = await allAlbum.getAssetListRange(start: start, end: end);

      if (batch.isEmpty) continue;

      // 使用compute在隔离进程中处理资源
      final token = RootIsolateToken.instance!;
      final batchResults = await compute(_processBatch, (batch, token));

      // 合并结果
      for (final entry in batchResults.entries) {
        if (result.containsKey(entry.key)) {
          result[entry.key]!.mediaFiles.addAll(entry.value.mediaFiles);
        } else {
          result[entry.key] = entry.value;
        }
      }

      processedCount += batch.length;
      final progress = ((processedCount / totalCount) * 100).round();
      _updateProgress(progress);
    }

    // 如果没有找到任何媒体文件，尝试使用标准目录
    if (result.isEmpty && Platform.isAndroid) {
      await _tryAddAndroidStandardDirectories();
    }

    return result;
  }

  /// 尝试添加Android标准媒体目录（如果相册为空）
  Future<void> _tryAddAndroidStandardDirectories() async {
    try {
      List<Directory>? externalStorageDirs;

      if (await Directory('/storage/emulated/0').exists()) {
        externalStorageDirs = [Directory('/storage/emulated/0')];
      } else {
        // 使用自定义方法获取存储目录，避免与path_provider包冲突
        externalStorageDirs = await _getAndroidStorageDirectories();
      }

      if (externalStorageDirs == null || externalStorageDirs.isEmpty) {
        return;
      }

      for (final dir in externalStorageDirs) {
        // 尝试扫描常见目录
        final dirsToScan = [
          Directory(path.join(dir.path, 'DCIM')),
          Directory(path.join(dir.path, 'Pictures')),
          Directory(path.join(dir.path, 'DCIM', 'Camera')),
          await getAppMediaDirectory(),
        ];

        for (final scanDir in dirsToScan) {
          if (await scanDir.exists()) {
            // 实现文件系统扫描逻辑
            await _scanDirectoryForMediaFiles(scanDir);
          }
        }
      }
    } catch (e) {
      debugPrint('添加Android标准目录出错: $e');
    }
  }

  /// 扫描目录中的媒体文件
  Future<void> _scanDirectoryForMediaFiles(Directory directory) async {
    try {
      final files = <File>[];

      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final extension = path.extension(entity.path).toLowerCase();
          final ext = extension.replaceAll('.', '');

          if (MediaFileInfo.isImageExtension(ext) ||
              MediaFileInfo.isVideoExtension(ext)) {
            files.add(entity);
          }
        }
      }

      // 使用compute处理文件
      if (files.isNotEmpty) {
        final token = RootIsolateToken.instance!;
        final results = await compute(_processFiles, (token, files));

        // 合并结果
        for (final entry in results.entries) {
          if (_mediaIndices.containsKey(entry.key)) {
            _mediaIndices[entry.key]!.mediaFiles.addAll(entry.value.mediaFiles);
          } else {
            _mediaIndices[entry.key] = entry.value;
          }
        }
      }
    } catch (e) {
      debugPrint('扫描目录出错: ${directory.path}, $e');
    }
  }

  /// 更新进度并通知监听器
  void _updateProgress(int progress) {
    _scanProgress = progress;
    if (_onProgressUpdate != null) {
      _onProgressUpdate(progress);
    }
  }

  /// 获取按日期组织的媒体索引
  Map<String, MediaIndex> getMediaIndices() {
    return Map.unmodifiable(_mediaIndices);
  }

  /// 获取Android存储目录（避免与path_provider冲突）
  Future<List<Directory>?> _getAndroidStorageDirectories() async {
    try {
      if (Platform.isAndroid) {
        // 使用path_provider包的方法，但重命名避免冲突
        final dirs = await path_provider.getExternalStorageDirectories();
        return dirs;
      }
      return null;
    } catch (e) {
      debugPrint('获取外部存储目录出错: $e');
      return null;
    }
  }
}

/// 在隔离进程中处理一批媒体资源
Future<Map<String, MediaIndex>> _processBatch(
    (List<AssetEntity>, RootIsolateToken) args) async {
  final (batch, token) = args;
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final Map<String, MediaIndex> batchResult = {};
  final lock = Lock();

  final limit = PLimit(16);
  final tasks = batch.map((asset) => limit(() async {
        try {
          final mediaInfo = await _processAssetToMediaInfo(asset);
          if (mediaInfo != null) {
            final datePath = MediaIndex.getDatePath(asset.createDateTime);

            await lock.synchronized(() {
              if (!batchResult.containsKey(datePath)) {
                batchResult[datePath] = MediaIndex(
                  datePath: datePath,
                  mediaFiles: [],
                );
              }

              batchResult[datePath]!.mediaFiles.add(mediaInfo);
            });
          }
        } catch (e) {
          debugPrint('处理资源出错: ${asset.id}, $e');
        }
      }));
  await Future.wait(tasks);

  return batchResult;
}

/// 在隔离进程中处理一批文件
Future<Map<String, MediaIndex>> _processFiles(
    (RootIsolateToken, List<File>) args) async {
  final (token, files) = args;
  // 确保在隔离进程中初始化BackgroundIsolateBinaryMessenger
  // 这是修复"BackgroundIsolateBinaryMessenger.instance值无效"错误的关键
  try {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  } catch (e) {
    debugPrint('初始化BackgroundIsolateBinaryMessenger失败: $e');
    // 继续执行，因为有些平台或者Flutter版本可能不需要这个步骤
  }

  final Map<String, MediaIndex> result = {};
  int skippedCount = 0;

  for (final file in files) {
    try {
      final filePath = file.path;
      final fileSize = await file.length();

      // 跳过特别大的文件，避免内存溢出
      if (fileSize > MobileMediaScanner._skipFileSize) {
        debugPrint('跳过大文件: ${file.path} (${_formatSize(fileSize)})');
        skippedCount++;
        continue;
      }

      final stat = await file.stat();

      final String nameWithoutExt = path.basename(filePath).split('.').first;
      final String extension =
          path.extension(filePath).replaceAll('.', '').toLowerCase();

      // 获取文件类型
      final MediaType mediaType = MediaFileInfo.inferTypeFromPath(filePath);

      if (mediaType != MediaType.unknown) {
        // 确定文件的实际创建日期
        DateTime? createdAt;

        // 检查文件路径是否包含从云端同步的标志
        final appDir = await path_provider.getApplicationSupportDirectory();
        final bool isCloudSyncedFile =
            filePath.contains('${appDir.path}${Platform.pathSeparator}media');

        if (isCloudSyncedFile) {
          // 如果是从云端同步到本地的文件，尝试从路径中提取日期
          // 路径格式通常是: \media\YYYY\MM\DD\filename.ext
          try {
            // 路径片段
            final pathSegments = filePath.split(Platform.pathSeparator);

            // 查找media目录之后的三个连续段
            int mediaIndex = pathSegments.indexOf('media');
            if (mediaIndex != -1 && mediaIndex + 3 < pathSegments.length) {
              final yearStr = pathSegments[mediaIndex + 1];
              final monthStr = pathSegments[mediaIndex + 2];
              final dayStr = pathSegments[mediaIndex + 3];

              // 检查是否是年/月/日格式
              final yearRegex = RegExp(r'^\d{4}$');
              final monthDayRegex = RegExp(r'^\d{2}$');

              if (yearRegex.hasMatch(yearStr) &&
                  monthDayRegex.hasMatch(monthStr) &&
                  monthDayRegex.hasMatch(dayStr)) {
                final year = int.tryParse(yearStr);
                final month = int.tryParse(monthStr);
                final day = int.tryParse(dayStr);

                if (year != null && month != null && day != null) {
                  // 创建日期对象
                  createdAt = DateTime(year, month, day);
                  debugPrint(
                      '从路径提取日期: $yearStr/$monthStr/$dayStr -> $createdAt');
                }
              }
            }
          } catch (e) {
            debugPrint('从路径提取日期错误: $e, 将使用文件修改时间');
          }
        }

        // 如果没有从路径中提取到日期，则使用文件的修改时间
        createdAt ??= stat.modified;
        final DateTime modifiedAt = stat.modified;

        // 生成安全的ID，对于大文件使用流式处理
        final String mediaId = await _generateFileHash(file, fileSize);

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

        // 添加到对应日期的索引中
        if (!result.containsKey(datePath)) {
          result[datePath] = MediaIndex(
            datePath: datePath,
            mediaFiles: [],
          );
        }

        result[datePath]!.mediaFiles.add(mediaInfo);
      }
    } catch (e) {
      debugPrint('处理文件出错: ${file.path}, $e');
    }
  }

  if (skippedCount > 0) {
    debugPrint('已跳过 $skippedCount 个过大的文件');
  }

  return result;
}

/// 为文件生成哈希值，对于大文件使用流式处理
Future<String> _generateFileHash(File file, int fileSize) async {
  // 对于小文件，使用简单的路径和大小组合作为ID
  if (fileSize < MobileMediaScanner._maxFileSize) {
    return '${file.path}:$fileSize:${DateTime.now().millisecondsSinceEpoch}';
  }
  // 对于中等大小文件，计算部分内容的哈希值
  else if (fileSize < MobileMediaScanner._skipFileSize) {
    try {
      // 只读取文件开头的部分进行哈希计算，避免内存溢出
      final input = file.openRead(0, 1024 * 1024); // 读取前1MB
      final bytes = await input.fold<List<int>>(
        <int>[],
        (List<int> previous, List<int> element) {
          previous.addAll(element);
          return previous;
        },
      );

      // 计算哈希
      final hash = sha256.convert(bytes);
      return '${hash.toString()}:${file.path}:$fileSize';
    } catch (e) {
      debugPrint('生成文件哈希出错: ${file.path}, $e');
      // 失败时回退到简单的组合ID
      return '${file.path}:$fileSize:${DateTime.now().millisecondsSinceEpoch}';
    }
  }
  // 对于特别大的文件，不应该到这里，但以防万一
  else {
    return '${file.path}:$fileSize:${DateTime.now().millisecondsSinceEpoch}';
  }
}

/// 格式化文件大小
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

/// 将AssetEntity转换为MediaFileInfo
Future<MediaFileInfo?> _processAssetToMediaInfo(AssetEntity asset) async {
  try {
    // 获取媒体文件
    final File? mediaFile = await asset.file;
    if (mediaFile == null) {
      return null;
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
      return null; // 跳过未知类型
    }

    // 获取文件大小
    int fileSize;
    try {
      fileSize = await mediaFile.length();

      // 跳过特别大的文件，避免内存溢出
      if (fileSize > MobileMediaScanner._skipFileSize) {
        debugPrint('跳过大文件: $originalPath (${_formatSize(fileSize)})');
        return null;
      }
    } catch (e) {
      // 如果获取文件大小失败，使用一个默认值
      debugPrint('获取文件大小出错: $originalPath, $e');
      fileSize = 0;
    }

    // 创建分辨率信息
    final MediaResolution resolution = MediaResolution(
      width: asset.width,
      height: asset.height,
    );

    // 使用安全的方式生成ID
    final String mediaId = asset.id;

    // 创建媒体文件信息对象
    return MediaFileInfo(
      id: mediaId,
      originalPath: originalPath,
      name: nameWithoutExt,
      extension: extension,
      size: fileSize,
      type: mediaType,
      createdAt: asset.createDateTime,
      modifiedAt: asset.modifiedDateTime,
      resolution: resolution,
      duration: asset.type == AssetType.video ? asset.videoDuration : null,
    );
  } catch (e) {
    debugPrint('处理资源出错: ${asset.id}, $e');
    return null;
  }
}
