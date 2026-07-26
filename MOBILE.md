# ezyReminder — iOS/Android Strategy (no Swift/Kotlin rewrite)

Goal: the webapp should feel native on iOS (and Android) without a rewrite. Two stages — ship Stage 1 with the webapp; adopt Stage 2 only if App Store presence or deeper native hooks become worth it.

## Stage 1: PWA (ships with the webapp, ~1–2 days)

Next.js already supports everything needed:

1. **Web App Manifest** (`app/manifest.ts`): name, icons (180/192/512px + maskable), `display: "standalone"`, theme color per light/dark. Installed via Safari → Share → **Add to Home Screen**; runs full-screen with no browser chrome.
2. **Service worker** (`@serwist/next`): cache app shell + last-fetched reminders → instant launch and read-only offline; queue writes with Background Sync when back online.
3. **Web Push on iOS** (16.4+): works **only when installed to Home Screen**. Use it as a bonus layer — email/Slack/WhatsApp remain the guaranteed channels, so push being best-effort costs nothing.
4. **Native-feel details** (cheap, high impact):
   - `viewport-fit=cover` + safe-area insets (notch/home bar)
   - `-webkit-tap-highlight-color: transparent`, `overscroll-behavior: none`
   - bottom-sheet detail view (thumb-reachable), 44px touch targets
   - `share_target` in manifest → ezyReminder appears in the iOS Share Sheet (share an Etsy order page straight into a Side Gig reminder)
   - App shortcuts in manifest: "New reminder", "Ship Queue"
5. **Install nudge:** small dismissible banner on iOS Safari explaining Add to Home Screen (Apple provides no install prompt API).

**Limitations to accept:** no App Store listing, push requires install, no Siri/widgets.

## Stage 2: Capacitor wrapper (optional, ~2–3 days, still zero rewrite)

[Capacitor](https://capacitorjs.com) wraps the *same* Next.js app in a real native shell — the web code stays the single source of truth.

- **What it adds:** App Store + Play Store listing, reliable APNs/FCM push (no install caveat), badge counts, haptics, local notifications that fire offline, future Siri Shortcut / widget plugins.
- **How:** `npx cap add ios android`; point Capacitor at the deployed web URL (server-rendered mode) or a static export; add `@capacitor/push-notifications` + `@capacitor/local-notifications`; write once, both platforms.
- **Cost:** Apple Developer account ($99/yr), App Store review, Xcode builds (automatable with GitHub Actions + fastlane). Swift/Kotlin exposure is limited to a few generated lines you never touch.

## Decision rule

| Trigger | Move |
|---|---|
| Just you + a few users, channels doing the notifying | Stay Stage 1 (PWA) |
| Want App Store presence, reliable native push, or badge counts | Add Stage 2 (Capacitor) |
| Ever need deep Siri/widgets/Watch | Re-evaluate; still likely Capacitor plugins before any rewrite |

Either way, 100% of product code remains the Next.js webapp.
