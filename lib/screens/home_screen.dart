import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_info.dart';
import '../models/trace_models.dart';
import '../screens/live_trace_screen.dart';
import '../screens/trace_detail_screen.dart';
import '../services/dns_resolver.dart';
import '../services/settings_controller.dart';
import '../services/trace_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    required this.store,
    required this.historyVersion,
    required this.onOpenSettings,
    required this.onOpenHistory,
  });

  final SettingsController settings;
  final TraceStore store;
  final ValueNotifier<int> historyVersion;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenHistory;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _target = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _starting = false;
  String? _error;
  List<TraceSession> _recentSessions = const [];

  @override
  void initState() {
    super.initState();
    widget.historyVersion.addListener(_loadRecent);
    _loadRecent();
  }

  @override
  void dispose() {
    widget.historyVersion.removeListener(_loadRecent);
    _target.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final sessions = await widget.store.list();
      if (!mounted) return;
      setState(() => _recentSessions = sessions.take(3).toList());
    } catch (_) {
      // History is optional; the trace screen still works.
    }
  }

  Future<void> _startTrace() async {
    if (_starting) return;
    final input = _target.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Enter a hostname or IP address to trace.');
      _focus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _starting = true;
      _error = null;
    });

    try {
      final target = await TargetResolver.resolve(input);
      await widget.settings.rememberTarget(
        target.host,
        target.address,
        target.family,
      );
      if (!mounted) return;
      setState(() => _starting = false);
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => LiveTraceScreen(
            target: target,
            config: widget.settings.settings.traceConfig,
            store: widget.store,
            keepScreenOn: widget.settings.settings.keepScreenOn,
            onSaved: () => widget.historyVersion.value++,
          ),
        ),
      );
      _focus.unfocus();
      if (!mounted) return;
      if (saved == true) {
        widget.historyVersion.value++;
        await _loadRecent();
      }
    } on TargetResolutionException catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Could not start the trace: $error';
      });
    }
  }

  void _useRecentTarget(RecentTarget target) {
    _target.text = target.host;
    _target.selection = TextSelection.collapsed(offset: target.host.length);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = widget.settings.settings;
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _Header(),
              const SizedBox(height: 30),
              Text('See every hop.', style: theme.textTheme.displaySmall),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(
                  'Continuous traceroute and latency statistics for the path '
                  'between you and any host.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Target', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _target,
                      focusNode: _focus,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _startTrace(),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'example.com or 1.1.1.1',
                        prefixIcon: const Icon(
                          Icons.language_rounded,
                          size: 21,
                        ),
                        suffixIcon: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _target,
                          builder: (context, value, _) {
                            if (value.text.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return IconButton(
                              tooltip: 'Clear',
                              onPressed: () => _target.clear(),
                              icon: const Icon(Icons.close_rounded, size: 19),
                            );
                          },
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.topCenter,
                      child: _error == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 16,
                                    color: theme.colorScheme.error,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.error,
                                            height: 1.4,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _starting ? null : _startTrace,
                      icon: _starting
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.route_rounded, size: 20),
                      label: Text(
                        _starting ? 'Resolving host…' : 'Start trace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _QuickOption(
                      icon: Icons.bolt_rounded,
                      label: 'Probe',
                      value: settings.probeMode == ProbeMode.auto
                          ? 'Auto ICMP'
                          : settings.probeMode.label,
                      onTap: widget.onOpenSettings,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _QuickOption(
                      icon: Icons.straighten_rounded,
                      label: 'Max hops',
                      value: '${settings.maxHops}',
                      onTap: widget.onOpenSettings,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _QuickOption(
                      icon: Icons.schedule_rounded,
                      label: 'Cycle',
                      value: settings.traceConfig.intervalLabel,
                      onTap: widget.onOpenSettings,
                    ),
                  ),
                ],
              ),
              if (widget.settings.recentTargets.isNotEmpty) ...[
                const SizedBox(height: 28),
                SectionHeader(
                  title: 'Recent targets',
                  subtitle: 'Tap to reuse a destination',
                  trailing: TextButton(
                    onPressed: () async {
                      await widget.settings.clearRecentTargets();
                      if (mounted) setState(() {});
                    },
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final target in widget.settings.recentTargets.take(6))
                      _RecentTargetChip(
                        target: target,
                        onTap: () => _useRecentTarget(target),
                      ),
                  ],
                ),
              ],
              if (_recentSessions.isNotEmpty) ...[
                const SizedBox(height: 30),
                SectionHeader(
                  title: 'Recent traces',
                  subtitle: 'Saved automatically when a trace stops',
                  trailing: TextButton(
                    onPressed: widget.onOpenHistory,
                    child: const Text('View all'),
                  ),
                ),
                const SizedBox(height: 10),
                for (final session in _recentSessions) ...[
                  _RecentTraceTile(
                    session: session,
                    onTap: () async {
                      final deleted = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => TraceDetailScreen(
                            session: session,
                            store: widget.store,
                          ),
                        ),
                      );
                      if (deleted == true) {
                        widget.historyVersion.value++;
                        await _loadRecent();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 28),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        size: 19,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No root required',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Uses unprivileged ICMP sockets with automatic '
                            'UDP fallback. No packet capture, VPN, or special '
                            'permissions.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  '${AppInfo.name} ${AppInfo.version}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.65,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F766E), Color(0xFF155E75)],
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F766E).withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(Icons.route_rounded, color: Colors.white, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppInfo.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                AppInfo.tagline,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
              ),
            ],
          ),
        ),
        StatusPill(
          label: 'MTR',
          color: theme.colorScheme.primary,
          filled: true,
        ),
      ],
    );
  }
}

class _QuickOption extends StatelessWidget {
  const _QuickOption({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTargetChip extends StatelessWidget {
  const _RecentTargetChip({required this.target, required this.onTap});

  final RecentTarget target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 13, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                target.family == 6 ? Icons.lan_rounded : Icons.public_rounded,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                target.host,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (target.host != target.address) ...[
                const SizedBox(width: 5),
                Text(
                  target.address,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTraceTile extends StatelessWidget {
  const _RecentTraceTile({required this.session, required this.onTap});

  final TraceSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final date = DateFormat('MMM d · HH:mm')
        .format(session.startedAt.toLocal());
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: session.reached
                  ? colors.good.withValues(alpha: 0.12)
                  : theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              session.reached
                  ? Icons.check_circle_outline_rounded
                  : Icons.help_outline_rounded,
              size: 18,
              color: session.reached
                  ? colors.good
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$date · ${_hopLabel(session)}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
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
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}

String _hopLabel(TraceSession session) {
  final count = session.hops.where((hop) => hop.received > 0).length;
  return '$count ${count == 1 ? 'hop' : 'hops'}';
}
