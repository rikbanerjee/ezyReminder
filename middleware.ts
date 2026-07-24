import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    /*
     * Match all request paths except:
     * - _next/static, _next/image (Next.js internals)
     * - favicon.ico, manifest/icons, and other static assets
     * - sw.js / sw.js.map (service worker — a redirect response breaks
     *   `navigator.serviceWorker.register`; served via app/[path]/route.ts)
     * - /api/v1 (agent-facing REST API authenticates via bearer key, not cookies)
     */
    "/((?!_next/static|_next/image|favicon.ico|sw\\.js|sw\\.js\\.map|api/v1|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico|json|webmanifest)$).*)",
  ],
};
