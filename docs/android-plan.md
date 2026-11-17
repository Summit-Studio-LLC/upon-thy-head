# Android: what it needs, and where the hard parts are

Research written 2026-11-16; tasks 1–3 of section 12 built the same day (see **Built so far** in section 12, and **Stand-ins** after it). It is for Noah. It covers everything the iPhone app does with Apple's own code (about 2,000 lines of Swift in `app/ios/Runner/`), the Android equivalent of each, and the order to build them in.

How to read the marks:
- **(Google)** means the claim was checked against Google's own pages, which are linked.
- *(unconfirmed)* means the claim comes from experience, a third-party write-up, or inference. Check it on a phone before relying on it.

---

## 1. The short answer

**Most of it is easy.** The Flutter side (the sky, the screens, the database, the blessing file format, the polish rules, the link) already runs as it is. The Apple-specific parts are about 2,000 lines over nine files, and every one has a plain Android equivalent: recording in parts, the lock, the hidden app-switcher picture, location, sharing, a PDF in Newsreader. Altogether this is about **three to four weeks of building**, plus the Play Store's waiting periods.

**Three things are hard:**

1. **Writing the words down on the phone.** Android has no single engine that does it on every phone, the way iOS does. Google's best answer, ML Kit's speech recognition, is in **alpha** (Google may still change it in ways that break the app). Its everyday mode lists Spanish only as Spain's Spanish, in beta. It works only while the app is on screen. It also sends Google usage statistics (never the audio). See section 3.
2. **Opening a `.blessing` file from other apps.** Gmail, WhatsApp and Samsung's My Files often hand a file over with no file type and sometimes no name. The app has to offer itself for "any file" of that kind and then look inside. It works, but each source app needs testing on a real phone.
3. **Getting onto the Play Store.** Recording with the screen locked needs a "microphone service", which Google reviews: a form plus a video of it in use. A new *personal* account must also run a closed test with 12 people for 14 days before it can publish. An *organisation* account (Summit Studio LLC) avoids that test but needs a D-U-N-S number, which can take up to 30 days.

**The one thing that could change the product:** on most Android phones, good Spanish may only be possible with a **downloaded speech model of about 180–550 MB**. On iPhone that download is an optional upgrade. On a mid-range Android phone it could be the only way Spanish works well. If that is true, Spanish on Android is "download once, with your agreement", not "works on first launch". That needs measuring on a real phone before it is promised anywhere.

---

## 2. Every piece at a glance

Sizes are building time for one capable developer. They include its own tests but not Play review waits.

| Piece | iPhone today | Android equivalent | Risk | Size |
|---|---|---|---|---|
| Words from speech | Apple's new engine, else the older one, on a file after Amen (`OnDeviceSpeech.swift`) | ML Kit GenAI Speech Recognition on the file; Whisper (whisper.cpp) as a download you agree to | **High** | 4–6 days |
| Recording in parts that survive a kill | ADTS AAC parts, joined at Amen (`SpeechChannel.swift`) | `MediaRecorder` writes the same ADTS AAC parts; `MediaMuxer` joins them | Low | 1.5 days |
| Recording with the screen locked | Background audio mode | A foreground "microphone" service with a notification | Medium (Play review) | 1 day + Play form |
| Gives way to a phone call | Audio session interruption | A callback reporting when the system silences the recording | Medium | 0.5 day |
| App lock | Face ID / Touch ID / passcode (`Privacy.swift`) | `BiometricPrompt` with fingerprint, face or PIN | Low | 1 day |
| Hiding contents in recent apps | A plain-sky cover | `setRecentsScreenshotEnabled(false)` (Android 13 and later) | Low | 0.5 day |
| Approximate location, asked once | CoreLocation, reduced accuracy | Coarse location permission only | Low | 0.5 day |
| Share text | Share sheet | Android share sheet | Low | 0.25 day |
| Share PDF in Newsreader | CoreText PDF (`Share.swift`) | Android's `PdfDocument` with the Newsreader font from the app | Low | 1 day |
| Share `.blessing` file | Exported file type | Share through a file provider (a safe way to hand a file to another app) with the app's own file type | Low | 0.5 day |
| Receive `.blessing` file | Scene delegate inbox | Filters for the app's type, for "unknown binary" files and for "share to"; then check the contents | **Medium-high** | 2 days |
| Listening back while locked | Background audio | A second foreground service ("media playback") with a notification | Medium | 1 day |
| Language menu | Native iOS pull-down (`LanguageMenu.swift`) | A menu drawn in Flutter (a non-iOS path already exists in the Dart code) | Low | 0.5 day |
| Keep screen awake | `isIdleTimerDisabled` | A keep-screen-on flag on the window | Low | 0.1 day |
| First-run permissions | Four rows: microphone, speech, location, Face ID | Four rows: microphone, notifications, location, lock. No speech permission | Low | 1 day |
| The sky (shader and painting) | Impeller on Metal | Impeller on Vulkan (Android 10 and later), else OpenGL | Medium | 1 day of checking |
| Database | `sqlite3` using the system SQLite | Must bundle SQLite on Android (see 8.1) | Medium (blocks the first build) | 0.25 day |
| Backup exclusion | Excluded from iCloud | Backup rules file, plus the no-backup folder for audio | Low | 0.25 day |
| Phone check page | `PhoneCheck.swift` | A smaller Android version | Low | 1 day |
| Store paperwork | App Store Connect | Play Console: Data safety, two foreground-service declarations with videos, target API 36 | Medium | 1 day + waits |

---

## 3. Writing speech down on the phone

