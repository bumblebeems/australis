#!/usr/bin/env python3
"""Set a static colour on Kingston FURY Beast/Renegade DDR5 RGB RAM.

This program accesses only the separate RGB-controller addresses 0x60..0x67.
Notably, it does not access the 0x50..0x57 SPD/temperature addresses, which the spd5118 driver claims.

Examples:
    sudo python3 furyctl.py probe
    sudo python3 furyctl.py --slot 2 --slot 4 \
        static --color 7f00ff --brightness 80 --yes
    sudo python3 furyctl.py --slot 2 --slot 4 off --yes

By default, the program identifies motherboard SMBus adapters from Linux sysfs metadata,
excluding GPU/DDC and other generic I2C adapters, then looks for the FURY signature only at RGB addresses 0x60..0x67.
--bus remains available as an override for unusual motherboards.
Bus numbers can change across boots, which is why automatic identification is preferable.
"""

from __future__ import annotations

import argparse
import ctypes
import fcntl
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path


# Linux i2c-dev UAPI constants.
I2C_SLAVE = 0x0703
I2C_FUNCS = 0x0705
I2C_SMBUS = 0x0720

I2C_FUNC_SMBUS_WRITE_BYTE_DATA = 0x00100000
I2C_FUNC_SMBUS_READ_I2C_BLOCK = 0x04000000

I2C_SMBUS_READ = 1
I2C_SMBUS_WRITE = 0
I2C_SMBUS_BYTE_DATA = 2
I2C_SMBUS_I2C_BLOCK_BROKEN = 6  # 32-byte I2C block read
I2C_SMBUS_BLOCK_MAX = 32

RGB_BASE_ADDRESS = 0x60
RGB_LAST_ADDRESS = 0x67

FURY_SIGNATURE = b"FURY"
KNOWN_SUBTYPES = {
    0x10: "Beast",
    0x11: "Renegade",
    0x12: "Beast",
    0x15: "Beast",
}

# Controller registers used for static colour.
REG_APPLY = 0x08
REG_MODE = 0x09
REG_BRIGHTNESS = 0x20
REG_RED = 0x31
REG_GREEN = 0x32
REG_BLUE = 0x33

BEGIN_TRANSFER = 0x53
END_TRANSFER = 0x44
MODE_STATIC = 0x00


class SMBusData(ctypes.Union):
    _fields_ = [
        ("byte", ctypes.c_uint8),
        ("word", ctypes.c_uint16),
        ("block", ctypes.c_uint8 * (I2C_SMBUS_BLOCK_MAX + 2)),
    ]


class SMBusIoctlData(ctypes.Structure):
    _fields_ = [
        ("read_write", ctypes.c_uint8),
        ("command", ctypes.c_uint8),
        ("size", ctypes.c_uint32),
        ("data", ctypes.POINTER(SMBusData)),
    ]


_libc = ctypes.CDLL(None, use_errno=True)
_libc.ioctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_void_p]
_libc.ioctl.restype = ctypes.c_int


class FuryError(RuntimeError):
    """Expected hardware, access, or protocol failure."""


@dataclass(frozen=True)
class FuryDevice:
    slot: int
    address: int
    subtype: int

    @property
    def model(self) -> str:
        return KNOWN_SUBTYPES[self.subtype]


@dataclass(frozen=True)
class SMBusCandidate:
    number: int
    name: str


