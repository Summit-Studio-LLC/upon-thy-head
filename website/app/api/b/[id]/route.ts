import { read, stop } from "../../../../lib/links/service.ts";
import { clientOf, deps, respond } from "../http.ts";

type Context = { params: Promise<{ id: string }> };

/** Read: the locked bytes, or "gone". */
export async function GET(request: Request, { params }: Context) {
  return respond(await read(deps(), { id: (await params).id, client: clientOf(request) }));
}

/** Stop: with the stop token, the copy is erased at once. */
export async function DELETE(request: Request, { params }: Context) {
  return respond(await stop(deps(), { id: (await params).id, authorization: request.headers.get("authorization"), client: clientOf(request) }));
}
