import 'package:device_info_plus/device_info_plus.dart';
import 'package:echo_pixel/screens/device_management_page.dart';
import 'package:echo_pixel/screens/webdav_status_page.dart';
import 'package:echo_pixel/services/thumbnail_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:media_kit/media_kit.dart'; // 导入MediaKit
import 'package:permission_handler/permission_handler.dart'; // 导入权限处理包
import 'package:provider/provider.dart';
import 'services/theme_service.dart';
import 'services/preview_quality_service.dart'; // 导入预览质量服务
import 'services/webdav_service.dart'; // 导入WebDAV服务
import 'services/media_sync_service.dart'; // 导入媒体同步服务
import 'services/media_index_service.dart'; // 导入媒体索引服务
import 'screens/photo_gallery_page.dart';
import 'screens/settings_page.dart'; // 导入新的设置页面

void main() async {
  // 确保初始化Flutter绑定
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化MediaKit
  MediaKit.ensureInitialized();

  // 初始化WebDAV服务和媒体同步服务
  final webDavService = WebDavService();
  final mediaSyncService = MediaSyncService(webDavService);

  // 初始化其他服务
  final themeService = ThemeService();
  final previewQualityService = PreviewQualityService();
  final mediaIndexService = MediaIndexService(); // 初始化媒体索引服务

  await Future.wait([
    themeService.initialize(),
    previewQualityService.initialize(),
    mediaSyncService.initialize(), // 初始化媒体同步服务
  ]);

  // 在Android平台上请求权限
  if (Platform.isAndroid) {
    await requestPermissions();
  }

  runApp(
    // 使用Provider提供服务
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeService>.value(value: themeService),
        ChangeNotifierProvider<PreviewQualityService>.value(
            value: previewQualityService),
        // 添加MediaSyncService作为Provider
        Provider<MediaSyncService>.value(value: mediaSyncService),
        // 添加WebDavService作为Provider
        Provider<WebDavService>.value(value: webDavService),
        Provider<ThumbnailService>.value(value: ThumbnailService()),
        // 添加MediaIndexService作为Provider
        ChangeNotifierProvider<MediaIndexService>.value(
            value: mediaIndexService),
      ],
      child: const MyApp(),
    ),
  );
}

