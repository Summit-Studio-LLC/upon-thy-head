#!/usr/bin/env python3
"""Android's words, unattended, on a booted emulator (tool/android_words.sh boots it, serves the model
and shuts both down). docs/android-plan.md, tasks 8 to 10, acceptance 1, 3, 4 and 5.

Driven through the screen as a person would (tool/android_ui.py). The microphone hears known speech
(SegmentRecorder's debug source); at Amen the recording is replaced by a known file
(`files/debug_feed.m4a`), so the words can be scored against exact text.

  1. fresh install: the first run, Download (from the Mac, tool/model_server.py), the practice with
     the 38 s English blessing: words per hundred wrong, and the time from Amen to words.
  3. a Spanish blessing (the language chosen from the pull-down): words per hundred wrong.
  5. a two-minute blessing written in full; then the same left mid-way (Home, back 10 s later); then
     force-stopped mid-way and opened again: it carries on from its last piece, and the final words
     are the same each time.
  4. fresh install again: Later at the first run; three blessings recorded while the model is not
     there ("The recording is kept"); Download on the third's page; all three written, oldest first.

Prints one line per check and a JSON summary; exits non-zero if any check failed. Every wait has
a limit.

  tool/android_words.py SERIAL OUTDIR [--only 1,3,5,4] [--apk APK]
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
WORK = os.path.join(APP, 'build', 'android_words')

# what the known recordings say (integration_test/audio; lib/check/spoken.dart)
EN = ("Emma, I lay my hands upon your head, um, right now, to give you a blessing of comfort. "
      "Your Heavenly Father knows you. He knows about, He knows the worry you have carried these weeks, and He wants you to know "
      "that you have not carried it alone. I bless you with, with peace as you go into this surgery, and I bless the hands of "
      "those who are going to be caring for you. Be patient with your body as it heals. your strength, it's going to come back "
      "to you in its time. I say these things in the name of Jesus Christ, amen.")
ES = ("Emma, pongo mis manos sobre tu cabeza para darte una bendición de consuelo. "
      "Tu Padre Celestial te conoce, y sabe la preocupación que has llevado estas semanas. Te bendigo con paz, y con fuerza "
      "para los días que vienen. Digo estas cosas en el nombre de Jesucristo, amén.")

results = []


def check(name, ok, detail=''):
    results.append({'check': name, 'ok': bool(ok), 'detail': detail})
    print(f"{'PASS' if ok else 'FAIL'}  {name}  {detail}", flush=True)
    return ok


def words(s):
    s = s.lower().replace('’', "'")
    s = re.sub(r"[^\w' ]+", ' ', s)
    return [w for w in s.split() if w and w != "'"]


def wer(truth, heard):
    a, b = words(truth), words(heard)
    prev = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i] + [0] * len(b)
        for j in range(1, len(b) + 1):
            cur[j] = min(prev[j - 1] + (a[i - 1] != b[j - 1]), prev[j] + 1, cur[j - 1] + 1)
        prev = cur
    return round(100 * prev[-1] / max(1, len(a)), 1)


class Run:
    def __init__(self, serial, out, apk):
        self.d = Device(serial)
        self.out = out
        self.apk = apk
        w, h = map(int, re.findall(r'(\d+)x(\d+)', self.d.sh('wm size'))[-1])
        dens = int(re.findall(r'(\d+)', self.d.sh('wm density'))[-1]) / 160
        self.ring = (w // 2, int(h - 136 * dens))

    # ---- helpers ----

    def shot(self, name):
        self.d.shot(os.path.join(self.out, f'{name}.png'))

    def log(self):
        return self.d.adb('logcat', '-d', '-v', 'raw', 'flutter:I', 'speech:I', 'whisper:I', 'model:I', 'words:I', '*:S', timeout=30)

    def lines(self, pattern):
        return [l for l in self.log().splitlines() if re.search(pattern, l)]

    def until_line(self, pattern, seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            l = self.lines(pattern)
            if l:
                return l
            time.sleep(1)
        raise TimeoutError(f'no log line matching {pattern!r} within {seconds} s; last: {self.lines("words:|model:")[-5:]}')

    def put(self, local, name):
        """A file into the app's own files folder."""
        self.d.adb('push', local, f'/data/local/tmp/uth_{name}', timeout=120, check=True)
        self.d.sh(f'run-as {PKG} mkdir -p files; run-as {PKG} cp /data/local/tmp/uth_{name} files/{name}; rm /data/local/tmp/uth_{name}')

    def feed(self, local):
        self.put(local, 'debug_feed.m4a')

    def fresh(self):
        """A fresh install, with the known speech for the microphone."""
        self.d.adb('uninstall', PKG, timeout=60)
        self.d.sh('pm trim-caches 4G', timeout=120)  # small emulator disks: room for the install
        self.d.adb('install', self.apk, timeout=300, check=True)
        self.put(os.path.join(WORK, 'mic.pcm'), 'debug_mic.pcm')
        self.d.adb('logcat', '-c')

    def first_run_to_model(self):
        self.d.launch()
        # the welcome's Continue is shown while the page is still opening, when a tap does nothing
        for _ in range(5):
            self.d.tap('^Continue', 40)
            try:
                self.d.wait('^A few things first|^Allow microphone', 10)
                break
            except TimeoutError:
                pass
        self.d.tap('^Allow microphone')
        self.d.tap('^While using the app')
        self.d.tap('^Allow notifications')
        self.d.tap('^Allow$')
        self.d.wait('Notifications\\. Optional.*Allowed')
        self.d.tap('^Continue')
        self.d.wait('^Writing the words down', 30)

    def home(self):
        self.d.wait('^New blessing', 30)

    def hold_ring(self, ms=2500):
        # the ring by its label ("Amen. Hold to finish"), where it is on this screen and at this size
        x, y = self.d.find(r'^Am[eé]n\. ') or self.ring
        self.d.sh(f'input swipe {x} {y} {x} {y} {ms}', timeout=30)

    def record(self, feed, seconds=11, spanish=False):
        """New blessing, Begin, [seconds], Amen (the recording replaced by [feed]); its id."""
        self.feed(feed)
        self.d.tap('^New blessing', 30)
        self.d.wait('^Begin')
        if spanish:
            self.d.tap('^Language of the blessing')
            self.d.wait('^Español$')
            self.shot('words-04-language-menu')
            self.d.tap('^Español$')
            self.d.wait('Language of the blessing: Español')
        n = len(self.lines(r'recording: started at'))
        self.d.tap('^Begin')
        l = self.until_line(r'recording: started at \d+ into \S+\.m4a', 15)
        while len(l) <= n:
            l = self.until_line(r'recording: started at \d+ into \S+\.m4a', 15)
        rid = re.search(r'into (\S+)\.m4a', l[-1]).group(1)
        time.sleep(seconds)
        # a slow emulator can miss one long press: once more if Amen did not take
        for attempt in range(3):
            self.hold_ring(3500)
            try:
                self.d.wait('^Review now|^Revisar ahora', 15 if attempt < 2 else 30)
                break
            except TimeoutError:
                if attempt == 2:
                    raise
        return rid

    def text_of(self, rid, seconds):
        """The words written for a recording: the log says when, a file (debug builds) has them whole."""
        l = self.until_line(rf'words: text {re.escape(rid)}\.m4a ', seconds)
        name = f'{rid}.m4a.txt'
        whole = self.d.adb('exec-out', f"run-as {PKG} sh -c 'cat */words_text/{name} 2>/dev/null || cat */*/words_text/{name} 2>/dev/null'", timeout=30)
        if whole.strip():
            return whole
        return json.loads(l[-1].split(f'words: text {rid}.m4a ', 1)[1])

    # ---- 1. first run, Download, practice ----

    def step1(self):
        self.fresh()
        self.first_run_to_model()
        self.shot('words-01-first-run-offer')
        check('1: the first run offers the download, with Download and Later', self.d.has('one-time download of 60 MB') and
              self.d.has('^Download$') and self.d.has('^Later$'))
        t0 = time.monotonic()
        self.d.tap('^Download$')
        time.sleep(3)
        self.shot('words-02-downloading')
        check('1: the download shows its progress', self.d.has('Downloading… \\d+ of 60 MB') or self.d.has('Checking the download'))
        self.d.wait('^Ready\\. This phone can write', 240)
        download_s = round(time.monotonic() - t0, 1)
        self.shot('words-03-ready')
        check('1: the model arrives and is checked', True, f'{download_s} s from Download to Ready')
        self.d.tap('^Continue')
        self.feed(os.path.join(APP, 'integration_test', 'audio', 'en.m4a'))
        self.d.tap('^Try it', 20)
        self.d.wait('^Begin', 20)
        self.d.tap('^Begin')
        time.sleep(3)
        self.hold_ring()
        a = time.monotonic()
        self.d.wait('^What the phone wrote', 30)
        line = self.until_line(r'words: text \S+ ', 120)[-1]
        took = round(time.monotonic() - a, 1)
        heard = json.loads(line.split(' ', 3)[3])
        time.sleep(1)
        self.shot('words-05-practice-result')
        w = wer(EN, heard)
        check('1: the practice writes the 38 s English blessing', w <= 15, f'{w} wrong per hundred, {took} s from Amen to words')
        check('1: the practice is in paragraphs', '\n\n' in heard, json.dumps(heard))
        self.d.tap('^Continue', 30)
        self.home()
        return {'download_s': download_s, 'practice_wer': w, 'practice_s': took, 'practice_text': heard}

    # ---- 3. Spanish ----

    def step3(self):
        rid = self.record(os.path.join(APP, 'integration_test', 'audio', 'es.m4a'), spanish=True)
        heard = self.text_of(rid, 120)
        time.sleep(1)
        self.shot('words-06-after-spanish')
        w = wer(ES, heard)
        check('3: a Spanish blessing is written in Spanish', w <= 20, f'{w} wrong per hundred: {json.dumps(heard)}')
        self.d.tap('^Save for later')
        self.home()
        return {'wer': w, 'text': heard}

    # ---- 5. left, and force-stopped, mid-writing ----

    def step5(self):
        long = os.path.join(WORK, 'two_minutes.m4a')
        rid = self.record(long)
        a = time.monotonic()
        ref = self.text_of(rid, 300)
        whole_s = round(time.monotonic() - a, 1)
        pieces = int(self.lines(rf'words: wrote {re.escape(rid)}\.m4a: [\d.]+ s, (\d+) pieces')[-1].split(' pieces')[0].split(', ')[-1])
        check('5: a two-minute blessing is written in full', len(words(ref)) > 150, f'{pieces} pieces in {whole_s} s')
        self.d.tap('^Save for later')
        self.home()

        # left mid-way (the log cleared first, so "piece 4" is this recording's)
        self.d.adb('logcat', '-c')
        rid2 = self.record(long)
        self.until_line(r'words: piece 4/', 120)
        self.shot('words-07-writing')
        self.d.key('KEYCODE_HOME')
        time.sleep(10)
        self.d.launch()
        left = self.text_of(rid2, 300)
        check('5: left mid-way and opened again: the same words', left == ref, '' if left == ref else json.dumps([ref, left]))
        self.d.wait('^Save for later|^New blessing', 20)
        if self.d.has('^Save for later'):
            self.d.tap('^Save for later')
        self.home()

        # force-stopped mid-way
        self.d.adb('logcat', '-c')
        rid3 = self.record(long)
        self.until_line(r'words: piece 6/', 120)
        done_before = len(self.lines(r'words: piece \d+/'))
        self.d.sh(f'am force-stop {PKG}')
        time.sleep(2)
        self.d.adb('logcat', '-c')
        self.d.launch()
        l = self.until_line(rf'words: {re.escape(rid3)}\.m4a carries on from piece (\d+)', 120)
        piece = int(re.search(r'carries on from piece (\d+)', l[-1]).group(1))
        killed = self.text_of(rid3, 300)
        check('5: force-stopped mid-way: carries on from its last piece', piece >= 6, f'from piece {piece} of {pieces}')
        check('5: force-stopped mid-way: the same words', killed == ref, '' if killed == ref else json.dumps([ref, killed]))
        self.home()
        return {'pieces': pieces, 'whole_s': whole_s, 'resumed_from': piece, 'reference': ref}

    def step5b(self):
        """Force-stopped right after Amen, before its first piece: written in full at the next launch."""
        long = os.path.join(WORK, 'two_minutes.m4a')
        self.d.adb('logcat', '-c')
        rid = self.record(long)
        self.d.sh(f'am force-stop {PKG}')
        time.sleep(2)
        self.d.adb('logcat', '-c')
        self.d.launch()
        text = self.text_of(rid, 300)
        check('5: force-stopped right after Amen: written in full at the next launch', len(words(text)) > 150, f'{len(words(text))} words')
        return {'words': len(words(text))}

    # ---- 4. Later, three waiting, Download, written oldest first ----

    def step4(self):
        self.fresh()
        self.first_run_to_model()
        self.d.tap('^Later$')
        self.home()
        ids = []
        en = os.path.join(APP, 'integration_test', 'audio', 'en.m4a')
        for i in range(3):
            ids.append(self.record(en))
            time.sleep(2)
            if i == 0:
                self.shot('words-08-after-amen-later')
                check('4: without the model, the recording is kept and the download offered',
                      self.d.has('^The recording is kept') and self.d.has('one-time download is done') and self.d.has('^Download$'))
            if i < 2:
                self.d.tap('^Save for later')
                self.home()
        self.d.adb('logcat', '-c')
        self.d.tap('^Download$')
        l = []
        end = time.monotonic() + 420
        while time.monotonic() < end and len(l) < 3:
            l = self.lines(r'words: wrote \S+ from its kept recording')
            time.sleep(2)
        order = [re.search(r'words: wrote (\S+) from', x).group(1) for x in l]
        check('4: once downloaded, all three are written', len(order) == 3, json.dumps(order))
        check('4: oldest first', order == ids, json.dumps({'recorded': ids, 'written': order}))
        # the page after Amen of the last one, still open, shows that its words came
        time.sleep(2)
        self.shot('words-09-written-after-download')
        check('4: the page after Amen no longer says "No words were heard"', not self.d.has('^No words were heard'))
        self.d.wait('^Save for later|^New blessing', 20)
        if self.d.has('^Save for later'):
            self.d.tap('^Save for later')
        self.home()
        return {'recorded': ids, 'written': order}


    # ---- 6. too little room, the connection lost, the app killed, mid-download ----

    def requests(self):
        try:
            with open(os.path.join(self.out, 'requests.log')) as f:
                return f.read().splitlines()
        except OSError:
            return []

    def step6(self):
        self.fresh()
        self.first_run_to_model()
        # too little room: the phone says so plainly, and nothing is fetched
        before = len(self.requests())
        self.d.sh(f"run-as {PKG} sh -c 'echo 10000000 > files/debug_free_bytes'")
        self.d.tap('^Download$')
        self.d.wait('needs \\d+ MB more free space', 20)
        self.shot('words-10-no-room')
        check('6: too little room is said plainly, and nothing is downloaded', len(self.requests()) == before)
        self.d.sh(f'run-as {PKG} rm files/debug_free_bytes')

        # the connection lost two seconds in: it waits, then carries on from where it was
        self.d.tap('^Try again$|^Download$')
        time.sleep(2)
        self.d.sh('svc wifi disable; svc data disable')
        try:
            self.d.wait('Waiting for a connection', 60)
            self.shot('words-11-waiting-for-connection')
            check('6: the connection lost mid-download: "Waiting for a connection"', True)
        finally:
            self.d.sh('svc wifi enable; svc data enable')
        self.d.wait('^Ready\\. This phone can write|Ready\\. This phone', 180)
        ranged = [l for l in self.requests()[before:] if "range='bytes=" in l]
        check('6: it carried on from where it stopped (a range request), and was checked', len(ranged) >= 1, json.dumps(self.requests()[before:]))

        # killed mid-download: opened again, it carries on by itself
        self.fresh()
        self.first_run_to_model()
        before = len(self.requests())
        self.d.tap('^Download$')
        time.sleep(4)
        self.d.sh(f'am force-stop {PKG}')
        time.sleep(2)
        self.d.launch()
        self.d.wait('^Writing the words down', 30)
        self.d.wait('Ready\\. This phone', 180)
        after = self.requests()[before:]
        check('6: killed mid-download, opened again: carries on (a range request) and is ready', any("range='bytes=" in l for l in after),
              json.dumps(after))
        self.d.tap('^Continue')
        return {'requests': self.requests()}

    # ---- 7. airplane mode: the words are written with no network at all ----

    def step7(self):
        if self.d.has('^Try it'):  # straight from step 6: skip the practice
            self.d.key('KEYCODE_BACK')
        self.home()
        before = len(self.requests())
        self.d.sh('cmd connectivity airplane-mode enable')
        time.sleep(3)
        try:
            rid = self.record(os.path.join(APP, 'integration_test', 'audio', 'en.m4a'))
            heard = self.text_of(rid, 120)
            time.sleep(1)
            self.shot('words-12-airplane-mode')
            w = wer(EN, heard)
            check('7: in airplane mode the words are written', w <= 15, f'{w} wrong per hundred')
        finally:
            self.d.sh('cmd connectivity airplane-mode disable')
        reqs = self.requests()
        check('7: the only requests the app ever made to the server were for the model',
              all(' /ggml-base-q5_1.bin ' in l for l in reqs) and len(reqs) == before, json.dumps(reqs))
        return {'wer': w}


    # ---- 9. a new blessing while an older one is being written ----

    def step9(self):
        """Needs the model (run after 1 or 6). The older recording is the two-minute one; the new
        one is recorded for real from the microphone's known speech (no feed), so what is kept is
        what was heard."""
        self.home()
        old = self.record(os.path.join(WORK, 'two_minutes.m4a'))
        self.until_line(rf'words: piece 3/', 120)
        self.d.tap('^Save for later')
        self.home()
        self.d.sh(f'run-as {PKG} rm -f files/debug_feed.m4a')
        self.d.tap('^New blessing', 30)
        self.d.wait('^Begin')
        n = len(self.lines(r'recording: started at'))
        t0 = time.monotonic()
        self.d.tap('^Begin')
        l = self.until_line(r'recording: started at \d+ into \S+\.m4a', 15)
        while len(l) <= n:
            l = self.until_line(r'recording: started at \d+ into \S+\.m4a', 15)
        begin_s = round(time.monotonic() - t0, 2)
        new = re.search(r'into (\S+)\.m4a', l[-1]).group(1)
        writing = bool(self.lines(r'words: piece \d+/')) and not self.lines(rf'words: text {re.escape(old)}\.m4a ')
        check('9: Begin is not held up while an older blessing is being written', begin_s < 4 and writing,
              f'{begin_s} s from the tap to recording (taps through adb take about 1 s); older still writing: {writing}')
        time.sleep(14)
        self.hold_ring()
        self.d.wait('^Review now', 30)
        heard = self.text_of(new, 240)
        old_text = self.text_of(old, 300)
        check('9: the new recording is whole (its words are the speech it heard)', ' '.join(words(heard)).startswith(' '.join(words(EN)[:6])),
              json.dumps(heard))
        order = [re.search(r'words: text (\S+)\.m4a', x).group(1) for x in self.lines(r'words: text \S+\.m4a ')]
        check('9: the new one is written first, then the older one finishes', order[-2:] == [new, old], json.dumps(order))
        self.shot('words-13-new-while-writing')
        self.d.tap('^Save for later')
        self.home()
        return {'begin_s': begin_s, 'new_text': heard, 'old_len': len(words(old_text))}

    # ---- 11. Spanish by the phone's language, and the largest text and display size ----

    def step11(self):
        """Needs the model. For the eye: Settings' model row, the writing screen and the review page,
        in Spanish and English at the largest sizes; then the download row once the model is removed."""
        L = {'en': dict(new='^New blessing', begin='^Begin', review='^Review now', save='^Save for later',
                        settings='^Settings$', remove='^Remove$', download='^Download$'),
             'es': dict(new='^Nueva bendición', begin='^Comenzar', review='^Revisar ahora', save='^Guardar para después',
                        settings='^Configuración$', remove='^Quitar$', download='^Descargar$')}
        base = re.findall(r'(\d+)', self.d.sh('wm density'))[0]
        long = os.path.join(WORK, 'two_minutes.m4a')
        shots = []

        def screens(lang, tag):
            t = L[lang]
            self.d.launch()
            self.d.wait(t['new'], 30)
            self.feed(long)
            self.d.tap(t['new'], 30)
            self.d.wait(t['begin'])
            self.d.tap(t['begin'])
            time.sleep(4)
            # the ring itself, found by its label: at the larger display size it is not where hold_ring presses
            self.d.hold(r'^Am[eé]n\. ', 2500)
            self.until_line(r'words: piece 2/', 120)
            self.shot(f'words-15-{tag}-writing'); shots.append(f'{tag}-writing')
            self.d.tap(t['review'], 30)
            time.sleep(2)
            self.shot(f'words-16-{tag}-review-writing'); shots.append(f'{tag}-review-writing')
            self.until_line(r'words: text \S+ ', 300)
            time.sleep(2)
            self.shot(f'words-17-{tag}-review-words'); shots.append(f'{tag}-review-words')
            self.d.key('KEYCODE_BACK')
            time.sleep(1)
            if self.d.has(t['save']):
                self.d.tap(t['save'])
            self.d.wait(t['new'], 30)
            self.d.tap(t['settings'], 20)
            time.sleep(2)
            for _ in range(6):
                if self.d.has(t['remove']) or self.d.has(t['download']):
                    break
                self.d.sh('input swipe 500 1800 500 700 400')
                time.sleep(1)
            self.shot(f'words-18-{tag}-settings-model'); shots.append(f'{tag}-settings-model')
            self.d.key('KEYCODE_BACK')
            self.d.adb('logcat', '-c')

        try:
            self.d.sh('cmd locale set-device-locale es-US')
            self.d.sh(f'settings put system font_scale 2.0; wm density {int(int(base) * 1.3)}')
            self.d.sh(f'am force-stop {PKG}')
            time.sleep(3)
            screens('es', 'es-large')
            self.d.sh('cmd locale set-device-locale en-US')
            self.d.sh(f'am force-stop {PKG}')
            time.sleep(3)
            screens('en', 'en-large')
        finally:
            self.d.sh('cmd locale set-device-locale en-US; settings put system font_scale 1.0; wm density reset')
        check('11: Spanish and the largest sizes captured for the eye', True, ', '.join(shots))
        return {'shots': shots}

    # ---- 12. cold start, before and after (release builds put in build/android_words/ first) ----

    def stepcold(self):
        out = {}
        for name in ('before', 'after'):
            apk = os.path.join(WORK, f'app-release-{name}.apk')
            self.d.adb('uninstall', PKG, timeout=60)
            self.d.sh('pm trim-caches 4G', timeout=120)
            self.d.adb('install', apk, timeout=300, check=True)
            times = []
            for _ in range(6):
                self.d.sh(f'am force-stop {PKG}')
                time.sleep(2)
                r = self.d.sh(f'am start -W -n {PKG}/.MainActivity', timeout=60)
                m = re.search(r'TotalTime: (\d+)', r)
                if m:
                    times.append(int(m.group(1)))
                time.sleep(3)
            times = times[1:]  # the first start after an install also compiles
            out[name] = {'ms': times, 'median': sorted(times)[len(times) // 2] if times else None,
                         'bytes': os.path.getsize(apk)}
        self.d.adb('uninstall', PKG, timeout=60)
        check('12: cold start before and after', out['before']['median'] and out['after']['median'], json.dumps(out))
        return out

    # ---- a wrong checksum (an APK built with a wrong WORDS_MODEL_SHA256) ----

    def stepsum(self):
        bad = os.path.join(WORK, 'app-badsum.apk')
        self.d.adb('uninstall', PKG, timeout=60)
        self.d.sh('pm trim-caches 4G', timeout=120)
        self.d.adb('install', bad, timeout=300, check=True)
        self.put(os.path.join(WORK, 'mic.pcm'), 'debug_mic.pcm')
        self.d.adb('logcat', '-c')
        self.first_run_to_model()
        self.d.tap('^Download$')
        self.d.wait('not complete or not right', 120)
        self.shot('words-14-wrong-checksum')
        files = self.d.sh(f'run-as {PKG} ls -la no_backup/models 2>&1')
        check('6: a wrong checksum is refused and the file is not kept', 'ggml' not in files,
              files.strip())
        check('6: and the offer is there again (Try again)', self.d.has('^Try again$'))
        return {'files': files}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('serial')
    p.add_argument('out')
    p.add_argument('--only', default='1,3,5,4')
    p.add_argument('--apk', default=os.path.join(APP, 'build', 'app', 'outputs', 'flutter-apk', 'app-debug.apk'))
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    r = Run(a.serial, a.out, a.apk)
    steps = a.only.split(',')
    summary = {'device': a.serial}
    for s in steps:
        try:
            summary[f'step{s}'] = getattr(r, f'step{s}')()
        except Exception as e:  # one step's failure must not hide the others
            check(f'{s}: ran to the end', False, repr(e))
            r.shot(f'failed-words-step{s}')
    summary['checks'] = results
    with open(os.path.join(a.out, 'summary.json'), 'w') as f:
        json.dump(summary, f, indent=1, ensure_ascii=False)
    failed = [x for x in results if not x['ok']]
    print(f'== {len(results) - len(failed)} of {len(results)} checks passed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
