#!/usr/bin/env python3
"""USB/ADB motion-only regression. Exit weft first; never clicks or types on Android."""
import argparse
import concurrent.futures
import json
import os
import pathlib
import queue
import subprocess
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
ADB = os.environ.get('WEFT_ADB', str(pathlib.Path.home() / 'Library/Android/sdk/platform-tools/adb'))


class Client:
    def __init__(self, serial, dex=None):
        self.serial, self.epoch, self.sequence = serial, 0, 0
        self.events, self.lock, self.done = queue.Queue(), threading.Lock(), threading.Event()
        dex = dex or ROOT / 'outputs/DerivedData/Build/Products/Debug/weft.app/Contents/Resources/weft-agent.dex'
        subprocess.run([ADB, '-s', serial, 'push', str(dex), '/data/local/tmp/weft-agent-v2.dex'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.process = subprocess.Popen([ADB, '-s', serial, 'shell', '-T', 'CLASSPATH=/data/local/tmp/weft-agent-v2.dex',
            'app_process', '/', 'io.baiyanwu.weft.BridgeAgent'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1)
        threading.Thread(target=self.read, daemon=True).start()
        threading.Thread(target=self.ping, daemon=True).start()
        try:
            self.ready = self.wait('ready')
            assert self.ready['protocol'] == 3 and self.ready['pointerMode'] == 'absolute'
        except Exception:
            self.close()
            raise

    def read(self):
        for line in self.process.stdout:
            try: self.events.put((time.monotonic(), json.loads(line)))
            except json.JSONDecodeError: pass

    def ping(self):
        while not self.done.wait(.35):
            try: self.send('ping')
            except (BrokenPipeError, ValueError, OSError): return

    def send(self, command):
        with self.lock:
            self.process.stdin.write(command + '\n')
            self.process.stdin.flush()

    def wait(self, kind, predicate=lambda event: True, after=0, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if kind == 'cursor':
                self.send(f'probe {self.epoch}')
            try: timestamp, event = self.events.get(timeout=.1)
            except queue.Empty:
                if self.process.poll() is not None: raise RuntimeError(f'{self.serial}: agent exited')
                continue
            if event.get('type') in ('error', 'entryFailed'): raise RuntimeError(event)
            if timestamp >= after and event.get('type') == kind and predicate(event): return event
        raise TimeoutError((self.serial, kind))

    def enter(self, side, fraction):
        self.epoch += 1
        self.sequence = 0
        start = time.monotonic()
        width, height = self.ready['width'], self.ready['height']
        tx, ty = round(fraction * (width - 1)), round(fraction * (height - 1))
        if side == 'below': ty = 0
        elif side == 'above': ty = height - 1
        elif side == 'left': tx = width - 1
        elif side == 'right': tx = 0
        rotation = self.ready['rotation']
        self.send(f'enter-abs {self.epoch} 0 {tx} {ty} {width} {height} {rotation}')
        event = self.wait('entered', lambda event: event.get('epoch') == self.epoch)
        assert event['x'] == tx and event['y'] == ty, event
        return event, round((time.monotonic() - start) * 1000)

    def pointer(self, x, y):
        self.sequence += 1
        self.send(f'pointer {self.epoch} {self.sequence} {x} {y} 0 0 0')

    def check_motion(self, side, fraction):
        entered, duration = self.enter(side, fraction)
        dx, dy = {'below': (0, 30), 'above': (0, -30), 'left': (-30, 0), 'right': (30, 0)}[side]
        self.pointer(entered['x'] + dx, entered['y'] + dy)
        self.wait('cursor', lambda event: event.get('epoch') == self.epoch and event.get('valid') and
            (event['x'] - entered['x']) * dx + (event['y'] - entered['y']) * dy > 10)
        self.pointer(entered['x'], entered['y'])
        self.wait('cursor', lambda event: event.get('epoch') == self.epoch and event.get('valid') and {
            'below': event['y'] <= 3, 'above': event['y'] >= entered['height'] - 4,
            'left': event['x'] >= entered['width'] - 4, 'right': event['x'] <= 3}[side])
        self.send(f'release {self.epoch}'); self.wait('released')
        return {'device': self.serial, 'direction': side, 'fraction': fraction, 'entryMS': duration, 'passed': True}

    def close(self):
        self.done.set()
        if self.process.poll() is None:
            try: self.send('release'); self.send('quit')
            except (BrokenPipeError, ValueError, OSError): pass
            self.process.stdin.close()
            try: self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.terminate(); self.process.wait(timeout=3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', action='append', required=True)
    parser.add_argument('--dex', type=pathlib.Path, help='Test a freshly built agent before packaging the Mac app.')
    parser.add_argument('--output', default=str(ROOT / 'outputs/device-multi-results.json'))
    args = parser.parse_args()
    if len(set(args.serial)) != len(args.serial): parser.error('Serials must be distinct')
    running = subprocess.check_output(['/bin/ps', '-axo', 'command='], text=True)
    if any(line.strip().endswith('/Contents/MacOS/weft') for line in running.splitlines()):
        parser.error('请先退出 weft，避免同时创建同名虚拟鼠标。')
    clients, results = [], []
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(args.serial)) as pool:
            futures = [pool.submit(Client, serial, args.dex) for serial in args.serial]
            failures = []
            for future in futures:
                try: clients.append(future.result())
                except Exception as error: failures.append(error)
            if failures: raise failures[0]
        for client in clients: client.wait('heartbeat', after=time.monotonic())
        for side, fraction in [('below', .5), ('right', .5), ('above', .5), ('left', .5), ('below', 0), ('below', 1)]:
            for client in clients:
                record = client.check_motion(side, fraction)
                results.append(record); print(json.dumps(record), flush=True)
        if len(clients) > 1:
            clients[0].close()
            survivor = clients[1]
            survivor.wait('heartbeat', after=time.monotonic())
            results.append({**survivor.check_motion('right', .5), 'scenario': 'other-device-disconnected'})
            clients[0] = Client(args.serial[0], args.dex)
            results.append({**clients[0].check_motion('below', .5), 'scenario': 'device-reconnected'})
        output = pathlib.Path(args.output); output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(results, indent=2))
        print(f'{len(results)} checks passed; {output}')
    finally:
        for client in clients: client.close()


if __name__ == '__main__': main()
