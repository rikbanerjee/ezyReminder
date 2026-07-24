"use client";

import { useEffect } from "react";

/** Registers the serwist-built service worker (MOBILE.md Stage 1). */
export function RegisterServiceWorker() {
  useEffect(() => {
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => {
        // Offline caching is a nice-to-have, not a hard requirement —
        // fail silently rather than surfacing a toast the user can't act on.
      });
    }
  }, []);

  return null;
}
