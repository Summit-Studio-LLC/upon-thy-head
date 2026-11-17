# Past blessings, kept rings: design notes

A draft for the owner. Open `index.html` (a 390×844 phone, clickable). The controls beside it switch between Part A, B1, B2 and B3, choose where Part A starts (S1 or S2), step through the screens, and switch English or Spanish, larger text and Reduce Motion. Screenshots are in `shots/` at 3x:
- `A-`, `B1-`, `B2-` and `B3-` files are in order.
- `es-` files are the Spanish versions of the main screens.
- `big-es-` files are Spanish at larger text.

`compare-A.png` puts Part A in one row. `compare-B.png` lines up B1, B2 and B3 by moment.

Nothing here is app code, and nothing outside this folder was touched.

---

## Part A: entering a past blessing

**What it is.** Someone has a blessing written down: typed up years ago, in a journal, or in an email. They put it into the app, and it takes its place on their ring at the date it was given.

### Where it starts. Recommended: S1

- **S1, inside New blessing (recommended).** The home is unchanged, and "New blessing" still goes straight to the recording screen. At the foot of that screen, far from Begin, sits one quiet line: **Enter a past blessing**.
  - Recording stays one tap away, and entering takes two.
  - Someone standing with hands about to be laid on a head never has to choose.
  - It also gives a way in to anyone who refused the microphone.
- **S2, two pills on home.** "Record" and "Enter" sit side by side. Entering is found sooner, but the home loses its single quiet action, and every visit asks for a choice that is almost always "Record".

### The entry page is the review page

The app's review page, with two changes:
- A first row, **Given** (Spanish: *Fecha*). It reads "When was it given?" until a date is set.
- **The words** start empty: "Type the words here, or paste them in one go." with a **Paste** chip.

The rest is as it is today: title, From, For, "For me / Passing it along", and tags.

There is no listen bar, because there is no recording. The light in the header appears once there is a date.

A long pasted blessing keeps its paragraphs, and nothing is polished or changed. The banner at the top of the pasted screen is iOS's own paste notice, drawn from memory.

### The date

A sheet titled "When was it given?" offers three choices: **Full date / Month and year / Year only**. The wheels change to match.

| What is known | Where its light sits | How it reads everywhere |
|---|---|---|
| Full date | That day, at noon (no time of day is asked) | "Sunday, August 23, 1998" |
| Month and year | The 15th of the month | "August 1998" |
| Year only | July 2, the middle of the year | "1998" |

The sheet says so in one line, for example "Only the year is known. Its light sits at mid-1998."

A year-only light never claims to be first or last in its year. If a full date in the same year is added, the two are ordered by that middle day.

### Where it was given: not asked

An entered blessing takes the rough place the phone already keeps, the same place a recording would use, or the Salt Lake Temple when location is refused.

The place only matters for the first blessing on a ring, which sets the ring's height. So:
- The ring keeps its height.
- Only its start moves.
- No new field is needed.

This is the least that could be drawn. Asking for a place would add a field that most people cannot answer for a blessing given 28 years ago, for an effect they would never see.

### Saving

The sky turns to the new light, which brightens in place. With Reduce Motion it fades in and the sky does not turn.
- The count becomes **"Six blessings since August 1998"**.
- The ruler reaches back: 2000, 2005 … 2025, with the new dot alone at the left and the other five close together at the right.

### When it is earlier than all the others (before and after)

The ring begins at the first blessing. In `A-11` and `A-12` the view is pinched out:
- **Before:** the ring begins at June 2024, and five lights are spread at 24° a year.
- **After:** the ring begins in August 1998, off to the left. The span is now 28 years, so (as `placement.dart` already does) the whole span is fitted into the ring, and the same five lights slide closer together.

With Reduce Motion they cross-fade to their new places instead of sliding.

### Honesty about the words

Where a recorded blessing's reading page says "The words as they were spoken.", an entered one says, with a small page icon:

> **Entered from a written copy, not recorded.** / *Anotada de una copia escrita, no grabada.*

### A later idea (only a sketch)

`A-15`: photograph a printed page, and the phone reads the words on the device into the same entry page. The photo is not kept. It is marked "A later idea" and is not part of this design.

---

## Part B: a parent keeping a ring for a child

The example family:
- **Dad** has his own five blessings.
- **Emma** was born in 2008 and has seven blessings, the first a naming blessing in August 2008.
- **James** was born in 2013 and has four.
- **Clara** is added as a newborn.
- **Mom** holds four more of Emma's on her own phone.

### B1, a ring for each person (recommended): what's drawn

