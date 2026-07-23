import Link from "next/link";
import { Settings } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { Button } from "@/components/ui/button";
import { signOut } from "@/app/actions";
import { HomeView } from "@/components/home/home-view";
import type { HomeContext, HomeReminder } from "@/components/home/types";

/**
 * Phase 1 — the Today screen (PLAN.md §5.2, DESIGN.md §4.1): quick-add,
 * context filter, and Overdue/Today/Upcoming/Done sections. Data is fetched
 * server-side (RLS-scoped); all date grouping happens client-side in the
 * user's timezone.
 */
export default async function Home() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: contextRows } = await supabase
    .from("contexts")
    .select("id, slug, name, color, default_channel")
    .order("name");

  const contexts: HomeContext[] = (contextRows ?? []) as HomeContext[];
  const contextById = new Map(contexts.map((c) => [c.id, c]));

  const reminderSelect =
    "id, title, due_at, snoozed_until, status, channels, is_order, context_id";

  // Active list: open + snoozed.
  const { data: activeRows } = await supabase
    .from("reminders")
    .select(reminderSelect)
    .in("status", ["open", "snoozed"])
    .order("due_at", { ascending: true, nullsFirst: false });

  // Done in the last ~48h — the client trims to "today" in local time.
  const since = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();
  const { data: doneRows } = await supabase
    .from("reminders")
    .select(reminderSelect)
    .eq("status", "done")
    .gte("updated_at", since)
    .order("updated_at", { ascending: false });

  type Row = {
    id: string;
    title: string;
    due_at: string | null;
    snoozed_until: string | null;
    status: HomeReminder["status"];
    channels: HomeReminder["channels"];
    is_order: boolean;
    context_id: string;
  };

  // Most recent failed delivery per reminder, for the ⚠ + retry affordance.
  const { data: failedRows } = await supabase
    .from("notifications")
    .select("id, reminder_id")
    .eq("status", "failed")
    .order("updated_at", { ascending: false });

  const failedByReminder = new Map<string, string>();
  for (const n of failedRows ?? []) {
    if (!failedByReminder.has(n.reminder_id)) failedByReminder.set(n.reminder_id, n.id);
  }

  const toReminder = (r: Row): HomeReminder => ({
    id: r.id,
    title: r.title,
    due_at: r.due_at,
    snoozed_until: r.snoozed_until,
    status: r.status,
    channels: r.channels ?? [],
    is_order: r.is_order,
    context: contextById.get(r.context_id) ?? null,
    failedNotificationId: failedByReminder.get(r.id) ?? null,
  });

  const reminders = ((activeRows ?? []) as Row[]).map(toReminder);
  const doneToday = ((doneRows ?? []) as Row[]).map(toReminder);

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

      <HomeView contexts={contexts} reminders={reminders} doneToday={doneToday} />

      <p className="px-1 pt-2 text-[12px] text-text-2">
        Signed in as {user?.email}
      </p>
    </main>
  );
}
