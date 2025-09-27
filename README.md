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

## Building a Debian package

1. Install build prerequisites (Raspberry Pi OS/Debian Bookworm):
   `sudo apt install debhelper dh-python pybuild-plugin-pyproject python3-all python3-build python3-installer python3-setuptools`
2. Make sure `python3-bluezero` is available as a deb package. If it is missing from your repository, build it separately from the `bluezero` sources and install it, for example: `sudo apt install ./python3-bluezero_<ver>_all.deb`.
3. From the project root, build the package: `dpkg-buildpackage -us -uc`.
4. The resulting `rpi-ble_<ver>_all.deb` will appear in the parent directory (`..`). Install it with: `sudo apt install ../rpi-ble_<ver>_all.deb`.
