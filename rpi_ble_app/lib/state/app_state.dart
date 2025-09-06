import 'dart:async'; 
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/ble_netcfg.dart';

class AppState extends ChangeNotifier {
  final FlutterReactiveBle ble = FlutterReactiveBle();
  late final BleNetcfg api = BleNetcfg(ble);

  bool scanning = false;
  List<DiscoveredDevice> scanResults = [];
  DiscoveredDevice? connected;

  StreamSubscription<DiscoveredDevice>? _scanSub;

  Future<void> startScan() async {
    if (scanning) return;
    scanResults = [];
    scanning = true;
    notifyListeners();

    final service = serviceId;
    _scanSub = ble.scanForDevices(
        withServices: [service], scanMode: ScanMode.lowLatency).listen((d) {
      if (d.name.toLowerCase().contains('rpi-netcfg') ||
          d.serviceUuids.contains(service)) {
        final i = scanResults.indexWhere((e) => e.id == d.id);
        if (i >= 0) {
          scanResults[i] = d;
        } else {
          scanResults.add(d);
        }
        notifyListeners();
      }
    }, onError: (_) {
      scanning = false;
      notifyListeners();
    });
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    scanning = false;
    notifyListeners();
  }

  Future<void> connect(DiscoveredDevice d) async {
    await stopScan();
    await api.connect(d.id);
    connected = d;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await api.disconnect();
    connected = null;
    notifyListeners();
  }
}