| # | Screen |
|---|---|
| 1–3 | The home title gets a small chevron. "For me ⌄" opens a sheet: For me, For Emma, For James, each with its count, then "Add someone". Choosing Emma shows **her** sky, with her count, her ruler from 2008, and New blessing for her. |
| 4–5 | **Adding someone** asks for a name and an optional birth date: "Their ring begins on this day." An empty ring reads "When a blessing is recorded for Clara, a light appears here." |
| 6–8 | **Recording for a child.** The recording screen shows a small "For Emma ⌄" chosen from the open sky. On the review page, "Whose blessing" becomes a row of names: For me · Emma · James · Clara · Passing it along. Entering a past one for Emma is Part A's page with Emma chosen. |
| 9–11 | **The hand-over, the parent's side.** It sits in the ··· menu of Emma's sky ("Hand over Emma's ring"), because it is rare and deliberate. The sheet uses the card the owner already chose for sharing: Emma's ring, its count, a **Kept by: Dad** row (editable), the gold "Send Emma's ring", "Emma can keep them in Upon Thy Head.", and "This sends a link. Anyone who has it can read these blessings." Then comes the ruled choice: "Keep Emma's ring on this phone, or delete it now?" with "If you keep it, blessings added later can be sent to Emma too." Keep is the gold button here. |
| 12–14 | **The child's side.** The link opens "Your blessings were kept for you.", then her blessings oldest first, one at a time ("1 of 7"), with Not now / **Keep them**. Her sky already holds seven lights from before she can remember, with one line under the count: **Kept for you by Dad**. |
| 15 | **The parent afterwards (kept).** Emma's ring stays, with "Handed to Emma on November 16". A blessing added later shows "One new · Send it", which sends only the new ones, and it can be done again whenever there are more. If the parent chose Delete, the ring and its blessings leave the phone. |
| 16 | **Two parents.** See below. |

**Two parents.** Mom kept four of Emma's on her phone. When she hands them over, Emma's phone asks once: "Four more of your blessings", "Kept by Mom", "They join your ring by their dates." They take their places by date. A blessing both phones already had (the same one shared between the parents) is kept once. The line becomes "Kept for you by Dad and Mom".

### How B2 and B3 differ at the same moments

| Moment | B1, a ring each | B2, one sky with several rings | B3, a list for each child |
|---|---|---|---|
| Home | One person's sky; the title switches | Every ring in one sky, the others fainter and lower, with names at their left end | As today; children have no lights on this phone |
| Adding a child | Name and birth date | Same page; a new faint ring appears | No step: a group forms from the For name; a birth date has nowhere to go |
| Recording for a child | A row of names on the review page | Same as B1 | "Passing it along", For Emma (as built now) |
| Handing over | From the ··· menu of her sky | From her ring brought forward | "Send all" on her group |
| Afterwards | The ring is marked "Handed to Emma on …" | Her ring very faint, labelled "handed over" | The group shows "sent November 16" |
| Child's side | Same in all three: read first, Keep them, sky already lit, "Kept for you by Dad" | | |

### What each makes easy and hard

**B1, a ring for each person**
- *Easy:*
  - Each sky stays one person's life. The parent sees Emma's sky exactly as Emma will.
  - The hand-over moves a whole sky from one phone to another, and nothing about it has to be redrawn.
  - Recording for Emma is natural when her sky is open.
- *Hard:*
  - One more thing to learn: the title is a switch.
  - A parent might record into the wrong sky; the "For Emma ⌄" on the recording screen and the names on review are there to catch that.
- *Build cost: moderate.*
  - An owner, or ring, on each blessing.
  - A small list of rings with names and birth dates.
  - The switch sheet.
  - A hand-over link that carries many blessings, and a receive flow for many.
  - A "Kept by" field.
  - The sky renderer is unchanged: it draws one ring, as now.

**B2, one sky with several rings**
- *Easy:* the whole family is in one view, and it is beautiful at two or three rings.
- *Hard:*
  - It breaks "a sky is one person's life": the parent's sky now holds other people's lights.
  - It crowds quickly. With four rings (`B2-03`) the sky is full, and labels must be kept off the faint rings.
  - Tap targets on thin rings are hard, especially at larger text.
  - After the hand-over, a ghost of the child's ring stays in the parent's sky.
- *Build cost: high.* Everything in B1, plus drawing several rings at once, tapping a ring to bring it forward, and a layout that copes with any number of rings.

**B3, a list for each child**
- *Easy:*
  - Cheapest to build: group the existing "To pass along" list by the For name, and add "Send all".
  - Nothing new to learn on the home.
- *Hard:*
  - The parent never sees a child's sky.
  - A birth date has nowhere to go, so the child's ring starts at the first blessing rather than at birth.
  - Grouping by a typed name is fragile ("Emma", "Em", "Emma G.").
  - Years of a child's blessings sit in a list described as blessings "for someone else".
- *Build cost: low.* Grouping, a bundled link, and the same receive flow.

### Recommendation: B1

- It keeps the rule that each sky is one person's life, and the hand-over becomes the moment that life is handed over whole.
- Its cost sits mostly in data and links, not in the sky renderer.
- B2 looks fine at first but strains at the third child.
- B3 is cheap but leaves out what makes the app worth it: the child's sky beginning at their birth.

