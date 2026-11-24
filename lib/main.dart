import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'screens/dashboard_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/extender_screen.dart';
import 'screens/login_screen.dart';
import 'screens/protection_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signal_screen.dart';
import 'screens/usage_screen.dart';
import 'screens/wifi_screen.dart';
import 'widgets/common.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(ChangeNotifierProvider.value(value: state, child: const MhmApp()));
}

class MhmApp extends StatelessWidget {
  const MhmApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      title: 'MHM NET5G',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (ctx, child) => Directionality(
        textDirection: s.ar ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: s.connected ? const HomeShell() : const LoginScreen(),
    );
  }
}

class _Dest {
  final IconData icon;
  final String ar;
  final String en;
  final Widget Function() page;
  const _Dest(this.icon, this.ar, this.en, this.page);
}

final _dests = <_Dest>[
  _Dest(Icons.dashboard_rounded, 'الرئيسية', 'Dashboard', () => const DashboardScreen()),
  _Dest(Icons.cell_tower_rounded, 'الإشارة والترددات', 'Signal & Bands', () => const SignalScreen()),
  _Dest(Icons.devices_rounded, 'الأجهزة', 'Devices', () => const DevicesScreen()),
  _Dest(Icons.shield_rounded, 'الحماية والرقابة', 'Protection', () => const ProtectionScreen()),
  _Dest(Icons.wifi_rounded, 'الواي فاي والضيوف', 'WiFi & Guest', () => const WifiScreen()),
  _Dest(Icons.data_usage_rounded, 'الاستهلاك', 'Usage', () => const UsageScreen()),
  _Dest(Icons.router_rounded, 'المقوي', 'Extender', () => const ExtenderScreen()),
  _Dest(Icons.settings_rounded, 'الإعدادات', 'Settings', () => const SettingsScreen()),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  late final AppState _s;

  @override
  void initState() {
    super.initState();
    _s = context.read<AppState>();
    _s.tabRequest.addListener(_onTab);
  }

  void _onTab() {
    final i = _s.tabRequest.value;
    if (i != null && mounted) setState(() => index = i);
    _s.tabRequest.value = null;
  }

  @override
  void dispose() {
    _s.tabRequest.removeListener(_onTab);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final wide = MediaQuery.of(context).size.width >= 900;
    final d = _dests[index];
    final title = Row(children: [
      const Text('MHM ', style: TextStyle(fontWeight: FontWeight.w900)),
      const Text('NET5G',
          style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.cyan)),
      const SizedBox(width: 12),
      Flexible(
        child: Text('· ${s.t(d.ar, d.en)}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.text2, fontSize: 15)),
      ),
    ]);
    final body = KeyedSubtree(key: ValueKey(index), child: d.page());

    final appBar = AppBar(
      title: title,
      actions: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 12),
          child: Chip(
            avatar: Icon(Icons.circle,
                size: 10, color: s.connected ? AppColors.green : AppColors.red),
            label: Text(s.networkLabel, style: const TextStyle(fontSize: 12)),
            backgroundColor: AppColors.surface2,
            side: BorderSide.none,
          ),
        ),
      ],
    );

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(children: [
          NavigationRail(
            extended: MediaQuery.of(context).size.width >= 1150,
            backgroundColor: AppColors.surface,
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => index = i),
            labelType: MediaQuery.of(context).size.width >= 1150
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            destinations: [
              for (final x in _dests)
                NavigationRailDestination(
                    icon: Icon(x.icon), label: Text(s.t(x.ar, x.en))),
            ],
          ),
          Expanded(child: body),
        ]),
      );
    }

    return Scaffold(
      appBar: appBar,
      drawer: Drawer(
        backgroundColor: AppColors.surface,
        child: SafeArea(
          child: ListView(children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Row(children: [
                Icon(Icons.wifi_tethering, color: AppColors.cyan, size: 32),
                SizedBox(width: 10),
                Text('MHM NET5G',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ]),
            ),
            for (var i = 0; i < _dests.length; i++)
              ListTile(
                leading: Icon(_dests[i].icon,
                    color: i == index ? AppColors.cyan : AppColors.text2),
                title: Text(s.t(_dests[i].ar, _dests[i].en)),
                selected: i == index,
                onTap: () {
                  setState(() => index = i);
                  Navigator.pop(context);
                },
              ),
          ]),
        ),
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surface,
        selectedIndex: index < 4 ? index : 4,
        onDestinationSelected: (i) {
          if (i == 4) {
            _openMore(context, s);
          } else {
            setState(() => index = i);
          }
        },
        destinations: [
          for (var i = 0; i < 4; i++)
            NavigationDestination(
                icon: Icon(_dests[i].icon),
                label: s.t(_dests[i].ar, _dests[i].en).split(' ').first),
          NavigationDestination(
              icon: const Icon(Icons.more_horiz_rounded), label: s.t('المزيد', 'More')),
        ],
      ),
    );
  }

  void _openMore(BuildContext context, AppState s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (c) => Directionality(
        textDirection: s.ar ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 4; i < _dests.length; i++)
              ListTile(
                leading: Icon(_dests[i].icon, color: AppColors.cyan),
                title: Text(s.t(_dests[i].ar, _dests[i].en)),
                onTap: () {
                  Navigator.pop(c);
                  setState(() => index = i);
                },
              ),
          ]),
        ),
      ),
    );
  }
}
