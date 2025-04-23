import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;

class PermissionGuidePage extends StatefulWidget {
  final VoidCallback onPermissionsGranted;

  const PermissionGuidePage({super.key, required this.onPermissionsGranted});

  @override
  State<PermissionGuidePage> createState() => _PermissionGuidePageState();
}

class _PermissionGuidePageState extends State<PermissionGuidePage> {
  bool _notificationPermissionGranted = false;
  bool _photosPermissionGranted = false;
  bool _videosPermissionGranted = false;
  bool _storagePermissionGranted = false;
  bool _isAndroid13OrAbove = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    if (Platform.isAndroid) {
      // 获取 Android SDK 版本
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      _isAndroid13OrAbove = sdkInt >= 33;

      // 检查通知权限
      _notificationPermissionGranted = await Permission.notification.isGranted;

      if (_isAndroid13OrAbove) {
        // Android 13 及以上使用新的细粒度权限
        _photosPermissionGranted = await Permission.photos.isGranted;
        _videosPermissionGranted = await Permission.videos.isGranted;
      } else {
        // 旧版本使用存储权限
        _storagePermissionGranted = await Permission.storage.isGranted;
      }
    }

    setState(() {
      _isLoading = false;
    });

    // 如果所有权限都已授予，直接调用回调
    _checkAllPermissionsGranted();
  }

  void _checkAllPermissionsGranted() {
    if (_notificationPermissionGranted &&
        (_isAndroid13OrAbove
            ? (_photosPermissionGranted && _videosPermissionGranted)
            : _storagePermissionGranted)) {
      // 记录权限已授予
      _savePermissionsGranted();
      // 调用回调函数
      widget.onPermissionsGranted();
    }
  }

  Future<void> _savePermissionsGranted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_granted', true);
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    setState(() {
      _notificationPermissionGranted = status.isGranted;
    });
    _checkAllPermissionsGranted();
  }

  Future<void> _requestMediaPermissions() async {
    if (_isAndroid13OrAbove) {
      // Android 13 及以上使用新的细粒度权限
      final photoStatus = await Permission.photos.request();
      final videoStatus = await Permission.videos.request();

      setState(() {
        _photosPermissionGranted = photoStatus.isGranted;
        _videosPermissionGranted = videoStatus.isGranted;
      });
    } else {
      // 旧版本使用存储权限
      final status = await Permission.storage.request();
      setState(() {
        _storagePermissionGranted = status.isGranted;
      });
    }
    _checkAllPermissionsGranted();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('权限引导'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Icon(
                  Icons.security,
                  size: 80,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Echo Pixel 需要以下权限才能正常工作',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // 通知权限
              _buildPermissionCard(
                icon: Icons.notifications,
                title: '通知权限',
                description: '允许 Echo Pixel 发送同步状态通知，当应用在后台运行时保持同步。',
                isGranted: _notificationPermissionGranted,
                onRequest: _requestNotificationPermission,
              ),

              const SizedBox(height: 16),

              // 相册权限
              _buildPermissionCard(
                icon: Icons.photo_library,
                title: _isAndroid13OrAbove ? '照片和视频权限' : '存储权限',
                description: '允许 Echo Pixel 访问您的照片和视频，以便同步到云端。',
                isGranted: _isAndroid13OrAbove
                    ? (_photosPermissionGranted && _videosPermissionGranted)
                    : _storagePermissionGranted,
                onRequest: _requestMediaPermissions,
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // 请求所有未授予的权限
                    if (!_notificationPermissionGranted) {
                      _requestNotificationPermission();
                    }

                    if (_isAndroid13OrAbove
                        ? (!_photosPermissionGranted ||
                            !_videosPermissionGranted)
                        : !_storagePermissionGranted) {
                      _requestMediaPermissions();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('授予所有权限', style: TextStyle(fontSize: 16)),
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                '提示：您可以随时在应用设置中修改权限。',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onRequest,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade100,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.blue, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: isGranted ? null : onRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isGranted ? Colors.green : Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isGranted ? '已授权' : '授予权限'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
