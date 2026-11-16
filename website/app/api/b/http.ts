// What the route handlers share: the service's dependencies, the headers every answer carries,
// and how a request's sender is counted without being remembered.

import { createHmac, randomBytes } from "node:crypto";
import { type Answer, Limiter, LIMITS } from "../../../lib/links/service.ts";
import { theStore } from "../../../lib/links/store.ts";

const limiter = new Limiter();
export const deps = () => ({ store: theStore(), limiter, now: () => Date.now() });

/** On every answer from the service: never cached, never framed, never treated as a page. */
export const HEADERS = {
  "Cache-Control": "no-store",
  "Content-Security-Policy": "default-src 'none'; sandbox; frame-ancestors 'none'",
  "Cross-Origin-Resource-Policy": "same-origin",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Robots-Tag": "noindex, nofollow, noarchive",
};

// A fresh secret each time the server starts. The address is mixed with it and only the mix is
// held, in memory, for as long as a rate-limit window lasts. It is never stored and never logged.
const secret = randomBytes(32);
//
// Which address: only the one the platform's own proxy wrote. On Vercel that is
// `x-vercel-forwarded-for`, which Vercel sets itself and a client cannot supply. `x-forwarded-for`
// is never read: anyone can send it, and a sender who could choose their own address could give
// themselves a fresh allowance with every request. Anywhere else (this Mac, a test) there is no
// trusted proxy, so every request counts against one shared allowance.
export function clientOf(request: Request): string {
  const trusted = process.env.VERCEL ? request.headers.get("x-vercel-forwarded-for") : null;
  const address = (trusted ?? "").split(",")[0].trim() || "shared";
  return createHmac("sha256", secret).update(address).digest("base64url").slice(0, 22);
}

export function respond(answer: Answer): Response {
  const headers = new Headers({ ...HEADERS, ...answer.headers });
  if (answer.bytes) return new Response(answer.bytes as BodyInit, { status: answer.status, headers });
  if (answer.json === undefined) return new Response(null, { status: answer.status, headers });
  headers.set("Content-Type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(answer.json), { status: answer.status, headers });
}

/** The body, read no further than one byte past the cap. */
export async function bodyOf(request: Request): Promise<Uint8Array | "too_big"> {
  if (Number(request.headers.get("content-length") ?? 0) > LIMITS.maxBytes) return "too_big";
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > LIMITS.maxBytes) {
      await reader.cancel();
      return "too_big";
    }
    chunks.push(value);
  }
  const out = new Uint8Array(size);
  let at = 0;
  for (const chunk of chunks) {
    out.set(chunk, at);
    at += chunk.length;
  }
  return out;
}