### How B relates to "Passing it along"

"Passing it along" stays, for **one-off** blessings for someone without a ring: a friend, a neighbour, someone in the ward. They still have no light in the recorder's sky, and they are still shared and then kept or deleted.

A ring is for someone whose blessings you keep over **years** and hand over later. On the review page both sit in one row of choices: For me · Emma · James · Clara · Passing it along. Someone who adds no rings sees exactly today's two choices.

B3 is in effect "Passing it along" stretched to do this job, which is why it is cheap and also why it falls short.

---

## Questions for the owner, most important first

1. **Should a child's blessings live in their own sky?** The title becomes a switch ("For me ⌄" opens For Emma, For James), as in B1. The alternatives are all the rings in one sky (B2), or only a list grouped by child under "To pass along" (B3).
2. **When a ring is handed over, which button should be gold: Keep or Delete?** The sheet asks "Keep Emma's ring on this phone, or delete it now?". Drawn: Keep is gold, so later blessings can be sent too. For a single shared blessing, the earlier ruling did not favour either.
3. **Should the app ever suggest the hand-over**, for example a quiet line in Emma's sky when she turns 18? Or should it only ever be in the ··· menu, as drawn?
4. **Should Emma's sky say "Kept for you by Dad", and each of her reading pages say "Kept by Dad"?** If so, should that name be typed once at hand-over (drawn, filled from the most common From name), or taken from the parent's profile?
5. **When you add Emma as a ring, what happens to blessings already in "To pass along" for Emma?** Should they move onto her ring, or should the app ask?
6. **Where should entering a past blessing start?** Drawn as recommended (S1): "Enter a past blessing" at the foot of the recording screen. The alternative (S2) is two pills on the home, Record and Enter.
7. **Must an entered blessing have at least a year?** Drawn: yes. Without one it cannot sit on the ring, and Done stays dim until there is a date.
8. **Is it all right that entering a much older blessing moves the start of the ring?** The other lights then slide closer together (A-11 and A-12). The alternative is to keep the ring as it is and set the older light apart, but that would no longer be one ring through time.
9. **Is the line "Entered from a written copy, not recorded." right** where a recorded one says "The words as they were spoken."?
10. **When two parents each kept blessings for Emma,** is it right that her phone joins them into one ring, shows one copy of any blessing both had, and reads "Kept for you by Dad and Mom"?

---

## The words on every screen

Taken from the mock itself, one table per screen, in order.
- The blessing texts are left out of the tables and given once at the end.
- Words drawn on the sky (light labels and ring names) are listed here, because they are not in the page text:
  - "Aug 24, 2025" / "24 ago 2025"
  - "Mar 3, 2026" / "3 mar 2026"
  - "Jun 2024" / "jun 2024"
  - "Aug 2022" / "ago 2022"
  - "Aug 16, 2026" / "16 ago 2026"
  - "For me" / "Para mí"
  - "Emma", "James", "Clara"
  - "Emma · handed over" / "Emma · entregado"
- On the picker, where Spanish puts the day before the month, the wheel rows are in a different order.
- The rail's notes beside the phone are in English only.

### A

**A-01 Home, as today**

| English | Español |
|---|---|
| For me | Para mí |
| Five blessings since June 2024 | Cinco bendiciones desde junio de 2024 |
| Sunday, October 4, 2026 | domingo, 4 de octubre de 2026 |
| Before the new job | Antes del nuevo trabajo |
| From Dad | De papá |
| New blessing | Nueva bendición |

**A-02 S2: home with Record and Enter**

| English | Español |
|---|---|
| For me | Para mí |
| Five blessings since June 2024 | Cinco bendiciones desde junio de 2024 |
| Sunday, October 4, 2026 | domingo, 4 de octubre de 2026 |
| Before the new job | Antes del nuevo trabajo |
| From Dad | De papá |
| Record | Grabar |
| Enter | Anotar |

**A-03 S1: the recording screen**

| English | Español |
|---|---|
| New blessing | Nueva bendición |
| Close | Cerrar |
| Begin | Comenzar |
| Nothing is recorded until you press. | No se graba nada hasta que lo presiones. |
| English ⌃⌄ | Español ⌃⌄ |
| Enter a past blessing | Anotar una bendición pasada |

**A-04 The entry page, empty**

| English | Español |
|---|---|
| Done | Listo |
| Blessing | Bendición |
| Given | Fecha |
| When was it given? | ¿Cuándo se dio? |
| From | De |
| Name | Nombre |
| For | Para |
| Whose blessing | De quién es |
| For me | Para mí |
| Passing it along | Para entregar |
| Tags | Etiquetas |
| Add a tag | Agregar una etiqueta |
| + Family | + Familia |
| + Healing | + Sanación |
| + Calling | + Llamamiento |
| + Comfort | + Consuelo |
| + Work | + Trabajo |
| The words | Las palabras |
| Type the words here, or paste them in one go. | Escribe aquí las palabras, o pégalas de una vez. |
| Paste | Pegar |

