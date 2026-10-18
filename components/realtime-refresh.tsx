"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

const TABLES = [
  "reminders",
  "orders",
  "shopping_items",
  "work_details",
  "sidegig_details",
  "contexts",
  "home_maintenance",
  "home_service_records",
] as const;

/** Refresh server-rendered data after this user's Supabase changes or when the tab resumes. */
export function RealtimeRefresh() {
  const router = useRouter();

  useEffect(() => {
    const supabase = createClient();
    let active = true;
    let activeUserId: string | null = null;
    let channel: ReturnType<typeof supabase.channel> | null = null;
    let refreshTimer: ReturnType<typeof setTimeout> | null = null;

    const scheduleRefresh = () => {
      if (refreshTimer) clearTimeout(refreshTimer);
      refreshTimer = setTimeout(() => {
        refreshTimer = null;
        if (active) router.refresh();
      }, 120);
    };

    const subscribeForUser = (userId: string | null) => {
      if (userId === activeUserId) return;
      activeUserId = userId;
      if (channel) {
        void supabase.removeChannel(channel);
        channel = null;
      }
      if (!userId || !active) return;

      let nextChannel = supabase.channel(`web-sync-${userId}`);
      for (const table of TABLES) {
        nextChannel = nextChannel.on(
          "postgres_changes",
          { event: "*", schema: "public", table, filter: `user_id=eq.${userId}` },
          scheduleRefresh,
        );
      }
      channel = nextChannel;
      void channel.subscribe((status) => {
        // Reconnects also report SUBSCRIBED; refresh once to recover events missed offline.
        if (status === "SUBSCRIBED") scheduleRefresh();
      });
    };

    const authListener = supabase.auth.onAuthStateChange((_event, session) => {
      const nextUserId = session?.user.id ?? null;
      const changed = nextUserId !== activeUserId;
      subscribeForUser(nextUserId);
      if (changed) scheduleRefresh();
    });

    void supabase.auth.getSession().then(({ data }) => {
      if (active) subscribeForUser(data.session?.user.id ?? null);
    });

    const refreshOnResume = () => {
      if (document.visibilityState === "visible") scheduleRefresh();
    };
    window.addEventListener("focus", scheduleRefresh);
    window.addEventListener("online", scheduleRefresh);
    document.addEventListener("visibilitychange", refreshOnResume);

    return () => {
      active = false;
      authListener.data.subscription.unsubscribe();
      window.removeEventListener("focus", scheduleRefresh);
      window.removeEventListener("online", scheduleRefresh);
      document.removeEventListener("visibilitychange", refreshOnResume);
      if (refreshTimer) clearTimeout(refreshTimer);
      if (channel) void supabase.removeChannel(channel);
    };
  }, [router]);

  return null;
}
