"""Protocol and lifecycle tests without a physical controller."""
import importlib.util
import io
import os
import tempfile
import threading
import time
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('trigger_bridge', 'tools/dualsense/trigger_bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class TriggerBridgeTest(unittest.TestCase):
    def test_usb_report_layout_and_strength(self):
        report = bridge.usb_report(2, 8)
        self.assertEqual(len(report), 63)
        self.assertEqual(report[:2], b'\x02\x0c')
        self.assertEqual(report[11], 0x21)  # right first
        self.assertEqual(report[22], 0x21)
        self.assertEqual(report[12:14], b'\xf8\x03')
        self.assertEqual(report[14:18], sum(7 << (3*i) for i in range(3, 10)).to_bytes(4, 'little'))
        self.assertEqual(report[25:29], sum(1 << (3*i) for i in range(3, 10)).to_bytes(4, 'little'))
        self.assertEqual(bridge.usb_report(0, 0)[11], 5)
        self.assertEqual(bridge.usb_report(0, 0)[22], 5)
        self.assertEqual(bridge.trigger_effect(100), bridge.trigger_effect(8))
        self.assertEqual(bridge.trigger_effect(-1), bridge.trigger_effect(0))

    def test_device_selection_refuses_ambiguous_and_bluetooth(self):
        def uevent(bus, product='00000CE6'):
            return io.StringIO(f'HID_ID={bus}:0000054C:{product}\n')
        with mock.patch.object(bridge.glob, 'glob', return_value=['/sys/class/hidraw/hidraw2']), \
             mock.patch('builtins.open', side_effect=lambda *a, **k: uevent('0003')):
            self.assertEqual(bridge.find_device(), '/dev/hidraw2')
        with mock.patch.object(bridge.glob, 'glob', return_value=['/sys/class/hidraw/hidraw2']), \
             mock.patch('builtins.open', side_effect=lambda *a, **k: uevent('0005')):
            with self.assertRaises(RuntimeError):
                bridge.find_device()
        with mock.patch.object(bridge.glob, 'glob', return_value=['/sys/class/hidraw/hidraw2', '/sys/class/hidraw/hidraw3']), \
             mock.patch('builtins.open', side_effect=lambda *a, **k: uevent('0003')):
            with self.assertRaises(RuntimeError):
                bridge.find_device()

    def test_disconnect_or_game_exit_releases_triggers(self):
        read_fd, write_fd = os.pipe()
        reports = []
        class Stdin:
            def fileno(self): return read_fd
        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.object(bridge, 'find_device', return_value='/dev/fake'), \
             mock.patch.object(bridge.sys, 'stdin', Stdin()), \
             mock.patch.object(bridge.os, 'open', return_value=999), \
             mock.patch.object(bridge.os, 'write', side_effect=lambda fd, data: reports.append(bytes(data)) if fd == 999 else os.write(fd, data)), \
             mock.patch.object(bridge.os, 'close'):
            thread = threading.Thread(target=bridge.run, args=(tmp + '/status',))
            thread.start()
            # use fdopen, as bridge.os is the same module as os
            with os.fdopen(write_fd, 'wb', buffering=0) as stream:
                stream.write(b'3 4\n')
                time.sleep(0.15)
            thread.join(2)
            self.assertFalse(thread.is_alive())
            self.assertEqual(reports[1], bridge.usb_report(3, 4))
            self.assertEqual(reports[-1], bridge.usb_report(0, 0))
        os.close(read_fd)

    def test_watchdog_releases_without_new_input(self):
        read_fd, write_fd = os.pipe()
        reports = []
        class Stdin:
            def fileno(self): return read_fd
        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.object(bridge, 'find_device', return_value='/dev/fake'), \
             mock.patch.object(bridge.sys, 'stdin', Stdin()), \
             mock.patch.object(bridge.os, 'open', return_value=999), \
             mock.patch.object(bridge.os, 'write', side_effect=lambda fd, data: reports.append(bytes(data))), \
             mock.patch.object(bridge.os, 'close'):
            thread = threading.Thread(target=bridge.run, args=(tmp + '/status',))
            thread.start()
            with os.fdopen(write_fd, 'wb', buffering=0) as stream:
                stream.write(b'3 4\n')
                time.sleep(1.2)
                self.assertIn(bytes(bridge.usb_report(3, 4)), reports)
                self.assertEqual(reports[-1], bridge.usb_report(0, 0))
            thread.join(2)
            self.assertFalse(thread.is_alive())
        os.close(read_fd)

    def test_no_device_reports_unavailable(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(bridge, 'find_device', side_effect=RuntimeError('no device')):
            bridge.run(tmp + '/status')
            with open(tmp + '/status', encoding='utf-8') as f:
                self.assertIn('error:', f.read())


if __name__ == '__main__':
    unittest.main()
