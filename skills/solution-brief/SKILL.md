---
name: solution-brief
version: 1.0.0
description: Create, fill in, review or update a Volta Solution Brief, the internal page that sits between a customer-confirmed Problem Brief and /scope. Volta sets it up with the target and constraints, the assigned builder fills in how they'll solve it (options, approach, feasibility and usability risks, increments, verification) with this skill as a one-question-at-a-time guide that challenges but never hands them the answer, and Volta reviews it, rates value and viability risk, and approves it to 1.0 before any /scope run. Use whenever someone says "solution brief", "brief the builder", "hand this to a builder", "how are we going to solve this", "help me work out my approach", "review the builder's brief", or a problem brief is confirmed and work is about to be scoped, even if they don't name the skill. Also use to update a brief after a test result or a change in approach. Not for the customer-facing problem page (/problem-brief), product requirements (/scope), technical design (/document), or proposals with pricing (/generate-proposal).
---

# Solution Brief

The Solution Brief is the page the builder writes, and Volta approves, before any development skill runs on a customer problem. It answers one question: **how will the builder solve this problem, and how will we all know it worked?**

```text
/problem-brief (customer confirms the problem and target)
  -> /solution-brief: Volta sets up -> builder fills in -> Volta reviews and approves
  -> /scope, once per increment -> /document -> /orchestrate -> /ship-it
```

The builder is given a problem, not a solution. Their job is to devise the approach and supply what we need to judge it. Volta's job is to set the target and the limits, then judge whether the approach is worth doing and can last.

**Every run ends with the page, built from `assets/solution-brief-template.html`.** If something is unknown, the page shows the gap.

## Who owns what

| Part of the page | Written by | When |
|---|---|---|
| Problem brief link, target, constraints (security, systems, guardrails) | Volta | Set up |
| Options, approach, why it moves the metric | Builder | Fill in |
| **Feasibility** and **usability** risks | Builder | Fill in |
| Increments and verification criteria | Builder | Fill in |
| **Value** and **viability** risks, approval | Volta | Review |

The four risks, from Marty Cagan's product risks:

| Risk | What goes wrong | Owner |
|---|---|---|
| **Value** | Built perfectly, the target still doesn't move. | Volta |
| **Viability** | It works, but can't keep running after we leave, costs too much, isn't allowed (privacy, security, contracts), or the customer won't fund it. | Volta |
| **Feasibility** | It can't be built or tested with the data, access, tools, skills and time we have. | Builder |
| **Usability** | It would fix the problem, but the people who have it won't use it or trust it in their normal day. | Builder |

Never copy the problem brief, requirements, acceptance examples or technical design onto this page. Link the problem brief and refer to its Done means items by number. The target formula is the one exception, because it is the builder's definition of success. Every section is either a decision or a limit the builder works within. If a sentence is neither, cut it.

## When a brief reaches 1.0

Drafts are `Draft 0.1`, `Draft 0.2` and so on. A brief becomes `1.0` only when:

- **The problem brief is at 1.0,** so the customer has confirmed the problem, the starting number and the target in writing.
- **Every element is filled in,** with no highlighted bracket and no `TBD`.
- **The Technical Lead's requirements are recorded,** with who gave them and when.
- **All four risks are rated** Low, Medium or High, with evidence. Every Medium or High risk has a test and a date.
- **The verification rows and the target have passed the misreading review,** run by Volta at review.
- **Every verification row is complete:** one Solved row, one Done row per Done means item, and at least one Safe row, each with a pass criterion, evidence, and who confirms it and when.
- **The builder has submitted it and the Volta owner has approved it,** each with a date in the facts strip.

`scripts/check_brief.sh` enforces these for any version at 1.0 or later. **No `/scope` run starts on a customer increment until its solution brief is at 1.0.**

## Choose the mode

- **Set up:** Volta, when a problem is ready to hand to a builder.
- **Guide:** the builder, filling in a brief they were given. Also use this when a builder says "help me with my solution brief" or opens a brief that has empty builder sections.
- **Review:** Volta, when a builder sends a brief back.
- **Update:** anyone, after a test result or a change. A change to the approach goes back through Review.

If it's unclear, ask who is running it: Volta or the builder.

## Set up (Volta)

Volta-only: needs Volta's systems (`outwork`, context maps, the Artifact tool, the `/problem-brief` sources); builders skip this mode.

