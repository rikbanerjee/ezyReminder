import type { Metadata, Viewport } from "next";
import { ThemeProvider } from "@/components/theme-provider";
import { Toaster } from "@/components/ui/sonner";
import { RegisterServiceWorker } from "@/components/register-sw";
import { InstallNudge } from "@/components/install-nudge";
import "./globals.css";

export const metadata: Metadata = {
  title: "easyReminder",
  description:
    "Reminders that reach you — email, Slack, or WhatsApp — for people juggling a job and side gigs.",
  icons: {
    icon: [
      { url: "/icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [{ url: "/apple-icon.png", sizes: "180x180", type: "image/png" }],
  },
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "easyReminder",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#F7F6F3" },
    { media: "(prefers-color-scheme: dark)", color: "#111113" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="antialiased">
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          {/* The app "frame" (DESIGN.md — matches design/prototype.html's
              .frame). Edge-to-edge on phone widths; on wider viewports it
              becomes a bounded, rounded, shadowed card floating on
              --page-backdrop, which is what gives the app a visible outer
              boundary instead of blending into the page.

              Fixed height (h-dvh, not min-h-dvh) is deliberate: it's what
              lets each page split into a non-scrolling header, an
              independently-scrolling content area (flex-1 min-h-0
              overflow-y-auto), and a bottom dock that stays a normal
              (non-scrolling) flex sibling after it — so the dock is always
              pinned at the bottom with content scrolling above it, never
              floating mid-page when content is short. `relative` +
              `overflow-hidden` is also what correctly clips ReminderSheet
              (absolute inset-0) to the frame's rounded bounds instead of
              the raw viewport. */}
          <div className="relative mx-auto flex h-dvh w-full flex-col overflow-hidden bg-background min-[480px]:my-6 min-[480px]:h-[calc(100dvh-3rem)] min-[480px]:max-w-[420px] min-[480px]:rounded-[44px] min-[480px]:border-[8px] min-[480px]:border-neutral-900 min-[480px]:shadow-[0_24px_80px_rgba(0,0,0,0.35)]">
            {children}
          </div>
          <Toaster position="bottom-center" />
          <RegisterServiceWorker />
          <InstallNudge />
        </ThemeProvider>
      </body>
    </html>
  );
}
