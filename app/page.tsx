import Link from "next/link";
import { redirect } from "next/navigation";
import { Settings } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { Button } from "@/components/ui/button";
import { signOut } from "@/app/actions";
import { HomeView } from "@/components/home/home-view";
import type { HomeReminder } from "@/components/home/types";
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
  searchParams: Promise<{ compose?: string; prefill?: string; open?: string }>;
}) {
  const { compose, prefill, open } = await searchParams;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: settings } = await supabase.from("user_settings").select("onboarded_at").maybeSingle();
  if (!settings?.onboarded_at) {
    const onboardingTarget = open ? `?next=${encodeURIComponent(`/?open=${open}`)}` : "";
    redirect(`/onboarding${onboardingTarget}`);
  }

  const { contexts, reminders, doneToday, shipSoonCount } = await fetchHomeData(supabase);
  const listedReminder = open ? [...reminders, ...doneToday].find((reminder) => reminder.id === open) : undefined;
  let openReminder: HomeReminder | undefined = listedReminder;
  if (open && !listedReminder && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(open)) {
    // The normal Today feed limits completed reminders to 48 hours. A universal link can still
    // open an older reminder, so fetch that one under RLS and attach its detail rows for the sheet.
    const { data: row } = await supabase
      .from("reminders")
      .select("id, title, notes, due_at, snoozed_until, status, channels, is_order, context_id, tags")
      .eq("id", open)
      .maybeSingle();
    if (row) {
      const context = contexts.find((item) => item.id === row.context_id) ?? null;
      const [orderResult, workResult, sidegigResult, shoppingResult, failedNotifications] = await Promise.all([
        supabase.from("orders").select("order_ref, recipient_name, ship_by, carrier, tracking_number, shipped_at").eq("reminder_id", row.id).maybeSingle(),
        supabase.from("work_details").select("manager_name, department_resource, project_name").eq("reminder_id", row.id).maybeSingle(),
        supabase.from("sidegig_details").select("initiative_name, client_name").eq("reminder_id", row.id).maybeSingle(),
        supabase.from("shopping_items").select("id, label, checked").eq("reminder_id", row.id).order("position", { ascending: true }),
        supabase.from("notifications").select("id").eq("reminder_id", row.id).eq("status", "failed").order("updated_at", { ascending: false }).limit(1),
      ]);
      openReminder = {
        id: row.id,
        title: row.title,
        notes: row.notes,
        due_at: row.due_at,
        snoozed_until: row.snoozed_until,
        status: row.status,
        channels: row.channels ?? [],
        is_order: row.is_order,
        tags: row.tags,
        context,
        failedNotificationId: failedNotifications.data?.[0]?.id ?? null,
        order: orderResult.data ? {
          orderRef: orderResult.data.order_ref,
          recipientName: orderResult.data.recipient_name,
          shipBy: orderResult.data.ship_by,
          carrier: orderResult.data.carrier,
          trackingNumber: orderResult.data.tracking_number,
          shippedAt: orderResult.data.shipped_at,
        } : null,
        workDetails: workResult.data ? {
          managerName: workResult.data.manager_name,
          departmentResource: workResult.data.department_resource,
          projectName: workResult.data.project_name,
        } : null,
        sidegigDetails: sidegigResult.data ? {
          initiativeName: sidegigResult.data.initiative_name,
          clientName: sidegigResult.data.client_name,
        } : null,
        shoppingItems: (shoppingResult.data ?? []).map((item) => ({ id: item.id, label: item.label, checked: item.checked })),
      };
    }
  }

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
          openReminderId={open}
          openReminder={openReminder}
          activeTab="today"
          shipSoonCount={shipSoonCount}
          footer={`Signed in as ${user?.email}`}
        />
      </div>
    </main>
  );
}
