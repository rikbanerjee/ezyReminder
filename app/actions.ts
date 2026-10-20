"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { Channel } from "@/lib/supabase/types";

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}

/** Payload the reminder sheet sends when creating a new reminder. */
export interface CreateReminderInput {
  title: string;
  notes?: string | null;
  dueAt: string | null; // ISO
  contextId?: string | null;
  isOrder: boolean;
  channels: Channel[];
  order?: {
    orderRef: string | null;
    recipientName: string | null;
    shipBy: string | null; // "YYYY-MM-DD"
    carrier: string | null;
  } | null;
}

export type ActionResult = { ok: true } | { ok: false; error: string };
export type CreateReminderResult = { ok: true; id: string } | { ok: false; error: string };

async function requireUser() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  return { supabase, user };
}

export async function createReminder(input: CreateReminderInput): Promise<CreateReminderResult> {
  const title = input.title.trim();
  if (!title) return { ok: false, error: "A reminder needs some text." };

  const { supabase } = await requireUser();

  // Resolve the context: explicit id, else Side Gig / first.
  let contextId = input.contextId ?? null;
  if (!contextId) {
    const { data: contexts, error: ctxErr } = await supabase
      .from("contexts")
      .select("id, slug")
      .order("name");
    if (ctxErr) return { ok: false, error: ctxErr.message };
    if (!contexts || contexts.length === 0) {
      return { ok: false, error: "No contexts found for your account." };
    }
    contextId = (contexts.find((c) => c.slug === "sidegig") ?? contexts[0]).id;
  }

  const shipBy = input.order?.shipBy ?? (input.dueAt ? input.dueAt.slice(0, 10) : null);
  const { data: id, error } = await supabase.rpc("create_reminder", {
    p_title: title,
    p_notes: input.notes ?? null,
    p_due_at: input.dueAt,
    p_context_id: contextId,
    p_channels: input.channels ?? [],
    p_is_order: input.isOrder,
    p_order_ref: input.order?.orderRef ?? null,
    p_recipient_name: input.order?.recipientName ?? null,
    p_ship_by: shipBy,
    p_carrier: input.order?.carrier ?? null,
  });
  if (error) return { ok: false, error: error.message };
  if (!id) return { ok: false, error: "Reminder could not be created." };

  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  revalidatePath("/ship-queue");
  revalidatePath("/side-gig");
  return { ok: true, id };
}

export async function completeReminder(id: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase
    .from("reminders")
    .update({ status: "done", snoozed_until: null })
    .eq("id", id);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  return { ok: true };
}

export async function reopenReminder(id: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase
    .from("reminders")
    .update({ status: "open", snoozed_until: null })
    .eq("id", id);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  return { ok: true };
}

export async function snoozeReminder(id: string, until: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase
    .from("reminders")
    .update({ status: "snoozed", snoozed_until: until })
    .eq("id", id);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  return { ok: true };
}

export async function deleteReminder(id: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase.from("reminders").delete().eq("id", id);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  return { ok: true };
}

/** Full edit from the reminder detail sheet (DESIGN.md §4.2). */
export interface UpdateReminderInput {
  id: string;
  title: string;
  notes: string | null;
  dueAt: string | null; // ISO
  contextId: string;
  channels: Channel[];
  isOrder: boolean;
}

export async function updateReminder(input: UpdateReminderInput): Promise<ActionResult> {
  const title = input.title.trim();
  if (!title) return { ok: false, error: "A reminder needs some text." };

  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("update_reminder", {
    p_id: input.id,
    p_title: title,
    p_notes: input.notes,
    p_due_at: input.dueAt,
    p_context_id: input.contextId,
    p_channels: input.channels,
    p_is_order: input.isOrder,
  });
  if (error) return { ok: false, error: error.message };

  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  revalidatePath("/ship-queue");
  return { ok: true };
}

export interface UpdateOrderDetailsInput {
  reminderId: string;
  orderRef: string | null;
  recipientName: string | null;
  shipBy: string | null; // "YYYY-MM-DD"
  carrier: string | null;
}

