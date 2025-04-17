import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import '../services/media_sync_service.dart';
import '../services/webdav_service.dart';

/// WebDAV传输状态页面 - 显示正在进行的上传和下载任务
class WebDavStatusPage extends StatefulWidget {
  final MediaSyncService mediaSyncService;

  const WebDavStatusPage({
    super.key,
    required this.mediaSyncService,
  });

  @override
  State<WebDavStatusPage> createState() => _WebDavStatusPageState();
}

class _WebDavStatusPageState extends State<WebDavStatusPage> {
  // 所有传输任务
  List<TransferTask> _tasks = [];

  // 定时刷新传输任务列表的计时器
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();

    // 注册传输任务状态更新回调
    widget.mediaSyncService.onTransferTasksUpdate = _onTasksUpdated;

    // 首次获取任务列表
    _updateTaskLists();

    // 设置定时器，每秒刷新一次界面（用于更新时间显示）
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  // 任务列表更新回调
  void _onTasksUpdated(List<TransferTask> tasks) {
    if (mounted) {
      setState(() {
        _tasks = List.from(tasks);
      });
    }
  }

  // 更新任务列表
  void _updateTaskLists() {
    final activeTasks = widget.mediaSyncService.activeTasks;
    final pendingTasks = widget.mediaSyncService.pendingTasks;
    final completedTasks = widget.mediaSyncService.completedTasks;

    if (mounted) {
      setState(() {
        _tasks = [...activeTasks, ...pendingTasks, ...completedTasks];
      });
    }
  }

  @override
  void dispose() {
    // 移除任务状态更新回调
    widget.mediaSyncService.onTransferTasksUpdate = null;

    // 取消定时器
    _refreshTimer?.cancel();
    _refreshTimer = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTasks =
        _tasks.where((t) => t.status == TransferStatus.inProgress).toList();
    final pendingTasks =
        _tasks.where((t) => t.status == TransferStatus.pending).toList();
    final completedTasks = _tasks
        .where((t) =>
            t.status == TransferStatus.completed ||
            t.status == TransferStatus.failed)
        .toList();

    // 按完成时间倒序排序完成的任务
    completedTasks.sort((a, b) =>
        (b.endTime ?? DateTime.now()).compareTo(a.endTime ?? DateTime.now()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV传输状态'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _updateTaskLists();
        },
        child: _tasks.isEmpty
            ? _buildEmptyState()
            : _buildTaskList(activeTasks, pendingTasks, completedTasks),
      ),
    );
  }

  // 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_done_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            '暂无传输任务',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '当前没有正在进行的上传或下载任务',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _updateTaskLists,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
          ),
        ],
      ),
    );
  }

  // 构建任务列表
  Widget _buildTaskList(
    List<TransferTask> activeTasks,
    List<TransferTask> pendingTasks,
    List<TransferTask> completedTasks,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (activeTasks.isNotEmpty) ...[
          const _SectionHeader(title: '正在传输', icon: Icons.sync),
          const SizedBox(height: 8),
          ...activeTasks.map((task) => _TaskListItem(task: task)),
          const SizedBox(height: 16),
        ],
        if (pendingTasks.isNotEmpty) ...[
          const _SectionHeader(title: '等待中', icon: Icons.pending_outlined),
          const SizedBox(height: 8),
          ...pendingTasks.map((task) => _TaskListItem(task: task)),
          const SizedBox(height: 16),
        ],
        if (completedTasks.isNotEmpty) ...[
          const _SectionHeader(title: '已完成', icon: Icons.done_all),
          const SizedBox(height: 8),
          ...completedTasks.map((task) => _TaskListItem(task: task)),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

// 分区标题组件
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

// 任务列表项组件
class _TaskListItem extends StatelessWidget {
  final TransferTask task;

  const _TaskListItem({required this.task});

  @override
  Widget build(BuildContext context) {
    final String statusText;
    final Color statusColor;
    final IconData statusIcon;

    // 根据任务状态确定显示属性
    switch (task.status) {
      case TransferStatus.pending:
        statusText = '等待中';
        statusColor = Colors.grey;
        statusIcon = Icons.pending_outlined;
        break;
      case TransferStatus.inProgress:
        statusText = '传输中';
        statusColor = Colors.blue;
        statusIcon = Icons.sync;
        break;
      case TransferStatus.completed:
        statusText = '已完成';
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
        break;
      case TransferStatus.failed:
        statusText = '失败';
        statusColor = Colors.red;
        statusIcon = Icons.error_outline;
        break;
    }

    // 格式化时间
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final startTimeStr = dateFormat.format(task.startTime);
    final endTimeStr =
        task.endTime != null ? dateFormat.format(task.endTime!) : '';

    // 格式化文件大小
    String formatSize(int bytes) {
      const suffixes = ['B', 'KB', 'MB', 'GB'];
      var i = 0;
      double size = bytes.toDouble();
      while (size > 1024 && i < suffixes.length - 1) {
        size /= 1024;
        i++;
      }
      return '${size.toStringAsFixed(1)}${suffixes[i]}';
    }

    // 计算持续时间
    String durationText = '';
    if (task.status == TransferStatus.inProgress) {
      final duration = task.duration;
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      durationText = '$minutes分$seconds秒';
    } else if (task.status == TransferStatus.completed ||
        task.status == TransferStatus.failed) {
      final duration = task.duration;
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      durationText = '$minutes分$seconds秒';
    }

    final bool isUpload = task.type == TransferType.upload;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isUpload ? Icons.upload_file : Icons.download_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '文件大小: ${formatSize(task.fileSize)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '开始时间: $startTimeStr',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      if (task.endTime != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '结束时间: $endTimeStr',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                      if (durationText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '耗时: $durationText',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (task.type == TransferType.upload)
                  const Icon(Icons.cloud_upload, color: Colors.blue)
                else
                  const Icon(Icons.cloud_download, color: Colors.green),
              ],
            ),
            if (task.status == TransferStatus.failed &&
                task.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                '错误: ${task.errorMessage}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
