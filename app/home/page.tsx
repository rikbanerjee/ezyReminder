import Link from "next/link";
import { redirect } from "next/navigation";
import { Settings } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { fetchHomeData } from "@/lib/home-data";
import { HouseholdView } from "@/components/household/household-view";
import type { MaintenanceItem, ServiceRecord } from "@/lib/household";

export default async function HouseholdPage({
  searchParams,
}: {
  searchParams: Promise<{ open?: string }>;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { open } = await searchParams;
  const [home, details, records] = await Promise.all([
    fetchHomeData(supabase),
    supabase.from("home_maintenance").select("*"),
    supabase
      .from("home_service_records")
      .select("*")
      .order("serviced_at", { ascending: false }),
  ]);
  // Fetch by the authoritative detail IDs; category changes never hide a reminder.
  const ids = (details.data ?? []).map((d) => d.reminder_id);
  const result = ids.length
    ? await supabase
        .from("reminders")
        .select(
          "id,title,notes,due_at,snoozed_until,status,channels,updated_at",
        )
        .in("id", ids)
    : { data: [], error: null };
  const items = (details.data ?? []).flatMap((d) => {
    const r = result.data?.find((r) => r.id === d.reminder_id);
    return r ? [{ ...r, ...d } as MaintenanceItem] : [];
  });
  const error = details.error || records.error || result.error;
  return (
    <main className="mx-auto flex h-full min-h-0 w-full max-w-md flex-col">
      <header className="flex items-center justify-between px-4 pb-2 pt-8">
        <h1 className="text-[28px] font-bold tracking-tight">Home</h1>
        <Link
          href="/settings"
          aria-label="Settings"
          className="grid size-11 place-items-center text-text-2"
        >
          <Settings className="size-5" />
        </Link>
      </header>
      <HouseholdView
        contexts={home.contexts}
        shopping={home.reminders.filter((r) => r.context?.slug === "shopping")}
        maintenance={items}
        records={(records.data ?? []) as ServiceRecord[]}
        shipSoonCount={home.shipSoonCount}
        openId={open}
        loadError={
          error
            ? "Home maintenance could not load. Try refreshing in a moment."
            : undefined
        }
      />
    </main>
  );
}
