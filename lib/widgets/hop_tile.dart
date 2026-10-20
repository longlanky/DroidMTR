import 'package:flutter/material.dart';

import '../models/trace_models.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'latency_chart.dart';

class HopTile extends StatelessWidget {
  const HopTile({
    super.key,
    required this.hop,
    this.onTap,
    this.compact = false,
  });

  final HopStats hop;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final active = hop.received > 0;
    final latency = active ? hop.avgMs : null;
    final color = hop.isDestination
        ? theme.colorScheme.primary
        : latencyColor(context, latency ?? 0);
    final loss = hop.lossPercent;
    final muted = theme.colorScheme.onSurfaceVariant;

    final title = hop.hostname?.isNotEmpty == true
        ? hop.hostname!
        : (hop.address?.isNotEmpty == true ? hop.address! : 'Awaiting reply');
    final subtitle =
        hop.hostname?.isNotEmpty == true && hop.address?.isNotEmpty == true
        ? hop.address!
        : (active
              ? '${hop.received} of ${hop.completed} probes returned'
              : (hop.sent > 0 ? '${hop.sent} probes sent' : 'Queued'));

    return Semantics(
      button: onTap != null,
      label:
          'Hop ${hop.ttl}, $title, loss ${formatLoss(loss)}, average ${formatMs(latency ?? 0)}',
      child: Material(
        color: hop.isDestination
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.20)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              12,
              compact ? 10 : 12,
              8,
              compact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ),
            child: Row(
              children: [
                _TtlBadge(ttl: hop.ttl, color: color, active: active),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? theme.colorScheme.onSurface
                                    : muted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          if (hop.isDestination) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.flag_rounded,
                              size: 13,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted.withValues(alpha: 0.85),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (active)
                  SizedBox(
                    width: compact ? 66 : 82,
                    height: 34,
                    child: LatencySparkline(
                      samples: hop.samples,
                      color: color,
                      height: 34,
                    ),
                  )
                else
                  SizedBox(
                    width: compact ? 66 : 82,
                    child: Text(
                      hop.sent > 0 ? '···' : '—',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: muted,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 58,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        active ? formatMs(hop.avgMs) : '—',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: active ? color : muted,
                          fontSize: 13,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (loss > 0)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: lossColor(context, loss),
                                shape: BoxShape.circle,
                              ),
                            ),
                          Text(
                            active || hop.lost > 0 ? formatLoss(loss) : '—',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: loss > 0
                                  ? lossColor(context, loss)
                                  : colors.good,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: muted.withValues(alpha: 0.55),
                  ),
                ] else
                  const SizedBox(width: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TtlBadge extends StatelessWidget {
  const _TtlBadge({
    required this.ttl,
    required this.color,
    required this.active,
  });

  final int ttl;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? color.withValues(alpha: 0.10)
            : theme.colorScheme.surfaceContainerHigh,
        shape: BoxShape.circle,
        border: Border.all(
          color: active
              ? color.withValues(alpha: 0.35)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        '$ttl',
        style: theme.textTheme.labelSmall?.copyWith(
          color: active ? color : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class PathStrip extends StatefulWidget {
  const PathStrip({
    super.key,
    required this.hops,
    required this.reached,
    required this.reachedTtl,
    this.running = false,
    this.onHopTap,
  });

  final List<HopStats> hops;
  final bool reached;
  final int reachedTtl;
  final bool running;
  final ValueChanged<HopStats>? onHopTap;

  @override
  State<PathStrip> createState() => _PathStripState();
}

class _PathStripState extends State<PathStrip> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final responding = widget.hops.where((hop) => hop.received > 0).length;
    final status = widget.reached
        ? 'Destination at hop ${widget.reachedTtl}'
        : (responding == 0
              ? 'Discovering path'
              : '$responding ${responding == 1 ? 'hop' : 'hops'} responding');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Path', style: theme.textTheme.titleSmall),
            const SizedBox(width: 8),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: widget.reached ? colors.good : colors.info,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              status,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (widget.reached)
              Icon(Icons.check_circle_rounded, size: 15, color: colors.good),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 54,
          child: widget.hops.isEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Waiting for the first reply…',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : SingleChildScrollView(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      const SizedBox(width: 2),
                      for (var i = 0; i < widget.hops.length; i++) ...[
                        _PathNode(
                          hop: widget.hops[i],
                          onTap: widget.onHopTap == null
                              ? null
                              : () => widget.onHopTap!(widget.hops[i]),
                        ),
                        if (i < widget.hops.length - 1)
                          _Connector(
                            active: widget.hops[i].received > 0,
                            color: widget.hops[i].isDestination
                                ? theme.colorScheme.primary
                                : null,
                          ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _PathNode extends StatelessWidget {
  const _PathNode({required this.hop, this.onTap});

  final HopStats hop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = hop.received > 0;
    final color = hop.isDestination
        ? theme.colorScheme.primary
        : (active
              ? latencyColor(context, hop.avgMs)
              : theme.colorScheme.outline);
    final node = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Center(
            child: Container(
              width: hop.isDestination ? 13 : 10,
              height: hop.isDestination ? 13 : 10,
              decoration: BoxDecoration(
                color: active ? color : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? color
                      : theme.colorScheme.outline.withValues(alpha: 0.7),
                  width: active ? 1.5 : 1.2,
                ),
                boxShadow: hop.isDestination
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.28),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '${hop.ttl}',
          style: theme.textTheme.labelSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            color: active
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            fontWeight: hop.isDestination ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );

    return Semantics(
      button: onTap != null,
      label:
          'Hop ${hop.ttl}${active ? ', ${formatMs(hop.avgMs)}' : ', no reply'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(width: 28, child: node),
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.active, this.color});

  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 18,
      height: 2,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color:
            color ??
            (active
                ? theme.colorScheme.outline
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}
