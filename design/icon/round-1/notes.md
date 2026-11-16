# Upon Thy Head — icon concepts, round 1

Eight concepts, each in three stages. A is an atmospheric image; B removes detail; C is the flat mark. All 24 artworks were made separately with the built-in image generation tool. No SVG, vector paths, canvas, HTML, CSS, or programmatically drawn artwork was used. No subagents were used.

The two additional concepts are 7, **Kept light** (something precious held safely for life), and 8, **Folded light** (a private written keepsake holding a light). They test preservation more directly than a generic person or crown.

## Preparation and delivery

I inspected only prototype pictures: `00-shell.png`, `01-begin.png`, and `04-reading.png`. The home screen's great ring, small personal lights, darkness, and quiet reading experience guided the work. The app was not edited and nothing was committed.

Every delivered artwork is a full-bleed 1024 × 1024 PNG. The generated raster was resized and placed on black to keep the visible subject within the middle 70 percent. A and B were exported in grayscale. C was exported as a nondithered 1-bit PNG, removing the generator's near-white variation and edge antialiasing: its only pixel values are pure white and pure black. These are export operations on generated images, not redrawn marks. Pillow assembled and labelled the contact sheet; its only drawn shapes are the rounded clipping masks for the small previews. Original artwork files have square corners. Small sheet previews use ordinary resampling, so preview edges can have antialiasing.

`sheet.png` has one row per concept, A/B/C at 280 pixels, followed by C at actual 120, 60, and 29 pixels inside rounded-square masks. View the sheet at 100% for a true small-size judgment. Final prompts below are verbatim, including the final revisions. Ring C used three takes; head C and crown B used two; the other images used one take. Only the selected take of each is in this folder.

## Ranking

1. **1 — A light on the ring.** The most specific connection to the actual home screen; one remembered blessing on a life-sized sky, with a sturdy flat arc.
2. **4 — Lamplight.** The clearest object at small size and the most natural bridge to the later Lamplight palette; quiet rather than decorative.
3. **7 — Kept light.** A compact, protective image of lifelong keeping; stronger as a simple mark than the literal figures, although it can suggest a smile or bowl.
4. **2 — Hands upon a head.** Most faithful to the name and the ordinance; the rich image is tender, but the small mark loses the character of the touch.
5. **5 — The sky and the written word.** Connects light with a written record very clearly, though it resembles a reading or scripture app more than a personal sky.
6. **3 — A light above a head.** Clean and calm, but the simplified person becomes a generic account symbol rather than a distinctive blessing record.
7. **8 — Folded light.** Communicates a private keepsake and survives reduction, but the page-and-dot resembles a file or media document.
8. **6 — A crown of lights.** Clean geometry, but the four discs readily become a paw print; that association works against the intended reverence.

My shortlist for the owner's next round is **1, 4, and 7**. Keep 2 available if the literal act matters more than small-size abstraction. Colour alone will not repair a semantic ambiguity.

## Small-size assessment

- **1 — Ring:** Pass at 120, 60, and 29. The final C revision thickened the arc; the dot and arc stay separate in meaning without glow. The luminous A should not be used at 29.
- **2 — Hands:** Clear at 120, serviceable at 60, **fails the tender-touch reading at 29**. The finger gaps compress and the hands can become a moustache-like shape over a disc.
- **3 — Above:** Shapes survive all sizes, but **fails distinctiveness**, reading as a generic person with a dot. This is a meaning problem, not disappearance of pixels.
- **4 — Lamp:** Pass at 120, 60, and 29; the flame remains separate. At 29 the lamp loses its historical material, but bowl, spout and flame survive.
- **5 — Word:** Pass for basic book-and-light recognition at 29; the central fold remains visible, though it does not communicate a personal blessing on its own.
- **6 — Crown:** Dots survive, but **fails the intended reading at 60 and 29** because it resembles a paw print, rather than a ring bent over a person.
- **7 — Kept:** Pass for the bowl-and-light silhouette at all sizes; **qualified semantic pass at 29**, where smile or person-in-a-bowl readings are possible.
- **8 — Folded:** Pass for page, clipped corner and enclosed light at all sizes; the folded-paper depth deliberately disappears in C. Too generic to shortlist.

