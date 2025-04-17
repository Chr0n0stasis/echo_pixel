import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import '../models/photo_model.dart';
import '../models/media_index.dart';
import '../models/cloud_mapping.dart';
import '../services/media_sync_service.dart';
import '../services/webdav_service.dart'; // 添加WebDavService导入

/// 相册服务类
/// 负责管理相册的创建、修改、删除以及相册数据的持久化
class AlbumService with ChangeNotifier {
  static final AlbumService _instance = AlbumService._internal();

  factory AlbumService() {
    return _instance;
  }

  AlbumService._internal() {
    loadAlbums();
  }

  // 相册列表
  List<Album> _albums = [];

  // 获取所有相册
  List<Album> get albums => List.unmodifiable(_albums);

  // 获取本地相册列表
  List<Album> get localAlbums =>
      _albums.where((album) => album.albumType == AlbumType.local).toList();

  // 获取云相册列表
  List<Album> get cloudAlbums =>
      _albums.where((album) => album.albumType == AlbumType.cloud).toList();

  // 加载所有相册
  Future<void> loadAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final albumsData = prefs.getStringList('albums') ?? [];

      _albums = albumsData
          .map((albumJson) {
            try {
              return Album.fromJson(json.decode(albumJson));
            } catch (e) {
              debugPrint('解析相册数据出错: $e');
              return null;
            }
          })
          .whereType<Album>()
          .toList();