class I2CBus:
    def __init__(self, bus_number: int):
        self.path = Path(f"/dev/i2c-{bus_number}")
        self.fd: int | None = None

    def __enter__(self) -> "I2CBus":
        try:
            self.fd = os.open(self.path, os.O_RDWR | os.O_CLOEXEC)
        except FileNotFoundError as exc:
            raise FuryError(
                f"{self.path} does not exist; load i2c-dev and the chipset "
                "SMBus driver, then check i2cdetect -l"
            ) from exc
        except PermissionError as exc:
            raise FuryError(f"permission denied opening {self.path}; run as root") from exc

        funcs = ctypes.c_ulong()
        if _libc.ioctl(self.fd, I2C_FUNCS, ctypes.byref(funcs)) < 0:
            self.close()
            self._raise_errno("querying adapter capabilities")
        required = (
            I2C_FUNC_SMBUS_WRITE_BYTE_DATA | I2C_FUNC_SMBUS_READ_I2C_BLOCK
        )
        missing = required & ~funcs.value
        if missing:
            self.close()
            raise FuryError(
                f"{self.path} lacks required SMBus capabilities (missing 0x{missing:x})"
            )
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def close(self) -> None:
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def _require_fd(self) -> int:
        if self.fd is None:
            raise FuryError("I2C bus is not open")
        return self.fd

    @staticmethod
    def _raise_errno(action: str) -> None:
        err = ctypes.get_errno()
        raise FuryError(f"I2C error while {action}: {os.strerror(err)}")

    def select(self, address: int) -> None:
        # I2C_SLAVE is intentionally used, not I2C_SLAVE_FORCE.  If a kernel
        # driver owns this RGB address, fail rather than bypassing it.
        try:
            fcntl.ioctl(self._require_fd(), I2C_SLAVE, address)
        except OSError as exc:
            raise FuryError(
                f"cannot select RGB address 0x{address:02x} on {self.path}: {exc.strerror}"
            ) from exc

    def _smbus(self, read_write: int, command: int, size: int, data: SMBusData) -> None:
        args = SMBusIoctlData(read_write, command, size, ctypes.pointer(data))
        if _libc.ioctl(self._require_fd(), I2C_SMBUS, ctypes.byref(args)) < 0:
            self._raise_errno(
                f"accessing command 0x{command:02x} on {self.path}"
            )

    def read_i2c_block_32(self, command: int = 0) -> bytes:
        data = SMBusData()
        data.block[0] = I2C_SMBUS_BLOCK_MAX
        self._smbus(
            I2C_SMBUS_READ, command, I2C_SMBUS_I2C_BLOCK_BROKEN, data
        )
        length = min(int(data.block[0]), I2C_SMBUS_BLOCK_MAX)
        return bytes(data.block[1 : length + 1])

    def write_byte_data(self, register: int, value: int) -> None:
        data = SMBusData()
        data.byte = value
        self._smbus(I2C_SMBUS_WRITE, register, I2C_SMBUS_BYTE_DATA, data)


def slot_to_address(slot: int) -> int:
    if not 1 <= slot <= 8:
        raise FuryError("slot must be from 1 to 8")
    return RGB_BASE_ADDRESS + slot - 1


def motherboard_smbus_candidates(
    sysfs_root: Path = Path("/sys/class/i2c-dev"),
) -> list[SMBusCandidate]:
    """Return host SMBus adapters without performing any bus transactions.

    RAM is connected to the motherboard SMBus, whose kernel adapter name starts
    with ``SMBus`` on the supported Intel i801 and AMD piix4 paths.  Display,
    GPU, USB and generic DesignWare I2C adapters are deliberately excluded.
    """
    candidates: list[SMBusCandidate] = []
    try:
        entries = list(sysfs_root.glob("i2c-*"))
    except OSError as exc:
        raise FuryError(f"cannot inspect {sysfs_root}: {exc}") from exc

    for entry in entries:
        match = re.fullmatch(r"i2c-(\d+)", entry.name)
        if not match:
            continue
        try:
            name = (entry / "name").read_text(encoding="utf-8").strip()
        except (OSError, UnicodeError):
            continue
        lowered = name.casefold()
        if not lowered.startswith("smbus "):
            continue
        if any(word in lowered for word in ("stub", "dummy", "virtual")):
            continue
        candidates.append(SMBusCandidate(int(match.group(1)), name))
    return sorted(candidates, key=lambda candidate: candidate.number)


def probe_slot(bus: I2CBus, slot: int) -> FuryDevice | None:
    address = slot_to_address(slot)
    try:
        bus.select(address)
        block = bus.read_i2c_block_32(0x00)
    except FuryError:
        return None

    # Observed controller ID layout: bytes 2..5 = FURY; byte 7 = subtype.
    if len(block) < 8 or block[2:6] != FURY_SIGNATURE:
        return None
    subtype = block[7]
    if subtype not in KNOWN_SUBTYPES:
        raise FuryError(
            f"slot {slot} at 0x{address:02x} says FURY but has unknown "
            f"subtype 0x{subtype:02x}; refusing to write"
        )
    return FuryDevice(slot=slot, address=address, subtype=subtype)


def require_devices(bus: I2CBus, slots: list[int]) -> list[FuryDevice]:
    devices: list[FuryDevice] = []
    for slot in slots:
        device = probe_slot(bus, slot)
        if device is None:
            raise FuryError(
                f"no supported Kingston FURY DDR5 RGB controller found in "
                f"slot {slot} (address 0x{slot_to_address(slot):02x})"
            )
        devices.append(device)
    return devices


