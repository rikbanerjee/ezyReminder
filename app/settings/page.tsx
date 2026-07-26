import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { SettingsView, type SettingsContext } from "@/components/settings/settings-view";

export default async function SettingsPage() {
  const supabase = await createClient();

  const [{ data: settings }, { data: contextRows }, { data: slack }] = await Promise.all([
    supabase.from("user_settings").select("timezone").maybeSingle(),
    supabase.from("contexts").select("id, name, color, quiet_hours").order("name"),
    supabase.from("slack_integrations").select("team_name").maybeSingle(),
  ]);

  const contexts: SettingsContext[] = (contextRows ?? []).map((c) => ({
    id: c.id,
    name: c.name,
    color: c.color,
    quiet_hours: (c.quiet_hours ?? {}) as { start?: string; end?: string },
  }));

  return (
    <main className="mx-auto flex h-full min-h-0 w-full max-w-md flex-col">
      <header className="flex shrink-0 items-center gap-2 px-4 pb-2 pt-8">
        <Link href="/" className="grid size-8 place-items-center rounded-lg text-text-2 hover:bg-muted" aria-label="Back">
          <ArrowLeft className="size-4" />
        </Link>
        <h1 className="text-[20px] font-bold tracking-tight">Settings</h1>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-8">
        <SettingsView
          timezone={settings?.timezone ?? "UTC"}
          contexts={contexts}
          slackConnected={!!slack}
          slackTeamName={slack?.team_name ?? null}
        />
      </div>
    </main>
  );
}
