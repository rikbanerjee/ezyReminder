const APNS_URL =
  "https://api.sandbox.push.apple.com/3/device/0000000000000000000000000000000000000000000000000000000000000000";
const APNS_TOPIC = "com.ezyreminder.app";

function jsonResponse(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function handler(request) {
  if (request.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceRoleKey) {
    return jsonResponse({ ok: false, error: "probe_not_configured" }, 503);
  }
  if (request.headers.get("authorization") !== `Bearer ${serviceRoleKey}`) {
    return jsonResponse({ ok: false, error: "unauthorized" }, 401);
  }

  let client;
  try {
    if (typeof Deno.createHttpClient !== "function") {
      return jsonResponse({ ok: false, error: "http2_client_unsupported" }, 503);
    }
    try {
      client = Deno.createHttpClient({ http1: false, http2: true });
    } catch {
      return jsonResponse({ ok: false, error: "http2_client_unsupported" }, 503);
    }
    const response = await fetch(APNS_URL, {
      method: "POST",
      client,
      signal: AbortSignal.timeout(10_000),
      headers: {
        "apns-push-type": "alert",
        "apns-topic": APNS_TOPIC,
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps: { alert: "Transport probe" } }),
    });

    const reason = (await response.json().catch(() => null))?.reason;
    const apnsId = response.headers.get("apns-id");
    if (response.status === 403 && reason === "MissingProviderToken" && apnsId) {
      return jsonResponse({
        ok: true,
        http2OnlyRequested: true,
        apnsStatus: response.status,
        reason,
        apnsId,
      }, 200);
    }

    return jsonResponse({
      ok: false,
      error: "transport_gate_not_passed",
      apnsStatus: response.status,
      reason: typeof reason === "string" ? reason : null,
      hasApnsId: Boolean(apnsId),
    }, 502);
  } catch {
    return jsonResponse({ ok: false, error: "transport_probe_failed" }, 503);
  } finally {
    client?.close();
  }
}

Deno.serve(handler);