1. Find the customer's project with `outwork context` and read its `context-map.md`. Read the problem brief from its live pages link with the Artifact tool. If there is no problem brief, stop and recommend `/problem-brief`. A draft problem brief is fine for setting up, but the solution brief can't reach 1.0 until the problem brief does.
2. Read what is on record since the problem brief's newest change log date, using the sources `/problem-brief` lists. Look for what the Technical Lead said about security, privacy, hosting and upkeep, the systems involved, and guardrails the customer asked for.
3. Copy the template and fill in only the set-up fields:
   - **Facts:** the problem brief link and version, the builder's name, and the Volta owner.
   - **What success means:** the target formula, copied word for word from the problem brief.
   - **Constraints**, each saying who set it:
     - **Security and privacy:** the customer data the work touches and how sensitive it is, who must not reach it, and the Technical Lead's requirements.
     - **Systems it touches:** which systems, and the access the builder will need.
     - **Guardrails:** what the customer asked for, such as nothing posting without approval.
4. Leave every builder section, and the Value and Viability rows, as placeholders. Don't write the approach, even if you have one in mind. Anything the builder should know goes in the hand-over message as a fact, not as a suggested solution.
5. Add a set-up row to the change log. Hand the builder the page as an HTML file, with the problem brief, and tell them to run `/solution-brief` on it.

## Guide (builder)

You are guiding the builder through filling in their brief. The builder devises the solution. **Your job is to make them think it through and write it down, not to solve it for them.**

This mode works without Volta's systems. Before the first question, read the brief file the builder was given and the problem brief. If you have Volta's systems and the problem brief is a claude.ai link, read it with the Artifact tool; otherwise read it from wherever the builder points (a file, a docs link or pasted text), and if they have no copy, ask them for one.

How to guide:

- **One question at a time.** Ask it, then wait for the answer.
- **Push back on weak answers.** If an answer is vague, contradicts the problem brief or an earlier answer, or can't fail, say why and ask again. For example: "How does that move the metric?", "What would show this can't be built?", "Who has to change what they do every day?"
- **Never suggest the approach.** Don't propose options, tools or designs, and don't say which option you'd pick. You may state facts from the problem brief and the constraints, and point out what an answer leaves out. If the builder explicitly asks for a hint, give one, label it as a hint, and say the choice is theirs.
- **If a question can be answered by reading the code or the problem brief,** read it instead of asking.
- **Write each answer onto the page as it's settled,** in the builder's words, tightened. Show them the line you wrote.

Work through the sections in this order, because each depends on the one before:

1. **Options considered.** Ask about each of the four, in order: do nothing, use what they already have, buy, build. Each needs a verdict (chosen, rejected or fallback) and a reason from the record, such as cost, fit with their systems, the constraints or the target. Push back on any option dismissed without a reason, especially "use what they already have", which is the one most often skipped.
2. **The approach.** 150 words or fewer, in plain terms, naming tools where known.
3. **Why it moves the metric.** What the approach changes about the problem brief's root cause, and roughly how far the target moves. If the builder can't explain how the number moves, stop here: they don't have an approach yet.
4. **Feasibility and usability risks.** For each: a rating (Low, Medium or High), the evidence, and for Medium or High, the earliest and cheapest test, with the date they'll know. Push for a test that could prove the risk real, not one that could only confirm it. Then: **if the highest risk is real**, what do we do instead? Usually that's the fallback option.
5. **Increments.** In order, each small enough for one `/scope` run, and mapped to a sprint. One sentence each, saying what is true for the problem lead when it ships and what it does for the metric. Put the test of the highest risk first, and mark the increment that first moves the metric. Setup or launch checks that need no code say "None needed".
6. **Verification.** Criteria, not test steps. `/document` designs the tests that meet them.
   - **Solved: target.** One row. It passes only when the target is reached on the live system after launch.
   - **Done N.** One row per Done means item on the problem brief, numbered to match. Use a short name and don't copy the item's text.
   - **Safe N.** One row per protection the approach depends on, taken from the security constraint. If the approach touches no new data or access, keep one Safe row that says so and why.
   - Each row has a **pass criterion that could fail** ("10 at once against a limit of 5 accept exactly 5", not "the limit works"), the **evidence**, and **who confirms it and when**. Prefer someone at the customer to confirm the Solved row.
7. **Open questions.** Anything the builder couldn't settle, with an owner and whether it blocks scoping. A security risk they suspect but haven't tested goes here, marked unverified.

Leave the Value and Viability rows as placeholders. Those are Volta's. If the builder has a view on them, put it in an open question.

Before submitting, run a misreading review of the increments and every verification row. Use a reviewer with no access to this conversation (a fresh sub-agent where your tool has them; otherwise reread only the page). For each pass criterion, it argues how the builder and the person who confirms it could reasonably disagree about whether it passed: subjective or vague words ("works", "fast", "most", "reliable", "smoothly"), a number with no unit, period or source, or a criterion with no stated way to check it. Show the builder each supported finding and ask them for the measurable version; don't write it for them. If the target formula itself could be misread, don't change it, because Volta copied it from the problem brief: add it to the open questions.

