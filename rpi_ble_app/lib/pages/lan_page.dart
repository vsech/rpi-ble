import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/net_validators.dart';

class LanPage extends StatefulWidget {
  const LanPage({super.key});
  @override
  State<LanPage> createState() => _LanPageState();
}

class _LanPageState extends State<LanPage> {
  Map<String, dynamic>? lan;
  String? selectedDev;

  final _formKey = GlobalKey<FormState>();
  final method = ValueNotifier<String>('dhcp');
  final ipCtl = TextEditingController();
  final maskCtl = TextEditingController();
  final gwCtl = TextEditingController();
  final dnsCtl = TextEditingController();

  @override
  void dispose() {
    ipCtl.dispose();
    maskCtl.dispose();
    gwCtl.dispose();
    dnsCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await context.read<AppState>().api.readLanCfgAll();
      final ifs =
          (m['ifaces'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      setState(() {
        lan = m;
        if (ifs.isNotEmpty) {
          final first = (ifs.first['device'] as String?)?.trim();
          _selectIface(first);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _selectIface(String? devRaw) {
    final dev = devRaw?.trim();
    if (dev == null || dev.isEmpty) return;
    final ifs = (lan?['ifaces'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final cur = ifs.firstWhereOrNull(
          (e) => (e['device'] as String?)?.trim() == dev,
        ) ??
        const <String, dynamic>{};

    setState(() {
      selectedDev = dev;
      method.value = (cur['method'] as String?)?.trim() ?? 'dhcp';
      ipCtl.text = (cur['ip'] as String? ?? '').trim();
      maskCtl.text = (cur['mask'] as String? ?? '').trim();
      gwCtl.text = (cur['gw'] as String? ?? '').trim();
      final dns = (cur['dns'] as List?)?.cast<String>() ?? const [];
      dnsCtl.text = dns.join(',');
    });
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate()) return;
    final dev = selectedDev?.trim();
    if (dev == null || dev.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select interface first')));
      return;
    }

    final cfg = <String, dynamic>{'device': dev, 'method': method.value};
    if (method.value == 'static') {
      cfg['ip'] = ipCtl.text.trim();
      cfg['mask'] = maskCtl.text.trim();
      cfg['gw'] = gwCtl.text.trim();
      cfg['dns'] = NetValidators.normalizeDnsList(dnsCtl.text);
    }

    try {
      await context.read<AppState>().api.writeLanCfg(cfg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LAN config sent for $dev')),
      );
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
    final ifs =
        (lan?['ifaces'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    // список имён интерфейсов (уже trimmed)
    final ifaceNames = [
      for (final e in ifs) (e['device'] as String?)?.trim(),
    ].whereType<String>().toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Row(children: [
            FilledButton.icon(
              onPressed: connected ? _load : null,
              icon: const Icon(Icons.refresh),
              label: const Text('Load LAN state'),
            ),
          ]),
          const SizedBox(height: 12),
          if (!connected) const Center(child: Text('Not connected')),
          if (connected) ...[
            // ====== список интерфейсов ======
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Interfaces',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (ifs.isEmpty) const Text('— no interfaces —'),
                    for (final e in ifs)
                      ListTile(
                        leading: const Icon(Icons.settings_ethernet),
                        title: Text((e['device'] as String? ?? '').trim()),
                        subtitle: Text(
                            '${(e['method'] ?? '').toString()}  ${(e['ip'] ?? '').toString()}'),
                        selected:
                            selectedDev == (e['device'] as String?)?.trim(),
                        onTap: () =>
                            _selectIface((e['device'] as String?)?.trim()),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ====== явный селектор интерфейса ======
            if (ifaceNames.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Text('Edit interface:'),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: selectedDev != null &&
                                ifaceNames.contains(selectedDev)
                            ? selectedDev
                            : ifaceNames.first,
                        items: [
                          for (final name in ifaceNames)
                            DropdownMenuItem(value: name, child: Text(name)),
                        ],
                        onChanged: (v) => _selectIface(v),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 12),

            if (selectedDev != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Edit ${selectedDev!}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Text('Method:'),
                          const SizedBox(width: 12),
                          ValueListenableBuilder<String>(
                            valueListenable: method,
                            builder: (_, v, __) => DropdownButton<String>(
                              value: v,
                              items: const [
                                DropdownMenuItem(
                                    value: 'dhcp', child: Text('DHCP')),
                                DropdownMenuItem(
                                    value: 'static', child: Text('Static')),
                              ],
                              onChanged: (x) =>
                                  method.value = (x ?? 'dhcp').trim(),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<String>(
                          valueListenable: method,
                          builder: (_, v, __) => Column(children: [
                            if (v == 'static') ...[
                              _tf(ipCtl, 'IP',
                                  validator: NetValidators.requiredIpv4),
                              _tf(maskCtl, 'Mask',
                                  validator: NetValidators.requiredIpv4),
                              _tf(gwCtl, 'Gateway',
                                  validator: NetValidators.requiredIpv4),
                              _tf(dnsCtl, 'DNS (comma/space separated)',
                                  validator: NetValidators.optionalDnsList),
                            ],
                          ]),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                              onPressed: _apply, child: const Text('Apply')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tf(TextEditingController c, String label,
      {String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: label),
        validator: validator,
      ),
    );
  }
}
