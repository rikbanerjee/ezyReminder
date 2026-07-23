import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { Database } from "@/lib/supabase/types";

/**
 * Supabase client for use in Server Components, Server Actions, and Route
 * Handlers. `cookies()` is async in Next.js 15, so this factory is async too
 * — call it with `await createClient()`.
 *
 * Server Components can't write cookies, so the `setAll` call there is
 * wrapped in a try/catch and is a no-op; session refresh in that case is
 * handled by `middleware.ts`, which *can* write cookies on every request.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            for (const { name, value, options } of cookiesToSet) {
              cookieStore.set(name, value, options);
            }
          } catch {
            // Called from a Server Component — session refresh is
            // handled by middleware instead.
          }
        },
      },
    }
  );
}
