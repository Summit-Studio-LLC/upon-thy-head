# Phone session

Steps with the iPhone in hand. Each one says what you should see. Note anything different, with the step number.

## Before you plug in

1. On the Mac, open Xcode > Settings > Apple Accounts and check that your account is there with the Summit Studio LLC team under it (it was on 2026-11-16). The "missing Xcode-Token" message in build logs is about an older Apple ID still saved in the Mac's keychain, not this one. Whether this account can add a new phone to the signing profile is proven only by the first run on that phone.
   You should see: "Summit Studio LLC" listed under the account.
   On the iPhone, turn on Developer Mode before the first run: Settings > Privacy & Security > Developer Mode > On. The phone restarts; unlock it and tap Turn On. (It was off on the iPhone Air on 2026-11-16.)
2. Only the iPhone 12 is in the signing profile today. Any other phone is added on its first run, which needs step 1. The phone on iOS 27.3 is newer than this Xcode (26.2), so it may need an Xcode update first. `phone.sh` says so if it does.

## Install

3. Plug the phone in with a cable, unlock it, and tap **Trust** when it asks about this computer.
4. In Terminal:
   ```
   cd ~/Development/work/summit_studio/projects/upon-thy-head/app
   tool/phone.sh --check --seed --log
   ```
   You should see: "Building (profile)…", then "Installing…", then "Opening…", then the app's log. The first build takes a few minutes.
   - `--check` adds the phone check page and opens it at launch.
   - `--seed` adds the five sample blessings.
   - `--log` keeps the log running and saves each phone check report on the Mac, in `app/build/phone/phone-check-<time>-N.txt`.
   - Press Ctrl-C to stop the log. The app keeps running.
5. If it stops with a one-line message, do what it says and run step 4 again. The usual first-run ones:
   - **Developer Mode is off**: on the phone, go to Settings > Privacy & Security > Developer Mode, turn it on, and let it restart. The switch appears only after Xcode has seen the phone once.
   - **Untrusted developer**: on the phone, go to Settings > General > VPN & Device Management > "Apple Development: NOAH BRIAN ANDERSON" > Trust.
   - **Phone locked**: unlock it and keep it unlocked until the app opens.
   - **Provisioning**: the phone is not in the profile. Do step 1, then run again.
   - **Several phones plugged in**: it lists them. Add `--phone "<name>"`.
6. The phone may ask to find devices on your local network. Either answer is fine. That question comes from Flutter's test tooling, and it does not appear in release builds.

Other runs: `tool/phone.sh` alone installs without the check page. `--release` builds exactly what people would get. `--spanish` opens the app in Spanish. `--report` copies the last report off the phone. `--help` lists everything.

## Phone check (about 3 minutes)

7. The app opens on Phone check, and the checks run one by one. Stay on the page until the last one finishes. iOS asks for the microphone during check 5 and for location during check 9: allow both, with **Allow Once** for location.
   You should see: every check ends with a time or "Failed". "Failed" checks show their error in red.
8. If check 3 offers **Download the en-US model**, tap it and wait for 100 %. Then tap **Run again**.
   You should see: check 3 lists the new engine with its words wrong, time and text. Check 4 then says whether "the new engine without speech-recognition permission (not asked yet)" works.
9. In check 4, tap **Ask for the microphone and speech recognition** and allow both.
   You should see: the speech question in iOS's own wording. Note it word for word (open question 32). Checks 3 and 4 run again, now with the older recogniser as well.
10. To try the new engine with speech refused: go to iPhone Settings > Apps > Upon Thy Head and turn off Speech Recognition. Reopen the app (Settings > Phone check, the last row) and tap **Run again**.
    You should see: check 4 says "(refused): it works", or explains why it could not try.
11. Check 7 shows a moving sky for 20 seconds. Don't touch the screen while it runs.
12. Tap **Copy report** and paste it anywhere (Notes is fine). The Mac also has it in `app/build/phone/`.

## Recording

Go back to the sky. Starting a blessing is "New blessing", then Begin.

13. **Arm's length.** Hold the phone at arm's length and speak a minute-long blessing in a normal voice, with an "um" and a pause of a few seconds. Say Amen.
    You should see: the review page with your words, mostly right. Note what was lost after the pause, the punctuation, and the "um".
14. **Across a room.** Put the phone on a table 3–4 m away and record again at the same volume.
    You should see: the words written as well as possible. Note how many are lost compared with step 13.
15. **Screen stays awake.** Start a recording and don't touch the phone for 2 minutes.
    You should see: the screen stays on and the clock keeps running.
16. **Locking mid-recording.** Record, press the side button to lock, talk for 30 s, unlock, and say Amen.
    You should see: the clock counted the locked time, and the words from while it was locked are there. No Face ID is asked if you were away under a minute.
17. **A call mid-recording.** Record, have someone call you, answer, hang up after 10 s, and go back to the app.
    You should see: "Paused" during the call with the clock stopped, then recording again. After Amen, one blessing with both parts.
18. **Force-quit mid-recording.** Record for 20 s, swipe up to the app switcher and swipe the app away. Open it again.
    You should see: Face ID, then a sheet saying "A recording was kept". The draft holds all but the last couple of seconds.
19. **Playback while locked.** Open a draft's review page, play it, and lock the phone.
    You should see: the audio keeps playing. The lock screen shows nothing about it (no Now Playing card). A call stops it, and it stays stopped.
20. **Language pull-down.** On Begin, tap the language control.
    You should see: the list opens below the control, not over it.

## Lock and privacy

21. **Face ID.** Close the app and open it.
    You should see: Face ID with the reason "Unlocks your blessings.", then the sky with its blessings.
22. **A failed attempt.** Lock the app (leave it for over a minute), then have someone else look at it, or cover your face.
    You should see: "Face Not Recognized", then the passcode option. The sky shows only stars and "For me · Locked" until you unlock.
23. **App switcher.** With blessings on screen, swipe up into the app switcher.
    You should see: the app's card shows the plain sky, never a blessing or its words.
24. **Permission wording.** Note each question's exact words as iOS shows them: microphone, speech, location, Face ID (step 9 covers speech).
25. **Allow Once.** Close and reopen the app, then record a blessing.
    You should see: no location question again. The blessing keeps the place found the first time.

## Sky

26. **Pinch and drag.** On the sky, drag slowly and quickly, pinch in and out, and let go mid-fling.
    You should see: smooth movement that follows your finger, with no stutter. Note anything that feels heavy or slippery.
27. **Release build.** Run `tool/phone.sh --release` and repeat step 26. This build is exactly what people get. It has no phone check page.

## Spanish

28. On the phone: go to Settings > General > Keyboard. Turn on Enable Dictation, and under Keyboards add "Español (Estados Unidos)" or "Español (México)". Wait a minute on Wi-Fi.
29. In the app: Settings > Phone check > **Run again**.
    You should see: check 2 says Spanish "can write now" for one of es-US, es-MX or es-ES. Check 3 then writes the Spanish recording.
30. On Begin, choose Español and record a short blessing in Spanish.
    You should see: Spanish words on the review page. If Spanish still can't be written, you see the audio kept and "could not be written yet".
31. Run `tool/phone.sh --spanish` and look around the app.
    You should see: every word in Spanish. The system questions stay in English unless the phone's own language is Spanish.

## If you have time

32. VoiceOver (Settings > Accessibility): open a polished draft's changes screen and swipe through the changes.
    You should see: each change read as a button with its size, kind, both versions and whether it is kept.
33. Run `tool/phone.sh --report` to copy the last phone check report to the Mac.
