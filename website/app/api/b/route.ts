import { after } from "next/server";
import { create } from "../../../lib/links/service.ts";
import { bodyOf, clientOf, deps, hasType, respond } from "./http.ts";

/**
 * Create: the phone sends the locked bytes and gets back the id, the expiry and the stop token.
 * A pass from /api/proof comes in the Blessing-Pass header.
 */
export async function POST(request: Request) {
  const contentType = request.headers.get("content-type");
  if (!hasType(contentType, "application/octet-stream")) return respond({ status: 415, json: { error: "type" } });
  return respond(
    await create(deps(after), {
      contentType,
      body: await bodyOf(request),
      client: clientOf(request),
      pass: request.headers.get("blessing-pass"),
    }),
  );
}
