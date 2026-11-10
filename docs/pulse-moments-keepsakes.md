# Pulse — design principles + Moments & Keepsakes

**Status:** the *principles* (spine, stays-by-default, one-way-broadcast) are
**live** in code. **Moments** and **Keepsakes** are **designed, not built** — this
doc is the spec so they don't drift toward social-media defaults.

> Read this before brainstorming Pulse features. The failure mode is reaching for
> the generic "inverted social media" playbook (ephemerality, decay, BeReal
> prompts, vanity metrics) instead of the actual model below. Anchor here first.

---

## 1. What Pulse is — the inversion

Pulse is **ambient presence and intimacy with your real circle** — the inverse of
broadcast social media on every axis:

| Social media | Pulse |
|---|---|
| Broadcast to the public | Narrowcast to your real graph (contacts − blocks) |
| Follower / like **counts** (clout) | You see *who* — never *how many* |
| Permanent profile grid (a brand) | A private shared **lifeline** you accumulate together |
| Algorithmic feed (engagement bait) | Chronological, your people only |
| Asymmetric (influencers / followers) | Symmetric — you see them iff they see you |
| Perform for an audience | Presence with people you know |

**Litmus test for any feature:** does it deepen *connection with people you know*,
or drift toward *performing for an audience / chasing reach*? If the latter,
reject it — even if it would boost "engagement." The discipline is the product.

---

## 2. The spine — the core metaphor (do not forget)

The feed renders as **one continuous vertical timeline thread** — the *spine*.
Each pulse is a segment: `avatar (40pt anchor) → 1.5pt vertical line → terminator
node-dot`. Stacked, the lines fuse into a single lifeline down the whole feed.
Cardless; one-way-broadcast.

- **The spine is a shared, private lifeline your circle builds together.** It
  doesn't scroll away — it *accumulates*.
- **Stays-by-default.** `expires_at == nil` is a "stays-pulse" — the norm. The
  node-dot draws an unwrapped **stays-ring** to mark it. Disappearing
  (`expires_at` set) is the **rare opt-out**, effectively a noop most posts never
  use; its node draws a depleting **expiry arc**. **No hard delete** (soft-delete
  only). So **everything is the keepsake history.**
- **"In the moment" and "keepsake" are not two modes.** Same post, one spine —
  just *where it sits over time*. Fresh at the top (in the moment), aging down
  into kept history. **Permanence becomes intimate** instead of performative,
  because the audience is only the people who were there.
- **The node-dot is the spine's state-carrier** (`PulseHubFeedDot` /
  `PulseNodeDot`): color = kind, stays-ring = permanent, expiry-arc = countdown,
  grows red when expiring soon. New marks (below) attach **here**, in this
  language — never by forking the spine into separate timelines/modes.

---

## 3. Moments (author-marked)

The author flags **their own** pulse as a **Moment** — "this one's for the books."

- **Presentation, not preservation.** Everything already stays, so a Moment is
  *not* a "keep." It's pure emphasis. Fully decoupled from chat's Keep/Star/Lock.
- **Shared.** Renders **elevated for the whole circle**: the node sits prouder
  (a bold moment emblem on the dot), the card stands taller/fuller. A
  *proclamation* — scroll the lifeline and the big ones sit up.
- **Autobiographical** — the chapters you mark in *your own* life.
- **Human choice, no algorithm.** "baby's here" → yes; "got the job" → maybe;
  the author decides.

---

## 4. Keepsakes (viewer-marked)

A viewer keeps any post (**from others**) onto **their own** spine — "I'm holding
this."

- **Per-viewer, private.** Shows only on *your* view of the spine.
- **No author permission needed.** You can keep the small, *unflagged* things that
  mattered to *you* (a throwaway photo of the two of you) — not just the author's
  declared big moments. This is the most intimate gesture in Pulse.
- **Quiet, tender.** Renders as a **dog-ear / folded corner / ribbon** — the
  gesture of folding down a page in your own book. Not loud.
- **Relational** — the pieces of *other people's* lives you treasure.

---

## 5. Similar but different — proclaimed vs folded-in

Both honor the spine (never fork it) and share the "this is special" family, but
they read in **different registers**:

| | Moment | Keepsake |
|---|---|---|
| Who | Author, of their own post | Viewer, of someone else's |
| Scope | Shared — whole circle sees it | Private — your spine only |
| Feel | **Proclaimed** — outward, proud, loud | **Folded-in** — inward, quiet, tender |
| Kind | Autobiographical | Relational |
| Mark | Bold emblem on the node + fuller card | Dog-ear / ribbon on the card, soft node mark |

A pulse can be **both** — the author proclaimed "baby's here" *and* you kept it,
so on your spine it's both proud and personally folded.

---

## 6. The filters — traveling the spine

Each filter is just "hide the chatter, keep the marked nodes" — the spine
**tightens**, reconnecting the landmark nodes directly. **Same spine, fewer
nodes.** Three states:

- **Live spine** (default) — everything, now flowing into history.
- **My Moments** — collapse to *my* declared Moments → my own highlight thread.
- **My Keepsakes** — collapse to posts I kept from others → the moments of my
  circle I treasure.

**No algorithm.** A normal app's "memories" guesses what mattered; this shows only
what a human marked, by hand — human-curated by definition. The inversion made
literal.

UI: two quiet chips (**Moments · Keepsakes**) off the live spine. **Open
question:** are they toggles on the main feed, or does **Keepsakes** want its own
calmer *room* — a place you go *to remember*, away from the "what's happening now"
energy? (My Moments feels at home in the feed; Keepsakes-of-others may want a
hush.)

---

## 7. Storage shapes — why two features, not one

The two marks are genuinely different *kinds of thing*, which is why two filters
is the honest design, not a UI accident:

- **Moment** = a flag on the pulse, author-set, shared → `pulses.is_moment` (or
  similar). **A property of the post.**
- **Keepsake** = a per-viewer save of someone else's post →
  `pulse_keepsakes(pulse_id, user_id, created_at)`. **A relationship between you
  and a post.**

Implemented in **mvPulse** (the flag + the join table); surfaced in **PulseKit**
(the two node/card marks + the two filters).

---

## 8. Vocabulary — don't collide with chat

- **Chat:** Keep / Star / Lock — *verbs*, "exempt this from disappearing"
  (preservation tiers; designed in the host app's own docs).
- **Pulse:** Moments / Keepsakes — *nouns*, the marked things on the spine
  (emphasis + held memory).

A keepsake is the **treasured object**, not the act of keeping. "I kept this
message" (chat) ≠ "I keepsaked this moment" (pulse). The vocabulary stays crisp
across the app.

---

## 9. Anti-features — protect the thesis (say no on purpose)

Public profiles/grids · follower or like **counts** · algorithmic ranking ·
reshare-to-public / virality · streaks-as-pressure · polls · anything that turns
a friend's glance into a vanity number, or forks the one spine into separate
modes.

---

## Status / next

- **Live:** spine, stays-by-default, one-way-broadcast, kinds, reactions, replies,
  audience, identity-directory avatars.
- **Designed, unbuilt:** Moments (mvPulse `is_moment` flag + PulseKit elevated
  render), Keepsakes (mvPulse `pulse_keepsakes` table + PulseKit dog-ear render),
  the two filters.
- **Open:** whether Keepsakes lives as a feed filter or its own room; the exact
  node/card visuals for each mark.
