#!/usr/bin/env python3
"""What the app's microphone hears on the emulator, and recordings compared with it.

  tool/android_mic.py prepare FILE OUT [--start S]
        FILE (anything ffmpeg reads) as 32 kHz mono 16-bit samples; pushed into the app as
        files/debug_mic.pcm, a debug build records them in place of the microphone's samples, at
        the microphone's pace (SegmentRecorder.debugSource). The emulator's own way of feeding its
        microphone (gRPC `injectAudio`) crashes emulator 36.5.11 at the first packet, and the
        Mac's microphone would record the room, so this is the known sound.
  tool/android_mic.py compare FED GOT [--offset-max 3] [--json]
        how closely GOT (the app's recording, pulled from the emulator) matches FED: length,
        loudness, the best alignment and the correlation there, and the spectrum's likeness

Needs Python 3 with numpy and scipy, and ffmpeg; `tool/android_mic.py setup` makes a virtual
environment under build/android_mic/ and prints its Python.
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
WORK = os.path.join(APP, 'build', 'android_mic')
RATE = 16000  # what is fed: enough for speech, and every phone records from it


def setup():
    venv = os.path.join(WORK, 'venv')
    if not os.path.exists(os.path.join(venv, 'bin', 'python')):
        subprocess.check_call([sys.executable, '-m', 'venv', venv])
    if subprocess.call([os.path.join(venv, 'bin', 'python'), '-c', 'import numpy, scipy']) != 0:
        subprocess.check_call([os.path.join(venv, 'bin', 'pip'), 'install', '-q', 'numpy', 'scipy'])
    print(os.path.join(venv, 'bin', 'python'))


def pcm(path, start=0.0, seconds=None):
    """The file as 16 kHz mono 16-bit samples (numpy int16)."""
    import numpy as np
    cmd = ['ffmpeg', '-v', 'error', '-ss', str(start), '-i', path]
    if seconds:
        cmd += ['-t', str(seconds)]
    cmd += ['-ac', '1', '-ar', str(RATE), '-f', 's16le', '-']
    return np.frombuffer(subprocess.check_output(cmd), dtype=np.int16)


def prepare(args):
    """FILE as the samples the app's microphone delivers in a debug build (SegmentRecorder.debugSource)."""
    subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-ss', str(args.start), '-i', args.file, '-ac', '1', '-ar', '32000',
                           '-f', 's16le', args.out])
    print(args.out)


def compare(args):
    import numpy as np
    from scipy import signal
    a = pcm(args.fed).astype(np.float64)
    b = pcm(args.got).astype(np.float64)
    out = {'fed_s': round(len(a) / RATE, 3), 'got_s': round(len(b) / RATE, 3)}

    def dbfs(x):
        r = np.sqrt(np.mean(x ** 2)) if len(x) else 0
        return round(20 * np.log10(r / 32768), 1) if r > 0 else -120.0

    out['fed_dbfs'] = dbfs(a)
    out['got_dbfs'] = dbfs(b)
    # alignment: the envelope (20 ms RMS) correlated over shifts up to offset-max seconds
    hop = RATE // 50

    def env(x):
        n = len(x) // hop
        return np.sqrt(np.mean(x[: n * hop].reshape(n, hop) ** 2, axis=1))

    ea, eb = env(a), env(b)
    n = min(len(ea), len(eb))
    best = (-2.0, 0)
    for lag in range(-int(args.offset_max * 50), int(args.offset_max * 50) + 1):
        if lag >= 0:
            x, y = ea[lag:lag + n], eb[:n]
        else:
            x, y = ea[:n], eb[-lag:-lag + n]
        m = min(len(x), len(y))
        if m < 50:
            continue
        c = np.corrcoef(x[:m], y[:m])[0, 1]
        if c > best[0]:
            best = (c, lag)
    out['envelope_corr'] = round(float(best[0]), 3)
    # GOT starts this many seconds into FED (positive) or after a lead-in of silence (negative)
    out['offset_s'] = round(best[1] / 50, 2)
    # the waveform's own correlation at that alignment, refined to the sample
    lag = best[1] * hop
    x = a[lag:] if lag >= 0 else a
    y = b if lag >= 0 else b[-lag:]
    m = min(len(x), len(y))
    x, y = x[:m], y[:m]
    win = 2 * hop
    xc = signal.correlate(y[: RATE * 5], x[: RATE * 5], mode='full', method='fft')
    mid = len(x[: RATE * 5]) - 1
    k = int(np.argmax(xc[mid - win: mid + win + 1])) - win
    if k > 0:
        y = y[k:]
    elif k < 0:
        x = x[-k:]
    m = min(len(x), len(y))
    out['wave_corr'] = round(float(np.corrcoef(x[:m], y[:m])[0, 1]), 3)
    # spectra (Welch), compared in dB over 100 Hz to 4 kHz where speech lives
    f, pa = signal.welch(x[:m], RATE, nperseg=1024)
    _, pb_ = signal.welch(y[:m], RATE, nperseg=1024)
    band = (f >= 100) & (f <= 4000)
    da, db = 10 * np.log10(pa[band] + 1e-12), 10 * np.log10(pb_[band] + 1e-12)
    out['spectrum_corr'] = round(float(np.corrcoef(da, db)[0, 1]), 3)
    # the longest stretch of near-silence inside GOT (a hole), in seconds
    eg = env(b)
    quiet = eg < max(eg.max() * 0.003, 3.0)
    longest = cur = 0
    for q in quiet:
        cur = cur + 1 if q else 0
        longest = max(longest, cur)
    out['longest_quiet_s'] = round(longest / 50, 2)
    if args.segments:
        # each 5 s of GOT, found anywhere in FED: where it is and how well it matches. A pause (a
        # call) shows as one jump in FED's time between two neighbours; a hole as a quiet window.
        segs = []
        w = 250  # 5 s of 20 ms envelope steps
        for s in range(0, len(eb) - w + 1, w):
            g = eb[s:s + w]
            if g.std() == 0:
                segs.append({'got_s': s / 50, 'fed_s': None, 'corr': 0.0})
                continue
            best = (-2.0, 0)
            for k in range(0, len(ea) - w + 1):
                f = ea[k:k + w]
                if f.std() == 0:
                    continue
                c = float(np.corrcoef(f, g)[0, 1])
                if c > best[0]:
                    best = (c, k)
            segs.append({'got_s': s / 50, 'fed_s': best[1] / 50, 'corr': round(best[0], 3)})
        out['segments'] = segs
    print(json.dumps(out) if args.json else '\n'.join(f'{k}: {v}' for k, v in out.items()))


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest='cmd', required=True)
    sub.add_parser('setup')
    f = sub.add_parser('prepare')
    f.add_argument('file')
    f.add_argument('out')
    f.add_argument('--start', type=float, default=0.0)
    c = sub.add_parser('compare')
    c.add_argument('fed')
    c.add_argument('got')
    c.add_argument('--offset-max', type=float, default=3.0)
    c.add_argument('--json', action='store_true')
    c.add_argument('--segments', action='store_true', help='where each 5 s of GOT is found in FED')
    a = p.parse_args()
    {'setup': lambda _: setup(), 'prepare': prepare, 'compare': compare}[a.cmd](a)


if __name__ == '__main__':
    main()
