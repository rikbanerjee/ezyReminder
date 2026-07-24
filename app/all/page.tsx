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
    <main className="mx-auto flex min-h-dvh max-w-md flex-col gap-5 px-4 py-8">
      <header className="flex items-center justify-between">
        <h1 className="text-[26px] font-bold tracking-tight">All</h1>
        <Link href="/settings" className="grid size-8 place-items-center rounded-lg text-text-2 hover:bg-muted" aria-label="Settings">
          <Settings className="size-4" />
        </Link>
      </header>

      <HomeView
        contexts={contexts}
        reminders={reminders}
        doneToday={doneToday}
        activeTab="all"
        shipSoonCount={shipSoonCount}
        showSearch
      />
    </main>
  );
}
