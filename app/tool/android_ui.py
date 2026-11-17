"""Driving the app on the Android emulator as a person does: through what the screen shows.

Flutter gives each control its label in Android's accessibility tree, so `uiautomator dump` lists
them and a tap lands on the control's centre with `adb shell input tap`. Used by
tool/android_record.py; nothing here knows the app's internals.
"""
import os
import re
import subprocess
import time

SDK = os.environ.get('ANDROID_HOME', os.path.expanduser('~/Library/Android/sdk'))
ADB = os.path.join(SDK, 'platform-tools', 'adb')
PKG = 'dev.summitstudio.uponthyhead'


class Device:
    def __init__(self, serial):
        self.serial = serial

    def adb(self, *args, timeout=60, check=False, binary=False):
        r = subprocess.run([ADB, '-s', self.serial, *args], capture_output=True, timeout=timeout)
        if check and r.returncode != 0:
            raise RuntimeError(f'adb {" ".join(args)}: {r.stderr.decode(errors="replace")}')
        return r.stdout if binary else r.stdout.decode(errors='replace')

    def sh(self, cmd, timeout=60):
        return self.adb('shell', cmd, timeout=timeout)

    # ---- the screen ----

    def nodes(self):
        """Every labelled node: (label, (x, y) centre, clickable)."""
        for _ in range(3):
            xml = self.sh('uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; cat /sdcard/ui.xml', timeout=30)
            if '<hierarchy' in xml:
                break
            time.sleep(1)
        out = []
        for m in re.finditer(r'<node ([^>]*)>', xml):
            a = dict(re.findall(r'([\w-]+)="([^"]*)"', m.group(1)))
            label = (a.get('content-desc') or a.get('text') or '').replace('&#10;', '\n').replace('&amp;', '&')
            b = re.findall(r'\d+', a.get('bounds', ''))
            if not label or len(b) != 4:
                continue
            x1, y1, x2, y2 = map(int, b)
            out.append((label, ((x1 + x2) // 2, (y1 + y2) // 2), a.get('clickable') == 'true'))
        return out

    def find(self, pattern):
        r = re.compile(pattern)
        for label, at, _ in self.nodes():
            if r.search(label):
                return at
        return None

    def has(self, pattern):
        return self.find(pattern) is not None

    def wait(self, pattern, seconds=20):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            at = self.find(pattern)
            if at:
                return at
            time.sleep(0.7)
        raise TimeoutError(f'nothing on screen matches {pattern!r}; showing: {[n[0][:60] for n in self.nodes()]}')

    def tap(self, pattern, seconds=20):
        x, y = self.wait(pattern, seconds)
        self.sh(f'input tap {x} {y}')
        return x, y

    def hold(self, pattern, ms=1500):
        x, y = self.wait(pattern)
        self.sh(f'input swipe {x} {y} {x} {y} {ms}', timeout=30)

    def key(self, name):
        self.sh(f'input keyevent {name}')

    def shot(self, path):
        with open(path, 'wb') as f:
            f.write(self.adb('exec-out', 'screencap', '-p', binary=True))

    # ---- the app ----

    def launch(self):
        self.sh(f'am start -n {PKG}/.MainActivity')

    def pid(self):
        return self.sh(f'pidof {PKG}').strip()

    def files(self, sub='.'):
        return self.sh(f'run-as {PKG} ls -la {sub}')

    def pull(self, path_in_app, dest):
        with open(dest, 'wb') as f:
            f.write(self.adb('exec-out', 'run-as', PKG, 'cat', path_in_app, binary=True, timeout=60))

    def logcat_clear(self):
        self.adb('logcat', '-c')

    def logcat(self, tags='speech:I player:I flutter:I *:S'):
        return self.adb('logcat', '-d', '-v', 'epoch', *tags.split(), timeout=30)
