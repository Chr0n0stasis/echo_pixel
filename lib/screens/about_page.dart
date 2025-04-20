import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _appVersion = '1.0.0';
  String _appBuildNumber = '1';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();

      setState(() {
        _appVersion = packageInfo.version;
        _appBuildNumber = packageInfo.buildNumber;
      });
    } catch (e) {
      debugPrint('获取应用信息错误: $e');
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于 Echo Pixel'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          // 应用图标和版本信息
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                // 应用图标
                SvgPicture.asset(
                  "assets/icon/EchoPixel.svg",
                  width: 100,
                  height: 100,
                ),
                const SizedBox(height: 16),

                // 应用名称
                const Text(
                  'Echo Pixel',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                // 应用版本
                Text(
                  '版本 $_appVersion ($_appBuildNumber)',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),

                // 应用描述
                const SizedBox(height: 16),
                const Text(
                  '一款跨平台的照片管理应用，支持本地照片浏览和WebDAV云同步',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),

          const Divider(),

          // 功能列表
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              '主要功能',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('照片库'),
            subtitle: const Text('浏览和管理您的照片和视频'),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync),
            title: const Text('WebDAV同步'),
            subtitle: const Text('将媒体文件同步到任何WebDAV服务器'),
          ),

          const Divider(),

          // 开发者信息
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              '开发者',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('shadow3'),
            subtitle: const Text('shadow3aaaa@gmail.com'),
            onTap: () => _launchUrl('shadow3aaaa@gmail.com'),
          ),

          const Divider(),

          // 法律信息
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              '法律信息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('开源许可'),
            onTap: () => _showLicensesPage(),
          ),

          // 版权信息
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              '© 2025 Echo Pixel. All rights reserved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLicensesPage() {
    showLicensePage(
      context: context,
      applicationName: 'Echo Pixel',
      applicationVersion: _appVersion,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SvgPicture.asset(
          "assets/icon/EchoPixel.svg",
          width: 100,
          height: 100,
        ),
      ),
    );
  }
}