// 请求所需的权限
Future<void> requestPermissions() async {
  // 针对不同Android版本请求不同权限
  if (Platform.isAndroid) {
    // 获取 Android SDK 版本
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 33) {
      // Android 13及以上使用新的细粒度权限
      await Future.wait([
        Permission.photos.request(),
        Permission.videos.request(),
      ]);
    } else {
      // 较旧版本使用存储权限
      await Permission.storage.request();
    }

    // 网络权限不需要动态申请
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 从Provider获取ThemeService
    final themeService = Provider.of<ThemeService>(context);

    return MaterialApp(
      title: 'Echo Pixel',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // 根据ThemeService设置主题模式
      themeMode: themeService.themeMode,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // 对相册页面的引用，用于后续控制
  late final PhotoGalleryPage _photoGalleryPage;

  // 判断是否是桌面平台
  bool get isDesktop {
    if (kIsWeb) return false; // 网页版使用移动端布局
    return !Platform.isAndroid && !Platform.isIOS;
  }

  // 判断设备方向
  bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  // 创建带有回调的相册页面实例
  void _initializePhotoGalleryPage() {
    _photoGalleryPage = PhotoGalleryPage(
      // 提供回调函数，在相册页面可以调用主页面的方法
      onSyncRequest: _handleSyncRequest,
      onWebDavSettingsRequest: _handleWebDavSettingsRequest,
      onRefreshRequest: _handleRefreshRequest,
    );
  }

  // 同步按钮回调
  void _handleSyncRequest() {
    // 这个方法会被相册页面调用
    debugPrint('主页面：收到同步请求');
    // 在这里可以添加任何需要在主页面处理的同步相关逻辑
  }

  // WebDAV设置回调
  void _handleWebDavSettingsRequest() {
    debugPrint('主页面：收到WebDAV设置请求');
    // 切换到设置页面
    setState(() {
      _selectedIndex = 2; // 设置页面的索引
    });
  }

  // 刷新请求回调
  void _handleRefreshRequest() {
    debugPrint('主页面：收到刷新请求');
    // 在这里可以添加任何需要在主页面处理的刷新相关逻辑
  }

  @override
  void initState() {
    super.initState();
    _initializePhotoGalleryPage();
  }

  // 页面列表
  Widget _getPageForIndex(int index) {
    return switch (index) {
      0 => _photoGalleryPage,
      1 => const WebDavStatusPage(),
      2 => const DeviceManagementPage(),
      _ => const SettingsPage(),
    };
  }

  // 底部导航项目
  final List<BottomNavigationBarItem> _bottomNavItems = [
    const BottomNavigationBarItem(icon: Icon(Icons.photo_library), label: '相册'),
    const BottomNavigationBarItem(
        icon: Icon(Icons.cloud_outlined), label: 'WebDAV'),
    const BottomNavigationBarItem(icon: Icon(Icons.devices), label: '设备'),
    const BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
  ];

  // 侧拉栏列表项
  List<Widget> _buildDrawerItems() {
    return [
      DrawerHeader(
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              'Echo Pixel',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '您的跨平台相册',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
      ListTile(
        selected: _selectedIndex == 0,
        leading: const Icon(Icons.photo_library),
        title: const Text('相册'),
        onTap: () {
          _onItemTapped(0);
          if (!isDesktop) Navigator.pop(context);
        },
      ),
      ListTile(
        selected: _selectedIndex == 1,
        leading: const Icon(Icons.cloud_outlined),
        title: const Text('WebDAV'),
        onTap: () {
          _onItemTapped(1);
          if (!isDesktop) Navigator.pop(context);
        },
      ),
      ListTile(
        selected: _selectedIndex == 2,
        leading: const Icon(Icons.devices),
        title: const Text('设备管理'),
        onTap: () {
          _onItemTapped(2);
          if (!isDesktop) Navigator.pop(context);
        },
      ),
      const Divider(),
      ListTile(
        selected: _selectedIndex == 3,
        leading: const Icon(Icons.settings),
        title: const Text('设置'),
        onTap: () {
          _onItemTapped(3);
          if (!isDesktop) Navigator.pop(context);
        },
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.cloud_sync),
        title: const Text('WebDAV同步'),
        onTap: () {
          // 触发同步
          PhotoGalleryPage.controller.syncWithWebDav();
          if (!isDesktop) Navigator.pop(context);
        },
      ),
      const Divider(),
      const AboutListTile(
        icon: Icon(Icons.info),
        applicationName: 'Echo Pixel',
        applicationVersion: '1.0.0',
        applicationLegalese: '© 2025 Echo Pixel',
        child: Text('关于应用'),
      ),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 检测设备是否为平板或大屏设备（宽度 > 600dp）
    final bool isTabletOrLarger = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        // 移除"Echo Pixel"标题，改为根据当前页面显示不同的标题
        title: Text(_selectedIndex == 0
            ? '照片库'
            : _selectedIndex == 1
                ? 'WebDAV'
                : _selectedIndex == 2
                    ? '设备管理'
                    : '设置'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // 集成相册页面的功能按钮
          if (_selectedIndex == 0) ...[
            // 同步按钮 - 使用控制器直接调用相册页面的功能
            IconButton(
              tooltip: '同步媒体文件',
              onPressed: () {
                PhotoGalleryPage.controller.syncWithWebDav();
              },
              icon: const Icon(Icons.sync),
            ),
          ],

          // 其他页面的功能按钮
          if (_selectedIndex != 0 && _selectedIndex != 3)
            IconButton(
              icon: const Icon(Icons.cloud_sync),
              onPressed: () {
                // 显示同步状态或触发同步
                PhotoGalleryPage.controller.syncWithWebDav();
              },
            ),
        ],
      ),
      drawer: isDesktop || isTabletOrLarger
          ? null
          : Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: _buildDrawerItems(),
              ),
            ),
      body: Row(
        children: [
          // 在桌面端或平板横屏模式显示永久侧边栏
          if (isDesktop || (isTabletOrLarger && isLandscape(context)))
            NavigationRail(
              extended: isDesktop || MediaQuery.of(context).size.width > 800,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.photo_library),
                  label: Text('相册'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.cloud_outlined),
                  label: Text('WebDAV'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.devices),
                  label: Text('设备'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings),
                  label: Text('设置'),
                ),
              ],
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onItemTapped,
            ),
          // 主内容区域
          Expanded(child: _getPageForIndex(_selectedIndex)),
        ],
      ),
      // 在移动端显示底部导航栏，桌面端不显示
      bottomNavigationBar:
          (!isDesktop && (!isTabletOrLarger || !isLandscape(context)))
              ? BottomNavigationBar(
                  items: _bottomNavItems,
                  currentIndex: _selectedIndex,
                  onTap: _onItemTapped,
                  type: BottomNavigationBarType.fixed,
                )
              : null,
    );
  }
}
