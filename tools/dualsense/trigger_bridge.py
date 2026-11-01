#!/usr/bin/env python3
"""Linux USB DualSense trigger bridge. stdin: '<left> <right>' strengths 0..8.

Only uses trigger fields in the HID output report. It never changes LEDs or
rumble. A watchdog releases the triggers if the game stops sending updates.
"""
import glob
import os
import select
import sys
import time


def trigger_effect(strength, start=3):
    strength = max(0, min(8, int(strength)))
    if not strength:
        return bytes([0x05] + [0] * 10)
    active = sum(1 << i for i in range(start, 10))
    forces = sum((strength - 1) << (3 * i) for i in range(start, 10))
    return bytes([0x21]) + active.to_bytes(2, 'little') + forces.to_bytes(4, 'little') + bytes(4)


def usb_report(left, right):
    # See DualSense output report layout and feedback bit packing in
    # https://github.com/nowrep/dualsensectl/blob/main/main.c
    report = bytearray(63)
    report[0] = 0x02
    report[1] = 0x0c  # trigger flags only
    report[11:22] = trigger_effect(right)
    report[22:33] = trigger_effect(left)
    return report


def find_device():
    devices = []
    for path in glob.glob('/sys/class/hidraw/hidraw*'):
        try:
            with open(os.path.join(path, 'device/uevent'), encoding='utf-8') as f:
                props = dict(line.strip().split('=', 1) for line in f if '=' in line)
            bus, vendor, product = (int(x, 16) for x in props['HID_ID'].split(':'))
            if vendor == 0x054c and product in (0x0ce6, 0x0df2):
                devices.append((bus, '/dev/' + os.path.basename(path)))
        except (OSError, ValueError, KeyError):
            continue
    if len(devices) != 1 or devices[0][0] != 3:
        raise RuntimeError('Требуется один DualSense по USB')
    return devices[0][1]


def status(path, text):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


def run(status_path):
    fd = None
    failed = False
    try:
        fd = os.open(find_device(), os.O_WRONLY | os.O_NONBLOCK)
        os.write(fd, usb_report(0, 0))  # verify write access before claiming support
        status(status_path, 'ready')
        last = time.monotonic()
        active = False
        pending = b''
        while True:
            readable, _, _ = select.select([sys.stdin.fileno()], [], [], 0.2)
            if readable:
                chunk = os.read(sys.stdin.fileno(), 256)
                if not chunk:
                    break
                pending += chunk
                if len(pending) > 4096:
                    break
                while b'\n' in pending:
                    line, pending = pending.split(b'\n', 1)
                    parts = line.split()
                    if len(parts) != 2:
                        continue
                    try:
                        left, right = (max(0, min(8, int(p))) for p in parts)
                    except ValueError:
                        continue
                    os.write(fd, usb_report(left, right))
                    active = bool(left or right)
                    last = time.monotonic()
            if active and time.monotonic() - last > 0.8:
                os.write(fd, usb_report(0, 0))
                active = False
    except (OSError, RuntimeError) as exc:
        failed = True
        try:
            status(status_path, 'error: ' + str(exc))
        except OSError:
            pass
    finally:
        if fd is not None:
            try:
                os.write(fd, usb_report(0, 0))
            except OSError:
                pass
            os.close(fd)
        if not failed:
            try:
                os.unlink(status_path)
            except OSError:
                pass


if __name__ == '__main__':
    if len(sys.argv) == 2:
        run(sys.argv[1])