These are my visual judgments from the actual-size previews, not user-testing results. All requested deliverables are present; the limitations above concern the concepts' meaning at small size.

## Final image prompts

### 1-ring-A.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: A light on the ring. Subject: A shallow sweeping arc of a great celestial ring, ends both contained inside the square, one prominent circular light sitting on the arc slightly right of center. No star-shaped cross. Only one light. Step A: Atmospheric luminous arc delicately lit in darkness, a softly glowing white pearl of light, restrained photographic depth and fine grain.
```

### 1-ring-B.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: A light on the ring. Subject: A shallow sweeping arc of a great celestial ring, ends both contained inside the square, one prominent circular light sitting on the arc slightly right of center. No star-shaped cross. Only one light. Step B: Reduce to one clean moderately thick white shallow arc and a solid luminous white circle on it; almost no glow, no grain.
```

### 1-ring-C.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. A deliberately bold two-dimensional emblem for a 29-pixel display: one thick white shallow convex-upward celestial arc spanning the central TWO THIRDS of the square (about 680 pixels wide), and one solid white circle of diameter 110 pixels resting on and slightly overlapping the arc, offset to the right of center. The arc must be a THICK SOLID BAND 60 pixels thick, not a hairline or outline. It should stay visibly thick even as a 29px thumbnail. Arc peaks near the vertical center. Circle touches arc; no floating gap. Only those two flat white shapes on pure black. Strict bitonal, no greys, shading, gradients, glow, texture or other details. Generous margin on all sides. No cross or star rays.
```

### 2-hands-A.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: Hands upon a head. Subject: Two human hands resting gently from opposite upper sides onto the crown of a plain rounded head seen from above/back. Palms face downward, fingers lie tenderly on the top of the head, never gripping. No face or facial features. Hands and head form a single quiet emblem. Step A: Sculptural monochrome chiaroscuro, beautiful anatomically plausible hands and a plain softly lit head form, fine soft grain, tender touch.
```

### 2-hands-B.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: Hands upon a head. Subject: Two human hands resting gently from opposite upper sides onto the crown of a plain rounded head seen from above/back. Palms face downward, fingers lie tenderly on the top of the head, never gripping. No face or facial features. Hands and head form a single quiet emblem. Step B: Reduce to large flat silhouettes of two downward resting hands above a rounded head. Only essential broad finger separations. No realistic anatomy detail or shading.
```

### 2-hands-C.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: Hands upon a head. Subject: Two human hands resting gently from opposite upper sides onto the crown of a plain rounded head seen from above/back. Palms face downward, fingers lie tenderly on the top of the head, never gripping. No face or facial features. Hands and head form a single quiet emblem. Step C: Flat bold white silhouettes of two hands lowered horizontally inward onto a simple white head disc, separate broad black gaps so the head and two hands remain legible. No fine fingers, no outlines. Strict two-dimensional binary white #FFFFFF and black #000000 only. No grey pixels, gradients, shading, texture, glow, thin strokes or fine outlines. Read clearly at 29 pixels wide.
```

### 3-above-A.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: A light above a head. Subject: A plain anonymous head and broad shoulders viewed from behind, and one small round light directly above the head with a clear black gap. No face, no hair detail, no halo, no rays. Step A: Quiet sculpture-like back of head and shoulders softly lit by a hovering round pearl of light, rich black-and-white tonal depth.
```

### 3-above-B.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: A light above a head. Subject: A plain anonymous head and broad shoulders viewed from behind, and one small round light directly above the head with a clear black gap. No face, no hair detail, no halo, no rays. Step B: Reduce to a solid head-and-shoulders silhouette with one simple round light above it, little or no shading.
```

