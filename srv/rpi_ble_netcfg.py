#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import json
import subprocess
import time
from typing import Any, Dict, Optional, List

from gi.repository import GLib
from bluezero import adapter, peripheral

# ==============================
# UUIDs
# ==============================
SVC_UUID = 'd84a0001-4f6f-4e10-8b27-2d9f2d6e0001'
def UUID(n): return f'd84a000{n}-4f6f-4e10-8b27-2d9f2d6e000{n}'


# ==============================
# Global state
# ==============================
_state: Dict[str, Any] = {
    "wifi": {},
    "lan": {},
    "status": {"op": None, "stage": None, "ok": True, "err": None},
    "last_scan": {"ts": 0, "aps": []},
}
WIFI_SCAN_STALE_SECS = 10
WIFI_NOTIFY_CHUNK = 360
# Handles to characteristic objects for sending notifications when enabled
_status_chr_obj = None  # type: Optional[peripheral.Characteristic]
_wifi_scan_chr_obj = None  # type: Optional[peripheral.Characteristic]

# ==============================
# Helpers
# ==============================


def _notify_json_chunks(characteristic, obj: Any) -> None:
    """Отправить JSON чанками через notify, чтобы не упереться в MTU."""
    payload = json_bytes(obj)
    for i in range(0, len(payload), WIFI_NOTIFY_CHUNK):
        chunk = payload[i:i+WIFI_NOTIFY_CHUNK]
        characteristic.set_value(to_le_list(chunk))
        while GLib.events_pending():
            GLib.main_context_default().iteration(False)


def _push_wifi_scan_result(data: Dict[str, Any]) -> None:
    """Всегда обновляем кэш. Если есть подписчики — пушим чанками."""
    global _wifi_scan_chr_obj
    _state["last_scan"] = data
    if _wifi_scan_chr_obj is not None:
        _notify_json_chunks(_wifi_scan_chr_obj, data)


def run(cmd: str) -> subprocess.CompletedProcess:
    cmd = f'sudo {cmd}'
    print(f'RUN: {cmd}')
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, check=False)


def json_bytes(obj: Any) -> bytes:
    return json.dumps(obj, ensure_ascii=False).encode()


def parse_json(b: bytes | bytearray | str) -> Any:
    if isinstance(b, (bytes, bytearray)):
        s = b.decode()
    else:
        s = b
    return json.loads(s)


def to_le_list(b: bytes | bytearray) -> List[int]:
    """Bluezero expects list[int] for characteristic values."""
    return list(b)


def from_le_list(v: List[int]) -> bytes:
    return bytes(v)


def _read_uptime() -> tuple[str, int]:
    pretty = run("uptime -p").stdout.strip() or "up ?"
    try:
        secs = int(float(run("cut -d' ' -f1 /proc/uptime").stdout.strip()))
    except Exception:
        secs = 0
    return pretty, secs


def _read_disk_used_pct() -> float:
    # по корневому разделу
    s = run("df -P / | tail -1 | awk '{print $5}'").stdout.strip().rstrip('%')
    try:
        return float(s)
    except Exception:
        return 0.0


def _read_mem_used_pct() -> float:
    # используем (total - available) / total
    out = run("free -b").stdout.splitlines()
    total = available = None
    for line in out:
        parts = line.split()
        if parts and parts[0] == "Mem:" and len(parts) >= 7:
            total = float(parts[1])
            available = float(parts[6])
            break
    if total and available is not None and total > 0:
        return round((total - available) * 100.0 / total, 1)
    return 0.0


def _read_temp_c() -> Optional[float]:
    # 1) vcgencmd (если доступен)
    r = run("vcgencmd measure_temp 2>/dev/null")
    if r.returncode == 0 and "temp=" in r.stdout:
        try:
            return float(r.stdout.strip().split("=", 1)[1].replace("'C", "").replace("C", ""))
        except Exception:
            pass
    # 2) sysfs
    r2 = run("cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null")
    if r2.stdout.strip().isdigit():
        try:
            return int(r2.stdout.strip()) / 1000.0
        except Exception:
            pass
    return None


