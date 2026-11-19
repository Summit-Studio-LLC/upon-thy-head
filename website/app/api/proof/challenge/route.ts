import { challenge } from "../../../../lib/links/service.ts";
import { clientOf, deps, respond } from "../../b/http.ts";

/** A signed, five-minute challenge to prove against. Nothing is kept. */
export async function POST(request: Request) {
  return respond(await challenge(deps(), { client: clientOf(request) }));
}
