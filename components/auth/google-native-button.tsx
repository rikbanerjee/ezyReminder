"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import Script from "next/script";
import { toast } from "sonner";
import { createClient } from "@/lib/supabase/client";

// Minimal shape of the `window.google` Identity Services API we use —
// no official types package for this (it's a plain <script>, not an npm
// module), so this is hand-rolled rather than `any`.
interface GoogleCredentialResponse {
  credential: string;
}

interface GoogleIdentityServices {
  accounts: {
    id: {
      initialize: (config: {
        client_id: string;
        callback: (response: GoogleCredentialResponse) => void;
      }) => void;
      renderButton: (
        parent: HTMLElement,
        options: { theme: string; size: string; width?: number; text?: string },
      ) => void;
    };
  };
}

declare global {
  interface Window {
    google?: GoogleIdentityServices;
  }
}

/**
 * Second, separate Google sign-in path (GOOGLE_NATIVE_SIGNIN_PROMPT.md) —
 * Google Identity Services renders its own button and returns a signed ID
 * token to page JS directly, so the account chooser references this site's
 * own origin instead of the Supabase project domain that
 * `signInWithOAuth`'s redirect flow shows. Deliberately left running
 * alongside the existing `handleGoogleSignIn` button in
 * app/(auth)/login/page.tsx, not replacing it, until this is confirmed
 * working end-to-end.
 */
export function GoogleNativeButton() {
  const containerRef = useRef<HTMLDivElement>(null);
  const router = useRouter();

  useEffect(() => {
    const clientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
    if (!clientId) return;

    let cancelled = false;

    async function handleCredentialResponse(response: GoogleCredentialResponse) {
      const supabase = createClient();
      const { error } = await supabase.auth.signInWithIdToken({
        provider: "google",
        token: response.credential,
      });

      if (error) {
        toast.error("Couldn't sign in with Google", { description: error.message });
        return;
      }

      router.push("/");
    }

    function tryRender() {
      if (cancelled) return;
      if (!window.google || !containerRef.current) {
        // GIS script (loaded via next/script below) hasn't finished yet —
        // keep polling rather than relying on a single onLoad callback,
        // since afterInteractive scripts can resolve before this effect runs.
        window.setTimeout(tryRender, 100);
        return;
      }
      window.google.accounts.id.initialize({
        client_id: clientId!,
        callback: handleCredentialResponse,
      });
      window.google.accounts.id.renderButton(containerRef.current, {
        theme: "outline",
        size: "large",
        width: 320,
        text: "continue_with",
      });
    }

    tryRender();
    return () => {
      cancelled = true;
    };
  }, [router]);

  const clientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
  if (!clientId) {
    return (
      <p className="rounded-md border border-hairline p-2 text-center text-[12px] text-text-2">
        Set NEXT_PUBLIC_GOOGLE_CLIENT_ID to enable the native Google button.
      </p>
    );
  }

  return (
    <>
      <Script src="https://accounts.google.com/gsi/client" strategy="afterInteractive" />
      <div ref={containerRef} className="flex justify-center" />
    </>
  );
}
