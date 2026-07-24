import * as chrono from "chrono-node";
import type { Channel } from "@/lib/supabase/types";

/**
 * Smart-parse for the quick-add box (PLAN.md §5.2, CLAUDE.md UX bar).
 *
 * Turns free text like
 *   "ship mug order to Portland tue 6pm #sidegig @whatsapp"
 * into structured fields. Pure and client-safe so the UI can render parsed
 * chips live *and* the same result is what we persist — no double logic.
 *
 * Tokens (stripped from the resulting title):
 *   #order                 → is_order = true
 *   #<context>             → context, matched against slugs/names/aliases
 *   @email | @slack | @whatsapp → delivery channel override
 *   natural-language dates → due_at (chrono-node), e.g. "tue 6pm", "in 2h"
 */

export interface ParsableContext {
  slug: string;
  name: string;
}

export interface ParsedQuickAdd {
  title: string;
  dueAt: Date | null;
  /** Matched context slug, or null if no #context token resolved. */
  contextSlug: string | null;
  isOrder: boolean;
  channels: Channel[];
  /** True once chrono found a date — lets the UI show a due chip. */
  hasDate: boolean;
}

// Aliases → canonical context slug. Extend as contexts are renamed; unknown
// #tokens simply fall through and stay part of the title.
const CONTEXT_ALIASES: Record<string, string> = {
  work: "work",
  job: "work",
  side: "sidegig",
  sidegig: "sidegig",
  gig: "sidegig",
  etsy: "sidegig",
  social: "social",
  life: "social",
  personal: "social",
  shopping: "shopping",
  shop: "shopping",
  groceries: "shopping",
};

const CHANNEL_ALIASES: Record<string, Channel> = {
  email: "email",
  mail: "email",
  slack: "slack",
  whatsapp: "whatsapp",
  wa: "whatsapp",
  text: "whatsapp",
};

function collapse(text: string): string {
  return text.replace(/\s{2,}/g, " ").trim();
}

export function parseQuickAdd(
  raw: string,
  contexts: ParsableContext[] = [],
): ParsedQuickAdd {
  let working = raw;
  let isOrder = false;
  let contextSlug: string | null = null;
  const channels: Channel[] = [];

  // Build a lookup from every known context slug/name to its slug so a user
  // who renamed "Side Gig" → "Etsy" can type "#etsy".
  const contextLookup: Record<string, string> = { ...CONTEXT_ALIASES };
  for (const c of contexts) {
    contextLookup[c.slug.toLowerCase()] = c.slug;
    contextLookup[c.name.toLowerCase().replace(/\s+/g, "")] = c.slug;
  }

  // @channel tokens
  working = working.replace(/@([a-z]+)/gi, (match, word: string) => {
    const channel = CHANNEL_ALIASES[word.toLowerCase()];
    if (channel) {
      if (!channels.includes(channel)) channels.push(channel);
      return " ";
    }
    return match; // leave unrecognised @handles in the title
  });

  // #tokens: #order flag, otherwise a context reference
  working = working.replace(/#([a-z0-9]+)/gi, (match, word: string) => {
    const lower = word.toLowerCase();
    if (lower === "order" || lower === "ship") {
      isOrder = true;
      return " ";
    }
    const slug = contextLookup[lower];
    if (slug) {
      contextSlug = slug;
      return " ";
    }
    return match; // unknown #tag stays in the title
  });

  // Dates — take the first chrono match, relative to now (browser tz on the
  // client, so "tue 6pm" resolves in the user's local time).
  let dueAt: Date | null = null;
  const results = chrono.parse(working, new Date(), { forwardDate: true });
  if (results.length > 0) {
    const first = results[0];
    dueAt = first.start.date();
    working = working.slice(0, first.index) + " " + working.slice(first.index + first.text.length);
  }

  return {
    title: collapse(working),
    dueAt,
    contextSlug,
    isOrder,
    channels,
    hasDate: dueAt !== null,
  };
}
