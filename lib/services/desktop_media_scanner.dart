import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';

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

      // 获取用户主目录
      final String homeDir = _getUserHomeDirectory();

      // 图片和视频目录路径
      final String picturesDir = path.join(homeDir, 'Pictures');
      final String videosDir = path.join(homeDir, 'Videos');

      // 要扫描的目录列表
      final List<Directory> dirsToScan = [];

      // 添加图片目录（如果存在）
      if (await Directory(picturesDir).exists()) {
        dirsToScan.add(Directory(picturesDir));
      }

      // 添加视频目录（如果存在）
      if (await Directory(videosDir).exists()) {
        dirsToScan.add(Directory(videosDir));
      }

      if (dirsToScan.isEmpty) {
        _scanError = '未找到Pictures或Videos文件夹';
        return _mediaIndices;
      }

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

  /// 获取用户主目录
  String _getUserHomeDirectory() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '';
    } else {
      return Platform.environment['HOME'] ?? '';
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
      final int fileSize = stat.size;

      // 使用文件的修改时间作为创建时间（受限于文件系统API）
      final DateTime createdAt = stat.modified;
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
      _mediaIndices[datePath]!.mediaFiles.add(mediaInfo);
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

  /// 获取媒体文件的缩略图（支持图片和视频）
  /// 目前仅支持图片，视频需要额外依赖项处理
  Future<Uint8List?> getThumbnail(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final extension =
          path.extension(filePath).toLowerCase().replaceAll('.', '');

      // 如果是图片，使用更节省内存的方式加载缩略图
      if (MediaFileInfo.isImageExtension(extension)) {
        // 这里应该实现真正的缩略图创建，而不是加载整个图片
        // 实际项目中应该使用 flutter_native_image 或类似库处理缩略图
        // 这里简化处理，返回完整图片但限制大小
        final fileSize = await file.length();
        if (fileSize > _maxFileSize) {
          return null; // 对于大图片，暂时不加载
        }
        return await file.readAsBytes();
      }

      // 对于视频，需要使用FFmpeg等工具生成缩略图
      return null;
    } catch (e) {
      debugPrint('获取缩略图错误: $e');
      return null;
    }
  }

  /// 获取按日期组织的媒体索引
  Map<String, MediaIndex> getMediaIndices() {
    return Map.unmodifiable(_mediaIndices);
  }
}
