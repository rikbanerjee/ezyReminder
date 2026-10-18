# ezyReminder — Launch Strategy

**Written 2026-07-27. Goal: 50 real users (strangers, not friends) by 2026-10-25.**

> **Update 2026-10:** Slack delivery was removed and the native iOS app is now a Flutter build (see MOBILE.md). Slack-related items below (distribution, Wedge A, free-tier channels) and §4's "skip the App Store" advice are superseded.

Companion to `PLAN.md` (product), `DESIGN.md` (UI), `MOBILE.md` (native strategy). This doc covers positioning, the domain decision, the pre-launch blocker list, and the 90-day sequence.

---

## 0. Where we actually are

| Phase | Status |
|---|---|
| 0 — Scaffold, auth, RLS | ✅ done |
| 1 — Core loop, contexts, sheet-based create | ✅ done |
| 2 — Delivery (Resend email, sweep; Slack removed 2026-10) | ✅ done (sweep on 5-min cron; email auto-snooze 0013) |
| 3 — Orders / Ship Queue | ✅ done |
| 4 — PWA (manifest, serwist, share_target) | ✅ done |
| 5 — WhatsApp (Twilio) | ⬜ not started |
| 6 — Agents (REST API keys + MCP) | ⬜ not started (`api_keys` table exists) |
| 7 — Shippo | ⬜ not started |
| Flutter iOS app (`mobile/`) | 🟡 built locally on `ios-mvp`; APNs transport proof + TestFlight pending |
| Home view (household sections, 0011/0014) | 🟡 migrations hosted; web + Flutter client release pending |
| Focus MVP (highlight + sessions, 0012) | 🟡 migration hosted; client release + signed-in web↔iPhone handoff pending |
| Focus times (FOCUS_IMPLEMENTATION_PLAN.md §13) | 🟡 Phase 0/1 + slim Phase 2 built on web + Flutter (2026-10-18); migrations 0015/0016 local only — hosted apply, release and handoff test pending. Clients fall back to the MVP until applied |

**The architecture is already multi-user.** RLS on every table, per-user Slack OAuth (`slack_integrations`), new-user seeding triggers for contexts and settings. There is no "make it multi-tenant" project. What's missing is the *operational* layer strangers need: deliverability, onboarding, quotas, legal pages, analytics.

**Web push is not implemented at all** — zero references to VAPID / `pushManager` / `web-push` in the tree. The PWA is install-and-cache only.

---

## 1. The domain question: keep them separate

**Recommendation: separate domains. Do not merge ezyReminder and ezyUpload.**

Both products are pre-launch with zero users, which removes the only good reason to merge — there's no traffic or domain authority to pool. What's left is cost (~$12/year, irrelevant) and "suite" coherence (a story that only matters to you, not to a stranger).

The costs of merging are real and immediate:

- **A shared domain forces a shared pitch.** "ezy — a suite of small tools" converts nobody. "Reminders that get delivered to your Slack DMs, not buried in an app you never open" converts someone. At 50 users the *only* thing that matters is a sentence a stranger repeats to a friend, and `ezy.app/reminder` is not repeatable out loud.
- **Different audiences, different launch venues.** The seller/side-gig communities where ezyReminder gets found are not where ezyUpload gets found. One domain means one landing page trying to do two jobs badly.
- **Shared auth is coupling, not leverage.** One Supabase project across both products means a schema migration or an RLS mistake in one takes down the other. At zero users the flexibility is worth more than the SSO.
- **Merging is reversible; splitting later is not.** If ezyReminder gets to 500 users you can always put ezyUpload on a subdomain under the winning brand. Going the other direction means breaking links and re-earning trust.

**Do this instead:** buy `ezyreminder.app` (or `.com`), point it at the existing Vercel project, and revisit a suite only if one product finds traction *and* the audiences turn out to overlap. Keep the visual language consistent across both so the suite story is available later at no cost today.

---

## 2. Positioning: pick one wedge

The category is brutal — Apple Reminders is free and preinstalled, Todoist and TickTick have a decade of head start. You do not win on "better reminders." You win by being *obviously for someone specific*.

There are two wedges in the current build. **Pick the second one for launch:**

**Wedge A — Slack DM delivery.** "Reminders that reach you where you already are." True and differentiated, but Slack reminders already exist natively, and the audience ("people who use Slack") is too broad to target.

**Wedge B — the day-job-plus-side-hustle operator.** ✅ **Use this.** "You have a 9-to-5 and you sell on Etsy at night. ezyReminder keeps the two from bleeding into each other — and DMs you the ship-by dates so orders don't slip." This wins because:

