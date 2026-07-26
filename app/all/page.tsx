import Link from "next/link";
import { Settings } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { HomeView } from "@/components/home/home-view";
import { fetchHomeData } from "@/lib/home-data";

/** All / Browse tab (DESIGN.md §4.4) — same list rendering as Today, plus search, no date-bucket framing. */
export default async function AllPage() {
  const supabase = await createClient();
  const { contexts, reminders, doneToday, shipSoonCount } = await fetchHomeData(supabase);

  return (
    <main className="mx-auto flex h-full min-h-0 w-full max-w-md flex-col">
      <header className="flex shrink-0 items-center justify-between px-4 pb-2 pt-8">
        <h1 className="text-[26px] font-bold tracking-tight">All</h1>
        <Link href="/settings" className="grid size-8 place-items-center rounded-lg text-text-2 hover:bg-muted" aria-label="Settings">
          <Settings className="size-4" />
        </Link>
      </header>

      <div className="min-h-0 flex-1 px-4">
        <HomeView
          contexts={contexts}
          reminders={reminders}
          doneToday={doneToday}
          activeTab="all"
          shipSoonCount={shipSoonCount}
          showSearch
        />
      </div>
    </main>
  );
}
