const INTERNAL_ORIGIN = "https://ezyreminder.invalid";

/** Accept only same-origin path targets for post-auth redirects. */
export function safeInternalPath(value: string | null | undefined, fallback = "/"): string {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\") || /[\u0000-\u001f\u007f]/.test(value)) {
    return fallback;
  }

  try {
    const target = new URL(value, INTERNAL_ORIGIN);
    if (target.origin !== INTERNAL_ORIGIN || target.pathname.startsWith("//")) return fallback;
    return `${target.pathname}${target.search}${target.hash}`;
  } catch {
    return fallback;
  }
}

/** Read the middleware's return target at the point a user starts authentication. */
export function currentAuthReturnPath(): string {
  if (typeof window === "undefined") return "/";
  return safeInternalPath(new URLSearchParams(window.location.search).get("next"));
}
