#!/usr/bin/env python3
"""Give the emulator a PIN and one fingerprint, or take them away again (tool/android_lock.sh).

  tool/android_fingerprint.py SERIAL add PIN      a PIN (adb `locksettings`), then one fingerprint
                                                   enrolled through Android's own Settings screens,
                                                   touched from adb (`emu finger touch 1`)
  tool/android_fingerprint.py SERIAL remove PIN   the PIN cleared (Android removes the fingerprints
                                                   with it) and the lock screen off, as these
                                                   emulators are kept
"""
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from android_ui import Device  # noqa: E402


def add(d, pin):
    d.sh('locksettings set-disabled false')
    print(d.sh(f'locksettings set-pin {pin}').strip())
    d.sh('am start -a android.settings.FINGERPRINT_ENROLL')
    d.wait('PIN', 20)
    # just after boot the PIN field can miss the first typing: tap it and type again
    for _ in range(3):
        time.sleep(1.5)
        if d.has('^PIN area$'):
            d.tap('^PIN area$', 5)
        d.sh(f'input text {pin}')
        d.key('KEYCODE_ENTER')
        try:
            d.wait('^MORE$|^More$|^I agree$|^I AGREE$', 12)
            break
        except TimeoutError:
            pass
    d.wait('^MORE$|^More$|^I agree$|^I AGREE$', 8)
    for _ in range(8):
        if d.has('^(I agree|I AGREE|Agree)$'):
            break
        d.tap('^MORE$|^More$', 5)
        time.sleep(1)
    d.tap('^(I agree|I AGREE|Agree)$', 10)
    d.wait('Touch the sensor', 20)
    for _ in range(30):
        d.adb('emu', 'finger', 'touch', '1')
        time.sleep(0.6)
        d.adb('emu', 'finger', 'remove', '1')
        time.sleep(0.6)
        if d.has('^Fingerprint added'):
            break
    d.tap('^(Done|DONE)$', 10)
    d.key('KEYCODE_HOME')
    prints = re.findall(r'"count":(\d+)', d.sh('dumpsys fingerprint'))
    print(f'fingerprints enrolled: {prints}')


def remove(d, pin):
    print(d.sh(f'locksettings clear --old {pin}').strip())
    d.sh('locksettings set-disabled true')
    print('fingerprint state:', re.findall(r'"count":\d+', d.sh('dumpsys fingerprint')), d.sh('locksettings get-disabled').strip())


if __name__ == '__main__':
    serial, what, pin = sys.argv[1:4]
    (add if what == 'add' else remove)(Device(serial), pin)
