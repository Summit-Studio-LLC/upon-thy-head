// Android's version of the same promise (Digital Asset Links), ready but empty: the Android app
// has no package name or signing key yet. When it does, put one statement in the list:
//
//   {
//     "relation": ["delegate_permission/common.handle_all_urls"],
//     "target": {
//       "namespace": "android_app",
//       "package_name": "<the Android package, e.g. dev.summitstudio.uponThyHead>",
//       "sha256_cert_fingerprints": ["<SHA-256 of the signing certificate, AA:BB:…>"]
//     }
//   }
//
// Use the fingerprint of the key Google Play signs with (Play Console > Setup > App integrity),
// and the upload key's as a second entry if debug builds should open links too. The app's manifest
// needs an intent filter for https://uponthyhead.app/b/ with android:autoVerify="true".

const statements: unknown[] = [];

export function GET() {
  return new Response(JSON.stringify(statements), { headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=3600" } });
}
