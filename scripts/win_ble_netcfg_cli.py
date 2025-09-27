#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import asyncio
import argparse
import json
from typing import Any, Dict, Optional

from bleak import BleakScanner, BleakClient

# ====== UUIDs (должны совпадать с сервером на Raspberry Pi) ======
SVC_UUID = 'd84a0001-4f6f-4e10-8b27-2d9f2d6e0001'
def UUID(n): return f'd84a000{n}-4f6f-4e10-8b27-2d9f2d6e000{n}'


CHR_DEVINFO = UUID(2)   # read/notify
CHR_SCAN_CTRL = UUID(3)   # write
CHR_SCAN_RESULT = UUID(4)   # read/notify
CHR_WIFI_CFG = UUID(5)   # read/write
CHR_LAN_CFG = UUID(6)   # read/write
CHR_ACTION = UUID(7)   # write
CHR_STATUS = UUID(8)   # read/notify


def jb(obj: Any) -> bytes:
    return json.dumps(obj, ensure_ascii=False).encode("utf-8")


def pj(data: bytes) -> Any:
    return json.loads(data.decode("utf-8"))

# ---------- Поиск устройства ----------


async def find_device(name_hint: str = "rpi-netcfg", timeout: float = 6.0):
    """Ищем устройство по имени (предпочтительно) или по сервису, если платформа отдаёт UUID'ы."""
    devices = await BleakScanner.discover(timeout=timeout)
    name_hint_l = (name_hint or "").strip().lower()

    for d in devices:
        # матч по имени
        if (d.name or "").strip().lower() == name_hint_l:
            return d

    # если не нашли по имени — пробуем по сервису, если содержит uuids
    for d in devices:
        uuids = set()
        m = getattr(d, "metadata", None)
        if isinstance(m, dict):
            try:
                uuids = {str(u).lower() for u in (m.get("uuids") or [])}
            except Exception:
                uuids = set()
        if SVC_UUID.lower() in uuids:
            return d

    return None


async def connect(address: Optional[str], name: Optional[str] = None):
    """Возвращает подключённый BleakClient. address > name > автопоиск."""
    dev = None
    if address:
        dev = address  # Bleak принимает строковый адрес
    elif name:
        dev = await find_device(name_hint=name)
    else:
        dev = await find_device()

    if not dev:
        raise RuntimeError(
            "BLE устройство не найдено. Включите Raspberry Pi и Bluetooth на ПК.")

    client = BleakClient(dev)
    await client.connect()
    return client

# ---------- Команды ----------


async def cmd_list() -> None:
    devs = await BleakScanner.discover(timeout=5.0)
    for d in devs:
        print(f"{d.address}\t{d.name}")


async def cmd_devinfo(address: Optional[str], name: Optional[str]) -> None:
    client = await connect(address, name)
    try:
        raw = await client.read_gatt_char(CHR_DEVINFO)
        print(f"Device Info: {raw}")
        print(json.dumps(pj(raw), ensure_ascii=False, indent=2))
    finally:
        await client.disconnect()


async def cmd_status_watch(address: Optional[str], name: Optional[str]) -> None:
    client = await connect(address, name)

    async def cb(_h, data: bytearray):
        try:
            print("[STATUS]", json.dumps(pj(bytes(data)), ensure_ascii=False))
        except Exception:
            pass
    try:
        await client.start_notify(CHR_STATUS, cb)
        print("Подписан на STATUS. Нажмите Ctrl+C для выхода.")
        while True:
            await asyncio.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        try:
            await client.stop_notify(CHR_STATUS)
        except Exception:
            pass
        await client.disconnect()


async def cmd_scan(address: Optional[str], name: Optional[str], wait: float) -> None:
    client = await connect(address, name)

    buf = bytearray()
    got_full = asyncio.Event()

    def try_parse_full() -> bool:
        # Пытаемся распарсить то, что накопилось
        try:
            obj = json.loads(buf.decode("utf-8"))
            print(json.dumps(obj, ensure_ascii=False, indent=2))
            got_full.set()
            return True
        except json.JSONDecodeError:
            return False

    def scan_cb(_h, data: bytearray):
        nonlocal buf
        buf += bytes(data)
        try_parse_full()

    try:
        # 1) подписка на результат
        await client.start_notify(CHR_SCAN_RESULT, scan_cb)
        # 2) триггер скана
        await client.write_gatt_char(CHR_SCAN_CTRL, b"start", response=True)

        if wait <= 0:
            # Быстрый путь: чуть подождать, затем просто READ (на сервере READ отдаёт полный JSON)
            await asyncio.sleep(0.8)
            raw = await client.read_gatt_char(CHR_SCAN_RESULT)
            print(json.dumps(json.loads(raw.decode("utf-8")),
                  ensure_ascii=False, indent=2))
        else:
            # Ждём валидный JSON из чанков; если не успели — fallback на READ
            try:
                await asyncio.wait_for(got_full.wait(), timeout=wait)
            except asyncio.TimeoutError:
                try:
                    raw = await client.read_gatt_char(CHR_SCAN_RESULT)
                    print(json.dumps(json.loads(raw.decode("utf-8")),
                          ensure_ascii=False, indent=2))
                except Exception:
                    print(
                        "Не успели получить полный JSON ни через notify, ни через read.")
    finally:
        try:
            await client.stop_notify(CHR_SCAN_RESULT)
        except Exception:
            pass
        await client.disconnect()