### 3-above-C.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: a light above a head. Step C, flat: exactly three bold white shapes: one circular head disc; a separate low broad shoulder mound directly below with a broad black gap; one smaller circular light directly above the head separated by a wide black gap. Seen from behind, absolutely no ears, neck detail, hair, face, realism, highlights or outlines. The lower shoulder mound is a broad shallow solid arch with flat bottom. Total composition occupies only center 60 percent of canvas. Much simpler than a conventional human profile silhouette. Binary pure black #000000 and pure white #FFFFFF only, no grey, gradients, glow, shading or texture. Raster icon mark readable at 29px.
```

### 4-lamp-A.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: Lamplight. Subject: One small ancient shallow oil lamp, side view, simple rounded bowl and short right-facing spout, a single upright teardrop flame above the spout, no handle, no ornament or pedestal. Step A: Intimate monochrome still life of an old clay oil lamp emerging from black, subtle clay texture and luminous flame with soft light.
```

### 4-lamp-B.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: Lamplight. Subject: One small ancient shallow oil lamp, side view, simple rounded bowl and short right-facing spout, a single upright teardrop flame above the spout, no handle, no ornament or pedestal. Step B: Reduce to a simple white bowl-and-spout silhouette with a single white flame, almost no shading, no texture.
```

### 4-lamp-C.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: Lamplight. Subject: One small ancient shallow oil lamp, side view, simple rounded bowl and short right-facing spout, a single upright teardrop flame above the spout, no handle, no ornament or pedestal. Step C: Only flat white solid shallow bowl with a short raised spout and one detached solid white teardrop flame. Bold primitive masses, no outlines, no interior detail. Strict two-dimensional binary white #FFFFFF and black #000000 only. No grey pixels, gradients, shading, texture, glow, thin strokes or fine outlines. Read clearly at 29 pixels wide.
```

### 5-word-A.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: The sky and the written word. Subject: A single light above a small open page/book. The open page is plain, only its two broad leaves and central fold; no actual writing, glyphs or letters. A quiet unified emblem. Step A: Rich black-and-white close still life, an open unmarked page gently illuminated by a single hovering white pearl of light, subtle paper texture and depth.
```

### 5-word-B.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: The sky and the written word. Subject: A single light above a small open page/book. The open page is plain, only its two broad leaves and central fold; no actual writing, glyphs or letters. A quiet unified emblem. Step B: Reduce to two broad white page shapes opened gently upward and a single round light above the center, one black central fold, no shading.
```

### 5-word-C.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: The sky and the written word. Subject: A single light above a small open page/book. The open page is plain, only its two broad leaves and central fold; no actual writing, glyphs or letters. A quiet unified emblem. Step C: Two chunky solid white open-book leaves divided by a broad black central fold, one solid white circular light above with a clear gap. No page outlines, no writing lines. Strict two-dimensional binary white #FFFFFF and black #000000 only. No grey pixels, gradients, shading, texture, glow, thin strokes or fine outlines. Read clearly at 29 pixels wide.
```

### 6-crown-A.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: A crown of lights. Subject: One small plain circular head disc with an open shallow arch of exactly three round lights above it. Nothing encircles the head. Abstract geometry, not a saint or halo; no shoulders or facial detail. Step A: One softly illuminated spherical head form below three softly glowing small lights arranged as a shallow overhead arc, quiet photographic depth in black.
```

