#!/usr/bin/env python3
"""The Android app lock, the recent-apps cover and location, unattended, on a booted emulator
(tool/android_lock.sh boots it, gives it a PIN and a fingerprint, and takes them away again).

Driven through the screen as a person would (tool/android_ui.py), from a fresh install of a build
made with SEED_SAMPLES=first-run (the five samples, and the first run all the same):

  1. the first run: Fingerprint or screen lock, Allow, the system prompt, a fingerprint touch from
     adb; Location, Allow, Android's question, "Only this time"; the microphone and notifications;
     through to the sky. No row moves when it is answered.
  2. away 70 s: locked on return, the prompt up; cancelled, the screen and its accessibility tree
     hold nothing of any blessing; Unlock, a fingerprint; away 70 s again, unlocked with the PIN.
  3. away 20 s: not locked.
  6. a blessing open, then recent apps: screenshots with the lock on and with it off (turning it
     off asks first); the lock turned on again.
  s. away 70 s with Dart slow to answer (a debug hook holds `active` back 10 s), the notification shade
     opened and closed before it answers: the plain cover holds until the answer, which locks.
  p. Home over Android's location question, away 70 s: locked; answering the question opens the prompt.
  9. location: a blessing recorded after "Only this time" carries the emulator's place rounded to a
     tenth of a degree; then a fresh install refusing location: the Salt Lake Temple, said so in
     Settings; then location off for the whole phone: "Use my location" comes back at once, still
     the Salt Lake Temple. Each path timed; Begin timed from the tap to the recording starting.

Prints one line per check and writes summary.json; exits non-zero if any check failed.

  tool/android_lock.py SERIAL OUTDIR APK PIN [--only 1,2,3,6,9]
"""
import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from android_ui import Device, PKG  # noqa: E402

# a place in the middle of its tenth-of-a-degree cell, so Android's blurring of an approximate
# place (about 2 km) cannot move it into the next one: expected "Near 40.3° N, 111.7° W"
GEO = (40.28, -111.68)
EXPECT = (40.3, -111.7)
TITLES = ['Before the new job', 'From Dad', 'Five blessings']

results = []


def plain(png):
    """The spread and brightness of the middle of a screenshot (0 to 1): a plain card is near 0, 0.04."""
    out = subprocess.run(['magick', png, '-alpha', 'off', '-gravity', 'center', '-crop', '40%x40%+0+0', '+repage',
                          '-colorspace', 'gray', '-format', '%[fx:standard_deviation] %[fx:mean]', 'info:'],
                         capture_output=True, text=True, timeout=30).stdout.split()
    return float(out[0]), float(out[1])


def check(name, ok, detail=''):
    results.append({'check': name, 'ok': bool(ok), 'detail': detail})
    print(f"{'PASS' if ok else 'FAIL'}  {name}  {detail}", flush=True)
    return ok


