import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/types";

/**
 * Service-role client — bypasses RLS. Only for server contexts with no
 * Supabase user session to scope to, e.g. the Slack interactivity webhook
 * (resolving an arbitrary slack_user_id back to our user_id). Never expose
 * this client or its result set directly to a request initiated by an
 * unauthenticated party without an explicit ownership check first.
 */
export function createServiceClient() {
  return createSupabaseClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false } },
  );
}