**A-05 Pasted in one go**

| English | Español |
|---|---|
| Done | Listo |
| Blessing | Bendición |
| Given | Fecha |
| When was it given? | ¿Cuándo se dio? |
| From | De |
| Name | Nombre |
| For | Para |
| Whose blessing | De quién es |
| For me | Para mí |
| Passing it along | Para entregar |
| Tags | Etiquetas |
| Add a tag | Agregar una etiqueta |
| + Family | + Familia |
| + Healing | + Sanación |
| + Calling | + Llamamiento |
| + Comfort | + Consuelo |
| + Work | + Trabajo |
| The words | Las palabras |
| Upon Thy Head pasted from Notes | Upon Thy Head pegó desde Notas |

**A-06 When: the full date**

| English | Español |
|---|---|
| Done | Listo |
| Blessing | Bendición |
| Given | Fecha |
| When was it given? | ¿Cuándo se dio? |
| From | De |
| Name | Nombre |
| For | Para |
| Whose blessing | De quién es |
| For me | Para mí |
| Passing it along | Para entregar |
| Tags | Etiquetas |
| Add a tag | Agregar una etiqueta |
| + Family | + Familia |
| + Healing | + Sanación |
| + Calling | + Llamamiento |
| + Comfort | + Consuelo |
| + Work | + Trabajo |
| The words | Las palabras |
| Full date | Fecha exacta |
| Month and year | Mes y año |
| Year only | Solo el año |
| June | junio |
| July | julio |
| August | agosto |
| September | septiembre |
| October | octubre |

**A-07 When: month and year**

| English | Español |
|---|---|
| Done | Listo |
| Blessing | Bendición |
| Given | Fecha |
| When was it given? | ¿Cuándo se dio? |
| From | De |
| Name | Nombre |
| For | Para |
| Whose blessing | De quién es |
| For me | Para mí |
| Passing it along | Para entregar |
| Tags | Etiquetas |
| Add a tag | Agregar una etiqueta |
| + Family | + Familia |
| + Healing | + Sanación |
| + Calling | + Llamamiento |
| + Comfort | + Consuelo |
| + Work | + Trabajo |
| The words | Las palabras |
| Full date | Fecha exacta |
| Month and year | Mes y año |
| Year only | Solo el año |
| June | junio |
| July | julio |
| August | agosto |
| September | septiembre |
| October | octubre |
| Only the month is known. Its light sits at mid-August 1998. | Solo se sabe el mes. Su luz se sitúa a mediados de agosto de 1998. |

**A-08 When: year only**

| English | Español |
|---|---|
| Done | Listo |
| Blessing | Bendición |
| Given | Fecha |
| When was it given? | ¿Cuándo se dio? |
| From | De |
| Name | Nombre |
| For | Para |
| Whose blessing | De quién es |
| For me | Para mí |
| Passing it along | Para entregar |
| Tags | Etiquetas |
| Add a tag | Agregar una etiqueta |
| + Family | + Familia |
| + Healing | + Sanación |
| + Calling | + Llamamiento |
| + Comfort | + Consuelo |
| + Work | + Trabajo |
| The words | Las palabras |
| Full date | Fecha exacta |
| Month and year | Mes y año |
| Year only | Solo el año |
| Only the year is known. Its light sits at mid-1998. | Solo se sabe el año. Su luz se sitúa a mediados de 1998. |

**A-09 Filled in, its light appears**

| English | Español |
|---|---|
| Done | Listo |
| Before college | Antes de la universidad |
| Given | Fecha |
| August 1998 | agosto de 1998 |
| From | De |
| Dad | Papá |
| For | Para |
| Daniel | Daniel |
| Whose blessing | De quién es |
| For me | Para mí |
| Passing it along | Para entregar |
| Tags | Etiquetas |
| Family × | Familia × |
| Add a tag | Agregar una etiqueta |
| + Healing | + Sanación |
| + Calling | + Llamamiento |
| + Comfort | + Consuelo |
| + Work | + Trabajo |
| The words | Las palabras |

**A-10 Saved: the light arrives**

| English | Español |
|---|---|
| For me | Para mí |
| Six blessings since August 1998 | Seis bendiciones desde agosto de 1998 |
| August 1998 | agosto de 1998 |
| Before college | Antes de la universidad |
| From Dad | De papá |
| New blessing | Nueva bendición |

**A-11 Earliest moves: before**

| English | Español |
|---|---|
| For me | Para mí |
| Five blessings since June 2024 | Cinco bendiciones desde junio de 2024 |
| Sunday, October 4, 2026 | domingo, 4 de octubre de 2026 |
| Before the new job | Antes del nuevo trabajo |
| From Dad | De papá |
| New blessing | Nueva bendición |

