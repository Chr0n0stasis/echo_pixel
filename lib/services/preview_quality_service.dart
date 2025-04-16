import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreviewQualityService extends ChangeNotifier {
  static const String _highQualityKey = 'high_quality_preview';

  // 单例模式
  static final PreviewQualityService _instance =
      PreviewQualityService._internal();

  factory PreviewQualityService() {
    return _instance;
  }

  PreviewQualityService._internal();

  // 是否使用高质量预览
  bool _isHighQuality = true;

  // 获取当前预览质量设置
  bool get isHighQuality => _isHighQuality;

  // 初始化
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final highQuality = prefs.getBool(_highQualityKey);

    _isHighQuality = highQuality ?? true;
    notifyListeners();
  }

  // 设置预览质量
  Future<void> setHighQuality(bool isHighQuality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_highQualityKey, isHighQuality);

    _isHighQuality = isHighQuality;
    notifyListeners();
  }

  // 获取图片缓存宽度
  int get imageCacheWidth => _isHighQuality ? 1080 : 480;

  // 获取图片缓存高度
  int get imageCacheHeight => _isHighQuality ? 1080 : 480;

  // 获取图片过滤质量
  FilterQuality get imageFilterQuality =>
      _isHighQuality ? FilterQuality.high : FilterQuality.medium;

  // 获取视频缩略图质量（百分比）
  int get videoThumbnailQuality => _isHighQuality ? 80 : 40;

  // 获取视频预览分辨率（高度）
  int get videoPreviewHeight => _isHighQuality ? 720 : 360;
}
