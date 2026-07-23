"use client";

import { useState, useTransition } from "react";
import Link from "next/link";
import { toast } from "sonner";
import { MessageSquare, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { updateTimezone, updateQuietHours, disconnectSlack } from "@/app/actions";

export interface SettingsContext {
  id: string;
  name: string;
  color: string;
  quiet_hours: { start?: string; end?: string };
}

export interface SettingsViewProps {
  timezone: string;
  contexts: SettingsContext[];
  slackConnected: boolean;
  slackTeamName: string | null;
}

export function SettingsView({ timezone, contexts, slackConnected, slackTeamName }: SettingsViewProps) {
  return (
    <div className="flex flex-col gap-6">
      <SlackSection connected={slackConnected} teamName={slackTeamName} />
      <TimezoneSection initialTimezone={timezone} />
      <QuietHoursSection contexts={contexts} />
    </div>
  );
}

function Section({ title, description, children }: { title: string; description?: string; children: React.ReactNode }) {
  return (
    <section className="rounded-xl border border-hairline bg-surface p-4">
      <h2 className="text-[15px] font-semibold">{title}</h2>
      {description && <p className="mt-0.5 text-[13px] text-text-2">{description}</p>}
      <div className="mt-3">{children}</div>
    </section>
  );
}

function SlackSection({ connected, teamName }: { connected: boolean; teamName: string | null }) {
  const [pending, startTransition] = useTransition();

  function disconnect() {
    startTransition(async () => {
      const res = await disconnectSlack();
      if (res.ok) toast.success("Slack disconnected");
      else toast.error("Couldn't disconnect", { description: res.error });
    });
  }

  return (
    <Section title="Slack" description="Get reminders as a DM with Done / Snooze buttons.">
      {connected ? (
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-[14px]">
            <MessageSquare className="size-4 text-text-2" />
            Connected{teamName ? ` to ${teamName}` : ""}
          </div>
          <Button type="button" variant="ghost" size="sm" disabled={pending} onClick={disconnect}>
            <Trash2 className="size-3.5" />
            Disconnect
          </Button>
        </div>
      ) : (
        <Button asChild size="sm">
          <Link href="/api/integrations/slack/oauth/start">
            <MessageSquare className="size-4" />
            Connect Slack
          </Link>
        </Button>
      )}
    </Section>
  );
}

function TimezoneSection({ initialTimezone }: { initialTimezone: string }) {
  const [timezone, setTimezone] = useState(initialTimezone);
  const [pending, startTransition] = useTransition();

  function save() {
    const value = timezone.trim();
    if (!value) return;
    startTransition(async () => {
      const res = await updateTimezone(value);
      if (res.ok) toast.success("Timezone saved");
      else toast.error("Couldn't save timezone", { description: res.error });
    });
  }

  return (
    <Section title="Timezone" description="Used to resolve each context's quiet hours to your local time.">
      <div className="flex items-center gap-2">
        <Input
          value={timezone}
          onChange={(e) => setTimezone(e.target.value)}
          placeholder="America/Los_Angeles"
          className="max-w-[240px]"
        />
        <Button size="sm" disabled={pending || timezone.trim() === initialTimezone} onClick={save}>
          Save
        </Button>
      </div>
      <p className="mt-1.5 text-[12px] text-text-2">IANA timezone name, e.g. America/New_York, Europe/London.</p>
    </Section>
  );
}

function QuietHoursSection({ contexts }: { contexts: SettingsContext[] }) {
  return (
    <Section title="Quiet hours" description="Reminders due in this window are delivered at the end time instead.">
      <div className="flex flex-col gap-3">
        {contexts.map((c) => (
          <QuietHoursRow key={c.id} context={c} />
        ))}
      </div>
    </Section>
  );
}

function QuietHoursRow({ context }: { context: SettingsContext }) {
  const [start, setStart] = useState(context.quiet_hours.start ?? "");
  const [end, setEnd] = useState(context.quiet_hours.end ?? "");
  const [pending, startTransition] = useTransition();

  const dirty = start !== (context.quiet_hours.start ?? "") || end !== (context.quiet_hours.end ?? "");

  function save() {
    startTransition(async () => {
      const res = await updateQuietHours(context.id, start, end);
      if (res.ok) toast.success(`${context.name} quiet hours saved`);
      else toast.error("Couldn't save", { description: res.error });
    });
  }

  return (
    <div className="flex items-center gap-3">
      <span className="flex w-24 shrink-0 items-center gap-1.5 text-[14px]">
        <span className="size-2 rounded-full" style={{ backgroundColor: context.color }} />
        {context.name}
      </span>
      <Label className="sr-only" htmlFor={`start-${context.id}`}>
        Start
      </Label>
      <Input id={`start-${context.id}`} type="time" value={start} onChange={(e) => setStart(e.target.value)} className="w-28" />
      <span className="text-text-2">to</span>
      <Label className="sr-only" htmlFor={`end-${context.id}`}>
        End
      </Label>
      <Input id={`end-${context.id}`} type="time" value={end} onChange={(e) => setEnd(e.target.value)} className="w-28" />
      <Button size="sm" variant="ghost" disabled={!dirty || pending} onClick={save}>
        Save
      </Button>
    </div>
  );
}
