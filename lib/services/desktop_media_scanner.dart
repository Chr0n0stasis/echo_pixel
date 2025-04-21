import 'dart:io';
import 'package:echo_pixel/services/media_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_index.dart';

/// 桌面端媒体扫描服务
/// 专门用于扫描桌面系统上的图片和视频
class DesktopMediaScanner {
  /// 扫描进度（0-100）
  int _scanProgress = 0;

  /// 扫描错误信息
  String? _scanError;

  /// 是否正在扫描
  bool _isScanning = false;

  /// 媒体索引结果（按日期分组）
  final Map<String, MediaIndex> _mediaIndices = {};

  /// 最大文件大小（处理哈希时采用块处理的阈值, 50MB）
  static const int _maxFileSize = 50 * 1024 * 1024;

  /// 要跳过的文件大小（超过此大小的文件将跳过处理, 2GB）
  static const int _skipFileSize = 2 * 1024 * 1024 * 1024;

  /// 获取扫描进度
  int get scanProgress => _scanProgress;

  /// 获取扫描错误
  String? get scanError => _scanError;

  /// 是否正在扫描
  bool get isScanning => _isScanning;

  /// 扫描桌面系统上的图片和视频
  /// 仅扫描用户目录下的Pictures和Videos文件夹
  Future<Map<String, MediaIndex>> scanDesktopMedia() async {
    if (kIsWeb || (Platform.isAndroid || Platform.isIOS)) {
      throw UnsupportedError('此方法仅支持桌面平台');
    }

    if (_isScanning) {
      throw StateError('已经在扫描中，请等待当前扫描完成');
    }

    try {
      _isScanning = true;
      _scanProgress = 0;
      _scanError = null;
      _mediaIndices.clear();

      final prefs = await SharedPreferences.getInstance();
      final scanFolders = prefs.getStringList('scan_folders');
      final cloudMediaFolder = await getAppMediaDirectory();

      // 要扫描的目录列表
      final List<Directory> dirsToScan = scanFolders != null
          ? scanFolders.map((folder) => Directory(folder)).toList()
          : [];
      // 添加云端媒体目录
      dirsToScan.add(cloudMediaFolder);

      debugPrint('扫描目录: ${scanFolders!.join(', ')}');

      // 收集所有媒体文件
      final List<FileSystemEntity> allMediaFiles = [];

      // 扫描所有指定的目录
      for (final dir in dirsToScan) {
        try {
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              final extension = path.extension(entity.path).toLowerCase();

              // 检查是否是受支持的媒体文件类型
              if (MediaFileInfo.isImageExtension(
                    extension.replaceAll('.', ''),
                  ) ||
                  MediaFileInfo.isVideoExtension(
                    extension.replaceAll('.', ''),
                  )) {
                allMediaFiles.add(entity);
              }
            }
          }
        } catch (e) {
          debugPrint('扫描目录错误: ${dir.path}, $e');
          // 继续扫描其他目录
        }
      }

      // 处理找到的媒体文件
      int processedCount = 0;
      int skippedCount = 0;
      for (final entity in allMediaFiles) {
        try {
          final file = entity as File;
          final fileSize = await file.length();

          // 跳过特别大的文件
          if (fileSize > _skipFileSize) {
            debugPrint('跳过大文件: ${file.path} (${_formatSize(fileSize)})');
            skippedCount++;
            continue;
          }

          await _processMediaFile(file);
        } catch (e) {
          debugPrint('处理媒体文件错误: ${entity.path}, $e');
          // 继续处理其他文件
        }

        // 更新进度
        processedCount++;
        _scanProgress = ((processedCount / allMediaFiles.length) * 100).round();
      }

      if (skippedCount > 0) {
        debugPrint('已跳过 $skippedCount 个过大的文件');
      }

      return _mediaIndices;
    } catch (e) {
      _scanError = '扫描出错: $e';
      rethrow;
    } finally {
      _isScanning = false;
      _scanProgress = 0;
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

  /// 处理单个媒体文件
  Future<void> _processMediaFile(File file) async {
    try {
      final String filePath = file.path;
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
      final int fileSize = stat.size;

      // 确定文件的实际创建日期
      DateTime? createdAt;

      // 检查文件路径是否包含从云端同步的标志（例如应用专属目录中的文件）
      final appDir = await getApplicationSupportDirectory();
      final bool isCloudSyncedFile =
          filePath.contains('${appDir.path}${Platform.pathSeparator}media');

      if (isCloudSyncedFile) {
        // 如果是从云端同步到本地的文件，尝试从路径中提取日期
        // Windows路径格式通常是: \media\YYYY\MM\DD\filename.ext
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
                debugPrint('从路径提取日期: $yearStr/$monthStr/$dayStr -> $createdAt');
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

      // 生成媒体ID (使用流式处理大文件)
      final String mediaId = await _generateFileHash(file);

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
      if (!_mediaIndices.containsKey(datePath)) {
        _mediaIndices[datePath] = MediaIndex(
          datePath: datePath,
          mediaFiles: [],
        );
      }

      // 添加到对应日期的索引中
      _mediaIndices[datePath]!
          .mediaFiles
          .add(MediaFile(info: mediaInfo, isLocal: !isCloudSyncedFile));
    } catch (e) {
      debugPrint('处理媒体文件出错: ${file.path}, $e');
      // 抛出异常，让调用者处理
      rethrow;
    }
  }

  /// 为文件生成哈希值，对于大文件使用流式处理
  Future<String> _generateFileHash(File file) async {
    final fileSize = await file.length();

    // 对于小文件，可以直接读取到内存
    if (fileSize < _maxFileSize) {
      final bytes = await file.readAsBytes();
      return sha256.convert(bytes).toString();
    }
    // 对于大文件，使用流式处理
    else {
      final input = file.openRead();
      final streamDigest = await sha256.bind(input).first;
      return streamDigest.toString();
    }
  }

  /// 获取按日期组织的媒体索引
  Map<String, MediaIndex> getMediaIndices() {
    return Map.unmodifiable(_mediaIndices);
  }
}
