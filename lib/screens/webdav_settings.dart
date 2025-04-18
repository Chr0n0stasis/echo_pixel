import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/webdav_service.dart';
import '../services/media_sync_service.dart';
import 'webdav_status_page.dart';

class WebDavSettingsScreen extends StatefulWidget {
  final MediaSyncService? mediaSyncService;

  const WebDavSettingsScreen({
    super.key,
    this.mediaSyncService,
  });

  @override
  State<WebDavSettingsScreen> createState() => _WebDavSettingsScreenState();
}

class _WebDavSettingsScreenState extends State<WebDavSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _uploadRootPathController = TextEditingController(text: '/');
  final _maxConcurrentTasksController = TextEditingController(text: '5');
  final _webDavService = WebDavService();
  late final MediaSyncService _mediaSyncService;

  bool _isConnecting = false;
  bool _isConnected = false;
  String _status = '';

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _uploadRootPathController.dispose();
    _maxConcurrentTasksController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 初始化或获取MediaSyncService
    _mediaSyncService =
        widget.mediaSyncService ?? MediaSyncService(_webDavService);

    // 从本地存储加载WebDAV配置
    _loadSavedSettings();
  }

  // 加载保存的WebDAV设置
  Future<void> _loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString('webdav_server');
      final username = prefs.getString('webdav_username');
      final password = prefs.getString('webdav_password');
      final uploadRootPath = prefs.getString('webdav_upload_root_path');
      final maxConcurrentTasks = prefs.getString('webdav_max_concurrent_tasks');

      if (serverUrl != null) {
        setState(() {
          _serverController.text = serverUrl;
          if (username != null) _usernameController.text = username;
          if (password != null) _passwordController.text = password;
          if (uploadRootPath != null) {
            _uploadRootPathController.text = uploadRootPath;
          }
          if (maxConcurrentTasks != null) {
            _maxConcurrentTasksController.text = maxConcurrentTasks;
          }
        });

        // 自动测试连接
        _testConnection();
      }
    } catch (e) {
      debugPrint('加载WebDAV设置错误: $e');
    }
  }

  // 打开WebDAV状态页面
  void _openWebDavStatusPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WebDavStatusPage(
          mediaSyncService: _mediaSyncService,
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _status = '正在连接...';
    });

    try {
      // 用户名和密码现在是可选的
      final username =
          _usernameController.text.isEmpty ? null : _usernameController.text;
      final password =
          _passwordController.text.isEmpty ? null : _passwordController.text;

      final isConnected = await _webDavService.initialize(
        _serverController.text,
        username: username,
        password: password,
        uploadRootPath: _uploadRootPathController.text,
      );

      setState(() {
        _isConnected = isConnected;
        _status = isConnected ? '连接成功！' : '连接失败，请检查输入信息';
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _status = '连接错误: $e';
      });
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate() || !_isConnected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先成功连接WebDAV服务器')));
      return;
    }

    try {
      // 保存WebDAV设置到本地存储
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('webdav_server', _serverController.text);

      // 用户名和密码是可选的
      if (_usernameController.text.isNotEmpty) {
        await prefs.setString('webdav_username', _usernameController.text);
      } else {
        await prefs.remove('webdav_username');
      }

      if (_passwordController.text.isNotEmpty) {
        await prefs.setString('webdav_password', _passwordController.text);
      } else {
        await prefs.remove('webdav_password');
      }

      // 保存新增的设置项
      await prefs.setString(
          'webdav_upload_root_path', _uploadRootPathController.text);
      await prefs.setString(
          'webdav_max_concurrent_tasks', _maxConcurrentTasksController.text);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WebDAV设置已保存')),
        );

        // 返回true表示设置已保存
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存设置错误: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV设置'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // 添加查看传输状态按钮
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: '查看传输状态',
            onPressed: _openWebDavStatusPage,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '设置WebDAV连接',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                '请输入您的WebDAV服务器信息，以便同步您的照片和相册。',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _serverController,
                decoration: const InputDecoration(
                  labelText: '服务器URL',
                  hintText: 'https://example.com/webdav',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cloud),
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入WebDAV服务器地址';
                  }
                  if (!value.startsWith('http://') &&
                      !value.startsWith('https://')) {
                    return '服务器地址必须以http://或https://开头';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名 (可选)',
                  hintText: '请输入用户名',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                // 用户名现在是可选的
                validator: (value) => null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '密码 (可选)',
                  hintText: '请输入密码',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
                // 密码现在是可选的
                validator: (value) => null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _uploadRootPathController,
                decoration: const InputDecoration(
                  labelText: '上传根路径',
                  hintText: '/path/to/upload',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.folder),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入上传根路径';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _maxConcurrentTasksController,
                decoration: const InputDecoration(
                  labelText: '最大并发任务数',
                  hintText: '5',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.settings),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入最大并发任务数';
                  }
                  if (int.tryParse(value) == null) {
                    return '最大并发任务数必须是数字';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              if (_status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: _isConnected
                        ? Colors.green.withOpacity(0.25)
                        : Colors.red.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    _status,
                    style: TextStyle(
                      color: _isConnected ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isConnecting ? null : _testConnection,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('测试连接'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isConnected ? _saveSettings : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('保存配置'),
              ),
              const SizedBox(height: 32),
              // 添加查看传输状态卡片
              Card(
                elevation: 2,
                child: InkWell(
                  onTap: _openWebDavStatusPage,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.sync,
                          size: 32,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '查看传输状态',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '监控当前正在进行的上传和下载任务',
                                style: TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const ExpansionTile(
                title: Text('高级设置'),
                children: [
                  ListTile(
                    title: Text('同步频率'),
                    subtitle: Text('设置自动同步间隔'),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