def _read_cpu_load1() -> float:
    try:
        # первая колонка /proc/loadavg — loadavg(1m)
        s = run("cat /proc/loadavg").stdout.strip().split()[0]
        return float(s)
    except Exception:
        return 0.0


def _read_arch() -> str:
    return run("uname -m").stdout.strip() or "unknown"


def _read_kernel() -> str:
    return run("uname -r").stdout.strip() or "unknown"


def _read_rpi_model() -> Optional[str]:
    # Для Raspberry Pi модель лежит тут
    cp = run("cat /proc/device-tree/model 2>/dev/null | tr -d '\\0'")
    model = cp.stdout.strip()
    return model or None


def _read_pretty_name() -> str:
    # OS: Debian GNU/Linux 12 (bookworm)
    out = run(
        "awk -F= '$1==\"PRETTY_NAME\"{gsub(/\"/,\"\");print $2}' /etc/os-release").stdout.strip()
    return out or "Linux"

# ==============================
# Network operations
# ==============================


def read_device_info() -> Dict[str, Any]:
    hostname = run("hostname -s").stdout.strip()
    cpu_load = _read_cpu_load1()
    cpu_temp = _read_temp_c()
    mem_used = _read_mem_used_pct()
    disk_used = _read_disk_used_pct()
    uptime_h, uptime_s = _read_uptime()

    os_name = _read_pretty_name()
    arch = _read_arch()
    kernel = _read_kernel()
    host_model = _read_rpi_model() or "Unknown"

    return {
        "hostname": hostname,
        "cpu_load": round(cpu_load, 2),
        "cpu_temp_c": (round(cpu_temp, 1) if cpu_temp is not None else None),
        "mem_used_pct": mem_used,
        "disk_used_pct": disk_used,
        "uptime": uptime_h,
        "uptime_s": uptime_s,
        "os": f"{os_name} {arch}",
        "host": host_model,
        "kernel": kernel,
    }


def read_wifi_cfg() -> Dict[str, Any]:
    ip = run(
        "nmcli -t -f IP4.ADDRESS device show wlan0 | sed 's/IP4.ADDRESS\[1\]:\s*//'").stdout.strip()
    ssid = run(
        "nmcli -t -f GENERAL.CONNECTION dev show wlan0 | sed 's/GENERAL.CONNECTION:\s*//'").stdout.strip()
    return {"ssid": ssid or None, "ip": ip.split('/')[0] if ip else None, "connected": bool(ssid)}

# --- LAN helpers ---


def list_nm_ifaces(include_wifi: bool = True) -> list[tuple[str, str, str]]:
    """
    Return list of (device, type, state) from nmcli. Filters ethernet and optional wifi.
    """
    out = run("nmcli -t -f DEVICE,TYPE,STATE device").stdout.strip().splitlines()
    items: list[tuple[str, str, str]] = []
    for line in out:
        if not line:
            continue
        dev, typ, state = (line.split(':', 2) + ['', ''])[:3]
        if typ == 'ethernet' or (include_wifi and typ == 'wifi'):
            items.append((dev, typ, state))
    return items


def get_primary_eth_iface() -> Optional[str]:
    """Pick a primary Ethernet interface (connected preferred)."""
    items = list_nm_ifaces(include_wifi=False)
    # connected ethernet first
    for dev, typ, state in items:
        if state == 'connected':
            return dev
    return items[0][0] if items else None


def get_connection_name(dev: str) -> Optional[str]:
    """Return active connection profile bound to device (if any)."""
    val = run(
        f"nmcli -t -f GENERAL.CONNECTION dev show {dev} | sed 's/GENERAL.CONNECTION:\s*//'").stdout.strip()
    return val or None


