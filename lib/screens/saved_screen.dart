import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/trace_models.dart';
import '../screens/trace_detail_screen.dart';
import '../services/trace_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({
    super.key,
    required this.store,
    required this.historyVersion,
    required this.onStartTrace,
  });

  final TraceStore store;
  final ValueNotifier<int> historyVersion;
  final VoidCallback onStartTrace;

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  List<TraceSession> _sessions = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.historyVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.historyVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sessions = await widget.store.list();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _open(TraceSession session) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TraceDetailScreen(session: session, store: widget.store),
      ),
    );
    if (deleted == true) {
      widget.historyVersion.value++;
      await _load();
    }
  }

  Future<void> _delete(TraceSession session) async {
    try {
      await widget.store.delete(session.id);
      widget.historyVersion.value++;
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the trace: $error')),
      );
    }
  }

  Future<bool> _confirmDelete(TraceSession session) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved trace?'),
        content: Text('Remove the result for ${session.host}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _clearAll() async {
    if (_sessions.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all history?'),
        content: Text(
          'This will permanently remove ${_sessions.length} saved '
          '${_sessions.length == 1 ? 'trace' : 'traces'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.clear();
    widget.historyVersion.value++;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('History', style: theme.textTheme.displaySmall),
                          const SizedBox(height: 5),
                          Text(
                            _loading
                                ? 'Loading saved traces…'
                                : '${_sessions.length} saved '
                                      '${_sessions.length == 1 ? 'trace' : 'traces'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (_sessions.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear history',
                        onPressed: _clearAll,
                        icon: const Icon(Icons.delete_sweep_outlined),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                ? EmptyState(
                    icon: Icons.route_outlined,
                    title: 'No saved traces yet',
                    message:
                        'Stopped traces are saved here automatically. '
                        'Start one to begin mapping a network path.',
                    action: FilledButton.icon(
                      onPressed: widget.onStartTrace,
                      icon: const Icon(Icons.route_rounded, size: 19),
                      label: const Text('Start a trace'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(180, 48),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
                      itemCount: _sessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (context, index) {
                        final session = _sessions[index];
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Dismissible(
                              key: ValueKey(session.id),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) => _confirmDelete(session),
                              onDismissed: (_) => _delete(session),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 22),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  Icons.delete_outline_rounded,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                              child: _SessionTile(
                                session: session,
                                onTap: () => _open(session),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.onTap});

  final TraceSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final date = DateFormat('MMM d · HH:mm')
        .format(session.startedAt.toLocal());
    final hops = session.hops.where((hop) => hop.received > 0).length;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: session.reached
                  ? colors.good.withValues(alpha: 0.12)
                  : theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              session.reached
                  ? Icons.check_circle_outline_rounded
                  : Icons.info_outline_rounded,
              size: 20,
              color: session.reached ? colors.good : colors.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        session.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    StatusPill(
                      label: session.mode.label,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '$date · $hops ${hops == 1 ? 'hop' : 'hops'} · ${formatDuration(session.durationMs)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                session.reached ? formatLoss(session.lossPercent) : 'N/A',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: session.reached
                      ? lossColor(context, session.lossPercent)
                      : theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatMs(session.averageRttMs),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            size: 19,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
          ),
        ],
      ),
    );
  }
}