async def cmd_wifi_get(address: Optional[str], name: Optional[str]) -> None:
    client = await connect(address, name)
    try:
        raw = await client.read_gatt_char(CHR_WIFI_CFG)
        print(json.dumps(pj(raw), ensure_ascii=False, indent=2))
    finally:
        await client.disconnect()


async def cmd_wifi_set(address: Optional[str], name: Optional[str], ssid: str, psk: Optional[str]) -> None:
    client = await connect(address, name)
    try:
        cfg: Dict[str, Any] = {"ssid": ssid}
        if psk:
            cfg["psk"] = psk
        await client.write_gatt_char(CHR_WIFI_CFG, jb(cfg), response=True)
        print("Wi-Fi конфиг отправлен.")
    finally:
        await client.disconnect()


async def cmd_lan_get(address: Optional[str], name: Optional[str]) -> None:
    client = await connect(address, name)
    try:
        raw = await client.read_gatt_char(CHR_LAN_CFG)
        print(json.dumps(pj(raw), ensure_ascii=False, indent=2))
    finally:
        await client.disconnect()


async def cmd_lan_set(address: Optional[str], name: Optional[str],
                      method: str, ip: Optional[str], mask: Optional[str],
                      gw: Optional[str], dns: Optional[str]) -> None:
    """
    method: 'dhcp' или 'static'
    ip, mask, gw обязательны при static
    dns — список через запятую (опционально)
    """
    client = await connect(address, name)
    try:
        if method.lower() == "dhcp":
            cfg: Dict[str, Any] = {"method": "dhcp"}
        else:
            if not (ip and mask and gw):
                raise SystemExit("Для static нужны --ip, --mask, --gw")
            cfg = {
                "method": "static",
                "ip": ip,
                "mask": mask,
                "gw": gw,
            }
            if dns:
                cfg["dns"] = [x.strip() for x in dns.split(",") if x.strip()]
        await client.write_gatt_char(CHR_LAN_CFG, jb(cfg), response=True)
        print("LAN конфиг отправлен.")
    finally:
        await client.disconnect()


async def cmd_action(address: Optional[str], name: Optional[str], action_cmd: str) -> None:
    if action_cmd not in ("apply", "reboot"):
        raise SystemExit("action must be 'apply' or 'reboot'")
    client = await connect(address, name)
    try:
        await client.write_gatt_char(CHR_ACTION, action_cmd.encode("utf-8"), response=True)
        print(f"Команда '{action_cmd}' отправлена.")
    finally:
        await client.disconnect()

# ---------- CLI ----------


def main():
    ap = argparse.ArgumentParser(description="Windows BLE CLI для rpi-netcfg")
    ap.add_argument(
        "--addr", help="BLE-адрес (если не указан — поиск по имени/сервису)")
    ap.add_argument(
        "--name", help="Имя BLE-устройства для поиска (по умолчанию rpi-netcfg)")

    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="Показать найденные BLE-устройства")
    sub.add_parser("devinfo", help="Показать Device Info")
    sub.add_parser("status", help="Подписка на статус")
    sub.add_parser("lan-get", help="Прочитать текущий LAN конфиг")

    p_scan = sub.add_parser("scan", help="Скан Wi-Fi (с подпиской)")
    p_scan.add_argument("--wait", type=float, default=2.0,
                        help="Ждать уведомления N секунд (0 — только read)")

    sub.add_parser("wifi-get", help="Прочитать текущий Wi-Fi конфиг")

    p_wset = sub.add_parser("wifi-set", help="Отправить Wi-Fi конфиг")
    p_wset.add_argument("--ssid", required=True)
    p_wset.add_argument("--psk", default=None)

    p_act = sub.add_parser("action", help="Команда apply или reboot")
    p_act.add_argument("cmd", choices=["apply", "reboot"])

    p_lanset = sub.add_parser("lan-set", help="Отправить LAN конфиг")
    p_lanset.add_argument(
        "--method", choices=["dhcp", "static"], required=True)
    p_lanset.add_argument("--ip")
    p_lanset.add_argument("--mask")
    p_lanset.add_argument("--gw")
    p_lanset.add_argument("--dns", help="Список DNS через запятую")

    args = ap.parse_args()

    if args.cmd == "list":
        asyncio.run(cmd_list())
    elif args.cmd == "devinfo":
        asyncio.run(cmd_devinfo(args.addr, args.name or "rpi-netcfg"))
    elif args.cmd == "status":
        asyncio.run(cmd_status_watch(args.addr, args.name or "rpi-netcfg"))
    elif args.cmd == "scan":
        asyncio.run(cmd_scan(args.addr, args.name or "rpi-netcfg", args.wait))
    elif args.cmd == "wifi-get":
        asyncio.run(cmd_wifi_get(args.addr, args.name or "rpi-netcfg"))
    elif args.cmd == "wifi-set":
        asyncio.run(cmd_wifi_set(
            args.addr, args.name or "rpi-netcfg", args.ssid, args.psk))
    elif args.cmd == "lan-get":
        asyncio.run(cmd_lan_get(args.addr, args.name or "rpi-netcfg"))
    elif args.cmd == "lan-set":
        asyncio.run(cmd_lan_set(args.addr, args.name or "rpi-netcfg",
                                args.method, args.ip, args.mask, args.gw, args.dns))
    elif args.cmd == "action":
        asyncio.run(cmd_action(args.addr, args.name or "rpi-netcfg", args.cmd))


if __name__ == "__main__":
    main()