def cidr_to_mask(bits: int) -> str:
    n = (0xffffffff >> (32 - bits)) << (32 - bits)
    return '.'.join(str((n >> (24 - 8*i)) & 0xff) for i in range(4))


def _nm_get(dev: str, key: str) -> list[str]:
    """Return list of values for a given nmcli 'device show' key using -g for robustness."""
    out = run(f"nmcli -g {key} device show {dev}").stdout
    return [line.strip() for line in out.splitlines() if line.strip()]


def _con_get(con: str, key: str) -> Optional[str]:
    out = run(f"nmcli -g {key} connection show '{con}'").stdout.strip()
    return out or None


def read_iface_cfg(dev: str) -> Dict[str, Any]:
    con = get_connection_name(dev)
    # method comes from the *connection* profile
    method_raw = _con_get(con, 'ipv4.method') if con else None
    method = None
    if method_raw:
        method = 'dhcp' if method_raw == 'auto' else (
            'static' if method_raw == 'manual' else method_raw)

    # IP addresses (pick first IPv4)
    addr_list = _nm_get(dev, 'IP4.ADDRESS')  # e.g. 192.168.31.26/24
    ip = None
    mask = None
    if addr_list:
        first = addr_list[0]
        if '/' in first:
            ip_part, cidr = first.split('/', 1)
            ip = ip_part
            try:
                mask = cidr_to_mask(int(cidr))
            except Exception:
                mask = None
        else:
            ip = first

    # Gateway (single value)
    gw_list = _nm_get(dev, 'IP4.GATEWAY')
    gw = gw_list[0] if gw_list else None

    # DNS (possibly multiple)
    dns_list = _nm_get(dev, 'IP4.DNS')

    data = {k: v for k, v in {
        'method': method,
        'ip': ip,
        'mask': mask,
        'gw': gw,
        'dns': dns_list or [],
        'device': dev,
    }.items() if v not in (None, '', [])}
    return data


def read_lan_cfg_all() -> Dict[str, Any]:
    """Return configs for all LAN-related interfaces (ethernet + wifi)."""
    ifaces = list_nm_ifaces(include_wifi=True)
    lst = [read_iface_cfg(dev) for dev, _typ, _state in ifaces]
    # filter empties
    lst = [x for x in lst if x]
    return {"ifaces": lst}


def read_lan_cfg() -> Dict[str, Any]:
    """Kept for backward compatibility: return primary ethernet config, or {}."""
    dev = get_primary_eth_iface()
    return read_iface_cfg(dev) if dev else {}


def scan_wifi() -> Dict[str, Any]:
    run("nmcli device wifi rescan")
    lines = run(
        "nmcli -t -f SSID,SIGNAL,SECURITY device wifi list").stdout.strip().splitlines()
    aps: List[Dict[str, Any]] = []
    for line in lines:
        if not line:
            continue
        ssid, signal, security = (line.split(':', 2) + ['', ''])[:3]
        try:
            sig = int(signal)
        except Exception:
            sig = 0
        if not ssid or sig < 50:
            continue
        aps.append({
            "ssid": ssid,
            "sign": sig,
            "secu": security or "?"
        })
    data = {"ts": time.time(), "aps": aps}
    _state["last_scan"] = data
    return data


def apply_wifi(cfg: Dict[str, Any]) -> tuple[bool, Optional[str]]:
    ssid = cfg.get("ssid")
    psk = cfg.get("psk")
    if not ssid:
        return False, "no_ssid"
    cmd = f'nmcli dev wifi connect "{ssid}"' + \
        (f' password "{psk}"' if psk else '') + ' ifname wlan0'
    r = run(cmd)
    ok = (r.returncode == 0)
    return ok, (None if ok else (r.stderr or r.stdout))


