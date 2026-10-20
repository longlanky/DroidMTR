import 'package:flutter/material.dart';

import '../app_info.dart';
import '../models/trace_models.dart';
import '../services/settings_controller.dart';
import '../services/trace_store.dart';
import '../widgets/common.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.store,
    required this.historyVersion,
  });

  final SettingsController settings;
  final TraceStore store;
  final ValueNotifier<int> historyVersion;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _savedCount = 0;

  @override
  void initState() {
    super.initState();
    widget.historyVersion.addListener(_loadCount);
    _loadCount();
  }

  @override
  void dispose() {
    widget.historyVersion.removeListener(_loadCount);
    super.dispose();
  }

  Future<void> _loadCount() async {
    try {
      final sessions = await widget.store.list();
      if (!mounted) return;
      setState(() => _savedCount = sessions.length);
    } catch (_) {
      // The count is informational.
    }
  }

  AppSettings get _s => widget.settings.settings;

  Future<void> _update(AppSettings value) => widget.settings.update(value);

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear trace history?'),
        content: const Text(
          'All saved trace results will be permanently deleted. '
          'Your settings and recent targets are kept.',
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
            child: const Text('Clear history'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.clear();
    widget.historyVersion.value++;
    await _loadCount();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Trace history cleared.')));
    }
  }

  Future<void> _clearRecent() async {
    await widget.settings.clearRecentTargets();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Recent targets cleared.')));
    }
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.route_rounded, size: 22),
            SizedBox(width: 8),
            Text(AppInfo.name),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${AppInfo.version} (${AppInfo.build})',
              style: Theme.of(dialogContext).textTheme.labelMedium,
            ),
            const SizedBox(height: 10),
            Text(
              AppInfo.description,
              style: Theme.of(dialogContext).textTheme.bodySmall
                  ?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              AppInfo.gplNotice,
              style: Theme.of(dialogContext).textTheme.bodySmall
                  ?.copyWith(height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              showLicensePage(
                context: context,
                applicationName: AppInfo.name,
                applicationVersion: AppInfo.version,
                applicationLegalese: AppInfo.gplNotice,
                applicationIcon: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.route_rounded, size: 36),
                ),
              );
            },
            child: const Text('Licenses'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            children: [
              Text('Settings', style: theme.textTheme.displaySmall),
              const SizedBox(height: 5),
              Text(
                'Tune probes, appearance, and stored data.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              _SettingsGroup(
                title: 'Appearance',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.palette_outlined,
                              size: 19,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Text('Theme', style: theme.textTheme.titleSmall),
                            const Spacer(),
                            Text(switch (_s.themeMode) {
                              AppThemeMode.system => 'System',
                              AppThemeMode.light => 'Light',
                              AppThemeMode.dark => 'Dark',
                            }, style: theme.textTheme.labelSmall),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<AppThemeMode>(
                            segments: const [
                              ButtonSegment(
                                value: AppThemeMode.system,
                                label: Text('System'),
                                icon: Icon(
                                  Icons.brightness_auto_rounded,
                                  size: 16,
                                ),
                              ),
                              ButtonSegment(
                                value: AppThemeMode.light,
                                label: Text('Light'),
                                icon: Icon(Icons.light_mode_outlined, size: 16),
                              ),
                              ButtonSegment(
                                value: AppThemeMode.dark,
                                label: Text('Dark'),
                                icon: Icon(Icons.dark_mode_outlined, size: 16),
                              ),
                            ],
                            selected: {_s.themeMode},
                            showSelectedIcon: false,
                            onSelectionChanged: (selection) => _update(
                              _s.copyWith(themeMode: selection.first),
                            ),
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              textStyle: WidgetStatePropertyAll(
                                theme.textTheme.labelSmall,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsGroup(
                title: 'Tracing defaults',
                children: [
                  _SliderTile(
                    icon: Icons.straighten_rounded,
                    label: 'Maximum hops',
                    value: '${_s.maxHops}',
                    slider: Slider(
                      value: _s.maxHops.toDouble(),
                      min: 1,
                      max: 64,
                      divisions: 63,
                      onChanged: (value) =>
                          _update(_s.copyWith(maxHops: value.round())),
                    ),
                    caption: 'Stop expanding the path after this many routers.',
                  ),
                  _SliderTile(
                    icon: Icons.schedule_rounded,
                    label: 'Cycle interval',
                    value: _s.traceConfig.intervalLabel,
                    slider: Slider(
                      value: _s.intervalMs.toDouble(),
                      min: 200,
                      max: 5000,
                      divisions: 48,
                      onChanged: (value) => _update(
                        _s.copyWith(intervalMs: (value / 100).round() * 100),
                      ),
                    ),
                    caption:
                        'Time spent probing all discovered hops once. Probes '
                        'are spread across the cycle.',
                  ),
                  _SliderTile(
                    icon: Icons.timer_outlined,
                    label: 'Probe timeout',
                    value: _s.traceConfig.timeoutLabel,
                    slider: Slider(
                      value: _s.timeoutMs.toDouble(),
                      min: 500,
                      max: 10000,
                      divisions: 19,
                      onChanged: (value) => _update(
                        _s.copyWith(timeoutMs: (value / 500).round() * 500),
                      ),
                    ),
                    caption:
                        'How long to wait for a reply before counting a loss.',
                  ),
                  _SliderTile(
                    icon: Icons.data_usage_rounded,
                    label: 'Packet payload',
                    value: '${_s.payloadBytes} B',
                    slider: Slider(
                      value: _s.payloadBytes.toDouble(),
                      min: 8,
                      max: 1400,
                      divisions: 174,
                      onChanged: (value) => _update(
                        _s.copyWith(payloadBytes: (value / 8).round() * 8),
                      ),
                    ),
                    caption: 'Payload bytes carried by each ICMP or UDP probe.',
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              size: 19,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Probe mode',
                              style: theme.textTheme.titleSmall,
                            ),
                            const Spacer(),
                            StatusPill(
                              label: _s.probeMode.label,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<ProbeMode>(
                            segments: const [
                              ButtonSegment(
                                value: ProbeMode.auto,
                                label: Text('Auto'),
                              ),
                              ButtonSegment(
                                value: ProbeMode.icmp,
                                label: Text('ICMP'),
                              ),
                              ButtonSegment(
                                value: ProbeMode.udp,
                                label: Text('UDP'),
                              ),
                            ],
                            selected: {_s.probeMode},
                            showSelectedIcon: false,
                            onSelectionChanged: (selection) => _update(
                              _s.copyWith(probeMode: selection.first),
                            ),
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              textStyle: WidgetStatePropertyAll(
                                theme.textTheme.labelSmall,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          _s.probeMode.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.4,
                          ),
                        ),
                        if (_s.probeMode == ProbeMode.auto) ...[
                          const SizedBox(height: 4),
                          Text(
                            'If ICMP sockets are unavailable, UDP is used '
                            'automatically for this trace.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.4,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    secondary: Icon(
                      Icons.dns_outlined,
                      size: 19,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      'Resolve hostnames',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      'Reverse-DNS lookup for responding hops',
                      style: theme.textTheme.bodySmall,
                    ),
                    value: _s.resolveNames,
                    onChanged: (value) =>
                        _update(_s.copyWith(resolveNames: value)),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    secondary: Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 19,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      'Keep screen awake',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      'Prevent the display from sleeping during a trace',
                      style: theme.textTheme.bodySmall,
                    ),
                    value: _s.keepScreenOn,
                    onChanged: (value) =>
                        _update(_s.copyWith(keepScreenOn: value)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsGroup(
                title: 'Data',
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      Icons.history_rounded,
                      size: 19,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      'Saved traces',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      '$_savedCount saved ${_savedCount == 1 ? 'trace' : 'traces'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: TextButton(
                      onPressed: _savedCount == 0 ? null : _clearHistory,
                      child: const Text('Clear'),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      Icons.history_toggle_off_rounded,
                      size: 19,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      'Recent targets',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      '${widget.settings.recentTargets.length} recent '
                      '${widget.settings.recentTargets.length == 1 ? 'destination' : 'destinations'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: TextButton(
                      onPressed: widget.settings.recentTargets.isEmpty
                          ? null
                          : _clearRecent,
                      child: const Text('Clear'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsGroup(
                title: 'System',
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      Icons.monitor_heart_outlined,
                      size: 19,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      'Diagnostics',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      'Socket capabilities and device information',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 19),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DiagnosticsScreen(),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      Icons.info_outline_rounded,
                      size: 19,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      'About ${AppInfo.name}',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      'Version ${AppInfo.version} · GPLv2',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 19),
                    onTap: _showAbout,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  '${AppInfo.name} · ${AppInfo.tagline}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.7,
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

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.7,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.slider,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget slider;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(label, style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                value,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SizedBox(
            height: 34,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: slider,
            ),
          ),
          Text(
            caption,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