def find_fury_bus(slots: list[int]) -> tuple[int, list[SMBusCandidate]]:
    """Locate exactly one motherboard SMBus containing a FURY controller."""
    candidates = motherboard_smbus_candidates()
    if not candidates:
        raise FuryError(
            "no motherboard SMBus adapters were identified in /sys/class/i2c-dev; "
            "load the chipset SMBus driver or supply --bus explicitly"
        )

    matches: list[SMBusCandidate] = []
    access_errors: list[str] = []
    for candidate in candidates:
        try:
            with I2CBus(candidate.number) as bus:
                if any(probe_slot(bus, slot) is not None for slot in slots):
                    matches.append(candidate)
        except FuryError as exc:
            access_errors.append(f"i2c-{candidate.number}: {exc}")

    if len(matches) == 1:
        return matches[0].number, candidates
    if len(matches) > 1:
        details = ", ".join(f"i2c-{item.number} ({item.name})" for item in matches)
        raise FuryError(
            f"FURY controllers appeared on multiple SMBus adapters: {details}; "
            "select one with --bus"
        )

    checked = ", ".join(f"i2c-{item.number} ({item.name})" for item in candidates)
    suffix = f" Access errors: {'; '.join(access_errors)}" if access_errors else ""
    raise FuryError(
        f"no supported FURY controller found on motherboard SMBus adapter(s): "
        f"{checked}.{suffix} Use --bus to override automatic adapter filtering."
    )


def set_static(
    bus: I2CBus, device: FuryDevice, rgb: tuple[int, int, int], brightness: int
) -> None:
    bus.select(device.address)
    writes = (
        (REG_APPLY, BEGIN_TRANSFER),
        (REG_MODE, MODE_STATIC),
        (REG_RED, rgb[0]),
        (REG_GREEN, rgb[1]),
        (REG_BLUE, rgb[2]),
        (REG_BRIGHTNESS, brightness),
        (REG_APPLY, END_TRANSFER),
    )
    for register, value in writes:
        bus.write_byte_data(register, value)
        time.sleep(0.015)


def parse_color(value: str) -> tuple[int, int, int]:
    normalized = value.removeprefix("#")
    if not re.fullmatch(r"[0-9a-fA-F]{6}", normalized):
        raise argparse.ArgumentTypeError("colour must be RRGGBB, e.g. 7f00ff")
    return tuple(bytes.fromhex(normalized))  # type: ignore[return-value]


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Control supported Kingston FURY DDR5 RGB RAM without touching "
            "SPD addresses or unloading spd5118."
        )
    )
    parser.add_argument(
        "--bus",
        type=int,
        help="override automatic motherboard SMBus detection with /dev/i2c-N",
    )
    parser.add_argument(
        "--slot",
        type=int,
        choices=range(1, 9),
        action="append",
        help="RAM/RGB slot 1..8; repeat for multiple sticks",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("probe", help="read-only probe for supported controllers")

    static = subparsers.add_parser("static", help="set a static RGB colour")
    static.add_argument("--color", type=parse_color, required=True, metavar="RRGGBB")
    static.add_argument("--brightness", type=int, choices=range(0, 101), default=80)
    static.add_argument("--yes", action="store_true", help="confirm hardware writes")

    off = subparsers.add_parser("off", help="turn the selected RGB controllers off")
    off.add_argument("--yes", action="store_true", help="confirm hardware writes")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = make_parser().parse_args(argv)
    slots = sorted(set(args.slot or range(1, 9)))

    try:
        bus_number = args.bus
        if bus_number is None:
            bus_number, _ = find_fury_bus(slots)
            print(f"Automatically selected motherboard SMBus i2c-{bus_number}.")

        with I2CBus(bus_number) as bus:
            if args.command == "probe":
                found = []
                for slot in slots:
                    device = probe_slot(bus, slot)
                    if device:
                        found.append(device)
                        print(
                            f"slot {device.slot}: Kingston FURY {device.model} DDR5 RGB "
                            f"at 0x{device.address:02x}"
                        )
                if not found:
                    print("No supported Kingston FURY DDR5 RGB controllers found.")
                    return 2
                return 0

            if not args.slot:
                raise FuryError("--slot is required for a write command")
            if not args.yes:
                raise FuryError("write not confirmed; add --yes after the command options")

            devices = require_devices(bus, slots)
            rgb = args.color if args.command == "static" else (0, 0, 0)
            brightness = args.brightness if args.command == "static" else 0
            for device in devices:
                set_static(bus, device, rgb, brightness)
                print(
                    f"slot {device.slot}: set #{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x} "
                    f"at {brightness}% brightness"
                )
        return 0
    except FuryError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