def apply_lan(cfg: Dict[str, Any]) -> tuple[bool, Optional[str]]:
    dev = cfg.get('device') or get_primary_eth_iface()
    con = get_connection_name(dev) if dev else None
    if not con:
        # fall back to a common default name
        con = 'Wired connection 1'
    if cfg.get("method") == "static":
        ip = cfg["ip"]
        mask = cfg["mask"]
        gw = cfg["gw"]
        dns = " ".join(cfg.get("dns", []))
        r1 = run(
            f'nmcli con mod "{con}" '
            f'ipv4.method manual ipv4.addresses "{ip}/{mask_to_cidr(mask)}" '
            f'ipv4.gateway "{gw}" ipv4.dns "{dns}"'
        )
    else:
        r1 = run(f'nmcli con mod "{con}" ipv4.method auto')
    r2 = run(f'nmcli con up "{con}"')
    ok = (r1.returncode == 0 and r2.returncode == 0)
    return ok, (None if ok else (r1.stderr or r2.stderr or r1.stdout or r2.stdout))


def mask_to_cidr(mask: str) -> int:
    return sum(bin(int(x)).count('1') for x in mask.split('.'))

# ==============================
# Status & notifications
# ==============================


def _set_status(op: str, stage: str, ok: bool = True, err: Optional[str] = None) -> None:
    global _status_chr_obj
    _state["status"] = {"op": op, "stage": stage, "ok": ok, "err": err}
    # Update value for reads
    if _status_chr_obj is not None:
        _status_chr_obj.set_value(to_le_list(json_bytes(_state["status"])))


def _push_wifi_scan_result(data: Dict[str, Any]) -> None:
    global _wifi_scan_chr_obj
    if _wifi_scan_chr_obj is not None:
        _wifi_scan_chr_obj.set_value(to_le_list(json_bytes(data)))

# ==============================
# GATT setup with bluezero 0.9 API
# ==============================


