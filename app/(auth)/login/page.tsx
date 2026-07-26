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
            easyReminder
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
          )}
        </CardContent>
      </Card>
    </main>
  );
}
