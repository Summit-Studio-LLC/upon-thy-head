# Android: what it needs, and where the hard parts are

Research written 2026-11-16; tasks 1–3 of section 12 built the same day, tasks 4–7, the plain player, and tasks 11 and 12 (the lock, recent apps, location) on 2026-11-17 (see **Built so far** in section 12, and **Stand-ins** after it). It is for Noah. It covers everything the iPhone app does with Apple's own code (about 2,000 lines of Swift in `app/ios/Runner/`), the Android equivalent of each, and the order to build them in.

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
| Recording in parts that survive a kill | ADTS AAC parts, joined at Amen (`SpeechChannel.swift`) | **Built:** `AudioRecord` into `MediaCodec`, written as the same ADTS AAC parts frame by frame; `MediaMuxer` joins them (`SegmentRecorder.kt`, `Adts.kt`) | Low | 1.5 days |
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

**Verdict:** not the main path. *(Measured 2026-11-17, see 3.5: from a file it wrote only the first sentence.)* It acts differently by maker, may quietly ignore the file and listen to the room instead, and on older phones cannot take a file at all.

### 3.2 ML Kit GenAI Speech Recognition (Google's on-device library)

From Google's page, last updated 2026-11-14: [ML Kit GenAI Speech Recognition](https://developers.google.com/ml-kit/genai/speech-recognition/android). All of the following is **(Google)** unless marked.

