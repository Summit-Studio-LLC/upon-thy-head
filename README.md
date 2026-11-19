# Upon Thy Head

A free app for iPhone, iPad and Android that turns a priesthood blessing into a written record, kept on your own device. Website: https://uponthyhead.app

- **Record a blessing.** The phone listens while the blessing is given and writes the words on the device. Nothing is sent anywhere.
- **Or enter a past one.** Type or paste a blessing you already have written down, with the date it was given, even if you only know the year.
- **A night sky for a home screen.** Each blessing is a light on a ring across a real sky, placed by its date.
- **Keep blessings for your family.** A ring for each family member, which can later be handed to their own phone.
- **Share by link, file, text or PDF.** A shared link holds only a locked copy; the key travels in the link itself and never reaches the server.
- **No account, no ads.** English and Spanish.

The app is in testing and not yet in the stores.

## What is in this repository

| Folder | What it holds |
|---|---|
| `app/` | The app, written in Flutter, with native Swift and Kotlin for recording, speech, sharing and the lock. See `app/README.md`. |
| `website/` | The landing page and the small service behind shared links (Next.js on Vercel). See `website/README.md` and `website/PROTOCOL.md`. |
| `docs/` | The decisions made along the way, the blessing file format, and the Spanish wording notes. |
| `design/` | Design explorations, prototypes and icon rounds. |

## Run it

```bash
# the app
cd app
flutter pub get
flutter run            # on a simulator, emulator or phone

# the website
cd website
pnpm install
pnpm dev               # http://localhost:3000
```

Made by Summit Studio.
