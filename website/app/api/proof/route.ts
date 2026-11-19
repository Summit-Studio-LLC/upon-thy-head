import { after } from "next/server";
import { PROOF } from "../../../lib/links/proof.ts";
import { prove } from "../../../lib/links/service.ts";
import { bodyOf, clientOf, deps, respond } from "../b/http.ts";

/** Proof of the app: an App Attest attestation or a Play Integrity token, answered with a pass. */
export async function POST(request: Request) {
  return respond(await prove(deps(after), { contentType: request.headers.get("content-type"), body: await bodyOf(request, PROOF.maxBody), client: clientOf(request) }));
}
