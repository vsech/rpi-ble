import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'pages/devices_page.dart';
import 'pages/info_page.dart';
import 'pages/wifi_page.dart';
import 'pages/lan_page.dart';
import 'pages/actions_page.dart';

void main() {
  runApp(ChangeNotifierProvider(
    create: (_) => AppState(),
    child: const NetcfgApp(),
  ));
}

class NetcfgApp extends StatefulWidget {
  const NetcfgApp({super.key});
  @override
  State<NetcfgApp> createState() => _NetcfgAppState();
}

class _NetcfgAppState extends State<NetcfgApp> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RPI Netcfg',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blueGrey),
      home: Scaffold(
        appBar: AppBar(title: const Text('Raspberry Pi Netcfg over BLE')),
        body: IndexedStack(
          index: _tab,
          children: const [
            DevicesPage(),
            InfoPage(),
            WifiPage(),
            LanPage(),
            ActionsPage(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.bluetooth_searching), label: 'Devices'),
            NavigationDestination(icon: Icon(Icons.memory), label: 'Info'),
            NavigationDestination(icon: Icon(Icons.wifi), label: 'Wi-Fi'),
            NavigationDestination(
                icon: Icon(Icons.settings_ethernet), label: 'LAN'),
            NavigationDestination(icon: Icon(Icons.power), label: 'Actions'),
          ],
        ),
      ),
    );
  }
}
