import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/trace_models.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'latency_chart.dart';

Future<void> showHopDetails(BuildContext context, HopStats hop) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _HopDetailSheet(hop: hop),
  );
}

class _HopDetailSheet extends StatelessWidget {
  const _HopDetailSheet({required this.hop});

  final HopStats hop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final active = hop.received > 0;
    final loss = hop.lossPercent;
    final color = hop.isDestination
        ? theme.colorScheme.primary
        : (active
              ? latencyColor(context, hop.avgMs)
              : theme.colorScheme.onSurfaceVariant);
    final title = hop.hostname?.isNotEmpty == true
        ? hop.hostname!
        : (hop.address?.isNotEmpty == true ? hop.address! : 'No reply');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.28)),
                  ),
                  child: Text(
                    '${hop.ttl}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                      if (hop.hostname != null &&
                          hop.address != null &&
                          hop.hostname != hop.address) ...[
                        const SizedBox(height: 3),
                        Text(
                          hop.address!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  label: hop.isDestination
                      ? 'DESTINATION'
                      : (active
                            ? AppTheme.latencyLabel(hop.avgMs).toUpperCase()
                            : 'NO REPLY'),
                  color: color,
                  filled: true,
                  icon: hop.isDestination ? Icons.flag_rounded : null,
                ),
              ],
            ),
            const SizedBox(height: 22),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Round-trip time',
                        style: theme.textTheme.titleSmall,
                      ),
                      const Spacer(),
                      Text(
                        '${hop.samples.length} probes',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LatencyChart(samples: hop.samples, color: color, height: 180),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Statistics', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 16),
                  _MetricGrid(
                    entries: [
                      ('Sent', '${hop.sent}'),
                      ('Received', '${hop.received}'),
                      ('Lost', '${hop.lost}'),
                      ('In flight', '${hop.pending}'),
                      ('Best', formatMs(hop.bestMs)),
                      ('Average', formatMs(hop.avgMs)),
                      ('Worst', formatMs(hop.worstMs)),
                      ('Std. dev.', formatMs(hop.stdevMs)),
                      ('Last', formatMs(hop.lastMs)),
                      ('Jitter avg', formatMs(hop.jitterAvgMs)),
                      ('Jitter max', formatMs(hop.jitterWorstMs)),
                      ('Loss', formatLoss(loss)),
                    ],
                    accent: color,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: Row(
                            children: [
                              if (hop.received > 0)
                                Expanded(
                                  flex: hop.received,
                                  child: Container(
                                    height: 7,
                                    color: colors.good,
                                  ),
                                ),
                              if (hop.lost > 0)
                                Expanded(
                                  flex: hop.lost,
                                  child: Container(
                                    height: 7,
                                    color: colors.bad,
                                  ),
                                ),
                              if (hop.pending > 0)
                                Expanded(
                                  flex: hop.pending,
                                  child: Container(
                                    height: 7,
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                ),
                              if (hop.received + hop.lost + hop.pending == 0)
                                Expanded(
                                  child: Container(
                                    height: 7,
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        formatLoss(loss),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: lossColor(context, loss),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (hop.address != null && hop.address!.isNotEmpty) ...[
              const SizedBox(height: 16),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Address', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            hop.address!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: hop.address!),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Address copied')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy'),
                        ),
                      ],
                    ),
                    if (hop.alternates.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Other responses',
                        style: theme.textTheme.labelSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final address in hop.alternates)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                address,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Router loss at an intermediate hop does not necessarily mean '
              'end-to-end packet loss. Many routers rate-limit ICMP replies.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ],
        );
      },
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.entries, required this.accent});

  final List<(String, String)> entries;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 520 ? 4 : 3;
        final spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 14,
          children: [
            for (final entry in entries)
              SizedBox(
                width: width,
                child: LabeledValue(
                  label: entry.$1,
                  value: entry.$2,
                  valueColor: entry.$1 == 'Average' ? accent : null,
                ),
              ),
          ],
        );
      },
    );
  }
}