The rule: the audio never leaves the phone. On iPhone the app records the whole blessing to a file and writes it out after Amen. Android has three ways to do the same.

### 3.1 Android's own recogniser (`SpeechRecognizer`)

- **On-device only:** `createOnDeviceSpeechRecognizer` exists from Android 12 (API 31). Its companion check, `isOnDeviceRecognitionAvailable`, says when there is none. **(Google)** [SpeechRecognizer reference](https://developer.android.com/reference/android/speech/SpeechRecognizer)
- **"Offline only" for the ordinary recogniser** (`EXTRA_PREFER_OFFLINE`): Google's own page says "depending on the recognizer implementation, these values may have no effect." It cannot be relied on. **(Google)** [RecognizerIntent](https://developer.android.com/reference/android/speech/RecognizerIntent)
- **From a file:** possible only from Android 13 (API 33), through `EXTRA_AUDIO_SOURCE`. Google says: "if … the recognizer does not support this feature, the recognizer will open the mic". There is no way to ask beforehand whether the phone honours it. **(Google)**
- **Long speech and pauses:** a "segmented session" mode (Android 13 and later) returns results in pieces split at silences, if the phone's recogniser supports it. **(Google)** By default the recogniser stops after a pause; it is built for short commands *(unconfirmed, widely reported)*.
- **Which engine answers** depends on the maker: Google's speech services on Pixels, often Samsung's own on Galaxy phones *(unconfirmed)*.
- **Languages:** whatever the phone has downloaded. `checkRecognitionSupport` and `triggerModelDownload` (Android 13 and later) can ask for more, sometimes with a prompt to the person. **(Google)**

**Verdict:** not the main path. It acts differently by maker, may quietly ignore the file and listen to the room instead, and on older phones cannot take a file at all.

### 3.2 ML Kit GenAI Speech Recognition (Google's on-device library)

From Google's page, last updated 2026-11-14: [ML Kit GenAI Speech Recognition](https://developers.google.com/ml-kit/genai/speech-recognition/android). All of the following is **(Google)** unless marked.

- **Status: alpha**, version `1.0.0-alpha2` (26 October 2026). "Not subject to any SLA or deprecation policy. Changes may be made … that break backward compatibility." It needs Kotlin 2.3. [Release notes](https://developers.google.com/ml-kit/release-notes)
- **Two modes:**
  - **Basic:** "the traditional on-device speech recognition model, similar to the SpeechRecognizer API". It runs on "Android devices using API level 31 and higher", so Android 12 and later.
  - **Advanced:** runs on Gemini Nano (Google's on-device AI model), with better quality. It is only on the Pixel 10 and 11 series and phones with recent top-end chips (Snapdragon SM8750 and later, Dimensity 9400-class, Exynos 2600), such as the Galaxy S26, Z Flip8 and Z Fold8. It does not work on phones with an unlocked bootloader.
- **From a file: yes.** `AudioSource.fromFile()` transcribes "a whole pre-recorded file" and "automatically decodes" M4A, so the app's existing `.m4a` goes straight in. In this one-shot mode it "transcribes it faster than real time" and returns a final result for each stretch of speech.
- **Languages:**
  - Advanced: `en-US` and `es-ES`.
  - Basic: `en-US`, and `es-ES` marked **beta** ("may have a slightly higher word error rate").
  - **There is no `es-US` or `es-MX` in either list.** Google adds "Additional locales are available", without naming them. So the Spanish of a family from Mexico or Latin America would go through Spain's Spanish model, with unknown quality *(unconfirmed)*.
- **Only while the app is in front:** "inference is permitted only when the app is the top foreground application. Using the API … including using a foreground service, will result in `BACKGROUND_USE_BLOCKED`." [GenAI overview](https://developers.google.com/ml-kit/genai). Google says this of the GenAI APIs as a group. Whether it also binds Basic mode *(unconfirmed)*, assume it does. So if someone says Amen and locks the phone at once, the writing waits until they open the app again. The iPhone app already retries quietly at launch and on the review page, so the design holds.
- **Daily limit:** each app has a usage quota, with a "per app battery use quota" (for example, daily). The size of that limit is not published. Several long blessings in a day might hit it *(unconfirmed)*.
- **On the phone: yes.** "Input, inference, and output data is processed locally." The model is downloaded once from Google. That download needs the internet, but no audio is sent.
- **But ML Kit does report to Google:** device model, app version, per-install identifiers, timings, input and output *sizes*, error codes and "configured languages", for "diagnostics and usage analytics". The words and the audio are not on that list. It has to be declared on the Play Data safety form, and no off switch was found *(unconfirmed)*. [ML Kit data disclosure](https://developers.google.com/ml-kit/android-data-disclosure)
- **Pauses and paragraphs:** the iPhone app starts a new paragraph after a two-second silence, using the time of each word. ML Kit gives word times **only when streaming**, and asking for them on a file throws an error. Streaming a file means feeding it at real-time speed, so a 15-minute blessing would take 15 minutes. So on Android, paragraphs must come from where ML Kit ends each stretch of speech, or from the app finding silences in the audio itself *(design inference)*.
- **Length:** no limit on file length is documented. A 20-minute file has not been tried by anyone I could find *(unconfirmed)*.

### 3.3 A model the app downloads: Whisper

OpenAI's Whisper, run by **whisper.cpp** (MIT licence; it has an Android example). The figures below are from the project's own files. [whisper.cpp](https://github.com/ggml-org/whisper.cpp), [model files](https://huggingface.co/ggerganov/whisper.cpp/tree/main)

| Model | File | Notes |
|---|---|---|
| base, quantised (q5_1) | 57 MiB | fast; weaker on Spanish *(unconfirmed)* |
| small, quantised (q5_1) | 181 MiB | the likely middle choice |
| large-v3-turbo, quantised (q5_0) | 547 MiB | the same model the iPhone research picked; best quality |
| medium, quantised (q5_0) | 514 MiB | |

(A "quantised" file is the same model stored with smaller numbers, so it is smaller and faster for a small loss of accuracy.)

- **Speed on mid-range Android phones: not confirmed.** I found no first-hand measurement I trust:
  - One benchmark found the same Whisper model up to 51 times faster in a different runtime, sherpa-onnx, than in whisper.cpp on Android ([VoicePing](https://voiceping.net/en/blog/research-offline-speech-transcription-benchmark/)).
  - Another blog claims faster than real time for base on a Pixel 6a, with vague method.
  - Whisper on Android mostly runs on the main processor. Expect "small" to take a few minutes for a 10-minute blessing on a mid-range phone, and turbo to be too slow there *(unconfirmed)*.
- **Spanish:** Whisper is trained on many languages and handles Latin American Spanish *(unconfirmed for this use; the iPhone research found community scores of 7–15 % word error for turbo)*.
- **A known Whisper fault:** during long silences it can write words that were never said *(widely reported, unconfirmed here)*. For a record whose promise is "exactly as spoken", silences would have to be cut out before the file goes to Whisper.
- **What it avoids:** it sends no usage statistics, depends on nothing from Google, and keeps working if Google changes ML Kit.
- **Runtime:** **sherpa-onnx** (Apache 2.0 *(unconfirmed)*) runs the same Whisper models and was much faster in the one comparison above. Try both before choosing.

### 3.4 Recommendation

**Main path: ML Kit GenAI Speech Recognition, run on the recorded file after Amen.** Use Advanced mode where the phone has it, and Basic otherwise. This is the closest match to the iPhone design (a file in, words out, on the phone), needs no download for English on most phones, and is Google's own library. Hide it behind one small Kotlin class with the same `transcribe` method the iPhone has, so it can be swapped out if Google changes it.

**Fallback: Whisper, downloaded only with the person's agreement,** the same way the iPhone ruling works. Offer it when:
- ML Kit says the phone cannot do the language, or
- the language is Spanish and the phone only has Basic mode, if measuring shows Basic's beta Spanish is not good enough.

Start with **small (181 MiB)**. Offer **turbo (547 MiB)** only on phones with 8 GB of memory or more, if it proves fast enough. When neither engine can do it, keep the recording and say the words will be written later, exactly as iPhone does.

**Must be measured on a real phone before trusting it** (on a Pixel 10 and on a mid-range Galaxy A):
1. A 10-minute and a 20-minute blessing, read in English and in Mexican Spanish: words wrong per hundred against a hand-typed copy, for ML Kit Basic, ML Kit Advanced, Whisper small and Whisper turbo.
2. How long each takes, and how hot the phone gets.
3. Whether ML Kit's one-shot file mode finishes a 20-minute file, and what it does with 5–10 second pauses (does it drop words after a pause, or split cleanly?).
4. With the phone in airplane mode after the model is downloaded: does it still work? (This proves the audio does not need the network.)
5. Locking the phone straight after Amen: confirm `BACKGROUND_USE_BLOCKED`, and that the retry on reopening works.
6. Three or four long blessings in a day: does the daily quota bite?
7. What ML Kit reports for `es-US` and `es-MX` (the "additional locales").

---

## 4. Recording

**Surviving a kill.** Android's `MediaRecorder` can write **AAC in ADTS form directly** (`OutputFormat.AAC_ADTS`, there since Android 4.1). **(Google)** [MediaRecorder.OutputFormat](https://developer.android.com/reference/android/media/MediaRecorder.OutputFormat). This is the same frame-by-frame format the iPhone app chose so that a part cut off mid-write can still be read. The parts can be joined into an `.m4a` without re-encoding using `MediaMuxer` *(confident, not re-checked)*. Recovery at launch then works as on iPhone. How much a kill loses depends on how often Android writes to disk *(measure; iPhone loses about 2 seconds)*.

**With the screen locked.** The app must run a **foreground service of type "microphone"**, with a notification showing while it records. **(Google)**
- It needs the manifest type `microphone`, the permission `FOREGROUND_SERVICE_MICROPHONE`, and the microphone permission already granted.
- It must be started **while the app is on screen**: "you cannot create a microphone foreground service while your app is in the background." Pressing Begin satisfies that.
- [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)

**The notification.** On Android 13 and later, the notification permission can be refused. The service still runs; its notification then shows only in the system's task manager, not in the notification shade. **(Google)** [Notification permission](https://developer.android.com/develop/ui/views/notifications/notification-permission). So the notification permission is *nice to have*, not required for recording.

**Giving way to a phone call.** On Android, "the call always receives audio". Any other app recording at the same time "receives silence". **(Google)** [Sharing audio input](https://developer.android.com/media/platform/sharing-audio-input). The recorder does not stop. It records silence, and the app learns this through a callback (`AudioRecordingCallback`; "capture silenced or unsilenced"). The Android version should:
1. watch that callback,
2. close the current part when silenced (as iPhone does),
3. start a new part when the sound comes back,
4. send the same `paused` event to Flutter.

The details of the callback under `MediaRecorder` versus `AudioRecord` need a test with a real call *(unconfirmed)*.

**Play Store.** For apps targeting Android 14 and later, Play Console asks for a declaration of each foreground service type: a description, plus **a video link** showing "the user initiate the microphone actively recording audio". **(Google)** [Play: foreground service requirements](https://support.google.com/googleplay/android-developer/answer/13392821). Listening back while locked needs a second declaration, "media playback", also with a video.

**Listening back while locked** needs a media-playback foreground service, and therefore a playback notification with controls. That conflicts with Claude's choice of "no Now Playing information on the lock screen" for iPhone. On Android a visible notification during background playback is required *(standard Android behaviour; see question 4)*.

---

## 5. The app lock and recent apps

- **Unlock:** Android's `BiometricPrompt` (from AndroidX) allows "fingerprint or face, or the device PIN, pattern or password" in one prompt (`BIOMETRIC_STRONG | DEVICE_CREDENTIAL`). The combination is limited on Android 10 and older. **(Google)** [Biometric authentication](https://developer.android.com/identity/sign-in/biometric-auth)
- **Face unlock on many phones does not count.** Outside recent Pixels, face unlock is usually rated "weak" or "convenience", so the prompt offers fingerprint or PIN instead *(unconfirmed per phone)*. The settings row should say "Screen lock" or "Fingerprint", not "Face ID", by what the phone reports.
- **Locks after 60 seconds away, never during a recording:** this is the same Dart logic as iPhone. The native side only reports when the app left and came back, through Android's lifecycle events.
- **Recent apps:** `setRecentsScreenshotEnabled(false)` (Android 13 and later) tells the system never to snapshot the app. It shows the window background instead, which can be the sky colour. **(Google)** [Activity reference](https://developer.android.com/reference/android/app/Activity#setRecentsScreenshotEnabled(boolean))
  - On Android 12 the only tool is `FLAG_SECURE`, which also blocks screenshots. That is a reason to make **Android 13 the floor** *(see section 11)*.
  - Unlike iOS, a custom picture (the plain-sky cover image) cannot be placed in the recent-apps view; only a plain colour *(unconfirmed but widely reported)*.

---

## 6. Approximate location, asked once

Ask only for `ACCESS_COARSE_LOCATION`. Android then never offers precise location. From Android 11, the system's own dialog offers "Only this time", which matches the iPhone's suggested "Allow Once" *(confident, not re-checked)*. A single reading from Android's location service, rounded to a tenth of a degree, is all that is needed. No Google Play services dependency is necessary. Low risk, half a day.

---

## 7. Sharing

**Text:** the standard share sheet. Easy.

**PDF:** Android's `PdfDocument` draws pages with the same drawing tools as the screen and accepts a font file. Newsreader can be loaded from the Flutter assets, so the PDF matches iPhone's *(confident; Newsreader's variable weight axis needs checking)*. Port `Share.swift`'s layout code: about a day.
- One difference: Android's share sheet does not reliably say when it has closed *(unconfirmed)*. The iPhone app deletes the shared file when the sheet closes; on Android, clean the share folder at the next launch and when the app returns to the front. This is already done at launch on iPhone (`clean`).

**Sending a `.blessing` file:** written to a private folder and handed over through a `FileProvider` with the MIME type `application/vnd.uponthyhead.blessing`. Easy.

**Receiving a `.blessing` file** is the fiddly part:
- **Filters:** the app declares filters for "open" (`VIEW`) on:
  - its own type,
  - `application/octet-stream` (the "unknown binary file" type),
  - and, as a safety net, files whose name ends in `.blessing`.
- **No type, no name:** Gmail attachments arrive as `application/octet-stream` with a content address that carries **no file name or extension** *(community reports, several years old; unconfirmed today)*. Some Samsung file managers send no type at all *(same)*.
- **The cost:** the app may appear in the "Open with" list for any unknown file. That is acceptable only because the app reads the first bytes and refuses anything that is not `"format": "upon-thy-head/blessing"`, with the existing message "This file could not be read." It also means "Open with Upon Thy Head" could be shown for a ZIP or other binary file; the strict reader handles it.
- **Share into the app:** add `SEND` too, so "Share → Upon Thy Head" works from WhatsApp and Gmail, whose own "open" button may not offer the app.
- **What carries over from iPhone:** the rest (strict reading, not while locked, not during a recording, read first on first launch) is Dart and does not change.
- **Each source must be tried on a real phone:** Quick Share's received-file notification, the Files app, Gmail, WhatsApp and Samsung My Files.

**Quick Share with iPhone (AirDrop):** Google's own list of Android phones that can send to and receive from an iPhone **(Google)** [Quick Share with iPhone](https://www.android.com/quick-share/with-iphone/):
- **Pixel:** 10, 10 Pro, 10 Pro XL, 10 Pro Fold, 10a; 9, 9 Pro, 9 Pro XL, 9 Pro Fold, 9a; 8a.
- **Galaxy:** S26, S25 and S24 series; Z Flip7 and Z Fold7; Z Flip6 and Z Fold6; Z TriFold.
- **Motorola:** razr fold 2026.

The iPhone must set AirDrop to "Everyone for 10 Minutes". Nothing in the app makes this work or not: the file arrives as a file. A `.blessing` file sent from Android lands in the iPhone's AirDrop prompt and opens in the app by its extension *(unconfirmed; test)*.

---

## 8. Storage, backup, privacy, Play rules

### 8.1 The database: a first-build blocker

The app tells the `sqlite3` package to use the system's own SQLite (`source: system` in `pubspec.yaml`). On Android, apps are not allowed to load the system's private SQLite library *(confident: Android 7 and later block non-public system libraries)*. The package's options are per project, not per platform (only the library *name* can vary by platform) **(package docs, `doc/hook.md`)**. So the project has to switch to the package's bundled SQLite for all platforms, or build SQLite from source. That is a small decision for iPhone too. It is the first Android task because nothing runs without it.

**Done (task 1):** every platform now uses the package's bundled SQLite (`pubspec.yaml`). An iPhone install made with the system's SQLite opens unchanged: the upgrade replay (section 12, task 1) kept every row, tag and change byte for byte.

### 8.2 Backup

Android backs apps up to Google Drive by default. Turn that off for the app (`allowBackup="false"`), and add backup rules that exclude everything. **(Google)** [Auto Backup](https://developer.android.com/guide/topics/data/autobackup)
- Google notes that on some makers' phones, turning backup off **does not stop phone-to-phone transfer** when someone moves to a new phone. **(Google)**
- Keep the audio in the app's "no backup" folder as a second guard.
- Whether the blessings themselves (the words) should transfer to a new phone is a product question (question 6).

### 8.3 Play Data safety form

On-device work does not count as "collecting". But ML Kit's usage statistics do: "App info and performance" and "Device or other IDs", as diagnostics **(Google, ML Kit data disclosure above)**. With ML Kit, the form cannot say "No data collected". With Whisper only, it could.

### 8.4 Target API

New apps and updates must target **Android 16 (API 36)** from 31 August 2026. **(Google)** [Target API requirements](https://developer.android.com/google/play/requirements/target-sdk). Targeting 36 brings two changes:
- **Edge-to-edge is enforced:** the app draws under the status and navigation bars. Flutter handles this, and the sky already fills the screen; check the bottom rings against the gesture bar. **(Google)** [Android 15 changes](https://developer.android.com/about/versions/15/behavior-changes-15)
- **Predictive back is on:** the system's back gesture animates and the old back callback is no longer used. **(Google)** [Android 16 changes](https://developer.android.com/about/versions/16/behavior-changes-16)
  - **This matters for the recording screen.** A back swipe must never end or discard a recording. *Correction (task 2):* back is simply **blocked** while a recording is live, not sent to Discard; Discard stays a deliberate tap, as on iPhone. On every other layer back does what the iPhone's close or swipe does (list, reading, review, Settings, sheets, the recording screen when idle), and on the home sky it leaves the app.

### 8.5 16 KB page size

Google Play requires native code to work on phones with 16 KB memory pages (needs NDK r28 or later). **(Google)** [Page sizes](https://developer.android.com/guide/practices/page-sizes). Flutter 3.44 builds are fine *(unconfirmed)*. The SQLite library and whisper.cpp or sherpa-onnx must be built for it. The Pixel_10_Pro emulator on this Mac already runs a 16 KB system image, so this can be proven here.

**Checked (task 1):** the debug APK passes `zipalign -c -P 16`, and the native libraries' LOAD segments are aligned at 16 KB (SQLite, dartjni) or 64 KB (Flutter). It runs on the 16 KB emulator.

---

## 9. The first run and permissions

On iPhone the screen "A few things first" has four rows: Microphone, Speech recognition, Location, Face ID. On Android:

| Row | Android | When it is asked |
|---|---|---|
| Microphone | One system question; "While using the app", "Only this time", "Don't allow" | On the row, as now |
| Speech recognition | **No such permission on Android.** ML Kit needs none. | Drop the row. If a model download is needed, that is its own question later, with its size |
| Notifications | Android 13 and later asks; refusing does not stop recording (section 4) | Replace the speech row: "So you can see that it is still recording when the phone is locked." |
| Location | One system question, approximate only | On the row, as now |
| Screen lock | **No system question.** The prompt simply appears when unlocking. | The row just asks to turn the lock on, and proves it with one unlock |

So the screen keeps four rows. Speech becomes Notifications, and "Face ID" is named for what the phone has ("Fingerprint", "Screen lock"). The same "Hey, there are a couple of things we need" flow still works. Android also stops asking after two refusals and sends the person to Settings, which the "off" state of each row already handles.

**Now (stand-in):** Android shows these four rows (Microphone, Notifications, Location, Screen lock) as plain information, each ending "Not available on this phone yet.", with Continue open and a lede that promises nothing ("This is what the app will ask for. None of it can be turned on here yet."). The practice recording is skipped because there is no microphone. Each row becomes a real question in its own task (6, 11, 12).

---

## 10. The sky

- **Renderer:** Impeller (Flutter's renderer) runs on Vulkan (a modern graphics interface) on Android 10 and later, and falls back to the older OpenGL path on phones without Vulkan. **(Google)** [Impeller](https://docs.flutter.dev/perf/impeller)
- **Concerns with `sky.frag`:**
  - It already samples the Milky Way by hand because Impeller's own filtering came out too bright on iPhone. Android GPUs (Adreno, Mali, Xclipse) may differ again. Compare screenshots against iPhone.
  - It declares `precision highp float`. Mali and older Adreno chips handle precision differently, which can cause banding in the glow *(unconfirmed)*.
  - The 4K Milky Way texture costs about 64 MB of graphics memory uncompressed *(arithmetic, if 4096×4096 RGBA)*. That is fine on 6 GB phones and tight on 3–4 GB ones.
  - Android emulators have had trouble with Vulkan; for example, [flutter#148481](https://github.com/flutter/flutter/issues/148481) reports emulator crashes with Vulkan validation layers. Judge looks and speed only on a real phone.
- **Done (task 3):** on the Pixel_10_Pro emulator the sky's average colour matches the iPhone simulator's within one level per channel on home, list, zoomed in, ruler, reading, Settings and after a restart (`design/sim/android/pair-*.png`). Real graphics chips are still task 15's.
- **Uniforms packed (2026-11-16):** `sky.frag` now passes its numbers as six `vec4`s instead of 18 loose uniforms. Impeller on Metal gives each uniform its own buffer and the iOS 17 simulator allows only 14, which was the iOS 17.4 simulator crash (Q61). The iOS 26 look is unchanged (screenshots before and after differ by under 0.1 %).
- **Floor:** Android 13 (see section 11). Treat phones with at least 4 GB of memory and a 2021-or-newer chip as the low end to test *(judgement)*.

---

## 11. What to decide before starting

1. **Minimum Android version: recommend Android 13 (API 33).** ML Kit speech needs 12 (API 31); hiding the app in recent apps cleanly, the notification permission and the platform recogniser's file input all arrive in 13. Android 13 is now three years old *(the share of phones on 13 or later was not checked against a first-hand source)*. Android 12 would mean screenshots are blocked whenever the lock is on.
2. **Phones to support:** any phone on Android 13 or later with Google Play. Test on two (section 13). Phones without Google Play (Huawei, some Amazon tablets) are out, because ML Kit needs it *(unconfirmed)*.
3. **Whether Android may launch after iPhone.** Recommended: yes. The Play Store's own waits (D-U-N-S, the foreground-service review, or the 14-day closed test) add 2–5 weeks that no amount of building shortens.
4. **The Play account:** personal (12 testers for 14 days) or Summit Studio LLC as an organisation (D-U-N-S; no tester rule) *(the exemption for organisations comes from third-party guides; Google's page speaks only of personal accounts created after 13 November 2023)*. **(Google)** [Testing requirements for new personal accounts](https://support.google.com/googleplay/android-developer/answer/14151465)

---

## 12. Build order (tasks of about half a day)

Each task has a "proved by" line: what shows it works. The Mac emulators are enough up to task 14; the rest needs a real phone.

### Built so far (2026-11-16)

Screenshots are in `design/sim/android/`; the scripted run is `app/tool/android_tests.sh` (boots the emulator, runs `integration_test/android_test.dart` in two parts with a real kill between, every step under a time limit, and shuts the emulator down).

- **Task 1, done.** `app/android/`: package `dev.summitstudio.uponthyhead`, minimum API 33, target and compile 36; adaptive icon with a themed (monochrome) layer from `design/icon/final` (`tool/android_icons.sh`); a dark launch with the icon on the sky's ground colour; upright on phones, free on tablets (smallest width 600 dp or more); backup off. SQLite bundled (8.1); 16 KB checked (8.5).
  - Proved by: the app opens on Pixel_10_Pro (Android 17) and Pixel_3a (Android 14) with the five samples; the launch frames never go white (`01-launch-frames.png`); the launcher icon, normal and themed (`08`–`11`); the iPhone upgrade replay: the committed build seeded with data still in the WAL, then this build installed over it, gave identical rows, tags and changes (md5), `integrity_check` ok, `user_version` 6, and the app opened on "Five blessings since June 2024" (`28-ios-upgrade-replay.png`).
- **Task 2, done.** Edge to edge (the bars are transparent; Flutter reports their sizes as padding, so the rings clear the gesture bar); back and predictive back on every layer (8.4); Android's own selection handles and copy menu on the review page (`27-review-selection-handles.png`); the fonts are the app's own (Newsreader), with Roboto standing in for SF Pro, which may not ship on Android.
  - Proved by: `android_test.dart` on Pixel_10_Pro: the list, zoom by pinch, the ruler, reading to the end, editing a title with the keyboard up (the field stays above it), the delete question closed by back, a deletion confirmed, Settings, the recording screen; back from each; then the app killed and reopened with the edit kept and the deletion gone. The same test passes on the iPhone simulator (`--ios`) for the side-by-side shots. Spanish by the emulator's language (`12`–`14`), the largest font and display size (`15`–`25`; two layouts were fixed for it: list rows overlapped, and the Settings language row overflowed).
- **Task 3, done.** See section 10. Proved by `pair-*.png`.

### Stand-ins (what Android says until each task lands)

Every iPhone channel has an Android answer in `MainActivity.kt` (`NotYet`) that means "this phone cannot", never "done", and `lib/not_yet.dart` names the same list on the Dart side. Nothing crashes and nothing pretends.

| Stand-in | What the person sees | Replaced by |
|---|---|---|
| Recording and speech | The recording screen opens with Begin dimmed and "Recording is not available on this phone yet."; first run's practice is skipped | Tasks 4–10 |
| App lock and recent-apps cover | Settings shows the lock switch off with "The lock is not available on this phone yet."; **recent apps shows the sky and blessings** | Task 11 |
| Location | Every blessing uses the Salt Lake Temple; Settings says so | Task 12 |
| Sharing | The reading page has no share button, so no link or file is sent from Android. The link's cryptography is already real (`LinkChannel.kt`: AES-256-GCM from `javax.crypto`, stop tokens wrapped by an Android Keystore key, proved against `website/protocol-vectors.json` on the emulator by `integration_test/link_test.dart`); the share channel answers `link` with not-yet | Task 13 |
| Receiving `.blessing` files | Nothing registered | Task 14 |
| Receiving a link | The manifest has the verified `https://uponthyhead.app/b/` filter and `MainActivity` hands the link to Dart as iPhone does, but Android only opens it in the app once the site serves `/.well-known/assetlinks.json` with the release key's fingerprint; until then the link opens the web page | When the site goes live |
| Listening back | No player on the review page | Task 18 (and the plain player before it) |
| The phone check page (test builds) | Answers "unavailable" | Its own task, not yet numbered |
| The recording-language menu | Tap to cycle languages (Flutter has no menu matching iOS's) | With the recording tasks |
| First-run wording | The lede and the location line say what Android will do, not "Tap Allow" (`lib/strings.dart`, `permsLedeNotYet`, `locationWhyAndroid`) | When each row becomes a real question |

**Wording still written for iPhone** and needing an Android version when its feature lands (all in `lib/strings.dart`; iPhone's wording stays as is): `noPasscode`, `asFileHint` ("another iPhone"), `faceIdWhy` and the Face ID / Touch ID names, `settingsFor`, `openSettings`, the phone check's strings, the speech row's strings, `stillNeeded`.

### The plan

1. **Make the Android project and switch SQLite to the bundled build.** Proved by: the app opens on the Pixel_10_Pro emulator (Android 37, 16 KB pages) and shows the five samples behind the test flag; iPhone still builds.
2. **Edge-to-edge and back gesture.** Proved by: the rings clear the gesture bar on the emulator; a back swipe while recording does nothing; a back swipe on review returns as on iPhone.
3. **The sky on Android.** Proved by: emulator screenshots of home, zoomed and recording beside the iPhone simulator's, with no clear difference in brightness. (Repeat on the real phone in task 15.)
4. **Recording to ADTS parts and joining them.** Proved by: an emulator recording from the Mac's microphone plays back; `seconds` matches.
5. **Recovery after a kill.** Proved by: start a recording, force-stop the app from adb (`am force-stop`), reopen it, and "recovered" shows with the length lost under 3 s.
6. **The microphone foreground service and notification.** Proved by: recording continues with the emulator screen locked for 5 minutes, and the notification shows.
7. **Giving way to a call.** Proved by: the emulator's simulated incoming call (`adb emu gsm call`) pauses the ring, a new part starts after hang-up, and the joined file has both halves.
8. **ML Kit Basic transcription on a file (English).** Proved by: a fixed English recording (the `debugFeed` file the iPhone tests use) comes back as the expected words on the emulator *(whether ML Kit Basic runs on the emulator is unconfirmed; if not, this moves to the real phone)*.
9. **Spanish and the engine choice** (`engine` method: Advanced, Basic or none). Proved by: `describe` reports each mode's status and locales; "unavailable" is handled exactly as on iPhone.
10. **Paragraphs from pauses.** Proved by: a recording with 3-second gaps gives paragraph breaks where iPhone does.
11. **The app lock and recent apps.** Proved by: on the emulator, a fingerprint enrolled and touched from adb (`adb emu finger touch 1`) unlocks; locks after 60 s away; never locks during a recording; the recent-apps view shows plain colour.
12. **Location and the first-run screen.** Proved by: a fresh install walks the four rows and each system question; refusing location falls back to the Salt Lake Temple.
13. **Share text, PDF and `.blessing`.** Proved by: the PDF opens in Files with Newsreader embedded; a `.blessing` file opens on a second emulator.
14. **Receiving a `.blessing` file.** Proved by: opening from Files and from a `content://` source with `application/octet-stream` works on the emulator; a non-blessing binary file gets "This file could not be read."
15. **Real phone: speech measurements** (section 3.4, items 1–7). Proved by: a table of error rate and time per engine and language, written into this document.
16. **Whisper as a download you agree to** (only if 15 says it is needed). Proved by: on the mid-range phone, a 10-minute Spanish blessing written within a time Noah accepts, in airplane mode.
17. **Real phone: receiving from Gmail, WhatsApp, Quick Share and Samsung My Files; AirDrop to and from an iPhone.** Proved by: each source opens the keep sheet.
18. **Listening back while locked** (media service). Proved by: playback continues with the phone locked.
19. **Real call, real lock, real kill on the phone.** Proved by: the iPhone phone-session steps, run again on Android.
20. **Play Console:** listing, Data safety, the two foreground-service declarations with videos (filmed from task 19), closed test. Proved by: the build accepted on the closed-testing track.

Tasks 15–17 can start as soon as a phone arrives. Do task 15 early, because its result decides whether task 16 is needed.

---

## 13. Testing here, and which phone to get

**Provable on this Mac's emulators** (Pixel_10_Pro is Android 17, API 37, with Google Play and 16 KB pages, 1280×2856 at 480 dpi; Pixel_3a_API_34 is Android 14; Pixel_7_API_31 is Android 12, **below the minimum**, so it cannot install the app and is not used):
- *The Pixel_10_Pro's storage is nearly full* (about 500 MB free). A second install of the debug APK beside the first does not fit, so `tool/android_tests.sh` installs once and attaches to the installed app for the restart part. Growing its data partition in Device Manager would remove the problem.
- Layout, the back gesture, the database, the first-run screens.
- Recording from the Mac's microphone (`hw.audioInput=yes` on all three); a kill and recovery; locked-screen recording; a simulated incoming call.
- Fingerprint unlock and PIN fallback (a fingerprint can be enrolled and "touched" from adb *(standard emulator feature)*).
- The recent-apps view; sharing to Files; opening a file with no type.
- Some Android licences on this Mac are not accepted yet (`flutter doctor --android-licenses`). The builds for tasks 1–3 did not stop on one, so none was accepted.
- The keyboard: the emulator's keyboard follows the **system** dark theme; an app cannot ask for a dark keyboard on Android. With the system dark, it is dark (`design/sim/android/26-review-keyboard-dark-theme.png`).
- Themed icons: the Pixel launcher themes only icons on the home screen, never the app drawer, and the gold ring in the dock marks a suggested app, not the icon.

**Probably not provable on an emulator:**
- ML Kit Advanced: it needs Gemini Nano on a supported phone, and Google says it refuses unlocked bootloaders (emulators look unlocked) *(inference)*.
- ML Kit Basic: unknown; try it in task 8.
- Real speech quality, heat, speed and the daily quota.
- The look and speed of the sky on a real graphics chip.
- Gmail, WhatsApp and Samsung My Files hand-offs.
- Quick Share and AirDrop.
- A real phone call; a maker's battery saver killing the service.

**Which phones:** *(prices and exact models unconfirmed)*
1. **Pixel 10** (or Pixel 10 Pro). It is on Google's list for both ML Kit Advanced speech and AirDrop with iPhone, it is Google's reference phone, and it gets updates first. Buy this one.
2. **A mid-range Samsung Galaxy A** (A26 or A36, about $250–400): the phones most families actually own. It tests ML Kit Basic only, Whisper's speed, Samsung's My Files and One UI's battery management. Borrow one if possible.

If only one phone: the Galaxy A, because it is where the speech plan is most at risk. The Pixel can be borrowed later for AirDrop.

---

## 14. Open questions for Noah (most important first)

1. **Spanish on Android may need a download.** If measuring shows Google's built-in Spanish is not good enough on ordinary Android phones, is it acceptable that Spanish on those phones asks to download about 180–550 MB once (Wi-Fi, with consent) before the first Spanish blessing can be written? The recording would still be kept and written after the download.
2. **Google's usage statistics.** Google's speech library reports app and device details and timings (never the audio or the words) to Google, and the store listing must say so. Is that acceptable? The alternative is Whisper only, at the cost of a download for everyone and slower writing.
3. **May Android launch after iPhone?** The Play Store's waits add weeks whatever the build speed.
4. **Listening back while locked on Android shows a playback notification with controls.** Android requires it. Acceptable? (Or listening back stops when the phone locks, on Android only.)
5. **Which Play account?** A personal account (12 testers for 14 days before launch) or Summit Studio LLC as an organisation (needs a D-U-N-S number, up to 30 days)?
6. **Moving to a new Android phone.** Turning backup off keeps blessings out of Google Drive. Some phones still copy app data on a phone-to-phone transfer, which would carry the blessings (never the audio, if it is kept in the no-backup folder). Should blessings travel to a new phone that way, or not at all?
7. **The minimum Android version:** Android 13 recommended. Agree?
8. **A phone to buy or borrow:** a Pixel 10, a Galaxy A, or both?
9. **Hiding the app in recent apps** shows a plain sky-coloured card on Android, not the sky picture iPhone shows. Fine?
10. **The app in "Open with" for unknown files.** To catch `.blessing` files from Gmail and WhatsApp, the app may appear in "Open with" for other unknown files too, and says "This file could not be read" if picked. Acceptable?
11. **The name under the icon** (found in task 1). On the Pixel launcher "Upon Thy Head" is cut to "Upon Thy He…" (`08-launcher-home.png`). The Pixel home screen shows one line *(other launchers may differ)*. Keep it cut, or give the launcher alone a shorter name (the app's own name stays "Upon Thy Head" everywhere else)? If shorter, which words?
12. **Recent apps shows the blessings until the lock lands** (task 11). Until then Android's recent-apps card shows the sky and the newest blessing's title (`07-recents.png`). Acceptable for test builds, or should the cover come first?

---

## Sources (first-hand)

- ML Kit GenAI Speech Recognition: https://developers.google.com/ml-kit/genai/speech-recognition/android
- ML Kit GenAI overview (devices, quota, foreground only): https://developers.google.com/ml-kit/genai
- ML Kit release notes: https://developers.google.com/ml-kit/release-notes
- ML Kit Android data disclosure: https://developers.google.com/ml-kit/android-data-disclosure
- SpeechRecognizer: https://developer.android.com/reference/android/speech/SpeechRecognizer
- RecognizerIntent: https://developer.android.com/reference/android/speech/RecognizerIntent
- whisper.cpp: https://github.com/ggml-org/whisper.cpp ; models https://huggingface.co/ggerganov/whisper.cpp/tree/main
- Foreground service types: https://developer.android.com/develop/background-work/services/fgs/service-types
- Play foreground service declaration: https://support.google.com/googleplay/android-developer/answer/13392821
- Sharing audio input (calls): https://developer.android.com/media/platform/sharing-audio-input
- MediaRecorder output formats: https://developer.android.com/reference/android/media/MediaRecorder.OutputFormat
- Notification permission: https://developer.android.com/develop/ui/views/notifications/notification-permission
- Biometric authentication: https://developer.android.com/identity/sign-in/biometric-auth
- Activity.setRecentsScreenshotEnabled: https://developer.android.com/reference/android/app/Activity
- Auto Backup: https://developer.android.com/guide/topics/data/autobackup
- Target API: https://developer.android.com/google/play/requirements/target-sdk
- 16 KB pages: https://developer.android.com/guide/practices/page-sizes
- Android 15 and 16 behaviour changes: https://developer.android.com/about/versions/15/behavior-changes-15 ; https://developer.android.com/about/versions/16/behavior-changes-16
- Impeller: https://docs.flutter.dev/perf/impeller
- Quick Share with iPhone: https://www.android.com/quick-share/with-iphone/
- Testing requirements for new personal accounts: https://support.google.com/googleplay/android-developer/answer/14151465
- Developer verification (sideloading rules from 30 September 2026 in some countries; not a Play blocker): https://developer.android.com/developer-verification
- Second-hand, used only where marked: VoicePing offline speech benchmark https://voiceping.net/en/blog/research-offline-speech-transcription-benchmark/ ; Gmail and Samsung file-type reports (Stack Overflow, archived) https://kaweah.freedombox.rocks/kiwix/stackoverflow.com_en_all_2023-11/a/12153391
