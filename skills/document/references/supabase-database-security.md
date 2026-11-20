# Supabase Database Security Standard

The shared standard for any change that affects who can read or write data in a Supabase
project. `/document`, `/start-work`, and `/ship-it` all point here so the same rules apply
whether the change is being designed, implemented, or shipped.

This is a floor, not a ceiling. It does not replace reading the Supabase documentation for
the specific feature being changed.

**This standard is not scoped to the four skills.** A change applied through the Supabase
MCP tools, the dashboard, or `supabase db push` in a chat session is still an access change
and owes the same checks — there is just no ship gate left to catch it, so the checks happen
before the statement runs or not at all.

## The two questions

Every access change has to answer both. Answering only the first is the most common way a
database gets exposed, because the feature works perfectly either way.

1. **Can everyone in the declared audience still reach this data?**
2. **Can everyone outside it still not?**

A table with its protection turned off answers question 1 flawlessly. Only question 2 can
tell the difference between a working feature and an open database.

## Declare the audience first

Neither question is answerable until the object's audience is declared. Every object a
change touches carries one of:

- **service-role-only** — no app-facing access at all; protection on with no rules is the
  *correct* end state, not a mistake to fix;
- **tenant-scoped** — signed-in users see their own account's rows and nobody else's;
- **authenticated** — any signed-in user, no tenant boundary;
- **public-read** — the anonymous public reads it by design, through a named projection
  (usually a view), and cannot write;
- **private** — an internal subset of authenticated users; name the roles included.

The audience comes from the delivery contract, the product contract, or the recorded
consumer inventory — **never invented at proof time**. "Anon must see nothing" is the wrong
assertion for a public events calendar, and rubber-stamping "anon access is intended here"
without a recorded declaration is how a temporary exception becomes a permanent leak.

## Consult the documentation before writing an access rule

Do not write a policy, a grant, a view, or a database function from memory. Supabase's rules
about which role a view runs as, what the public key can reach, and how storage permissions
are evaluated have changed over time and are easy to get subtly wrong.

Use, in order of preference:

1. **The Supabase-maintained skills**, installed globally on this machine — load them before
   writing the change, not after it breaks:
   - `supabase-postgres-best-practices` — schema, migrations, access policies and the tests
     that verify them, indexes, triggers, database functions, and diagnosing rows visible to
     the wrong user or tenant.
   - `supabase` — Auth, sessions and cookies, Edge Functions, Storage, Realtime, the client
     libraries, and security audits.
2. The Supabase docs search tool on the connected Supabase MCP server (`search_docs`).
3. `context7` for the Supabase client libraries.

Name the documentation you consulted in the delivery contract or proof table. "I know how RLS
works" is not a source.

## Run the advisors — and know what they cannot see

Supabase ships a security advisor that lists exposure problems directly. It is one call and
it is the cheapest check available.

- **Before** a change that touches data access, capture the advisor output as a baseline —
  each finding's name and object, not just a count — and **post it to the GitHub issue
  immediately**. The comparison happens at ship time, possibly in a different session; a
  baseline that lives only in conversation context does not survive to be compared against.
- **After** the change, run it again and compare **item-by-item**. Counts hide a new finding
  offset by a fixed one.
- A finding the change introduced is a blocking defect. A pre-existing finding is not this
  change's problem, but it must not be silently absorbed into the new baseline.

Use `get_advisors` on the connected Supabase MCP server, for both the `security` and
`performance` types where relevant.

**The advisor's blind spots.** It sees protection toggles and definer objects. It cannot see
what a policy *permits*, what the API configuration exposes, or whether a function body
checks who is calling. A clean advisor diff does not mean access is unchanged — the largest
exposure class in practice (permissive policies, next section) is invisible to it, so the
advisor comparison is one check of several, never the whole proof.

## The failure modes to check by name

Generic questions about "authorization" get generic answers. Check for these specifically:

| Failure mode | What it means in practice |
|---|---|
| Protection turned off on a table | Anyone holding the public key reads or writes every row. |
| Protection on, but no rules written | The app silently returns zero rows — the outage flavor of this mistake — *unless* service-role-only is the declared audience, in which case this is the correct locked state. |
| Rules written, but they let everyone through | A policy with no role restriction applies to everyone, the anonymous public included; a `USING (true)` condition admits every row; a policy's *name* is not evidence of its behavior. The advisor cannot see this category — read `pg_policies` (roles, command, condition) for every touched table. |
| A view that runs as its owner | The view ignores the caller's permissions and returns everything. |
| A database function anyone can call | Every new function is executable by everyone until revoked. Ship the revoke and the intended grants in the same migration, and put an auth check inside every function that runs with elevated privileges — the advisor cannot tell a guarded function from an unguarded one. |
| Grants to the public or logged-in role | Direct table access that bypasses the intended path entirely. |
| Storage buckets and their rules | A bucket flagged public serves files with **no rule evaluation at all** — a refused directory listing proves nothing while every file stays fetchable by path. The negative proof for storage is fetching a known file path, not listing. Flipping a bucket public→private is an access change with its own consumer blast radius (every consumer needs signed URLs). |
| Access set in configuration, not code | The exposed-schema list in the API settings, bucket public flags, an edge function's JWT verification toggle, realtime publication membership, and key rotation all change who can reach data and produce **no code diff**. A config change made in a session is an access change and owes the same checks. |
| A secret key reachable by the browser | An admin key in client code or a public environment variable defeats every rule above. |
| A credential embedded in a database object | A key inlined in a trigger definition, a scheduled-job command, a function body, or migration SQL is readable by anyone who can read the catalog and survives in every database dump. Webhook and job auth headers come from Vault at call time, never inline. |
| Personal, financial, or credential columns | Exposure here is a reportable incident, not a bug. Row rules do not limit *columns*: a row a user may legitimately see can still leak phone numbers or tokens. Sensitive columns are fixed with a curated view or column grants, not a row policy. |

