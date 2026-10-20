"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { focusLocalDate } from "@/lib/focus";
import { fetchFocusDashboard, focusError, type FocusData } from "@/lib/focus-client";

/**
 * Dashboard data, server-aligned clock and Realtime refresh. Lives in the provider (above every sheet) so
 * a refresh only replaces `data`; sheet drafts are never touched.
 */
export function useFocusDashboard() {
  const supabase = useMemo(() => createClient(), []);
  const [data, setData] = useState<FocusData | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [userId, setUserId] = useState<string | null>(null);
  const [now, setNow] = useState(Date.now());
  const offset = useRef(0);
  const requestId = useRef(0);
  const mounted = useRef(true);
  const refreshTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const reload = useCallback(async () => {
    const id = ++requestId.current;
    try {
      const fresh = await fetchFocusDashboard(supabase);
      if (!mounted.current || id !== requestId.current) return null;
      offset.current = new Date(fresh.server_now).getTime() - Date.now();
      setData(fresh);
      setLoadError(null);
      setNow(Date.now());
      return fresh;
    } catch (error) {
      if (mounted.current && id === requestId.current) setLoadError(focusError(error));
      return null;
    } finally {
      if (mounted.current && id === requestId.current) setLoading(false);
    }
  }, [supabase]);

  const refresh = useCallback(() => {
    if (refreshTimer.current) clearTimeout(refreshTimer.current);
    refreshTimer.current = setTimeout(() => { void reload(); }, 120);
  }, [reload]);

  // Auth identity, first load and "came back to the tab" refreshes.
  useEffect(() => {
    mounted.current = true;
    void reload();
    const auth = supabase.auth.onAuthStateChange((_event, session) => { setUserId(session?.user.id ?? null); refresh(); });
    void supabase.auth.getSession().then(({ data: { session } }) => { if (mounted.current) setUserId(session?.user.id ?? null); });
    const visible = () => { if (document.visibilityState === "visible") refresh(); };
    window.addEventListener("focus", refresh);
    window.addEventListener("online", refresh);
    document.addEventListener("visibilitychange", visible);
    return () => {
      mounted.current = false;
      auth.data.subscription.unsubscribe();
      if (refreshTimer.current) clearTimeout(refreshTimer.current);
      window.removeEventListener("focus", refresh);
      window.removeEventListener("online", refresh);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [reload, refresh, supabase]);

  useEffect(() => { if (!userId) setData(null); }, [userId]);

  // Tables that have always existed (0012). Kept on their own channel: a channel that names a table the
  // hosted database doesn't have yet errors as a whole.
  useEffect(() => {
    if (!userId) return;
    const channel = supabase.channel(`focus-${userId}`);
    for (const table of ["focus_highlights", "focus_sessions", "user_settings"]) {
      channel.on("postgres_changes", { event: "*", schema: "public", table, filter: `user_id=eq.${userId}` }, refresh);
    }
    channel.subscribe((status) => { if (status === "SUBSCRIBED") refresh(); });
    return () => { void supabase.removeChannel(channel); };
  }, [userId, supabase, refresh]);

  // Migration 0015/0016 tables, only once the dashboard proves they exist.
  const hasPreferences = data?.api.preferences ?? false;
  const hasTimes = data?.api.times ?? false;
  useEffect(() => {
    if (!userId || (!hasPreferences && !hasTimes)) return;
    const channel = supabase.channel(`focus-plan-${userId}`);
    const tables = [...(hasPreferences ? ["focus_preferences"] : []), ...(hasTimes ? ["focus_times", "focus_assignments"] : [])];
    for (const table of tables) {
      channel.on("postgres_changes", { event: "*", schema: "public", table, filter: `user_id=eq.${userId}` }, refresh);
    }
    channel.subscribe((status) => { if (status === "SUBSCRIBED") refresh(); });
    return () => { void supabase.removeChannel(channel); };
  }, [userId, hasPreferences, hasTimes, supabase, refresh]);

  const hasSession = !!data?.active_session;
  useEffect(() => {
    const interval = setInterval(() => setNow(Date.now()), hasSession ? 1000 : 30000);
    return () => clearInterval(interval);
  }, [hasSession]);

  const clock = new Date(now + offset.current);
  // Account-local midnight passed: highlight and "today" move on.
  useEffect(() => {
    if (data && focusLocalDate(new Date(now + offset.current), data.timezone) !== data.local_date) void reload();
  }, [now, data, reload]);

  return { supabase, data, loading, loadError, reload, clock };
}
