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
    <main className="mx-auto flex h-full min-h-0 w-full max-w-md flex-col">
      <header className="flex shrink-0 items-center justify-between px-4 pb-2 pt-8">
        <h1 className="text-[26px] font-bold tracking-tight">Today</h1>
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

      <div className="min-h-0 flex-1 px-4">
        <HomeView
          contexts={contexts}
          reminders={reminders}
          doneToday={doneToday}
          composePrefill={prefill}
          composeAutoFocus={!!compose}
          activeTab="today"
          shipSoonCount={shipSoonCount}
          footer={`Signed in as ${user?.email}`}
        />
      </div>
    </main>
  );
}
