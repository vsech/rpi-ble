import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class ActionsPage extends StatelessWidget {
  const ActionsPage({super.key});

  Future<void> _do(
      BuildContext context, Future<void> Function() fn, String okMsg) async {
    try {
      await fn();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(okMsg)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        context.select<AppState, bool>((s) => s.connected != null);
    final api = context.read<AppState>().api;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          FilledButton.icon(
            onPressed: connected
                ? () => _do(context, api.actionApply, 'Apply sent')
                : null,
            icon: const Icon(Icons.check),
            label: const Text('Apply'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: connected
                ? () => _do(context, api.actionReboot, 'Reboot sent')
                : null,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reboot'),
          ),
        ],
      ),
    );
  }
}
