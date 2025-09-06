import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/permissions.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            ElevatedButton.icon(
              onPressed: s.scanning
                  ? null
                  : () async {
                      if (!await ensureBlePerms()) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Grant BLE permissions')),
                          );
                        }
                        return;
                      }
                      await s.startScan();
                    },
              icon: const Icon(Icons.search),
              label: const Text('Scan'),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: s.scanning ? () => s.stopScan() : null,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
            const Spacer(),
            if (s.connected != null)
              FilledButton.icon(
                onPressed: () => s.disconnect(),
                icon: const Icon(Icons.link_off),
                label: Text(
                  'Disconnect ${s.connected!.name.isNotEmpty ? s.connected!.name : s.connected!.id}',
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: s.scanResults.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (ctx, i) {
                final d = s.scanResults[i];
                return ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(d.name.isEmpty ? d.id : d.name),
                  subtitle: Text('RSSI ${d.rssi}  •  ${d.id}'),
                  trailing: FilledButton(
                    onPressed: () => s.connect(d),
                    child: const Text('Connect'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
