import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../services/native_bindings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  int? _capabilities;
  String? _engineVersion;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bindings = NativeBindings.instance();
      _capabilities = bindings.capabilities;
      _engineVersion = bindings.version;
      _error = null;
    } catch (error) {
      _capabilities = null;
      _engineVersion = null;
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _has(int mask) => (_capabilities ?? 0) & mask != 0;

  Future<void> _copyDiagnostics() async {
    final text = StringBuffer()
      ..writeln('${AppInfo.name} ${AppInfo.version}')
      ..writeln('Package: ${AppInfo.packageName}')
      ..writeln(
        'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      )
      ..writeln('Dart: ${Platform.version}')
      ..writeln('ABI: ${_abi()}')
      ..writeln('Native engine: ${_engineVersion ?? 'unavailable'}')
      ..writeln('Capabilities: 0x${(_capabilities ?? 0).toRadixString(16)}')
      ..writeln('ICMP IPv4: ${_has(capIcmp4)}')
      ..writeln('UDP IPv4: ${_has(capUdp4)}')
      ..writeln('ICMP IPv6: ${_has(capIcmp6)}')
      ..writeln('UDP IPv6: ${_has(capUdp6)}')
      ..writeln('RECVERR IPv4: ${_has(capRecverr4)}')
      ..writeln('RECVERR IPv6: ${_has(capRecverr6)}')
      ..writeln('Error: ${_error ?? 'none'}');
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Diagnostics copied')));
  }

  String _abi() {
    final abi = Abi.current();
    return switch (abi) {
      Abi.androidArm => 'arm',
      Abi.androidArm64 => 'arm64',
      Abi.androidIA32 => 'x86',
      Abi.androidX64 => 'x86_64',
      Abi.androidRiscv64 => 'riscv64',
      _ => abi.toString(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Copy diagnostics',
            onPressed: _loading ? null : _copyDiagnostics,
            icon: const Icon(Icons.copy_all_outlined, size: 21),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _error == null
                                ? colors.good.withValues(alpha: 0.12)
                                : colors.bad.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _error == null
                                ? Icons.check_circle_outline_rounded
                                : Icons.error_outline_rounded,
                            color: _error == null ? colors.good : colors.bad,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _error == null
                                    ? 'Native engine ready'
                                    : 'Native engine unavailable',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _error == null
                                    ? 'libdmtr ${_engineVersion ?? ''} · ABI ${_abi()}'
                                    : _error!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'PROBE CAPABILITIES',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        _CapabilityRow(
                          title: 'ICMP IPv4 ping socket',
                          description: 'Preferred probe transport',
                          supported: _has(capIcmp4),
                          loading: _loading,
                        ),
                        _CapabilityRow(
                          title: 'UDP IPv4 + error queue',
                          description: 'Compatibility fallback',
                          supported: _has(capUdp4) && _has(capRecverr4),
                          loading: _loading,
                        ),
                        _CapabilityRow(
                          title: 'ICMP IPv6 ping socket',
                          description: 'IPv6 target support',
                          supported: _has(capIcmp6),
                          loading: _loading,
                        ),
                        _CapabilityRow(
                          title: 'UDP IPv6 + error queue',
                          description: 'IPv6 fallback',
                          supported: _has(capUdp6) && _has(capRecverr6),
                          loading: _loading,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _has(capIcmp4)
                        ? 'ICMP is available. Auto mode will use it unless you '
                              'choose UDP in Settings.'
                        : 'ICMP datagram sockets are restricted on this device. '
                              'Auto mode will use UDP probes. Traceroute still '
                              'works, but some destinations may not report the '
                              'final hop.',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'DEVICE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _InfoRow(
                          label: Platform.isAndroid ? 'Android' : 'Linux',
                          value: Platform.operatingSystemVersion,
                        ),
                        _InfoRow(label: 'ABI', value: _abi()),
                        _InfoRow(
                          label: 'App',
                          value: '${AppInfo.version} (${AppInfo.build})',
                        ),
                        _InfoRow(
                          label: 'Package',
                          value: AppInfo.packageName,
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('How probing works', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    'DroidMTR sends one probe per TTL and listens for ICMP '
                    'time-exceeded replies from routers. No root access, raw '
                    'sockets, VPN service, or packet-capture permission is used. '
                    'On networks that filter ICMP, select UDP mode.',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.55),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'DEVELOPER DIAGNOSTICS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      'capabilities: 0x${(_capabilities ?? 0).toRadixString(16)}\n'
                      'engine: ${_engineVersion ?? 'unavailable'}\n'
                      'dart: ${Platform.version}\n'
                      'error: ${_error ?? 'none'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.title,
    required this.description,
    required this.supported,
    required this.loading,
  });

  final String title;
  final String description;
  final bool supported;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Icon(
            supported
                ? Icons.check_circle_rounded
                : Icons.remove_circle_outline_rounded,
            size: 18,
            color: loading
                ? theme.colorScheme.outline
                : (supported ? colors.good : colors.warning),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(description, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          Text(
            loading ? '…' : (supported ? 'Supported' : 'Unavailable'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: loading
                  ? theme.colorScheme.outline
                  : (supported ? colors.good : colors.warning),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(label, style: theme.textTheme.labelSmall),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
