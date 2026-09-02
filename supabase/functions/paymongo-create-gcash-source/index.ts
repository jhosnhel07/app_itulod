// Creates a PayMongo GCash Source for a transport booking and returns the
// hosted checkout URL. Runs with the caller's own JWT (not the service role)
// so existing RLS policies on transport_bookings decide what they can read
// or update — this function never sees other customers' bookings.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const PAYMONGO_SECRET_KEY = Deno.env.get("PAYMONGO_SECRET_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

// PayMongo's minimum amount for GCash sources, in centavos (₱100).
// Confirm the current figure against PayMongo's docs before going live.
const MIN_AMOUNT_CENTAVOS = 10000;

function authHeader() {
  const encoded = btoa(`${PAYMONGO_SECRET_KEY}:`);
  return `Basic ${encoded}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authorization } },
    });

    const { booking_id } = await req.json();
    if (!booking_id) {
      return new Response(JSON.stringify({ error: "booking_id is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: booking, error: fetchError } = await supabase
      .from("transport_bookings")
      .select("id, customer_id, status, payment_method, payment_status, estimated_fare, final_fare")
      .eq("id", booking_id)
      .single();

    if (fetchError || !booking) {
      return new Response(JSON.stringify({ error: "Booking not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (booking.payment_method !== "gcash") {
      return new Response(JSON.stringify({ error: "Booking is not set to pay with GCash" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (booking.status === "cancelled" || booking.payment_status === "paid") {
      return new Response(JSON.stringify({ error: "Booking cannot be paid" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const fare = booking.final_fare ?? booking.estimated_fare;
    if (!fare) {
      return new Response(JSON.stringify({ error: "Booking has no fare set" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const amountCentavos = Math.round(fare * 100);
    if (amountCentavos < MIN_AMOUNT_CENTAVOS) {
      return new Response(
        JSON.stringify({ error: `Amount must be at least ₱${MIN_AMOUNT_CENTAVOS / 100} for GCash` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const redirectBase = `${SUPABASE_URL}/functions/v1/paymongo-redirect`;
    const paymongoRes = await fetch("https://api.paymongo.com/v1/sources", {
      method: "POST",
      headers: {
        Authorization: authHeader(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        data: {
          attributes: {
            amount: amountCentavos,
            currency: "PHP",
            type: "gcash",
            redirect: {
              success: `${redirectBase}?status=success&booking_id=${booking.id}`,
              failed: `${redirectBase}?status=failed&booking_id=${booking.id}`,
            },
          },
        },
      }),
    });

    const paymongoJson = await paymongoRes.json();
    if (!paymongoRes.ok) {
      return new Response(JSON.stringify({ error: paymongoJson?.errors?.[0]?.detail ?? "PayMongo error" }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const source = paymongoJson.data;
    const { error: updateError } = await supabase
      .from("transport_bookings")
      .update({ payment_source_id: source.id })
      .eq("id", booking.id);

    if (updateError) {
      return new Response(JSON.stringify({ error: updateError.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        checkout_url: source.attributes.redirect.checkout_url,
        source_id: source.id,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