- **Status: alpha**, version `1.0.0-alpha2` (26 October 2026). "Not subject to any SLA or deprecation policy. Changes may be made … that break backward compatibility." It needs Kotlin 2.3. [Release notes](https://developers.google.com/ml-kit/release-notes)
- **Two modes:**
  - **Basic:** "the traditional on-device speech recognition model, similar to the SpeechRecognizer API". It runs on "Android devices using API level 31 and higher", so Android 12 and later.
  - **Advanced:** runs on Gemini Nano (Google's on-device AI model), with better quality. It is only on the Pixel 10 and 11 series and phones with recent top-end chips (Snapdragon SM8750 and later, Dimensity 9400-class, Exynos 2600), such as the Galaxy S26, Z Flip8 and Z Fold8. It does not work on phones with an unlocked bootloader.
- **From a file: yes** *(measured 2026-11-17, see 3.5: only for short files; a 10-minute file failed at once, paragraphs were left out, and it needs the microphone permission even for a file)*. `AudioSource.fromFile()` transcribes "a whole pre-recorded file" and "automatically decodes" M4A, so the app's existing `.m4a` goes straight in. In this one-shot mode it "transcribes it faster than real time" and returns a final result for each stretch of speech.
- **Languages:**
  - Advanced: `en-US` and `es-ES`.
  - Basic: `en-US`, and `es-ES` marked **beta** ("may have a slightly higher word error rate").
  - **There is no `es-US` or `es-MX` in either list** *(measured: the Pixel 10 Pro emulator offers a Basic `es-US` download, though it never finished there; `es-MX` is not offered)*. Google adds "Additional locales are available", without naming them. So the Spanish of a family from Mexico or Latin America would go through Spain's Spanish model, with unknown quality *(unconfirmed)*.
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
- **A known Whisper fault:** during long silences it can write words that were never said *(widely reported; measured 2026-11-17, see 3.5: here it mostly left speech out instead, and invented words only on a clip repeated twenty times)*. For a record whose promise is "exactly as spoken", silences would have to be cut out before the file goes to Whisper.
- **What it avoids:** it sends no usage statistics, depends on nothing from Google, and keeps working if Google changes ML Kit.
- **Runtime:** **sherpa-onnx** (Apache 2.0 *(unconfirmed)*) runs the same Whisper models and was much faster in the one comparison above. Try both before choosing. *(Dropped 2026-11-17, see 3.5: its prebuilt tools did not run, and it adds 27.5 MB of libraries.)*

### 3.4 Recommendation

*(Superseded 2026-11-17 by 3.5: Whisper base is the main path, because ML Kit could not be shown working on these emulators and no phone will be used before launch.)*

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

### 3.5 Measured on this Mac's emulators (2026-11-17)

Noah's ruling: no real Android phone before launch. So the engine has to be one whose behaviour these emulators can show. Everything here was run on the Pixel_10_Pro emulator (Android 17, Google Play image, arm64) and the Pixel 3a emulator (Android 14, Google APIs image), with the emulator's sound off and the audio fed from files. The host is an Apple M3 Max. Every number is **a single run**, so differences of a few words per hundred mean nothing. "Wrong per hundred" is counted the way `lib/check/spoken.dart` counts it, against the typed text.

**The test audio:**
- `en`: the project's 38-second English clip.
- `es`: the 24-second Spanish clip.
- `long_en`: the English clip repeated 14 times with 7 s of silence between (10.5 min).
- `long_es`: the Spanish clip **repeated about 20 times** (10.4 min). **Whisper's worst case:** the same 24 seconds over and over invites it to repeat itself, so treat its `long_es` numbers as a stress test, not a forecast.
- `es_varied`: a 6-minute Spanish blessing that never repeats (553 words, macOS's Paulina voice at 150 words a minute, 7 s pauses between paragraphs). The fairest long Spanish test made here, though a synthetic voice is easier than a person.

**The table**

| | ML Kit Basic | ML Kit Advanced | Android's recogniser | Whisper (whisper.cpp) |
|---|---|---|---|---|
| **Proven here** | Pixel 10 Pro: English is already on the phone. A 38 s file took 8–14 s, and four runs out of four **left out the first two of four paragraphs**, in airplane mode too. A 2-minute file lost the second paragraph of every repeat, and the first paragraph of the first. **A 10-minute file fails at once** (`UNKNOWN`), from the app's own `.m4a` and from WAV alike. Spanish (`es-ES`, `es-US`) never finished downloading in about 5 minutes. `es-MX` not offered. Pixel 3a (Android 14): unavailable for every language. | Nothing: unavailable on both emulators (it needs Gemini Nano). | Both emulators: on the phone. A system dialog downloads the language. From a file it writes **only the first stretch of speech** (one sentence), then stops. Works in airplane mode. | The whole way through: English and Spanish, 10-minute files, airplane mode, time, memory. Its fault is **leaving speech out**, not making it up (see below). |
| **Cannot be proven without a phone** | Whether real phones drop paragraphs too, Spanish at all, which mid-range phones have it, the daily limit, the background block. | Everything. | Samsung's own engine. | Speed and heat on a mid-range phone (estimated below). |
| **Cost to the person** | None for English on a Pixel; unknown for Spanish. | — | A system download prompt (44 MB English, 49 MB Spanish; 79 MB and 123 MB once installed). | A one-time download with consent: 58 MB (base) or 191 MB (small), plus the wait after Amen. |
| **Cost to the build** | +1.9 MB. An alpha library. It **needs the microphone permission even to read a file** (`ERROR_TYPE_INSUFFICIENT_PERMISSION` without it). It pulls in Kotlin's 2.4 standard library; it built with the app's AGP 9.0.1 and Kotlin 2.3.20. | Same. | None. | +3.3 MB of native code (1.5 MB zipped): a C++ build in Gradle with the NDK. The app also needs a 0.9 MB silence-finding model. The download, its consent screen and a resume-later queue are app code. |

**Whisper's numbers** (Pixel 10 Pro emulator, 4 threads, `whisper-cli` built from whisper.cpp of 2026-11-16 with NDK 28.2):

| Model | Audio | Whole file, as is | Cut at silences, no carry-over |
|---|---|---|---|
| base | en | 2.7 s, 29 wrong per hundred (the first paragraph left out) | 1.9 *(Mac)* |
| small | en | 8.2 s, 2.8 | 0.0 *(Mac)* |
| base | es | 1.3 s, 4.2 | 4.2 *(Mac)* |
| small | es | 4.2 s, 0.0 | 4.2 *(Mac)* |
| base | long_en | 27 s, 38.5 | **35 s, 15.8** (Mac: 13.6) |
| small | long_en | 96 s, 48.8 | **65 s, 21.3** (Mac: 21.4) |
| base | long_es *(repeated clip)* | 21 s, 91.0: wrote "(Amén)" for the last 8 minutes | 24 s, 39.0 (Mac: 34.2) |
| small | long_es *(repeated clip)* | 83 s, 32.9 | 61 s, 46.1 (Mac: 53.4) |
| base | es_varied | 14 s, 30.4 (whole paragraphs left out) | **15 s, 4.7** (Mac: 4.5) |
| small | es_varied | 45 s, 29.7 | **37 s, 23.3** (Mac: 10.3) |

- "Cut at silences, no carry-over" is `-mc 0 --vad -vm ggml-silero-v5.1.2.bin`: whisper.cpp's own silence finder hands Whisper each stretch of speech, and nothing is carried from one stretch to the next. This is how the app would run it. "*(Mac)*" rows were run on the host with the same models (`whisper-cli -ng`, 8 threads), as a cross-check.
- Cutting the silences out of the file instead (to 1 s each) helped only a little (base long_en 38.5 → 33.6).
- **What goes wrong is missing words.** On these files Whisper invented words only once: the "(Amén)" loop on the repeated Spanish clip. Otherwise it left words out. Small in particular drops the first word after a pause ("Emma, I lay…" became "I lay…" in 13 of 14 repeats) and sometimes a whole sentence. Widening the silence finder's margin (`--vad-speech-pad-ms 300`) made it worse, not better.
- **Base did better than small on every long file**, and small did better only on the short, clean clips. Small's Spanish varied from 10 to 23 per hundred between two runs of the same file. One run each is not enough to choose between them on quality. Base is the better start on size and speed anyway.
- **Memory (peak):** base 250–345 MiB, small 505–611 MiB.
- **Airplane mode:** base on `en` ran in airplane mode with the same result. It is a program on the phone with no network code at all.
- **Mid-range estimate (an estimate, not a measurement).** The emulator runs arm64 code directly on the M3 Max's cores. A Galaxy A-class phone (Cortex-A78-class big cores) is about 2.5–3 times slower per core than an M3, with far less memory bandwidth, so I assume 3–5 times slower. **A 10-minute blessing: about 2–3 minutes with base, 3–5½ minutes with small.** Heat and battery are unknown.
- **sherpa-onnx dropped:** its prebuilt Android tools did not run (`libc++_shared.so` missing). It would add 27.5 MB of libraries (22 MB of that is onnxruntime), and its Whisper base files are 159 MB, against 57 MiB for whisper.cpp's.

**ML Kit and the recogniser, more detail:**
- Pixel 10 Pro, ML Kit status: Basic `en-US` AVAILABLE, `es-ES` and `es-US` DOWNLOADABLE, `es-MX` UNAVAILABLE. Advanced: UNAVAILABLE for all four ("AICore failed … BINDING_FAILURE").
- `download()` for Spanish returned "Model download is not completed yet and will be retried automatically", and the status stayed DOWNLOADABLE through about 5 minutes of polling, twice. Spanish files then fail with `ERROR_TYPE_INVALID_REQUEST`.
- ML Kit on `en` (wrong per hundred 48–50, four runs): the first ~8 seconds of output time pass with sound levels reported but no words. The first words it writes are "I bless you with with pieces", the start of the third paragraph.
- The recogniser on `en`: Pixel 3a wrote the first sentence only, 83 wrong per hundred. The Pixel 10 Pro did the same. Spanish: the first sentence plus a stray "pistola" (77 per hundred). Without a segmented session it wrote nothing. Supported languages: `es-ES` on both; `es-US` on the Pixel 10 Pro only; `es-MX` on neither.

**What this corrects above:**
- 3.1: the languages are a system download of 44–49 MB each, 79–123 MB once installed. From a file, Google's recogniser stopped after the first sentence even with a segmented session, so it is not even a fallback without the app cutting the file itself.
- 3.2: "From a file: yes" holds only for short files: 10 minutes failed at once. It also left paragraphs out every time. It needs the microphone permission even for a file. There **is** an `es-US` Basic model offered (not `es-MX`). On the Android 14 emulator it is not offered at all.
- 3.3: the "known fault" measured here is leaving speech out more than writing words never said. Cutting at silences with no carry-over is needed and helps a great deal. Small is not clearly better than base on long blessings. sherpa-onnx is dropped.
- 3.4 is replaced by the recommendation below.

**Recommendation.** **Whisper base (q5_1), run by whisper.cpp inside the app, cut at silences, with no carry-over**, for English and Spanish alike. It is the only engine whose whole job (a 10-minute file, both languages, airplane mode) could be shown working on these emulators. Because it is the app's own code, a real phone will behave like the emulator, only slower. ML Kit failed on the length a blessing actually is, left out paragraphs, and could not get Spanish at all here. With no phone to prove otherwise, it cannot be the main path at launch. Keep the `transcribe` method behind one small Kotlin class so ML Kit can be tried again once someone has a real phone. Offer small later only if base proves weak with real voices.

**What the person would see** (wording to settle with Noah):
- **First run,** a row on the permissions page: "**Writing the words down.** A one-time download of 58 MB lets this phone write your blessings in words. Your voice never leaves the phone." Buttons: **Download** / **Later**. Under it when not on Wi-Fi: "This will use mobile data."
- If **Later**, or while it downloads: blessings record as now, and the review page says "**The words will be written once the download finishes.**" When it finishes, they are written then.
- **After Amen:** "**Writing the words…** A long blessing can take a few minutes on this phone. You can leave the app; the words will be ready when you come back." (While the app is closed, the writing waits and resumes on the next launch, as on iPhone. Keeping it running in the background would need a foreground notification. That is a later choice.)

**How to repeat this:** the throwaway probe app and scripts are in `~/Development/scratch-uth-speech` (outside the project). `tools/p10.sh` is the Whisper whole-file pass and the recogniser. `tools/p10b.sh` is silences and no carry-over. `tools/p10c.sh` and `p10d.sh` are ML Kit. `tools/wer.py` does the scoring. Each script boots the emulator with `-no-audio -no-snapshot-save`, uninstalls the probe and shuts the emulator down at the end.

---

## 4. Recording

**Surviving a kill.** Android's `MediaRecorder` can write **AAC in ADTS form directly** (`OutputFormat.AAC_ADTS`, there since Android 4.1). **(Google)** [MediaRecorder.OutputFormat](https://developer.android.com/reference/android/media/MediaRecorder.OutputFormat). ADTS is the same frame-by-frame format the iPhone app chose so that a part cut off mid-write can still be read.

**As built (task 4):** not `MediaRecorder` but `AudioRecord` (32 kHz mono) feeding Android's AAC encoder (`MediaCodec`, AAC-LC 24 kbit/s, about 11 MB an hour as on iPhone), with each frame written by the app as soon as it is encoded (`SegmentRecorder.kt`). Two reasons: the call callback below only reports on a recording that is still running, so the microphone stays open through a call and the silent samples are simply not written; and a kill then loses only what is inside the encoder. Measured: **0.07–0.08 s lost** at a `force-stop` 30 s in (iPhone loses about 2 s). The parts are joined into one `.m4a` by `MediaMuxer` without encoding again (`Adts.kt`), whole or not at all (a `.tmp` file renamed into place). Recovery at launch uses the iPhone's code path and the existing "A recording was kept" sheet.

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

**As built (task 7):** the recorder pauses on either of two signals: the callback's "silenced" flag, and the phone's audio mode turning to ringing, in a call or in a voice/video call (`AudioManager.OnModeChangedListener`). On the emulator the simulated call arrives as the mode change; whether a real call also sets "silenced", and which comes first, is for the real phone (task 19). The microphone used is the phone's own (`TYPE_BUILTIN_MIC`), so a Bluetooth headset connecting or dropping changes nothing; another app taking the microphone arrives as "silenced" (not provable on the emulator, which has no second recording app).

**Play Store.** For apps targeting Android 14 and later, Play Console asks for a declaration of each foreground service type: a description, plus **a video link** showing "the user initiate the microphone actively recording audio". **(Google)** [Play: foreground service requirements](https://support.google.com/googleplay/android-developer/answer/13392821). Listening back while locked needs a second declaration, "media playback", also with a video.

**Listening back while locked** needs a media-playback foreground service, and therefore a playback notification with controls. That conflicts with Claude's choice of "no Now Playing information on the lock screen" for iPhone. On Android a visible notification during background playback is required *(standard Android behaviour; see question 4)*.

---

## 5. The app lock and recent apps

- **Unlock:** Android's `BiometricPrompt` allows "fingerprint or face, or the device PIN, pattern or password" in one prompt (`BIOMETRIC_STRONG | DEVICE_CREDENTIAL`). The combination is limited on Android 10 and older. **(Google)** [Biometric authentication](https://developer.android.com/identity/sign-in/biometric-auth)
  - *Corrected when built (2026-11-17):* the app uses the platform's own `android.hardware.biometrics.BiometricPrompt`, not AndroidX's. At Android 13 it does the same (`setAllowedAuthenticators(BIOMETRIC_STRONG | DEVICE_CREDENTIAL)`), needs no library, and works from the plain `FlutterActivity` the app already has; AndroidX's needs a `FragmentActivity`. It needs the `USE_BIOMETRIC` permission (granted at install, never asked).
- **Face unlock on many phones does not count.** Outside recent Pixels, face unlock is usually rated "weak" or "convenience", so the prompt offers fingerprint or PIN instead *(unconfirmed per phone)*. The settings row should say "Screen lock" or "Fingerprint", not "Face ID", by what the phone reports.
- **Locks after 60 seconds away, never during a recording:** this is the same Dart logic as iPhone. The native side only reports when the app left and came back, through Android's lifecycle events.
- **Recent apps:** `setRecentsScreenshotEnabled(false)` (Android 13 and later) tells the system never to snapshot the app. It shows the window background instead, which can be the sky colour. **(Google)** [Activity reference](https://developer.android.com/reference/android/app/Activity#setRecentsScreenshotEnabled(boolean))
  - On Android 12 the only tool is `FLAG_SECURE`, which also blocks screenshots. That is a reason to make **Android 13 the floor** *(see section 11)*.
  - Unlike iOS, a custom picture (the plain-sky cover image) cannot be placed in the recent-apps view; only a plain colour *(unconfirmed but widely reported)*.
  - *As built:* with the lock on, `setRecentsScreenshotEnabled(false)`, and whenever the app loses the screen (its window loses focus: recent apps, the notification shade; or it leaves) a plain view in the ground colour is laid over it (the iPhone's cover, without the picture), lifted on return once the Dart side has decided whether to lock, so a locked return never shows the last frame first. Never for the unlock prompt or Android's own permission questions, as on iPhone. Screenshots stay allowed (no `FLAG_SECURE`).
  - *Corrected when built:* turning the snapshot off is not enough on a Pixel. Its recent apps shows the app itself, live, as it opens, so the cover must go on when the window loses focus, not when the app stops.

---

## 6. Approximate location, asked once

Ask only for `ACCESS_COARSE_LOCATION`. Android then never offers precise location. From Android 11, the system's own dialog offers "Only this time", which matches the iPhone's suggested "Allow Once" *(confident, not re-checked)*. A single reading from Android's location service, rounded to a tenth of a degree, is all that is needed. No Google Play services dependency is necessary. Low risk, half a day.

*As built (2026-11-17):* `LocationChannel.kt` uses the platform's `LocationManager.getCurrentLocation` (Android 11+), asked of every enabled provider of fused, network and GPS at once, the first place to come used; with only coarse permission Android blurs each to about 2 km. If no fix comes within 6 s, a place the phone knew in the last ten minutes is used, else none (the Salt Lake Temple). *Corrected twice:* the first build used a recent last-known place first; on the emulator that was the place from boot, not where the phone is now, so a current fix comes first. Then, asked of fused alone, the emulator never answered: with approximate permission the fused provider runs at low power and never turns GPS on, and the emulator has no network location, so its `geo fix` was never read (`dumpsys location`: the app's fused request `BALANCED`, the provider's `LOW_POWER`, GPS untouched). Asking all three at once costs nothing on a phone where fused answers first. Play services' fused client was not used: the platform does the one reading needed, and the app stays free of Google libraries. After "Only this time" lapses Android reports location as not allowed; the place found stays kept, and nothing asks again unprompted. Settings' "Use my location" asks again while Android will; once Android answers at once without a question (refused twice), it opens the app's page in Settings.

---

## 7. Sharing

*Rewritten 2026-11-17 for the ruling "Sharing is by link, for everyone" (decisions, 2026-11-16) and built as tasks 13 and 14. The earlier version of this section put the `.blessing` file first; the ruling makes the file the fallback for no internet only.*

**What the person sees** is the iPhone's S3 sheet, drawn by the shared Dart code (`lib/share/share_sheet.dart`): a card of the blessing, the gold **Send this blessing**, and **Only the words** with Text and PDF. The native half is `ShareChannel.kt`, answering the iPhone's `upon_thy_head/share` methods with the same keys and answers.

**A link** (`website/PROTOCOL.md`): the record is locked on the phone (`LinkChannel.kt`, javax.crypto AES-256-GCM, a new key each time), only the locked copy goes to the service, the key stays after the `#`, and the stop token is kept wrapped by an Android Keystore key. Once made, the sheet shows the link with **Copy link** and **Send the link**.
- **Send the link** opens Android's own share sheet (`Intent.createChooser`) with an `ACTION_SEND` of type `text/plain` whose text is the link alone, so Messages, WhatsApp and Gmail make it a link. The blessing's title is the sheet's heading (`EXTRA_TITLE`); there is no subject, which some messaging apps turn into an MMS.
- **Copy link** puts it on Android's clipboard marked sensitive (`ClipDescription.EXTRA_IS_SENSITIVE`), so Android's copy preview shows dots, never the link; the clipboard then behaves as Android's own does.
- The share sheet is started for a result, so the app hears when it closes and can close it itself when it locks; while it is up, losing focus to it is not leaving the app (no cover), as on iPhone where the sheet is part of the app.

**Only the words:** Text is the same `text/plain` hand-over. The PDF is the iPhone's document, ported from `Share.swift` to `PdfDocument` (`SharedPdf` in `ShareChannel.kt`): Letter or A4 by region, an inch of margin, Newsreader from the Flutter assets at weight 400 with the optical size following the size, old-style figures, the iPhone's measures, widows and orphans kept off, a footer from page 2. Android's PDF writer embeds the font, subset, so the text is real.

**Files leave through the app's own provider** (`BlessingFiles.kt`, a read-only `ContentProvider` on one folder, `cache/share/`, not exported, readable only with the grant on the share intent): no storage permission is asked. It is AndroidX's FileProvider cut to size, with one difference that matters: a `.blessing` file reports `application/vnd.uponthyhead.blessing`, where FileProvider would say `application/octet-stream`. Files stay until the next share or the next launch (Gmail reads an attachment when the mail is sent, so removing it when the sheet closes could empty the mail).

**No internet, or no service:** the iPhone's one line ("No internet, so a link cannot be made now.") and **Send as a file**: the `.blessing` file, named "<title>, <date>.blessing", typed `application/vnd.uponthyhead.blessing`. This is the only place the file is offered.

**Receiving a link:** the manifest's verified filter for `https://uponthyhead.app/b/` hands the link, fragment and all, to the Dart code iPhone uses (`lib/share/links.dart`): fetched, opened with its key, the keep sheet, and every refusal. See "When the site goes live" below for what turns it on.

**Receiving a `.blessing` file:** `ShareChannel.incoming` reads up to 512 KB from the `content://` (or `file://`) address on a background thread and hands the bytes to the strict Dart reader. The filters, as narrow as still catches one sent by Gmail and WhatsApp:
1. `VIEW` of `application/vnd.uponthyhead.blessing` (this app's files and an iPhone's carry it);
2. `VIEW` of `application/octet-stream` from a `content://` address (Gmail can hand over an attachment whose type it does not know, with no name; the Files app says octet-stream for any extension Android does not know, `.blessing` included);
3. `VIEW` with no type at all, by a name ending `.blessing`;
4. `SEND` of the app's own type only ("Share → Upon Thy Head").
- **What the person sees:** "Upon Thy Head" is offered under "Open with" for unknown binary files, never for pictures, PDFs, text, archives with a known type, or anything with a type of its own; it is not in the share list for unknown files. Opening something that is not a blessing says "This file could not be read." The rest (not while locked, not during a recording, first launch) is the shared Dart code.

**When the site goes live** (Android opens `https://uponthyhead.app/b/…` in the app only after it verifies the site):
1. The release signing key's SHA-256 fingerprint: Play Console → the app → Test and release → App integrity → App signing → "App signing key certificate", SHA-256. (With Play App Signing the key that signs what people install is Google's, not the upload key, so it must be that one. Add the upload key's too while testing builds installed outside Play.)
2. Serve `https://uponthyhead.app/.well-known/assetlinks.json` (the website's `app/.well-known/assetlinks.json/route.ts`), `Content-Type: application/json`, no redirect:

        [{
          "relation": ["delegate_permission/common.handle_all_urls"],
          "target": {
            "namespace": "android_app",
            "package_name": "dev.summitstudio.uponthyhead",
            "sha256_cert_fingerprints": ["<AA:BB:…:FF, the 32-byte fingerprint from step 1>"]
          }
        }]

3. Check from a phone with the release build: `adb shell pm verify-app-links --re-verify dev.summitstudio.uponthyhead`, then `adb shell pm get-app-links dev.summitstudio.uponthyhead` must show `uponthyhead.app: verified`. Google's checker: `https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://uponthyhead.app&relation=delegate_permission/common.handle_all_urls`.
4. Then on a real phone: a link tapped in Messages, Gmail and WhatsApp opens the app, with the `#` part intact (proved here only from the moment Android hands it over: `am start -a android.intent.action.VIEW -d 'https://uponthyhead.app/b/<id>#<key>' dev.summitstudio.uponthyhead`).

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

**Now (2026-11-17, after tasks 11 and 12):** all four rows are real. Microphone (required), Notifications and Location (optional) put Android's own questions; Location asks for approximate location only, and its line ends "Only this time is enough." Screen lock (optional) has no system question: its Allow turns the lock on and proves it with one unlock (the system prompt); cancelled, the row stays unanswered. It is named "Fingerprint or screen lock" when the phone reports a strong fingerprint, else "Screen lock"; never "Face ID". With no screen lock at all the row is Off: "This phone has no screen lock, so anyone can open this app. Set one to lock your blessings.", and its Settings button opens the phone's own screen-lock settings; back from there with one set, the row offers Allow. The lede is "Tap Allow, and the phone will ask." Continue opens once the microphone is answered; refusing notifications changes nothing about recording. If the first run was left before the microphone was answered, Begin asks. A refused microphone is said in Android's terms ("The microphone is not allowed for Upon Thy Head." and "In Settings, tap Permissions, then Microphone.", with Settings opening the app's own page); while Android will still ask once more, the button is "Allow the microphone" and asks again. The practice recording is skipped: it shows only the words, and the words are not written on Android yet.

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

Screenshots are in `design/sim/android/` (tasks 11–12: `53`–`89`, and `pair-11-settings`, `pair-21-first-run`, `pair-22-locked` beside iPhone's; tasks 4–7: `30`–`52`, and `pair-12-recording`, `pair-13-review` beside iPhone's, whose review shot is older and has no "Whose blessing" row); the scripted run is `app/tool/android_tests.sh` (boots the emulator, runs `integration_test/android_test.dart` in two parts with a real kill between, every step under a time limit, and shuts the emulator down).

- **Task 1, done.** `app/android/`: package `dev.summitstudio.uponthyhead`, minimum API 33, target and compile 36; adaptive icon with a themed (monochrome) layer from `design/icon/final` (`tool/android_icons.sh`); a dark launch with the icon on the sky's ground colour; upright on phones, free on tablets (smallest width 600 dp or more); backup off. SQLite bundled (8.1); 16 KB checked (8.5).
  - Proved by: the app opens on Pixel_10_Pro (Android 17) and Pixel_3a (Android 14) with the five samples; the launch frames never go white (`01-launch-frames.png`); the launcher icon, normal and themed (`08`–`11`); the iPhone upgrade replay: the committed build seeded with data still in the WAL, then this build installed over it, gave identical rows, tags and changes (md5), `integrity_check` ok, `user_version` 6, and the app opened on "Five blessings since June 2024" (`28-ios-upgrade-replay.png`).
- **Task 2, done.** Edge to edge (the bars are transparent; Flutter reports their sizes as padding, so the rings clear the gesture bar); back and predictive back on every layer (8.4); Android's own selection handles and copy menu on the review page (`27-review-selection-handles.png`); the fonts are the app's own (Newsreader), with Roboto standing in for SF Pro, which may not ship on Android.
  - Proved by: `android_test.dart` on Pixel_10_Pro: the list, zoom by pinch, the ruler, reading to the end, editing a title with the keyboard up (the field stays above it), the delete question closed by back, a deletion confirmed, Settings, the recording screen; back from each; then the app killed and reopened with the edit kept and the deletion gone. The same test passes on the iPhone simulator (`--ios`) for the side-by-side shots. Spanish by the emulator's language (`12`–`14`), the largest font and display size (`15`–`25`; two layouts were fixed for it: list rows overlapped, and the Settings language row overflowed).
- **Task 3, done.** See section 10. Proved by `pair-*.png`.

### Built 2026-11-17: recording without the words

The scripted run is `app/tool/android_record.sh <avd> [--only 1,2,…]` (boots the emulator with `-no-audio`, installs the debug build, drives the app through what the screen shows with `tool/android_record.py`, compares each recording with what the microphone was given using `tool/android_mic.py`, writes `summary.json`, uninstalls and shuts down; every step under a time limit). Output: `app/build/android_record/<avd>/`. The microphone is given a known sound (section 13): English and Spanish speech, then the same reversed, 124 s.

- **Task 4, done.** `SegmentRecorder.kt`: `AudioRecord` (32 kHz mono, the built-in microphone) → `MediaCodec` AAC-LC 24 kbit/s → each frame written as ADTS to `<id>.partN.aac` as soon as it is encoded; `Adts.kt` joins the parts into one `.m4a` with `MediaMuxer`, without encoding again, through a `.tmp` file renamed into place. The channel (`speech`) answers the iPhone's methods and sends the iPhone's events, so the Dart side is shared.
  - Proved by (Pixel_10_Pro): Begin to Amen 40.97 s, the joined file 40.99 s; against what was heard, waveform correlation 0.997, spectrum 1.00, loudness −17.1 dBFS against −17.4. Pixel 3a (Android 14): 41.86 s against 41.93 s, waveform 0.997.
- **Task 5, done.** At launch the parts left by a killed recording are joined and offered on the iPhone's "A recording was kept" sheet.
  - Proved by: `am force-stop` 30 s in, five times on each emulator. Lost: Pixel_10_Pro 0.04, 0.04, 0.07, 0.50, 0.02 s; Pixel 3a 0.06, 0.02, 0.01, 0.06, 0.06 s (the limit is 3 s; iPhone loses about 2 s). The recovered file matches what was heard (waveform 0.997). A swipe from recent apps also ends the recording (the service gives up the microphone and the process, `onTaskRemoved`), and it is recovered at the next launch: 0.01 s lost (Pixel 3a 0.06 s). `am kill` while in the background does nothing: Android keeps an app with a microphone service alive, and Amen keeps the whole recording (26.05 of 26.11 s).
- **Task 6, done.** `RecordingService.kt`: a foreground service of type `microphone`, started at Begin while the app is on screen (Android 14+ requires that), stopped at Amen, Discard or a recovery. Its notification is quiet (low importance, no sound or vibration), uses the monochrome icon, says "Recording a blessing" ("Grabando una bendición") with the running time (a chronometer that stops while paused), opens the app when tapped, and has no buttons. Asking for notifications is optional: refused, the service still runs and Android lists it only in the drawer's active-apps list. The screen stays on while recording (as on iPhone); back, turning the phone, recent apps and home never end a recording.
  - Proved by (Pixel_10_Pro, `android_record.sh`): 5 minutes with the screen off, notifications allowed: 311.26 s recorded of 311.25 s Begin to Amen, matching what was heard (waveform 0.997); the notification in the shade with its running time (`31`, `32`). Then notifications refused (`pm revoke`) and 5 minutes again: 311.30 of 311.27 s, no notification, the service ran all the same (`33`). *The emulator has no screen lock set, so "locked" here is the screen off and the keyguard without a PIN.* Back, recent apps, turning the phone and 2 minutes on the home screen: 149.15 s of 149.12 s (`41`: the app stays upright on phones, as designed). Battery saver with "Don't keep activities": the same recording goes on, 41.02 of 41.01 s. Spanish at the largest text and display size: the notification says "Grabando una bendición" (`45`).
- **Seen at the largest text and display size** (step 9, Spanish `45`–`48`, English `49`–`52`; Android's largest font, 2.0, with the display size at its largest):
  - The "recording is kept" page ran up under the status bar. It now stops below it and scrolls, with the buttons in view (`lib/record/after_screen.dart`; unchanged when it fits, so iPhone looks as before). The run scrolls it back to the top and checks the date line shows (`47`, `50`).
  - The line under the ring ("Mantén presionado para terminar") was drawn across the ring, and "Amén" ran out of it. Now the ring and its line are one column, the line always below the ring with a gap, and the ring's word is shrunk to fit the ring, as Begin's already was (`lib/record/hold_ring.dart`, `lib/record/record_screen.dart`; `46`, `49`, `51`, `52`). *Why shrink the word, not grow the ring:* the ring's size is the hold's target and its countdown drawing, the same on both phones; the word is short and still reads at the cap. At the usual size the word fits with room to spare ("Descartar" is about 73 of the 76 points allowed) and the ring sits where it always did, so iPhone is unchanged. Proved by `test/hold_ring_test.dart`: English and Spanish, Discard and Amen, two screens, text sizes 1.0, 1.35 (about iPhone's first accessibility size), 2.0 and 3.0; it failed before the change.
- **Task 7, done.** A call (the audio mode turning to ringing or a call; no phone permission is asked) or another app taking the microphone (the recording's `isClientSilenced` flag) pauses the recording as iPhone's interruption does: the ring shows paused, the part is closed and nothing silent is written; when the sound comes back a new part starts, and Amen joins them. A Bluetooth or wired headset connecting mid-blessing does not move the recording: it stays on the built-in microphone (`preferredDevice` = `TYPE_BUILTIN_MIC`).
  - Proved by (`adb emu gsm`): a call answered 20 s in and ended 22 s later: paused at 20.3 s, listening again at 43.1 s; 40.22 s recorded of 63.02 s, paused 22.81 s; every 5 s of the joined file found in what was heard in order, with one jump of 22.6 s at the call and no hole (longest quiet 3.28 s; the known sound itself has 3.18 s) (`36`). A declined call pauses only while it rings (10.2 → 14.3 s). A call with the screen off pauses and resumes (10.2 → 23.2 s; 23.10 of 35.97 s kept). Another app taking the microphone and a Bluetooth headset: not provable on the emulator (section 13).
- **The plain player** (`PlayerChannel.kt`, `MediaPlayer`): play, pause, back 10 s, the scrubber; on screen only (leaving the app pauses it; task 18 is listening while locked).
  - Proved by (step 8): a 31 s recording opened from "Review now": the line, the player loaded at 0:31; Play moved it to 0:06 in 4 s; Pause held it; a tap three quarters along the scrubber went to 0:27; back ten seconds to 0:17 (`42`, `43`). Done asks "Finished reviewing? The recording stays on this phone until its words are written. Then it is erased." (`44`; it said "will be erased" before this was found and fixed), Finish opens the reading page, and the `.m4a` is still on the phone after Finish and after a restart. *Typing into the words field from adb did not reach the field* (adb's text input, not the app: typing on Android was proven in task 2), so the rule with typed words is proven by the unit test `the audio rule` in `test/recovery_test.dart`.
- **The microphone refused** (step 7). The first run lets a refused microphone go on; the recording screen then says, in Android's words, "The microphone is not allowed for Upon Thy Head." with **Allow the microphone**, which puts the phone's question again (`37`, `38`). Refused a second time, Android will not ask again, so the line adds "In Settings, tap Permissions, then Microphone." and the button is **Open Settings**, which opens the app's own page in Settings (`39`, `40`). Allowed there, back in the app the refusal is gone and Begin works.
- **Recording without the words.** After Amen the blessing is a draft whose words are still to come (`WordsStatus.later`); the after screen and its review page say "The words will be written on this phone in a coming version of the app." The seam for tasks 8–10 is one place on each side: `transcribe` in `SpeechChannel.kt` (now answers the error `later`), `Transcript.later` in `lib/record/speech.dart`, and the draft state.

### The audio rule

On iPhone the recording is erased once its words are written and reviewed. On Android the words are not written yet, so: **a recording is never erased while its words are still to come** (`keepsRecording` in `lib/record/recovery.dart` is true for `WordsStatus.later`). Done on its review page finishes the blessing as on iPhone (no longer a draft; its reading page opens), with or without typed words, but the recording stays. It is given to the phone again at every launch and whenever its review page opens (`_writeLaterWords` in `lib/home/home_screen.dart`); today Android answers "later" and nothing changes. When tasks 8–10 make words come: with nothing typed they become the blessing's words; with words typed, the person's words stand and the phone's are kept beneath them as the first transcript, as iPhone keeps its own; then the recording is erased, as it would have been at Done. Deleting the blessing erases it at any time. Its size is about 11 MB an hour, as on iPhone.

### iPhone after this work (2026-11-17)

`flutter analyze` is clean and the 307 unit tests pass. On the clean simulator (iPhone 17 Pro (clean), shut down and booted before each run): `drafts_acceptance.sh`, `review_acceptance.sh` and `share_acceptance.sh` pass. The tests that press Begin fail: `integration_tests.sh` (`record`, `ring`), the second run of `recovery_acceptance.sh`, and phase 2 of `link_acceptance.sh`, all with "the recorder would not start". **The starting commit (3dcfdee), exported untouched, fails `record_test` the same way**, so it is this Mac, not this work: the simulator records from the Mac's default input, which is a USB webcam microphone ("Brio 101"). After the failed start, the `ring` test also crashed the app: a crash (SIGSEGV) in `SegmentRecorder.exportComposition` inside `AVAssetExportSession`, in iPhone Swift that this work did not change. It deserves its own look: a failed start should never crash. After the ring fix, `record_test` was run again alone and failed the same way at the same place.

**The coordinator's check, the same night.** It is not the webcam: with the Mac's input switched to the built-in microphone and then to a virtual device, the recorder still would not start (the setting was put back). The simulator's log shows the app's audio device timing out when it starts (`AudioDeviceStart`, mach send and receive time-outs), so the Mac's audio service is stuck, most likely since the Android emulator hung on the microphone during this work. The Mac still plays sound. The same four runs passed on the commit before this one, four hours earlier. To clear it: restart the Mac's audio service (`sudo killall coreaudiod`, which needs the owner's password) or restart the Mac, then run `record`, `ring`, `recovery_acceptance.sh`, `spanish_acceptance.sh`, `speech_tests.sh` and `link_acceptance.sh` again. **Until then the iPhone recording runs are unproven against this work.** Two crashes seen in this state are inside Apple's frameworks on the simulator (`AVAssetExportSession` given a recording that never started; `AVAudioRecorder`'s callback after the recorder was released); whether a failed start can crash a real iPhone is still to be checked.

### Built 2026-11-17: the lock, recent apps, location (tasks 11 and 12)

The scripted run is `app/tool/android_lock.sh <avd> [--only 2,3,6,9]`: it builds a debug APK with `--dart-define=SEED_SAMPLES=first-run` (the five samples, and the first run still shown), boots the emulator with `-no-audio`, gives it a PIN and a fingerprint, installs, drives the app through what the screen shows (`tool/android_lock.py`: acceptance steps 1, 2, 3, 6, 7 and 9, each under a time limit), then uninstalls, takes the PIN and fingerprint away, puts the storage settings back and shuts the emulator down. Output: `app/build/android_lock/<avd>/` (`summary.json` and the screenshots).

**The PIN and fingerprint from adb** (`tool/android_fingerprint.py <serial> add|remove <pin>`): `adb shell locksettings set-pin 1111`; then `adb shell am start -a android.settings.FINGERPRINT_ENROLL`, the PIN typed (`input text 1111`, Enter), "More" and "I agree" tapped, and `adb emu finger touch 1` / `adb emu finger remove 1` repeated until "Fingerprint added", then Done. In the app, `adb emu finger touch 1` is a right finger and `touch 2` a wrong one. Removed with `adb shell locksettings clear --old 1111`, then `locksettings set-disabled true`, as the emulators were found (no PIN, no fingerprint, the lock screen off).

- **Task 11, done.** `LockChannel.kt` answers the iPhone's lock channel, so the rules are the Dart ones iPhone uses (`lib/lock/lock.dart`): opens locked; locks after 60 s away; never during a recording, and after one that ended while away; Cancel leaves it locked with Unlock to try again; a blessing arriving waits behind the lock; while locked the screen has only "For me", "Locked", "Unlock" and "New blessing", for the eye and for TalkBack. One system prompt takes a strong fingerprint or the PIN, pattern or password (section 5). The phone's lock is named "Fingerprint or screen lock" when it reports a strong fingerprint, else "Screen lock"; "Face ID" is never shown on Android. With no screen lock at all the app never pretends: the switch is off, and the line says "This phone has no screen lock, so anyone can open this app. Set one to lock your blessings." with **Set a screen lock**, which opens the phone's own screen-lock settings. Turning the lock off asks for the unlock first.
- **Recent apps.** With the lock on: `setRecentsScreenshotEnabled(false)`, and the plain ground colour laid over the app whenever it loses the screen, as the iPhone's cover is (`willDeactivate` there, losing window focus here, never for the unlock prompt or Android's own permission questions), lifted once Dart has answered. *Found and fixed:* the Pixel's recent apps shows the app itself, live, as it opens; no snapshot is taken then, so turning screenshots off alone left the open blessing readable in the card (the first run's picture: the blessing "Before the new job" in full, though nothing of it was in the accessibility tree). Screenshots stay allowed (no `FLAG_SECURE`). With the lock off, recent apps shows the app as it is, as iPhone does with its lock off.
- **Task 12, done.** Location and Screen lock are real first-run rows, both optional; see section 9 for the wording. Location per section 6.

**Proved by (Pixel_10_Pro, Android 17):**
1. Fresh install, first run: the lock row is "Fingerprint or screen lock"; Allow puts the system prompt ("Keep your blessings locked"); one `adb emu finger touch 1` answers it. Location: Android's question offers approximate only; "Only this time". No row moved when answered (each row's centre identical before and after). Through to the sky with the five samples (`54`–`57`).
2. Away 70 s: locked, the prompt up; nothing of a blessing on screen or in the accessibility dump (`58`). Unlock by fingerprint; away 70 s again; unlock by PIN.
3. Away 20 s: not locked.
4. Recording, away 90 s: still recording ("Listening", Amen), not locked (`64`). Amen, "Save for later", away 70 s: locked, the prompt up.
5. Cancel: locked, Unlock puts the prompt again (`65`). Three wrong fingerprints (`adb emu finger touch 2`): each "Not recognized", the prompt stays. **The fifth wrong one: Android 17 locks the whole phone** (its own lock screen; the app's prompt is cancelled, code 10). After the phone's PIN, the app is still locked (`66`), and its prompt's "Use PIN" opens it.
6. Recent apps with the lock on while a blessing is open: the card is the plain ground colour (the middle of the card measured: no spread, brightness 0.036, the ground's), with no words of the blessing (`59`). With the lock off: the open blessing, as on iPhone with its lock off (`60`).
7. Lock off in Settings: it asks first (the prompt, a fingerprint); away 70 s: not locked; switched back on.
8. No PIN, pattern or fingerprint: the first-run row is Off with the line above and a Settings button to the phone's screen-lock settings (`53`); in Settings the switch is off with **Set a screen lock** (`62`); the app opens without a lock and never shows "Locked".
9. Location (each timed; Begin is never held up, 0.27–0.28 s from the tap to the recording starting):
   - Allowed once, `adb emu geo fix -111.68 40.28`: the next blessing carries 40.3, −111.7; Settings "Near 40.3° N, 111.7° W".
   - Refused ("Don't allow"): Settings "Near Salt Lake Temple" (`63`).
   - Location off for the whole phone, the app allowed: the app answers at once (its log: "none (location off)" in 0 ms on the Pixel 3a; on Pixel_10_Pro, before that log was added, the screen read back in 3.9 s, nearly all of it the screen read itself); still the Salt Lake Temple, and the next blessing has the Temple (40.7704, −111.8919). Once, Android 17 put its own "No location access … Turn on location" over the app; the run closes it if it comes.
10. Killed (`am force-stop`) while locked: reopens locked. Killed while the prompt is up: reopens locked with one prompt; Cancel, and no second prompt comes.
11. Spanish by the phone's language (`cmd locale set-device-locale es-US`): the rows, Android's question, the lock screen and Settings (`67`–`71`). Android's largest font (2.0) and display size (1.3 × density), English and Spanish: first run, Android's question, the lock screen, Settings (`72`–`85`). At that size the rows put Allow beneath the words and the page scrolls; nothing is cut.
12. `tool/android_lock.sh` runs 1, 2, 3, 6, 7 and 9 unattended: 25 of 25 checks passed, boot to shutdown in about 20 minutes. Its recent-apps check measures the card's picture, not only the accessibility tree (the tree alone passed while the blessing was readable).

**Pixel 3a, Android 14 (the AVD is `Pixel_3a_API_34_extension_level_7_arm64-v8a`), the same script:** 25 of 25: steps 1, 2, 3, 6, 7 and 9 as above; the recent-apps card plain with the lock on (`86`), the app as it is with it off (`87`), locked (`88`), first run answered (`89`); Begin 0.30–0.32 s; with location off for the phone the app answered "none (location off)" in 0 ms (its own log). Android 14's prompt has no Cancel button ("Tap to cancel authentication", or back); the app behaves the same.

**Two ways the lock failed open, fixed 2026-11-17 (found by a security review of the task 11 commit).** Both in `LockChannel.kt`; `tool/android_lock.sh Pixel_10_Pro --only p,s,9` run once afterwards.

- *Leaving while one of Android's permission questions was up was not counted as leaving.* `left()` (from `onStop`) skipped the clock and the cover whenever a question or the unlock prompt was up, so Home pressed over the location question left the app unlocked for as long as it was away. Now `onStop` always notes the time and places the cover; the exemption stays only in `focus()` (a question taking focus is not leaving). The unlock prompt itself never stopped the activity on either emulator (it only takes focus), so the change cannot lock a person out mid-prompt. *Proved by step p:* the location question opened from Settings, Home, 68 s away, back: behind the question, which Android still shows, the app is already the locked sky, with no blessing on screen; answering the question leaves "Locked" and **Unlock** (the prompt does not open by itself because Android's question was on top when the app asked; one tap on Unlock brings it). **Not met:** recent apps does not show the plain card at that moment. It shows Android's question over the screen that asked (here Settings: "To pass along 0", nothing of a blessing). The question is the permission controller's own activity on top of the app's task, and Android takes its picture; the app's "no screenshot" setting covers only the app's own windows. Questions are asked only from first run, Settings, and Begin, none of which shows a blessing's words. See section 14, question on recent apps.
- *The cover lifted before the lock was decided when Dart was slow or failed.* `tell()` lifted the cover on an error, on "not implemented", and after 1.5 s regardless. Now it lifts on Dart's answer however late. On an error, "not implemented" or the 1.5 s limit, it lifts only when the return cannot lock: not a return from the background, or away under 30 s (half of the 60 s `lockAfter`, so a clock read a little early or late, or a rule changed in Dart, can never turn a locking return into one that lifts unasked). *Proved by step s,* with a debug-only hook (`files/slow_active`, read only in debuggable builds) that holds Dart's answer back 6 s: away 70 s, 3 s after return the screen is still the plain ground (spread 0.000); the late answer then locks and its prompt shows; after the unlock the cover is gone. 3 of 3.
- Step 9 of that run stopped at its start (the launcher was showing when it looked for the app, after step p's permission reset ended the app); it passed in the 25-of-25 runs before the fixes. In the first run after them, its two failures came from the first version of step p leaving the microphone refused, and the five steps 1, 2, 3, 6 and 7 passed 18 of 18 with the fixes in.

**Three fixes and a third way the lock could fail open, 2026-11-17 (later).** Proved by one run of `tool/android_lock.sh Pixel_10_Pro` (all steps): **33 of 33 checks passed** (`app/build/android_lock/Pixel_10_Pro/summary.json`). A first attempt stopped before the app was installed: the fingerprint helper found the Play Store's sign-in page on screen just after boot. Nothing had been changed by then; the second attempt is the run counted.

- *The PDF's text now copies as written.* `SharedPdf` draws with fixed cuts of the app's own Newsreader, one per size the PDF uses (8.5, 9.5, 11, 12.5 and 26 pt regular; 13.5 pt italic). They were made with fontTools' instancer from `assets/fonts/Newsreader*.ttf` at weight 400 and the optical size equal to the size, so the page is drawn as before. They live in the Android assets only (`android/app/src/main/assets/pdf_fonts/`, under the same SIL OFL as `assets/fonts/Newsreader-OFL.txt`); iPhone is unchanged. Any other size falls back to the variable font. Android's PDF writer now embeds them as TrueType with a Unicode map (`Newsreader16pt-Regular [Type0]: embedded (FontFile2), text: ToUnicode`), where before it drew Type 3 shapes. `tool/pdf_check.swift`: "the words extract in order and equal the blessing's (92 words)". Page 1 before and after: `design/sim/android/143-pdf-page-1-before.png` and `144-pdf-page-1-after.png`. The lines, line breaks and glyphs are the same; the text renders a hair darker, because it is drawn as text rather than as filled shapes. **The app grew by 395 KB** in the APK (708 KB of fonts, deflated). **Still failing one check:** the PDF has no document title. Android's `PdfDocument` has no way to set one; the old PDF had none either.
- *The lock script's location step* now brings the app back to its sky before it starts (step p's permission reset ends the app, and step s may leave it). It passed: Begin 0.26 s; the place rounded to (40.3, −111.7); refused: the Salt Lake Temple; location off: answered in 1 ms.
- *The unlock prompt now opens by itself after one of Android's questions.* Before, `authenticate` answered "no" at once while a question was up, so a locked return behind Android's location question waited for a tap on Unlock. Now the request is held and the prompt opens as soon as the question is answered and the app has the screen again (`LockChannel.questionGone`, from `onRequestPermissionsResult` and from the window regaining focus). The prompt never opens over the question, so two system dialogs are never up at once. Step p: "once the question is answered, the unlock prompt opens by itself (no tap on Unlock)". Step p's recent-apps check now asks only that nothing of a blessing is in the card. The plain card cannot be had there (see above, and section 14, question 24); the measurement is still printed beside it.
- *A focus change could undo the fail-closed rule* (found by a security review). After five minutes away, `tell(300, true)` waits for Dart's answer. If the notification shade was pulled down and closed before Dart answered, the focus return sent `tell(0, false)`. That call, now the newest, could lift the cover 1.5 s later without the first answer. Now a return that may lock (from the background, 30 s or more) sets a sticky `mayLockUnanswered` flag, cleared only by Dart's success for that call or a later one (Dart handles the calls in order); while it is set, nothing lifts the cover without an answer. Step s holds the answer back 10 s (the debug hook), opens and closes the shade 4 s after the return, and 2 s later checks the screen: still the plain ground (spread 0.000). The late answer then locks, and after the unlock the cover is gone.

**iPhone after this work:** `flutter analyze` clean, 309 unit tests pass. On the clean simulator, shut down and booted before each: the `home` integration test, `drafts_acceptance.sh`, `share_acceptance.sh`, `file_acceptance.sh` and `first_run_acceptance.sh <udid> all` pass. **Not run**, because the Mac's audio service is still stuck ("the recorder would not start", above): the iPhone lock, record, recovery, polish, speech, Spanish and link runs. No iPhone string was changed.

### Built 2026-11-17: sending and receiving (tasks 13 and 14)

**What was built.** `ShareChannel.kt` answers the iPhone's `upon_thy_head/share` channel with the same methods and keys, so every rule is the Dart one iPhone uses (the S3 sheet, `lib/share/`). Links are made in Dart as on iPhone (AES-256-GCM, a new key per link, the key after `#`; `website/PROTOCOL.md`); the service address is the one constant `linkService` with the `LINK_SERVICE` build-time override.
- **Copy link**: Android's clipboard, marked `EXTRA_IS_SENSITIVE`, so Android 13+ shows "Content copied" without the link in its preview, as it does for passwords. The app keeps no copy of its own.
- **Send the link**: Android's share sheet (`ACTION_SEND`, `text/plain`, the link alone, the title as the sheet's heading). The app hears when the sheet closes (`startActivityForResult`) and what was chosen (the chooser's callback); "Stop" and the Sent sheet follow as on iPhone.
- **Text and PDF**: the text through the same sheet; the PDF laid out as iPhone's (`SharedPdf`: Letter in the US and Canada, A4 elsewhere, an inch of margin, the same headings, widow and orphan rules and footer), written to `cache/share/` and handed over through the app's own read-only provider (`BlessingFiles.kt`, `content://dev.summitstudio.uponthyhead.files/share/…`, granted to the receiving app only for that share). No storage permission is asked or declared.
- **No internet**: the one line "No internet, so a link cannot be made now." and **Send as a file**: the `.blessing` file through the same provider, named "<title>, <date>.blessing", type `application/vnd.uponthyhead.blessing`. Under it Android says "It opens only in Upon Thy Head." and, as the file row's hint, "Opens in Upon Thy Head on another phone." (`asFileHintAndroid`; iPhone's "…another iPhone." unchanged).
- **Receiving a link**: `https://uponthyhead.app/b/…` with `autoVerify` (section 7). The fragment arrives whole. Cold, background and during a recording (the sheet waits until after Amen), behind the app lock (task 11).
- **Receiving a file**: the narrowest filters that still catch a blessing: `VIEW` of its own type; `VIEW` of `application/octet-stream` from `content://` (Gmail and most mail apps report that for a type they do not know); `VIEW` with no type and a name ending `.blessing`; `SEND` of its own type. Not offered for pictures, PDFs, zips, or for sharing any unknown file. Read on a thread, at most 512 KB; anything else is "This file could not be read."
- **Cleartext**: refused in release (`usesCleartextTraffic="false"` and `res/xml/network_security_config.xml`); the debug build alone (`src/debug/res/xml/`) allows `10.0.2.2`, `127.0.0.1` and `localhost`. Dart's `HttpClient` does not read Android's config, so `HttpLinkService` itself refuses any address that is not `https`, except `http` in debug builds. *Proved by* the merged release manifest (`build/app/intermediates/merged_manifest/release/…`: `android:usesCleartextTraffic="false"`, `android:networkSecurityConfig="@xml/network_security_config"`) and the merged release config (`<base-config cleartextTrafficPermitted="false" />`, no `10.0.2.2` anywhere in the release resources).

**Proved by `tool/android_share.sh`** (steps 1, 3, 5, 6 and 8 unattended, plus 9, 4 and 10; every step has a limit; the website runs on 4319 with a temporary store, `tool/link_proxy.py` on 4320 writes down every request). Pixel 10 Pro, Android 17; the numbers are those of `design/sim/android/`:
1. "Comfort before surgery": the S3 sheet (`90`), Link made (`91`), Copy (the clipboard read back equal, marked sensitive), Android's share sheet holding the one link (`92`; pair `pair-23-share-sheet.png` beside iPhone's), handed over as `text/plain` with nothing else. The link opened in Chrome on this Mac: the four paragraphs character for character (`93`).
2. Every request the app made, read back: no key in any address, header or body; each stop token only in its own stop's `Authorization` header (12 requests: 2 creates, 1 stop, 9 fetches).
3. The phone's data cleared so it becomes the receiver. The link: "You already have this blessing." (`103`). Deleted, then the link: the keep sheet (`101`; pair `pair-24-keep-sheet.png`), Keep, the reading page (`102`); the record as sent, field for field, its five changes, its tags, its place to a tenth of a degree (40.2, −111.7). Refusals, each with its own words: key missing (`104`), a different copy (Keep mine / Replace mine, `105`), made by a newer version (`106`), a wrong key (`107`), expired ("This link has stopped working."), no internet ("This blessing is on its way.", `108`). The contract's first vector opens.
4. A link arriving with the app closed, in the background, and during a recording: nothing shows while recording (`109`), the keep sheet after Amen. (The phone's own lock screen: see the Pixel 3a below.)
5. "Your links" (`97`), Stop: "Stopped November 17" (`98`); the web page then says the link has stopped (`99`); opened in the app: "This link has stopped working." (`100`).
6. No internet: the one line and Send as a file (`110`); handed over as `application/vnd.uponthyhead.blessing` through the provider (`111`); the shell, which has no grant, is refused ("Permission Denial"); the file pulled off is a valid blessing file; the app uninstalled and reinstalled, the blessing deleted, the file tapped in Files: the keep sheet (`113`), kept with the words as sent.
8. Android's own resolver (`cmd package query-activities`, as any app opening a file asks): the app is offered for its own type, `octet-stream` from `content://`, and a name ending `.blessing` with no type (both `file://` and `content://`); not for a picture, a PDF, a zip, or sharing an unknown file. In the Files app the emulator asks **Open with**: Upon Thy Head, Google Wallet, Google, then Just once / Always (`112`), because Wallet also takes `octet-stream`; then "You already have this blessing." (`114`). A zip renamed `Notes.zzz` opened with the app, and a `.blessing` that is not one: "This file could not be read." (`115`).
9. Text: the share sheet holds the title, date and words. PDF: handed over as `application/pdf` through the provider; Newsreader at every size, Letter, nothing past the margins, no footer on a one-page blessing, searchable ("in the name" found) (`96`). **Fails one check:** Android's PDF writer (Skia) cannot embed a variable font, so it draws Newsreader's glyphs as Type 3 shapes. The page looks right and searches, but text copied out of it comes apart ("u pon yo r head"). The fix is static instances of Newsreader for the PDF alone (section 14).
10. Spanish (`116`–`119`) and the largest font and display size, Spanish (`120`–`123`) and English (`124`–`127`): the S3 sheet, Link made, Your links, the keep sheet. **Found and fixed:** at the largest sizes the S3 sheet ran off the top of the screen and "Only the words" was squeezed to a letter a line. Every sheet (`lib/widgets/sheet.dart`) is now never taller than the screen and scrolls inside, and "Only the words" goes above Text and PDF when it would take more than 45% of the row. At ordinary sizes nothing moves; iPhone gets the same fix at its largest sizes.

**Pixel 3a, Android 14** (steps 1, 9, 3, 6 and 4; `133`–`142`): 30 of 31, the one failure the same PDF text fault. Copy is marked sensitive and read back on Android 14 too. Step 4 there also covered **the phone's own lock screen**: a link arriving with the screen off and locked opens nothing until the phone is unlocked, then the keep sheet (`141`).

**iPhone after this work:** `flutter analyze` clean, 309 unit tests pass, and on the clean simulator `share_acceptance.sh` and `file_acceptance.sh` both "ALL PHASES PASSED". Not run on iPhone: `link_acceptance.sh` and the other acceptance scripts (outside the brief's list); the sheet height and words-row change was proved on iPhone only through those two scripts (accessibility-medium text size), not at the largest sizes.

Debug builds only, the app writes to Android's log what it handed over (type, kind, address, length; never the words or the link) and what it read back after Copy (length, equal, sensitive), so the script can check them.

### Stand-ins (what Android says until each task lands)

Every iPhone channel has an Android answer in `MainActivity.kt` (`NotYet`) that means "this phone cannot", never "done", and `lib/not_yet.dart` names the same list on the Dart side. Nothing crashes and nothing pretends.

| Stand-in | What the person sees | Replaced by |
|---|---|---|
| Writing the words | Recording is real (tasks 4–7). After Amen: "The recording is kept" and "The words will be written on this phone in a coming version of the app. The recording stays here until then."; the blessing is a draft (counted by the drafts badge, marked `WordsStatus.later`). Its review page has the player and the same line ending "You can also type them here." The recording is never erased while its words are still to come (see **The audio rule** below). The first run's practice is skipped. The welcome page still says "The words are written on this phone." (section 14, question 13) | Tasks 8–10 (the seam: `transcribe` in `SpeechChannel.kt`) |
| Receiving a link from another app | The app's handling is real (task 13, from the moment Android hands it the link). A link tapped in Messages or Gmail opens the web page instead until the site serves `/.well-known/assetlinks.json` with the release key's fingerprint (section 7, "When the site goes live"); the web page reads it too | When the site goes live |
| Listening back with the phone locked | The review page's player works on screen (play, pause, back 10 s, the scrubber); leaving the app pauses it | Task 18 |
| The phone check page (test builds) | Answers "unavailable" | Its own task, not yet numbered |
| The recording-language menu | Tap to cycle languages (Flutter has no menu matching iOS's) | With tasks 8–10, when the language decides which words are written |

**Wording still written for iPhone** and needing an Android version when its feature lands (all in `lib/strings.dart`; iPhone's wording stays as is): the phone check's strings, the speech row's strings.

*Done with tasks 13 and 14:* `asFileHint` (Android: `asFileHintAndroid`, "Opens in Upon Thy Head on another phone." / "Se abre en Upon Thy Head en otro teléfono."; no screen shows it today, the S3 sheet having replaced the sheet that did). The rest of the sharing words already said "this phone", never "iPhone". `NotYet.sharing` is gone.

*Done with tasks 11 and 12:* `noPasscode` (Android: `noScreenLock`), `faceIdWhy` (Android: `lockWhyAndroid`, "To keep your blessings locked. Allow turns it on and asks once."), the Face ID / Touch ID names (Android: `screenLock`, `fingerprintOrScreenLock`), `lockHint` (Android: `lockHintAndroid`, "Asks for your fingerprint or screen lock…" / "Asks for your screen lock…"), and `settingsFor` for the lock row (`settingsForScreenLock`, "Open Settings to set a screen lock"). `openSettings` ("Open Settings" / "Abrir Configuración") and `stillNeeded` were already right on Android: Android's Settings app is "Settings" / "Configuración" on a Pixel, and only the microphone is required there, so `stillNeeded` only ever says "Allow the microphone to go on." "Not available on this phone yet." (`notYetOnThisPhone`, `lockNotYet`, `locationNotYet`) is gone.

### The plan

1. **Make the Android project and switch SQLite to the bundled build.** Proved by: the app opens on the Pixel_10_Pro emulator (Android 37, 16 KB pages) and shows the five samples behind the test flag; iPhone still builds.
2. **Edge-to-edge and back gesture.** Proved by: the rings clear the gesture bar on the emulator; a back swipe while recording does nothing; a back swipe on review returns as on iPhone.
3. **The sky on Android.** Proved by: emulator screenshots of home, zoomed and recording beside the iPhone simulator's, with no clear difference in brightness. (Repeat on the real phone in task 15.)
4. **Recording to ADTS parts and joining them.** *Done 2026-11-17 (see Built so far).* Proved by: an emulator recording of known speech plays back and matches what was heard; `seconds` matches. (Not from the Mac's microphone: see section 13.)
5. **Recovery after a kill.** *Done.* Proved by: start a recording, force-stop the app from adb (`am force-stop`), reopen it, and "recovered" shows with the length lost under 3 s.
6. **The microphone foreground service and notification.** *Done.* Proved by: recording continues with the emulator screen locked for 5 minutes, and the notification shows.
7. **Giving way to a call.** *Done.* Proved by: the emulator's simulated incoming call (`adb emu gsm call`) pauses the ring, a new part starts after hang-up, and the joined file has both halves.
8. **ML Kit Basic transcription on a file (English).** Proved by: a fixed English recording (the `debugFeed` file the iPhone tests use) comes back as the expected words on the emulator *(whether ML Kit Basic runs on the emulator is unconfirmed; if not, this moves to the real phone)*.
9. **Spanish and the engine choice** (`engine` method: Advanced, Basic or none). Proved by: `describe` reports each mode's status and locales; "unavailable" is handled exactly as on iPhone.
10. **Paragraphs from pauses.** Proved by: a recording with 3-second gaps gives paragraph breaks where iPhone does.
11. **The app lock and recent apps. Done 2026-11-17.** Proved by: on the emulator, a fingerprint enrolled and touched from adb (`adb emu finger touch 1`) unlocks; locks after 60 s away; never locks during a recording; the recent-apps view shows plain colour. *As proved:* see **Built 2026-11-17: the lock, recent apps, location**, steps 1–8 and 10–12.
12. **Location and the first-run screen. Done 2026-11-17.** Proved by: a fresh install walks the four rows and each system question; refusing location falls back to the Salt Lake Temple. *As proved:* the same block, steps 1, 9 and 11.
13. **Sharing: the link, text, PDF and `.blessing`. Done 2026-11-17** (the PDF's text fixed later that day). Proved by `tool/android_share.sh` against the website on this Mac; see **Built 2026-11-17: sending and receiving (tasks 13 and 14)**.
14. **Receiving a link and a `.blessing` file. Done 2026-11-17.** Proved by the same script, steps 3, 4, 5 and 8; the same block.
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
- *The Pixel_10_Pro's storage is nearly full* (about 480–600 MB free). A second install of the debug APK beside the first does not fit, so `tool/android_tests.sh` installs once and attaches to the installed app for the restart part. Android also refuses any install below its low-storage line (about 500 MB, `INSTALL_FAILED_INSUFFICIENT_STORAGE`), so `tool/android_record.sh` lowers that line to 200 MB for the run (`settings put global sys_storage_threshold_max_bytes`) and removes the setting when it ends. The other apps on the emulator were left alone. Growing its data partition in Device Manager would remove the problem.
- Layout, the back gesture, the database, the first-run screens.
- Recording, a kill and recovery, locked-screen recording, a simulated incoming call (`adb emu gsm call`), all with a known sound instead of a microphone:
  - *Emulator 36.5.11 and host audio do not mix.* With the Mac's audio on, the emulator hangs the moment anything opens the microphone; its own way of feeding the microphone a file (gRPC `injectAudio`) crashes it at the first packet. So `tool/android_record.sh` boots with `-no-audio` (the microphone then delivers silence) and `-crash-report-mode never`.
  - *The debug microphone source.* In a debuggable build only, if `files/debug_mic.pcm` (32 kHz mono 16-bit) is there at Begin, `SegmentRecorder` writes its samples in place of the microphone's, one for one and at the microphone's pace, paused or not. Everything else is the real path: `AudioRecord` runs, the encoder, the parts, the service, the join. Release builds never look for the file (`FLAG_DEBUGGABLE`). Recording from the Mac's microphone was tried and is not possible here.
  - What it cannot show: the microphone's own sound, its gain, and what a real phone does to it.
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

**Cannot be proven without a real phone** (tasks 4–7 and the player):
1. A real voice through a real microphone: level, noise, and that 24 kbit/s at 32 kHz sounds as it does on iPhone. The emulator's microphone was replaced by a file (above).
2. A real call: the emulator's call is a modem simulation; whether a real dialler's audio focus, a VoIP call (WhatsApp, Meet) or a call answered on a watch pauses the recording.
3. Another app taking the microphone (the silenced flag): the emulator has only one microphone and no second recording app was run against it.
4. A Bluetooth headset connecting mid-recording (the recording should stay on the built-in microphone, `setPreferredDevice`): the emulator has no Bluetooth audio.
5. Makers' battery savers (Samsung, Xiaomi, OnePlus) stopping a foreground service during a long locked recording; Doze over hours, not 10 minutes.
6. Heat and battery over an hour's recording, and the size of an hour's file on the phone's own encoder (the emulator's is software).
7. The notification on Samsung's One UI and other makers' lock screens.
8. Swipe-from-recents behaviour on launchers other than the Pixel's (some makers kill the process outright; recovery should still hold, as with `force-stop`).
9. Sound through the phone's own speaker on the player (the emulator ran without audio; the player's position and controls were proven, not the sound).

**Cannot be proven without a real phone** (tasks 11 and 12):
10. A real finger on a real sensor, and an under-display sensor's own animation over the prompt; the emulator's fingerprint is a simulated touch.
11. Face unlock: the emulator has none. On Pixel 8 and later it counts as strong and the prompt would offer the face; on most other phones it is weak and the prompt offers fingerprint or PIN only. The row then says "Screen lock" on a phone whose face unlock is all the person uses (section 14).
12. Makers' recent-apps screens (Samsung, Xiaomi, OnePlus): whether each shows a live tile, a snapshot, or the window's colour, and whether the cover goes on in time. Proven only on the Pixel launcher (Android 17 and 14).
13. Makers' own prompts: Samsung and others restyle `BiometricPrompt`, and some put PIN and fingerprint on separate screens.
14. What Android does after too many wrong fingerprints on other phones and versions (Android 17 on the emulator locks the whole phone at the fifth).
15. A real location: an indoor fix through Wi-Fi and cell towers with Google's network location, how long the first fix takes after a reboot, and whether the 6 s limit is enough there. The emulator has no network location and answers through its simulated GPS.
16. "Only this time" lapsing in real use (Android lets it lapse a short while after the app leaves the screen) and the next blessing keeping the place found.

**Cannot be proven without a real phone** (tasks 13 and 14):
17. A `.blessing` file arriving through Gmail, WhatsApp, Google Messages and Quick Share: the type and name each keeps, and whether tapping it offers Upon Thy Head. The emulator proves what Android does with each type and name (step 8: its own type, `application/octet-stream`, no type with a name ending `.blessing`), not what each app hands over. Gmail is known to report `application/octet-stream` for attachments it does not know; WhatsApp is known to rename some files.
18. A link tapped in Messages, Gmail or WhatsApp opening the app: needs the live site's `assetlinks.json` and a Play-signed install (section 7, "When the site goes live"); `pm get-app-links` on the phone then shows `uponthyhead.app: verified`. On the emulator links were handed over as Android hands a verified link (`am start -a VIEW -d https://uponthyhead.app/b/…`).
19. Locked when a link arrives: the link waiting behind the lock was proven for the recording screen and in task 11 (a blessing arriving waits behind the lock); a link handed over while the phone's own lock screen is up was not run.
20. Makers' share sheets (Samsung's own, Xiaomi's): that each shows the link as the text, and that Copy in them leaves the link hidden in the clipboard preview as Android's own does.
21. Opening the PDF in Google Drive's viewer, Samsung Notes and a printer's app: the emulator proves the file (`tool/pdf_check.swift`), not each viewer.

**Which phones:** *(prices and exact models unconfirmed)*
1. **Pixel 10** (or Pixel 10 Pro). It is on Google's list for both ML Kit Advanced speech and AirDrop with iPhone, it is Google's reference phone, and it gets updates first. Buy this one.
2. **A mid-range Samsung Galaxy A** (A26 or A36, about $250–400): the phones most families actually own. It tests ML Kit Basic only, Whisper's speed, Samsung's My Files and One UI's battery management. Borrow one if possible.

If only one phone: the Galaxy A, because it is where the speech plan is most at risk. The Pixel can be borrowed later for AirDrop.

---

## 14. Open questions for Noah (most important first)

1. *(Settled by 3.5 and question 27: every Android phone downloads Whisper, for both languages.)* **Spanish on Android may need a download.** If measuring shows Google's built-in Spanish is not good enough on ordinary Android phones, is it acceptable that Spanish on those phones asks to download about 180–550 MB once (Wi-Fi, with consent) before the first Spanish blessing can be written? The recording would still be kept and written after the download.
2. **Google's usage statistics.** Google's speech library reports app and device details and timings (never the audio or the words) to Google, and the store listing must say so. Is that acceptable? The alternative is Whisper only, at the cost of a download for everyone and slower writing. **Answered 2026-11-16: acceptable** ("That's their device… That's not on us").
3. **May Android launch after iPhone?** The Play Store's waits add weeks whatever the build speed. **Answered 2026-11-16: no, they launch together.**
4. **Listening back while locked on Android shows a playback notification with controls.** Android requires it. Acceptable? (Or listening back stops when the phone locks, on Android only.)
5. **Which Play account?** A personal account (12 testers for 14 days before launch) or Summit Studio LLC as an organisation (needs a D-U-N-S number, up to 30 days)? **Answered 2026-11-16: Summit Studio's organisation account already exists** (Starcard is on it), so neither wait applies.
6. **Moving to a new Android phone.** Turning backup off keeps blessings out of Google Drive. Some phones still copy app data on a phone-to-phone transfer, which would carry the blessings (never the audio, if it is kept in the no-backup folder). Should blessings travel to a new phone that way, or not at all?
7. **The minimum Android version:** Android 13 recommended. Agree? **Answered 2026-11-16: Android 13.**
8. **A phone to buy or borrow:** a Pixel 10, a Galaxy A, or both? **Answered 2026-11-16: none. No real Android phone before launch.**
9. **Hiding the app in recent apps** shows a plain sky-coloured card on Android, not the sky picture iPhone shows. Fine?
10. **The app in "Open with" for unknown files.** To catch `.blessing` files from Gmail and WhatsApp, the app may appear in "Open with" for other unknown files too, and says "This file could not be read" if picked. Acceptable?
11. **The name under the icon** (found in task 1). On the Pixel launcher "Upon Thy Head" is cut to "Upon Thy He…" (`08-launcher-home.png`). The Pixel home screen shows one line *(other launchers may differ)*. Keep it cut, or give the launcher alone a shorter name (the app's own name stays "Upon Thy Head" everywhere else)? If shorter, which words?
12. *(Answered by task 11: with the lock on, recent apps shows the plain ground colour.)*
13. **The welcome page promises what Android cannot do yet** (found with task 4). The first page says "The words are written on this phone." On Android today the recording is kept and the words come in a coming version. Leave the welcome as is until tasks 8–10, or give Android its own line meanwhile (for example "Your voice is kept on this phone; the words follow in a coming version")?
14. **No practice on Android's first run.** The iPhone's first run lets you say a line and see it written; Android skips that page because nothing can be written yet. Fine until tasks 8–10?
15. **Blessings that wait for their words.** Each Android blessing recorded now stays a draft-like "words to come" until a later version writes them, and its recording (about 11 MB an hour) stays on the phone until then, even after Done. Acceptable, or should Done on a blessing with typed words let the recording go?
16. **The emulator's storage** (Pixel_10_Pro, about 480 MB free). Every test reinstalls the app because two copies do not fit. Growing its data partition in Device Manager would make runs faster and safer; may I (or will you)?

---

**Found with tasks 11 and 12** (each as it would look on the phone):

17. **A refused row moves the rows above it.** On the first run, refusing location (or the microphone) puts "Off" and a Settings button under that row's words, so the screen grows and the rows above it move up by about a line. Answered rows never move. iPhone does the same today. Keep it, or give every row the room for the Settings button from the start (more empty space under each row)?
18. **Skipping the lock row leaves the lock on.** If Continue is pressed without tapping Allow on "Fingerprint or screen lock", the app is still locked the next time it opens after a minute away, as on iPhone (the lock is on unless turned off in Settings). Should Android's lock instead stay off until Allow is tapped, so the row's "Optional" means what it says?
19. **The Settings row is called "App lock", not "Screen lock".** The method is in the line beneath ("Asks for your fingerprint or screen lock when you open the app"). The brief asked for the name "Screen lock"; "App lock" was kept because it is what the switch does (it locks this app, not the phone), and the same word is used on iPhone. Rename it?
20. **Phones whose only unlock is the face.** On most Android phones other than recent Pixels, face unlock is rated weak, so the app's prompt offers only the PIN, pattern or password; the row says "Screen lock". Someone who always unlocks by face will type a PIN to open the app. Acceptable?
21. **The notification shade covers the app.** With the lock on, pulling down the notification shade lays the plain ground over the app until the shade closes, as iPhone covers it for Control Center. Fine?

**Found with tasks 13 and 14:**

22. *(Fixed 2026-11-17: fixed cuts of Newsreader for the PDF, 395 KB more in the app; the text copies as written.)* **A PDF from Android looks right, but its text copies out broken.** Selecting or copying words from the PDF gives "u pon yo r head"; searching still finds them. Android's PDF writer cannot embed Newsreader as it is (one variable font), so it draws the letters as shapes. Fixing it means adding fixed Newsreader fonts for the PDF alone (about 1 MB more in the app). Add them, or ship as is?
23. **Tapping a `.blessing` in Files asks "Open with": Upon Thy Head, Google Wallet, Google, then Just once / Always.** Wallet also claims unknown files. Once someone taps Always it goes straight to the app. Acceptable?
24. **Recent apps over Android's own permission question** shows that question over the screen that asked (Settings during the first run; never a blessing). The app's plain card cannot be put under Android's question. Acceptable?
25. **Android's share sheet shows the whole link, key included,** in its preview at the top; iPhone's shows only the domain. Anyone looking at the screen while sharing could read it. Acceptable (it is the same link that is being sent)?
26. **Until `/.well-known/assetlinks.json` is live with the release signing key, a link tapped in Messages opens the web page, not the app.** Nothing to decide; a reminder for launch.

**Found with the speech measurements (3.5, 2026-11-17):**

27. **Every Android phone downloads 58 MB before its first blessing can be written.** On the first run, a row says "Writing the words down. A one-time download of 58 MB lets this phone write your blessings in words. Your voice never leaves the phone", with **Download** and **Later**. (This also settles question 1: English and Spanish both use the download.) Acceptable, and is that the wording?
28. **After Amen, "Writing the words…" for a few minutes on an ordinary phone.** It is estimated at 2–3 minutes for a 10-minute blessing (measured at 35 s on the emulator). Acceptable?
29. **A word can go missing after a pause** (for example "Emma," at the start of a paragraph). The review page shows what was written for the person to fix, as on iPhone. Should Android's review page also say something like "Check the words; a word after a pause can be missed"?
30. **If the app is closed while it writes,** the writing waits and finishes the next time the app opens, with no notification. Or it keeps going in the background and shows a notification, "Writing the words of a blessing", until done. Which?

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
