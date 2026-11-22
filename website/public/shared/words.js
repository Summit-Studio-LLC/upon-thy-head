// Every word on the shared-blessing page, in English and Spanish. The wording follows
// design/share/notes.md and the app's own strings (app/lib/strings.dart).

const en = {
  lang: "en",
  locale: "en-US",
  brand: "Upon Thy Head",
  pageTitle: "A blessing",
  opening: "Opening the blessing…",
  sharedUntil: (day) => `Shared with you · until ${day}`,
  untitled: "Blessing",
  blessingFrom: (name) => `A blessing from ${name}`,
  aBlessing: "A blessing",
  forName: (name) => `For ${name}`,
  asSpoken: "The words as they were spoken.",
  entered: "Entered from a written copy, not recorded.",
  polishedFrom: (n) => `Polished from the spoken words, with ${n} ${n === 1 ? "small change" : "small changes"}.`,
  unlockedHere: "This page unlocked the blessing here, on this device. Our server keeps only a locked copy and cannot read it.",
  keepButton: "Keep it in Upon Thy Head",
  keepNote: "Get the app, then open this link again.",
  comingTitle: "Upon Thy Head is on iPhone and iPad, and is coming to Android.",
  comingNote: (day) => `Until then, this link opens here until ${day}.`,
  gone: { title: "This link has stopped working.", body: "Links last 30 days, or less if the sender stops one. Ask them to send it again." },
  key: { title: "This link is not complete.", body: "The last part of the link is the key that unlocks the blessing, and it is missing or was changed. Ask the person who sent it to share it again." },
  newer: { title: "This blessing was made with a newer version of Upon Thy Head.", body: "This page cannot open it yet. Please try again later." },
  unreadable: { title: "This blessing could not be read.", body: "Ask the person who sent it to share it again." },
  offline: { title: "The blessing could not be fetched.", body: "Check your connection, then try again." },
  busy: { title: "Please wait a moment.", body: "This link has been opened many times in a short while. Try again in a minute." },
  again: "Try again",
  noScript: {
    title: "This page needs JavaScript to unlock the blessing.",
    body: "The blessing is kept locked on our server, and the key is in the link itself, which the server never sees. Unlocking it has to happen here in your browser. Turn JavaScript on for this page, then load it again.",
  },
  notOfficial: "Upon Thy Head is not an official app of The Church of Jesus Christ of Latter-day Saints.",
  ringTitle: "Your blessings were kept for you.",
  ringKeptBy: (name, n) => `${name} kept ${n === 1 ? "one blessing" : `${n} blessings`} for you. Here they are, oldest first.`,
  ringCount: (n) => `${n === 1 ? "One blessing was" : `${n} blessings were`} kept for you. Here they are, oldest first.`,
  ringKeep: "You can keep them in Upon Thy Head, where they join your own ring by their dates.",
  ringKeepButton: "Keep them in Upon Thy Head",
  unlockedHereRing: "This page unlocked these blessings here, on this device. Our server keeps only a locked copy and cannot read it.",
};

const es = {
  lang: "es",
  locale: "es",
  brand: "Upon Thy Head",
  pageTitle: "Una bendición",
  opening: "Abriendo la bendición…",
  sharedUntil: (day) => `Compartida contigo · hasta el ${day}`,
  untitled: "Bendición",
  blessingFrom: (name) => `Una bendición de ${name}`,
  aBlessing: "Una bendición",
  forName: (name) => `Para ${name}`,
  asSpoken: "Las palabras tal como se dijeron.",
  entered: "Anotada de una copia escrita, no grabada.",
  polishedFrom: (n) => `Pulidas a partir de las palabras dichas, con ${n} ${n === 1 ? "pequeño cambio" : "pequeños cambios"}.`,
  unlockedHere: "Esta página abrió la bendición aquí, en este dispositivo. Nuestro servidor guarda solo una copia cerrada y no puede leerla.",
  keepButton: "Guardarla en Upon Thy Head",
  keepNote: "Descarga la app y vuelve a abrir este enlace.",
  comingTitle: "Upon Thy Head ya está en iPhone y iPad, y llegará pronto a Android.",
  comingNote: (day) => `Mientras tanto, este enlace se abre aquí hasta el ${day}.`,
  gone: { title: "Este enlace dejó de funcionar.", body: "Los enlaces duran 30 días, o menos si quien lo envió lo detiene. Pídele que lo vuelva a enviar." },
  key: { title: "Este enlace no está completo.", body: "La última parte del enlace es la llave que abre la bendición, y falta o fue cambiada. Pídele a quien lo envió que lo comparta de nuevo." },
  newer: { title: "Esta bendición se creó con una versión más nueva de Upon Thy Head.", body: "Esta página todavía no puede abrirla. Inténtalo de nuevo más tarde." },
  unreadable: { title: "No se pudo leer esta bendición.", body: "Pídele a quien la envió que la comparta de nuevo." },
  offline: { title: "No se pudo obtener la bendición.", body: "Revisa tu conexión e inténtalo de nuevo." },
  busy: { title: "Espera un momento.", body: "Este enlace se abrió muchas veces en poco tiempo. Inténtalo de nuevo en un minuto." },
  again: "Intentar de nuevo",
  noScript: {
    title: "Esta página necesita JavaScript para abrir la bendición.",
    body: "La bendición se guarda cerrada en nuestro servidor, y la llave está en el propio enlace, que el servidor nunca ve. Abrirla tiene que ocurrir aquí, en tu navegador. Activa JavaScript para esta página y vuelve a cargarla.",
  },
  notOfficial: "Upon Thy Head no es una aplicación oficial de La Iglesia de Jesucristo de los Santos de los Últimos Días.",
  ringTitle: "Tus bendiciones se guardaron para ti.",
  ringKeptBy: (name, n) => `${name} guardó ${n === 1 ? "una bendición" : `${n} bendiciones`} para ti. Aquí están, de la más antigua a la más reciente.`,
  ringCount: (n) => `${n === 1 ? "Se guardó una bendición" : `Se guardaron ${n} bendiciones`} para ti. Aquí están, de la más antigua a la más reciente.`,
  ringKeep: "Puedes guardarlas en Upon Thy Head, donde se unen a tu propio anillo según sus fechas.",
  ringKeepButton: "Guardarlas en Upon Thy Head",
  unlockedHereRing: "Esta página abrió estas bendiciones aquí, en este dispositivo. Nuestro servidor guarda solo una copia cerrada y no puede leerla.",
};

export const WORDS = { en, es };

/** The page's words for a list of preferred languages ("es-MX", "en"...): Spanish if it comes first. */
export function wordsFor(languages) {
  for (const l of languages) {
    const two = String(l).trim().slice(0, 2).toLowerCase();
    if (two === "es") return es;
    if (two === "en") return en;
  }
  return en;
}
