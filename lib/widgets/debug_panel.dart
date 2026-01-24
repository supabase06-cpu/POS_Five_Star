import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/debug_logger_service.dart';

class DebugButton extends StatelessWidget {
  const DebugButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!DebugLoggerService.isDeveloperMode) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: DebugLoggerService(),
      builder: (context, _) {
        final logger = DebugLoggerService();
        final totalLogs = logger.apiLogs.length + logger.appLogs.length;
        
        return IconButton(
          icon: Badge(
            isLabelVisible: totalLogs > 0,
            label: Text('$totalLogs', style: const TextStyle(fontSize: 10)),
            child: const Icon(Icons.bug_report, color: Colors.white),
          ),
          tooltip: 'Developer Logs',
          onPressed: () => _showDebugPanel(context),
        );
      },
    );
  }

  void _showDebugPanel(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const DebugPanelDialog(),
    );
  }
}

class DebugPanelDialog extends StatefulWidget {
  const DebugPanelDialog({super.key});

  @override
  State<DebugPanelDialog> createState() => _DebugPanelDialogState();
}

class _DebugPanelDialogState extends State<DebugPanelDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _logger = DebugLoggerService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 700,
        height: 500,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF2D2D2D),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bug_report, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Developer Console',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Tabs
            ListenableBuilder(
              listenable: _logger,
              builder: (context, _) {
                return Container(
                  color: const Color(0xFF2D2D2D),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.green,
                    labelColor: Colors.green,
                    unselectedLabelColor: Colors.grey,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.api, size: 16),
                            const SizedBox(width: 6),
                            Text('API (${_logger.apiLogs.length})'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.article, size: 16),
                            const SizedBox(width: 6),
                            Text('Logs (${_logger.appLogs.length})'),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            // Content
            Expanded(
              child: ListenableBuilder(
                listenable: _logger,
                builder: (context, _) {
                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _buildApiTab(),
                      _buildLogsTab(),
                    ],
                  );
                },
              ),
            ),
            // Footer with clear buttons
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF2D2D2D),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep, size: 16),
                    label: const Text('Clear API'),
                    style: TextButton.styleFrom(foregroundColor: Colors.orange),
                    onPressed: () => _logger.clearApiLogs(),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep, size: 16),
                    label: const Text('Clear Logs'),
                    style: TextButton.styleFrom(foregroundColor: Colors.orange),
                    onPressed: () => _logger.clearAppLogs(),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_forever, size: 16),
                    label: const Text('Clear All'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () => _logger.clearAll(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiTab() {
    if (_logger.apiLogs.isEmpty) {
      return const Center(
        child: Text('No API calls yet', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _logger.apiLogs.length,
      itemBuilder: (context, index) {
        final log = _logger.apiLogs[index];
        return _ApiLogTile(log: log);
      },
    );
  }

  Widget _buildLogsTab() {
    if (_logger.appLogs.isEmpty) {
      return const Center(
        child: Text('No logs yet', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _logger.appLogs.length,
      itemBuilder: (context, index) {
        final log = _logger.appLogs[index];
        return _LogTile(log: log);
      },
    );
  }
}

class _ApiLogTile extends StatefulWidget {
  final LogEntry log;
  const _ApiLogTile({required this.log});

  @override
  State<_ApiLogTile> createState() => _ApiLogTileState();
}

class _ApiLogTileState extends State<_ApiLogTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final isError = log.error != null || (log.statusCode != null && log.statusCode! >= 400);
    final statusColor = isError ? Colors.red : Colors.green;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  if (log.statusCode != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${log.statusCode}',
                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      log.title,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (log.duration != null)
                    Text(
                      '${log.duration!.inMilliseconds}ms',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _formatTime(log.timestamp),
                    style: TextStyle(color: Colors.grey[600], fontSize: 10),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14),
                    color: Colors.grey,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _copyToClipboard(context, log),
                  ),
                ],
              ),
            ),
          ),
          // Expanded content
          if (_expanded) ...[
            const Divider(height: 1, color: Color(0xFF3D3D3D)),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (log.request != null) ...[
                    const Text('REQUEST:', style: TextStyle(color: Colors.cyan, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SelectableText(
                        log.request!,
                        style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (log.response != null) ...[
                    const Text('RESPONSE:', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 150),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          log.response!,
                          style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ],
                  if (log.error != null) ...[
                    const Text('ERROR:', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SelectableText(
                        log.error!,
                        style: const TextStyle(color: Colors.red, fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  void _copyToClipboard(BuildContext context, LogEntry log) {
    final text = '''
API: ${log.title}
Status: ${log.statusCode ?? 'N/A'}
Time: ${log.timestamp}
Duration: ${log.duration?.inMilliseconds ?? 'N/A'}ms

REQUEST:
${log.request ?? 'N/A'}

RESPONSE:
${log.response ?? 'N/A'}

ERROR:
${log.error ?? 'N/A'}
''';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
    );
  }
}

class _LogTile extends StatelessWidget {
  final LogEntry log;
  const _LogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatTime(log.timestamp),
            style: TextStyle(color: Colors.grey[600], fontSize: 10, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  log.title,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                if (log.response != null)
                  SelectableText(
                    log.response!,
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}
