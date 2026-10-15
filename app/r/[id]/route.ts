import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_PATTERN.test(id)) notFound();

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect(`/login?next=${encodeURIComponent(`/r/${id}`)}`);

  // The lookup is RLS-scoped, so a reminder owned by someone else is indistinguishable from a missing id.
  const { data } = await supabase.from("reminders").select("id").eq("id", id).maybeSingle();
  if (!data) notFound();

  redirect(`/?open=${encodeURIComponent(id)}`);
}
