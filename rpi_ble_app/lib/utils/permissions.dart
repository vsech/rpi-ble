import 'package:permission_handler/permission_handler.dart';

Future<bool> ensureBlePerms() async {
  final req = <Permission>[
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ];
  final statuses = await req.request();
  return statuses.values.every((s) => s.isGranted);
}