      notifyListeners();
      debugPrint('已加载${_albums.length}个相册');
    } catch (e) {
      debugPrint('加载相册数据失败: $e');
    }
  }

  // 保存所有相册
  Future<void> saveAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final albumsData =
          _albums.map((album) => json.encode(album.toJson())).toList();
      await prefs.setStringList('albums', albumsData);
      debugPrint('已保存${_albums.length}个相册');
    } catch (e) {
      debugPrint('保存相册数据失败: $e');
    }
  }

  // 创建新的本地相册
  Future<Album> createLocalAlbum({
    required String name,
    String? description,
    List<String> photoIds = const [],
    String? coverPhotoId,
    String? localFolderPath,
  }) async {
    final album = Album(
      id: const Uuid().v4(),
      name: name,
      description: description,
      createdAt: DateTime.now(),
      photoIds: List<String>.from(photoIds),
      coverPhotoId:
          coverPhotoId ?? (photoIds.isNotEmpty ? photoIds.first : null),
      isSynced: false,
      albumType: AlbumType.local,
      localFolderPath: localFolderPath,
    );

    _albums.add(album);
    await saveAlbums();
    notifyListeners();

    return album;
  }

  // 创建新的云相册
  Future<Album> createCloudAlbum({
    required String name,
    String? description,
    List<String> photoIds = const [],
    String? coverPhotoId,
  }) async {
    // 过滤出已在云端同步的照片，云相册只能包含已同步的照片
    final syncedPhotoIds = await _filterSyncedPhotos(photoIds);

    final album = Album(
      id: const Uuid().v4(),
      name: name,
      description: description,
      createdAt: DateTime.now(),
      photoIds: syncedPhotoIds,
      coverPhotoId: coverPhotoId ??
          (syncedPhotoIds.isNotEmpty ? syncedPhotoIds.first : null),
      isSynced: false, // 初始创建为未同步状态，需要下一次云同步来更新
      albumType: AlbumType.cloud,
      pendingCloudPhotosCount: 0, // 初始创建时没有待下载的照片
    );

    _albums.add(album);
    await saveAlbums();
    notifyListeners();

    return album;
  }

  // 创建新相册（兼容旧代码）
  Future<Album> createAlbum({
    required String name,
    String? description,
    List<String> photoIds = const [],
    String? coverPhotoId,
    AlbumType albumType = AlbumType.local,
    String? localFolderPath,
  }) async {
    if (albumType == AlbumType.cloud) {
      return createCloudAlbum(
        name: name,
        description: description,
        photoIds: photoIds,
        coverPhotoId: coverPhotoId,
      );
    } else {
      return createLocalAlbum(
        name: name,
        description: description,
        photoIds: photoIds,
        coverPhotoId: coverPhotoId,
        localFolderPath: localFolderPath,
      );
    }
  }

  // 更新相册
  Future<Album> updateAlbum(Album album) async {
    final index = _albums.indexWhere((a) => a.id == album.id);

    if (index >= 0) {
      _albums[index] = album;
      await saveAlbums();
      notifyListeners();
      return album;
    } else {
      throw Exception('相册不存在');
    }
  }

  // 删除相册
  Future<void> deleteAlbum(String albumId) async {
    _albums.removeWhere((album) => album.id == albumId);
    await saveAlbums();
    notifyListeners();
  }

  // 根据ID查找相册
  Album? getAlbumById(String albumId) {
    try {
      return _albums.firstWhere((album) => album.id == albumId);
    } catch (e) {
      return null;
    }
  }

  // 向相册添加照片
  Future<Album> addPhotosToAlbum(String albumId, List<String> photoIds) async {
    final album = getAlbumById(albumId);

    if (album == null) {
      throw Exception('相册不存在');
    }

    // 根据相册类型使用不同的添加逻辑
    if (album.albumType == AlbumType.cloud) {
      return addPhotosToCloudAlbum(albumId, photoIds);
    } else {
      return addPhotosToLocalAlbum(albumId, photoIds);
    }
  }

  // 向本地相册添加照片
  Future<Album> addPhotosToLocalAlbum(
      String albumId, List<String> photoIds) async {
    final album = getAlbumById(albumId);
    if (album == null || album.albumType != AlbumType.local) {
      throw Exception('本地相册不存在');
    }

    // 创建一个新的照片ID列表，确保不重复
    final Set<String> newPhotoIds = Set<String>.from(album.photoIds);
    newPhotoIds.addAll(photoIds);

    // 如果相册没有封面图片，使用第一张照片作为封面
    String? coverPhotoId = album.coverPhotoId;
    if (coverPhotoId == null && newPhotoIds.isNotEmpty) {
      coverPhotoId = newPhotoIds.first;
    }

    final updatedAlbum = album.copyWith(
      photoIds: newPhotoIds.toList(),
      coverPhotoId: coverPhotoId,
    );

    return await updateAlbum(updatedAlbum);
  }

  // 向云相册添加照片（只能添加已同步的照片）
  Future<Album> addPhotosToCloudAlbum(
      String albumId, List<String> photoIds) async {
    final album = getAlbumById(albumId);
    if (album == null || album.albumType != AlbumType.cloud) {
      throw Exception('云相册不存在');
    }

    // 筛选出已同步的照片
    final syncedPhotoIds = await _filterSyncedPhotos(photoIds);

    // 创建一个新的照片ID列表，确保不重复
    final Set<String> newPhotoIds = Set<String>.from(album.photoIds);
    newPhotoIds.addAll(syncedPhotoIds);

    // 如果相册没有封面图片，使用第一张照片作为封面
    String? coverPhotoId = album.coverPhotoId;
    if (coverPhotoId == null && newPhotoIds.isNotEmpty) {
      coverPhotoId = newPhotoIds.first;
    }

    final updatedAlbum = album.copyWith(
      photoIds: newPhotoIds.toList(),
      coverPhotoId: coverPhotoId,
      isSynced: false, // 标记为需要同步
    );

    return await updateAlbum(updatedAlbum);
  }

  // 筛选出已同步到云端的照片ID
  Future<List<String>> _filterSyncedPhotos(List<String> photoIds) async {
    if (photoIds.isEmpty) return [];

    // 需要传递WebDavService实例，从其他可访问的位置获取
    final webdavService = await _getWebDavService();
    if (webdavService == null) {
      debugPrint('无法获取WebDavService实例，无法筛选同步照片');
      return [];
    }

    final mediaSyncService = MediaSyncService(webdavService);

    // 初始化MediaSyncService
    try {
      await mediaSyncService.initialize();
    } catch (e) {
      debugPrint('初始化MediaSyncService失败: $e');
      return []; // 如果初始化失败，不能同步任何照片
    }

    // 查找所有已同步照片
    final syncedPhotoIds = <String>[];
    for (final photoId in photoIds) {
      // 使用MediaSyncService的公共API来检查照片是否已同步
      final mapping = await _checkPhotoSyncStatus(mediaSyncService, photoId);
      if (mapping != null && mapping.syncStatus == SyncStatus.synced) {
        syncedPhotoIds.add(photoId);
      }
    }

    if (syncedPhotoIds.isEmpty) {
      debugPrint('没有找到已同步的照片，请先同步照片后再添加到云相册');
    } else {
      debugPrint('找到${syncedPhotoIds.length}张已同步的照片');
    }

    return syncedPhotoIds;
  }

  // 辅助方法：检查照片的同步状态
  Future<MediaMapping?> _checkPhotoSyncStatus(
      MediaSyncService service, String photoId) async {
    // 这里需要根据MediaSyncService的公共API实现
    // 例如，可能需要使用service提供的getMapping或类似方法
    try {
      // 注：这是一个占位实现，实际代码应使用MediaSyncService的真实公共API
      final mappings = await service.getCloudMappings();
      return mappings?.findMappingById(photoId);
    } catch (e) {
      debugPrint('检查照片$photoId同步状态失败: $e');
      return null;
    }
  }

  // 获取WebDavService实例的辅助方法
  Future<WebDavService?> _getWebDavService() async {
    try {
      // 使用WebDavService的单例模式
      final webdavService = WebDavService();

      // 检查WebDavService是否已连接
      if (webdavService.isConnected) {
        return webdavService;
      }

      // 如果未连接，尝试使用保存的凭据初始化
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString('webdav_server'); // 正确的键名
      final username = prefs.getString('webdav_username');
      final password = prefs.getString('webdav_password');
      final uploadPath = prefs.getString('webdav_upload_path') ?? '/';

      if (serverUrl != null && username != null && password != null) {
        final connected = await webdavService.initialize(
          serverUrl,
          username: username,
          password: password,
          uploadRootPath: uploadPath,
        );

        if (connected) {
          debugPrint('WebDavService已成功初始化');
          return webdavService;
        } else {
          debugPrint('WebDavService初始化失败');
          return null;
        }
      }

      debugPrint('没有找到WebDAV配置信息');
      return null;
    } catch (e) {
      debugPrint('获取WebDavService失败: $e');
      return null;
    }
  }

  // 从相册移除照片
  Future<Album> removePhotosFromAlbum(
      String albumId, List<String> photoIds) async {
    final album = getAlbumById(albumId);

    if (album == null) {
      throw Exception('相册不存在');
    }

    // 移除指定的照片ID
    final List<String> newPhotoIds = List<String>.from(album.photoIds);
    newPhotoIds.removeWhere((id) => photoIds.contains(id));

    // 如果移除的照片包括封面照片，需要更新封面照片
    String? coverPhotoId = album.coverPhotoId;
    if (coverPhotoId != null && photoIds.contains(coverPhotoId)) {
      coverPhotoId = newPhotoIds.isNotEmpty ? newPhotoIds.first : null;
    }

    final updatedAlbum = album.copyWith(
      photoIds: newPhotoIds,
      coverPhotoId: coverPhotoId,
      // 如果是云相册，标记为需要同步
      isSynced: album.albumType == AlbumType.cloud ? false : album.isSynced,
    );

    return await updateAlbum(updatedAlbum);
  }

  // 设置相册封面
  Future<Album> setAlbumCover(String albumId, String photoId) async {
    final album = getAlbumById(albumId);

    if (album == null) {
      throw Exception('相册不存在');
    }

    if (!album.photoIds.contains(photoId)) {
      throw Exception('照片不在相册中');
    }

    final updatedAlbum = album.copyWith(
      coverPhotoId: photoId,
      // 如果是云相册，标记为需要同步
      isSynced: album.albumType == AlbumType.cloud ? false : album.isSynced,
    );

    return await updateAlbum(updatedAlbum);
  }

  // 从文件系统目录创建本地相册
  Future<Album> createAlbumFromDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw Exception('目录不存在: $directoryPath');
    }

    final name = path.basename(directoryPath);
    final description = '从本地文件夹创建的相册: ${path.basename(directoryPath)}';

    // 创建一个新的本地相册
    return createLocalAlbum(
      name: name,
      description: description,
      localFolderPath: directoryPath,
      // 不立即添加照片，可以在后续扫描时添加
    );
  }

  // 更新相册的云同步状态
  Future<void> updateCloudSyncStatus(String albumId, bool isSynced) async {
    final album = getAlbumById(albumId);
    if (album != null && album.albumType == AlbumType.cloud) {
      final updatedAlbum = album.copyWith(isSynced: isSynced);
      await updateAlbum(updatedAlbum);
    }
  }

  // 更新云相册的待下载照片计数
  Future<void> updatePendingCloudPhotosCount(String albumId, int count) async {
    final album = getAlbumById(albumId);
    if (album != null && album.albumType == AlbumType.cloud) {
      final updatedAlbum = album.copyWith(pendingCloudPhotosCount: count);
      await updateAlbum(updatedAlbum);
    }
  }

  // 扫描本地文件夹，将照片添加到本地相册
  Future<void> scanFolderForLocalAlbum(
      String albumId, Map<String, MediaIndex> mediaIndices) async {
    final album = getAlbumById(albumId);
    if (album == null ||
        album.albumType != AlbumType.local ||
        album.localFolderPath == null) {
      return;
    }

    final folderPath = album.localFolderPath!;
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      return;
    }

    // 收集所有媒体文件
    final allMediaFiles = <MediaFileInfo>[];
    for (final index in mediaIndices.values) {
      allMediaFiles.addAll(index.mediaFiles);
    }

    // 查找文件夹内的所有媒体文件
    final folderMediaIds = <String>[];
    for (final media in allMediaFiles) {
      // 检查媒体文件是否在该文件夹内或其子文件夹内
      if (media.originalPath.startsWith(folderPath)) {
        folderMediaIds.add(media.id);
      }
    }

    if (folderMediaIds.isNotEmpty) {
      // 添加到相册
      await addPhotosToLocalAlbum(albumId, folderMediaIds);
    }
  }
}
