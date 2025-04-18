import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/media_sync_service.dart';

/// WebDAV传输状态页面 - 显示正在进行的上传和下载任务
class WebDavStatusPage extends StatefulWidget {
  const WebDavStatusPage({
    super.key,
  });

  @override
  State<WebDavStatusPage> createState() => _WebDavStatusPageState();
}

class _WebDavStatusPageState extends State<WebDavStatusPage> {
  late final MediaSyncService _mediaSyncService;

  // 所有传输任务
  List<TransferTask> _tasks = [];

  // 定时刷新传输任务列表的计时器
  Timer? _refreshTimer;

  // 同步状态信息
  String? _syncStatusInfo;
  int _syncProgress = 0;
  bool _isSyncing = false;
  String? _syncError;

  // 同步步骤
  final List<String> _syncSteps = [
    '准备同步',
    '上传本地映射表',
    '下载并合并云端映射表',
    '创建云端目录结构',
    '上传文件',
    '下载文件',
    '保存同步状态',
    '同步完成'
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;

      _mediaSyncService = context.read<MediaSyncService>();
      // 注册传输任务状态更新回调
      _mediaSyncService.onTransferTasksUpdate = _onTasksUpdated;

      // 注册同步状态更新回调
      _mediaSyncService.onSyncStatusUpdate = _onSyncStatusUpdated;

      // 首次获取任务列表和同步状态
      _updateTaskLists();
      _updateSyncStatus();

      // 设置定时器，每秒刷新一次界面（用于更新时间显示）
      _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            // 更新同步状态
            _updateSyncStatus();
          });
        }
      });
    });
  }

  // 同步状态更新回调
  void _onSyncStatusUpdated(String status) {
    if (mounted) {
      setState(() {
        _syncStatusInfo = status;
      });
    }
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
    final activeTasks = _mediaSyncService.activeTasks;
    final pendingTasks = _mediaSyncService.pendingTasks;
    final completedTasks = _mediaSyncService.completedTasks;

    if (mounted) {
      setState(() {
        _tasks = [...activeTasks, ...pendingTasks, ...completedTasks];
        debugPrint('WebDavStatusPage - 任务列表更新: ${_tasks.length}个任务');
      });
    }
  }

  // 更新同步状态
  void _updateSyncStatus() {
    if (mounted) {
      setState(() {
        _isSyncing = _mediaSyncService.isSyncing;
        _syncProgress = _mediaSyncService.syncProgress;
        _syncError = _mediaSyncService.syncError;

        // 如果有新的状态信息，使用它
        final newStatusInfo = _mediaSyncService.syncStatusInfo;
        if (newStatusInfo != null && newStatusInfo.isNotEmpty) {
          _syncStatusInfo = newStatusInfo;
        }
      });
    }
  }

  @override
  void dispose() {
    // 移除任务状态更新回调
    _mediaSyncService.onTransferTasksUpdate = null;

    // 移除同步状态更新回调
    _mediaSyncService.onSyncStatusUpdate = null;

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
        .sorted((a, b) => (b.endTime ?? DateTime.now())
            .compareTo(a.endTime ?? DateTime.now()))
        .take(50)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV传输状态'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _updateTaskLists();
          _updateSyncStatus();
        },
        child: ListView(
          children: [
            // 同步状态展示卡片
            if (_syncStatusInfo != null || _isSyncing) _buildSyncStatusCard(),

            // 同步步骤进度条
            if (_isSyncing || _syncProgress > 0) _buildSyncProgressSteps(),

            // 任务列表或空状态
            _tasks.isEmpty
                ? _buildEmptyState()
                : _buildTaskList(activeTasks, pendingTasks, completedTasks),
          ],
        ),
      ),
    );
  }

  // 构建同步状态卡片
  Widget _buildSyncStatusCard() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 3,
        color: _syncError != null
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _syncError != null
                        ? Icons.error_outline
                        : _isSyncing
                            ? Icons.sync
                            : Icons.cloud_done,
                    color: _syncError != null
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isSyncing
                          ? '正在同步'
                          : _syncError != null
                              ? '同步错误'
                              : '同步状态',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _syncError != null
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  if (_isSyncing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_syncProgress%',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              if (_syncStatusInfo != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .background
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _syncStatusInfo!,
                          style: const TextStyle(
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_syncError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .error
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .error
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _syncError!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 构建同步步骤进度
  Widget _buildSyncProgressSteps() {
    // 计算当前处于哪个步骤
    final currentStepIndex =
        (_syncProgress / (100 / _syncSteps.length)).floor();
    final currentStep = currentStepIndex.clamp(0, _syncSteps.length - 1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
            child: Text(
              '同步步骤',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  for (int i = 0; i < _syncSteps.length; i++)
                    _buildStepItem(i, currentStep),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建单个步骤项
  Widget _buildStepItem(int index, int currentStep) {
    final bool isCompleted = index < currentStep;
    final bool isCurrent = index == currentStep;
    final bool isUpcoming = index > currentStep;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 步骤指示器
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isCompleted
                    ? Theme.of(context).colorScheme.primary
                    : isCurrent
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCurrent
                      ? Theme.of(context).colorScheme.primary
                      : isUpcoming
                          ? Theme.of(context).colorScheme.outline
                          : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Center(
                child: Icon(
                  isCompleted
                      ? Icons.check
                      : isCurrent
                          ? Icons.sync
                          : Icons.circle,
                  size: 16,
                  color: isCompleted
                      ? Theme.of(context).colorScheme.onPrimary
                      : isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.5),
                ),
              ),
            ),
            if (index < _syncSteps.length - 1)
              Container(
                width: 2,
                height: 24,
                color: isCompleted
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.3),
              ),
          ],
        ),
        const SizedBox(width: 12),
        // 步骤内容
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _syncSteps[index],
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isUpcoming
                        ? Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6)
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (isCurrent && _syncStatusInfo != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _syncStatusInfo!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
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
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
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
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.7),
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
      ),
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
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.3)),
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

extension TruncateList<T> on List<T> {
  List<T> truncate(int maxLength) {
    return length <= maxLength ? this : sublist(0, maxLength);
  }
}