- It's a **findable audience**: Etsy/eBay/Depop seller subreddits, Shopify Discords, print-on-demand Facebook groups, r/sidehustle.
- It's a **real pain Apple Reminders can't touch**: the Ship Queue, order refs, recipients, ship-by dates. A generic todo app has no answer for "which of my 6 open orders needs a label today."
- It has a **built-in expansion path to revenue**: Shippo (Phase 7) turns the Ship Queue into label purchase, which is a thing people pay for.

Contexts (Work / Side Gig / Social / Shopping) stop being a feature list and become the proof you understand the person. Lead with the Ship Queue screenshot, not the reminder list.

**Landing page headline to test:** *"Your day job and your side hustle, finally in separate boxes — with reminders that DM you before an order slips."*

---

## 3. Pre-launch blockers

Ordered by lead time, not importance. **The two items with external review queues go first** — start them the day you read this, because you cannot compress someone else's turnaround.

### Long-lead (start immediately)

1. **Resend sending domain + SPF/DKIM/DMARC.** Right now `RESEND_FROM_EMAIL` is presumably a shared/test sender. Email is the guaranteed delivery channel for every context, and if it lands in spam users churn *silently* — they never tell you, they just stop. Verify `mail.ezyreminder.app`, set DMARC to `p=none` initially, and confirm inbox placement to Gmail/Outlook/iCloud before a single stranger signs up.
2. **Slack public distribution.** Your app is almost certainly a single-workspace dev app today. [Enabling public distribution](https://api.slack.com/start/distributing) is a self-serve toggle, but it requires OAuth redirect URLs configured and no hardcoded tokens anywhere. **You do not need Slack Marketplace review to get to 50 users** — Marketplace listing is a separate, much heavier process with a Security & Compliance questionnaire. Skip it until you have traction; a plain "Add to Slack" install link is enough.

### Google OAuth — smaller problem than it looks

The infamous 100-user cap applies to **sensitive or restricted scopes** (Gmail, Drive, Calendar, Contacts). ezyReminder only requests `openid`/`email`/`profile` for sign-in, which are non-sensitive — so **no cap and no "unverified app" warning screen applies to you.** You still want a privacy policy URL and proper branding on the consent screen so it looks legitimate, but this is cosmetic, not a gate. Don't burn a week on verification you don't need.

### Must-fix before a public link

3. **Onboarding / first-run.** There is no onboarding code in the tree. Today a new user signs up and lands on an empty screen — the single highest-leverage churn fix you have. Minimum: seed one example reminder per context on signup, and a one-screen "how do you want to be reminded?" step that pushes them to connect Slack or confirm their email before they leave. A user who never connects a channel never experiences the product.
4. **Quotas and abuse limits.** A public signup form wired to an email sender is a spam vector, and one abuse incident can get your Resend domain blocked. Cap reminders per user per day (start at 50) and notifications per user per hour. Cheap to add, expensive to skip.
5. **Privacy policy + Terms.** Required for the Slack install flow and for looking like a real product. Two static pages.
6. **Analytics.** You cannot steer toward 50 users blind. PostHog free tier: track signup → context connected → first reminder created → first reminder *delivered* → day-7 return. The funnel step that matters most is **first successful delivery**, because that's the moment the product's promise becomes real.
7. **Error monitoring on the sweep.** The `pg_cron` → Edge Function sweep is the heart of the product. If it silently dies at 3am, every user's reminders vanish and you find out from a complaint. Add a dead-man's-switch (healthchecks.io free tier) plus Sentry on the function.

### Credibility gaps (fix during weeks 5-8, not before)

8. **Recurring reminders.** `recurrence` is in the schema as an rrule string but there's no UI or sweep handling. For a reminder app this reads as broken to a new user — "remind me every Monday" is table stakes. Not a launch blocker for 10 hand-held users; is a blocker before a public post.
9. **Snooze from email.** Slack has action buttons; email should have equivalent one-click done/snooze links. Email is the default channel for the Side Gig context — your launch audience.

---

## 4. Push and mobile: do the cheap half, skip the expensive half

You flagged native push as blocking. Split it:

**Do: Web Push (~1-2 days).** VAPID keys, `pushManager.subscribe`, a `push_subscriptions` table, and a branch in the existing notification adapter interface (`send(reminder, channel)`) so push is just another channel. On iOS this works only when the PWA is installed to the Home Screen — which is fine, because it's a bonus layer. Email and Slack remain the guaranteed channels.

**Don't: Capacitor / App Store (for now).** `MOBILE.md` already frames this correctly as Stage 2. Understand what it will and won't do for this goal: **an App Store listing will not bring you 50 users.** Nobody browses the store for an unknown reminder app. Your first 500 users arrive via a link from a community post. Capacitor costs an Apple Developer account, review cycles, and Xcode build infrastructure — roughly a 2-3 week detour that produces zero acquisition. Revisit when a real user asks for it, or past ~200 users.

The deeper point: **the whole premise of this product is that the app comes to you.** If push is what makes it usable, the delivery channels aren't working — and delivery is the actual product. Fix delivery quality first.

---

## 5. The 90-day sequence

### Weeks 1-2 — Make it safe to hand to a stranger

Domain purchase and DNS. Resend domain verification and inbox-placement testing. Slack public distribution enabled. Privacy/Terms pages. PostHog + Sentry + healthchecks on the sweep. Onboarding first-run flow. Per-user quotas. Landing page with the Ship Queue as the hero screenshot.

*Exit criteria: you can post the URL publicly without anything embarrassing or dangerous happening.*

### Weeks 3-4 — Ten users you talk to by name

Do not post publicly yet. Recruit 10 people individually — friends who sell things, one or two from a seller Discord you're already in, anyone with a day job and a side hustle. **Watch at least three of them sign up on a call.** You will learn more in those three sessions than from the next 200 signups.

Instrument ruthlessly and answer one question: *do they still have reminders being delivered on day 7?* Retention at day 7 is the only number that matters at this stage. If it's near zero, the problem is positioning or delivery quality, and no amount of launch marketing fixes it.

*Exit criteria: 5+ of 10 still receiving and completing reminders on day 7.*

### Weeks 5-8 — Fix what they screamed about, then ship recurrence + push

Build recurring reminders, email action links, and Web Push. Beyond that, build only what the 10 users actually asked for — resist the roadmap. WhatsApp (Phase 5) is explicitly *not* here: it's Twilio template approval friction for a channel nobody has asked for yet.

*Exit criteria: no P0 complaints outstanding from the first cohort.*

### Weeks 9-12 — Public launch, in waves

Do not launch everywhere at once — you get one shot per channel and you want to sequence them so each wave's feedback improves the next.

1. **Niche communities first (week 9).** Etsy/eBay/Depop seller subreddits, Shopify and print-on-demand Discords, seller Facebook groups. **The rule: participate, don't drop links.** Reddit self-promo gets you banned and it deserves to. Find the recurring "how do you track your orders?" threads and answer them usefully, mentioning what you built only where it's genuinely the answer. This is slow and it is the highest-quality traffic you will get.
2. **Show HN (week 10).** The Slack-DM-delivery and agent-API angles play well with that audience. Title it around the specific mechanic, not the category.
3. **Product Hunt (week 11).** Modest, real, and mostly useful for the backlink and social proof.
4. **The MCP server (Phase 6) is a distribution channel, not just a feature.** A listed MCP server puts you in front of Claude and Cursor users who are actively looking for tools to wire in. It's underrated as acquisition and it's already half-built (`api_keys` table exists). Consider pulling it forward to week 11.
5. **Build in public** on X/LinkedIn throughout — the "day job + side hustle" story *is* your story, which makes it credible rather than marketing.

---

## 6. Pricing: not yet

Stay free through 50 users. You are buying information, not revenue, and a price tag suppresses the signal you need. Do not build billing in the first 90 days.

When you do (and design toward it now): free tier covers email + Slack with a reminder cap; paid at roughly $4-5/month adds WhatsApp, unlimited reminders, and eventually Shippo label purchase. The Shippo integration is the strongest paid hook because it saves money and time in a way a reminder never will.

---

## 7. What would make me wrong

Stated plainly so you can check it against reality rather than trusting the doc:

- **If the side-gig framing doesn't land in seller communities**, the wedge is wrong, not the execution. The signal will be visible by week 9-10 — a genuinely useful reply in a seller thread should draw curiosity. Silence means the pain isn't where you think it is, and the pivot is toward Wedge A (Slack delivery for knowledge workers) rather than more features.
- **If day-7 retention in the first cohort is near zero**, stop and do not launch publicly. Something in the delivery loop or the daily habit is broken, and public traffic would just burn the audience.
- **If people ask for the App Store unprompted and repeatedly**, my advice in §4 is wrong for your users — go build the Capacitor wrapper.
- **Someone will disagree with the domain call** on the grounds that a suite compounds: one brand, one login, cross-promotion between tools, and less overhead maintaining two identities. That's a legitimate argument and it's how Basecamp/37signals-style shops operate. It's a stronger argument once *either* product has users to cross-promote to — which is exactly the condition that doesn't hold today. Revisit at 500 users on either side.