**A-12 Earliest moves: after**

| English | Español |
|---|---|
| For me | Para mí |
| Six blessings since August 1998 | Seis bendiciones desde agosto de 1998 |
| Sunday, October 4, 2026 | domingo, 4 de octubre de 2026 |
| Before the new job | Antes del nuevo trabajo |
| From Dad | De papá |
| New blessing | Nueva bendición |

**A-13 Its reading page**

| English | Español |
|---|---|
| Edit | Editar |
| August 1998 | agosto de 1998 |
| Before college | Antes de la universidad |
| A blessing from Dad | Una bendición de papá |

**A-14 The end of its reading page**

| English | Español |
|---|---|
| Edit | Editar |
| Entered from a written copy, not recorded. | Anotada de una copia escrita, no grabada. |
| For Daniel | Para Daniel |
| Family | Familia |
| Its light keeps its place in time on the ring of sky overhead. | Su luz guarda su lugar en el tiempo, en el anillo del cielo que está en lo alto. |
| Delete this blessing | Eliminar esta bendición |

**A-15 Later idea: read a printed page**

| English | Español |
|---|---|
| A later idea | Una idea para después |
| The words are read on this phone. The photo is not kept. | Las palabras se leen en este teléfono. La foto no se guarda. |
| Read the words | Leer las palabras |

### B1

**B1-01 Home: the title is a switch**

| English | Español |
|---|---|
| For me | Para mí |
| Five blessings since June 2024 | Cinco bendiciones desde junio de 2024 |
| Sunday, October 4, 2026 | domingo, 4 de octubre de 2026 |
| Before the new job | Antes del nuevo trabajo |
| From Dad | De papá |
| New blessing | Nueva bendición |

**B1-02 The switch between rings**

| English | Español |
|---|---|
| For me | Para mí |
| Five blessings since June 2024 | Cinco bendiciones desde junio de 2024 |
| Sunday, October 4, 2026 | domingo, 4 de octubre de 2026 |
| Before the new job | Antes del nuevo trabajo |
| From Dad | De papá |
| New blessing | Nueva bendición |
| For Emma | Para Emma |
| Seven blessings since August 2008 | Siete bendiciones desde agosto de 2008 |
| For James | Para James |
| Four blessings since March 2013 | Cuatro bendiciones desde marzo de 2013 |
| Add someone | Agregar a alguien |

**B1-03 Emma’s sky**

| English | Español |
|---|---|
| For Emma | Para Emma |
| Seven blessings since August 2008 | Siete bendiciones desde agosto de 2008 |
| Sunday, August 16, 2026 | domingo, 16 de agosto de 2026 |
| Before leaving home | Antes de irse de casa |
| From Dad | De papá |
| New blessing | Nueva bendición |

**B1-04 Adding a child**

| English | Español |
|---|---|
| Add someone | Agregar a alguien |
| For a child without a phone of their own. Their blessings are kept here until you hand them over. | Para un hijo o una hija sin teléfono propio. Sus bendiciones se guardan aquí hasta que se las entregues. |
| Name | Nombre |
| Clara | Clara |
| Born | Nació |
| November 2, 2026 | 2 de noviembre de 2026 |
| Optional. Their ring begins on this day. | Opcional. Su anillo comienza ese día. |
| Add | Agregar |

**B1-05 A new ring, empty**

| English | Español |
|---|---|
| For Clara | Para Clara |
| No blessings yet | Todavía no hay bendiciones |
| When a blessing is recorded for Clara, a light appears here. | Cuando se grabe una bendición para Clara, una luz aparecerá aquí. |
| New blessing | Nueva bendición |

**B1-06 Recording for Emma**

| English | Español |
|---|---|
| New blessing | Nueva bendición |
| For Emma | Para Emma |
| Close | Cerrar |
| Begin | Comenzar |
| Nothing is recorded until you press. | No se graba nada hasta que lo presiones. |
| English ⌃⌄ | Español ⌃⌄ |
| Enter a past blessing | Anotar una bendición pasada |

**B1-07 Review: whose blessing**

| English | Español |
|---|---|
| Done | Listo |
| Monday, November 16, 2026 | lunes, 16 de noviembre de 2026 |
| Blessing | Bendición |
| From | De |
| Dad | Papá |
| For | Para |
| Emma | Emma |
| Whose blessing | De quién es |
| For me | Para mí |
| James | James |
| Clara | Clara |
| Passing it along | Para entregar |
| 0:00 / 0:52 | 0:00 / 0:52 |

**B1-08 Entering a past one for Emma**

