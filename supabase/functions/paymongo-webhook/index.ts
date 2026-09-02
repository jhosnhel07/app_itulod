// Receives PayMongo webhook events for GCash sources/payments.
// Verifies the Paymongo-Signature header, then:
//  - source.chargeable -> creates the actual Payment against that source
//  - payment.paid / payment.failed -> updates the booking's payment_status
import { createClient } from "jsr:@supabase/supabase-js@2";

const PAYMONGO_SECRET_KEY = Deno.env.get("PAYMONGO_SECRET_KEY")!;
const PAYMONGO_WEBHOOK_SECRET = Deno.env.get("PAYMONGO_WEBHOOK_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
const isLiveKey = PAYMONGO_SECRET_KEY.startsWith("sk_live_");

function authHeader() {
  return `Basic ${btoa(`${PAYMONGO_SECRET_KEY}:`)}`;
}

async function hmacSha256Hex(secret: string, message: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function verifySignature(rawBody: string, header: string | null) {
  if (!header) return false;
  const parts = Object.fromEntries(
    header.split(",").map((p) => p.split("=") as [string, string]),
  );
  const expected = await hmacSha256Hex(PAYMONGO_WEBHOOK_SECRET, `${parts.t}.${rawBody}`);
  const provided = isLiveKey ? parts.li : parts.te;
  return provided === expected;
}

async function logEvent(bookingId: string | null, eventType: string, paymongoId: string, payload: unknown) {
  await supabase.from("payment_events").insert({
    booking_id: bookingId,
    event_type: eventType,
    paymongo_id: paymongoId,
    payload,
  });
}

async function findBookingBySourceId(sourceId: string) {
  const { data } = await supabase
    .from("transport_bookings")
    .select("id")
    .eq("payment_source_id", sourceId)
    .maybeSingle();
  return data?.id as string | undefined;
}

Deno.serve(async (req) => {
  const rawBody = await req.text();
  const signatureHeader = req.headers.get("Paymongo-Signature");

  if (!(await verifySignature(rawBody, signatureHeader))) {
    return new Response("Invalid signature", { status: 401 });
  }

  const event = JSON.parse(rawBody);
  const eventType = event?.data?.attributes?.type as string;
  const resource = event?.data?.attributes?.data;

  try {
    if (eventType === "source.chargeable") {
      const sourceId = resource.id as string;
      const amount = resource.attributes.amount as number;
      const bookingId = await findBookingBySourceId(sourceId);

      // PayMongo redelivers events (at-least-once), and a source can only be
      // charged once. If we've already recorded a payment for this booking,
      // treat this as a duplicate delivery instead of re-charging (which
      // PayMongo would reject) and incorrectly marking a paid booking failed.
      if (bookingId) {
        const { data: existing } = await supabase
          .from("transport_bookings")
          .select("payment_status")
          .eq("id", bookingId)
          .maybeSingle();
        if (existing?.payment_status === "paid") {
          await logEvent(bookingId, eventType, sourceId, event);
          return new Response(JSON.stringify({ received: true, skipped: "already paid" }), {
            headers: { "Content-Type": "application/json" },
          });
        }
      }

      const paymentRes = await fetch("https://api.paymongo.com/v1/payments", {
        method: "POST",
        headers: { Authorization: authHeader(), "Content-Type": "application/json" },
        body: JSON.stringify({
          data: {
            attributes: {
              amount,
              currency: "PHP",
              source: { id: sourceId, type: "source" },
              description: bookingId ? `Booking ${bookingId}` : "GCash payment",
            },
          },
        }),
      });
      const paymentJson = await paymentRes.json();
      await logEvent(bookingId ?? null, eventType, sourceId, event);

      if (!paymentRes.ok) {
        if (bookingId) {
          await supabase.from("transport_bookings").update({ payment_status: "failed" }).eq("id", bookingId);
        }
        return new Response(JSON.stringify({ error: paymentJson }), { status: 502 });
      }
    } else if (eventType === "payment.paid" || eventType === "payment.failed") {
      const sourceId = resource?.attributes?.source?.id as string | undefined;
      const bookingId = sourceId ? await findBookingBySourceId(sourceId) : undefined;

      await logEvent(bookingId ?? null, eventType, resource?.id, event);

      if (bookingId) {
        await supabase
          .from("transport_bookings")
          .update({
            payment_status: eventType === "payment.paid" ? "paid" : "failed",
            payment_id: resource?.id ?? null,
          })
          .eq("id", bookingId);
      }
    } else {
      await logEvent(null, eventType ?? "unknown", resource?.id ?? "unknown", event);
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
