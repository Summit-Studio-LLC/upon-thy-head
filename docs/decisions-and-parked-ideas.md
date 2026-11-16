# Upon Thy Head: decisions, parked ideas, open questions

Kept so nothing said in conversation is lost. Newest decisions first. Dates are when Noah decided.

## Decisions

### 2026-11-16

- **Link sharing (Noah, morning):** "yes, anyone holding the link can read the blessing." The link is to be built as the brief describes. Claude's reading: the brief's "stays between the two devices" may therefore be reworded to say plainly that whoever holds the link can read it.
- **The app icon (Noah, morning):** "let's use codex to create designs, NOT SVG. let's start with images and work our way simpler, 2d, flat. black and white. We'll add color later today." Codex makes the concepts as generated images, each taken in steps from a rich picture to a flat two-dimensional mark, black and white first. Rounds are kept in `design/icon/`.
- **First commit (Noah, morning):** everything is committed to `master` (2343944). Simulator screenshots and films in `design/sim/` (about 850 MB) are left out of git by Claude's choice, because the test scripts write them again; they stay on disk.
- **Icon directions (Noah, after round 1):** "i like the crown of lights middle one (simpler) most. but i also like the hands laying on. let's iterate in those directions". So: the crown of lights at its middle level of simplicity (`design/icon/round-1/6-crown-B.png`), and hands laid on a head. Round 2 (flat marks of the ring, hands and an arc over a head) was started by Claude before this and read as eyes and signal symbols; round 3 follows his two directions.
- **Icon, after round 3 (Noah):** "k7 is best" for the crown of lights (`design/icon/round-3/K7.png`: the sphere large and low, a thin arch with three lights that fades into the dark at its ends). For the hands: no gradients, flat, no 3D, just 2D; he was emphatic. The round 3 hands were soft three-dimensional renders and are rejected as a look. Round 4 was cancelled unfinished; round 5 follows this.
- **The icon's design (Noah, after round 5):** "let's go with G4." `design/icon/round-5/G4.png`: the softly lit sphere with the arch of three lights above it, at the soft level, filling the square a little more than K7. The hands are set aside. Colour comes next, in the Lamplight palette (round 6).
- **The icon is chosen (Noah, after rounds 6 and 7):** "we do need the icons to be bigger", then "M5 is it". `design/icon/round-7/M5.png`: G4 in the Lamplight colours, filling more of the square, lights and arch twice as heavy, the middle light the largest. The master is `design/icon/final/icon-1024.png` (the same image with its ground set to the app's #0B0907; the image tool had drifted to about #080604). It is installed in `app/ios/Runner/Assets.xcassets/AppIcon.appiconset` in every size. Not done yet: the dark and tinted variants newer iOS versions can use, and a favicon for the website.
- **Onboarding (Noah, same message):** "When the app first loads, the flow needs to be: 1. An opening screen 2. A welcome 3. Permissions 4. Getting them in. That's the flow we need to get worked out." Not designed yet; today the app opens straight onto the sky and asks for permissions at the first recording. Claude's first draft is in `design/onboarding/`.
- **The domain (Noah, later that morning):** "let's purchase the domain via cloudflare." `uponthyhead.app` was registered at Cloudflare on 2026-11-16 for one year ($8.20; renewal $14.20), with contact privacy on and auto-renew on, matching his other domains there (auto-renew is Claude's choice; say if it should be off). No app by this name is on the US App Store. The closest other app found is "LDS BlessingKeeper" ($9.99, July 2026, no ratings): it stores blessings typed, recorded or uploaded; nothing found records and writes the words on the phone.
- **The website (Noah, same message):** one landing page only, "simple, clean, elegant", design-led, with placeholders for pictures of the app, built with Next.js for Vercel. It is being built by a separate Fable thread in `website/`.
- **Phone:** the app was installed on the iPhone Air on 2026-11-16 by `tool/phone.sh`; Xcode added the phone to the signing profile, so the sign-in works, on iOS 27.3 with Xcode 26.2.
- **Rulings from Noah's numbered answers (2026-11-16, about noon).** He answered Claude's list of 25 questions; his numbers ran one behind the list after the first, so each is matched here to the question it answers.
  - **Onboarding, step 4:** "I would like to try the rehearsal and see how that goes. I'll probably give you feedback afterwards." Build the optional practice recording.
  - **Onboarding, permissions:** asked at first run, but not the moment the app opens: "we shouldn't immediately push it as soon as the app opens. We need to say, 'Hey, there are a couple of things we need,' and explain why we need each of them in quick succession. Should be simple and elegant."
  - **A shared blessing on first launch:** "Read first, I guess." Face ID is asked only when it is kept. "Not now" keeps nothing and the file can be opened again.
  - **The opening screen:** first launch only. Only the ring, no light ("I'll give feedback as we see it").
  - **The welcome's last line** ("Free. No account. No ads."): stays ("I guess that works").
  - **Someone who gives blessings:** "If the person is giving blessings, they shouldn't be able to have them. They would only have them if they were recording themselves and then handing it to the person who is receiving the blessing." Claude's reading: a blessing recorded for someone else is held only so that it can be handed to that person; it is not the recorder's to keep, has no light in their sky, and there is no "giver's sky". Not yet confirmed: whether it is removed from the recorder's phone once handed over.
  - **Tinted icon variant:** yes. **Auto-renew on the domain:** stays on.
  - **Commits:** "I don't care when you commit. You get to decide that." Claude may commit to `master` at sensible points without asking each time. (Pushing is still only on his word.)
  - **`design/sim/` stays out of git.**
  - **"Ajustes" or "Configuración":** Claude's pick, which is "Configuración".
  - **iPad:** "iPad and iPhone." The app is for both. Nothing has been checked on an iPad yet.
  - **The blessing file carries the place:** "both parties were part of it. Location can be shared, and that's fine." (This reverses the first build of the file, which left the place out.) A received blessing is marked as the receiver's own.
  - **A phone with no passcode:** what Settings says is enough. **After moving house:** "Use my location" in Settings is enough. **A recording killed in its first two seconds:** silence is right.
  - **Polish:** "ah" as a filler and Spanish "que que" left alone are both fine. **An unnamed blessing** shows as "Blessing" or "Bendición" by the phone's language.
  - **Put off, to be asked again:** finishing the phone check ("Please check up on me about that later"); skipping the speech permission on the new engine and offering the model on those phones (after the phone check); who the native Spanish speaker is ("Ask me later"); the PDF's details ("I'll review that later").
- **Permissions screen, icons (Noah, 2026-11-16, early afternoon):** "For the permissions, use some icons to the left of the titles of each permission for better hierarchy and scanability." Each of the four rows on "A few things first" gets a small line icon at its left, in the app's own icon style.
- **A blessing recorded for someone else, after it is handed over (Noah, 2026-11-16, about 1:30 pm):** "They get the option: they can have it stay on their phone or delete it." So once a blessing marked "Passing it along" has been shared, the app asks whether to keep it on this phone or delete it. It never has a light in the recorder's sky. This unblocks "Passing it along" and the list of everything recorded.
- **Launching the website (Noah, same message):** "You're welcome to launch it when you're done developing. Whether that's today or tomorrow doesn't matter. No one will visit it unless we start driving traffic to it." Claude may deploy the site to Vercel and point `uponthyhead.app` at it once it is finished, without asking again.
- **Android now (Noah, 2026-11-16, about 2 pm):** asked whether Android is still "later", he answered "the answer is no: we are doing Android now." The Android app is in scope now, alongside iPhone and iPad. A research task writes `docs/android-plan.md` first (what each native piece needs on Android, above all on-device speech); building follows once the onboarding task is out of the app. This Mac has the Android SDK and three emulators; no Android phone is connected.
- **How a blessing is handed over (Noah, same conversation):** his plan stands: "our own file format and try to use Bluetooth". The `.blessing` file through the system share sheet is that plan: AirDrop between iPhones, Quick Share between Android phones, and the AirDrop and Quick Share bridge (some Android phones only, as of 2026) or an attachment between the two. Building our own Bluetooth handoff inside the app is parked until the bridge is seen to fall short. Whether the share sheet also offers "As a link" is still open: he had not understood the question.
- **The share sheet (Noah, 2026-11-16, mid-afternoon):** "We should use icons as much as we can and avoid using text" and "We should encourage using a blessing file rather than just using text, which I feel people are going to try to do as much as they can." The sheet is to be redrawn: icons carry the choices, the blessing itself is the first and plainest choice, text and PDF are quiet. A mock is being made in `design/share/`.
- **The link, reopened (same message):** he first said to leave "As a link" out for now, then asked what happens when a blessing file reaches someone without the app, and said: "I feel like the whole point of having the link was that it would use the app clip. ... Maybe we still do the link, but we just do it in a secure way. I'm not sure." Undecided. The fact: a blessing file is a dead end for someone without the app. The mock draws both ways (file only, and a short link whose server holds only a locked copy) so he can choose.
- **Android rulings (Noah, 2026-11-16, later afternoon):**
  - **No real Android phone for testing:** "we won't test Android. We will let our users test them. As unfortunate as that is, we will do our best beforehand." So everything is proven on the emulators as far as they go, and what they cannot prove (above all real speech, real calls, Quick Share and AirDrop between phones) is listed plainly as unproven at release.
  - **Google Play account:** Summit Studio LLC already has an organisation developer account; Starcard was released on it. No 12-tester closed test and no D-U-N-S wait apply. The runbook to copy is `starcard/docs/release/play-store.md`.
  - **Google's speech library sends Google usage statistics** (never audio or words): acceptable. "That's their device. They've already accepted or decided that themselves. That's not on us." It still has to be declared on the Play listing.
  - **A Spanish model download on Android:** "We'll figure that out later."
  - **Minimum Android 13.**
  - **Launch together (Noah, a few minutes later):** "I will relaunch Android alongside iPhone." Claude reads "relaunch" as "launch": iPhone and Android go out at the same time, so the iPhone release waits for Android to be ready.
- **Sharing and the promise (same message):** "the words do stay on your phone, and it's understandable that if you share them, they're no longer on your phone." The promise does not need rewording for sharing. And handing a blessing from one phone with the app to another by Bluetooth needs no internet; internet matters only for a link.
- **Sharing is by link, for everyone (Noah, 2026-11-16, about 3 pm):** "I wonder if we just use the link for everything, because sharing the file directly might cause problems if the receiving end doesn't have the file. That's completely mitigated by our app link, universal links, and all the other stuff that points it to our app." So the main way to send a blessing is a short link. The phone locks the blessing before it leaves; a server (the website) holds only the locked copy for a limited time; the key is in the part of the link after `#`. With the app, the link opens the app; without it, a web page shows the blessing. The share sheet is layout **S3** from `design/share/` (Noah: "I like S3"): a small card of the blessing, the gold "Send this blessing" button, and "Only the words" with small Text and PDF buttons. Claude's choices, open to change: a link works for 30 days and the sender can stop it sooner; the blessing file is offered only when there is no internet, and never otherwise (Noah, later: "only if no internet, then yes"). The contract between app and server is `website/PROTOCOL.md`. This replaces the earlier "whole blessing inside the link" design and the "no link" answer given earlier the same day.
- **Test phone:** the iPhone Air on iOS 27.3 is the one plugged in. Developer Mode was off on it at the first try.

### 2026-11-15

**Recording and transcription**
- Speech engine: use Apple's new on-device engine where the phone supports it. Where it does not, Apple's older recogniser comes first, with a downloadable speech model as an optional upgrade the person must agree to before anything is downloaded (Noah, evening of 2026-11-15). Which model is still to be measured on a phone; the research below suggests WhisperKit.
- Recording continues while the phone is locked. Keep it (Noah, evening of 2026-11-15).
- A recording cut short by the app being killed must be recovered into a blessing. Build it now, not later (Noah, evening of 2026-11-15).
- Testing on a real phone: Noah's own iPhone, from 2026-11-16.
- Minimum iOS version: 17 (Noah, night of 2026-11-15, on Claude's recommendation).
- Drafts waiting for review: show a badge on the home screen when there are any (Noah, night of 2026-11-15). Where it sits and what it opens is Claude's to design.
- Listening back on the review page keeps playing while the phone is locked (Noah, night of 2026-11-15).
- Tags are capitalised automatically (Noah, night of 2026-11-15).
- Chosen by Claude within Noah's rulings, open to change (2026-11-15): the drafts badge is a quiet gold pill under the count line on the home screen ("3 to review"), opening the oldest draft; when several recordings are recovered, "Review now" opens the oldest; words that could not be written are tried again quietly at launch and when the review page opens (Noah, night of 2026-11-15), because the screen already promises the recording "stays here until they can be"; no Now Playing information on the lock screen during playback; polish by rule is deliberately cautious (filler sounds, a short function word said twice; never "holy, holy, holy" or anything that could be meant); the legend on the changes screen shows only the sizes of change that occur.
- More of Claude's choices, open to change (2026-11-15, late): "ah" is not a filler (it can be meant); with no change kept the review row reads "Original words"; Spanish "que que" is left alone; the changes sheet shows only the words that changed.
- App lock, location and settings, as briefed by Claude (2026-11-15, late; none of this is Noah's ruling beyond "lock on by default" and "ask for location, else the Salt Lake Temple"): recording never waits for the lock, and "Review now" asks to unlock; the locked screen shows the sky with no lights, dates or count; it locks at launch and after 60 seconds away; the app switcher shows plain sky; location is asked once, at the first recording, approximate only, stored to one decimal of a degree, and reused for later blessings; a settings page behind a "more" icon holds App lock, Language for recording, Where blessings are given, and About.
- The language picked on the Begin screen is remembered, and is the same setting the Settings page shows (Claude, 2026-11-16; the lock task had made it last for one recording only, which would make a Spanish-speaking family on an English phone choose every time). Open to change.
- Spanish, settled by Claude after review (2026-11-16), open to change: midnight to 5:59 reads "de la madrugada" ("2:10 de la noche" is not how Spanish says it); language names stay in their own language ("English", "Español") in both interfaces, as iOS lists them. Still Noah's or a native speaker's to settle: "Ajustes" or "Configuración"; see `docs/spanish-strings.md`.
- Sharing as text and as a PDF, as briefed by Claude (2026-11-16; the product brief asks for both, the details are Claude's and open to change): only a finished blessing can be shared, never a draft; a share icon on the reading page opens the app's sheet with "As text" and "As a PDF" and the line "Once it leaves this phone, it is no longer private to it."; what is shared is what the reading page shows; the PDF is black on white in Newsreader with no logo or app name, and tags are not printed. Sharing as a blessing file and as a link wait for Noah's answers on "Passing it along" and link sharing.
- The reading page's line "Exactly as it was spoken. Nothing has been changed." is reworded so it stays true after corrections; no link to the first transcript (Noah, night of 2026-11-15). Claude's wording: "The words as they were spoken." The first transcript stays saved underneath.
- Audio is kept on the phone until the person has finished reviewing the blessing, then deleted. It never leaves the device.
- Language: follow the phone's language, with an iOS-style pull-down picker to change it.
- Starting: nothing is recorded until Begin is pressed.
- First ten seconds: the bottom ring is Discard. Press and hold to discard, with no confirmation; it returns to Begin. A tap does nothing.
- After ten seconds: the ring is Amen (hold to finish). Discard moves to the top right and asks first.
- While listening: constellations near the look point are drawn slowly, star to star.

**The sky**
- Placement: a ring. Lights are spaced by time along one line round the sky, the timeline in 3D. Lights are not fixed; they may slide as blessings are added. Zooming is the answer to bunching.
  - Details chosen by Claude within that ruling, open to change: the line starts at the point of sky that was overhead at the first blessing; later is to the right; it grows 24 degrees a year (two degrees a month) until the span to now would pass 300 degrees, at about twelve and a half years, then the whole span is fitted into 300 (first built at 45 and 340; slowed so a few blessings are seen together, and the gap widened so the oldest never sit beside the newest); neighbours keep at least half a degree apart; date labels that would overlap are hidden until you zoom in. Built 2026-11-15, with zoom down to a 15 degree view.
- No separate "way back" control after dragging the sky. The ruler and arrows at the bottom are the way back.
- Dates matter most. Faint star names are fine.
- Pinch to zoom.
- Location: ask for it, suggesting "Allow Once". If refused, use the Salt Lake Temple. (With the ring, location only decides which ring of sky is used and where it starts.)

**Data**
- Full create, read, edit and delete, built and tested. Delete is part of this.
- Demo data: Noah will supply real blessings. The five samples appear only behind a test flag.

**Who does what**
- Claude Opus builds the app. Claude (this assistant) organises the work, writes the briefs and checks the designs. Grok and Codex may be used where useful.

### Earlier

- Name: Upon Thy Head. Domain `.app`, not registered yet.
- Design direction: Firmament (a real night sky). Palette: Lamplight.
- Flutter, iOS first, Android later. English and Spanish at launch.
- The product brief's principles stand: never summarise; words stay on the device; exact words always recoverable; simple; reverent; free with no ads.

## Parked ideas (not now, do not lose)

- **Fill constellations.** Each blessing lights the next star of a constellation, in date order; when a constellation is finished, the next begins. Noah's idea, and his favourite after the ring. Pictures: `design/prototype/placement-constellations.png`.
  - Noah has already said yes to: the recording screen draws the constellation in progress, with the line reaching for the next star.
  - Still to decide when it comes back: which constellation comes first and next (Claude suggested the one overhead when its first blessing is given); whether a light ever moves when a blessing is added late or deleted (suggested: never); whether to hint at the unlit rest of a figure or mark a finished one (suggested: neither).
  - Known problems from the pictures: date labels crowd in tight figures; small constellations bunch the lights, so the camera should zoom to fit.
- **Spiral up to the zenith.** Noah's backup to constellations: round the compass by date, higher each year, above a horizon. Pictures: `design/prototype/placement-options.png` (panel 1).
- **Keep audio for a month after review**, on the device, in case the person wants to recover it. Noah's idea for later.
- **Vigil palette**, kept as the alternate to Lamplight.
- **The rosette** (a slowly turning ring of twelve circles) as an alternate recording animation. Still in the web prototype behind `#rec=rose`.
- **Sharper Milky Way when zoomed in.** The app uses a half-size image to save memory; a larger or tiled image would hold detail at full zoom.

## Research: a downloadable speech model (2026-11-15, no code)

Why it matters: Apple's engines write Spanish on the device only once Apple's Spanish dictation asset is installed. A fresh simulator and a Mac without it report Spanish as server-only. A model the app downloads would make Spanish work on any recent phone, whatever Apple has installed. Both options below run OpenAI's Whisper models, which are released with their code under the MIT licence.

| | WhisperKit (Argmax) | whisper.cpp (ggml) |
|---|---|---|
| What it is | Swift package; Whisper converted to Core ML, runs on the Neural Engine | C/C++ library; optional Core ML encoder for the Neural Engine, Metal for the rest |
| Licence | MIT for the open framework; Argmax's "Pro" SDK is under a separate commercial licence | MIT |
| Model sizes | tiny ~40 MB, base ~75 MB, small ~250 MB, large-v3 4-bit ~626 MB, large-v3-turbo 4-bit ~632 MB (*the first three unconfirmed; the 626/632 MB names are in Argmax's model repo*) | ggml files about the same as Whisper's (base ~140 MB, small ~460 MB in full precision, smaller quantised) (*unconfirmed*); the Core ML encoder is an extra download on top |
| Speed, recent iPhone | base: a 15-minute file in 51 s on an iPhone 15 Pro, release build (one write-up). Real-time factors on an iPhone 15 Pro of ~0.1 tiny, ~0.3 small, ~0.7 medium (*aggregator, unconfirmed*) | small.en Q5_1 on an iPhone 15 Pro: real-time factor ~0.4–0.5 (*community guide, unconfirmed*) |
| Speed, older iPhone | No primary figures found | small.en Q5_1 on an iPhone 11: ~0.8, "just keeps up" (*community guide, unconfirmed*) |
| Minimum iOS | iOS 17 in Argmax's own comparison; iOS 16 elsewhere (*conflicting*) | Core ML path iOS 15 or later |
| First run | Core ML models compile for the device on first use, which takes a while (*reported*) | Same for the Core ML encoder |

Spanish accuracy: large-v3-turbo is large-v3 with the decoder cut from 32 to 4 layers (1.55 B to 809 M parameters). Community scores on Common Voice 17 Spanish disagree (6.9 % and 15.4 % word error rate) because they normalise text differently. No official figure was found; *unconfirmed*.

Recommendation (inferred, not measured on a phone): if a model is added, use **WhisperKit with large-v3-turbo 4-bit (~632 MB)** on phones with 6 GB or more, and **small (~250 MB)** on older ones. Download it only when someone chooses Spanish and the phone has no on-device Spanish of its own, over Wi-Fi, with a plain "about 600 MB" before it starts. Whisper writes punctuation and does not restart after pauses, so it would also fix the two faults of Apple's older recogniser found below. Measure on a real older iPhone before deciding: none of the speed figures above were checked.

Sources:
- WhisperKit: https://github.com/argmaxinc/WhisperKit ; models https://huggingface.co/argmaxinc/whisperkit-coreml (626 MB / turbo 632 MB folders); Argmax on Apple's engine https://www.argmaxinc.com/blog/apple-and-argmax ; iPhone 15 Pro base timing https://note.com/shu223/n/ne61389edccf6 ; sizes and real-time factors (aggregator) https://mintlify.wiki/argmaxinc/WhisperKit/resources/faq
- whisper.cpp: https://github.com/ggml-org/whisper.cpp (Core ML, Neural Engine >3× encoder speed-up, first-run compile); Core ML on iOS 15 https://www.mintlify.com/mybigday/whisper.rn/platform-guides/ios ; iPhone figures https://jvoltci.github.io/mosaic/edge-ai/multimodal/whisper-cpp
- Whisper licence and turbo: https://github.com/openai/whisper ; https://superlinked.com/models/openai-whisper-large-v3-turbo.md ; Spanish scores https://huggingface.co/adriszmar/whisper-large-v3-turbo-es and https://huggingface-proxy.pages.dev/surus-ai/whisper-large-v3-turbo-latam

## Open questions for Noah

1. (Answered: Noah's iPhone, from 2026-11-16. Still untested until then: the new engine, Spanish, background recording, a real call, a real voice.)
2. (Answered: older recogniser first, model as an optional upgrade with consent.) Still open: should the model upgrade also be offered on phones that have Apple's new engine?
3. App lock is on by default. Should starting a recording skip Face ID, like the camera from the lock screen, with only reading locked?
4. (Answered 2026-11-16: yes, anyone holding the link can read the blessing.) Link sharing: anyone holding the link can read the blessing, and it passes through whatever app carries it. Is that acceptable, and may the brief's "stays between the two devices" be reworded?
5. A giver's home screen: only "For me" blessings appear in the sky, so someone who only gives blessings has an empty one. What should they see?
6. Words for the last line of the reading page, now that the light's place is the ring. Placeholder: "Its light keeps its place in time on the ring of sky overhead."
7. Listening back during review: Claude took "keep the audio until review is finished" to mean the person can play it, and the review page has a listen bar. Or was it meant only as a safety copy?
8. "For me / Passing it along" is not on the review page yet, because a blessing marked "Passing it along" would appear nowhere: the sky and list show only "For me". It is planned to arrive with the list of everything recorded, which still needs a design.
9. The prototype's "heavy change" example rewords a sentence for style, which the brief forbids. Polish will be built to the brief (fillers, repeats, grammar). Still show three levels of change, or two?
10. (Answered by 2: the older recogniser's missing "um" and punctuation are accepted, with the model as the upgrade.)
11. (Answered: keep recording while locked.)
12. (Answered: build recovery now.)
13. (Answered: iOS 17.)

14. (Answered: a badge on the home screen when there are drafts.)
15. (Answered: reword the line only; no link to the first transcript.)
16. (Answered: let it play while the phone is locked.)
17. (Answered: capitalise tags automatically.)

18. Still open: a recording killed in its first two seconds or so leaves no audio, so nothing is kept and nothing is said. Is silence right there, or should the app say "a recording was started but nothing was kept"?
19. (Answered: "Review now" opens the oldest.)
20. (Answered: words that could not be written are tried again quietly at launch and when the review page opens.)

New from the polish build (2026-11-15), most important first:

21. Polish finds only filler sounds and a short word said twice. The prototype's sheet shows three sizes of change (light, medium, heavy); rules alone only ever make light changes, so the legend shows one size. Keep three sizes for a future source (a model on the phone), or settle on two? (Also question 9.)
22. (Settled by Claude, see Decisions; open to change.) When some or all changes are restored, the review row reads "Polished for reading · 1 of 2 kept", and with none kept "0 of 2 kept" (the reading page then shows the words as spoken). Is "0 of 2 kept" right, or should the row say something like "Original words in use"?
23. (Settled by Claude, see Decisions; open to change.) Fillers include "ah" as well as "um", "uh", "er", "erm", "hmm" (Spanish: "eh", "em", "este" between commas, and similar). "Ah" can be meant ("Ah, my daughter"). Leave it in the list, or drop it?
24. (Settled by Claude, see Decisions; open to change.) Spanish "que que" is never treated as a stumble, because "que que" can be grammatical. Agreed?
25. (Settled by Claude, see Decisions; open to change.) The changes sheet shows the original trimmed to the words that changed ("um") rather than the prototype's raw stretch (", um, right now,"). The underline still marks the same place. Fine?
26. How big a change is (light, medium, heavy) is measured by how many words it touches and whether meaning words change. Rules only produce light. The thresholds are Claude's: worth a look when a second source arrives.

New from the lock, location and settings build (2026-11-16), most important first:

27. A phone with no passcode cannot be locked at all (Face ID needs one). The app then opens unlocked and Settings says "Set a passcode on this iPhone to lock your blessings." Nothing else is shown at launch. Should the app say anything more than that, once?
28. Allow Once: iOS forgets it when the app is closed, so the place is found once and then kept (rounded). Later recordings reuse the kept place and never ask again. If the person moves house, Settings' "Use my location" is the only way to update it. Fine?
29. (Settled by Claude: the choice on Begin is remembered again; see Decisions.) The Begin pull-down now changes only that one recording; the default lives in Settings ("Language for recording"). Before this build, a choice on Begin was remembered for next time. Agreed?
30. (Done in the Spanish task, 2026-11-16: the launch screen is the sky's dark ground colour.) The launch screen (the white flash before the sky) is still Flutter's plain white. It is not part of this brief, but it shows on every launch, now also before the lock. Make it the ground colour?
31. The lock does not cover a notification, because the app sends none. If reminders ever arrive, they must say nothing about a blessing.
32. Found in passing, not part of this build: on iOS 26 the speech-recognition question shows Apple's own words, "Speech data from this app will be sent to Apple to process your requests…", not the app's line ("…Nothing is sent anywhere."). The app asks for on-device recognition, so nothing is sent, but the system question says otherwise, right after Settings' "Nothing is sent anywhere." Worth checking on Noah's iPhone; there may be nothing the app can change.

New from the Spanish build (2026-11-16), most important first:

33. "Ajustes" or "Configuración"? The brief says Settings = "Ajustes", and the app's page is called that. Latin American iOS calls the iPhone's own Settings app "Configuración" ("Ajustes" is Spain's), so the button that sends the person there says "Abrir Configuración". One app now uses both words. Use "Configuración" for the app's page too?
34. Spanish wordings Claude is least sure of are starred in docs/spanish-strings.md for the native speaker: "Pulir" for polish, "Muletilla" for filler, "Mantén presionado para descartar" (long), the reading page's last line, the hint "Para grabar nunca hace falta", "de la noche" from 7 pm (no "evening"; should small hours be "de la madrugada"?), "sept" for September.
35. A blessing nobody has named carries the title "Blessing" (or "Bendición") in the store. It is now shown in the phone's language whichever language it was made in. A typed title is never changed. Fine?

New from the phone-readiness build (2026-11-16), most important first:

36. Speech permission and the new engine. Apple says the speech-recognition question "only applies to speech recognition using SFSpeechRecognizer", and that "SpeechAnalyzer transcriber modules don't send audio data of the user's voice to Apple's servers". On a phone with the new engine, the app could skip that question entirely. That would also remove open question 32's misleading system wording. The phone check (check 4) proves whether it works on the phone. If it does, should the app stop asking for speech recognition where the new engine runs, and ask only where it falls back to the older recogniser?
37. Only the iPhone 12 is in the signing profile. A different phone needs Xcode's sign-in to work (it is broken on this Mac today; see docs/phone-session.md step 1). The phone on iOS 27.3 may need a newer Xcode than 26.2.
38. The iPad keeps all four orientations, because Apple requires them for an iPad app that is not full-screen only. The iPhone is now portrait only. Is the app meant for iPad at all? If not, set it to iPhone only.
39. (Answered 2026-11-16: M5, installed; see Decisions.) (In hand 2026-11-16: Codex is making concepts as images, black and white first, colour later; see Decisions.) The app icon is still Flutter's default (the blue "F"), so that is what the home screen shows today. It needs a design. Until then, should it at least be the sky's ground colour with a single light?

New from the sharing build (2026-11-16), most important first:

40. The PDF is made with a thin rule about an inch and a third long under the heading, not across the page, and the footer (from page 2) is a mid-grey rather than black, so it recedes when printed. Both are Claude's; say if either should change.
41. Shared text and PDFs carry the long date with its weekday ("Tuesday, March 3, 2026"), as the reading page does; the file name has no weekday ("Comfort before surgery, March 3, 2026.pdf"). Fine?
42. Spanish "Una vez que sale de este teléfono, ya no es privada." drops the English "to it". Starred for the native speaker in docs/spanish-strings.md.
43. Tags and the line about the light in the sky are left out of both the text and the PDF, as briefed. A recipient appears as "For Emma" in the heading, not at the foot as on the reading page.

New from the blessing-file build (2026-11-16), most important first:

44. (Answered 2026-11-16: yes; the serif now falls back to Apple Color Emoji, built in the first-run task.) An emoji in a blessing's words shows as an empty box on the reading page (the Newsreader serif has no emoji, and the app's serif style names no fallback). The words themselves are kept exactly; only the drawing is wrong (`design/sim/file/19-es-already-have-same.png`, the 🙏 after "camino"). This was not caused by the file; it is true of any blessing whose words hold an emoji, and dictation does write them. Should the serif style fall back to Apple's emoji font? The change touches every serif text in the app, so it was not made unasked.
45. The link: see the verdict in docs/blessing-file.md. It never fits an App Clip Code, a QR code only to about 800–1,000 words, and Mail risks breaking it past about 150 words. Which way? (a) a short link to a server that holds only ciphertext, the key after the `#`; (b) a link only for short blessings, the file otherwise; (c) no link, the file and the PDF only.
46. (Answered 2026-11-16: the file carries the place, built; see docs/blessing-file.md.) A received blessing takes the receiver's place (or the Salt Lake Temple when the place is unknown), because the file carries no place, as briefed. Its light sits on the ring by its time, exactly where it was. The place matters only if it becomes the earliest blessing on the ring, whose place sets where the ring starts and its height. Fine?
47. (Answered 2026-11-16: keep it; Replace mine now keeps the recording kept with the person's own copy.) Replace mine erases any recording kept with the old copy, since the words it was reviewed against are gone. Should it keep the recording instead?
48. A received blessing is always the person's own ("For me"). If the same blessing is already on this phone as one they passed on, "You already have this blessing." is said, but its page does not open (the sky shows one side at a time). Should a received one ever be filed as passed on?
49. (Fixed by Claude 2026-11-16: a tap on the dimmed sky now does nothing on the receiving sheet; a shared blessing is declined only by its button.) A tap in the half second while the sheet rises lands on the dimmed sky, which counts as Not now. Should the sky ignore taps until the sheet is up?
50. The system share sheet offers Upon Thy Head itself as a place to send the file; choosing it only says "You already have this blessing." Leave it, or hide the app from its own sheet?
51. (Answered 2026-11-16: the chosen icon is installed.) In Files the file shows the app's icon, which is still Flutter's default (question 39).
New from the first-run build (2026-11-16):

52. The first run's Face ID row: the simulator never shows iOS's "Do you want to allow … to use Face ID?" question and goes straight to the scan, so the row's asking-then-answered sequence has only been seen with the scan. On a phone the consent question comes first and the scan after it. One look on a phone before release?
53. The opening's sky is the real sky overhead at the place and time, so the Milky Way is there only when it is overhead (the mock showed it always). Keep the real sky, or always turn the camera to the Milky Way for the opening?
54. The practice listens in the language the recording screen would use (the one set in Settings, else the phone's). A Spanish speaker on an English phone practises in English until they change it. Offer the language pull-down on the practice too?
55. After a first launch from a blessing file, the rest of the first run starts at the permissions screen at the next launch, with no opening or welcome, since the person has already seen the sky. Or should they get the welcome too?
56. Touch ID phones get no question (iOS asks none), so the row shows as on, named Touch ID. A phone with no Face ID or Touch ID set up shows the passcode line and is not asked. Both are drawn from the brief's cases but untested on hardware (the simulator is Face ID). Fine?
57. The row icons: a microphone, lines of writing with a pencil (for speech turned into text), the location arrow, and the Face ID corners with a face (Touch ID and passcode rows use the lock). Writing, or a waveform, for speech?
58. "Permitido" on the Spanish rows agrees with "permiso", not with each row's noun (micrófono, reconocimiento de voz, ubicación, Face ID). Keep the one word, or agree per row ("Permitida" for ubicación)?
59. (Fixed by Claude 2026-11-16.) A location question was seen over the opening in one acceptance run (c1-01, 13:20). Nothing in the app asks for location before Continue on the permissions screen: the only other ask is the recording screen's, after its microphone and speech questions, which the first run never reaches. Reproduced: a location question left up when an earlier run killed the app stays on the simulator's screen through an uninstall and a reinstall, and shows over the next install's black opening. The acceptance run now clears such a leftover before each install and fails if any system question is on screen at any moment during the opening or the welcome. Nothing to decide; noted so it is not chased again.
60. (Fixed by Claude 2026-11-16.) A sheet that is off is slid below the screen but still built, and VoiceOver could reach it: on the sky with no sheet up, "A recording was kept" and "Later" were readable, and on the recording screen "Discard" and "Keep listening". Every sheet (lib/widgets/sheet.dart) is now out of VoiceOver's reach while off (test/sheet_test.dart). Worth a VoiceOver pass on a phone across the app.
61. **The app crashes at launch on the iOS 17.4 simulator** (iPad Pro 11-inch (M4), the only iOS 17 simulator here), in every build, the seeded one too, so it is not the first run: Impeller segfaults drawing the sky's shader (`RuntimeEffectContents` → `PipelineDescriptor::GetHash`, a pipeline that was never made). On iOS 26.3 (the iPhone 17 Pro and an iPad Air 11-inch (M3)) it runs. The app's minimum is iOS 17. Is an iOS 17 device on hand to check whether a real phone does the same, or should the minimum go up to 18 (or Impeller be looked at for the sky shader on iOS 17)?

## Things found that the brief did not know

- **Polish (built 2026-11-15, tier 1: rules only, English and Spanish).**
  - Changes are stored one row each (schema version 6, table `blessing_changes`): position in the spoken words, was, now, kind, size, kept, and which source made them. The sample's five edits were moved into it on upgrade, tested. Version 5 capitalised existing tags.
  - Sources are pluggable (`ChangeSource` in lib/polish/rules.dart). The rules are the first; a model on the phone would be another, stored and shown the same way.
  - The person's own corrections after polish: a change whose words were not touched survives, keeping kept or restored; a change whose words were edited is dropped; the rules run again on save and new finds are added as kept.
  - The reading page shows the polished words when any change is kept, and the original otherwise. The original is always kept beside them.
  - The changes screen follows the prototype (05-review-changes.png): the same underlines, caret for a cut, sheet, step buttons, Restore all, motion. With Reduce Motion it changes instantly. With VoiceOver each change is a button that says its size, kind, both versions and whether it is in use (tested in a widget test, not yet with VoiceOver on a phone).
  - Real speech on the simulator wrote "with with" itself and missed some punctuation, so rules had real things to find. The older recogniser drops "um", so the test puts one back by hand to have a filler.
  - The phone in the simulator is 402 points wide and the prototype 390, so lines wrap at different words; that is the main difference in the side-by-side (design/sim/polish/17-side-by-side.png).
  - Not provable on the simulator: playback with the screen actually locked (the Settings app stood in for the background), that no Now Playing card appears, a real phone call stopping it.

- Apple's new speech engine does not run in the simulator and reports itself unavailable on some phones that run the newest iOS (one report: iPhone 11 Pro). Apple publishes no device list.
- It is not confirmed that an App Clip receives the part of a link after the `#`, where the brief puts the encrypted blessing. Needs a test on a device.
- Flutter cannot run release builds on the simulator, so speed has only been measured on a Mac. A real iPhone is the test.
- **Which engine runs where (measured 2026-11-15).**
  - iOS 26.3 simulator: the new engine (SpeechTranscriber) reports itself unavailable everywhere. The older recogniser writes en-US on the device.
  - On a fresh simulator, es-US, es-MX and es-ES are "server only", so the app keeps Spanish blessings as audio and says the words could not be written yet.
  - A simulator set to Spanish (es-US region and keyboard, Spanish dictation turned on) got on-device es-US after a reboot. The prepared Spanish file then came back with 5 of 48 words wrong, in 1.3 s for 24 s of audio.
  - So Spanish works on the device once Apple's Spanish dictation asset is there. A phone gets that asset when Spanish dictation is turned on (*inferred from the simulator*).
  - A macOS 15.7 Mac without that asset is English-only.
- **Real microphone, simulator, Mac speakers into the Mac microphone (measured, two runs):**
  - 63 and 67 of 106 words wrong.
  - Whole stretches were lost, and two stretches were written twice; the repeat is now fixed.
  - The same audio as a file gives 8 of 106 wrong, so most of the loss is the speaker-to-microphone path in a room (*inferred*).
  - A real voice into a phone has not been tried.
- **Locale order for Spanish:** es-US, then es-MX, then es-ES, chosen by what the device supports on-device. On a fresh simulator none qualified; on the Spanish one, es-US was chosen.
- **The older recogniser restarts after each pause of a few seconds** and never sends the words before it as final. The app keeps each stretch and starts a new paragraph there.
  - Punctuation is mostly lost in restarted stretches.
  - Fillers such as "um" are dropped.
  - That is not "exact words". The audio is kept until review for this reason.
- **Downloads from Apple:** where the new engine is present, the app asks the system to download the language model when the recording screen opens. Apple serves the model; no audio leaves the phone.
- **Apple has a second new-engine module, DictationTranscriber**, closer to the older recogniser's behaviour. It is not used. It is a possible fallback if SpeechTranscriber is missing on a phone where dictation works.
- **Recording keeps going when the screen locks or the app goes to the background.** The app declares background audio for this. Apple's review may ask why: the answer is "recording a blessing in progress".
- **Recordings are excluded from iCloud and iTunes backups**, in Application Support/audio, so they stay on this phone only. A blessing restored from a backup will have its words but not its audio.
- **Interruptions:** a phone call or Siri closes the current part of the recording. The screen says "Paused" and the clock stops. Recording resumes in a new part when the microphone comes back or the app returns, and the parts are joined at Amen.
- **Recovery after the app is killed (built 2026-11-15).**
  - Measured before: a recording part being written as .m4a when the app is killed cannot be opened at all (86 KB on disk after 23 s, "moov atom not found"). The audio was there but unreadable.
  - Now each part is written as ADTS AAC (`<id>.partN.aac`), which has no index at the end, so a cut-off part reads up to its last whole frame. Parts are joined into `<id>.m4a` at Amen or at the next launch, by copying the frames, not encoding again.
  - The recorder writes to disk every 64 AAC frames, so the sample rate sets what a kill can lose: 4.2 s at 16 kHz, 2.4 s at 32 kHz. Recording is now 32 kHz at the same 24 kbit/s, so the same file size (about 11 MB an hour) and at most about 2.5 s lost. At 16 kHz a 4-second recording would have left an empty file.
  - At Begin a small note (`<id>.recording.json`) is written beside the audio: id, time and clock offset, place, language. The parts are found on disk by name, not listed in the note, so nothing is rewritten while recording.
  - At launch, before the sky: each note becomes a draft at its true time, the words are written as after Amen, and a sheet says "A recording was kept" once. Then every file in the audio folder that belongs to no blessing is removed.
  - A recording killed before anything reached disk (the first ~2.5 s) leaves nothing: there is no audio to keep.
  - The store now records whether the words were written (schema version 4: pending, written, could not be written on this phone, failed). A draft saved at Amen whose words were not yet written gets them at the next launch. The review page can now tell "no words were heard" from "could not be written".
  - Not provable on the simulator: the battery dying, iOS ending the app in the background, a real phone call. Data the app had written survives a process kill; whether it survives sudden power loss is up to iOS. To try on Noah's iPhone.
- **Review page (built 2026-11-15).**
  - The corrected words replace the transcript. The words as the phone first wrote them are kept in a separate field, `first_text`, which the store never overwrites once set (schema version 3; existing databases copy their words into it on upgrade, tested).
  - A blessing recorded before this version has its old words as its "first" words, because there was no earlier copy.
  - Playback uses Apple's spoken-audio session and does not mix with other audio, so a phone call always wins: a call pauses it, and it does not resume by itself.
  - Typing is saved 0.4 s after the last key, and at once when the page closes or the app leaves the screen. The acceptance run found and fixed a bug here where the delayed save never happened.
  - If the review page is opened before the words are written, it shows "Writing the words…" in place of the box; the title, names and tags can be filled in meanwhile, and the words drop into the box when they arrive without disturbing them.
  - The "could not be written" notice cannot tell an older draft that heard nothing from one whose engine failed; both show the empty box with the listen bar.
  - The five sample blessings now carry tags, so tag suggestions have something to show behind the test flag.
  - The language pull-down on Begin now hangs below its control.
- **App lock, location and Settings (built 2026-11-16).**
  - The lock uses Apple's "device owner" check: Face ID, Touch ID or Optic ID, with the passcode as the fallback, all drawn by iOS. The app has no lockout of its own. Settings names the method the phone has ("Asks for Face ID when you open the app…", or "your passcode" when no face or finger is enrolled).
  - Locked, the sky engine is given no blessings at all, and the caption, list, count, badge, reading page and recovered-recording sheet are not built. Only stars, the Milky Way, "For me · Locked", Unlock and New blessing are drawn.
  - The app switcher picture is a native cover (a still of the plain sky, `assets/sky/cover.jpg`, made by `tool/cover_shot.sh` from the app's own sky) put over the app the moment it stops being active. It is lifted only after Flutter has hidden what must be hidden, so the picture iOS takes never shows a blessing. It is not put up for the app's own system questions (Face ID, permissions), so those do not flash the cover.
  - Time away is measured natively, from leaving to coming back. More than 60 s locks, except while recording or while the review page plays.
  - Location is asked for "approximate" only (`NSLocationDefaultAccuracyReduced`), after the microphone and speech questions, and only once ever. The place is rounded to a tenth of a degree (about 11 km) before it is kept. A blessing keeps the place it was given with, and the ring takes its latitude and start from the first blessing, so a place found later never moves a light.
  - The integration tests start as if just unlocked (`AppLock(startUnlocked: true)` in `integration_test/support.dart`); the lock itself stays on. Real users get the default.
  - `tool/alerts/` is a tiny UI test that answers the system's own questions (permissions, "Face Not Recognized", Home, the app switcher) for `tool/lock_acceptance.sh`. Simulator only; Xcode is the only thing it needs.
  - A simulator always has a passcode in iOS's eyes: with Face ID removed it still answers "passcode", and it cannot be removed. So the no-passcode case was run with only that answer replaced; the launch and the Settings page were real.
  - Acceptance run 2026-11-16 (`tool/lock_acceptance.sh`): all nine cases passed. Mexico City was kept as 19.4, -99.1 and the ring sits at 19.4°; refused location kept 40.7704, -111.8919 and said nothing; 70 s away locked, 20 s did not, 70 s away during a recording did not (still recording at 73 s); the switcher cover was up natively while in the switcher and lifted on return.
  - Not provable on a simulator: a real face, Touch ID and the passcode fallback; a phone with no passcode; Allow Once across real launches; how far the approximate location wanders; when iOS takes its switcher picture on a phone.

- **Spanish (built 2026-11-16).**
  - The app's words follow the phone's first language: any Spanish gives Spanish, anything else English. There is no switch in the app. The language a blessing is recorded in is still its own setting.
  - `lib/strings.dart` has an English class and a Spanish one that must implement every member, so a missing Spanish string does not compile. A unit test also checks that every fixed string has Spanish that differs from the English.
  - iOS words the system's permission questions by the phone's own language, not the app's. A per-app language (iOS Settings > the app > Language, or `-AppleLanguages "(es)"`) gives a Spanish app with English permission questions. On a phone set to Spanish they are Spanish (`app/ios/Runner/es.lproj/InfoPlist.strings`, checked on a temporary Spanish simulator by `tool/spanish_prompts.sh`). The Face ID / passcode reason comes from the app, so it follows the app.
  - The launch screen is now the sky's ground colour (#0B0907) with nothing on it, and so is the view behind Flutter's first frame. A recorded cold launch is dark from the first frame of the opening zoom until the sky (`design/sim/spanish/launch.mp4`, frames in `launch-first-frames.png`).
  - At the first accessibility text size the longer Spanish broke six places, and some of them broke in English too: the recording header (title over Descartar), pill buttons (two-line labels clipped), the changes sheet's "Original" label (split mid-word), "Comenzar" in the Begin circle, the list's count line (ran into the timeline) and its dates ("3 / mar"). Each now keeps to one line: a pill label, the Begin word, a list date and the count line shrink to fit when they would not fit (`FittedBox` scale-down, so nothing changes at normal size), the pair labels widen, and the recording header stops growing past 1.2× as iOS's own navigation bars do. Longer text elsewhere wraps cleanly.

- **Ready for a real phone (built 2026-11-16).**
  - `flutter build ios --release` and `--profile` both build, with and without `--no-codesign`, and sign with the team's development profile. Sizes: release 22.5 MB (Dart code 4.8 MB), profile 30.5 MB, profile with the phone check 30.9 MB.
  - Fixed for device builds:
    - A privacy manifest (`ios/Runner/PrivacyInfo.xcprivacy`): no tracking, nothing collected, file timestamps (C617.1) and disk space (85F4.1).
    - The display name is set ("Upon Thy Head").
    - The iPhone is portrait only.
    - The twelve Swift warnings from APIs deprecated since iOS 17 are fixed: microphone permission is now through AVAudioApplication, and asset loading uses `load(...)`.
  - Checked, nothing to change: no shaders of the app's own (Impeller draws everything); no `kDebugMode` paths that matter on a phone; background audio and the purpose strings in Info.plist. The test audio and the sample blessings are behind build flags.
  - Profile builds ask "find devices on your local network" because of Flutter's tooling. Release builds do not.
  - **Phone check** (`--dart-define=PHONE_CHECK=true` only): the last row of Settings. Ten checks run one by one, each on its own time limit: the phone, the speech engines, the prepared recordings through each engine, permissions, the microphone, a cut-off recording, the sky's speed, the lock, location and storage. The report is copied as text, printed to the app's log between `===== UPON THY HEAD PHONE CHECK BEGIN =====` and `... END =====`, and saved as Documents/phone-check.txt. A normal build has no page, no audio and none of its strings (checked in the built app). The native half (`ios/Runner/PhoneCheck.swift`) answers only when the bundle holds the `phone_check` folder, which only a check build has.
  - **Speech permission and the new engine (Apple):** "This process only applies to speech recognition using SFSpeechRecognizer. … SpeechAnalyzer transcriber modules don't send audio data of the user's voice to Apple's servers." Source: Asking permission to use speech recognition, https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition . WWDC25 session 277 (https://developer.apple.com/videos/play/wwdc2025/277/) mentions only the microphone for SpeechAnalyzer. Check 4 runs the new engine with speech permission not asked or refused, and reports whether it wrote words and whether any question appeared. The simulator has no new engine, so this is unproven until the phone.
  - **`tool/phone.sh`:** builds, installs and opens the app on a plugged-in iPhone with Xcode's own `devicectl`. With no phone, it says what to do. With several, it lists them. It explains the usual first-run failures in one line each. If the phone is not in the signing profile, it tries to register it through Xcode. Steps for the session: docs/phone-session.md.
  - Simulator run of the phone check, 2026-11-16 (debug, iPhone 17 Pro, iOS 26.3.1): every check answered.
    - Speech: no new engine. English through the older recogniser had 8 of 106 words wrong, 2.1 s for 37.9 s of audio. Spanish could not be written.
    - Microphone: AAC, 32 kHz, peak −36 dB, played back.
    - Cut-off recording: 9.6 of 10.3 s readable.
    - Sky: 0 slow frames at 60 Hz with 5 and with 120 blessings.
    - Lock: Face ID. Location: rounded 4.1 km. Storage: the audio folder is excluded from backups, schema 6.
  - Not provable without a phone: install and launch through devicectl, `--log`, registering a new phone, the new engine and its download, the new engine without speech permission, a 120 Hz screen, and real speed.

- **Sharing as text and as a PDF (built 2026-11-16).**
  - A share icon (iOS's square with an arrow, drawn in the app's own 1.5 stroke) sits left of "Edit" on a finished blessing's reading page; a draft has none. It opens the app's own sheet ("Share this blessing", "As text", "As a PDF", and the line that it is no longer private once it leaves). Each row opens the system share sheet with that one item and nothing else. Code: `lib/share/share.dart`, `ios/Runner/Share.swift`.
  - The text is the title, the long date, "A blessing from …" and "For …" when known, a blank line, then the words in paragraphs. The words are the reading page's (polished when any change is kept). Labels and date follow the phone's language; the title, names and words never change. The share sheet's subject and header are the title (through LinkPresentation, a system framework).
  - The PDF is drawn natively with Core Text from the Newsreader fonts in the Flutter assets, at the app's settings (weight 400, optical size following the size). Quartz embeds each optical size as its own TrueType subset ("Newsreader16pt-Regular_wght_opsz…"), with MacRoman encoding, so its text is real, selectable and searchable without a ToUnicode table; Spanish accents are in MacRoman. A character outside MacRoman (a ligature, an emoji) would make Quartz use a different font type; not tested.
  - Paper: US Letter for the regions CLDR lists as Letter (US, Canada, Mexico, Chile, Colombia, Costa Rica, Guatemala, Panama, Philippines, Puerto Rico, El Salvador, Venezuela, Nicaragua, Belize), A4 everywhere else. iOS has no paper-size setting of its own to read.
  - Pages: a one-inch margin, the words at 12.5 pt on 20.5 pt lines, half a line between paragraphs. Lines are laid out one by one, so a paragraph's first line is never left alone at the foot of a page and its last never alone at the head (a two-line paragraph moves whole). Footer from page 2: the title (cut with "…" if long) and "2 of 3".
  - The file lives in the app's tmp/share/ only while the sheet is up. It is removed when the sheet closes, when the app locks with the sheet up (the sheet is dismissed first), and at the next launch after the app was killed. The document's information holds only the title; iOS adds its own "Producer" (the iOS version and "Quartz PDFContext"). No app name.
  - The app switcher: the existing cover goes over the system share sheet too (checked natively and in a screenshot, `design/sim/share/05-en-switcher-with-sheet.png`).
  - iOS 26's share sheet has no Close button: it closes with a tap outside it or a swipe down. "Copy" with text puts exactly the text on the pasteboard.
  - Acceptance: `tool/share_acceptance.sh` (integration_test/share_test.dart) with `tool/pdf_check.swift`, which checks a PDF on the Mac with PDFKit and Core Graphics (nothing to install): name, title, paper, page count, fonts and their embedding, the words in order, margins, footers, stranded lines; it renders each page at 144 dpi.
  - Acceptance run 2026-11-16 (run 6 of `tool/share_acceptance.sh`, iPhone 17 Pro (clean), iOS 26.3.1): every case passed. The icon is on "Comfort before surgery" and not on a draft. Copy puts exactly the expected text on the pasteboard: 531 characters in English and 537 in Spanish. Sample, long, minimal and long-title PDFs all pass `pdf_check` (Letter). The long blessing (2,491 words) runs to 6 pages, with footers "2 of 6" to "6 of 6" and no stranded lines. The long title with "/" and ":" gives the file name "Before the move for the children their school, their friends, and the long road between the old…, May 18, 2025.pdf". The Spanish sample passes, as "Comfort before surgery, 3 de marzo de 2026.pdf". With the region set to en_GB the pages are A4, 595 × 842 pt. tmp/share is removed after every close. After a kill -9 with a file prepared, the file was still there, and the relaunch removed it. Away 70 s with the sheet up: locked, the sheet gone, the file removed; Face ID unlocked afterwards.
  - Found while testing: the clean simulator had no Face ID enrolled, so unlocking fell back to the passcode. The share run now enrols a face (`notifyutil … BiometricKit.enrollmentChanged`) before it starts. On the Spanish simulator, some of the system share sheet's own labels stay in English ("Preview", "More", "Save to Files"). That is the simulator's localisation, not the app's.

- **The first run (built 2026-11-16).** The opening, the welcome, one permissions screen, the rehearsal and "Read first" for a fresh install opened by a blessing file, in English and Spanish, iPhone and iPad.
  - Code: `lib/onboarding/first_run.dart` (where a launch begins, the permission rows, the questions in order), `lib/onboarding/first_run_screens.dart` (the layers), the `Onboard` steps in `lib/home/home_screen.dart`, the four icons in `lib/widgets/icons.dart`. Tests: `test/first_run_test.dart`. Acceptance: `tool/first_run_acceptance.sh` (iOS's real questions answered by `tool/alerts`; the app's own buttons pressed by their VoiceOver labels).
  - Where a launch is, kept in the settings file as `firstRun`: none (fresh), `permissions`, `rehearsal`, `rest` (after a shared first launch: the permissions and rehearsal at the next launch), `done`, `existing` (an install that had blessings before it existed, and the seeded build). A kill on the permissions screen comes back to it with no opening; a kill in the practice comes back to "Try a few words first?" with the practice's audio removed.
  - Nothing is locked while the first run is shown on an empty store (there is nothing to lock). A shared first launch that keeps a blessing turns the lock on; the rest then waits until it is unlocked.
  - The recording screen asks iOS's questions only on an install that has not been through the first run (`recordScreenMayAsk`); after it, its refused lines and Open Settings are the only way back.
  - The practice is a `RecordSession(practice: true)`: Amen from the start, no recording note (so nothing can ever be rebuilt from it), audio in `tmp/practice`, emptied after every practice and at every launch. No light is put in the sky.
  - The opening's ring is drawn at the place's latitude, sweeping left to right; the sky is the real sky overhead now, so the Milky Way is there only when it is overhead (the mock showed it always).
  - The permissions screen: each row has its icon at the left (microphone; lines of writing with a pencil for speech recognition; the location arrow; the Face ID corners and face; the lock for Touch ID, Optic ID or a passcode-only phone). 22 points, the 1.5 stroke, the second ink at rest and the gold while its question is up; the icon keeps its size at every text size and stays centred on the title's first line. The icons are not read by VoiceOver; the row's label says the name and its state.
  - After the last answer the screen stays about two seconds, so the last mark is seen after Face ID's own scan has gone, then moves on by itself.
  - Found while testing: the simulator never shows iOS's "Do you want to allow … to use Face ID?" question; Face ID goes straight to its scan, and nothing in TCC records a consent. On a phone the question comes first (question 52). An "Allow Once" location reads as unanswered at the next launch, so the app remembers it asked (`locationAsked`) and does not ask twice. A per-app language written with `simctl spawn … defaults write <bundle> AppleLanguages` outlives an uninstall; a Spanish phase that ends while the simulator is shut down leaves it behind (the file run did, and the record test then ran in Spanish). The alert tapper's queries on the app hang for good once the app has been terminated and launched again by simctl, so the first-run script starts a fresh tapper before every launch. The record integration test needs the permissions granted first (`tool/sim_permissions.sh grant`).

- **A blessing as a `.blessing` file (built 2026-11-16); a blessing in a link (written and measured, no screen).**
  - The format, the reading rules, how a file arrives, the link's design, its lengths, what a link meets (with sources) and the verdict are in docs/blessing-file.md.
  - Type `dev.summitstudio.uponThyHead.blessing`, exported and owned; conforms to data and content, not JSON or text. iOS reports the identifier in lower case ("dev.summitstudio.uponthyhead.blessing"); identifiers compare without case.
  - It arrives through the scene's URL contexts, at a cold launch and while running. A tap in Files and `simctl openurl file://…` both log "receive: launched/opened with 1 file(s)" and take the same path. Files' own copy stays in Files; the copy iOS puts in Documents/Inbox is deleted once read; nothing is left in the app's folders (checked after every case).
  - File names on disk come back decomposed (an accent as its own character), so "Para Lucía…" is not byte-equal to the name the app gave. Nothing reads the name, so it does not matter.
  - The sheet held back while locked is also hidden from VoiceOver, and Reduce Motion now makes every sheet in the app appear and go without sliding (lib/widgets/sheet.dart).
  - Acceptance: `tool/file_acceptance.sh` (integration_test/file_test.dart). The test is built into the app and runs at each launch, because iOS must launch the app for a file, which `flutter drive` cannot do; it talks to the script through files in the app's container. The alert tapper got `files <name>` (open a file from Files' On My iPhone).
  - Acceptance run 2026-11-16 (run 10 of `tool/file_acceptance.sh`, iPhone 17 Pro (clean), iOS 26.3.1): every case passed. The share sheet was handed one file, "Comfort before surgery, March 3, 2026.blessing", 1,542 bytes, not JSON, not text. Tapped in Files with the app closed: the lock first, nothing shown before Face ID; the sheet; Keep; title, date, giver, recipient, tags, words and all five changes identical, the light at exactly the same place (difference 0). The same file: "You already have this blessing.", still one. An edited copy: Keep mine left it, Replace mine took the edit. The changes screen works on the received one, and restoring a change brought back ", um, right now,". From the background: the 2,491-word blessing with accents, emoji and 19 paragraphs, exact. Locked after 70 s away: Face ID first. Newer, rubbish, 600 KB and no title: the right lines, nothing saved. Not now: nothing saved, nothing left. At the first accessibility size nothing is clipped. A file opened during a recording waited through the recording and the page after Amen, and came after Save for later. Spanish, launched by a file: the whole of it again. Screenshots in `design/sim/file/`, the film of step 2 in `design/sim/file/step2-files-tap.mov`.
  - Found while testing: a tap on Keep before the sheet has finished rising lands on the dimmed sky and counts as Not now (question 49); holding the ring in a recording's first ten seconds is Discard, not Amen (as designed, but a test must wait).
