#!/usr/bin/env python3
"""Exercise real Android device actions through the agent. Exit weft first; restores volume afterward."""
import argparse
import json
import pathlib
import queue
import re
import subprocess
import time

from test_devices import ADB, Client, ROOT


def shell(serial, *args):
    return subprocess.check_output([ADB, '-s', serial, 'shell', *args], text=True, timeout=8)


def volume(serial, stream):
    output = shell(serial, 'cmd', 'media_session', 'volume', '--stream', str(stream), '--get')
    match = re.search(r'volume is (\d+) in range', output)
    if not match:
        raise RuntimeError(f'{serial}: cannot read volume stream {stream}')
    return int(match.group(1))


class MappingClient(Client):
    def visit(self, enabled, actions):
        self.send(f'map-buttons {self.epoch + 1} {int(enabled)} ' + ' '.join(actions))
        entered, _ = self.enter('below', .5)
        self.point = entered['x'], entered['y']
        return entered

    def frame(self, buttons, epoch=None):
        self.sequence += 1
        x, y = self.point
        self.send(f'pointer {self.epoch if epoch is None else epoch} {self.sequence} {x} {y} {buttons} 0 0')

    def barrier(self):
        self.send(f'probe {self.epoch}')
        mapped = []
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            try:
                _, event = self.events.get(timeout=.1)
            except queue.Empty:
                if self.process.poll() is not None:
                    raise RuntimeError('agent exited before input was processed')
                continue
            if event.get('type') in ('error', 'entryFailed'):
                raise RuntimeError(event)
            if event.get('type') == 'mapped':
                mapped.append(event)
            if event.get('type') == 'cursor' and event.get('epoch') == self.epoch:
                return mapped
        raise TimeoutError('input barrier timed out')

    def click_and_hold(self, bit):
        self.frame(bit)
        self.frame(bit)
        self.frame(bit)
        self.frame(0)
        return self.barrier()

    def release(self):
        self.send(f'release {self.epoch}')
        self.wait('released', lambda event: event.get('epoch') == self.epoch)


def check_home(serial):
    home = shell(serial, 'cmd', 'package', 'resolve-activity', '--brief', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME').splitlines()[-1]
    package = home.split('/')[0]
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        windows = shell(serial, 'dumpsys', 'window')
        if any(package in line for line in windows.splitlines() if 'mCurrentFocus=' in line):
            return True
        time.sleep(.1)
    raise AssertionError(f'{serial}: mapped Home did not focus the launcher')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', action='append', required=True)
    parser.add_argument('--dex', type=pathlib.Path, required=True)
    parser.add_argument('--exercise-device-actions', action='store_true', help='Required: this test triggers Back, Home, Recents and volume actions.')
    parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'local/outputs/button-mapping-results.json')
    args = parser.parse_args()
    if not args.exercise_device_actions:
        parser.error('Pass --exercise-device-actions to explicitly exercise Android device functions.')
    if len(set(args.serial)) != len(args.serial):
        parser.error('Serials must be distinct')
    running = subprocess.check_output(['/bin/ps', '-axo', 'command='], text=True)
    if any(line.strip().endswith('/Contents/MacOS/weft') for line in running.splitlines()):
        parser.error('请先退出 weft，避免同时创建同名虚拟鼠标。')
    actions = ['back', 'home', 'recents', 'volumeUp', 'volumeDown']
    keys = [4, 3, 187, 24, 25]
    originals = ['original'] * 5
    records, clients, volumes = [], [], {}
    try:
        for serial in args.serial:
            volumes[serial] = {stream: volume(serial, stream) for stream in [0, 2, 3]}
            clients.append(MappingClient(serial, args.dex))
        for client in clients:
            client.visit(True, actions)
            for index, code in enumerate(keys):
                events = client.click_and_hold(1 << index)
                assert len(events) == 1 and events[0]['keyCode'] == code, events
                assert events[0]['epoch'] == client.epoch, events
                record = {'device': client.serial, 'button': index + 1, 'action': actions[index], 'oncePerPress': True, 'passed': True}
                if code == 3:
                    record['launcherFocused'] = check_home(client.serial)
                records.append(record)
                print(json.dumps(record), flush=True)
            client.release()
            client.visit(False, actions)
            assert client.click_and_hold(8) == [], 'disabled mapping triggered a device action'
            client.frame(31, epoch=client.epoch - 1)
            assert client.barrier() == [], 'stale input triggered an action'
            client.release()
            client.visit(True, originals)
            assert client.click_and_hold(8) == [], 'default button triggered a mapped action'
            client.release()
            record = {'device': client.serial, 'disabled': True, 'defaultsRestored': True, 'staleVisitIgnored': True, 'passed': True}
            records.append(record)
            print(json.dumps(record), flush=True)
    finally:
        for client in clients:
            client.close()
        for serial, streams in volumes.items():
            for stream, initial in streams.items():
                if volume(serial, stream) != initial:
                    shell(serial, 'cmd', 'media_session', 'volume', '--stream', str(stream), '--set', str(initial))
                assert volume(serial, stream) == initial, f'{serial}: volume was not restored'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(records, indent=2))
    print(f'{len(records)} checks passed; {args.output}', flush=True)


if __name__ == '__main__':
    main()
