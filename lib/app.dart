import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/saved_screen.dart';
import 'screens/settings_screen.dart';
import 'services/settings_controller.dart';
import 'services/trace_store.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.settings, required this.store});

  final SettingsController settings;
  final TraceStore store;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  final ValueNotifier<int> _historyVersion = ValueNotifier<int>(0);

  @override
  void dispose() {
    _historyVersion.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        key: const PageStorageKey('home'),
        settings: widget.settings,
        store: widget.store,
        historyVersion: _historyVersion,
        onOpenSettings: () => _select(2),
        onOpenHistory: () => _select(1),
      ),
      SavedScreen(
        key: const PageStorageKey('history'),
        store: widget.store,
        historyVersion: _historyVersion,
        onStartTrace: () => _select(0),
      ),
      SettingsScreen(
        key: const PageStorageKey('settings'),
        settings: widget.settings,
        store: widget.store,
        historyVersion: _historyVersion,
      ),
    ];

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) _select(0);
      },
      child: Scaffold(
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.route_outlined),
                selectedIcon: Icon(Icons.route_rounded),
                label: 'Trace',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_rounded),
                selectedIcon: Icon(Icons.history_toggle_off_rounded),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_rounded),
                selectedIcon: Icon(Icons.tune_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
