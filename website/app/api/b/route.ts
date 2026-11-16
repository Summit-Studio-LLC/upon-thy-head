import { create } from "../../../lib/links/service.ts";
import { bodyOf, clientOf, deps, respond } from "./http.ts";

/** Create: the phone sends the locked bytes and gets back the id, the expiry and the stop token. */
export async function POST(request: Request) {
  return respond(await create(deps(), { contentType: request.headers.get("content-type"), body: await bodyOf(request), client: clientOf(request) }));
}
