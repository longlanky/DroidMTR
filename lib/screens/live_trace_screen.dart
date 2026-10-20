import 'package:flutter/material.dart';

import '../models/trace_models.dart';
import '../services/report_formatter.dart';
import '../services/trace_controller.dart';
import '../services/trace_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/hop_detail_sheet.dart';
import '../widgets/hop_tile.dart';

class LiveTraceScreen extends StatefulWidget {
  const LiveTraceScreen({
    super.key,
    required this.target,
    required this.config,
    required this.store,
    this.keepScreenOn = true,
    this.onSaved,
  });

  final TraceTarget target;
  final TraceConfig config;
  final TraceStore store;
  final bool keepScreenOn;
  final VoidCallback? onSaved;

  @override
  State<LiveTraceScreen> createState() => _LiveTraceScreenState();
}

class _LiveTraceScreenState extends State<LiveTraceScreen> {
  late TraceController _controller;
  late TraceConfig _config;
  bool _stopping = false;
  bool _allowPop = false;
  bool _savedAny = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _controller = _createController(_config);
    _controller.start();
  }

  TraceController _createController(TraceConfig config) {
    final controller = TraceController(
      target: widget.target,
      config: config,
      store: widget.store,
      keepScreenOn: widget.keepScreenOn,
    );
    controller.addListener(_onControllerChanged);
    return controller;
  }

  void _onControllerChanged() {
    if (!mounted || _disposed) return;
    setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _requestExit() async {
    if (_controller.isActive && !_allowPop) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stop this trace?'),
          content: const Text(
            'The collected result will be saved to your trace history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Keep tracing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Stop & save'),
            ),
          ],
        ),
      );
      if (!mounted || action == null || action == 'cancel') return;
      await _stop(save: action == 'save');
      return;
    }
    if (mounted) Navigator.of(context).pop(_savedAny);
  }

  Future<void> _stop({bool save = true}) async {
    if (_stopping || _allowPop) return;
    setState(() => _stopping = true);
    final session = await _controller.stop(save: save);
    if (!mounted) return;
    final wasSaved =
        save &&
        session != null &&
        _controller.lastSavedSession?.id == session.id;
    setState(() {
      _stopping = false;
      _allowPop = true;
      _savedAny = wasSaved;
    });
    if (wasSaved) widget.onSaved?.call();
    if (session != null && session.totalSent > 0) {
      await _showCompletionSheet(session, saved: wasSaved);
    }
    if (mounted) Navigator.of(context).pop(_savedAny);
  }

  Future<void> _showCompletionSheet(
    TraceSession session, {
    required bool saved,
  }) async {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 2, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: colors.good.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded, color: colors.good, size: 28),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text('Trace complete', style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                saved
                    ? 'Saved to your trace history'
                    : 'This trace was not saved',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 22),
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          label: 'Destination',
                          value: session.reached ? 'Reached' : 'Not reached',
                          valueColor: session.reached
                              ? colors.good
                              : colors.warning,
                        ),
                      ),
                      Expanded(
                        child: MetricTile(
                          label: 'Hops',
                          value:
                              '${session.hops.where((hop) => hop.received > 0).length}',
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
                          value: session.reached
                              ? formatLoss(session.lossPercent)
                              : 'N/A',
                          valueColor: session.reached
                              ? lossColor(context, session.lossPercent)
                              : null,
                        ),
                      ),
                      Expanded(
                        child: MetricTile(
                          label: 'Avg RTT',
                          value: formatMs(session.averageRttMs),
                          valueColor: latencyColor(
                            context,
                            session.averageRttMs,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ReportSharer.shareText(session),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('Share report'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSnapshot() async {
    try {
      final session = await _controller.saveSnapshot();
      if (!mounted) return;
      if (session == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No probe data to save yet.')),
        );
        return;
      }
      _savedAny = true;
      widget.onSaved?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Snapshot saved to History.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save snapshot: $error')),
      );
    }
  }

  void _retryWith(TraceConfig config) {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    setState(() {
      _config = config;
      _controller = _createController(config);
      _controller.start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _controller.snapshot;
    final error = _controller.error;
    final failed = _controller.state == TraceRunState.failed;
    final starting =
        _controller.state == TraceRunState.starting && snapshot == null;

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _requestExit();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _requestExit,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.target.host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                widget.target.host == widget.target.address
                    ? (widget.target.family == 6
                          ? 'IPv6 target'
                          : 'IPv4 target')
                    : widget.target.address,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Save snapshot',
              onPressed: _stopping ? null : _saveSnapshot,
              icon: const Icon(Icons.bookmark_add_outlined, size: 22),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Stack(
          children: [
            if (failed)
              _ErrorView(
                message: error ?? 'The probe engine could not start.',
                mode: _config.mode,
                onTryUdp: _config.mode == ProbeMode.udp
                    ? null
                    : () => _retryWith(_config.copyWith(mode: ProbeMode.udp)),
                onRetry: () => _retryWith(_config),
                onBack: () => Navigator.of(context).pop(_savedAny),
              )
            else if (starting)
              _StartingView(target: widget.target)
            else
              _buildLiveBody(snapshot),
            if (_stopping)
              ColoredBox(
                color: Theme.of(context).colorScheme.scrim
                    .withValues(alpha: 0.28),
                child: Center(
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Saving trace…',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: failed
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: FilledButton.tonalIcon(
                        onPressed: _stopping ? null : () => _stop(save: true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .errorContainer,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onErrorContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        icon: _stopping
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.stop_rounded, size: 20),
                        label: Text(_stopping ? 'Stopping…' : 'Stop trace'),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildLiveBody(TraceSnapshot? snapshot) {
    final theme = Theme.of(context);
    final hops = snapshot?.hops ?? const <HopStats>[];
    final elapsed = snapshot?.elapsedMs ?? 0;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummaryCard(
                      snapshot: snapshot,
                      target: widget.target,
                      elapsedMs: elapsed,
                    ),
                    if (snapshot != null && snapshot.error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _InlineWarning(
                        message: snapshot.error,
                        onTryUdp: snapshot.mode == ProbeMode.udp
                            ? null
                            : () => _retryWith(
                                _config.copyWith(mode: ProbeMode.udp),
                              ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SectionHeader(
                      title: 'Hops',
                      subtitle: 'Tap a hop for the full statistics',
                      trailing: snapshot == null
                          ? null
                          : StatusPill(
                              label: snapshot.mode.label,
                              color: theme.colorScheme.primary,
                            ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hops.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 30),
              child: Center(child: Text('Waiting for the first probe…')),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: hops.length,
              itemBuilder: (context, index) {
                final hop = hops[index];
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: HopTile(
                      hop: hop,
                      onTap: () => showHopDetails(context, hop),
                    ),
                  ),
                );
              },
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Text(
                  snapshot?.reached == true
                      ? 'The path is complete. Probing continues so you can watch '
                            'latency and loss change over time.'
                      : 'Hop loss can be caused by routers that rate-limit replies. '
                            'Compare the final hop to judge end-to-end loss.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.85,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.snapshot,
    required this.target,
    required this.elapsedMs,
  });

  final TraceSnapshot? snapshot;
  final TraceTarget target;
  final int elapsedMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final running = snapshot?.running ?? true;
    final reached = snapshot?.reached ?? false;
    final avg = snapshot?.averageRttMs ?? 0;
    final loss = snapshot?.lossPercent ?? 0;
    final latency = latencyColor(context, avg);
    final hops = snapshot?.hops ?? const <HopStats>[];
    final summary = snapshot?.summaryHop;
    final sent = summary?.sent ?? snapshot?.totalSent ?? 0;
    final received = summary?.received ?? snapshot?.totalRecv ?? 0;
    final lost = summary?.lost ?? snapshot?.totalLost ?? 0;
    final inFlight = summary?.pending ?? snapshot?.totalPending ?? 0;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (running)
                LiveDot(color: theme.colorScheme.primary)
              else
                Icon(
                  reached ? Icons.check_circle_rounded : Icons.info_rounded,
                  size: 13,
                  color: reached ? colors.good : colors.warning,
                ),
              const SizedBox(width: 7),
              Text(
                running ? 'Tracing' : 'Stopped',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· ${_formatElapsed(elapsedMs)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              StatusPill(
                label: reached
                    ? 'DESTINATION REACHED'
                    : target.family == 6
                    ? 'IPv6'
                    : 'IPv4',
                color: reached
                    ? colors.good
                    : theme.colorScheme.onSurfaceVariant,
                filled: reached,
                icon: reached ? Icons.flag_rounded : null,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Average RTT', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          avg > 0 ? formatMs(avg) : '—',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontSize: 32,
                            color: avg > 0
                                ? latency
                                : theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: MetricTile(
                  label: 'Loss',
                  value: snapshot == null || !reached
                      ? 'N/A'
                      : formatLoss(loss),
                  valueColor: snapshot == null || !reached
                      ? null
                      : lossColor(context, loss),
                ),
              ),
              Expanded(
                child: MetricTile(
                  label: 'Hops',
                  value: '${hops.where((hop) => hop.received > 0).length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          PathStrip(
            hops: hops,
            reached: reached,
            reachedTtl: snapshot?.reachedTtl ?? 0,
            running: running,
            onHopTap: (hop) => showHopDetails(context, hop),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: LabeledValue(label: 'Sent', value: '$sent'),
              ),
              Expanded(
                child: LabeledValue(label: 'Received', value: '$received'),
              ),
              Expanded(
                child: LabeledValue(
                  label: 'Lost',
                  value: '$lost',
                  valueColor: lost > 0 ? colors.warning : null,
                ),
              ),
              Expanded(
                child: LabeledValue(label: 'In flight', value: '$inFlight'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatElapsed(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (minutes >= 60) {
      final hours = duration.inHours;
      return '$hours:${(minutes % 60).toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.message, this.onTryUdp});

  final String message;
  final VoidCallback? onTryUdp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderColor: colors.warning.withValues(alpha: 0.4),
      color: colors.warning.withValues(alpha: 0.06),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: colors.warning),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
          if (onTryUdp != null)
            TextButton(onPressed: onTryUdp, child: const Text('Try UDP')),
        ],
      ),
    );
  }
}

class _StartingView extends StatelessWidget {
  const _StartingView({required this.target});

  final TraceTarget target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 18),
            Text('Starting trace', style: theme.textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(
              '${target.host} · ${target.address}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.mode,
    required this.onTryUdp,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final ProbeMode mode;
  final VoidCallback? onTryUdp;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: colors.bad.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  color: colors.bad,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Unable to start the trace',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 22),
              if (onTryUdp != null)
                FilledButton.icon(
                  onPressed: onTryUdp,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 19),
                  label: const Text('Try UDP probe mode'),
                ),
              if (onTryUdp != null) const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onRetry,
                child: Text('Retry ${mode.label}'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onBack, child: const Text('Back')),
            ],
          ),
        ),
      ),
    );
  }
}
