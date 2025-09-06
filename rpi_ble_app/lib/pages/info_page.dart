import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/kv.dart';

class InfoPage extends StatefulWidget {
  const InfoPage({super.key});
  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  Map<String, dynamic>? info;
  Map<String, dynamic>? status;
  StreamSubscription? _statusSub;

  Future<void> _refresh() async {
    final api = context.read<AppState>().api;
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      final i = await api.readDeviceInfo();
      final st = await api.readStatus();
      setState(() {
        info = i;
        status = st;
      });
      await _statusSub?.cancel();
      _statusSub = api.statusStream().listen((e) {
        setState(() => status = e);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
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
              onPressed: connected ? _refresh : null,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ]),
          const SizedBox(height: 12),
          if (!connected) const Center(child: Text('Not connected')),
          if (connected) ...[
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: KV(info, title: 'Device Info'))),
            const SizedBox(height: 12),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: KV(status, title: 'Status (live)'))),
          ],
        ],
      ),
    );
  }
}