When every builder section is filled in, run the check if the builder can run bash (`bash scripts/check_brief.sh <file>` from this skill's folder). Fix what it reports in the builder's sections. Write `Submitted <date>` under the builder's name, add a change log row, save the page as a local HTML file (don't publish it), and tell the builder to send the file back to the Volta owner.

## Review (Volta)

Volta-only: needs Volta's systems (the Artifact tool, context maps, `/log`, `/problem-risks`); builders skip this mode.

1. Read the builder's page and the problem brief together. Check nothing in the set-up fields was changed. If something was, ask why before accepting it.
2. Judge the builder's sections against one bar: **would this approach, built as described, reach the target safely within the constraints?** For each gap or weak answer, write a specific question for the builder. Don't rewrite their approach. Look especially for:
   - an option dismissed without a reason;
   - a "why it moves the metric" that doesn't connect to the root cause;
   - feasibility or usability rated Low with no evidence;
   - verification criteria that can't fail;
   - any pass criterion, increment or target wording that the builder and the customer could read differently. Run the misreading review from Guide mode again with a fresh reviewer rather than trusting the builder's own pass, and turn each supported finding into a question. If the target formula is the problem, it is fixed in the problem brief first, through `/problem-brief` Update;
   - a Safe row missing for a protection the security constraint needs.
3. Rate **Value** and **Viability** with evidence. For a fuller assessment, `/problem-risks` uses the same four risks.
   - **Value:** does this approach move the confirmed target, for the people who have the problem, by enough to matter?
   - **Viability:** who runs it after we leave, what it costs each month, whether it's allowed, and whether the customer is paying for it.

   Add a test and date for anything rated Medium or High.
4. Decide:
   - **Send back:** add a change log row with the questions, keep it a Draft, and send the file to the builder. Their next Guide run starts from the questions.
   - **Approve:** this needs every 1.0 condition. Write `Approved <date>` under the Volta owner, set the version to `1.0`, and run the check until it passes.
5. Publish with the Artifact tool as a private page, icon `document`. Add a row to the live pages table in the project's `context-map.md` (page name, link, what it holds, "Use `/solution-brief` to update"). Record it with `/log`. Don't commit unless the user asks.
6. Hand back the link, what stands between the brief and 1.0 (including the problem brief's status), and one next step. After approval, that step is `/scope` on increment 1, linking the brief.
7. Once the brief is at 1.0, send the builder a copy they can open, because they can't open the private page: the approved 1.0 HTML file, or a docs.voltaeffect.com review copy made with `/doc` where Volta uses it. Tell them this copy is what `/scope` reads.

## Update

1. Read the current page and the problem brief: if you have Volta's systems and they are claude.ai links, read them with the Artifact tool; otherwise read the files or links the user points to. If the problem brief's version moved, carry over any change to the target, and match the Done rows to its Done means.
2. Apply sourced changes: test results, verification evidence, and links to `/scope` issues. Those don't need re-approval.
3. A change to the approach, a risk rating, the success definition or a constraint on a 1.0 brief goes back to Draft and through Review. If `/scope` issues already exist, list them in the hand-back, because their product contracts may now rest on the wrong approach.
4. If the highest risk proves real, don't switch approach quietly. Add a change log row with the result, move the fallback into the approach, and send it back through Review.
5. Bump the version and add a change log row only when the page's content changed. Run the check. If you have Volta's systems and the brief is published, publish to the same link; otherwise save the file locally and send it on.

## Build and check rules

- Keep the template's styling, sections and order exactly. Change only the placeholders, and delete the template comments.
- For gaps use `<span class="tbc">[short label]</span>`, or `TBD` for a person. Put attributions in `<span class="said">(Mark, 21 Oct)</span>`.
- `bash scripts/check_brief.sh <file>` checks the structure, the four options and the four risks, unfilled placeholders, the approach paragraph's length, the verification rows, and the 1.0 conditions. It can't judge whether the reasoning holds up, so read the page too.

## What this skill never does

- Ends a run without the page.
- Suggests the approach to a builder, or writes the builder's sections during Set up or Review.
- Lets the builder rate Value or Viability, or lets Volta skip rating them.
- Marks a brief 1.0 while the problem brief isn't, or records a submission or approval nobody gave.
- Copies requirements, acceptance examples, technical design or the problem brief's text onto the page.
- Fills a gap with a guess.
- Sends the page to the customer. It is internal.
