# Upon Thy Head: the website

One landing page for uponthyhead.app. Next.js (App Router, TypeScript), on Vercel.

**Live since 2026-11-17** at https://uponthyhead.app (and `www.`): Vercel project `upon-thy-head` on the Summit Studio team, connected to the GitHub repository with Root Directory `website`: a push to `master` that changes anything in `website/` deploys to production, and a push that does not is skipped. `www.` redirects to the bare address. DNS is at Cloudflare: two unproxied CNAME records to Vercel. The app is not in a store yet, so the button reads "Coming soon to iPhone and Android" (`download` in `app/content.ts`). **The link service is off:** no storage is set up, so it answers 503 and keeps nothing. Do not add storage until the list under "Before the link goes live" in `docs/decisions-and-parked-ideas.md` is done.

## Run it

```bash
pnpm install
pnpm dev                    # http://localhost:3000
pnpm build && pnpm start    # the production build
```

## Where things are

| What | Where |
|------|-------|
| Every word on the page | `app/content.ts` (one object, `en`; Spanish follows as a second object of the same shape) |
| The page | `app/page.tsx` |
| Colours, type, layout | `app/globals.css` (Lamplight, copied from `app/lib/theme.dart`) |
| Picture and icon slots | `app/slots.tsx` |
| How the words arrive (motion) | `app/reveal.tsx` |
| Newsreader font files | `app/fonts/` (served from this site) |
| The living sky (stars, ring, movement) | `app/sky.tsx`; pictures and star files in `public/sky/`, made by `scripts/make-sky.mjs` |

## Pictures of the app

Each slot shows a placeholder until its file exists. Put the file in `public/shots/` and rebuild; the
picture takes the placeholder's place and nothing else moves.

| Slot on the page | File |
|------------------|------|
| The sky | `public/shots/sky.png` |
| Recording | `public/shots/recording.png` |
| The changes | `public/shots/changes.png` |
| Reading a blessing | `public/shots/reading.png` |
| Sharing | `public/shots/sharing.png` |

Use a plain full-screen iPhone screenshot with no device frame (for example 1206 × 2622). The page
rounds the corners itself. `.jpg`, `.webp` and `.avif` also work. The words read aloud for each
picture are in `app/content.ts` under `shots`.

## The app icon and favicon

All three are made from `design/icon/final/icon-1024.png` (the original is not touched). To replace
the icon, replace these files:

- On the page: `public/app-icon.png` (the square master; the page rounds the corners).
- Browser tab: `app/icon.png` (512 px, corners rounded) and `app/favicon.ico` (48, 32, 16 px).
- Home screen: `app/apple-icon.png` (180 × 180, square; iOS rounds it).

## Motion

The words rise and come into focus as the page opens and as each section scrolls into view. The
primitives are Animate UI's `Effect`, `SplittingText` and `Button` (`@animate-ui/react`, on `motion`),
timed to the "Texts reveal" recipe from transitions.dev and slowed for this page. The timings are
the constants at the top of `app/reveal.tsx`. With Reduce Motion on, the travel is dropped and only
a fade is kept. With JavaScript off, a `<noscript>` rule in `app/layout.tsx` shows everything at once.

## Shared blessings

A link made by the app, `https://uponthyhead.app/b/<id>#<key>`, opens at `/b/<id>`. The contract the
app builds to is `PROTOCOL.md`; `protocol-vectors.json` has the test vectors.

| What | Where |
|------|-------|
| The format, the page's script, its words (English and Spanish), its styles | `public/shared/` (`format.js`, `page.js`, `words.js`, `page.css`) |
| **The switch for the App Store and Google Play buttons** | `public/shared/stores.js` |
| The page's document and its security headers | `app/b/[id]/route.ts` |
| The service: create, read, stop, clean-up, limits | `lib/links/service.ts`, called from `app/api/b/` and `app/api/sweep/` |
| Storage, behind one interface | `lib/links/store.ts` |
| The files that send a link into the app | `app/.well-known/` |

Run it on this machine, with copies kept in the folder `.data/links` (git-ignored) and no account:

```bash
pnpm dev                                          # uses .data/links by itself
LINKS_LOCAL_DIR=.data/links pnpm start -p 4319    # the production build needs to be told
node tests/phone.mjs http://localhost:4319        # plays the phone: prints a link to open
```

Test it:

```bash
pnpm test                                         # the format against the vectors; the service and stores
LINKS_LOCAL_DIR=.data/links node tests/browser.mjs http://localhost:4319   # Chromium and WebKit, with the site running
```

The browser test makes seven links, and one network may make ten in ten minutes, so restart the site
between runs.

On Vercel (nothing is set up yet): add Upstash Redis from the Marketplace, which sets
`UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` (the older `KV_REST_API_*` names are read
too); set `CRON_SECRET` so the daily clean-up in `vercel.json` can run; and add a Firewall rate-limit
rule for `POST /api/b`. Without storage set up, the service answers 503 and keeps nothing.

`/b` with no id returns 404.

## Privacy

No analytics, no cookies, no third-party scripts, no fonts or images from other servers. Keep it so.
The one thing the site keeps is the locked copy of a shared blessing, for 30 days, which it cannot read.

## The sky

The sky at the top and at the close is drawn live. The Milky Way is a picture; over it, every star
down to magnitude 9.6 (about 25,000 at the top) is drawn in WebGL from the real catalogue, through
the same camera that made the picture. So the stars stay sharp on any screen, and each sits at its
own depth: bright stars are near and travel far as the page scrolls, faint ones barely move, and
the Milky Way moves least. On a computer the layers also shift slightly with the pointer.

On load the stars come forward and the arc of lights draws itself. Then the top of the page is held
for about two and a half screens of scrolling while the arc draws away into a whole halo of lights
that turns, with two lines of words beneath it. At the close a smaller halo turns above the icon.

To tune it, in `app/sky.tsx`: the `LIGHTS` list is the lights on the ring; the hero and close blocks
of `draw` hold the amounts (`travel` is the star parallax, `turned` the halo's rotation, `lean` its
tilt). The scene's words are `journey` in `app/content.ts` and its length is `.journey[data-live]`
in `app/globals.css`.

- Reduce Motion: the sky is drawn once and holds still, and the page is not held.
- JavaScript off, or no WebGL: a finished still of the same sky is shown.
- Elsewhere on the page, pictures drift and the section rings draw themselves with the scroll. That
  part is plain CSS (`animation-timeline`) and simply does not run in browsers without it.

`node scripts/make-sky.mjs` rebuilds `public/sky/` and `app/sky-views.json` from the app's own star
catalogue and Milky Way map in `../design/prototype/src/` (it only reads from there). Stars: HYG
Database v4.1 by David Nash, CC BY-SA 4.0, which asks for the credit shown in the footer. Milky Way:
NASA/Goddard Space Flight Center Scientific Visualization Studio, public domain.
