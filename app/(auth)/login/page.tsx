"use client";

import { useState } from "react";
import { toast } from "sonner";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<"idle" | "sending" | "sent">("idle");
  const [googlePending, setGooglePending] = useState(false);

  async function handleGoogleSignIn() {
    setGooglePending(true);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${window.location.origin}/auth/callback`,
      },
    });

    if (error) {
      setGooglePending(false);
      toast.error("Couldn't sign in with Google", { description: error.message });
    }
    // On success, Supabase redirects to Google — no local state to update.
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!email) return;

    setStatus("sending");
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
      },
    });

    if (error) {
      setStatus("idle");
      toast.error("Couldn't send the link", { description: error.message });
      return;
    }

    setStatus("sent");
  }

  return (
    <main className="flex h-full min-h-0 items-center justify-center overflow-y-auto px-4">
      <Card className="w-full max-w-sm border-hairline">
        <CardHeader>
          <CardTitle className="text-2xl font-bold tracking-tight">
            ezyReminder
          </CardTitle>
          <CardDescription>
            {status === "sent"
              ? `Check ${email} for a sign-in link.`
              : "Sign in with a magic link — no password to remember."}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {status === "sent" ? (
            <Button
              variant="outline"
              className="w-full"
              onClick={() => setStatus("idle")}
            >
              Use a different email
            </Button>
          ) : (
            <div className="flex flex-col gap-4">
              <Button
                type="button"
                variant="outline"
                className="w-full"
                disabled={googlePending}
                onClick={handleGoogleSignIn}
              >
                <GoogleIcon className="size-4" />
                {googlePending ? "Redirecting…" : "Continue with Google"}
              </Button>

              <div className="flex items-center gap-3 text-[12px] text-text-2">
                <div className="h-px flex-1 bg-hairline" />
                or
                <div className="h-px flex-1 bg-hairline" />
              </div>

              <form onSubmit={handleSubmit} className="flex flex-col gap-4">
                <div className="flex flex-col gap-2">
                  <Label htmlFor="email">Email</Label>
                  <Input
                    id="email"
                    type="email"
                    inputMode="email"
                    autoComplete="email"
                    placeholder="you@example.com"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                    autoFocus
                  />
                </div>
                <Button type="submit" disabled={status === "sending"} className="w-full">
                  {status === "sending" ? "Sending…" : "Send magic link"}
                </Button>
              </form>
            </div>
          )}
        </CardContent>
      </Card>
    </main>
  );
}

function GoogleIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} aria-hidden>
      <path
        fill="#4285F4"
        d="M23.52 12.27c0-.85-.08-1.67-.22-2.45H12v4.64h6.47c-.28 1.5-1.13 2.77-2.4 3.62v3h3.89c2.28-2.1 3.56-5.2 3.56-8.81Z"
      />
      <path
        fill="#34A853"
        d="M12 24c3.24 0 5.96-1.07 7.95-2.92l-3.89-3c-1.08.72-2.46 1.15-4.06 1.15-3.13 0-5.78-2.11-6.73-4.95H1.26v3.11C3.24 21.3 7.31 24 12 24Z"
      />
      <path
        fill="#FBBC05"
        d="M5.27 14.28A7.2 7.2 0 0 1 4.87 12c0-.79.14-1.56.4-2.28V6.61H1.26A11.98 11.98 0 0 0 0 12c0 1.94.46 3.77 1.26 5.39l4.01-3.11Z"
      />
      <path
        fill="#EA4335"
        d="M12 4.77c1.76 0 3.34.6 4.58 1.79l3.44-3.44C17.95 1.19 15.24 0 12 0 7.31 0 3.24 2.7 1.26 6.61l4.01 3.11C6.22 6.88 8.87 4.77 12 4.77Z"
      />
    </svg>
  );
}
