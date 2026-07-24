/// <reference lib="webworker" />
/**
 * Service worker (MOBILE.md Stage 1, CLAUDE.md-decided: @serwist/next).
 * Caches the app shell + static assets for instant launch and read-only
 * offline; reminder data is fetched fresh whenever online (no queued
 * writes yet — that's a later MOBILE.md stretch, not in this pass).
 */
import { defaultCache } from "@serwist/next/worker";
import type { PrecacheEntry, SerwistGlobalConfig } from "serwist";
import { Serwist } from "serwist";

declare global {
  interface WorkerGlobalScope extends SerwistGlobalConfig {
    __SW_MANIFEST: (PrecacheEntry | string)[] | undefined;
  }
}

declare const self: ServiceWorkerGlobalScope;

const serwist = new Serwist({
  precacheEntries: self.__SW_MANIFEST,
  skipWaiting: true,
  clientsClaim: true,
  navigationPreload: true,
  runtimeCaching: defaultCache,
});

serwist.addEventListeners();