### 6-crown-B.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: crown of lights. Step B, simplified but not yet fully flat. A plain small head sphere lit from above, no face or features. Above it, three simple round white lights sitting on one thin OPEN shallow arch connecting those three lights. The arch is entirely ABOVE the head with a clear gap, not encircling it, not a halo. Restrained very soft grey modelling on the head and slight glow only around the three lights. No background stars or details. Few simple shapes, centered composition, all inside central 60 percent of black square. Step C will remove the connecting arch and all shading, leaving four flat discs; this Step B must retain the connecting arch and subtle spherical shading.
```

### 6-crown-C.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: A crown of lights. Subject: One small plain circular head disc with an open shallow arch of exactly three round lights above it. Nothing encircles the head. Abstract geometry, not a saint or halo; no shoulders or facial detail. Step C: Exactly four flat solid white discs: a larger head disc below and three smaller discs in a shallow arch above, clear broad black gaps. No connecting arc, no halo. Strict two-dimensional binary white #FFFFFF and black #000000 only. No grey pixels, gradients, shading, texture, glow, thin strokes or fine outlines. Read clearly at 29 pixels wide.
```

### 7-kept-A.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: Kept light. Subject: A single round light sheltered just inside a low open bowl-shaped vessel. A quiet broad upward-curving cradle holding one light, no hands, no flame, no extra objects. Step A: Tactile pale stone vessel shaped as a low open bowl, a glowing white pearl held in its center, beautiful soft chiaroscuro, subtle grain, private and still.
```

### 7-kept-B.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: Kept light. Subject: A single round light sheltered just inside a low open bowl-shaped vessel. A quiet broad upward-curving cradle holding one light, no hands, no flame, no extra objects. Step B: Reduce to one broad white crescent-shaped bowl with a round white light nestled above its inner hollow, clear dark gap, no texture.
```

### 7-kept-C.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: Kept light. Subject: A single round light sheltered just inside a low open bowl-shaped vessel. A quiet broad upward-curving cradle holding one light, no hands, no flame, no extra objects. Step C: One bold flat white upward-facing crescent bowl, wide with thick base and short low tips, plus one solid white disc nestled in its hollow with a broad black separation. Avoid eye appearance: bowl much wider than disc, no upper arch. Strict two-dimensional binary white #FFFFFF and black #000000 only. No grey pixels, gradients, shading, texture, glow, thin strokes or fine outlines. Read clearly at 29 pixels wide.
```

### 8-folded-A.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: Folded light. Subject: A single upright plain paper leaf, with its upper right corner folded down, and one round white light held in the upper center of the page as a black circular cutout surrounding a white dot. No letters or writing. An intimate keepsake. Step A: One softly lit upright paper leaf emerging from black, visible folded corner and delicate paper texture, one round luminous point held on the page, sculptural monochrome.
```

### 8-folded-B.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: Folded light. Subject: A single upright plain paper leaf, with its upper right corner folded down, and one round white light held in the upper center of the page as a black circular cutout surrounding a white dot. No letters or writing. An intimate keepsake. Step B: Reduce to a plain upright white page silhouette with one simple folded corner and one round light isolated by a broad black circular opening, no shading.
```

### 8-folded-C.png

```text
Use case: logo-brand. Create one finished raster artwork, exactly 1024 x 1024, square full bleed pure black ground. Upon Thy Head is a private, reverent lifelong record of blessings given by laying on hands; visual language is a quiet night sky. White/light on black, monochrome only. One centered subject entirely inside the central 70 percent, generous empty black margin. No text, letters, numbers, monograms, frame, rounded corners, mockup, drop shadow, watermark. No faces, crosses, praying hands, saints, halos, angels, statue, temple/church building, dove, official religious symbol, or recognizable existing app logo. Concept: Folded light. Subject: A single upright plain paper leaf, with its upper right corner folded down, and one round white light held in the upper center of the page as a black circular cutout surrounding a white dot. No letters or writing. An intimate keepsake. Step C: Only a bold flat white upright page silhouette with a clipped upper right corner, one broad black circle in the upper middle containing a solid white disc. No fold line, no writing, no thin strokes. Strict two-dimensional binary white #FFFFFF and black #000000 only. No grey pixels, gradients, shading, texture, glow, thin strokes or fine outlines. Read clearly at 29 pixels wide.
```

