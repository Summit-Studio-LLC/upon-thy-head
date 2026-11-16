# First run: draft for Noah

Noah asked for: "1. An opening screen 2. A welcome 3. Permissions 4. Getting them in."

- `index.html`: the mock at iPhone size. Click through inside the phone, or use the rail on the left to jump to a step, switch 4a and 4b, play the shared-blessing version, switch to Spanish, turn on larger text, or turn on Reduce Motion. In a system question, "Don't Allow" shows what a refusal looks like.
- `shots/`: 3x screenshots. `01`–`24` are English, in order. `es-` are the Spanish versions. `big-` are at larger text.
- `flow.png`: every English screen in one row.
- `src/`: the sources. `node src/build.mjs` builds `index.html` and `node src/shoot.mjs` takes the screenshots. The sky, fonts and star data are read from `design/prototype/src` and are not changed there.

## The flow

| | Step | What happens |
|---|---|---|
| 1 | Opening | Black. The sky rises, as if you were looking up. The ring crosses it from left to right, the way time runs along it. One warm light arrives overhead, then the name. It moves on at about 3.8 seconds, or at a tap. |
| 2 | Welcome | Three lines arrive one after another, then a quiet fourth line, then Continue. The light from the opening stays, dimmer. |
| 3 | Permissions | Microphone, speech recognition, location, Face ID. One screen each, then iOS's own question. |
| 4a | Straight in | The sky becomes theirs: "For me", the empty-sky line, "New blessing". |
| 4b | Rehearsal | "Try a few words first?" opens the real recording screen marked as practice: Begin, Listening, hold Amen, then what the phone wrote. Nothing is kept. Then 4a. "Not now" goes straight to 4a. |
| Shared | Opened from a shared blessing | Opening (the light is the shared blessing's own light), one line, Face ID, then "Keep it with your blessings?" over the sky. Keep: their sky with that one light. |

## Every word

### 1 Opening
| English | Spanish |
|---|---|
| Upon Thy Head | Upon Thy Head |

### 2 Welcome
| English | Spanish |
|---|---|
| Record a blessing as it is given. | Graba una bendición mientras se da. |
| The words are written on this phone. Nothing leaves it unless you share it. | Las palabras se escriben en este teléfono. Nada sale de él si tú no lo compartes. |
| The words as they were spoken are always kept. | Las palabras tal como se dijeron siempre se guardan. |
| Free. No account. No ads. | Gratis. Sin cuenta. Sin anuncios. |
| Continue | Continuar |

### 3 Permissions (the app's screen)
| | English | Spanish |
|---|---|---|
| Microphone label | Microphone | Micrófono |
| line | To hear the blessing as it is given. | Para oír la bendición mientras se da. |
| under it | It listens only while you record. | Solo escucha mientras grabas. |
| if refused | The microphone is off. You can turn it on in Settings, under Upon Thy Head. | El micrófono está desactivado. Puedes activarlo en Configuración, en Upon Thy Head. |
| Speech label | Speech recognition | Reconocimiento de voz |
| line | To write the words down, here on this phone. | Para escribir las palabras, aquí en este teléfono. |
| if refused | Speech recognition is off. You can turn it on in Settings, under Upon Thy Head. | El reconocimiento de voz está desactivado. Puedes activarlo en Configuración, en Upon Thy Head. |
| Location label | Location | Ubicación |
| line | To find the sky above you. | Para encontrar el cielo sobre ti. |
| under it | Without it, the sky above the Salt Lake Temple is used. | Sin ella, se usa el cielo sobre el Templo de Salt Lake. |
| if refused | The sky above the Salt Lake Temple will be used. You can change this in the app's settings. | Se usará el cielo sobre el Templo de Salt Lake. Puedes cambiarlo en los ajustes de la app. |
| Face ID label | Face ID | Face ID |
| line | Your blessings are locked. Face ID opens them. | Tus bendiciones están bloqueadas. Face ID las abre. |
| under it | You can turn the lock off in settings. | Puedes quitar el bloqueo en los ajustes. |
| if refused | Your passcode will open them instead. | Tu código las abrirá en su lugar. |
| button | Continue | Continuar |

### 3 Permissions (iOS's question, drawn as a look-alike)
The bodies are the app's real lines from `Info.plist` and `es.lproj/InfoPlist.strings`. The titles and buttons are iOS's and are written from memory, so they may not match iOS 27 word for word.

| | English | Spanish |
|---|---|---|
| Microphone | "Upon Thy Head" Would Like to Access the Microphone · Upon Thy Head listens only while you record a blessing. The audio stays on this phone. · Don't Allow / Allow | "Upon Thy Head" quiere acceder al micrófono · Upon Thy Head escucha solo mientras grabas una bendición. El audio se queda en este teléfono. · No permitir / Permitir |
| Speech | "Upon Thy Head" Would Like to Access Speech Recognition · Speech is turned into text on this phone. Nothing is sent anywhere. · Don't Allow / Allow | "Upon Thy Head" quiere acceder al reconocimiento de voz · La voz se convierte en texto en este teléfono. No se envía nada a ningún lado. · No permitir / Permitir |
| Location | Allow "Upon Thy Head" to use your location? · Used once to place your first blessing's light in the sky where it was given. Allow Once is enough. · (approximate map) · Allow Once / Allow While Using App / Don't Allow | ¿Permitir que "Upon Thy Head" use tu ubicación? · Se usa una vez para poner la luz de tu primera bendición en el cielo donde se dio. Con «Permitir una vez» basta. · Permitir una vez / Permitir al usar la app / No permitir |
| Face ID | Do you want to allow "Upon Thy Head" to use Face ID? · Unlocks your blessings. · Don't Allow / OK | ¿Quieres permitir que "Upon Thy Head" use Face ID? · Desbloquea tus bendiciones. · No permitir / Aceptar |

### 4a Straight in (the app's own strings)
| English | Spanish |
|---|---|
| For me | Para mí |
| When a blessing is recorded, its light appears here. | Cuando se grabe una bendición, su luz aparecerá aquí. |
| New blessing | Nueva bendición |

### 4b Rehearsal
| English | Spanish |
|---|---|
| Try a few words first? | ¿Probar primero con unas palabras? |
| Say anything, then hold Amen. You will see what the phone wrote. Nothing is kept. | Di cualquier cosa y luego mantén presionado Amén. Verás lo que escribió el teléfono. No se guarda nada. |
| Try it · Not now | Probar · Ahora no |
| Practice (top of the Begin screen) | Práctica |
| Begin | Comenzar |
| This is only practice. Nothing is kept. | Es solo una práctica. No se guarda nada. |
| Listening, for practice | Escuchando, de práctica |
| Amen · Hold to finish | Amén · Mantén presionado para terminar |
| What the phone wrote | Lo que escribió el teléfono |
| (their words; the mock shows "This is only a practice. I am trying it out before Sunday.") | (sus palabras; la maqueta muestra "Esto es solo una práctica. Lo estoy probando antes del domingo.") |
| Nothing from the practice is kept. | No se guarda nada de la práctica. |
| Continue | Continuar |

### Opened from a shared blessing
| English | Spanish |
|---|---|
| A blessing has been shared with you. | Alguien compartió una bendición contigo. |
| It opens after one more step. | Se abre después de un paso más. |
| (Face ID screen as above) | (pantalla de Face ID como arriba) |
| Keep it with your blessings? (already in `strings.dart`) | ¿Guardarla con tus bendiciones? (ya está en `strings.dart`) |
| Not now · Keep (already in `strings.dart`) | Ahora no · Guardar |
| One blessing (under "For me" after keeping) | Una bendición |

## What I changed from the first draft, and why

1. **No "Skip" on the permission screens.** Apple's review guideline 5.1.1(iv), as I remember it, says a screen shown before a system permission question should say "Continue" or "Next", and should not offer a way to leave without seeing the system question. Apps have been rejected for a "Not now" there. So each screen has one button, Continue. To decline, the person taps "Don't Allow" in iOS's question, and the screen then shows one calm line about where to change it. Check the current text of the guideline before building.
2. **"Asked again when first needed" only works if nothing was refused.** Once someone taps "Don't Allow", iOS will not show the question again; only Settings can change it. Since every question is now asked during the first run, the recording screen's existing refused line (`Strings.refused`) and "Open Settings" are the second chance. The flow does not try to ask again.
3. **The welcome no longer says "never sent anywhere".** Sharing as a link is decided (anyone with the link can read the blessing), so "never sent anywhere" would not be true. It now says "Nothing leaves it unless you share it."
4. **"Every word is kept as it was spoken" became "The words as they were spoken are always kept."** Polishing changes words on the reading page. You already had "Nothing has been changed" reworded for the same reason. The new line matches the reading page's own "The words as they were spoken" and is still true after polishing, because the first transcript is always kept.
5. **Each permission screen has a short label above its line** (Microphone, Speech recognition, Location, Face ID). "To record a blessing." on its own does not say what is being asked for. The label is small and grey, so each screen is still one thought.
6. **Microphone line: "To hear the blessing as it is given."** It says what the microphone is for, and "It listens only while you record" answers the worry people have about an app holding the microphone. "Record" is kept for the welcome's first line, so it isn't said twice in a row.
7. **The Salt Lake Temple sentence sits under the location line**, so the person knows what refusing means before iOS asks.
8. **Practice teaches holding Amen.** In the rehearsal, the ring is "Amen" from the first second, and the person holds it to finish. That is the one gesture that ends a real blessing, and nothing else in the app teaches it. The words appear only after Amen, the same as a real recording, so the practice does not show anything a real recording won't.
9. **In the shared version, the opening light is the shared blessing's own light**, at its place on the ring. It is the same light the person sees in "Keep it with your blessings?" and in their sky after keeping it.
10. **The opening's ring sweeps left to right**, the direction time runs along it. The opening runs about 3.8 seconds rather than 3, so the name stays on screen for about a second after it fully appears.
11. **Reduce Motion:** the opening is a cross-fade (no tilt, no sweep), the welcome lines appear together, and the screens cross-fade quickly. **Larger text:** everything is laid out from the bottom up, so the words grow upward. With the Spanish welcome at large text the words reach the light, so the light is hidden at large sizes. The share sheet's two buttons stack, with Keep on top.

## What would have to change in the app

- **A first-run flag** (for example `onboardedAt` in settings). The opening and welcome show only when it is empty. Later launches go to the lock, as today.
- **A new onboarding route** in front of the sky: opening, welcome, four permission pages, and 4a or 4b. The sky renderer's camera needs the opening's moves: exposure from black, a tilt up to the zenith, the ring drawn part of the way, and one light fading in.
- **Permission calls move out of the recording screen** into the onboarding pages (microphone, speech, location, then a first `LocalAuthentication` evaluation for Face ID). The recording screen keeps its check and its refused line for anyone who refused. Location: the app already asks for approximate location only (`NSLocationDefaultAccuracyReduced`); the place found is kept as today.
- **Face ID at first run** means a real Face ID scan during onboarding. It is skipped when the phone has no passcode (open question 27), and when the phone has Touch ID it says Touch ID instead.
- **Speech recognition** may be skipped where the new on-device engine runs, if the phone check confirms open question 36.
- **4b needs a practice mode** on the recording screen: no draft written, nothing stored, audio dropped after showing the words, and a ring that reads Amen from the start (not Discard).
- **The shared-file launch** (`share/receive.dart`) has to wait for the short onboarding and Face ID before showing its "Keep it with your blessings?" sheet. Today it probably shows that sheet straight away.
- **New strings** in `strings.dart`, in English and Spanish: everything in the tables above, except "For me", the empty-sky line, "New blessing", "Keep it with your blessings?", "Keep", "Not now", "Begin", "Amen" and "Hold to finish", which already exist.

## Questions for Noah, most important first

1. **4a or 4b?** Straight into the sky, or the optional "Try a few words first?" practice before the first blessing? I lean toward 4b, because the first real blessing can't be given twice. "Not now" keeps it to one tap for anyone who doesn't want it.
2. **All four questions at first run?** Asking up front means no system question ever interrupts a blessing while hands are raised. The cost is four questions in a row before the person has seen anything. The other way: ask only Face ID at first run, and the other three on the "New blessing" screen before Begin is pressed, still never during a recording.
3. **Speech recognition on newer phones (open question 36).** If the new engine needs no permission, those phones skip that screen entirely, and the misleading iOS wording from open question 32 disappears with it. Should we wait for the phone check before settling the onboarding?
4. **Face ID before the shared blessing opens.** As drafted, someone opening a blessing sent to them scans their face before they can see it. Should a shared blessing open to read first, with Face ID asked only once they keep it?
5. **"Not now" on a shared blessing.** In the mock it goes to the empty sky and the blessing is not kept. Should it open the blessing to read once without keeping it, or ask again the next time the file or link is opened?
6. **The opening on every launch, or only the first?** As drafted it is first run only; later launches go straight to the lock. A shorter one (the sky rising, about 1.5 seconds) could play every time.
7. **"Free. No account. No ads."** Keep it on the welcome, or leave it to the App Store page?
8. **Where does the opening's light go?** It fades during the welcome, so the empty sky in 4a has no light. Is it right that the first light is shown and then taken away, or should the opening have only the ring, and the first light arrive with the first blessing?
