import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

class MediaScanSettingsPage extends StatefulWidget {
  const MediaScanSettingsPage({super.key});

  @override
  State<MediaScanSettingsPage> createState() => _MediaScanSettingsPageState();
}

class _MediaScanSettingsPageState extends State<MediaScanSettingsPage> {
  final List<String> _scanFolders = [];
  bool _isLoading = true;
  bool _scanHiddenFolders = false;
  bool _scanSystemFolders = false;
  bool _enableAutoScan = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载扫描目录列表
      final scanFolders = prefs.getStringList('scan_folders');

      // 加载其他扫描设置
      final scanHidden = prefs.getBool('scan_hidden_folders');
      final scanSystem = prefs.getBool('scan_system_folders');
      final autoScan = prefs.getBool('enable_auto_scan');

      setState(() {
        if (scanFolders != null) {
          _scanFolders.clear();
          _scanFolders.addAll(scanFolders);
        } else {
          _addDefaultFolders();
        }

        _scanHiddenFolders = scanHidden ?? false;
        _scanSystemFolders = scanSystem ?? false;
        _enableAutoScan = autoScan ?? true;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('加载媒体扫描设置错误: $e');
      setState(() {
        _addDefaultFolders();
        _isLoading = false;
      });
    }
  }

  Future<void> _addDefaultFolders() async {
    _scanFolders.clear();

    try {
      if (Platform.isAndroid) {
        // Android平台的默认媒体目录
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final dcimDir = Directory('${externalDir.path}/../DCIM');
          final picturesDir = Directory('${externalDir.path}/../Pictures');

          if (await dcimDir.exists()) {
            _scanFolders.add(dcimDir.path);
          }
          if (await picturesDir.exists()) {
            _scanFolders.add(picturesDir.path);
          }
        }
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // 桌面平台的默认媒体目录
        final homeDir = _getUserHomeDirectory();

        if (Platform.isWindows) {
          _scanFolders.add(path.join(homeDir, 'Pictures'));
          _scanFolders.add(path.join(homeDir, 'Videos'));
        } else if (Platform.isMacOS) {
          _scanFolders.add(path.join(homeDir, 'Pictures'));
          _scanFolders.add(path.join(homeDir, 'Movies'));
        } else if (Platform.isLinux) {
          _scanFolders.add(path.join(homeDir, 'Pictures'));
          _scanFolders.add(path.join(homeDir, 'Videos'));
        }
      }
    } catch (e) {
      debugPrint('添加默认文件夹错误: $e');
    }
  }

  String _getUserHomeDirectory() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '';
    } else {
      return Platform.environment['HOME'] ?? '';
    }
  }

  Future<void> _addScanFolder() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择要扫描的文件夹',
      );

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        // 检查目录是否已经在列表中
        if (!_scanFolders.contains(selectedDirectory)) {
          setState(() {
            _scanFolders.add(selectedDirectory);
          });
          await _saveScanFolders();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('该文件夹已在扫描列表中')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('选择文件夹错误: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择文件夹失败: $e')),
        );
      }
    }
  }

  Future<void> _removeScanFolder(int index) async {
    setState(() {
      _scanFolders.removeAt(index);
    });
    await _saveScanFolders();
  }

  Future<void> _saveScanFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('scan_folders', _scanFolders);
    } catch (e) {
      debugPrint('保存扫描文件夹列表错误: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存扫描文件夹失败: $e')),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('scan_hidden_folders', _scanHiddenFolders);
      await prefs.setBool('scan_system_folders', _scanSystemFolders);
      await prefs.setBool('enable_auto_scan', _enableAutoScan);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设置已保存')),
        );
      }
    } catch (e) {
      debugPrint('保存媒体扫描设置错误: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存设置失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体扫描设置'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // 扫描文件夹列表
                Card(
                  margin: const EdgeInsets.only(bottom: 16.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '扫描文件夹',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '选择要扫描媒体文件的文件夹',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        if (_scanFolders.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('没有扫描文件夹，点击下方按钮添加'),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _scanFolders.length,
                            itemBuilder: (context, index) {
                              final folder = _scanFolders[index];
                              return ListTile(
                                leading: const Icon(Icons.folder),
                                title: Text(
                                  folder,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _removeScanFolder(index),
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 16),
                        Center(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('添加文件夹'),
                            onPressed: _addScanFolder,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 扫描设置
                Card(
                  margin: const EdgeInsets.only(bottom: 16.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '扫描设置',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text('自动扫描'),
                          subtitle: const Text('应用启动时自动扫描新媒体文件'),
                          value: _enableAutoScan,
                          onChanged: (value) {
                            setState(() {
                              _enableAutoScan = value;
                            });
                            _saveSettings();
                          },
                        ),
                        SwitchListTile(
                          title: const Text('扫描隐藏文件夹'),
                          subtitle: const Text('包含以"."开头的隐藏文件夹'),
                          value: _scanHiddenFolders,
                          onChanged: (value) {
                            setState(() {
                              _scanHiddenFolders = value;
                            });
                            _saveSettings();
                          },
                        ),
                        SwitchListTile(
                          title: const Text('扫描系统文件夹'),
                          subtitle: const Text('包含系统文件夹中的媒体文件'),
                          value: _scanSystemFolders,
                          onChanged: (value) {
                            setState(() {
                              _scanSystemFolders = value;
                            });
                            _saveSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // 扫描操作
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '扫描操作',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text('全量扫描'),
                              onPressed: () {
                                // 全量扫描的操作
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('开始全量扫描...')),
                                );
                              },
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.update),
                              label: const Text('增量扫描'),
                              onPressed: () {
                                // 增量扫描的操作
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('开始增量扫描...')),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 提示信息
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '提示',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '1. 全量扫描会扫描所有设定的文件夹，可能需要较长时间\n'
                          '2. 增量扫描只会扫描新增或修改的文件，速度更快\n'
                          '3. 扫描过程中请勿关闭应用',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
