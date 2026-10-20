"use server";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/supabase/types";

export async function saveMaintenance(
  input: Database["public"]["Functions"]["save_home_task"]["Args"],
) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("save_home_task", input);
  if (error) return { ok: false as const, error: error.message };
  revalidatePath("/home");
  revalidatePath("/");
  revalidatePath("/all");
  return { ok: true as const, id: data };
}
export async function recordService(
  input: Database["public"]["Functions"]["record_home_service"]["Args"],
) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("record_home_service", input);
  if (error) return { ok: false as const, error: error.message };
  revalidatePath("/home");
  revalidatePath("/");
  revalidatePath("/all");
  return { ok: true as const };
}
