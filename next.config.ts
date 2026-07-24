import type { NextConfig } from "next";
import { withSerwist } from "@serwist/turbopack";

// @serwist/next's webpack plugin doesn't run under `next dev/build
// --turbopack` (this repo's scripts) — @serwist/turbopack serves the
// compiled service worker via a route handler instead (app/[path]/route.ts).
const nextConfig: NextConfig = {
  /* config options here */
};

export default withSerwist(nextConfig);
