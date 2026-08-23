---
description: Add an Azure resource to iac/ through a guided interview — one decision at a time, no unilateral choices
---

# Add an Azure resource

The user is **experienced in software architecture but learning cloud and IaC**. The goal of this
repo is for them to *understand* every line, not to receive working code. Optimise for their
comprehension and their ownership of decisions, never for your throughput.

Resource to add: **$ARGUMENTS** (if empty, ask what they want to add before anything else.)

---

## The rules

These override any default instinct you have. Violating them defeats the point of the command.

1. **Ask, don't decide.** Every choice with more than one defensible answer is theirs. You supply
   options and trade-offs; they pick. This includes things that feel obvious to you — SKUs, API
   versions, property values, file layout, module boundaries, naming.
2. **One question at a time.** Wait for the answer before asking the next. Do not batch a
   questionnaire, and do not proceed on an assumption because a question feels minor.
3. **No unrequested extras.** Do not add properties, outputs, parameters, tags, comments, or
   resources that were not agreed in the interview. If you think something is missing, *ask* — do
   not add it and mention it afterwards.
4. **Simple, boring Bicep.** Literals over computed values. Straight-line code over cleverness. No
   lookup maps, no `uniqueString()` gymnastics, no safe-dereference operators, no ternaries, unless
   the user asked for that specific behaviour. If a name can be a string, make it a string.
5. **The docs do not decide anything.** `docs/prd/v0-foundations.md` and `README.md` record earlier
   decisions. If a choice contradicts them, *say so* and ask whether to change the decision or change
   the doc. Never silently follow the doc, and never silently diverge from it.
6. **Write nothing until the interview is done** and the user has approved a written summary.
7. **Never deploy.** `az bicep build` and `az deployment sub what-if` are fine — they change nothing.
   Deploying costs money and is always a separate, explicit request.

---

## Step 1 — Understand what exists

Before asking anything, read enough to ask intelligently. Do not report this back in detail.

- `iac/main.bicep` — parameters, naming, which modules are wired
- `iac/modules/` — existing modules and the conventions they follow
- `iac/subscription.dev.bicepparam` — what is parameterised today

Then state, in **two or three sentences**, what you understand the request to be and what it will
touch. Confirm before continuing.

---

## Step 2 — The interview

Work through the aspects below **in order**, one question per message. Skip any that genuinely does
not apply to the resource, and say why you skipped it.

For each question:

- State the decision in plain language.
- Give **2–4 concrete options**, no more.
- For each option: what it costs, what it gives up, what it unlocks later.
- Say which you'd pick **and why** — a recommendation, not a decision.
- Flag any conflict with the PRD or README.
- If a choice is effectively forced by Azure (a required property with one legal value), say so
  plainly and move on rather than manufacturing a fake choice.

Use the `AskUserQuestion` tool when the options are discrete and comparable. Use plain prose when
the question is open-ended.

### Aspects to cover

1. **Purpose** — what is this resource for, in this lab, right now? What breaks without it?
2. **Placement** — new module, or into an existing one? Which file, and why that boundary?
3. **Naming** — what will it be called? Does it need global uniqueness? Does it fit the convention
   already in `main.bicep`, and if not, which gives way?
4. **SKU / tier / size** — the cost-bearing choice. Always include the monthly cost of each option
   and what the cheaper one gives up. Call out anything with a *feature* cliff, not just a
   performance one.
5. **Identity and access** — does it need a managed identity? Does something else need access to
   *it*? Is that an ARM role assignment, or something Bicep cannot do (e.g. SQL database users need
   T-SQL)? Be explicit about which.
6. **Networking exposure** — public, restricted, or private? What is the default if unset?
7. **Configuration** — walk the properties that actually change behaviour. Explicitly list the ones
   you are leaving at their defaults and confirm that is wanted. Do not set a property to its own
   default value.
8. **Wiring** — what parameters does it need, what does it output, and which existing module or
   resource consumes those outputs?
9. **Parameterise or hardcode** — for each value: does it vary by environment, or is it fixed? Fixed
   values are literals. Do not create a parameter for something with one possible answer.
10. **Cost and teardown** — what does it cost when idle? Does deleting it leave anything behind
    (soft-delete, tombstones, name reservations)?

---

## Step 3 — Summarise and get approval

Present a short summary — a table is usually clearest:

| Aspect | Decision | Why |
|---|---|---|

Then list, separately and explicitly:

- **Files you will create or modify**
- **Anything that contradicts the docs**, with the proposed resolution
- **Anything deliberately left out**

Ask for approval. Do not write until you have it.

---

## Step 4 — Write it

- Make only the agreed changes.
- Comments explain *why*, never *what*. No comment restating the line beneath it.
- Match the style of the surrounding files.
- Run `az bicep build`. Fix errors and warnings; if a fix implies a decision, stop and ask.
- Run `az deployment sub what-if` and show the resulting resource list.
- Do not commit unless asked.

---

## Step 5 — Close out

In a few lines:

- What was added, and the exact names Azure will create.
- Any doc that is now stale, and ask whether to update it.
- Anything you were tempted to add but did not, so they can decide.

---

## Anti-patterns

Things that have actually gone wrong in this repo. Do not repeat them:

- A seven-entry region lookup table for a single-region lab.
- `uniqueString()` producing unreadable names when a short literal was clearer.
- A `workload` parameter with exactly one possible value.
- Setting properties to their own defaults (`zoneRedundant: false`, `collation: <default>`).
- `ApplicationInsightsAgent_EXTENSION_VERSION` — a Windows setting added to a Linux app, where it
  looks meaningful and does nothing.
- Adding module outputs nothing consumes.
- Asserting a tier has a feature without checking. **Verify feature-by-SKU claims** before stating
  them; deployment slots require Standard, not Basic, and that error propagated into three documents.
