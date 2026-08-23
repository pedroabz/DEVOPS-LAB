---
description: Write a plain-language explainer on an Azure topic — how it works, the trade-offs, and what each Bicep setting actually does
---

# Deep dive

Topic: **$ARGUMENTS** (if empty, ask what to cover.)

Write the doc Pedro needs to *understand* this topic well enough to decide what belongs in
`devops-lab`. He's strong on software architecture, new to Azure. Assume intelligence, assume no
Azure background.

Output goes in `docs/<topic>-explained.md`, matching the existing files there.

---

## Rules

1. **Verify, don't remember.** Every factual claim — tier limits, minimum sizes, which SKU has which
   feature, prices — gets checked against `learn.microsoft.com` or the Retail Prices API **in this
   run**. Azure changes, and a confidently wrong claim in a doc is worse than no doc. If you can't
   verify something, say so in the text.
2. **Plain language.** Short sentences. Contractions fine. No "leverage", "utilise", "robust",
   "seamless". Write like you're explaining it at a desk, not presenting to a board.
3. **Explain the model before the syntax.** People get stuck on *why does this even exist*, not on
   property names. Lead with the problem the thing solves.
4. **Name the trap.** Every Azure feature has one thing that silently doesn't work if you get it
   wrong. Find it and make it prominent. That's usually the most valuable paragraph in the doc.
5. **Recommend, don't decide.** End with what you'd do and why. Clearly a recommendation. He decides.
6. **Don't write any Bicep into the repo.** This command produces understanding, not resources. Use
   `/add-resource` afterwards.
7. **Split if it's big.** More than ~250 lines means it's really 2–3 topics. Split them, number them
   ("Part 2 of 3"), and cross-link at the top of each.

---

## Structure

Adapt as the topic needs, but cover these:

**The problem** — what goes wrong without this thing. Concretely, in this project's terms.

**How it actually works** — the mental model. Diagrams as ASCII if they help. Say plainly what it
*doesn't* do, because that's usually where the misunderstanding lives.

**The trap** — the thing that looks configured but silently isn't. Include how to tell whether it's
actually working, ideally a test that fails the way a misconfiguration would.

**What you configure in Bicep** — a table per resource type:

| Property | What it does | For us |
|---|---|---|

Cover the properties that *change behaviour*. Include ones you'd deliberately leave unset and say
why. Skip anything irrelevant at this scale rather than listing the whole schema.

**Trade-offs** — what you gain, what it costs (money *and* complexity *and* new failure modes), and
what it explicitly doesn't buy you.

**What I'd do here** — a short list, specific to `devops-lab`, referencing the resource inventory row
numbers in `docs/prd/v0-foundations.md` where relevant.

---

## After writing

Report in a few lines:

- Which files you created
- Anything that contradicts the PRD, README, or an existing doc — **ask** whether to change the doc
  or the decision, don't fix it
- Anything you couldn't verify
- Whether the inventory needs a new row

Don't commit.