## Enumerate the consumers before changing access

**A Supabase project is almost never read by only the repository you are working in.**

Searching one repository for references to a table and finding none does not make that table
dormant. Most apps inject the database URL through their deployment environment rather than a
committed file, so a text search for the project reference undercounts consumers badly.

Before any change that turns protection on, changes which role a view or function runs as,
revokes permission to run a function, changes storage rules, drops an object, **or renames,
retypes, or re-constrains an object other consumers may read**:

1. List every runtime consumer of the project — web apps, scheduled jobs, edge functions,
   reporting scripts, integrations.
2. For each place the object is used, record how it authenticates: the public key, a
   logged-in user's session, or an admin key.
3. Anything read with the public key or a user session needs its rules written **before**
   protection is turned on, or those reads start returning nothing.
4. **Admin-key consumers are not safe either.** They bypass row rules, but they break on
   revoked execute permission, dropped or renamed objects, and schema moves. Pair every
   `REVOKE ... FROM PUBLIC` with explicit grants for each intended caller class — in the
   same migration, or the revoke silently takes down the scheduled jobs and reporting
   scripts nobody remembered.
5. Check what the database itself depends on: foreign keys, triggers, views, scheduled jobs,
   and functions that run with elevated privileges. Application code is not the whole picture.

Where a project has recorded its consumer inventory — a context map, a project memory, a
security inventory document — read it. Do not re-derive it from a text search.

**Known inventories.** Where a team keeps a recorded consumer inventory or incident history
for a shared database (for example in a project memory or context map), read it from any repo
before changing who can reach that database's objects.

## How to run the proof

**The MCP `execute_sql` tool and the dashboard SQL editor run with elevated privileges.** A
bare query through either is admin-key evidence: it returns rows no matter what the rules
say, whatever role you intended to test. Use one of these instead:

**As the anonymous role**

- REST: call the project's API with the publishable key (`get_publishable_keys` on the MCP
  server returns it) and no user token.
- SQL, through `execute_sql`, by assuming the role inside a transaction that rolls back:

  ```sql
  begin;
  set local role anon;
  select ... ;
  rollback;
  ```

**As a specific user — wrong tenant, or an excluded internal role**

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"<user-uuid>","role":"authenticated"}', true);
select ... ;
rollback;
```

Keep a standing test user in a second tenant for this. If the project has no second tenant
to test against, create one — the proof cannot run without it, and an unrunnable proof gets
waived, which is how exposures ship.

**Probe safety**

- A negative proof of a write path must not be able to succeed destructively. Probe with a
  `where false` predicate or a nonexistent key, so that even a broken rule mutates nothing.
- A full mutating probe — actually calling a delete function to prove it is blocked — runs
  only against a database branch (`create_branch`) or a local stack, never production. If
  the rule turns out to be broken, the probe *is* the incident.
- Production re-verification is read probes and the advisor comparison only.

**Prefer the project's harness**

Where the project ships an access-test harness, the proof runs there — add one exposure
assertion (the excluded role gets nothing) and one preservation assertion (the authorized
role's row *count* is unchanged) for every touched object. Manual queries are the fallback,
not the default. The preservation half is what catches the outage direction: protection
enabled without rules drops authorized counts to zero, and a hand-picked single-row check
misses it.

## What counts as proof

Proof is a query that ran against a real database as a real role, and the rows it returned.

- **Positive proof:** each role in the declared audience sees the intended rows — as a
  before/after count where the harness supports it, not one hand-picked row.
- **Negative proof:** every role the declared audience excludes gets nothing. That means the
  anonymous role *unless the object is declared public-read*, a user from a different
  tenant, and any internal role the contract excludes. For a public-read object, the
  negative proof is that anon gets **only the declared projection** and cannot write,
  update, or delete.
- **Column proof:** for objects carrying personal, financial, or credential columns, the
  positive proof asserts the returned *column set*, not just the rows.
- Neither half is proven by an admin key, which bypasses the rules being tested.
- Neither half is proven by asserting the text of a migration file. A migration that was
  written correctly and never applied reads exactly the same as one that was.
