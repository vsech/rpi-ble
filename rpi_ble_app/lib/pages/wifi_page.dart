import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/kv.dart';

class WifiPage extends StatefulWidget {
  const WifiPage({super.key});
  @override
  State<WifiPage> createState() => _WifiPageState();
}

class _WifiPageState extends State<WifiPage> {
  Map<String, dynamic>? wifiCfg;
  Map<String, dynamic>? lastScan;
  StreamSubscription? _scanSub;

  final ssidCtl = TextEditingController();
  final pskCtl = TextEditingController();

  @override
  void dispose() {
    _scanSub?.cancel();
    ssidCtl.dispose();
    pskCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    try {
      final cfg = await api.readWifiCfg();
      setState(() => wifiCfg = cfg);
      await _scanSub?.cancel();
      _scanSub =
          api.wifiScanStream().listen((e) => setState(() => lastScan = e));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _scan() async {
    try {
      await context.read<AppState>().api.startWifiScan();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Scan error: $e')));
    }
  }

  Future<void> _connectWifi() async {
    final ssid = ssidCtl.text.trim();
    final psk = pskCtl.text;
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('SSID required')));
      return;
    }
    try {
      await context
          .read<AppState>()
          .api
          .writeWifiCfg({'ssid': ssid, if (psk.isNotEmpty) 'psk': psk});
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Wi-Fi connect sent')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        context.select<AppState, bool>((s) => s.connected != null);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Row(children: [
            FilledButton.icon(
              onPressed: connected ? _load : null,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Load Wi-Fi state'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: connected ? _scan : null,
              icon: const Icon(Icons.search),
              label: const Text('Scan'),
            ),
          ]),
          const SizedBox(height: 12),
          if (!connected) const Center(child: Text('Not connected')),
          if (connected) ...[
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: KV(wifiCfg, title: 'Current Wi-Fi'))),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Connect to network',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                        controller: ssidCtl,
                        decoration: const InputDecoration(labelText: 'SSID')),
                    const SizedBox(height: 8),
                    TextField(
                        controller: pskCtl,
                        decoration: const InputDecoration(
                            labelText: 'Password (optional)'),
                        obscureText: true),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                          onPressed: _connectWifi,
                          child: const Text('Connect')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _wifiScanList(lastScan))),
          ],
        ],
      ),
    );
  }

  Widget _wifiScanList(Map<String, dynamic>? scan) {
    final aps =
        (scan?['aps'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    String humanTs = '';
    if (scan != null) {
      final tsRaw = scan['ts'];
      if (tsRaw is num) {
        humanTs = DateTime.fromMillisecondsSinceEpoch((tsRaw * 1000).round())
            .toLocal()
            .toString();
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('Wi-Fi Scan Results',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(humanTs),
        ]),
        const SizedBox(height: 8),
        if (aps.isEmpty) const Text('— no results —'),
        for (final ap in aps)
          ListTile(
            leading: const Icon(Icons.network_wifi),
            title: Text((ap['ssid']?.toString().isNotEmpty ?? false)
                ? ap['ssid'].toString()
                : '<hidden>'),
            subtitle: Text(
                'Signal ${ap['signal'] ?? ap['sign'] ?? '?'} • Security ${ap['security'] ?? ap['secu'] ?? '?'}'),
            trailing: TextButton(
              onPressed: () => ssidCtl.text = ap['ssid']?.toString() ?? '',
              child: const Text('Use'),
            ),
          ),
      ],
    );
  }
}
