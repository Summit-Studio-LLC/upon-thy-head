// Warnings to the owner when the day's allowance is being used up, by email through Resend's HTTP
// API. A warning carries counts only. With RESEND_API_KEY, ALERT_TO or ALERT_FROM unset, nothing is
// sent and nothing fails. Sending never holds up a link: the service runs it after answering.

export type Alert = (subject: string, text: string) => Promise<void>;

export function resendAlert(env: Record<string, string | undefined> = process.env, fetcher: typeof fetch = fetch): Alert | undefined {
  const key = env.RESEND_API_KEY, to = env.ALERT_TO, from = env.ALERT_FROM;
  if (!key || !to || !from) return undefined;
  return async (subject, text) => {
    const response = await fetcher("https://api.resend.com/emails", {
      method: "POST",
      headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
      body: JSON.stringify({ from, to: to.split(",").map((t) => t.trim()).filter(Boolean), subject, text }),
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error("resend refused the warning");
  };
}
