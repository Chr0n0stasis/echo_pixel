import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const String _darkModeKey = 'dark_mode';

  // 单例模式
  static final ThemeService _instance = ThemeService._internal();

  factory ThemeService() {
    return _instance;
  }

  ThemeService._internal();

  // 主题模式
  ThemeMode _themeMode = ThemeMode.system;

  // 获取当前主题模式
  ThemeMode get themeMode => _themeMode;

  // 是否为深色模式
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  // 初始化
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool(_darkModeKey);

    if (isDarkMode != null) {
      _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system;
    }

    notifyListeners();
  }

  // 设置深色模式
  Future<void> setDarkMode(bool isDarkMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, isDarkMode);

    _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  // 切换主题模式
  Future<void> toggleThemeMode() async {
    await setDarkMode(!isDarkMode);
  }
}
