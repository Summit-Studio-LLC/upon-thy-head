# Working on Upon Thy Head

For people and coding agents. Read this first; it is short. `CLAUDE.md` points here.

## What this is

A free app for iPhone, iPad and Android that turns a priesthood blessing into a written record kept on the person's own device. Home is a real night sky; each blessing is a light on a ring, placed by its date. `README.md` has the overview.

- `app/`: the app. Flutter (3.44, Impeller), with native Swift (`app/ios/Runner/`) and Kotlin (`app/android/app/src/main/kotlin/dev/summitstudio/uponthyhead/`) behind method channels for recording, speech, the lock, sharing, location and proof of the app.
- `website/`: the landing page and the small service behind shared links (Next.js on Vercel, storage in Postgres). `website/PROTOCOL.md` is the contract; `website/AGENTS.md` has Next.js notes.
- `docs/decisions-and-parked-ideas.md`: every decision, newest first, with what was proven and what was not. Read the latest entries before changing a feature.
- `docs/android-plan.md`: the map of Android: what is built, how each part was proven, what is left (section 12, "The plan") and the open questions (section 14).
- `docs/blessing-file.md`: the `.blessing` file and link record formats. `docs/spanish-strings.md`: Spanish wording notes.
- `design/`: prototypes and drawings. Not app code.

## Rules that do not bend

1. **The words stay on the device.** No analytics, crash reporters, ad or tracking SDKs, and no network call other than the link service (`uponthyhead.app`) and, on Android, the one-time speech model download. Do not add a dependency that phones home.
2. **Nothing of a blessing leaves the app's own screens** unless the person shares it: no names, dates, titles, words or counts in logs, notifications, Spotlight, launcher shortcuts, widgets or the app switcher.
3. **Never summarise or reword a blessing.** The exact words as written are always recoverable. Polish only removes filler sounds and repeated short words, and shows what it changed.
4. **The link service sees only locked bytes.** The key travels after the `#` in the link and never reaches the server. The service stores nothing about a device or a person and writes no logs of its own.
5. **While the app is locked, nothing of any blessing or family member shows**, including to a screen reader.
6. **Free, no ads, no account.**

## How the app is written

- **Its own widgets.** The app draws its own buttons, sheets, pills and menus (`app/lib/widgets/`); it does not use Material or Cupertino components. The look is dark, quiet and reverent: a night sky, serif headings, a few glass pills. Do not introduce new colours or a different visual language. Liquid glass on home's head comes from `liquid_glass_widgets`, pinned to an exact version on purpose.
- **Every string in English and Spanish**, in `app/lib/strings.dart` (iPad wording in `strings_ipad.dart`; Android wording has its own entries there). Note any Spanish you are unsure of in `docs/spanish-strings.md`.
- **Screen readers.** Every control needs a semantics node with the same tap action as its gesture. The pattern is in `app/lib/widgets/buttons.dart`; `app/test/screen_reader_test.dart` presses every control through the semantics tree.
- **Text size.** Screens must hold up at the largest accessibility text size. On wide screens, pages are centred columns (`app/lib/widgets/measure.dart`).
- **The store** is SQLite (`app/lib/data/store.dart`) with numbered migrations; it is at version 10. A schema change needs a migration and a test that an older store still opens with its blessings intact.
- **The file and link formats** are versioned and have test vectors shared by the app and the website (`website/protocol-vectors.json`, made by `website/scripts/make-vectors.mjs`, checked by `app/integration_test/protocol_vectors.dart`). Change the format, the docs and the vectors together, and keep every older file and link readable.
- **Comments** say why, in plain English. Match the style of the file you are in. Make small exact edits; do not reformat or rewrite a file you are not replacing.

## Checking your work

The project is built rapidly and evaluated once, in full, before a store release. So for each change:

```bash
cd app
flutter analyze        # must be clean
flutter test           # the whole unit and widget suite; about ten seconds
```

plus one look at the feature working on a simulator, emulator or phone. For the website: `cd website && pnpm test`.

The scripts in `app/tool/` (`*_acceptance.sh`, `android_*.sh`) are the long scripted checks. They assume one particular Mac's simulators and emulators, so you are not expected to run them; say plainly what you did and did not check.

When a feature lands, add an entry at the top of the current date in `docs/decisions-and-parked-ideas.md`: what was built, any choices you made that nobody ruled on (labelled as yours), what was proven and how, what was not, and questions for the owner.

## Android: where to start

- Minimum Android 13 (API 33). Package `dev.summitstudio.uponthyhead`.
- Each native piece is one Kotlin file beside `MainActivity.kt`: `RecordingService` and `SegmentRecorder` (recording as a foreground service), `WhisperEngine`, `ModelStore`, `SpeechChannel` and `WordsChannel` (speech written on the phone by whisper.cpp; prebuilt libraries are in `app/android/app/src/main/jniLibs/`, rebuilt by `app/tool/android_whisper.sh`), `LockChannel`, `LocationChannel`, `ShareChannel`, `LinkChannel`, `BlessingFiles`, `PlayerChannel`, `ProofChannel` (Play Integrity).
- A feature Android cannot do yet answers "this phone cannot", never "done": see `NotYet` in `MainActivity.kt` and `app/lib/not_yet.dart`.
- **Most useful now:**
  1. An initial build has been smoke-tested on a real Android phone; tasks 15, 17 and 19 in `docs/android-plan.md` still need their full real-phone pass: speech from a real voice in English and Spanish, receiving files and links from other apps, a real call, lock and kill during a recording.
  2. Features built on 2026-11-18 compile for Android but have not been seen on it: family members and their rings, entering a past blessing, handing a ring over by link, the liquid glass controls on home, and the iPad-pass layout changes.
  3. Listening back while the phone is locked is built (task 18, `PlaybackService`); it has not been heard on a phone. The open questions are in section 14.
  4. Play Integrity is built on both sides (`ProofChannel.kt`, `website/lib/links/proof.ts`) but can only be proven from an install off Play's internal testing track.
- Never test against the live link service. Run the website locally (`cd website && pnpm dev`) and point the app at it the way `app/tool/android_share.sh` does.

## Working alongside others

- The owner and the owner's agents commit straight to `master`. **Everyone else: work on a branch or a fork and open a pull request against `master`. Do not push to `master`.** A push to `master` that changes `website/` deploys to production.
- Keep a pull request to one feature or fix, and say which files you touched outside your area. The iPhone side changes daily; rebase before you ask for review.
- Do not change `version:` in `app/pubspec.yaml`, signing settings, bundle or package identifiers, or the release scripts (`app/tool/testflight.sh`).
- Never commit a secret: keystores, `.p8` keys, service-account JSON, `.env` files, tokens.