export async function updateOrderDetails(input: UpdateOrderDetailsInput): Promise<ActionResult> {
  const { supabase, user } = await requireUser();
  const { error } = await supabase.from("orders").upsert({
    reminder_id: input.reminderId,
    user_id: user.id,
    order_ref: input.orderRef,
    recipient_name: input.recipientName,
    ship_by: input.shipBy,
    carrier: input.carrier,
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  revalidatePath("/ship-queue");
  return { ok: true };
}

export interface UpdateWorkDetailsInput {
  reminderId: string;
  managerName: string | null;
  departmentResource: string | null;
  projectName: string | null;
}

/** Work → "Add follow-up details" panel (PLAN.md §3.1, DESIGN.md §4.2). */
export async function updateWorkDetails(input: UpdateWorkDetailsInput): Promise<ActionResult> {
  const { supabase, user } = await requireUser();
  const { error } = await supabase.from("work_details").upsert({
    reminder_id: input.reminderId,
    user_id: user.id,
    manager_name: input.managerName,
    department_resource: input.departmentResource,
    project_name: input.projectName,
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  return { ok: true };
}

export interface UpdateSidegigDetailsInput {
  reminderId: string;
  initiativeName: string | null;
  clientName: string | null;
}

/** Side Gig → "Add initiative details" panel (PLAN.md §3.1, DESIGN.md §4.2). */
export async function updateSidegigDetails(input: UpdateSidegigDetailsInput): Promise<ActionResult> {
  const { supabase, user } = await requireUser();
  const { error } = await supabase.from("sidegig_details").upsert({
    reminder_id: input.reminderId,
    user_id: user.id,
    initiative_name: input.initiativeName,
    client_name: input.clientName,
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  return { ok: true };
}

/** Ship Queue / detail sheet "Mark shipped" (DESIGN.md §4.2, §4.3). */
export async function markShipped(reminderId: string, trackingNumber: string, carrier: string | null): Promise<ActionResult> {
  const { supabase } = await requireUser();

  const { error } = await supabase.rpc("mark_shipped", {
    p_reminder_id: reminderId,
    p_tracking_number: trackingNumber || null,
    p_carrier: carrier || null,
  });
  if (error) return { ok: false, error: error.message };

  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  revalidatePath("/ship-queue");
  return { ok: true };
}

/** "+3d follow-up" toast action after marking an order shipped. */
export async function createFollowUp(reminderId: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("create_follow_up", { p_reminder_id: reminderId });
  if (error) return { ok: false, error: error.message };

  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  return { ok: true };
}

/** Shopping checklist (DESIGN.md §4.2.1) — each add/check/delete is an instant write. */
export type AddShoppingItemResult = { ok: true; id: string } | { ok: false; error: string };

export async function addShoppingItem(reminderId: string, label: string): Promise<AddShoppingItemResult> {
  const trimmed = label.trim();
  if (!trimmed) return { ok: false, error: "Item needs some text." };

  const { supabase } = await requireUser();
  const { data: id, error } = await supabase.rpc("add_shopping_item", {
    p_reminder_id: reminderId,
    p_label: trimmed,
  });
  if (error) return { ok: false, error: error.message };
  if (!id) return { ok: false, error: "Shopping item could not be added." };

  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  return { ok: true, id };
}

export async function toggleShoppingItem(itemId: string, checked: boolean): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase.from("shopping_items").update({ checked }).eq("id", itemId);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  return { ok: true };
}

export async function deleteShoppingItem(itemId: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase.from("shopping_items").delete().eq("id", itemId);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  return { ok: true };
}

/** Queue a retry through the same claimed, quiet-hours-aware delivery pipeline. */
export async function retryNotification(id: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("retry_notification", { p_notification_id: id });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  revalidatePath("/home");
  revalidatePath("/all");
  return { ok: true };
}

export async function updateTimezone(timezone: string): Promise<ActionResult> {
  const { supabase, user } = await requireUser();
  const { error } = await supabase.from("user_settings").upsert({ user_id: user.id, timezone });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/settings");
  return { ok: true };
}

export async function updateQuietHours(contextId: string, start: string, end: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase
    .from("contexts")
    .update({ quiet_hours: { start, end } })
    .eq("id", contextId);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/settings");
  return { ok: true };
}

export async function completeOnboarding(): Promise<ActionResult> {
  const { supabase, user } = await requireUser();
  const { error } = await supabase
    .from("user_settings")
    .upsert({ user_id: user.id, onboarded_at: new Date().toISOString() });
  if (error) return { ok: false, error: error.message };
  return { ok: true };
}
