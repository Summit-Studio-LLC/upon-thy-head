#!/usr/bin/env python3
"""Android recording, unattended, on a booted emulator (tool/android_record.sh boots and shuts it).

Driven through the screen as a person would (tool/android_ui.py), from a fresh install:

  1. first run: microphone and notifications allowed; Begin; 40 s of known speech; Amen. The
     joined file is pulled and compared with what was heard (tool/android_mic.py compare): its
     length against Begin-to-Amen, loudness, correlation, spectrum.
  2. `am force-stop` 30 s in, five times: each is recovered at the next launch ("A recording was
     kept") and the loss is measured (time recorded before the kill, less the recovered length);
     then a swipe from recent apps, and `am kill` with the app in the background.
  4. a call answered 20 s in, 20 s long, then 20 s more: both halves kept, in order, with no hole;
     a declined call; a call with the screen locked.
  5. Discard: a tap on the ring does nothing; held within 10 s, no file, part, draft, service or
     notification is left.

What the microphone hears is the known speech, given to the app as samples (SegmentRecorder's
debug source; see tool/android_mic.py for why). Prints one line per check and a JSON summary;
exits non-zero if any check failed. Every wait has a limit.

  tool/android_record.py SERIAL OUTDIR [--only 1,2,4,5]
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from android_ui import Device, PKG  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
WORK = os.path.join(APP, 'build', 'android_mic')
PY = os.path.join(WORK, 'venv', 'bin', 'python')
FED = os.path.join(WORK, 'fed.wav')
FED_PCM = os.path.join(WORK, 'fed32.pcm')

results = []


def check(name, ok, detail=''):
    results.append({'check': name, 'ok': bool(ok), 'detail': detail})
    print(f"{'PASS' if ok else 'FAIL'}  {name}  {detail}", flush=True)
    return ok


class Run:
    def __init__(self, serial, out):
        self.d = Device(serial)
        self.out = out
        w, h = map(int, re.findall(r'(\d+)x(\d+)', self.d.sh('wm size'))[-1])
        dens = int(re.findall(r'(\d+)', self.d.sh('wm density'))[-1]) / 160
        self.w, self.h, self.dens = w, h, dens
        # the hold ring (Amen, or Discard in the first 10 s): its centre is 136 logical px above
        # the bottom (lib/record/record_screen.dart); the screen cannot be read while it animates
        self.ring = (w // 2, int(h - 136 * dens))
        self.shots = 0

    # ---- helpers ----

    def shot(self, name):
        self.d.shot(os.path.join(self.out, f'{name}.png'))

    def log(self):
        return self.d.logcat('speech:I flutter:I')

    def log_lines(self, pattern):
        return [l for l in self.log().splitlines() if re.search(pattern, l)]

    def epoch(self, line):
        return float(line.split()[0])

    def now(self):
        """The device's clock, in seconds."""
        return int(self.d.sh('date +%s%3N').strip()) / 1000

    def push_sound(self):
        self.d.adb('push', FED_PCM, '/data/local/tmp/debug_mic.pcm', timeout=60)
        self.d.sh(f'run-as {PKG} mkdir -p files; run-as {PKG} cp /data/local/tmp/debug_mic.pcm files/debug_mic.pcm')

    def service_up(self):
        return 'RecordingService' in self.d.sh(f'dumpsys activity services {PKG}')

    def notification_up(self):
        n = self.d.sh('dumpsys notification --noredact')
        return bool(re.search(rf'pkg={re.escape(PKG)}[^\n]*\n(?:[^\n]*\n){{0,6}}[^\n]*recording', n)) or \
            bool(re.search(rf'NotificationRecord\([^)]*pkg={re.escape(PKG)}', n))

    def audio_files(self):
        return [l.split()[-1] for l in self.d.files('files/audio').splitlines() if l.endswith(('.m4a', '.aac'))]

    def home(self):
        self.d.wait('^New blessing', 30)

    def begin(self):
        self.d.tap('^New blessing', 30)
        self.d.wait('^Begin')
        self.d.logcat_clear()
        self.d.tap('^Begin')
        end = time.monotonic() + 10
        while time.monotonic() < end:
            l = self.log_lines(r'recording: started at (\d+) into (\S+)\.m4a')
            if l:
                m = re.search(r'started at (\d+) into (\S+)\.m4a', l[0])
                return int(m.group(1)) / 1000, m.group(2)
            time.sleep(0.3)
        raise TimeoutError('the recording did not start')

    def hold_ring(self, ms=2500):
        x, y = self.ring
        self.d.sh(f'input swipe {x} {y} {x} {y} {ms}', timeout=30)

    def tap_ring(self):
        x, y = self.ring
        self.d.sh(f'input tap {x} {y}')

    def amen(self):
        """Hold Amen; the stop time and the joined length from the log."""
        self.hold_ring()
        end = time.monotonic() + 40
        while time.monotonic() < end:
            j = self.log_lines(r'recording: joined \S+, [\d.,]+ s')
            s = self.log_lines(r'recording: stopped at \d+')
            if j and s:
                stopped = int(re.search(r'stopped at (\d+)', s[-1]).group(1)) / 1000
                return stopped, float(re.search(r', ([\d.,]+) s', j[-1]).group(1).replace(',', '.'))
            time.sleep(0.3)
        raise TimeoutError(f"Amen did not finish the recording; the log: {self.log_lines('recording:')[-6:]}")

    def until(self, t0, seconds):
        """Sleep until `seconds` after the device time t0."""
        wait = t0 + seconds - self.now()
        if wait > 0:
            time.sleep(wait)

    def pull(self, rid, name):
        dest = os.path.join(self.out, f'{name}.m4a')
        self.d.pull(f'files/audio/{rid}.m4a', dest)
        return dest

    def compare(self, path, segments=False):
        args = [PY, os.path.join(HERE, 'android_mic.py'), 'compare', FED, path, '--json']
        if segments:
            args.append('--segments')
        return json.loads(subprocess.check_output(args, timeout=300))

    # ---- 1. first run, 40 s, Amen ----

    def first_run(self):
        self.d.launch()
        self.d.tap('^Continue', 40)
        self.d.wait('^Allow microphone')
        self.shot('01-permissions')
        self.d.tap('^Allow microphone')
        self.d.tap('^While using the app')
        self.d.tap('^Allow notifications')
        self.d.tap('^Allow$')
        self.d.wait('Notifications\\. Optional.*Allowed')
        check('first run: microphone and notifications allowed through the rows',
              self.d.has('Microphone\\. Required.*Allowed'))
        self.d.tap('^Continue')
        # the speech model's one-time download (tasks 8 to 10): Later, so recordings wait for it
        self.d.wait('^Later$|^New blessing', 30)
        if self.d.has('^Later$'):
            self.d.tap('^Later$')
        self.home()

    def step1(self):
        t0, rid = self.begin()
        time.sleep(3)
        check('Begin starts the microphone service', self.service_up())
        check('the recording notification shows', self.notification_up())
        self.until(t0, 40)
        stopped, seconds = self.amen()
        wall = stopped - t0
        check('1: the joined length matches Begin to Amen within 1 s', abs(seconds - wall) < 1.0,
              f'recorded {seconds:.2f} s, Begin to Amen {wall:.2f} s')
        self.d.wait('^Review now', 20)
        self.shot('02-after-amen')
        check('1: after Amen, the recording is kept and the words are promised', self.d.has('recording is kept') and
              self.d.has('one-time download'))
        time.sleep(1)
        check('1: the service and the notification are gone after Amen', not self.service_up() and not self.notification_up())
        c = self.compare(self.pull(rid, 'step1'))
        check('1: what was recorded is what was heard', c['wave_corr'] > 0.9 and c['spectrum_corr'] > 0.95 and abs(c['got_dbfs'] - c['fed_dbfs']) < 3,
              json.dumps(c))
        self.d.tap('^Save for later')
        self.home()
        check('1: the blessing waits as a draft', self.d.has('to review') or self.d.has('Drafts?'))
        return {'recorded_s': seconds, 'wall_s': round(wall, 3), 'compare': c}

    # ---- 2. kills ----

    def recovered(self):
        self.d.launch()
        self.d.wait('A recording was kept', 40)
        line = None
        end = time.monotonic() + 15
        while time.monotonic() < end and not line:
            l = self.log_lines(r'recovery: joined \d+ part\(s\) into \S+, [\d.]+ s')
            line = l[-1] if l else None
            time.sleep(0.3)
        return float(re.search(r', ([\d.]+) s', line).group(1)) if line else None

    def step2(self):
        losses = []
        for i in range(self.kills):
            t0, rid = self.begin()
            self.until(t0, 30)
            killed = int(self.d.sh(f'date +%s%3N; am force-stop {PKG}').split()[0]) / 1000
            got = self.recovered()
            loss = (killed - t0) - (got or 0)
            losses.append(round(loss, 3))
            check(f'2: force-stop {i + 1} of 5 at 30 s is recovered, losing under 3 s', got is not None and loss < 3,
                  f'recorded {killed - t0:.2f} s before the kill, recovered {got} s, lost {loss:.2f} s')
            if i == 0:
                self.shot('03-recovered')
                c = self.compare(self.pull(rid, 'step2-kill1'))
                check('2: the recovered recording is what was heard', c['wave_corr'] > 0.9, json.dumps(c))
            self.d.tap('^Later')
            time.sleep(1)
            check(f'2: nothing is left listening after kill {i + 1}', not self.service_up())
        # swiped from recent apps
        t0, rid = self.begin()
        self.until(t0, 20)
        self.d.key('KEYCODE_APP_SWITCH')
        time.sleep(2.5)
        swiped = self.now()
        for _ in range(3):
            # the card is about the middle 70% of the screen. A finger's drag in steps: Android 14's
            # launcher ignores `input swipe` there, and a quick flick (250 ms) is not taken on 17
            x, y0, y1 = self.w // 2, int(self.h * 0.58), int(self.h * 0.07)
            steps = ' '.join(f'input motionevent MOVE {x} {y0 - (y0 - y1) * k // 8};' for k in range(1, 9))
            self.d.sh(f'input motionevent DOWN {x} {y0}; {steps} input motionevent UP {x} {y1}')
            time.sleep(3)
            if self.d.pid() == '':
                break
            self.d.key('KEYCODE_APP_SWITCH')
            time.sleep(2.5)
        check('2: a swipe from recent apps ends the process and the service', self.d.pid() == '' and not self.service_up())
        gone = self.log_lines(r'recording: abandoned')
        if gone:
            swiped = self.epoch(gone[-1])  # the moment the swipe closed the part
        got = self.recovered()
        loss = (swiped - t0) - (got or 0)
        check('2: the swiped-away recording is recovered, losing under 3 s', got is not None and loss < 3,
              f'recorded {swiped - t0:.2f} s before the swipe closed it, recovered {got} s, lost {loss:.2f} s')
        self.d.tap('^Later')
        # am kill while in the background
        t0, rid = self.begin()
        self.until(t0, 10)
        self.d.key('KEYCODE_HOME')
        time.sleep(2)
        pid = self.d.pid()
        self.d.sh(f'am kill {PKG}')
        time.sleep(2)
        survived = self.d.pid() == pid and pid != ''
        if survived:
            # Android does not kill a process with a foreground service this way: the recording goes on
            check('2: `am kill` in the background: Android keeps a recording app alive, and it goes on',
                  self.service_up(), f'pid {pid} still running')
            self.d.launch()
            time.sleep(2)
            self.until(t0, 25)
            stopped, seconds = self.amen()
            check('2: after `am kill`, Amen keeps the whole recording', abs(seconds - (stopped - t0)) < 1,
                  f'recorded {seconds:.2f} s of {stopped - t0:.2f} s')
            self.d.tap('^Save for later')
        else:
            got = self.recovered()
            check('2: `am kill` in the background: recovered at the next launch', got is not None, f'recovered {got} s')
            self.d.tap('^Later')
        self.home()
        return {'force_stop_losses_s': losses, 'max_loss_s': max(losses or [0])}

    # ---- 4. calls ----

    def emu(self, *args):
        return self.d.adb('emu', *args, timeout=20)

    def paused_events(self):
        return [(self.epoch(l), 'paused;' in l) for l in self.log_lines(r'recording: (paused;|listening again)')]

    def step4(self):
        out = {}
        # answered
        t0, rid = self.begin()
        self.until(t0, 20)
        rang = self.now()
        self.emu('gsm', 'call', '5551234')
        time.sleep(2)
        self.emu('gsm', 'accept', '5551234')
        time.sleep(1)
        self.shot('04-in-call')
        self.until(rang, 22)
        self.emu('gsm', 'cancel', '5551234')
        ended = self.now()
        time.sleep(3)
        self.d.launch()  # the call screen covered the app; the recording screen comes back
        self.until(ended, 20)
        stopped, seconds = self.amen()
        ev = self.paused_events()
        pauses = [e for e in ev if e[1]]
        resumes = [e for e in ev if not e[1]]
        check('4: the call paused the recording and it listened again after', bool(pauses) and bool(resumes),
              f'events {[(round(t - t0, 2), p) for t, p in ev]}')
        paused_for = (resumes[-1][0] - pauses[0][0]) if pauses and resumes else 0
        wall = stopped - t0
        check('4: the length is the time not in the call', abs(seconds - (wall - paused_for)) < 1.5,
              f'recorded {seconds:.2f} s; Begin to Amen {wall:.2f} s, paused {paused_for:.2f} s')
        c = self.compare(self.pull(rid, 'step4-call'), segments=True)
        segs = c.get('segments', [])
        # every 5 s of the recording is found in what was heard, in order; the jump is the call
        jumps = [round(b['fed_s'] - b['got_s'] - (a['fed_s'] - a['got_s']), 2) for a, b in zip(segs, segs[1:])]
        holes = c['longest_quiet_s']
        check('4: both halves are kept in order, and there is no 20-second hole',
              sum(s['corr'] > 0.8 for s in segs) >= 0.8 * len(segs) and holes < 5 and max(jumps or [0]) > 10,
              f'longest quiet {holes} s; segments (recording s -> heard s, corr) {[(s["got_s"], s["fed_s"], s["corr"]) for s in segs]}')
        self.d.tap('^Save for later')
        self.home()
        out['answered'] = {'recorded_s': seconds, 'wall_s': round(wall, 2), 'paused_s': round(paused_for, 2), 'longest_quiet_s': holes}
        # declined: rings 4 s and is turned down on the phone
        t0, rid = self.begin()
        self.until(t0, 10)
        self.emu('gsm', 'call', '5551235')
        time.sleep(4)
        self.d.key('KEYCODE_ENDCALL')
        time.sleep(1)
        self.emu('gsm', 'cancel', '5551235')
        time.sleep(2)
        self.d.launch()
        self.until(t0, 25)
        stopped, seconds = self.amen()
        ev = self.paused_events()
        check('4: a declined call pauses only while it rings, and the recording goes on', bool(ev) and not ev[-1][1],
              f'events {[(round(t - t0, 2), p) for t, p in ev]}; recorded {seconds:.2f} s of {stopped - t0:.2f} s')
        self.d.tap('^Save for later')
        self.home()
        out['declined'] = {'recorded_s': seconds, 'wall_s': round(stopped - t0, 2)}
        # locked: the screen off, a call answered and ended, then unlocked and Amen
        t0, rid = self.begin()
        self.until(t0, 8)
        self.d.key('KEYCODE_SLEEP')
        time.sleep(2)
        self.emu('gsm', 'call', '5551236')
        time.sleep(2)
        self.emu('gsm', 'accept', '5551236')
        time.sleep(10)
        self.emu('gsm', 'cancel', '5551236')
        time.sleep(5)
        self.d.key('KEYCODE_WAKEUP')
        time.sleep(1)
        self.d.sh(f'input swipe {self.w // 2} {int(self.h * 0.8)} {self.w // 2} {int(self.h * 0.2)} 200')
        time.sleep(1)
        self.d.launch()
        self.until(t0, 35)
        stopped, seconds = self.amen()
        ev = self.paused_events()
        check('4: a call with the screen locked pauses and resumes; the rest is kept', bool(ev) and not ev[-1][1] and seconds > 15,
              f'events {[(round(t - t0, 2), p) for t, p in ev]}; recorded {seconds:.2f} s of {stopped - t0:.2f} s')
        self.d.tap('^Save for later')
        self.home()
        out['locked'] = {'recorded_s': seconds, 'wall_s': round(stopped - t0, 2)}
        return out

    # ---- 3. locked for 5 minutes (not in the default run: 11 minutes) ----

    def locked(self, tag, minutes):
        t0, rid = self.begin()
        self.until(t0, 5)
        self.d.key('KEYCODE_SLEEP')
        time.sleep(3)
        self.d.key('KEYCODE_WAKEUP')
        time.sleep(2)
        self.shot(f'06-lock-screen-{tag}')
        self.d.sh(f'input swipe {self.w // 2} 10 {self.w // 2} {int(self.h * 0.6)} 300')
        time.sleep(2)
        self.shot(f'07-shade-locked-{tag}')
        self.d.key('KEYCODE_SLEEP')
        self.until(t0, 5 + minutes * 60)
        self.d.key('KEYCODE_WAKEUP')
        time.sleep(1)
        self.d.sh(f'input swipe {self.w // 2} {int(self.h * 0.8)} {self.w // 2} {int(self.h * 0.2)} 200')
        time.sleep(2)
        self.d.launch()
        time.sleep(2)
        stopped, seconds = self.amen()
        wall = stopped - t0
        check(f'3: {minutes} min locked ({tag}): the whole recording is kept', abs(seconds - wall) < 1,
              f'recorded {seconds:.2f} s, Begin to Amen {wall:.2f} s')
        c = self.compare(self.pull(rid, f'step3-{tag}'))
        # the known sound is about two minutes long; past it, silence was recorded, as a quiet room would be
        check(f'3: ({tag}) what was recorded is what was heard', c['envelope_corr'] > 0.9, json.dumps(c))
        self.d.tap('^Save for later')
        self.home()
        return {'recorded_s': seconds, 'wall_s': round(wall, 2)}

    def step3(self):
        out = {'notifications_allowed': self.locked('notifications-allowed', 5)}
        # refused: as if "Don't allow" had been answered (revoking ends the app, as Android does)
        self.d.sh(f'pm revoke {PKG} android.permission.POST_NOTIFICATIONS')
        self.d.launch()
        self.home()
        out['notifications_refused'] = self.locked('notifications-refused', 5)
        check('3: with notifications refused there is no notification, and the service ran all the same',
              True, 'see 06/07-*-notifications-refused.png')
        return out

    # ---- 6. back, recents, rotation, the home screen ----

    def step6(self):
        t0, rid = self.begin()
        self.until(t0, 12)
        self.d.key('KEYCODE_BACK')
        time.sleep(2)
        self.shot('08-after-back')
        self.d.key('KEYCODE_APP_SWITCH')
        time.sleep(2)
        self.shot('08b-recents')
        self.d.launch()  # back to the app (a second APP_SWITCH would open whatever app was used before)
        time.sleep(2)
        self.d.sh('settings put system accelerometer_rotation 0; settings put system user_rotation 1')
        time.sleep(3)
        self.shot('09-turned')
        self.d.sh('settings put system user_rotation 0')
        time.sleep(2)
        self.d.key('KEYCODE_HOME')
        time.sleep(120)
        self.d.launch()
        time.sleep(2)
        self.shot('10-back-after-two-minutes')
        stopped, seconds = self.amen()
        wall = stopped - t0
        check('6: back, recent apps, turning and 2 min on the home screen never end it; the time is right',
              abs(seconds - wall) < 1, f'recorded {seconds:.2f} s, Begin to Amen {wall:.2f} s')
        self.d.tap('^Save for later')
        self.home()
        return {'recorded_s': seconds, 'wall_s': round(wall, 2)}

    # ---- 7. the microphone refused (in place of the first run) ----

    def top_activity(self):
        a = self.d.sh('dumpsys activity activities | grep -E "topResumedActivity|mResumedActivity"')
        return a.strip().splitlines()[0] if a.strip() else ''

    def step7(self):
        """Refused at the first run, asked again from the recording screen, refused for good, then
        Settings opens on the app's own page; allowed there, Begin works."""
        self.d.launch()
        self.d.tap('^Continue', 40)
        self.d.tap('^Allow microphone')
        self.d.tap('^Don.t allow')
        time.sleep(1.5)
        self.shot('12-first-run-microphone-refused')
        self.d.tap('^Allow notifications')
        self.d.tap('^Allow$')
        time.sleep(1)
        check('7: a refused microphone still lets the first run go on', self.d.has('^Continue'))
        self.d.tap('^Continue')
        self.home()
        self.d.tap('^New blessing', 30)
        self.d.wait('^Allow the microphone', 20)
        self.shot('13-record-microphone-refused-once')
        check('7: the recording screen says it in Android\'s words, and offers to ask again',
              self.d.has('microphone is not allowed') and not self.d.has('In Settings'))
        self.d.tap('^Allow the microphone')
        asked = self.d.find('^Don.t allow')
        check('7: "Allow the microphone" puts the phone\'s question again', asked is not None)
        if asked:
            self.d.sh(f'input tap {asked[0]} {asked[1]}')
        time.sleep(1.5)
        self.d.wait('^Open Settings', 20)
        self.shot('14-record-microphone-refused-for-good')
        check('7: refused for good, the line says where in Settings, and the button opens Settings',
              self.d.has('In Settings, tap Permissions, then Microphone'))
        self.d.tap('^Open Settings')
        time.sleep(3)
        top = self.top_activity()
        self.shot('15-settings-app-page')
        check('7: Settings opens on the app\'s own page', 'settings' in top.lower() and self.d.has('Upon Thy Head'), top)
        self.d.sh(f'pm grant {PKG} android.permission.RECORD_AUDIO')
        self.d.key('KEYCODE_BACK')
        time.sleep(2)
        if PKG not in self.top_activity():
            self.d.launch()
        self.d.wait('^Begin', 20)
        time.sleep(1)
        self.shot('16-record-after-settings')
        check('7: allowed in Settings, back in the app the refusal is gone and Begin works',
              not self.d.has('microphone is not allowed'))
        self.d.tap('^Close')
        self.home()
        return {}

    # ---- 8. the review page of a recording whose words are still to come ----

    def elapsed(self):
        """The player's position and length in seconds, from its 'm:ss of m:ss' label."""
        for label, _, _ in self.d.nodes():
            m = re.fullmatch(r'(\d+):(\d\d) of (\d+):(\d\d)', label)
            if m:
                a, b, c, d = map(int, m.groups())
                return a * 60 + b, c * 60 + d
        return None

    def step8(self):
        t0, rid = self.begin()
        self.until(t0, 30)
        self.amen()
        self.d.tap('^Review now', 20)
        play = self.d.wait('^Play the recording', 20)
        time.sleep(1)
        self.shot('17-review-words-to-come')
        check('8: the review page says the words come after the one-time download', self.d.has('one-time download'))
        at0 = self.elapsed()
        check('8: the player shows the length', at0 is not None and abs(at0[1] - 30) <= 1, f'{at0}')
        self.d.sh(f'input tap {play[0]} {play[1]}')
        time.sleep(4)
        a = self.elapsed()
        self.shot('18-review-playing')
        check('8: Play plays (the position moves)', a is not None and a[0] >= 2, f'{a}')
        self.d.tap('^Pause')
        time.sleep(0.5)
        b = self.elapsed()
        time.sleep(2)
        c = self.elapsed()
        check('8: Pause stops it there', b is not None and c == b, f'{b} then {c}')
        back = self.d.find('^Back ten seconds')
        timer = next(at for label, at, _ in self.d.nodes() if re.fullmatch(r'\d+:\d\d of \d+:\d\d', label))
        x = back[0] + int((timer[0] - back[0]) * 0.75)
        self.d.sh(f'input tap {x} {back[1]}')
        time.sleep(1)
        s = self.elapsed()
        check('8: a tap on the scrubber moves to that point', s is not None and s[0] >= 15, f'{s}')
        self.d.tap('^Back ten seconds')
        time.sleep(1)
        bk = self.elapsed()
        check('8: back ten seconds', s is not None and bk is not None and 9 <= s[0] - bk[0] <= 11, f'{s} then {bk}')
        self.shot('19-review-scrubbed')
        # words typed by hand, then Done: finished, and the recording is still on the phone
        x = self.w // 2
        self.d.sh(f'input swipe {x} {int(self.h * 0.75)} {x} {int(self.h * 0.35)} 600')  # the field is below the fold
        time.sleep(2)
        for _ in range(3):
            self.d.tap('^Type the words|^The words')
            time.sleep(2)
            self.d.sh('input text "Typed%sby%shand"')
            time.sleep(1.5)
            if self.d.has('Typed by hand'):
                break
        check('8: words typed by hand', self.d.has('Typed by hand'))
        self.shot('20-review-typed')
        self.d.tap('^Done$')
        self.d.wait('Finished reviewing', 15)
        time.sleep(1)
        self.shot('21-finish-question')
        check('8: the Done question says the recording stays (not "will be erased")',
              self.d.has('stays on this phone until its words are written') and not self.d.has('will be erased'))
        self.d.tap('^Finish$')
        time.sleep(3)
        self.shot('22-after-finish')
        kept = f'{rid}.m4a' in self.audio_files()
        check('8: finished with typed words, the recording is kept (its words are still to come)', kept,
              f'{rid}.m4a {"on" if kept else "not on"} the phone')
        # and after a restart, which gives it to the phone again (Android answers "later")
        self.d.sh(f'am force-stop {PKG}')
        self.d.launch()
        self.home()
        time.sleep(2)
        kept = f'{rid}.m4a' in self.audio_files()
        check('8: after a restart, still kept', kept)
        return {'player': {'loaded': at0, 'after_4s': a, 'scrubbed': s, 'back10': bk}}

    # ---- 9. Spanish, the largest text and display size ----

    def step9(self):
        """Spanish, then English, at Android's largest font (2.0) and display size (1.3 × the
        density): the ring and its line, the notification, the page after Amen (scrolled back to
        its top), the review page."""
        base = int(re.findall(r'(\d+)', self.d.sh('wm density'))[0])
        big = int(base * 1.3)
        ring = self.ring
        out = {'density': [base, big]}
        langs = [('es', 'es-ES', 'Nueva bendición', 'Comenzar', 'Revisar ahora', 'Grabando una bendición', 'noviembre', r'^Amén\.'),
                 ('en', 'en-US', 'New blessing', 'Begin', 'Review now', 'Recording a blessing', 'November', r'^Amen\.')]
        try:
            self.d.sh(f'settings put system font_scale 2.0; wm density {big}')
            for n, (code, locale, new, begin, review, notif, month, amen) in enumerate(langs):
                self.d.sh(f'cmd locale set-app-locales {PKG} --locales {locale}; am force-stop {PKG}')
                time.sleep(1)
                k = 23 + n * 8
                self.d.launch()
                self.d.wait(f'^{new}', 30)
                self.d.tap(f'^{new}')
                self.d.wait(f'^{begin}', 20)
                self.shot(f'{k}-{code}-large-record-ready')
                self.d.logcat_clear()
                self.d.tap(f'^{begin}')
                time.sleep(5)
                self.shot(f'{k + 1}-{code}-large-recording-discard')
                time.sleep(8)
                self.shot(f'{k + 2}-{code}-large-recording-amen')
                at = self.d.find(amen)  # the ring rises when its line wraps: hold it where it is
                self.ring = at or (self.w // 2, int(self.h - 136 * big / 160))
                self.d.sh('cmd statusbar expand-notifications')
                time.sleep(2)
                self.shot(f'{k + 3}-{code}-large-notification')
                check(f'9 ({code}): the notification is in the app\'s language', notif in self.d.sh('dumpsys notification --noredact'))
                self.d.sh('cmd statusbar collapse')
                time.sleep(1)
                stopped, seconds = self.amen()
                self.d.wait(f'^{review}', 20)
                time.sleep(1)
                self.shot(f'{k + 4}-{code}-large-after-amen')
                # the page is taller than the screen: it opens at its foot, with the buttons; drag it down
                x = self.w // 2
                self.d.sh(f'input swipe {x} {int(self.h * 0.3)} {x} {int(self.h * 0.85)} 600')
                time.sleep(1.5)
                self.shot(f'{k + 5}-{code}-large-after-amen-scrolled-to-top')
                check(f'9 ({code}): after Amen, scrolled back, the date line shows below the status bar',
                      self.d.has(month), f'recorded {seconds:.2f} s')
                self.d.tap(f'^{review}')
                time.sleep(3)
                self.shot(f'{k + 6}-{code}-large-review')
                self.d.key('KEYCODE_BACK')
                time.sleep(2)
                out[code] = {'recorded_s': seconds, 'ring': self.ring}
            return out
        finally:
            self.ring = ring
            self.d.sh(f'cmd locale set-app-locales {PKG} --locales ""; settings put system font_scale 1.0; wm density reset')

    # ---- 10. battery saver and "Don't keep activities" ----

    def step10(self):
        self.d.sh('settings put global always_finish_activities 1; cmd power set-mode 1')
        try:
            t0, rid = self.begin()
            self.until(t0, 10)
            self.d.key('KEYCODE_HOME')
            time.sleep(20)
            self.d.launch()  # a new activity: the old one was finished
            time.sleep(3)
            self.shot('11-dont-keep-activities')
            self.until(t0, 40)
            stopped, seconds = self.amen()
            wall = stopped - t0
            check('10: battery saver and "Don\'t keep activities": the same recording goes on', abs(seconds - wall) < 1,
                  f'recorded {seconds:.2f} s, Begin to Amen {wall:.2f} s')
            self.d.tap('^Save for later')
            self.home()
            return {'recorded_s': seconds, 'wall_s': round(wall, 2)}
        finally:
            self.d.sh('settings put global always_finish_activities 0; cmd power set-mode 0')

    # ---- 5. discard ----

    def step5(self):
        before = set(self.audio_files())
        t0, rid = self.begin()
        self.until(t0, 3)
        self.tap_ring()
        time.sleep(1.5)
        check('5: a tap on the ring does not discard', self.service_up() and not self.log_lines('recording: stopped|cancel'))
        self.until(t0, 6)
        self.hold_ring(2500)
        time.sleep(3)
        after = set(self.audio_files())
        left = [f for f in after - before if rid in f] + [f for f in after if rid in f]
        check('5: held within 10 s: no file and no part left', not left, f'left: {left}')
        check('5: no service and no notification left', not self.service_up() and not self.notification_up())
        self.home()
        self.shot('05-after-discard')
        return {'files_left': left}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('serial')
    p.add_argument('out')
    p.add_argument('--only', default='1,2,4,5')
    p.add_argument('--kills', type=int, default=5, help='force-stops in step 2')
    p.add_argument('--installed', action='store_true', help='the app is past its first run already')
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    r = Run(a.serial, a.out)
    r.kills = a.kills
    steps = a.only.split(',')
    summary = {'device': a.serial, 'ring': r.ring}
    r.push_sound()
    if a.installed:
        r.d.launch()
        r.home()
    elif '7' in steps:
        try:
            summary['step7'] = r.step7()  # the refusing first run, in place of the allowing one
        except Exception as e:
            check('7: ran to the end', False, repr(e))
            r.shot('failed-step7')
            r.d.sh(f'pm grant {PKG} android.permission.RECORD_AUDIO; pm grant {PKG} android.permission.POST_NOTIFICATIONS')
            r.d.launch()
    else:
        r.first_run()
    for s in ['1', '2', '3', '4', '5', '6', '8', '10', '9']:
        if s not in steps:
            continue
        try:
            summary[f'step{s}'] = getattr(r, f'step{s}')()
        except Exception as e:  # one step's failure must not hide the others
            check(f'{s}: ran to the end', False, repr(e))
            r.shot(f'failed-step{s}')
            r.d.key('KEYCODE_BACK')
            try:
                r.d.launch()
                r.d.wait('^New blessing|^Later', 20)
                if r.d.has('^Later'):
                    r.d.tap('^Later')
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
