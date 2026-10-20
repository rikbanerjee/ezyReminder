import type { MetadataRoute } from "next";

/**
 * Web App Manifest (MOBILE.md Stage 1). Installed via Safari → Share → Add
 * to Home Screen; runs full-screen with no browser chrome. Icons use the
 * approved Chacha bell artwork (design/app-icon.png; npm run icons).
 */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "ezyReminder",
    short_name: "ezyReminder",
    description: "Reminders that reach you — on your phone or by email.",
    start_url: "/",
    display: "standalone",
    background_color: "#F7F6F3",
    theme_color: "#3478F6",
    icons: [
      { src: "/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/icon-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
    shortcuts: [
      { name: "New reminder", url: "/?compose=1" },
      { name: "Ship Queue", url: "/ship-queue" },
    ],
    share_target: {
      action: "/share-target",
      method: "GET",
      params: {
        title: "title",
        text: "text",
        url: "url",
      },
    },
  };
}
