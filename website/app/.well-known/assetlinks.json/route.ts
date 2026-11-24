// Android's version of the same promise (Digital Asset Links): a blessing link opens in the app
// installed from Google Play. The app's manifest has the matching intent filter for
// https://uponthyhead.app/b/ with android:autoVerify="true".
//
// The first fingerprint is the key Google Play signs the app with (Play Console > App signing);
// it is the one phones see. The second is our upload key (important/upload-keystore.jks), so a
// release build installed straight from this Mac opens links too. Both are public values.

const statements: unknown[] = [
  {
    relation: ["delegate_permission/common.handle_all_urls"],
    target: {
      namespace: "android_app",
      package_name: "dev.summitstudio.uponthyhead",
      sha256_cert_fingerprints: [
        "BE:D9:33:96:D9:C4:E0:9E:11:7F:D5:00:DF:32:D6:43:F9:73:A9:42:14:5E:0D:79:DB:03:57:39:22:DD:92:F7",
        "8E:36:68:A4:FB:2F:8B:C6:8C:90:92:8F:53:32:FE:62:E4:35:FD:39:19:4E:25:63:77:91:66:BE:C9:11:A9:EC",
      ],
    },
  },
];

export function GET() {
  return new Response(JSON.stringify(statements), { headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=3600" } });
}
