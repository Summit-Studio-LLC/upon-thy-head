# Upon Thy Head: every English string and its Spanish

For a native speaker to read. The app shows Spanish when the phone's first language is any Spanish,
English otherwise. The Spanish aims at plain, warm, reverent Latin American Spanish as used in the
United States, addressing the person as "tú". Names, titles, tags and the blessing's own words are
never translated.

**★ marks the ones I most want checked.** The note says why. Where a string has a number or a name
in it, an example is shown; each Spanish sentence is written whole (never pieced together from the
English order).

The source of truth is `app/lib/strings.dart` (class `Words` for English, `_Spanish` for Spanish).
Change a wording there; this file is a copy for reading.

## The most important questions

1. ★ **"Ajustes" or "Configuración".** The brief says Settings = "Ajustes", and the app's own page is
   called that. But iOS in Latin American Spanish calls the iPhone's Settings app
   **"Configuración"** ("Ajustes" is Spain's iOS). The button that opens the iPhone's Settings app
   says "Abrir Configuración" so the person can find it. Should the app's own page also be
   "Configuración", so there is only one word?
2. ★ **"Pulir" for "polish".** "Pulir las palabras", "Pulidas para leer", "Usar pulidas". Natural
   for text ("pulir un texto"), but a speaker may prefer "Corregir", "Limpiar" or "Afinar".
3. ★ **"Muletilla" for "filler".** "Muletilla" is the everyday word for "um", "este", "o sea". It
   can also mean a pet phrase, which is not quite "um".
4. ★ **Times of day.** Midnight to 5:59 is "de la madrugada", morning is 6:00–11:59
   ("de la mañana"), afternoon 12:00–6:59 pm ("de la tarde"), night 7:00–11:59 pm ("de la noche").
   English uses evening 5–9 pm; Spanish has no common "evening" word, so 7 pm onwards is
   "de la noche". One o'clock takes "a la" ("a la 1:15"), others "a las".
5. ★ **Months shortened:** "ene, feb, mar, abr, may, jun, jul, ago, sept, oct, nov, dic", with no
   full stop, as in "15 nov 2026". September as "sept" (US and Mexican usage) or "sep"?
6. ★ **The reading page's last line** (also open question 6 in decisions): "Su luz guarda su lugar
   en el tiempo, en el anillo del cielo que está en lo alto." The English is a placeholder too.
7. ★ **"Mantén presionado para descartar"** under the ring is long. "Mantén presionado" is iOS's
   own Latin American wording. "Mantén para descartar" would be shorter but less natural.

## Home

| English | Spanish | Note |
|---|---|---|
| For me | Para mí | |
| Show as a list | Ver como lista | VoiceOver |
| Show as a sky | Ver como cielo | VoiceOver |
| Read this blessing | Leer esta bendición | VoiceOver |
| Earlier blessing / Later blessing | Bendición anterior / Bendición siguiente | VoiceOver, the arrows |
| New blessing | Nueva bendición | |
| From Dad | De Dad | |
| When a blessing is recorded, its light appears here. | Cuando se grabe una bendición, su luz aparecerá aquí. | |
| No blessings yet | Todavía no hay bendiciones | |
| One blessing since June 2024 | Una bendición desde junio de 2024 | Counts are in words up to twelve |
| Five blessings since June 2024 | Cinco bendiciones desde junio de 2024 | |
| 21 blessings since June 2024 | 21 bendiciones desde junio de 2024 | |
| 1 to review / 3 to review | 1 por revisar / 3 por revisar | The gold badge |
| One blessing to review. Opens it. | Una bendición por revisar. Ábrela. | ★ VoiceOver. The English describes what happens, the Spanish asks the person to do it. "La abre" sounded wrong. |
| 3 blessings to review. Opens the oldest. | 3 bendiciones por revisar. Abre la más antigua. | VoiceOver |
| Not reviewed | Sin revisar | Under a draft in the list |
| Blessing | Bendición | The title of a blessing nobody has named yet. A draft made in English shows "Bendición" on a Spanish phone, and the reverse. A title someone typed is never changed. |

## Dates and times

| English | Spanish |
|---|---|
| Sunday, November 15, 2026 | domingo, 15 de noviembre de 2026 |
| Nov 15, 2026 (sky labels) | 15 nov 2026 |
| Nov 15 (list) | 15 nov |
| 9:40 in the morning | 9:40 de la mañana |
| 1:15 in the afternoon | 1:15 de la tarde |
| 10:23 at night | 10:23 de la noche |
| Tuesday, March 3, 9:40 in the morning (after Amen) | martes, 3 de marzo, 9:40 de la mañana |

Weekdays and months are lowercase, as Spanish writes them, even at the start of a line. ★ Is that
right at the start of a line on its own?

## Recording

| English | Spanish | Note |
|---|---|---|
| Close | Cerrar | |
| Begin | Comenzar | |
| Begin. Nothing is recorded until you press | Comenzar. No se graba nada hasta que lo presiones | VoiceOver |
| Nothing is recorded until you press. | No se graba nada hasta que lo presiones. | |
| Language of the blessing: Español | Idioma de la bendición: Español | VoiceOver. Language names are always in their own language. |
| Listening | Escuchando | |
| Paused | En pausa | During a call |
| Discard | Descartar | |
| Amen | Amén | |
| Hold to discard | Mantén presionado para descartar | ★ length (see question 7) |
| Hold to finish | Mantén presionado para terminar | |
| Discard. Hold to discard this recording | Descartar. Mantén presionado para descartar esta grabación | VoiceOver |
| Amen. Hold to finish | Amén. Mantén presionado para terminar | VoiceOver |
| Discard this recording? | ¿Descartar esta grabación? | |
| Nothing from it will be kept. It keeps listening while you decide. | No se guardará nada de ella. Sigue escuchando mientras decides. | ★ "Sigue escuchando" could be read as an order to the person ("keep listening!"). The app is the one listening. Perhaps "La app sigue escuchando mientras decides." |
| Keep listening | Seguir escuchando | |
| The microphone and speech recognition are turned off for Upon Thy Head. | El micrófono y el reconocimiento de voz están desactivados para Upon Thy Head. | |
| The microphone is turned off for Upon Thy Head. | El micrófono está desactivado para Upon Thy Head. | |
| Speech recognition is turned off for Upon Thy Head. | El reconocimiento de voz está desactivado para Upon Thy Head. | |
| Open Settings | Abrir Configuración | ★ question 1 |

## After Amen

| English | Spanish |
|---|---|
| Writing the words… | Escribiendo las palabras… |
| The words are kept | Las palabras están guardadas |
| The recording stays on this phone until you have reviewed the words. Then it is erased. | La grabación se queda en este teléfono hasta que hayas revisado las palabras. Después se borra. |
| No words were heard | No se oyeron palabras |
| The recording is kept | La grabación está guardada |
| The words could not be written on this phone yet. The recording stays here until they can be. | Todavía no se pudieron escribir las palabras en este teléfono. La grabación se queda aquí hasta que se pueda. |
| The words could not be written this time. The recording stays on this phone. | Esta vez no se pudieron escribir las palabras. La grabación se queda en este teléfono. |
| Review now | Revisar ahora |
| Save for later | Guardar para después |

"Escribir las palabras" stands for the phone turning speech into text. ★ "Transcribir" is more
exact but more technical; the English avoids "transcribe" on purpose.

## A recording kept when the app closed

| English | Spanish |
|---|---|
| A recording was kept | Se guardó una grabación |
| Two recordings were kept | Se guardaron dos grabaciones |
| The app closed while a blessing was being recorded on Sunday, November 15, 10:23 at night. What had been recorded is saved. | La app se cerró mientras se grababa una bendición el domingo 15 de noviembre, a las 10:23 de la noche. Lo que se había grabado está guardado. |
| The app closed while two blessings were being recorded. What had been recorded is saved. | La app se cerró mientras se grababan dos bendiciones. Lo que se había grabado está guardado. |
| Review now / Later | Revisar ahora / Más tarde |

## Review page

| English | Spanish | Note |
|---|---|---|
| Review / Review this blessing | Revisar / Revisar esta bendición | |
| Not yet reviewed. The recording stays on this phone until you finish. | Todavía sin revisar. La grabación se queda en este teléfono hasta que termines. | |
| Back. Everything typed is kept | Atrás. Todo lo que escribiste se guarda | VoiceOver |
| Done | Listo | iOS's own word for Done |
| Blessing (title placeholder) | Bendición | |
| Title | Título | |
| From / For | De / Para | Field labels |
| From: who gave the blessing | De: quién dio la bendición | VoiceOver |
| For: who it was given to | Para: a quién se le dio | VoiceOver |
| Name | Nombre | Placeholder |
| Tags | Etiquetas | |
| Add a tag | Agregar una etiqueta | "Agregar" (Latin America), not "añadir" (Spain) |
| Remove tag Healing / Add tag Healing | Quitar la etiqueta Healing / Agregar la etiqueta Healing | VoiceOver; tags are never translated |
| Play the recording / Pause | Reproducir la grabación / Pausar | VoiceOver |
| Back ten seconds | Retroceder diez segundos | VoiceOver |
| 0:12 of 1:04 | 0:12 de 1:04 | VoiceOver |
| The words | Las palabras | |
| The words could not be written on this phone. Listen to the recording and type them here. | No se pudieron escribir las palabras en este teléfono. Escucha la grabación y escríbelas aquí. | |
| No words were heard. Listen to the recording and type them here. | No se oyeron palabras. Escucha la grabación y escríbelas aquí. | |
| Type the words | Escribe las palabras | Placeholder |
| Finished reviewing? | ¿Terminaste de revisar? | |
| The recording will be erased from this phone. The words stay. | La grabación se borrará de este teléfono. Las palabras se quedan. | |
| Finish / Not yet | Terminar / Todavía no | |

## Polish and the changes screen

| English | Spanish | Note |
|---|---|---|
| Polish the words | Pulir las palabras | ★ question 2 |
| Leaves out filler sounds and stumbled-over words. Every change can be undone. | Quita las muletillas y las palabras repetidas sin querer. Cada cambio se puede deshacer. | ★ "stumbled-over words" became "words repeated by mistake", which is what polish actually finds |
| Nothing to polish. | No hay nada que pulir. | |
| The spoken words | Las palabras dichas | |
| Polished for reading | Pulidas para leer | ★ |
| 1 change / 4 changes | 1 cambio / 4 cambios | |
| 1 of 2 kept / 3 of 4 kept | Se conserva 1 de 2 / Se conservan 3 de 4 | ★ Written as a sentence so singular and plural agree |
| Original words | Palabras originales | |
| Restore all | Restaurar todo | |
| Use polished | Usar pulidas | ★ short for "usar las palabras pulidas" |
| Restore original | Restaurar original | |
| Next | Siguiente | |
| Original / Polished | Original / Pulido | Sheet labels. ★ "Pulido" (el texto) next to "Pulidas" (las palabras) elsewhere. |
| Left out | Omitido | Where a change removes words |
| Previous change / Next change | Cambio anterior / Cambio siguiente | VoiceOver |
| 2 of 5 | 2 de 5 | |
| Light / Moderate / Heavy change | Cambio leve / Cambio moderado / Cambio grande | ★ "grande" or "importante" |
| Filler removed | Muletilla quitada | ★ question 3 |
| Repeated word removed | Palabra repetida quitada | |
| Reworded | Reformulado | |
| Grammar corrected | Gramática corregida | |
| Punctuation | Puntuación | |
| Light change. Filler removed. Original: um. Polished: Left out. Polished words in use. | Cambio leve. Muletilla quitada. Original: um. Pulido: Omitido. Se usan las palabras pulidas. | VoiceOver |
| … Original words restored. | … Se restauraron las palabras originales. | VoiceOver |
| Polished from the spoken words, with 5 small changes. The original is kept beside it. | Pulidas a partir de las palabras dichas, con 5 pequeños cambios. Las originales se guardan junto a ellas. | Reading page |
| Review changes | Revisar los cambios | |

## Reading page

| English | Spanish | Note |
|---|---|---|
| Back to the sky | Volver al cielo | |
| Edit | Editar | |
| A blessing from Dad | Una bendición de Dad | Names never translated |
| For Emma | Para Emma | |
| The words as they were spoken. | Las palabras tal como se dijeron. | |
| No words have been kept for this blessing yet. | Todavía no se han guardado palabras para esta bendición. | |
| Its light keeps its place in time on the ring of sky overhead. | Su luz guarda su lugar en el tiempo, en el anillo del cielo que está en lo alto. | ★ question 6 |
| Its light keeps the place in the sky that was straight overhead at 1:15 in the afternoon, behind the daylight. | Su luz guarda el lugar del cielo que estaba justo encima a la 1:15 de la tarde, detrás de la luz del día. | Not shown at present (the ring placement is used) |
| Edit this blessing / Title / From / Save / Cancel | Editar esta bendición / Título / De / Guardar / Cancelar | |

## Deleting

| English | Spanish |
|---|---|
| Delete this blessing | Eliminar esta bendición |
| Delete this blessing? | ¿Eliminar esta bendición? |
| Its words will be removed from this phone. This cannot be undone. | Sus palabras se quitarán de este teléfono. Esto no se puede deshacer. |
| Delete / Keep | Eliminar / Conservar |

## The app lock

| English | Spanish | Note |
|---|---|---|
| Locked | Bloqueado | "Para mí · Bloqueado" |
| Unlock | Desbloquear | |
| Unlock your blessings | Desbloquea tus bendiciones | Shown by iOS under the passcode question |
| Turn off the app lock | Desactivar el bloqueo de la app | Shown by iOS |

## Settings

| English | Spanish | Note |
|---|---|---|
| Settings | Ajustes | ★ question 1 |
| Back to the sky | Volver al cielo | |
| App lock | Bloqueo de la app | |
| Asks for Face ID when you open the app. Recording never waits for it. | Pide Face ID al abrir la app. Para grabar nunca hace falta. | ★ The second sentence is reworded ("it is never needed to record"). The literal one ("La grabación nunca lo espera") read oddly. |
| Asks for your passcode when you open the app. … | Pide tu código al abrir la app. … | "código" is iOS's Latin American word for passcode |
| Set a passcode on this iPhone to lock your blessings. | Configura un código en este iPhone para bloquear tus bendiciones. | |
| Language for recording | Idioma para grabar | |
| The language new recordings start in. Choosing one on the Begin screen changes it here too. | El idioma en que empiezan las grabaciones nuevas. Si eliges uno en la pantalla Comenzar, también cambia aquí. | |
| Same as this iPhone | Igual que este iPhone | |
| Where blessings are given | Dónde se dan las bendiciones | ★ "se dan" for blessings given: Church usage might prefer another verb |
| Near Salt Lake Temple | Cerca del Templo de Salt Lake | The Church's Spanish name for the temple |
| Near 40.8° N, 111.9° W | Cerca de 40.8° N, 111.9° O | West is O (oeste); decimal point as in the US and Mexico |
| Decides which ring of sky the lights sit on. Only a rough place is kept. | Decide en qué anillo del cielo quedan las luces. Solo se guarda un lugar aproximado. | |
| Use my location | Usar mi ubicación | |
| About | Acerca de | |
| Your words stay on this iPhone. Nothing is sent anywhere. | Tus palabras se quedan en este iPhone. No se envía nada a ningún lado. | |
| Version 0.1.0 | Versión 0.1.0 | |

## Sharing (reading page, and the shared text and PDF)

| English | Spanish | Note |
|---|---|---|
| Share (the icon, for VoiceOver) | Compartir | |
| Share this blessing | Compartir esta bendición | |
| As text | Como texto | |
| The words, to paste or send in a message. | Las palabras, para pegar o enviar en un mensaje. | |
| As a PDF | Como PDF | |
| A page to print or keep. | Una página para imprimir o guardar. | |
| Once it leaves this phone, it is no longer private to it. | Una vez que sale de este teléfono, ya no es privada. | ★ The English "private to it" has no neat Spanish; this says "it is no longer private". |
| 2 of 3 (the PDF's footer) | 2 de 3 | |
| March 3, 2026 (in a shared file's name) | 3 de marzo de 2026 | "Comfort before surgery, 3 de marzo de 2026.pdf"; the title is never translated |

The shared text and the PDF use the reading page's own lines: the long date, "Una bendición de …"
and "Para …".

## The system's questions (app/ios/Runner/es.lproj/InfoPlist.strings)

iOS shows these under its own question. Apple writes the question's title and buttons, in the
phone's language.

| English | Spanish |
|---|---|
| Upon Thy Head listens only while you record a blessing. The audio stays on this phone. | Upon Thy Head escucha solo mientras grabas una bendición. El audio se queda en este teléfono. |
| Speech is turned into text on this phone. Nothing is sent anywhere. | La voz se convierte en texto en este teléfono. No se envía nada a ningún lado. |
| Used once to place your first blessing's light in the sky where it was given. Allow Once is enough. | Se usa una vez para poner la luz de tu primera bendición en el cielo donde se dio. Con «Permitir una vez» basta. |
| Unlocks your blessings. | Desbloquea tus bendiciones. |

«Permitir una vez» matches Apple's button: on a simulator set to Spanish (United States),
`app/tool/spanish_prompts.sh` shows all three questions in Spanish and taps that button by name
(screenshots in `design/sim/spanish/prompts/`).

## Words used throughout

bendición (blessing) · Para mí · Nueva bendición · Comenzar · Amén · Descartar · Revisar ahora ·
Guardar para después · Ajustes · Bloqueo de la app · grabación (recording) · las palabras (the
words) · teléfono (phone) where English says phone, iPhone where English says iPhone · "tú"
throughout.

## Left as they are on purpose

- **Language names** in Settings and on the recording screen are each language's own name:
  "English" and "Español" in both languages, as iOS lists languages. ★ "Inglés" is the other choice.
- **Tags** suggested when tagging are the tags already used on other blessings, so on a phone
  with the sample blessings they are English ("Healing", "Family"). Tags are never translated.
