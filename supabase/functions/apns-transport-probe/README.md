# APNs HTTP/2 transport probe

This endpoint is a transport diagnostic only. It sends one synthetic alert request to Apple's fixed sandbox host using a zero-filled, invalid device token and no APNs provider token. A `403 MissingProviderToken` response with an `apns-id` demonstrates that the request reached APNs over the configured HTTP/2-only client. It does **not** demonstrate authenticated push delivery or validate an APNs key.

The probe accepts only `POST` with `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`. Unauthorized requests do not create a client or make an outbound request. The APNs URL and topic are constants; request input cannot select a host, token, relay, proxy, or CA. TLS uses the runtime's default certificate validation. The client closes after each request, and the outbound request times out after 10 seconds. No request or response credentials are logged or returned.

## Offline tests

Run from the repository root:

```sh
node --test supabase/functions/apns-transport-probe/index.test.mjs
```

The tests replace Deno's server, environment, HTTP client, and `fetch`; they never contact Apple or Supabase.

## Human-only hosted check

After review, a project administrator can deploy this diagnostic function with the normal Supabase CLI or dashboard workflow:

```sh
npx supabase functions deploy apns-transport-probe
```

Default Supabase JWT verification remains enabled. Invoke it from an administrator-controlled shell or the dashboard's authenticated test context. Keep the service-role key in a local environment variable or the dashboard secret manager; never paste it into chat, a ticket, or command history. Example from an authorized local shell:

```sh
curl -sS -X POST "$SUPABASE_URL/functions/v1/apns-transport-probe" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"
```

The expected success JSON contains `ok: true`, `apnsStatus: 403`, `reason: "MissingProviderToken"`, and an `apnsId`. Any other status, reason, missing identifier, timeout, or network error means the transport gate did not pass. A failed probe does not trigger an HTTP/1.1 fallback. Do not proceed to an APNs sender until this probe passes in the hosted environment and the separate human deployment gate is satisfied.

Deno's `Deno.createHttpClient` supports `http1` and `http2` options, and `fetch` accepts its returned client. This probe requests `{ http1: false, http2: true }`, so an unsupported or failed HTTP/2 transport fails closed. See the [Deno Fetch API](https://docs.deno.com/api/deno/fetch/) and [Apple's APNs request documentation](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns).
