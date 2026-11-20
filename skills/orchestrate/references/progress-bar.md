# Progress bar (Volta orchestrate-progress tool)

Read this only when the orchestrate-progress tool is present. SKILL.md links here from its Progress bar section.

When the orchestrate-progress tool is present (the Volta `orchestrate-progress` mod is loaded and `mcp__orchestrate-progress__report` is available), use it as below. It draws a bar above the prompt that fills only as the orchestrator confirms requirements. Otherwise, as always in Codex, skip this section and every progress call; nothing else changes.

- **Start (Step 1):** once the contract is read, call it with `action: "start"`, the issue given to `/orchestrate`, its title, and `issues`: every issue in the run with its in-scope `SR-*`, `AC-*` and `TR-*` identifiers. For an epic, include each child, and mark already-closed ones `closed: true` so the bar shows the whole epic. Leave out deferred identifiers. A resumed run calls start again; the mod restores earlier verdicts from the sign-off comments on GitHub.
- **Stage (Step 3 onward):** whenever a track's status changes, report it with `action: "stage"`.
- **Verdict (Steps 4, 5 and 7):** report each requirement as soon as you reach a verdict, with `action: "verdict"`. Use `confirmed` only after your own Step 4 check, never on an implementer's claim alone. Use `sent-back` when it goes back as a blocking finding, and `unmet` when it will be reported UNMET. The bar shows UNMET as "unverified" and never counts it.
- **Accepted as a follow-up (Step 6):** when the user accepts an UNMET requirement as a follow-up, report it with `action: "verdict"` and status `accepted`, and only then. The bar counts it toward done but keeps it apart from verified. Record their acceptance in the sign-off as `- AC-3 <short name>: UNMET, accepted as follow-up by the user (<follow-up issue or date>).`; the mod reads that wording back from GitHub.
- **Waiting on the user (Step 6):** when you ask the user a decision, report `action: "ask"` with the question in one short line. Once they have answered, report `action: "answered"`. The bar shows "Waiting on your answer" only in between, so never leave it set after they reply.

Use these exact shapes. Every call carries `issue` as a number. The mod converts a few common slips and says so in its reply, and refuses anything else with `NOT RECORDED`; a refusal changed nothing, so fix the call and send it again.

```json
{"action": "start", "issue": 45, "title": "<title>", "repo": "owner/name",
 "issues": [{"issue": 45, "ids": ["SR-01", "SR-02", "AC-01", "AC-02"]}]}
{"action": "stage", "issue": 45, "stage": "under review"}
{"action": "stage", "issue": 45, "stage": "sent back", "round": 1}
{"action": "verdict", "issue": 45, "verdicts": [{"id": "SR-01", "status": "confirmed"}, {"id": "AC-02", "status": "unmet"}]}
{"action": "ask", "issue": 45, "question": "<one short line>"}
{"action": "answered", "issue": 45}
```

- **Always pass `repo`** as the repository the issue lives in. Without it the mod uses the repository of the session's folder, which is wrong whenever the session runs from a project folder rather than the code checkout. The start reply names the repository it used; check it.
- **`ids` and verdicts take `SR-*`, `AC-*` and `TR-*` only.** Decisions (`D-*`) are not counted.
- **`stage` is one of** `preparing`, `implementing`, `under review`, `sent back`, `verified`, `blocked`, `ready to ship`, `shipped`, with nothing added. Put detail in your message to the user, not in the stage. Merged or deployed but not yet checked live is `ready to ship`; live is `shipped`.
- **Read every reply.** After a verdict, the verified count in the reply must have moved. A reply that starts `NOT RECORDED`, or a count that did not move, means the bar did not take it.