def main() -> None:
    # Get adapter
    adapters = list(adapter.Adapter.available())
    if not adapters:
        raise RuntimeError('No Bluetooth adapter found')
    adapter_address = adapters[0].address

    hostname = run("hostname -s").stdout.strip()

    app = peripheral.Peripheral(
        adapter_address, local_name=f'rpi-netcfg-{hostname}')

    # Create one service
    app.add_service(srv_id=1, uuid=SVC_UUID, primary=True)

    # ---- Device Info (read, notify) ----
    def devinfo_read() -> List[int]:
        return to_le_list(json_bytes(read_device_info()))

    app.add_characteristic(
        srv_id=1, chr_id=1, uuid=UUID(2),
        value=[], notifying=False,
        flags=['read', 'notify'],
        read_callback=devinfo_read,
        write_callback=None,
        notify_callback=None,
    )

    # ---- WiFi Scan Control (write) ----
    def scan_write(value: List[int], options: Dict[str, Any]) -> None:
        cmd = from_le_list(value).decode().strip().lower()
        if cmd == 'start':
            _set_status('wifi_scan', 'start', True, None)
            data = scan_wifi()

            def _do_push():
                _push_wifi_scan_result(data)
                _set_status('wifi_scan', 'done', True, None)
                return False
            GLib.idle_add(_do_push)

    app.add_characteristic(
        srv_id=1, chr_id=2, uuid=UUID(3),
        value=[], notifying=False,
        flags=['write', 'write-without-response'],
        write_callback=scan_write,
        read_callback=None,
        notify_callback=None,
    )

    # ---- WiFi Scan Result (read, notify) ----
    def wifi_scan_read() -> List[int]:
        # Return last_scan cached; caller can trigger a fresh scan via control
        last = _state.get('last_scan') or {"ts": 0, "aps": []}
        if not last["aps"] or (time.time() - float(last["ts"])) > WIFI_SCAN_STALE_SECS:
            last = scan_wifi()
            _state["last_scan"] = last
        return to_le_list(json_bytes(last))

    def wifi_scan_notify_cb(notifying: bool, characteristic: peripheral.Characteristic) -> None:
        global _wifi_scan_chr_obj
        _wifi_scan_chr_obj = characteristic if notifying else None

    app.add_characteristic(
        srv_id=1, chr_id=3, uuid=UUID(4),
        value=to_le_list(json_bytes(_state['last_scan'])), notifying=False,
        flags=['read', 'notify'],
        read_callback=wifi_scan_read,
        write_callback=None,
        notify_callback=wifi_scan_notify_cb,
    )

    # ---- WiFi Config (read, write) ----
    def wifi_cfg_read() -> List[int]:
        return to_le_list(json_bytes(read_wifi_cfg()))

    def wifi_cfg_write(value: List[int], options: Dict[str, Any]) -> None:
        try:
            cfg = parse_json(from_le_list(value))
        except Exception as e:
            _set_status('apply', 'wifi_connect', False, f'bad_json: {e}')
            return
        _set_status('apply', 'wifi_connect', True, None)
        ok, err = apply_wifi(cfg)
        _set_status('apply', 'wifi_connect_done', ok, None if ok else err)

    app.add_characteristic(
        srv_id=1, chr_id=4, uuid=UUID(5),
        value=[], notifying=False,
        flags=['read', 'write'],
        read_callback=wifi_cfg_read,
        write_callback=wifi_cfg_write,
        notify_callback=None,
    )

    # ---- LAN Config (read, write) ----
    def lan_cfg_read() -> List[int]:
        # возвращаем все интерфейсы (ethernet + wifi)
        return to_le_list(json_bytes(read_lan_cfg_all()))

    def lan_cfg_write(value: List[int], options: Dict[str, Any]) -> None:
        try:
            cfg = parse_json(from_le_list(value))
        except Exception as e:
            _set_status('apply', 'lan_config', False, f'bad_json: {e}')
            return
        # если указан конкретный интерфейс — применяем к нему, иначе к primary ethernet
        dev = cfg.get('device') or get_primary_eth_iface()
        con = get_connection_name(dev) if dev else None
        if not con:
            con = 'Wired connection 1'
        # соберём минимальный словарь для apply_lan (он теперь сам найдёт con)
        ok, err = apply_lan(cfg)
        _set_status('apply', 'lan_config_done', ok, None if ok else err)
        if ok:
            _state['lan'] = read_lan_cfg_all()

    app.add_characteristic(
        srv_id=1, chr_id=5, uuid=UUID(6),
        value=to_le_list(json_bytes(read_lan_cfg_all())), notifying=False,
        flags=['read', 'write'],
        read_callback=lan_cfg_read,
        write_callback=lan_cfg_write,
        notify_callback=None,
    )

    # ---- Action (write) ----
    def action_write(value: List[int], options: Dict[str, Any]) -> None:
        import os
        cmd = from_le_list(value).decode().strip().lower()
        if cmd == 'apply':
            _set_status('apply', 'done', True, None)
        elif cmd == 'reboot':
            _set_status('reboot', 'now', True, None)
            run('reboot')

    app.add_characteristic(
        srv_id=1, chr_id=6, uuid=UUID(7),
        value=[], notifying=False,
        flags=['write', 'write-without-response'],
        write_callback=action_write,
        read_callback=None,
        notify_callback=None,
    )

    # ---- Status (read, notify) ----
    def status_read() -> List[int]:
        return to_le_list(json_bytes(_state['status']))

    def status_notify_cb(notifying: bool, characteristic: peripheral.Characteristic) -> None:
        global _status_chr_obj
        _status_chr_obj = characteristic if notifying else None

    app.add_characteristic(
        srv_id=1, chr_id=7, uuid=UUID(8),
        value=to_le_list(json_bytes(_state['status'])), notifying=False,
        flags=['read', 'notify'],
        read_callback=status_read,
        write_callback=None,
        notify_callback=status_notify_cb,
    )

    # Publish and run GLib main loop
    app.publish()
    try:
        GLib.MainLoop().run()
    except KeyboardInterrupt:
        app.unpublish()


if __name__ == '__main__':
    main()
