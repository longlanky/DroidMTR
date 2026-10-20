import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/trace_models.dart';
import '../services/report_formatter.dart';
import '../services/trace_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/hop_detail_sheet.dart';
import '../widgets/hop_tile.dart';

class TraceDetailScreen extends StatefulWidget {
  const TraceDetailScreen({
    super.key,
    required this.session,
    required this.store,
  });

  final TraceSession session;
  final TraceStore store;

  @override
  State<TraceDetailScreen> createState() => _TraceDetailScreenState();
}

class _TraceDetailScreenState extends State<TraceDetailScreen> {
  late final TraceSession _session = widget.session;
  bool _deleting = false;

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this trace?'),
        content: Text(
          'The saved result for ${_session.host} will be permanently removed.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.store.delete(_session.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the trace: $error')),
      );
    }
  }

  Future<void> _share(Future<void> Function(TraceSession) action) async {
    try {
      await action(_session);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share the report: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final date = DateFormat('MMM d, yyyy · HH:mm')
        .format(_session.startedAt.toLocal());
    final respondingHops = _session.hops
        .where((hop) => hop.received > 0)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _session.host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            Text(
              _session.host == _session.address
                  ? (_session.family == 6 ? 'IPv6 target' : 'IPv4 target')
                  : _session.address,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Trace actions',
            onSelected: (value) {
              switch (value) {
                case 'text':
                  _share(ReportSharer.shareText);
                  break;
                case 'csv':
                  _share(ReportSharer.shareCsv);
                  break;
                case 'delete':
                  _delete();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'text',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.notes_rounded),
                  title: Text('Share text report'),
                ),
              ),
              const PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.table_chart_outlined),
                  title: Text('Share CSV data'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'Delete trace',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppCard(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                StatusPill(
                                  label: _session.reached
                                      ? 'REACHED'
                                      : 'NOT REACHED',
                                  color: _session.reached
                                      ? colors.good
                                      : colors.warning,
                                  filled: true,
                                  icon: _session.reached
                                      ? Icons.check_circle_rounded
                                      : Icons.info_rounded,
                                ),
                                const SizedBox(width: 8),
                                StatusPill(
                                  label: _session.mode.label,
                                  color: theme.colorScheme.primary,
                                ),
                                const Spacer(),
                                Text(date, style: theme.textTheme.labelSmall),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _session.host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _session.host == _session.address
                                  ? (_session.family == 6
                                        ? 'IPv6 target'
                                        : 'IPv4 target')
                                  : _session.address,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: MetricTile(
                                    label: 'Duration',
                                    value: formatDuration(_session.durationMs),
                                  ),
                                ),
                                Expanded(
                                  child: MetricTile(
                                    label: 'Hops',
                                    value: '${respondingHops.length}',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: MetricTile(
                                    label: 'Loss',
                                    value: _session.reached
                                        ? formatLoss(_session.lossPercent)
                                        : 'N/A',
                                    valueColor: _session.reached
                                        ? lossColor(
                                            context,
                                            _session.lossPercent,
                                          )
                                        : null,
                                  ),
                                ),
                                Expanded(
                                  child: MetricTile(
                                    label: 'Avg RTT',
                                    value: formatMs(_session.averageRttMs),
                                    valueColor: latencyColor(
                                      context,
                                      _session.averageRttMs,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Divider(color: theme.colorScheme.outlineVariant),
                            const SizedBox(height: 14),
                            PathStrip(
                              hops: _session.hops,
                              reached: _session.reached,
                              reachedTtl: _session.reachedTtl,
                              onHopTap: (hop) => showHopDetails(context, hop),
                            ),
                          ],
                        ),
                      ),
                      if (!_session.reached) ...[
                        const SizedBox(height: 12),
                        AppCard(
                          padding: const EdgeInsets.all(14),
                          borderColor: colors.warning.withValues(alpha: 0.35),
                          color: colors.warning.withValues(alpha: 0.06),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: colors.warning,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'The destination did not answer within '
                                  '${_session.config.maxHops} hops. The path shown '
                                  'is still useful for diagnosing where replies stop.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (respondingHops.isNotEmpty) ...[
                        SectionHeader(
                          title: 'Latency profile',
                          subtitle: 'Average round-trip time by hop',
                        ),
                        const SizedBox(height: 10),
                        AppCard(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                          child: _LatencyProfile(hops: respondingHops),
                        ),
                        const SizedBox(height: 24),
                      ],
                      SectionHeader(
                        title: 'Hops',
                        subtitle:
                            '${_session.totalSent} probes sent · '
                            '${_session.totalRecv} returned',
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              for (final hop in _session.hops)
                if (hop.hasData)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: HopTile(
                          hop: hop,
                          onTap: () => showHopDetails(context, hop),
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'Saved ${DateFormat('MMM d, yyyy · HH:mm').format(_session.endedAt.toLocal())}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (_deleting)
            ColoredBox(
              color: theme.colorScheme.scrim.withValues(alpha: 0.25),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _LatencyProfile extends StatelessWidget {
  const _LatencyProfile({required this.hops});

  final List<HopStats> hops;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final maxValue = hops.fold<double>(
      1,
      (value, hop) => hop.worstMs > value ? hop.worstMs : value,
    );
    return Column(
      children: [
        for (var i = 0; i < hops.length; i++) ...[
          Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${hops[i].ttl}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hops[i].hostname?.isNotEmpty == true
                          ? hops[i].hostname!
                          : (hops[i].address ?? '*'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 5),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final avgFraction = (hops[i].avgMs / maxValue).clamp(
                          0.015,
                          1.0,
                        );
                        final worstFraction = (hops[i].worstMs / maxValue)
                            .clamp(0.015, 1.0);
                        final color = hops[i].isDestination
                            ? theme.colorScheme.primary
                            : latencyColor(context, hops[i].avgMs);
                        return SizedBox(
                          height: 8,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: worstFraction,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.20),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: avgFraction,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 58,
                child: Text(
                  formatMs(hops[i].avgMs),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hops[i].lossPercent > 0
                        ? lossColor(context, hops[i].lossPercent)
                        : theme.colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (i < hops.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(
                height: 1,
                color: colors.grid.withValues(alpha: 0.6),
              ),
            ),
        ],
      ],
    );
  }
}