class Run:
    def __init__(self, serial, out, apk, pin):
        self.d = Device(serial)
        self.out, self.apk, self.pin = out, apk, pin
        w, h = map(int, re.findall(r'(\d+)x(\d+)', self.d.sh('wm size'))[-1])
        dens = int(re.findall(r'(\d+)', self.d.sh('wm density'))[-1]) / 160
        self.ring = (w // 2, int(h - 136 * dens))

    def shot(self, name):
        self.d.shot(os.path.join(self.out, f'{name}.png'))

    def touch(self):
        self.d.adb('emu', 'finger', 'touch', '1')
        time.sleep(0.5)
        self.d.adb('emu', 'finger', 'remove', '1')

    def labels(self):
        return [n[0] for n in self.d.nodes()]

    def blessing_shown(self):
        """Any blessing's title, the count, or a date in the accessibility tree."""
        ls = ' | '.join(self.labels())
        return [t for t in TITLES if t in ls] + re.findall(r'\b(?:January|February|March|April|May|June|July|August|'
                                                          r'September|October|November|December) \d+, \d{4}', ls)

    def prompt_up(self, seconds=8):
        try:
            self.d.wait('^Touch the fingerprint sensor|^Use PIN', seconds)
            return True
        except TimeoutError:
            return False

    def away(self, seconds):
        self.d.key('KEYCODE_HOME')
        time.sleep(seconds)
        self.d.launch()
        time.sleep(2)

    def home(self):
        self.d.wait('^New blessing', 30)

    def install(self):
        self.d.adb('uninstall', PKG, timeout=60)
        out = self.d.adb('install', self.apk, timeout=240)
        if 'Success' not in out:
            raise RuntimeError(f'install: {out}')

    # ---- 1 ----

    def rows(self):
        return {l.split('.')[0]: (l, at) for l, at, _ in self.d.nodes() if '. Optional.' in l or '. Required.' in l}

    def first_run(self, location='Only this time', lock=True):
        self.d.launch()
        self.d.tap('^Continue', 40)
        time.sleep(1.5)
        if not self.d.has('^Allow microphone'):
            self.d.tap('^Continue', 20)
        self.d.wait('^Allow microphone')
        before = {k: v[1] for k, v in self.rows().items()}
        if lock:
            self.shot('first-run-before')
            check('1: the lock row is named for the phone, never Face ID',
                  'Fingerprint or screen lock' in before and not any('Face ID' in l for l in self.labels()), str(list(before)))
            self.d.tap('^Allow fingerprint or screen lock')
            check('1: Allow puts the system prompt', self.prompt_up())
            self.shot('prompt')
            self.touch()
            self.d.wait(r'^Fingerprint or screen lock\. Optional\..*Allowed', 10)
            check('1: one fingerprint touch answers the row', True)
        geo = self.d.adb('emu', 'geo', 'fix', str(GEO[1]), str(GEO[0]))
        self.d.tap('^Allow location')
        self.d.wait('approximate location')
        check('1: Android asks for approximate location only', not self.d.has('^Precise'))
        self.d.tap(f'^{location}')
        self.d.tap('^Allow microphone')
        self.d.tap('^While using the app')
        self.d.tap('^Allow notifications')
        self.d.tap('^Allow$')
        time.sleep(1.5)
        after = {k: v[1] for k, v in self.rows().items()}
        if lock:
            self.shot('first-run-after')
        if lock:
            check('1: no row moved when answered', all(before.get(k) == after.get(k) for k in before), f'{before} -> {after}')
        self.d.tap('^Continue')
        self.home()
        check('1: through to the sky with the samples', self.d.has('Five blessings'), geo.strip())

    # ---- 2 ----

    def step2(self):
        self.away(70)
        up = self.prompt_up()
        check('2: away 70 s: locked, and the phone asks', up)
        self.shot('locked-prompt')
        if up:
            # Android 17's prompt has a Cancel button, Android 14's only "Tap to cancel": back is both
            self.d.key('KEYCODE_BACK')
            time.sleep(1.5)
        seen = self.blessing_shown()
        check('2: locked: nothing of a blessing on screen or in the accessibility tree', not seen and self.d.has('^Unlock'),
              f'found {seen}' if seen else 'labels: ' + ', '.join(self.labels()))
        self.shot('locked')
        self.d.tap('^Unlock')
        check('2: Unlock (try again) puts the prompt again', self.prompt_up())
        self.touch()
        time.sleep(2)
        check('2: a fingerprint unlocks', self.d.has('Five blessings'))
        self.away(70)
        check('2: away 70 s again: locked', self.prompt_up())
        self.d.tap('^Use PIN', 5)
        time.sleep(1.5)
        self.d.sh(f'input text {self.pin}')
        self.d.key('KEYCODE_ENTER')
        time.sleep(3)
        check('2: the PIN unlocks', self.d.has('Five blessings'))

    # ---- 3 ----

    def step3(self):
        self.away(20)
        up = self.prompt_up(4)
        check('3: away 20 s: not locked', not up and self.d.has('Five blessings'))

    # ---- 6 ----

    def recents(self, name):
        self.d.tap('^Read this blessing')
        time.sleep(2.5)
        self.shot(f'{name}-open')
        self.d.key('KEYCODE_APP_SWITCH')
        time.sleep(3)
        self.shot(name)
        ls = ' | '.join(self.labels())
        self.d.launch()
        time.sleep(2)
        return ls

    def settings_lock(self, on):
        self.d.tap('^Settings$')
        time.sleep(2)
        self.d.wait('^App lock')
        sw = [at for l, at, c in self.d.nodes() if l.startswith('App lock') and c]
        sw = sw[0] if sw else max((at for l, at, _ in self.d.nodes() if l.startswith('App lock')), key=lambda a: a[0])
        self.shot('settings-lock-on' if not on else 'settings-lock-off')
        self.d.sh(f'input tap {sw[0]} {sw[1]}')
        if not on:
            check('7: turning the lock off asks first', self.prompt_up())
            self.touch()
        time.sleep(2)
        self.d.key('KEYCODE_BACK')
        time.sleep(2)

    def step6(self):
        if self.prompt_up(2):
            self.touch()
            time.sleep(2)
        on = self.recents('recents-lock-on')
        check('6: recent apps with the lock on: no words of the blessing in the card', not any(t in on for t in TITLES), on[:200])
        sd, mean = plain(os.path.join(self.out, 'recents-lock-on.png'))
        check('6: recent apps with the lock on: the card is the plain ground colour', sd < 0.02 and mean < 0.1,
              f'middle of the card: spread {sd:.3f}, brightness {mean:.3f}')
        self.d.key('KEYCODE_BACK')
        time.sleep(2)
        self.settings_lock(on=False)
        off = self.recents('recents-lock-off')
        check('6: recent apps with the lock off: the app as it is (as iPhone with its lock off)', True, off[:200])
        self.d.key('KEYCODE_BACK')
        time.sleep(2)
        self.away(70)
        check('7: lock off, away 70 s: not locked', not self.prompt_up(4) and self.d.has('Five blessings'))
        self.settings_lock(on=True)

    # ---- the two ways the lock failed open (security review of 1c0f4cb) ----

    def unlock_if_asked(self, seconds=4):
        if self.prompt_up(seconds):
            self.touch()
            time.sleep(2)

    def stepp(self):
        """Home with Android's location question up (from Settings), recent apps, away 70 s, back: locked."""
        self.unlock_if_asked(2)
        self.d.sh(f'pm revoke {PKG} android.permission.ACCESS_COARSE_LOCATION')  # Android ends the app for this
        try:
            time.sleep(2)
            self.d.launch()
            self.unlock_if_asked(10)
            self.home()
            self.d.tap('^Settings$')
            time.sleep(2)
            for _ in range(4):
                if self.d.has('^Use my location'):
                    break
                self.d.sh('input swipe 640 2200 640 900 300')
                time.sleep(1)
            self.use_my_location()
            asked = True
            try:
                self.d.wait('^While using the app|^Only this time|^Don.t allow', 15)
            except TimeoutError:
                asked = False
            check('p: Android\'s location question is up over Settings', asked)
            self.shot('perm-question')
            self.d.key('KEYCODE_HOME')
            time.sleep(2)
            self.d.key('KEYCODE_APP_SWITCH')
            time.sleep(3)
            self.shot('perm-recents')
            sd, mean = plain(os.path.join(self.out, 'perm-recents.png'))
            # Not the plain card: the question is the permission controller's own activity on top of
            # the app's task, and Android takes its picture (docs/android-plan.md section 5, "Not met").
            # What must hold is that nothing of a blessing is in it.
            seen = [t for t in TITLES if t in ' | '.join(self.labels())]
            check('p: left over the question: recent apps holds nothing of a blessing (Android\'s question over Settings)',
                  not seen, f'found {seen}; middle of the card: spread {sd:.3f}, brightness {mean:.3f} (plain card: under 0.02)')
            self.d.key('KEYCODE_HOME')
            time.sleep(68)
            self.d.launch()
            time.sleep(2.5)
            self.shot('perm-back')
            # the question may still be over the app; answering it must not open the app either
            answered = False
            if self.d.has('^Only this time'):
                self.d.tap('^Only this time')
                answered = True
            up = self.prompt_up(8)
            if answered:
                check('p: once the question is answered, the unlock prompt opens by itself (no tap on Unlock)', up)
            if up:
                self.d.key('KEYCODE_BACK')
                time.sleep(1.5)
            seen = self.blessing_shown()
            check('p: away 70 s from the question: locked, nothing of a blessing showing',
                  up and not seen and self.d.has('^Unlock'), f'prompt {up}, shown {seen}, screen {self.labels()[:6]}')
            self.shot('perm-locked')
            self.d.tap('^Unlock')
            if self.prompt_up():
                self.touch()
            time.sleep(2)
        finally:
            self.d.sh(f'pm grant {PKG} android.permission.ACCESS_COARSE_LOCATION')  # ends the app again
            time.sleep(2)
            self.d.launch()
            self.unlock_if_asked(10)
        self.home()

    def steps(self):
        """Dart slow to answer after 70 s away (debug hook: `active` held back 10 s): the cover holds."""
        self.unlock_if_asked(2)
        self.home()
        self.d.tap('^Read this blessing')
        time.sleep(2.5)
        self.d.sh(f"run-as {PKG} sh -c 'echo 10000 > files/slow_active'")
        try:
            self.d.key('KEYCODE_HOME')
            time.sleep(70)
            self.d.launch()
            time.sleep(3)  # past the old 1.5 s lift, before Dart has been told
            self.shot('slow-3s')
            sd, mean = plain(os.path.join(self.out, 'slow-3s.png'))
            check('s: Dart not yet answered 3 s after a 70 s absence: still the plain cover', sd < 0.02 and mean < 0.1,
                  f'middle of the screen: spread {sd:.3f}, brightness {mean:.3f}')
            # the shade pulled down and closed before Dart answers: the focus return sends a second
            # `active` (away 0), whose own 1.5 s limit must not lift the cover the first still holds
            self.d.sh('cmd statusbar expand-notifications')
            time.sleep(0.8)
            self.d.sh('cmd statusbar collapse')
            time.sleep(2)  # the second call's 1.5 s gone; the first answer is still held back
            self.shot('slow-after-shade')
            sd, mean = plain(os.path.join(self.out, 'slow-after-shade.png'))
            check('s: the shade opened and closed while the answer is held back: still the plain cover', sd < 0.02 and mean < 0.1,
                  f'middle of the screen: spread {sd:.3f}, brightness {mean:.3f}')
            up = self.prompt_up(12)
            check('s: the late answer locks, and its prompt shows', up)
        finally:
            self.d.sh(f'run-as {PKG} rm -f files/slow_active')
        if up:
            self.touch()
            time.sleep(2.5)
        check('s: unlocked after the late answer: the cover is gone', bool(self.blessing_shown()), str(self.blessing_shown()))
        self.d.key('KEYCODE_BACK')
        time.sleep(2)

    # ---- 9 ----

    def places(self):
        tmp = tempfile.mkdtemp()
        base = 'app_flutter/blessings.sqlite'
        for ext in ['', '-wal', '-shm']:
            data = self.d.adb('exec-out', 'run-as', PKG, 'cat', base + ext, binary=True)
            with open(os.path.join(tmp, 'b.sqlite' + ext), 'wb') as f:
                f.write(data)
        con = sqlite3.connect(os.path.join(tmp, 'b.sqlite'))
        rows = con.execute('select id, latitude, longitude, created_at_ms from blessings order by created_at_ms').fetchall()
        con.close()
        return rows

    def record(self):
        """New blessing, Begin (timed from the tap to the recording starting), 12 s, Amen."""
        self.d.tap('^New blessing', 30)
        x, y = self.d.wait('^Begin', 15)
        self.d.adb('logcat', '-c')
        t = time.monotonic()
        self.d.sh(f'input tap {x} {y}')
        started = None
        while time.monotonic() - t < 10:
            if 'recording: started' in self.d.adb('logcat', '-d', '-s', 'speech:I'):
                started = time.monotonic() - t
                break
            time.sleep(0.2)
        time.sleep(12)
        x, y = self.ring
        self.d.sh(f'input swipe {x} {y} {x} {y} 2500', timeout=30)
        time.sleep(4)
        for label in ['^Save for later', '^Later', '^Done', '^Keep']:
            if self.d.has(label):
                self.d.tap(label)
                break
        time.sleep(2)
        return started

    def settings_place(self):
        self.d.tap('^Settings$')
        time.sleep(2)
        for _ in range(4):
            got = [l for l in self.labels() if l.startswith('Near ')]
            if got:
                break
            self.d.sh('input swipe 640 2200 640 900 300')
            time.sleep(1)
        return got[0] if got else None

    def use_my_location(self):
        at = self.d.wait('^Use my location')
        t = time.monotonic()
        self.d.sh(f'input tap {at[0]} {at[1]}')
        return t

    def step9(self, summary):
        # after steps p and s the app may have been ended (a permission reset) or left: bring it back
        if not self.d.has('^New blessing'):
            self.d.launch()
            self.unlock_if_asked(6)
        self.home()
        before = {r[0] for r in self.places()}
        begin = self.record()
        check('9: Begin is not held up by location', begin is not None and begin < 3, f'{begin:.2f} s' if begin else 'never started')
        new = [r for r in self.places() if r[0] not in before]
        got = (new[-1][1], new[-1][2]) if new else None
        check('9: the blessing recorded after "Only this time" carries the place, rounded', got == EXPECT, f'{got}, geo fix {GEO}')
        summary['place'] = got
        # refused, on a fresh install
        self.install()
        t = time.monotonic()
        self.first_run(location="Don’t allow", lock=False)
        place = self.settings_place()
        check('9: refused: Settings names the Salt Lake Temple', place == 'Near Salt Lake Temple', str(place))
        self.shot('settings-location-refused')
        # location off for the whole phone, allowed for the app
        self.d.sh('cmd location set-location-enabled false')
        self.d.sh(f'pm grant {PKG} android.permission.ACCESS_COARSE_LOCATION')
        self.d.adb('logcat', '-c')
        t = self.use_my_location()
        # Android 17 sometimes puts its own "No location access ... Turn on location" over the app:
        # closed if it does. The app's own time is from its log (LocationChannel's "located")
        system = False
        while time.monotonic() - t < 10:
            if self.d.has('^No location access'):
                system = True
                self.shot('location-off-system-dialog')
                self.d.tap('^Close')
            elif self.d.has('^Use my location'):
                break
        waited = time.monotonic() - t
        place = [l for l in self.labels() if l.startswith('Near ')]
        place = place[0] if place else None
        ms = re.findall(r'located: (.*) in (\d+) ms', self.d.adb('logcat', '-d', '-s', 'location:I'))
        answer = int(ms[-1][1]) if ms else None
        summary['location off'] = {'system dialog': system, 'app answered ms': answer, 'screen read seconds': round(waited, 2)}
        check('9: location off for the phone: answered at once, still the Salt Lake Temple',
              place == 'Near Salt Lake Temple' and answer is not None and answer < 1000,
              f'{place}; the app answered "{ms[-1][0] if ms else "?"}" in {answer} ms; the screen read back after {waited:.2f} s')
        self.d.key('KEYCODE_BACK')
        time.sleep(2)
        if not self.d.has('^New blessing'):
            self.d.tap('^Back to the sky')
            time.sleep(2)
        begin = self.record()
        new = self.places()
        check('9: location off: Begin is not held up; the blessing has the Salt Lake Temple',
              begin is not None and begin < 3 and new and (round(new[-1][1], 4), round(new[-1][2], 4)) == (40.7704, -111.8919),
              f'Begin {begin}, {new[-1][1:3] if new else None}')
        self.d.sh('cmd location set-location-enabled true')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('serial')
    p.add_argument('out')
    p.add_argument('apk')
    p.add_argument('pin')
    p.add_argument('--only', default='1,2,3,6,p,s,9')
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    r = Run(a.serial, a.out, a.apk, a.pin)
    steps = a.only.split(',')
    summary = {'device': a.serial}
    r.first_run()
    for s in ['2', '3', '6', 'p', 's', '9']:
        if s not in steps:
            continue
        try:
            if s == '9':
                r.step9(summary)
            else:
                getattr(r, f'step{s}')()
        except Exception as e:  # one step's failure must not hide the others
            check(f'{s}: ran to the end', False, repr(e)[:400])
            r.shot(f'failed-step{s}')
            try:
                r.d.launch()
                if r.prompt_up(4):
                    r.touch()
            except Exception:
                pass
    summary['checks'] = results
    with open(os.path.join(a.out, 'summary.json'), 'w') as f:
        json.dump(summary, f, indent=1)
    failed = [x for x in results if not x['ok']]
    print(f'== {len(results) - len(failed)} of {len(results)} checks passed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
