import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { OnboardingView } from "@/components/onboarding/onboarding-view";
import { safeInternalPath } from "@/lib/auth-redirect";

/**
 * First-run screen (LAUNCH.md §3.3) — a new user's contexts already come
 * seeded with an example reminder each (0005_onboarding.sql), but nothing
 * yet pushes them to connect a delivery channel. Gated by
 * user_settings.onboarded_at; app/page.tsx redirects here until it's set.
 */
export default async function OnboardingPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next: requestedNext } = await searchParams;
  const continueTo = safeInternalPath(requestedNext);
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: settings } = await supabase.from("user_settings").select("onboarded_at").maybeSingle();

  if (settings?.onboarded_at) redirect(continueTo);

  return (
    <main className="flex h-full min-h-0 items-center justify-center overflow-y-auto px-4">
      <OnboardingView email={user.email ?? ""} continueTo={continueTo} />
    </main>
  );
}
