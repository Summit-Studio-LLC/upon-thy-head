"""Sending and receiving a blessing on Android, against the website running on this Mac, through
what the screen shows (tool/android_ui.py). Run by tool/android_share.sh; read that first.

  tool/android_share.py SERIAL OUTDIR APK WEBSITE_LINKS_DIR REQUESTS_LOG [--only 1,3,5,6,8,9,4,10]

Steps (the acceptance's numbers, docs/android-plan.md tasks 13 and 14):
  1  "Comfort before surgery": the S3 sheet, the link made, Copy, Android's share sheet holding the
     one link as text/plain; the link opened in Chrome on the Mac shows the words exactly
  9  Text and PDF: what the share sheet held; the PDF pulled off and checked (tool/pdf_check.swift)
  5  a second link; "Your links", Stop; the web page says stopped; opened into the app, the same
  3  the app's data cleared (this phone becomes the receiver): the link opens as "already have it";
     the blessing deleted; the link again: the keep sheet, Keep, the reading page; the record and its
     place as sent. The refusals: key missing, a different copy, made by a newer version, a wrong
     key, expired, no internet; a vector of website/protocol-vectors.json opened
  4  a link arriving with the app closed, in the background, and during a recording (after Amen)
  6  no internet: the one line, "Send as a file", the file pulled off and checked, opened back after a
     reinstall
  8  .blessing files from the Files app (application/octet-stream from a content:// address), a
     file that is not a blessing, and what Android offers the app for (resolve-activity)
 10  Spanish, then the largest font and display size: the sheets, for the eye (screenshots)
The website is stopped and started through files the shell script watches (OUTDIR/ctl).
"""
import argparse
import base64
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from android_ui import Device, PKG  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = 'http://127.0.0.1:4319'
results = []


def check(name, ok, detail=''):
    results.append({'check': name, 'ok': bool(ok), 'detail': str(detail)[:300]})
    print(f"{'PASS' if ok else 'FAIL'}  {name}  {str(detail)[:300]}", flush=True)
    return ok


def web(link, shot=None):
    """The link opened in Chrome on the Mac (tool/link_web.mjs): what the page shows."""
    args = ['node', os.path.join(HERE, 'link_web.mjs'), link] + ([shot] if shot else [])
    out = subprocess.run(args, capture_output=True, text=True, timeout=90).stdout.strip().splitlines()
    try:
        return json.loads(out[-1])
    except Exception:
        return {'state': 'error', 'raw': out[-3:]}


def node(*args):
    out = subprocess.run(['node', os.path.join(HERE, 'android_share_seal.mjs'), *args], capture_output=True, text=True, timeout=30)
    return json.loads(out.stdout)