| English | Español |
|---|---|
| Done | Listo |
| A name and a blessing | Nombre y bendición |
| Given | Fecha |
| August 2008 | agosto de 2008 |
| From | De |
| Dad | Papá |
| For | Para |
| Emma | Emma |
| Whose blessing | De quién es |
| For me | Para mí |
| James | James |
| Clara | Clara |
| Passing it along | Para entregar |
| Tags | Etiquetas |
| Add a tag | Agregar una etiqueta |
| + Family | + Familia |
| + Healing | + Sanación |
| + Calling | + Llamamiento |
| + Comfort | + Consuelo |
| + Work | + Trabajo |
| The words | Las palabras |

**B1-09 Emma’s sky, the ··· menu**

| English | Español |
|---|---|
| For Emma | Para Emma |
| Seven blessings since August 2008 | Siete bendiciones desde agosto de 2008 |
| Sunday, August 16, 2026 | domingo, 16 de agosto de 2026 |
| Before leaving home | Antes de irse de casa |
| From Dad | De papá |
| New blessing | Nueva bendición |
| Hand over Emma’s ring | Entregar el anillo de Emma |
| Edit name and birth date | Editar nombre y nacimiento |

**B1-10 Handing over: the parent sends**

| English | Español |
|---|---|
| For Emma | Para Emma |
| Seven blessings since August 2008 | Siete bendiciones desde agosto de 2008 |
| Sunday, August 16, 2026 | domingo, 16 de agosto de 2026 |
| Before leaving home | Antes de irse de casa |
| From Dad | De papá |
| New blessing | Nueva bendición |
| Emma’s ring | El anillo de Emma |
| Kept by | Guardadas por |
| Dad | Papá |
| Send Emma’s ring | Enviar el anillo de Emma |
| Emma can keep them in Upon Thy Head. | Emma podrá guardarlas en Upon Thy Head. |
| This sends a link. Anyone who has it can read these blessings. | Esto envía un enlace. Quien lo tenga puede leer estas bendiciones. |

**B1-11 Sent: keep a copy or delete**

| English | Español |
|---|---|
| For Emma | Para Emma |
| Seven blessings since August 2008 | Siete bendiciones desde agosto de 2008 |
| Sunday, August 16, 2026 | domingo, 16 de agosto de 2026 |
| Before leaving home | Antes de irse de casa |
| From Dad | De papá |
| New blessing | Nueva bendición |
| Sent | Enviado |
| Keep Emma’s ring on this phone, or delete it now? | ¿Guardar el anillo de Emma en este teléfono o eliminarlo ahora? |
| If you keep it, blessings added later can be sent to Emma too. | Si lo guardas, las bendiciones que agregues después también se pueden enviar a Emma. |
| Delete | Eliminar |
| Keep | Guardar |

**B1-12 Emma’s phone: the app opens**

| English | Español |
|---|---|
| Your blessings were kept for you. | Tus bendiciones se guardaron para ti. |
| Dad kept seven blessings for you, from August 2008. Read them first, then keep them. | Papá guardó siete bendiciones para ti, desde agosto de 2008. Léelas primero y luego guárdalas. |
| Continue | Continuar |

**B1-13 Emma’s phone: reading first**

| English | Español |
|---|---|
| Sunday, August 10, 2008 | domingo, 10 de agosto de 2008 |
| A name and a blessing | Nombre y bendición |
| A blessing from Dad | Una bendición de papá |
| 1 of 7 | 1 de 7 |
| Not now | Ahora no |
| Keep them | Guardarlas |

**B1-14 Emma’s phone: her sky**

| English | Español |
|---|---|
| For me | Para mí |
| Seven blessings since August 2008 | Siete bendiciones desde agosto de 2008 |
| Kept for you by Dad | Guardadas para ti por papá |
| Sunday, August 16, 2026 | domingo, 16 de agosto de 2026 |
| Before leaving home | Antes de irse de casa |
| From Dad | De papá |
| New blessing | Nueva bendición |

**B1-15 Parent, afterwards**

| English | Español |
|---|---|
| For Emma | Para Emma |
| Eight blessings since August 2008 | Ocho bendiciones desde agosto de 2008 |
| Handed to Emma on November 16 | Entregado a Emma el 16 de noviembre |
| One new · Send it | Una nueva · Enviarla |
| Thursday, December 24, 2026 | jueves, 24 de diciembre de 2026 |
| Christmas, at home | Navidad, en casa |
| From Dad | De papá |
| New blessing | Nueva bendición |

**B1-16 Two parents: the second hand-over**

| English | Español |
|---|---|
| For me | Para mí |
| Seven blessings since August 2008 | Siete bendiciones desde agosto de 2008 |
| Kept for you by Dad | Guardadas para ti por papá |
| Sunday, August 16, 2026 | domingo, 16 de agosto de 2026 |
| Before leaving home | Antes de irse de casa |
| From Dad | De papá |
| New blessing | Nueva bendición |
| Four more of your blessings | Cuatro bendiciones más para ti |
| Kept by Mom | Guardadas por mamá |
| August 2014 to May 2024 | De agosto de 2014 a mayo de 2024 |
| They join your ring by their dates. Keep them? | Se unen a tu anillo según sus fechas. ¿Guardarlas? |
| Not now | Ahora no |
| Keep them | Guardarlas |

