import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// 前台任务回调入口点
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(SyncTaskHandler());
}

/// 前台同步服务，用于在后台同步时保持应用活跃
class ForegroundSyncService {
  static const String _taskName = 'Echo Pixel 同步';
  static const String _taskDesc = '正在与云端同步媒体文件...';
  static const String _channelId = 'sync_channel';
  static const String _channelName = '同步通知';

  static bool _isRunning = false;

  // 获取任务运行状态
  static bool get isRunning => _isRunning;

  // 初始化前台任务配置
  static Future<void> initForegroundTask() async {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: _channelId,
          channelName: _channelName,
          channelDescription: '保持媒体同步在后台运行',
          channelImportance: NotificationChannelImportance.HIGH,
          priority: NotificationPriority.HIGH,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: true,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          allowWakeLock: true,
        ),
      );
    }
  }

  // 启动前台任务
  static Future<void> startForegroundTask({
    required String title,
    required String desc,
    required Function(int progress) onProgressUpdate,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      // 请求电池优化豁免
      if (Platform.isAndroid &&
          !await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      // 启用屏幕常亮
      await WakelockPlus.enable();

      // 注册回调
      await _registerCallbackTask(onProgressUpdate);

      // 启动前台任务
      await FlutterForegroundTask.startService(
        notificationTitle: title,
        notificationText: desc,
        callback: startCallback,
      );

      debugPrint('Foreground task started');

      _isRunning = true;
    }
  }

  // 停止前台任务
  static Future<void> stopForegroundTask() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // 禁用屏幕常亮
      await WakelockPlus.disable();
      await FlutterForegroundTask.stopService();
      _isRunning = false;
    }
  }

  // 更新前台任务通知
  static Future<void> updateNotification({
    String? title,
    String? desc,
    int progress = 0,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      if (!_isRunning) return;

      await FlutterForegroundTask.updateService(
        notificationTitle: title ?? _taskName,
        notificationText: desc ?? _taskDesc,
        callback: startCallback,
      );
    }
  }

  // 注册任务回调
  static Future<void> _registerCallbackTask(
      Function(int progress) onProgressUpdate) async {
    // 保存进度更新回调到静态变量
    SyncTaskHandler.onProgressUpdate = onProgressUpdate;
  }
}

// 同步任务处理器
class SyncTaskHandler extends TaskHandler {
  // 进度更新回调
  static Function(int progress)? onProgressUpdate;

  // 处理前台任务事件
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 任务开始时调用
    WidgetsFlutterBinding.ensureInitialized();
  }

  // 处理前台任务事件（定期调用）
  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  // 处理前台任务销毁
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // 任务结束时调用
    await WakelockPlus.disable();
  }

  // 处理同步进度更新
  void updateProgress(int progress) {
    if (onProgressUpdate != null) {
      onProgressUpdate!(progress);
    }
  }
}
