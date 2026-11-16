// Tells iOS that links to /b/… on this site belong to the app, so a shared link opens straight
// in it. Served as JSON, with no redirect, at exactly /.well-known/apple-app-site-association.
// Only /b/* is claimed: the landing page and everything else stay in the browser.

const association = {
  applinks: {
    details: [{ appIDs: ["7R77MUH4FF.dev.summitstudio.uponThyHead"], components: [{ "/": "/b/*", comment: "A shared blessing" }] }],
  },
};

export function GET() {
  return new Response(JSON.stringify(association), { headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=3600" } });
}
