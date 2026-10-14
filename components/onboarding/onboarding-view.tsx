"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { Check, Mail } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { completeOnboarding } from "@/app/actions";

export function OnboardingView({ email }: { email: string }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  function finish() {
    startTransition(async () => {
      await completeOnboarding();
      router.push("/");
    });
  }

  return (
    <Card className="w-full max-w-sm border-hairline">
      <CardHeader>
        <CardTitle className="text-2xl font-bold tracking-tight">How do you want to be reminded?</CardTitle>
        <CardDescription>
          We&apos;ve added one example reminder per context so you can see how it works. Reminders arrive by email
          for now — the iPhone app adds notifications on your phone.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="flex flex-col gap-3">
          <div className="flex items-center justify-between rounded-lg border border-hairline p-3">
            <div className="flex items-center gap-2 text-[14px]">
              <Mail className="size-4 text-text-2" />
              <span>
                Email <span className="text-text-2">— {email}</span>
              </span>
            </div>
            <span className="flex items-center gap-1 text-[12px] font-medium text-work">
              <Check className="size-3.5" />
              Ready
            </span>
          </div>

          <Button className="mt-2 w-full" disabled={pending} onClick={finish}>
            Continue
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
