# Raspberry Pi BLE GATT server to expose network settings over BLE

Compatible with bluezero 0.9.x API.

Service UUID and characteristics must match the mobile app (Flutter) side.

Requires:
  `sudo apt install -y python3-dbus python3-gi python3-gi-cairo gir1.2-glib-2.0 libgirepository1.0-dev libcairo2-dev libdbus-1-dev libbluetooth-dev bluez`

  `pip install --no-build-isolation bluezero`

Often needs bluetoothd with --experimental for GATT server:
  `sudo systemctl edit bluetooth.service`

  ```conf
  [Service]
  ExecStart=/usr/lib/bluetooth/bluetoothd --experimental
  ```

  `sudo systemctl daemon-reload && sudo systemctl restart bluetooth`

Install from the repository root:
  `pip install .`

Run the GATT server:
  `rpi-ble-netcfg`

Run the pairing helper agent (optional):
  `rpi-ble-autoagent`

Sample systemd units ship with the package. Resolve their paths via `importlib.resources`:
  - BLE server: `importlib.resources.files("rpi_ble") / "systemd/rpi-ble-netcfg.service"`
  - Auto agent: `importlib.resources.files("rpi_ble") / "systemd/ble-autoagent.service"`
