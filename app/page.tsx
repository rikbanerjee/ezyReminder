import Link from "next/link";
import { Settings } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { Button } from "@/components/ui/button";
import { signOut } from "@/app/actions";
import { HomeView } from "@/components/home/home-view";
import { fetchHomeData } from "@/lib/home-data";

/**
 * Phase 1 — the Today screen (PLAN.md §5.2, DESIGN.md §4.1): quick-add,
 * context filter, and Overdue/Today/Upcoming/Done sections. Data is fetched
 * server-side (RLS-scoped); all date grouping happens client-side in the
 * user's timezone.
 */
export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ compose?: string; prefill?: string }>;
}) {
  const { compose, prefill } = await searchParams;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { contexts, reminders, doneToday, shipSoonCount } = await fetchHomeData(supabase);

  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col gap-5 px-4 py-8">
      <header className="flex items-center justify-between">
        <h1 className="text-[26px] font-bold tracking-tight">easyReminder</h1>
        <div className="flex items-center gap-1">
          <Link href="/settings" className="grid size-8 place-items-center rounded-lg text-text-2 hover:bg-muted" aria-label="Settings">
            <Settings className="size-4" />
          </Link>
          <form action={signOut}>
            <Button variant="ghost" size="sm" type="submit">
              Sign out
            </Button>
          </form>
        </div>
      </header>

      <HomeView
        contexts={contexts}
        reminders={reminders}
        doneToday={doneToday}
        composePrefill={prefill}
        composeAutoFocus={!!compose}
        activeTab="today"
        shipSoonCount={shipSoonCount}
      />

      <p className="px-1 pt-2 text-[12px] text-text-2">
        Signed in as {user?.email}
      </p>
    </main>
  );
}
