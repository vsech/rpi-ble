import 'dart:async';
import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

const String svcUuid = 'd84a0001-4f6f-4e10-8b27-2d9f2d6e0001';
String uuidN(int n) => 'd84a000$n-4f6f-4e10-8b27-2d9f2d6e000$n';

final Uuid serviceId = Uuid.parse(svcUuid);
final Uuid chrDevInfo = Uuid.parse(uuidN(2)); // read/notify
final Uuid chrScanCtrl = Uuid.parse(uuidN(3)); // write
final Uuid chrScanRes = Uuid.parse(uuidN(4)); // read/notify
final Uuid chrWifiCfg = Uuid.parse(uuidN(5)); // read/write
final Uuid chrLanCfg = Uuid.parse(uuidN(6)); // read/write
final Uuid chrAction = Uuid.parse(uuidN(7)); // write
final Uuid chrStatus = Uuid.parse(uuidN(8)); // read/notify

class BleNetcfg {
  BleNetcfg(this._ble);
  final FlutterReactiveBle _ble;

  String? _deviceId;

  StreamSubscription<ConnectionStateUpdate>? _connSub;

  QualifiedCharacteristic _qc(Uuid charId) {
    final devId = _deviceId;
    if (devId == null) throw StateError('Not connected');
    return QualifiedCharacteristic(
        deviceId: devId, serviceId: serviceId, characteristicId: charId);
  }

  Future<void> connect(String deviceId) async {
    await _connSub?.cancel();
    _deviceId = deviceId;
    final completer = Completer<void>();

    _connSub = _ble
        .connectToDevice(
            id: deviceId, connectionTimeout: const Duration(seconds: 20))
        .listen((u) {
      switch (u.connectionState) {
        case DeviceConnectionState.connected:
          if (!completer.isCompleted) completer.complete();
          break;
        case DeviceConnectionState.disconnected:
          if (!completer.isCompleted) completer.completeError('Disconnected');
          break;
        default:
          break;
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    });

    return completer.future;
  }

  Future<void> disconnect() async {
    await _connSub?.cancel();
    _connSub = null;
    _deviceId = null;
  }

  // ---- helpers ----
  static List<int> _utf8(String s) => utf8.encode(s);
  static String _str(List<int> v) => utf8.decode(v, allowMalformed: true);
  static List<int> _jsonBytes(Object obj) => utf8.encode(jsonEncode(obj));

  Future<Map<String, dynamic>> _readJson(Uuid id) async {
    final data = await _ble.readCharacteristic(_qc(id));
    return _safeJsonDecode(_str(data)) as Map<String, dynamic>;
  }

  Future<void> _writeString(Uuid id, String s) =>
      _ble.writeCharacteristicWithResponse(_qc(id), value: _utf8(s));

  Future<void> _writeJson(Uuid id, Object obj) async {
    final bytes = _jsonBytes(obj);
    const mtu = 180;
    for (var i = 0; i < bytes.length; i += mtu) {
      final part = bytes.sublist(i, (i + mtu).clamp(0, bytes.length));
      await _ble.writeCharacteristicWithResponse(_qc(id), value: part);
      await Future.delayed(const Duration(milliseconds: 5));
    }
  }

  // ---- API ----
  Future<Map<String, dynamic>> readDeviceInfo() => _readJson(chrDevInfo);

  Stream<Map<String, dynamic>> statusStream() => _ble
      .subscribeToCharacteristic(_qc(chrStatus))
      .transform(_jsonStreamTransformer());

  Future<Map<String, dynamic>> readStatus() => _readJson(chrStatus);

  Future<void> startWifiScan() => _writeString(chrScanCtrl, 'start');

  Stream<Map<String, dynamic>> wifiScanStream() => _ble
      .subscribeToCharacteristic(_qc(chrScanRes))
      .transform(_jsonStreamTransformer());

  Future<Map<String, dynamic>> readWifiCfg() => _readJson(chrWifiCfg);
  Future<void> writeWifiCfg(Map<String, dynamic> cfg) =>
      _writeJson(chrWifiCfg, cfg);

  Future<Map<String, dynamic>> readLanCfgAll() => _readJson(chrLanCfg);
  Future<void> writeLanCfg(Map<String, dynamic> cfg) =>
      _writeJson(chrLanCfg, cfg);

  Future<void> actionApply() => _writeString(chrAction, 'apply');
  Future<void> actionReboot() => _writeString(chrAction, 'reboot');

  // ---- JSON stream transformer ----
  StreamTransformer<List<int>, Map<String, dynamic>> _jsonStreamTransformer() {
    final buffer = StringBuffer();
    Timer? timer;
    void clear() {
      buffer.clear();
      timer?.cancel();
      timer = null;
    }

    return StreamTransformer.fromHandlers(
      handleData: (data, sink) {
        buffer.write(_str(data));
        final parsed = _tryParseJson(buffer.toString());
        if (parsed != null) {
          sink.add(parsed);
          clear();
          return;
        }
        timer ??= Timer(const Duration(milliseconds: 150), () {
          final p2 = _tryParseJson(buffer.toString());
          if (p2 != null) sink.add(p2);
          clear();
        });
      },
      handleDone: (sink) {
        final p = _tryParseJson(buffer.toString());
        if (p != null) sink.add(p);
        sink.close();
        clear();
      },
    );
  }

  static Map<String, dynamic>? _tryParseJson(String s) {
    try {
      final v = _safeJsonDecode(s);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  static Object _safeJsonDecode(String s) {
    final trimmed = s.replaceAll('\u0000', '').trim();
    return jsonDecode(trimmed);
  }
}
