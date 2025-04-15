import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:media_kit/media_kit.dart'; // 导入MediaKit

import 'screens/photo_gallery_page.dart';

void main() {
  // 确保初始化Flutter绑定
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化MediaKit
  MediaKit.ensureInitialized();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      themeMode: ThemeMode.system,
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

  // 判断是否是桌面平台
  bool get isDesktop {
    if (kIsWeb) return false; // 网页版使用移动端布局
    return !Platform.isAndroid && !Platform.isIOS;
  }

  // 判断设备方向
  bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  // 页面列表
  final List<Widget> _pages = [
    const PhotoGalleryPage(),
    const AlbumsPage(),
    const SearchPage(),
    const SettingsPage(),
  ];

  // 底部导航项目
  final List<BottomNavigationBarItem> _bottomNavItems = [
    const BottomNavigationBarItem(icon: Icon(Icons.photo_library), label: '相册'),
    const BottomNavigationBarItem(icon: Icon(Icons.collections), label: '合集'),
    const BottomNavigationBarItem(icon: Icon(Icons.search), label: '搜索'),
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
        leading: const Icon(Icons.collections),
        title: const Text('合集'),
        onTap: () {
          _onItemTapped(1);
          if (!isDesktop) Navigator.pop(context);
        },
      ),
      ListTile(
        selected: _selectedIndex == 2,
        leading: const Icon(Icons.search),
        title: const Text('搜索'),
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
          // 打开WebDAV同步设置
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
        title: const Text('Echo Pixel'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_sync),
            onPressed: () {
              // 显示同步状态或触发同步
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // 显示更多选项
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
                  icon: Icon(Icons.collections),
                  label: Text('合集'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.search),
                  label: Text('搜索'),
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
          Expanded(child: _pages[_selectedIndex]),
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
      floatingActionButton: _selectedIndex < 2
          ? FloatingActionButton(
              onPressed: () {
                // 添加照片或创建新相册
              },
              tooltip: _selectedIndex == 0 ? '添加照片' : '创建相册',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

// 相册合集页面
class AlbumsPage extends StatelessWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(child: Text('相册合集页面 - 这里将显示所有相册')),
    );
  }
}

// 搜索页面
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(child: Text('搜索页面 - 这里可以搜索照片')),
    );
  }
}

// 设置页面
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(child: Text('设置页面 - 这里将包含应用设置和WebDAV配置')),
    );
  }
}
