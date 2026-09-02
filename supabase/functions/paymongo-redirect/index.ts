// Fallback confirmation page PayMongo redirects to after the GCash checkout.
// The Flutter WebView normally intercepts navigation to this URL before it
// loads (see gcash_checkout_screen.dart), so this is mostly a safety net for
// browsers or slow interception.
Deno.serve((req) => {
  const url = new URL(req.url);
  const status = url.searchParams.get("status") === "success" ? "success" : "failed";
  const message =
    status === "success"
      ? "Payment received. You can return to the app."
      : "Payment was not completed. You can return to the app and try again.";

  const html = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Payment ${status}</title>
<style>body{font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#f5f5f5;color:#222;text-align:center;padding:24px}</style>
</head><body><p>${message}</p></body></html>`;

  return new Response(html, { headers: { "Content-Type": "text/html" } });
});