class Run:
    def __init__(self, a):
        self.d = Device(a.serial)
        self.out, self.apk, self.links_dir, self.req = a.out, a.apk, a.links, a.requests
        self.made = {}   # name → link as the app made it
        self.n = 90      # screenshots continue design/sim/android's numbering
        self.shots = []

    # ---- helpers ----

    def shot(self, name):
        p = os.path.join(self.out, f'{name}.png')
        self.d.shot(p)
        self.shots.append(name)
        return p

    def server(self, what):
        """stop or start the website (the shell script does it)."""
        ctl = os.path.join(self.out, 'ctl')
        with open(ctl + '.tmp', 'w') as f:
            f.write(what)
        os.rename(ctl + '.tmp', ctl)
        for _ in range(240):
            if not os.path.exists(ctl):
                return
            time.sleep(0.25)
        raise RuntimeError(f'server {what}: no answer')

    def launch(self):
        self.d.launch()
        time.sleep(2)
        self.back_home()
        self.home()

    def home(self, seconds=40):
        self.d.wait('^New blessing|^Nueva bendición', seconds)
        time.sleep(1)

    def grant(self):
        for p in ['RECORD_AUDIO', 'POST_NOTIFICATIONS', 'ACCESS_COARSE_LOCATION']:
            self.d.sh(f'pm grant {PKG} android.permission.{p}')

    def first_run(self):
        """Through the first run if it shows (permissions granted beforehand)."""
        for _ in range(6):
            if self.d.has('^New blessing|^Nueva bendición'):
                return
            for b in ['^Continue', '^Done', '^Skip']:
                if self.d.has(b):
                    self.d.tap(b, 5)
                    time.sleep(1.5)
                    break
            else:
                time.sleep(2)
        self.home()

    def fresh(self, keep_data=False):
        if not keep_data:
            self.d.sh(f'pm clear {PKG}')
        self.grant()
        self.d.launch()
        time.sleep(3)
        self.first_run()

    def open_blessing(self, title):
        """From home: the list, then the blessing's row."""
        self.back_home()
        self.home()
        if self.d.has('^Show as a list|^Ver como lista'):
            self.d.tap('^Show as a list|^Ver como lista')
            time.sleep(1.5)
        self.d.tap(r'(^|\. )' + re.escape(title) + r'(\.|$)', 15)  # a row reads "<date>. <title>. From <giver>"
        time.sleep(2)
        self.d.wait('^Share$|^Compartir$', 15)

    def back_home(self):
        for _ in range(5):
            if self.d.has('^New blessing|^Nueva bendición'):
                break
            if self.d.has('^Back to the sky|^Volver al cielo'):
                self.d.tap('^Back to the sky|^Volver al cielo', 5)
            else:
                self.d.key('KEYCODE_BACK')
            time.sleep(1.2)
        if self.d.has('^Show as a sky|^Ver como cielo'):
            self.d.tap('^Show as a sky|^Ver como cielo')
            time.sleep(1)

    def link_now(self):
        """The link as the S3 sheet shows it."""
        for label in [n[0].replace('\n', ' ') for n in self.d.nodes()]:
            m = re.search(r'https?://\S+/b/[A-Za-z0-9_-]{22}#[A-Za-z0-9_-]{43}', label)
            if m:
                return m.group(0)
        return None

    def am_link(self, link, stop=False):
        """Android hands the app a link: the real site's form, as App Links will, explicitly."""
        m = re.search(r'/b/([A-Za-z0-9_-]+)(#.*)?$', link)
        real = f'https://uponthyhead.app/b/{m.group(1)}{m.group(2) or ""}'
        if stop:
            self.d.sh(f'am force-stop {PKG}')
            time.sleep(1)
        # single quotes keep the shell from reading '#' as a comment
        return self.d.sh(f"am start -W -a android.intent.action.VIEW -d '{real}' {PKG}")

    def receive_sheet(self, seconds=20):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            ls = [n[0] for n in self.d.nodes()]
            j = ' | '.join(ls)
            for pat in ['Keep it with your blessings', 'already have this blessing', 'this copy is different|Replace mine',
                        'stopped working', 'on its way', 'not complete', 'could not be fetched', 'could not be opened',
                        'could not be read', 'newer version']:
                if re.search(pat, j):
                    return j
            time.sleep(0.8)
        return ' | '.join(n[0] for n in self.d.nodes())

    def dismiss_sheet(self):
        for b in ['^OK$', '^Not now$', '^Keep mine$', '^Ahora no$']:
            if self.d.has(b):
                self.d.tap(b, 5)
                time.sleep(1.5)
                return

    def db(self):
        tmp = tempfile.mkdtemp()
        for ext in ['', '-wal', '-shm']:
            data = self.d.adb('exec-out', 'run-as', PKG, 'cat', 'app_flutter/blessings.sqlite' + ext, binary=True)
            with open(os.path.join(tmp, 'b.sqlite' + ext), 'wb') as f:
                f.write(data)
        con = sqlite3.connect(os.path.join(tmp, 'b.sqlite'))
        con.row_factory = sqlite3.Row
        return con

    def row(self, title):
        con = self.db()
        r = con.execute('select * from blessings where title = ?', (title,)).fetchone()
        out = dict(r) if r else None
        if out:
            out['changes'] = [dict(x) for x in con.execute('select * from blessing_changes where blessing_id = ? order by position', (out['id'],))]
            out['tags'] = [x[0] for x in con.execute('select tag from blessing_tags where blessing_id = ? order by position', (out['id'],))]
        con.close()
        return out

    def chooser(self):
        """Android's share sheet: up, and what its preview holds."""
        try:
            self.d.wait('^Share$|Copy|Nearby|Quick Share|Messages', 12)
        except TimeoutError:
            return None
        top = self.d.sh('dumpsys activity activities | grep -E "topResumedActivity|ResumedActivity" | head -2')
        return {'labels': [n[0] for n in self.d.nodes()], 'top': top}

    def close_chooser(self):
        self.d.key('KEYCODE_BACK')
        time.sleep(1.5)

    def make_link(self, title, name):
        self.open_blessing(title)
        self.d.tap('^Share$')
        time.sleep(1.5)
        if name == 'surgery':
            self.shot(f'{self.n}-share-sheet'); self.n += 1
        self.d.tap('^Send this blessing')
        self.d.wait('^Link made', 20)
        time.sleep(0.8)
        if name == 'surgery':   # Copy first: closing Android's share sheet closes this one too
            self.shot(f'{self.n}-link-made'); self.n += 1
            self.d.adb('logcat', '-c')
            self.d.tap('^Copy link')
            time.sleep(1)
            self.copy_log = self.d.adb('logcat', '-d', '-s', 'share:I')
            self.d.adb('logcat', '-c')
        # the sheet shows the link cut short; Android's share sheet shows it whole
        self.d.tap('^Send the link')
        self.chooser_seen = self.chooser()
        link = self.link_now()
        if name == 'surgery':
            self.shot(f'{self.n}-android-share-sheet'); self.n += 1
            self.handed_log = self.d.adb('logcat', '-d', '-s', 'share:I')
        self.close_chooser()
        self.made[name] = link
        return link

    # ---- 1 ----

    def step1(self):
        link = self.make_link('Comfort before surgery', 'surgery')
        check('1: the link made, 92 characters as the contract says (the local site in place of uponthyhead.app)',
              link is not None and len(link.split('/b/')[1]) == 66, link and f'{len(link)} characters, …/b/<22>#<43>')
        log = self.copy_log
        check('1: Copy: the link on the clipboard, marked sensitive (so Android 13+ hides it in its preview)',
              link is not None and f'copied: {len(link)} characters, read back true, sensitive true' in log, log.strip().splitlines()[-1:])
        c = self.chooser_seen
        held = [l for l in (c or {}).get('labels', []) if '/b/' in l]
        check("1: Android's share sheet is up holding the one link as its text",
              c is not None and len(held) >= 1 and all(link in h.replace('\n', ' ') for h in held), held[:2])
        log = self.handed_log
        check('1: handed over as text/plain with the link alone (the app\'s log, no key in it)',
              'handed text/plain' in log and (link.split('#')[1] not in log), log.strip().splitlines()[-1:] if log.strip() else '')
        # the web page in Chrome on the Mac
        page = web(link, os.path.join(self.out, f'{self.n}-web-page.png')); self.n += 1
        r = self.row('Comfort before surgery')
        expect = [s.strip() for s in re.split(r'\n\s*\n', r['polished_text']) if s.strip()]
        check('1: the web page shows the blessing\'s words, character for character',
              page.get('state') == 'open' and page.get('words') == expect and page.get('title') == 'Comfort before surgery',
              f"state {page.get('state')}, {len(page.get('words') or [])} paragraphs of {len(expect)}")
        self.original = r
        self.back_home()

    # ---- 9 ----

    def step9(self):
        self.open_blessing('Comfort before surgery')
        self.d.tap('^Share$')
        time.sleep(1.2)
        self.d.adb('logcat', '-c')
        self.d.tap('^Text$')
        c = self.chooser()
        self.shot(f'{self.n}-share-text'); self.n += 1
        joined = ' | '.join((c or {}).get('labels', []))
        check('9: Text: the share sheet holds the title, date and words', c is not None and 'Comfort before surgery' in joined, joined[:160])
        self.close_chooser()
        self.d.tap('^Share$')
        time.sleep(1.2)
        self.d.tap('^PDF$')
        c = self.chooser()
        self.shot(f'{self.n}-share-pdf'); self.n += 1
        log = self.d.adb('logcat', '-d', '-s', 'share:I')
        check('9: PDF: handed over as application/pdf through the app\'s content address, no permission asked',
              'handed application/pdf' in log and 'content://dev.summitstudio.uponthyhead.files/share/' in log, log.strip().splitlines()[-1:])
        names = self.d.sh(f'run-as {PKG} ls cache/share').split('\n')
        pdf = [x.strip() for x in names if x.strip().endswith('.pdf')]
        local = os.path.join(self.out, pdf[0] if pdf else 'shared.pdf')  # pdf_check reads the name too
        if pdf:
            self.d.pull(f'cache/share/{pdf[0]}', local)
        self.close_chooser()
        expected = {'fileName': pdf[0] if pdf else '', 'title': 'Comfort before surgery', 'paper': 'letter',
                    'paragraphs': [s.strip() for s in re.split(r'\n\s*\n', self.row('Comfort before surgery')['polished_text']) if s.strip()],
                    'footer': '{n} of {total}'}
        with open(os.path.join(self.out, 'pdf_expected.json'), 'w') as f:
            json.dump(expected, f)
        out = subprocess.run(['swift', os.path.join(HERE, 'pdf_check.swift'), local, os.path.join(self.out, 'pdf_expected.json'), self.out],
                             capture_output=True, text=True, timeout=240).stdout
        with open(os.path.join(self.out, 'pdf_check.txt'), 'w') as f:
            f.write(out)
        check('9: the PDF pulled off the emulator: Newsreader embedded, the right words (tool/pdf_check.swift)',
              'PDF CHECK PASSED' in out, ' / '.join(l for l in out.splitlines() if l.startswith('FAIL'))[:300] or pdf)
        self.back_home()

    # ---- 5 ----

    def step5(self):
        link = self.make_link('Before the new job', 'job')
        self.d.key('KEYCODE_BACK')
        time.sleep(1.5)
        self.back_home()
        self.d.tap('^Settings', 10)
        time.sleep(1.5)
        self.d.tap('^Your links', 10)
        time.sleep(1.5)
        self.shot(f'{self.n}-your-links'); self.n += 1
        # the newest link is first: "Before the new job"
        x, y = self.d.wait(r'(^|\. )Before the new job')
        stops = [at for l, at, _ in self.d.nodes() if l == 'Stop' or l.startswith('Stop,')]
        stop = min(stops, key=lambda a: abs(a[1] - y)) if stops else None
        self.d.sh(f'input tap {stop[0]} {stop[1]}')
        time.sleep(1)
        self.d.tap('^Stop link', 10)
        time.sleep(2.5)
        self.shot(f'{self.n}-your-links-stopped'); self.n += 1
        j = ' | '.join(n[0] for n in self.d.nodes())
        check('5: "Your links": Stop, and the link shows as stopped', 'Stopped' in j or 'stopped' in j, j[:200])
        page = web(link, os.path.join(self.out, f'{self.n}-web-stopped.png')); self.n += 1
        check('5: the web page then says the link has stopped', page.get('state') == 'gone', page.get('state'))
        self.back_home()
        self.am_link(link)
        j = self.receive_sheet()
        self.shot(f'{self.n}-keep-stopped'); self.n += 1
        check('5: opened into the app: "This link has stopped working."', 'stopped working' in j, j[:160])
        self.dismiss_sheet()

    # ---- 3 ----

    def plant(self, plain, version=1, expires_in=86400):
        tmp = tempfile.mktemp()
        with open(tmp, 'w') as f:
            f.write(plain)
        s = node('seal', tmp, str(version))
        ident = base64.urlsafe_b64encode(os.urandom(16)).decode().rstrip('=')
        with open(os.path.join(self.links_dir, ident + '.copy'), 'w') as f:
            json.dump({'c': s['locked'], 'e': int(time.time() * 1000) + expires_in * 1000, 's': 'planted'}, f)
        return f'{SITE}/b/{ident}#{s["key"]}', ident

    def refusal(self, name, link, expect, n_shot=True):
        self.am_link(link)
        j = self.receive_sheet()
        if n_shot:
            self.shot(f'{self.n}-refusal-{name}'); self.n += 1
        ok = check(f'3: {name}: "{expect}"', re.search(expect, j) is not None, j[:160])
        self.dismiss_sheet()
        return ok

    def step3(self):
        link = self.made['surgery']
        key = link.split('#')[1]
        ident = link.split('/b/')[1].split('#')[0]
        plain = node('open', os.path.join(self.links_dir, ident + '.copy'), key)['plain']
        # this phone becomes the receiver: its data cleared (the samples come back, the links do not)
        self.fresh()
        self.refusal('already have it', link, 'already have this blessing', n_shot=True)
        self.open_blessing('Comfort before surgery')
        self.d.sh('input swipe 540 1800 540 300 300')
        self.d.sh('input swipe 540 1800 540 300 300')
        self.d.tap('^Delete this blessing', 15)
        time.sleep(1)
        self.d.tap('^Delete$', 10)
        time.sleep(2.5)
        check('3: deleted here', self.row('Comfort before surgery') is None)
        self.back_home()
        self.am_link(link)
        j = self.receive_sheet()
        self.shot(f'{self.n}-keep-sheet-link'); self.n += 1
        check('3: the link opens the keep sheet', 'Keep it with your blessings' in j and 'Comfort before surgery' in j, j[:160])
        self.d.tap('^Keep$', 10)
        time.sleep(3)
        self.shot(f'{self.n}-kept-reading'); self.n += 1
        r = self.row('Comfort before surgery')
        o = self.original
        # the place travels to a tenth of a degree, as the app keeps it (lib/share/blessing_file.dart)
        tenth = lambda v: None if v is None else round(v, 1)
        differ = [k for k in ['id', 'title', 'giver', 'recipient', 'given_utc_minute', 'utc_offset_minutes', 'raw_text', 'polished_text']
                  if r is None or r[k] != o[k]] + [k for k in ['latitude', 'longitude'] if r is None or tenth(r[k]) != tenth(o[k])]
        same = not differ
        ch = r is not None and [(c['start_at'], c['was'], c['now'], c['kind']) for c in r['changes']] == \
            [(c['start_at'], c['was'], c['now'], c['kind']) for c in o['changes']]
        check('3: Keep: the reading page; the words, date and changes as sent, its place carried',
              same and ch and r['tags'] == o['tags'], r and f"place {r['latitude']}, {r['longitude']} (sent {o['latitude']}, {o['longitude']}); "
              f"{len(r['changes'])} changes, as sent {ch}; tags {r['tags']}; differ {differ}")
        self.back_home()
        # the refusals
        self.refusal('key missing', link.split('#')[0], 'not complete')
        d = json.loads(plain)
        d['title'] = 'Comfort before surgery'
        d['words'] = d['words'] + ' Amen.'
        diff, _ = self.plant(json.dumps(d, ensure_ascii=False, separators=(',', ':')))
        self.refusal('a different copy', diff, 'this copy is different|Replace mine')
        newer, _ = self.plant(plain, version=2)
        self.refusal('made by a newer version', newer, 'newer version')
        good, gid = self.plant(plain)
        wrong = good.split('#')[0] + '#' + base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip('=')
        self.refusal('a wrong key', wrong, 'could not be opened')
        expired, _ = self.plant(plain, expires_in=-60)
        self.refusal('expired', expired, 'stopped working', n_shot=False)
        # a vector of the contract, made by Node: what the iPhone is proven against too
        v = json.load(open(os.path.join(HERE, '..', '..', 'website', 'protocol-vectors.json')))['vectors'][0]
        with open(os.path.join(self.links_dir, v['id'] + '.copy'), 'w') as f:
            json.dump({'c': v['locked']['base64'] if isinstance(v['locked'], dict) else v['locked'], 'e': int(time.time() * 1000) + 86400000, 's': 'vector'}, f)
        self.am_link(v['link'])
        j = self.receive_sheet()
        check("3: the contract's first vector opens: its title on the keep sheet (or already here)",
              v['shown']['title'] in j or 'already have' in j or 'this copy is different' in j, j[:160])
        self.dismiss_sheet()
        self.server('stop')
        self.refusal('no internet', good, 'on its way')
        self.server('start')

    # ---- 4 ----

    def step4(self):
        plain = json.loads(node('open', *self._any_copy())['plain'])
        for how in ['closed', 'background', 'locked', 'recording']:
            d = dict(plain)
            d['id'] = f'arrival-{how}-{int(time.time())}'
            d['title'] = f'Arrived {how}'
            link, _ = self.plant(json.dumps(d, separators=(',', ':')))
            if how == 'closed':
                self.am_link(link, stop=True)
                j = self.receive_sheet(40)
                check('4: the app closed: launched by the link, the keep sheet', 'Arrived closed' in j, j[:120])
            elif how == 'locked':
                # the phone's own lock screen up (no screen lock set in this run: a swipe opens it)
                self.d.key('KEYCODE_SLEEP')
                time.sleep(3)
                self.am_link(link)
                time.sleep(3)
                self.d.key('KEYCODE_WAKEUP')
                time.sleep(1.5)
                self.d.sh('wm dismiss-keyguard')
                time.sleep(2)
                j = self.receive_sheet()
                self.shot(f'{self.n}-link-after-phone-lock'); self.n += 1
                check('4: the phone locked when the link came: after unlocking it, the keep sheet', 'Arrived locked' in j, j[:120])
            elif how == 'background':
                self.d.key('KEYCODE_HOME')
                time.sleep(5)
                self.am_link(link)
                j = self.receive_sheet()
                check('4: in the background: the keep sheet', 'Arrived background' in j, j[:120])
            else:
                self.d.tap('^New blessing|^Nueva bendición', 15)
                self.d.tap('^Begin', 15)
                time.sleep(12)
                self.am_link(link)
                time.sleep(5)
                j = ' | '.join(n[0] for n in self.d.nodes())
                self.shot(f'{self.n}-link-during-recording'); self.n += 1
                check('4: during a recording: nothing shows, still recording', 'Arrived recording' not in j and self.d.has('Amen'), j[:120])
                self.d.hold('Amen', 2500)
                time.sleep(3)
                for b in ['^Save for later', '^Review now', '^Done']:
                    if self.d.has(b):
                        self.d.tap(b, 5)
                        break
                time.sleep(2)
                self.back_home()
                j = self.receive_sheet(20)
                check('4: after Amen: the keep sheet', 'Arrived recording' in j, j[:120])
            self.dismiss_sheet()
            self.back_home()

    def _any_copy(self):
        link = self.made['surgery']
        ident = link.split('/b/')[1].split('#')[0]
        return os.path.join(self.links_dir, ident + '.copy'), link.split('#')[1]

    # ---- 6 ----

    def step6(self):
        self.server('stop')
        self.open_blessing('Comfort before surgery')
        self.d.tap('^Share$')
        time.sleep(1.2)
        self.d.tap('^Send this blessing')
        self.d.wait('^Send as a file', 25)
        self.shot(f'{self.n}-no-internet'); self.n += 1
        check('6: no internet: the one line and "Send as a file"', self.d.has('No internet, so a link cannot be made now'))
        self.d.adb('logcat', '-c')
        self.d.tap('^Send as a file')
        c = self.chooser()
        self.shot(f'{self.n}-share-file'); self.n += 1
        log = self.d.adb('logcat', '-d', '-s', 'share:I')
        check('6: the file handed over as application/vnd.uponthyhead.blessing by content address',
              'handed application/vnd.uponthyhead.blessing' in log, log.strip().splitlines()[-1:])
        names = [x.strip() for x in self.d.sh(f'run-as {PKG} ls cache/share').split('\n') if x.strip().endswith('.blessing')]
        local = os.path.join(self.out, 'shared.blessing')
        if names:
            self.d.pull(f'cache/share/{names[0]}', local)
        # what the receiving app is told: the name and type the provider gives
        q = self.d.sh(f"content query --uri 'content://{PKG}.files/share/{urllib.parse.quote(names[0]) if names else 'x'}' 2>&1")
        self.close_chooser()
        self.server('start')
        try:
            rec = json.load(open(local, encoding='utf-8'))
            ok = rec.get('format') == 'upon-thy-head/blessing' and rec.get('version') == 1 and rec.get('title') == 'Comfort before surgery'
        except Exception as e:
            rec, ok = {}, False
        check('6: the file pulled off: a valid blessing file, named for the blessing',
              ok and names and names[0].endswith('.blessing') and names[0].startswith('Comfort before surgery'), names)
        check('6: the app\'s content address withholds it from anyone not granted (Android refuses the shell)',
              'Permission Denial' in q or 'SecurityException' in q or 'not exported' in q, q.strip()[:120])
        self.blessing_file = local
        self.blessing_name = names[0] if names else 'x.blessing'
        self.back_home()
        # opened back after a reinstall
        self.d.adb('uninstall', PKG, timeout=60)
        out = self.d.adb('install', self.apk, timeout=240)
        check('6: reinstalled', 'Success' in out, out.strip()[-60:])
        self.fresh(keep_data=True)
        self.open_blessing('Comfort before surgery')
        self.d.sh('input swipe 540 1800 540 300 300')
        self.d.sh('input swipe 540 1800 540 300 300')
        self.d.tap('^Delete this blessing', 15)
        time.sleep(1)
        self.d.tap('^Delete$', 10)
        time.sleep(2.5)
        self.back_home()
        j = self.files_open(local, self.blessing_name)
        self.shot(f'{self.n}-keep-sheet-file'); self.n += 1
        check('6: the file opens back into the reinstalled app: the keep sheet', 'Keep it with your blessings' in j and 'Comfort before surgery' in j, j[:160])
        self.d.tap('^Keep$', 10)
        time.sleep(2.5)
        r = self.row('Comfort before surgery')
        check('6: kept: the words as sent', r is not None and r['polished_text'] == self.original['polished_text'])
        self.back_home()

    # ---- 8 ----

    def files_open(self, local, name):
        """Put [local] in Download and tap it in the Files app, as a person would."""
        self.d.adb('push', local, f'/sdcard/Download/{name}', timeout=60)
        self.d.sh("am start -a android.intent.action.VIEW -d 'content://com.android.externalstorage.documents/root/primary' "
                  "-t vnd.android.document/root com.google.android.documentsui")
        time.sleep(3)
        if not self.d.has(re.escape(name)):
            for _ in range(3):
                if self.d.has('^Download$'):
                    self.d.tap('^Download$', 5)
                    time.sleep(2)
                    break
                time.sleep(1)
        self.d.tap(re.escape(name), 20)
        time.sleep(2)
        # Android may ask which app opens it ("Open with Upon Thy Head", Just once / Always) when
        # another app (Google Wallet on the emulator) also takes the same type
        if self.d.has('^Open with|^Just once$') and not self.d.has('Keep it with your blessings'):
            if 'open-with' not in ' '.join(self.shots):
                self.shot(f'{self.n}-open-with'); self.n += 1
            if self.d.has('^Upon Thy Head$'):
                self.d.tap('^Upon Thy Head$', 5)
                time.sleep(1)
            self.d.tap('^Just once$', 5)
            time.sleep(1)
        return self.receive_sheet(25)

    def step8(self):
        # what the app is offered for (Android's resolver, as any app opening a file asks it)
        def resolves(args):
            out = self.d.sh(f'cmd package query-activities --brief {args}')
            return PKG in out
        cases = {
            'its own type (content)': ("-a android.intent.action.VIEW -d content://x/y -t application/vnd.uponthyhead.blessing", True),
            'octet-stream (content)': ("-a android.intent.action.VIEW -d content://x/y -t application/octet-stream", True),
            'no type, a name ending .blessing (file refused)': ("-a android.intent.action.VIEW -d 'file:///sdcard/Download/A%20b.blessing'", False),
            'no type, a name ending .blessing (content)': ("-a android.intent.action.VIEW -d 'content://p/Download/A b, March 3, 2026.blessing'", True),
            'no type, many dots ending .blessing (content)': ("-a android.intent.action.VIEW -d 'content://p/Download/A.b.c.d.blessing'", True),
            'share into the app, its own type': ("-a android.intent.action.SEND -t application/vnd.uponthyhead.blessing", True),
            'a picture': ("-a android.intent.action.VIEW -d content://x/y -t image/jpeg", False),
            'a PDF': ("-a android.intent.action.VIEW -d content://x/y -t application/pdf", False),
            'a zip': ("-a android.intent.action.VIEW -d content://x/y -t application/zip", False),
            'share any unknown file': ("-a android.intent.action.SEND -t application/octet-stream", False),
        }
        got = {k: resolves(a) for k, (a, _) in cases.items()}
        check('8: Android offers the app for a blessing\'s type, octet-stream and *.blessing; not for pictures, PDFs, zips, or sharing unknown files',
              all(got[k] == want for k, (_, want) in cases.items()), got)
        # a blessing file from the Files app (it says application/octet-stream for a name it does not know)
        if self.row('Before the new job'):
            pass
        src = getattr(self, 'blessing_file', None)
        if src:
            j = self.files_open(src, 'From Files.blessing')
            self.shot(f'{self.n}-files-blessing'); self.n += 1
            check('8: a .blessing file tapped in the Files app: the app opens it (already here, or the keep sheet)',
                  re.search('already have this blessing|Keep it with your blessings', j) is not None, j[:160])
            self.dismiss_sheet()
            log = self.d.sh("dumpsys activity intents 2>/dev/null | head -0")
        # a file that is not a blessing
        bad = os.path.join(self.out, 'not-a-blessing.bin')
        with open(bad, 'wb') as f:
            f.write(b'PK\x03\x04' + os.urandom(400))
        j = self.files_open(bad, 'Notes.zzz')
        self.shot(f'{self.n}-refusal-not-a-blessing'); self.n += 1
        check('8: a file that is not a blessing: "This file could not be read."', 'could not be read' in j, j[:160])
        self.dismiss_sheet()
        bad2 = os.path.join(self.out, 'fake.blessing')
        with open(bad2, 'w') as f:
            f.write('{"format": "something-else"}')
        j = self.files_open(bad2, 'Fake.blessing')
        check('8: a .blessing that is not one: "This file could not be read."', 'could not be read' in j, j[:160])
        self.dismiss_sheet()
        self.d.sh('rm -f /sdcard/Download/*.blessing /sdcard/Download/Notes.zzz')
        self.d.key('KEYCODE_HOME')

    # ---- 10 ----

    def step10(self):
        def screens(tag):
            self.d.sh(f'am force-stop {PKG}')  # a cold start in the new language and size
            time.sleep(1)
            self.launch()
            self.open_blessing('Comfort before surgery')  # the samples keep their titles in Spanish
            self.d.tap('^Share$|^Compartir$')
            time.sleep(1.5)
            self.shot(f'{self.n}-{tag}-share-sheet'); self.n += 1
            self.d.tap('^Send this blessing|^Enviar esta bendición')
            time.sleep(4)
            self.shot(f'{self.n}-{tag}-link-made'); self.n += 1
            link = self.link_now()
            self.d.key('KEYCODE_BACK')
            time.sleep(1)
            self.back_home()
            self.d.tap('^More|^Settings|^Más|^Ajustes|^Configuración', 10)
            time.sleep(1.5)
            self.d.tap('^Your links|^Tus enlaces', 10)
            time.sleep(1.5)
            self.shot(f'{self.n}-{tag}-your-links'); self.n += 1
            self.back_home()
            # the keep sheet: the contract's first vector, under a new id so it is not "already here"
            v = json.load(open(os.path.join(HERE, '..', '..', 'website', 'protocol-vectors.json')))['vectors'][0]
            d = json.loads(v['plaintext']['utf8'])
            d['id'] = f'big-{tag}-{int(time.time())}'
            l2, _ = self.plant(json.dumps(d, ensure_ascii=False, separators=(',', ':')))
            self.am_link(l2)
            time.sleep(4)
            self.shot(f'{self.n}-{tag}-keep-sheet'); self.n += 1
            self.dismiss_sheet()
        self.d.sh('cmd locale set-device-locale es-US')
        time.sleep(3)
        try:
            screens('es')
        except Exception as e:
            check('10: Spanish screens ran', False, repr(e)[:200])
        dens = re.findall(r'(\d+)', self.d.sh('wm density'))[0]
        self.d.sh('settings put system font_scale 2.0')
        self.d.sh(f'wm density {int(int(dens) * 1.3)}')
        time.sleep(3)
        try:
            screens('es-large')
            self.d.sh('cmd locale set-device-locale en-US')
            time.sleep(3)
            screens('en-large')
        except Exception as e:
            check('10: large screens ran', False, repr(e)[:200])
        finally:
            self.d.sh('cmd locale set-device-locale en-US')
            self.d.sh('settings put system font_scale 1.0')
            self.d.sh('wm density reset')
        check('10: Spanish and the largest sizes captured for the eye', True, 'see the screenshots')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('serial')
    p.add_argument('out')
    p.add_argument('apk')
    p.add_argument('links')
    p.add_argument('requests')
    p.add_argument('--only', default='1,9,5,3,4,6,8')
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    r = Run(a)
    r.fresh()
    order = a.only.split(',')
    for s in order:
        try:
            getattr(r, f'step{s}')()
        except Exception as e:  # one step's failure must not hide the others
            check(f'{s}: ran to the end', False, repr(e)[:400])
            r.shot(f'failed-step{s}')
            try:
                r.d.key('KEYCODE_BACK')
                r.d.launch()
                r.server('start')
            except Exception:
                pass
    with open(os.path.join(a.out, 'made.json'), 'w') as f:
        json.dump({k: v for k, v in r.made.items()}, f)
    with open(os.path.join(a.out, 'summary.json'), 'w') as f:
        json.dump({'device': a.serial, 'checks': results, 'shots': r.shots}, f, indent=1)
    failed = [x for x in results if not x['ok']]
    print(f'== {len(results) - len(failed)} of {len(results)} checks passed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
