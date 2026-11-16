// The receiver's page. It fetches the locked copy, opens it here with the key from the part of the
// address after "#", and shows the blessing.
//
// The key never leaves this page: the only request made is for /api/b/<id>, the fragment is never
// put in a request, a log, storage or the page's title, and the address is left exactly as it came.

import { ID_PATTERN, LinkError, keptChanges, keyFromFragment, open, paragraphs, polished, readRecord } from "./format.js";
import { STORES } from "./stores.js";
import { wordsFor } from "./words.js";

const w = wordsFor([document.documentElement.lang, ...(navigator.languages ?? [])]);
const main = document.getElementById("main");
const keep = document.getElementById("keep");

const el = (tag, className, text) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};

function show(state, nodes) {
  document.body.dataset.state = state;
  main.replaceChildren(...nodes);
}

function message(state, { title, body }, retry = false) {
  const nodes = [el("h1", "message-title", title), el("p", "message-body", body)];
  if (retry) {
    const again = el("button", "again", w.again);
    again.type = "button";
    again.addEventListener("click", () => location.reload());
    nodes.push(again);
  }
  keep.hidden = true;
  const box = el("div", "message");
  box.append(...nodes);
  show(state, [box]);
}

const day = (date, timeZone) => new Intl.DateTimeFormat(w.locale, { month: "long", day: "numeric", timeZone }).format(date);
const longDate = (date) => new Intl.DateTimeFormat(w.locale, { weekday: "long", year: "numeric", month: "long", day: "numeric", timeZone: "UTC" }).format(date);

function showBlessing(record, expires) {
  const until = expires ? day(expires) : "";
  // the date as it was where the blessing was given
  const given = longDate(new Date(record.given.getTime() + record.offset * 60000));
  const article = el("article", "blessing");
  if (record.language) article.lang = record.language;
  const head = el("header", "blessing-head");
  if (until) head.append(Object.assign(el("p", "shared", w.sharedUntil(until)), { lang: w.lang }));
  head.append(el("h1", "title", record.title || w.untitled));
  head.append(Object.assign(el("p", "from", record.from ? w.blessingFrom(record.from) : w.aBlessing), { lang: w.lang }));
  head.append(Object.assign(el("p", "given", [given, record.for && w.forName(record.for)].filter(Boolean).join(" · ")), { lang: w.lang }));
  const words = el("div", "words");
  for (const p of paragraphs(polished(record))) words.append(el("p", "", p));
  const kept = keptChanges(record);
  const notes = Object.assign(el("footer", "notes"), { lang: w.lang });
  notes.append(el("p", "", kept ? w.polishedFrom(kept) : w.asSpoken), el("p", "", w.unlockedHere), el("p", "", w.notOfficial));
  article.append(head, words, notes);
  document.title = `${record.title || w.untitled} · ${w.brand}`;
  show("open", [article]);

  // Keep it in Upon Thy Head: a button once the app is in a store (see stores.js), a plain line until then.
  const android = /Android/i.test(navigator.userAgent);
  const store = android ? STORES.googlePlay : STORES.appStore || STORES.googlePlay;
  if (store) {
    const button = el("a", "keep-button");
    button.href = store;
    button.rel = "noreferrer";
    button.append(Object.assign(el("img"), { src: "/app-icon.png", alt: "", width: 28, height: 28 }), el("span", "", w.keepButton));
    keep.replaceChildren(button, el("p", "keep-note", w.keepNote));
  } else {
    keep.replaceChildren(el("p", "keep-coming", w.comingTitle), el("p", "keep-note", until ? w.comingNote(until) : ""));
  }
  keep.hidden = false;
}

async function run() {
  const id = location.pathname.split("/").filter(Boolean).pop() ?? "";
  if (!ID_PATTERN.test(id)) return message("gone", w.gone);
  let key;
  try {
    key = keyFromFragment(location.hash);
  } catch {
    return message("key", w.key);
  }
  let response;
  try {
    response = await fetch(`/api/b/${id}`, { cache: "no-store", credentials: "omit", referrerPolicy: "no-referrer" });
  } catch {
    return message("offline", w.offline, true);
  }
  if (response.status === 410 || response.status === 404) return message("gone", w.gone);
  if (response.status === 429) return message("busy", w.busy, true);
  if (!response.ok) return message("offline", w.offline, true);
  try {
    const locked = new Uint8Array(await response.arrayBuffer());
    const expires = new Date(response.headers.get("Blessing-Expires") ?? "");
    const record = readRecord(await open(locked, key));
    showBlessing(record, Number.isNaN(expires.getTime()) ? null : expires);
  } catch (error) {
    const code = error instanceof LinkError ? error.code : "record";
    if (code === "newer") return message("newer", w.newer);
    if (code === "locked" || code === "key") return message("key", w.key);
    return message("unreadable", w.unreadable);
  }
}

show("opening", [el("p", "opening", w.opening)]);
if (!globalThis.crypto?.subtle) message("unreadable", w.unreadable);
else run();