### B2

**B2-01 Home: one sky, three rings**

| English | Español |
|---|---|
| For me | Para mí |
| Five blessings since June 2024 | Cinco bendiciones desde junio de 2024 |
| Sunday, October 4, 2026 | domingo, 4 de octubre de 2026 |
| Before the new job | Antes del nuevo trabajo |
| From Dad | De papá |
| New blessing | Nueva bendición |

**B2-02 Emma’s ring brought forward**

| English | Español |
|---|---|
| For Emma | Para Emma |
| Seven blessings since August 2008 | Siete bendiciones desde agosto de 2008 |
| Sunday, August 16, 2026 | domingo, 16 de agosto de 2026 |
| Before leaving home | Antes de irse de casa |
| From Dad | De papá |
| New blessing | Nueva bendición |

**B2-03 A child added: a new ring**

| English | Español |
|---|---|
| For me | Para mí |
| Five blessings since June 2024 | Cinco bendiciones desde junio de 2024 |
| Sunday, October 4, 2026 | domingo, 4 de octubre de 2026 |
| Before the new job | Antes del nuevo trabajo |
| From Dad | De papá |
| New blessing | Nueva bendición |

**B2-04 Review: whose blessing**

| English | Español |
|---|---|
| Done | Listo |
| Monday, November 16, 2026 | lunes, 16 de noviembre de 2026 |
| Blessing | Bendición |
| From | De |
| Dad | Papá |
| For | Para |
| Emma | Emma |
| Whose blessing | De quién es |
| For me | Para mí |
| James | James |
| Clara | Clara |
| Passing it along | Para entregar |
| 0:00 / 0:52 | 0:00 / 0:52 |

**B2-05 Handing over Emma’s ring**

| English | Español |
|---|---|
| For Emma | Para Emma |
| Seven blessings since August 2008 | Siete bendiciones desde agosto de 2008 |
| Sunday, August 16, 2026 | domingo, 16 de agosto de 2026 |
| Before leaving home | Antes de irse de casa |
| From Dad | De papá |
| New blessing | Nueva bendición |
| Emma’s ring | El anillo de Emma |
| Kept by | Guardadas por |
| Dad | Papá |
| Send Emma’s ring | Enviar el anillo de Emma |
| Emma can keep them in Upon Thy Head. | Emma podrá guardarlas en Upon Thy Head. |
| This sends a link. Anyone who has it can read these blessings. | Esto envía un enlace. Quien lo tenga puede leer estas bendiciones. |

**B2-06 Afterwards: a ring handed over**

| English | Español |
|---|---|
| For me | Para mí |
| Five blessings since June 2024 | Cinco bendiciones desde junio de 2024 |
| Sunday, October 4, 2026 | domingo, 4 de octubre de 2026 |
| Before the new job | Antes del nuevo trabajo |
| From Dad | De papá |
| New blessing | Nueva bendición |

### B3

**B3-01 Home: unchanged**

| English | Español |
|---|---|
| For me | Para mí |
| Five blessings since June 2024 | Cinco bendiciones desde junio de 2024 |
| Sunday, October 4, 2026 | domingo, 4 de octubre de 2026 |
| Before the new job | Antes del nuevo trabajo |
| From Dad | De papá |
| New blessing | Nueva bendición |

**B3-02 To pass along, by child**

| English | Español |
|---|---|
| To pass along | Para entregar |
| Blessings recorded for someone else. They have no light in your sky. | Bendiciones grabadas para otra persona. No tienen luz en tu cielo. |
| Emma | Emma |
| Seven blessings · not sent yet | Siete bendiciones · aún no enviadas |
| Send all | Enviar todas |
| Before leaving home | Antes de irse de casa |
| Aug 16, 2026 | 16 ago 2026 |
| Before high school | Antes de la preparatoria |
| Aug 21, 2022 | 21 ago 2022 |
| Five more | Cinco más |
| James | James |
| Four blessings · not sent yet | Cuatro bendiciones · aún no enviadas |
| Before the move | Antes de la mudanza |
| Jun 3, 2025 | 3 jun 2025 |
| Three more | Tres más |
| Clara | Clara |
| One blessing · not sent yet | Una bendición · aún no enviada |
| A name and a blessing | Nombre y bendición |
| Nov 1, 2026 | 1 nov 2026 |

**B3-03 Review: passing it along**

| English | Español |
|---|---|
| Done | Listo |
| Monday, November 16, 2026 | lunes, 16 de noviembre de 2026 |
| Blessing | Bendición |
| From | De |
| Dad | Papá |
| For | Para |
| Emma | Emma |
| Whose blessing | De quién es |
| For me | Para mí |
| Passing it along | Para entregar |
| 0:00 / 0:52 | 0:00 / 0:52 |

