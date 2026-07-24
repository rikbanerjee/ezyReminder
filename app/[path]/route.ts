import { createSerwistRoute } from "@serwist/turbopack";

/**
 * Serves the compiled service worker at /sw.js (and its sourcemap) via a
 * dynamic route rather than a static public/ file — @serwist/next's
 * webpack-plugin injection doesn't run under `next build/dev --turbopack`
 * (this repo's build script), so we use @serwist/turbopack's route-handler
 * mode instead. `dynamicParams: false` means any path other than the ones
 * serwist actually built (sw.js, sw.js.map) 404s — this route never
 * shadows the app's other top-level pages/routes, which Next matches first.
 */
export const { dynamic, dynamicParams, revalidate, generateStaticParams, GET } = createSerwistRoute({
  swSrc: "app/sw.ts",
  useNativeEsbuild: true,
  // Override serwist's default target list, which esbuild can't downlevel
  // destructuring for on this esbuild version — modern browsers only,
  // matching the app's own Web Push (iOS 16.4+) baseline anyway.
  esbuildOptions: { target: "es2021" },
});