**B3-04 Sending all of Emma’s**

| English | Español |
|---|---|
| To pass along | Para entregar |
| Blessings recorded for someone else. They have no light in your sky. | Bendiciones grabadas para otra persona. No tienen luz en tu cielo. |
| Emma | Emma |
| Seven blessings · not sent yet | Siete bendiciones · aún no enviadas |
| Send all | Enviar todas |
| Before leaving home | Antes de irse de casa |
| Aug 16, 2026 | 16 ago 2026 |
| Before high school | Antes de la preparatoria |
| Aug 21, 2022 | 21 ago 2022 |
| Five more | Cinco más |
| James | James |
| Four blessings · not sent yet | Cuatro bendiciones · aún no enviadas |
| Before the move | Antes de la mudanza |
| Jun 3, 2025 | 3 jun 2025 |
| Three more | Tres más |
| Clara | Clara |
| One blessing · not sent yet | Una bendición · aún no enviada |
| A name and a blessing | Nombre y bendición |
| Nov 1, 2026 | 1 nov 2026 |
| Emma’s blessings | Las bendiciones de Emma |
| Seven blessings since August 2008 | Siete bendiciones desde agosto de 2008 |
| Kept by | Guardadas por |
| Dad | Papá |
| Send all seven to Emma | Enviar las siete a Emma |
| Emma can keep them in Upon Thy Head. | Emma podrá guardarlas en Upon Thy Head. |
| This sends a link. Anyone who has it can read these blessings. | Esto envía un enlace. Quien lo tenga puede leer estas bendiciones. |

**B3-05 Sent: keep or delete**

| English | Español |
|---|---|
| To pass along | Para entregar |
| Blessings recorded for someone else. They have no light in your sky. | Bendiciones grabadas para otra persona. No tienen luz en tu cielo. |
| Emma | Emma |
| Seven blessings · not sent yet | Siete bendiciones · aún no enviadas |
| Send all | Enviar todas |
| Before leaving home | Antes de irse de casa |
| Aug 16, 2026 | 16 ago 2026 |
| Before high school | Antes de la preparatoria |
| Aug 21, 2022 | 21 ago 2022 |
| Five more | Cinco más |
| James | James |
| Four blessings · not sent yet | Cuatro bendiciones · aún no enviadas |
| Before the move | Antes de la mudanza |
| Jun 3, 2025 | 3 jun 2025 |
| Three more | Tres más |
| Clara | Clara |
| One blessing · not sent yet | Una bendición · aún no enviada |
| A name and a blessing | Nombre y bendición |
| Nov 1, 2026 | 1 nov 2026 |
| Sent | Enviado |
| Keep these seven on this phone, or delete them now? | ¿Guardar estas siete en este teléfono o eliminarlas ahora? |
| Each one also stays in this list as sent. | Cada una sigue en esta lista como enviada. |
| Delete | Eliminar |
| Keep | Guardar |

**B3-06 Afterwards**

| English | Español |
|---|---|
| To pass along | Para entregar |
| Blessings recorded for someone else. They have no light in your sky. | Bendiciones grabadas para otra persona. No tienen luz en tu cielo. |
| Emma | Emma |
| Seven blessings · sent November 16 | Siete bendiciones · enviadas el 16 de noviembre |
| James | James |
| Four blessings · not sent yet | Cuatro bendiciones · aún no enviadas |
| Send all | Enviar todas |
| Before the move | Antes de la mudanza |
| Jun 3, 2025 | 3 jun 2025 |
| Three more | Tres más |
| Clara | Clara |
| One blessing · not sent yet | Una bendición · aún no enviada |
| A name and a blessing | Nombre y bendición |
| Nov 1, 2026 | 1 nov 2026 |

### The blessing texts used in the draft

The words below are placeholders, written for this draft.

**Before college (August 1998, from Dad).** "Daniel, by the authority of the Melchizedek Priesthood which I hold, I lay my hands upon your head and give you a father’s blessing as you leave home for the first time. …" The Spanish is "Daniel, por la autoridad del Sacerdocio de Melquisedec que poseo, pongo mis manos sobre tu cabeza y te doy una bendición de padre al salir de casa por primera vez. …" Both are given in full in `src/app.js`, under `PAST`.

**A name and a blessing (August 10, 2008).** "Emma Grace, holding you in our arms, by the authority of the Melchizedek Priesthood, we give you a name and a blessing. …" The Spanish is "Emma Grace, teniéndote en nuestros brazos, …" Both are under `BABY`.

**The recording being reviewed.** "Emma I lay my hands upon your head as you go back to school after this visit home …" The Spanish is "Emma pongo mis manos sobre tu cabeza ahora que regresas a la escuela …" Both are under `SPOKEN`.
