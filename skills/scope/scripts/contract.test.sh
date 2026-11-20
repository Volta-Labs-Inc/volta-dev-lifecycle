#!/usr/bin/env bash
#
# Tests for contract.py. Stubs the GitHub CLI with an issue store under a temp
# dir, builds throwaway git repos for the commit and drift questions, and
# asserts every exit path: written, already current, stale, read-back mismatch,
# contract drift, code drift, missing sections, legacy bodies, epic children.
#
# Run:  ./contract.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$SCRIPT_DIR/contract.py"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/contract-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0

ok() {
	PASS=$((PASS + 1))
	printf '  ok    %s\n' "$1"
}

no() {
	FAIL=$((FAIL + 1))
	printf '  FAIL  %s\n' "$1"
	[ -n "${2:-}" ] && printf '        %s\n' "$2"
	# Must return 0: callers use `cond && no "..." || ok "..."`.
	return 0
}

expect_status() {
	local want="$1" got="$2" what="$3"
	if [ "$want" = "$got" ]; then
		ok "$what (exit $got)"
	else
		no "$what" "expected exit $want, got $got: $OUTPUT"
	fi
}

contains() {
	local what="$1" needle="$2" haystack="$3"
	if printf '%s' "$haystack" | grep -qF -- "$needle"; then
		ok "$what"
	else
		no "$what" "missing: $needle
        in: $(printf '%s' "$haystack" | head -c 600)"
	fi
}

lacks() {
	local what="$1" needle="$2" haystack="$3"
	if printf '%s' "$haystack" | grep -qF -- "$needle"; then
		no "$what" "unexpected: $needle"
	else
		ok "$what"
	fi
}

# --- the fake gh ----------------------------------------------------------------
# An issue store of JSON files. Knobs:
#   GH_STUB_FAIL=1       every call fails the way a network or auth error would
#   GH_STUB_EDIT_NOOP=1  `issue edit` succeeds but changes nothing (a lost write)
#   GH_STUB_CRLF=1       `issue view` returns the body with CRLF line endings,
#                        as GitHub does for bodies saved from the web editor
#   GH_STUB_RACE=1       after serving an `issue view`, someone else edits the body
#   GH_STUB_CREATE_EMPTY=1  `issue create` stores an empty body (a lost body)
STUB_BIN="$TMP_ROOT/bin"
STORE="$TMP_ROOT/store"
mkdir -p "$STUB_BIN" "$STORE"
cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env python3
import json, os, sys
store = os.environ["GH_STUB_STORE"]
args = sys.argv[1:]
with open(os.path.join(store, "calls.log"), "a") as log:
    log.write(" ".join(args) + "\n")
if os.environ.get("GH_STUB_FAIL") == "1":
    sys.stderr.write("error connecting to api.github.com\n")
    sys.exit(1)

def opt(flag):
    return args[args.index(flag) + 1] if flag in args else None

repo = opt("-R") or "test/repo"

def path(n):
    if repo == "test/repo":
        return os.path.join(store, "%s.json" % n)
    folder = os.path.join(store, repo.replace("/", "__"))
    os.makedirs(folder, exist_ok=True)
    return os.path.join(folder, "%s.json" % n)

def load(n):
    try:
        with open(path(n)) as f:
            return json.load(f)
    except FileNotFoundError:
        sys.stderr.write("GraphQL: Could not resolve to an issue (repository.issue)\n")
        sys.exit(1)

if args[:2] == ["repo", "view"]:
    print("test/repo"); sys.exit(0)
if args[:2] == ["issue", "view"]:
    issue = load(args[2])
    fields = (opt("--json") or "").split(",")
    out = {k: issue.get(k) for k in fields if k}
    if "body" in out and os.environ.get("GH_STUB_CRLF") == "1":
        out["body"] = out["body"].replace("\n", "\r\n")
    print(json.dumps(out))
    if os.environ.get("GH_STUB_RACE") == "1":
        issue["body"] += "\n\nracing edit by someone else\n"
        with open(path(args[2]), "w") as f:
            json.dump(issue, f)
    sys.exit(0)
if args[:2] == ["issue", "edit"]:
    issue = load(args[2])
    if os.environ.get("GH_STUB_EDIT_NOOP") != "1":
        with open(opt("--body-file")) as f:
            issue["body"] = f.read()
        with open(path(args[2]), "w") as f:
            json.dump(issue, f)
    print("https://github.com/test/repo/issues/%s" % args[2]); sys.exit(0)
if args[:2] == ["issue", "create"]:
    numbers = [int(n[:-5]) for n in os.listdir(store) if n.endswith(".json")]
    n = max(numbers + [0]) + 1
    with open(opt("--body-file")) as f:
        body = f.read()
    if os.environ.get("GH_STUB_CREATE_EMPTY") == "1":
        body = ""
    parent = opt("--parent")
    issue = {"number": n, "title": opt("--title"), "state": "OPEN", "body": body,
             "url": "https://github.com/test/repo/issues/%d" % n,
             "parent": {"number": int(parent)} if parent else None,
             "labels": [args[i + 1] for i, a in enumerate(args) if a == "--label"]}
    with open(path(n), "w") as f:
        json.dump(issue, f)
    sys.stderr.write("Creating issue in test/repo\n")
    print(issue["url"]); sys.exit(0)
sys.stderr.write("stub gh: unsupported call: %s\n" % " ".join(args))
sys.exit(1)
EOF
chmod +x "$STUB_BIN/gh"
export GH_BIN="$STUB_BIN/gh"
export GH_STUB_STORE="$STORE"

seed_issue() { # number title bodyfile [parent: N or owner/repo#N] [repo]
	python3 - "$STORE" "$1" "$2" "$3" "${4:-}" "${5:-test/repo}" <<'EOF'
import json, os, sys
store, n, title, bodyfile, parent, repo = sys.argv[1:7]
with open(bodyfile) as f:
    body = f.read()
if "#" in parent:
    # GitHub names a cross-repository parent only by its URL.
    parent_repo, parent_n = parent.split("#")
    parent_ref = {"number": int(parent_n), "url": "https://github.com/%s/issues/%s" % (parent_repo, parent_n)}
else:
    parent_ref = {"number": int(parent)} if parent else None
issue = {"number": int(n), "title": title, "state": "OPEN", "body": body,
         "url": "https://github.com/%s/issues/%s" % (repo, n), "parent": parent_ref}
folder = store if repo == "test/repo" else os.path.join(store, repo.replace("/", "__"))
os.makedirs(folder, exist_ok=True)
with open(os.path.join(folder, "%s.json" % n), "w") as f:
    json.dump(issue, f)
EOF
}

issue_body() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["body"], end="")' "$STORE/$1.json"; }
edit_calls() { grep -c "^issue edit" "$STORE/calls.log" 2>/dev/null || true; }
jget() { python3 -c 'import json,sys; v=json.loads(sys.stdin.read())
for k in sys.argv[1].split("."):
    v = v[int(k)] if isinstance(v, list) else v.get(k)
print(v if not isinstance(v, (dict, list)) else json.dumps(v))' "$1"; }

# --- throwaway repos ------------------------------------------------------------
# Origin + clone on main with two tracked areas. Echoes the clone path.
new_repo() {
	local name="$1" root="$TMP_ROOT/$1"
	mkdir -p "$root"
	git init -q --bare "$root/origin.git"
	git --git-dir "$root/origin.git" symbolic-ref HEAD refs/heads/main
	git clone -q "$root/origin.git" "$root/clone" 2>/dev/null
	(
		cd "$root/clone"
		git config user.email t@test.com
		git config user.name Test
		git checkout -q -b main 2>/dev/null || git branch -qm main
		mkdir -p skills/scope other
		echo one >skills/scope/SKILL.md
		echo two >other/notes.md
		git add .
		git commit -qm "init"
		git push -q origin HEAD:main
		git remote set-head origin -a >/dev/null 2>&1
	)
	printf '%s\n' "$root/clone"
}

commit_push() { # repo path message
	(
		cd "$1"
		# Another clone may have pushed meanwhile; start from origin's tip so the push lands.
		git fetch -q origin main && git merge -q --ff-only origin/main
		mkdir -p "$(dirname "$2")"
		echo "$3" >>"$2"
		git add -A
		git commit -qm "$3"
		git push -q origin HEAD:main
	)
}

tip() { git -C "$1" rev-parse --short=8 origin/main; }

run_contract() { # repo-path args...
	local path="$1"
	shift
	OUTPUT="$(cd "$path" && python3 "$CONTRACT" "$@" 2>&1)"
	return $?
}

PRODUCT_A="$TMP_ROOT/product-a.md"
cat >"$PRODUCT_A" <<'EOF'
## Outcome

Agents plan from one issue.

## Relies on

- The existing `/document` handoff.

## Product requirements

- **SR-01** - When /scope writes, the product section carries a fingerprint.
- **SR-02** - When the fingerprint moves, building stops.

## Acceptance examples

### AC-01 - Drift is caught

- **Given** a delivery contract planned against v1
- **When** the product contract becomes v2
- **Then** check reports CONTRACT_DRIFT

## Decisions

- **D-01** - GitHub, not Linear.
EOF

PRODUCT_B="$TMP_ROOT/product-b.md"
sed 's/Agents plan from one issue./Agents plan from one issue, always./' "$PRODUCT_A" >"$PRODUCT_B"

DELIVERY_A="$TMP_ROOT/delivery-a.md"
cat >"$DELIVERY_A" <<'EOF'
## Scope authority

- **Delivery tier:** light

## Drift report

- **Paths watched:** `skills/scope/`, `other/notes.md`
- **What changed:** nothing since scoping.

## Requirement-to-proof matrix

| Scope ID | Required behavior | Surface | Automated proof | Runtime proof | Readback or evidence |
|---|---|---|---|---|---|
| SR-01 / AC-01 | fingerprint stamped | backend | contract.test.sh | write then read | stamp line |

## Completion contract

- [ ] SR-02 is proven elsewhere, in a later increment (not in the matrix above).
EOF

printf '\ncontract.py tests\n\n'

# --- 1. fingerprint is stable under GitHub's own rewrites ------------------------
fp_a="$(python3 "$CONTRACT" fingerprint "$PRODUCT_A")"
printf '%s' "$(cat "$PRODUCT_A")" | sed 's/$/   /' | awk '{printf "%s\r\n", $0}' >"$TMP_ROOT/product-a-crlf.md"
printf '\n\n' >>"$TMP_ROOT/product-a-crlf.md"
fp_crlf="$(python3 "$CONTRACT" fingerprint "$TMP_ROOT/product-a-crlf.md")"
fp_b="$(python3 "$CONTRACT" fingerprint "$PRODUCT_B")"
[ "${#fp_a}" -eq 8 ] && ok "fingerprint is 8 hex characters ($fp_a)" || no "fingerprint is 8 hex characters" "$fp_a"
[ "$fp_a" = "$fp_crlf" ] && ok "CRLF, trailing spaces and blank edges do not change the fingerprint" || no "CRLF, trailing spaces and blank edges do not change the fingerprint" "$fp_a vs $fp_crlf"
[ "$fp_a" != "$fp_b" ] && ok "a changed word changes the fingerprint" || no "a changed word changes the fingerprint"
{ printf '# Product contract\n\n'; cat "$PRODUCT_A"; } >"$TMP_ROOT/product-a-headed.md"
fp_headed="$(python3 "$CONTRACT" fingerprint --section product "$TMP_ROOT/product-a-headed.md")"
[ "$fp_a" = "$fp_headed" ] && ok "a pasted section heading is dropped before fingerprinting" || no "a pasted section heading is dropped before fingerprinting" "$fp_a vs $fp_headed"

# --- 2. create an issue holding the product contract ---------------------------
repo="$(new_repo create)"
run_contract "$repo" create --title "Move the contract" --file "$PRODUCT_A" --label scope --json
expect_status 0 $? "create writes the product contract and reads it back"
[ "$(printf '%s' "$OUTPUT" | jget status)" = "CREATED" ] && ok "create reports CREATED" || no "create reports CREATED" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget number)" = "1" ] && ok "create returns the new issue number" || no "create returns the new issue number" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget stamp.fp)" = "$fp_a" ] && ok "create stamps the content fingerprint" || no "create stamps the content fingerprint" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget stamp.at)" = "$(tip "$repo")" ] && ok "create stamps the default-branch tip as scoped-at" || no "create stamps the default-branch tip" "$OUTPUT"
body="$(issue_body 1)"
contains "the body opens with the product start marker" "<!-- contract:product v=1 fp=$fp_a at=$(tip "$repo")" "$body"
contains "the body has the visible stamp line" "_Product contract v1 · fingerprint \`$fp_a\`" "$body"
contains "the body has the H1 the agent did not have to write" "# Product contract" "$body"
contains "the body closes the section" "<!-- /contract:product -->" "$body"
grep -q -- "--label scope" "$STORE/calls.log" && ok "labels are passed to gh issue create" || no "labels are passed to gh issue create"

# --- 3. writing the same product text again changes nothing ---------------------
before="$(edit_calls)"
run_contract "$repo" write 1 --section product --file "$TMP_ROOT/product-a-crlf.md"
expect_status 0 $? "rewriting identical text is ALREADY_CURRENT"
contains "ALREADY_CURRENT is reported" "ALREADY_CURRENT" "$OUTPUT"
[ "$(edit_calls)" = "$before" ] && ok "no edit call is made for identical text" || no "no edit call is made for identical text"

# --- 4. a changed product contract becomes v2 and keeps the rest of the body -----
printf '\n\nFree text Matt typed under the sections.\n' >>"$TMP_ROOT/legacy-tail.md"
python3 - "$STORE/1.json" "$TMP_ROOT/legacy-tail.md" <<'EOF'
import json, sys
p, tail = sys.argv[1:3]
d = json.load(open(p)); d["body"] += open(tail).read(); json.dump(d, open(p, "w"))
EOF
run_contract "$repo" write 1 --section product --file "$PRODUCT_B" --expect-fingerprint "$fp_a" --json
expect_status 0 $? "update with the right expected fingerprint is written"
[ "$(printf '%s' "$OUTPUT" | jget stamp.v)" = "2" ] && ok "the version increments to 2" || no "the version increments to 2" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget stamp.fp)" = "$fp_b" ] && ok "the new fingerprint is stamped" || no "the new fingerprint is stamped" "$OUTPUT"
body="$(issue_body 1)"
contains "text outside the section survives an update" "Free text Matt typed under the sections." "$body"
lacks "the old product text is gone" "Agents plan from one issue." "$body"
[ "$(printf '%s' "$body" | grep -c '<!-- contract:product ')" = "1" ] && ok "exactly one product section remains" || no "exactly one product section remains"

# --- 5. a stale expected fingerprint is refused ---------------------------------
before="$(edit_calls)"
run_contract "$repo" write 1 --section product --file "$PRODUCT_A" --expect-fingerprint "$fp_a"
expect_status 10 $? "updating from a fingerprint that is no longer current is refused"
contains "the refusal names the current fingerprint" "$fp_b" "$OUTPUT"
[ "$(edit_calls)" = "$before" ] && ok "a stale update makes no edit call" || no "a stale update makes no edit call"

# --- 6. the delivery contract goes directly below the product contract ----------
run_contract "$repo" write 1 --section delivery --file "$DELIVERY_A" --product-fingerprint "$fp_b" --json
expect_status 0 $? "delivery write against the current product fingerprint succeeds"
[ "$(printf '%s' "$OUTPUT" | jget stamp.fp)" = "$fp_b" ] && ok "delivery stamp records the product fingerprint it planned against" || no "delivery stamp records the product fingerprint" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget stamp.v)" = "2" ] && ok "delivery stamp records the product version" || no "delivery stamp records the product version" "$OUTPUT"
body="$(issue_body 1)"
python3 - "$body" <<'EOF' && ok "delivery section sits after the product section and before the free text" || no "delivery section ordering"
import sys
b = sys.argv[1]
assert 0 <= b.find("<!-- /contract:product -->") < b.find("<!-- contract:delivery ") < b.find("Free text Matt typed"), b
EOF
contains "the matrix heading the progress mod looks for is inside the delivery section" "## Requirement-to-proof matrix" "$body"
run_contract "$repo" check 1 --json
expect_status 0 $? "check is IN_SYNC right after planning"
[ "$(printf '%s' "$OUTPUT" | jget status)" = "IN_SYNC" ] && ok "status IN_SYNC" || no "status IN_SYNC" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget not_in_matrix)" = '["SR-02"]' ] && ok "check names the product identifier with no matrix row" || no "check names SR-02 as not in matrix" "$OUTPUT"

# --- 7. read shows both sections and their identifiers --------------------------
run_contract "$repo" read 1 --json
expect_status 0 $? "read returns JSON for an issue with both sections"
[ "$(printf '%s' "$OUTPUT" | jget product.identifiers.SR)" = '["SR-01", "SR-02"]' ] && ok "read lists the product SR identifiers" || no "read lists the product SR identifiers" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget delivery.matrix_identifiers.SR)" = '["SR-01"]' ] && ok "read cuts the matrix the way the progress mod does (SR-02 in Completion contract is excluded)" || no "matrix cut" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget delivery.paths_watched)" = '["skills/scope/", "other/notes.md"]' ] && ok "read parses the watched paths" || no "read parses the watched paths" "$OUTPUT"
run_contract "$repo" read 1 --section product
expect_status 0 $? "read --section prints the section text"
[ "$(printf '%s\n' "$OUTPUT" | python3 "$CONTRACT" fingerprint -)" = "$fp_b" ] && ok "the printed product text fingerprints to the stamped value" || no "printed product text fingerprints to the stamped value"

# --- 8. the product contract moves on: contract drift ---------------------------
run_contract "$repo" write 1 --section product --file "$PRODUCT_A" --expect-fingerprint "$fp_b"
expect_status 0 $? "product v3 is written"
contains "the write warns that the delivery contract is now behind" "needs /document reconciliation" "$OUTPUT"
run_contract "$repo" check 1
expect_status 10 $? "check reports CONTRACT_DRIFT once the product fingerprint moved"
contains "drift names the planned fingerprint" "$fp_b" "$OUTPUT"
contains "drift names the current fingerprint" "$fp_a" "$OUTPUT"
before="$(edit_calls)"
run_contract "$repo" write 1 --section delivery --file "$DELIVERY_A" --product-fingerprint "$fp_b"
expect_status 10 $? "a delivery write planned against the old product fingerprint is refused"
[ "$(edit_calls)" = "$before" ] && ok "the refused delivery write makes no edit call" || no "the refused delivery write makes no edit call"
run_contract "$repo" write 1 --section delivery --file "$DELIVERY_A" --product-fingerprint "$fp_a"
expect_status 0 $? "re-planning against the current product fingerprint succeeds"
run_contract "$repo" check 1
expect_status 0 $? "check is IN_SYNC again after re-planning"

# --- 9. code drift under the watched paths --------------------------------------
commit_push "$repo" other/notes.md "touch a watched file"
run_contract "$repo" check 1
expect_status 12 $? "a commit under a watched path since planning is CODE_DRIFT"
contains "the drift report lists the file" "other/notes.md" "$OUTPUT"
contains "the drift report lists the commit" "touch a watched file" "$OUTPUT"
run_contract "$repo" write 1 --section delivery --file "$DELIVERY_A" --product-fingerprint "$fp_a"
expect_status 0 $? "re-planning stamps the new default-branch tip"
commit_push "$repo" unrelated/readme.md "touch an unwatched file"
run_contract "$repo" check 1
expect_status 0 $? "a commit outside the watched paths is not drift"
contains "the report says NO_CHANGE" "NO_CHANGE" "$OUTPUT"
run_contract "$repo" check 1 --no-code
expect_status 0 $? "--no-code skips the comparison"
contains "--no-code says so" "not checked (--no-code)" "$OUTPUT"

# --- 10. drift as a standalone command, including a fetch from origin -----------
since="$(tip "$repo")"
run_contract "$repo" drift --since "$since" -- skills/scope
expect_status 0 $? "drift with nothing changed exits 0"
# A commit that reaches origin from another clone: drift must fetch to see it.
other_clone="$TMP_ROOT/create/other"
git clone -q "$TMP_ROOT/create/origin.git" "$other_clone" 2>/dev/null
(cd "$other_clone" && git config user.email t@test.com && git config user.name Test && echo more >>skills/scope/SKILL.md && git add -A && git commit -qm "edited elsewhere" && git push -q origin HEAD:main)
run_contract "$repo" drift --since "$since" -- skills/scope
expect_status 12 $? "drift fetches origin and sees a commit made from another clone"
contains "drift lists the commit from the other clone" "edited elsewhere" "$OUTPUT"
run_contract "$repo" drift --since "$since" --json -- other
expect_status 0 $? "drift limited to another path ignores it"
run_contract "$repo" drift --since deadbeef -- skills
expect_status 1 $? "an unknown --since commit is an error"
run_contract "$repo" drift --since "$since" --until "$since" -- skills
expect_status 0 $? "--until pins the comparison"

# --- 11. an issue with only a product contract ----------------------------------
run_contract "$repo" create --title "Scoped only" --file "$PRODUCT_A"
expect_status 0 $? "second issue created"
run_contract "$repo" check 2
expect_status 20 $? "check on a scoped-only issue is NO_DELIVERY"
contains "NO_DELIVERY points at /document" "run /document" "$OUTPUT"

# --- 12. technical scope: a delivery contract with no product contract ---------
printf 'Plain description.\n' >"$TMP_ROOT/plain.md"
seed_issue 3 "Technical chore" "$TMP_ROOT/plain.md"
run_contract "$repo" write 3 --section delivery --file "$DELIVERY_A" --json
expect_status 0 $? "a delivery contract can be written without a product contract"
[ "$(printf '%s' "$OUTPUT" | jget stamp.fp)" = "none" ] && ok "it is stamped fp=none" || no "it is stamped fp=none" "$OUTPUT"
body="$(issue_body 3)"
contains "the plain description is kept below the section" "Plain description." "$body"
contains "the human stamp says it was planned without a product contract" "planned without a product contract" "$body"
run_contract "$repo" check 3
expect_status 30 $? "check on a technical-scope issue is NO_PRODUCT"
contains "NO_PRODUCT says there is no Linear reference either" "no Linear reference either" "$OUTPUT"
contains "a technical-scope check still runs the code comparison" "status: NO_CHANGE" "$OUTPUT"
commit_push "$repo" skills/scope/SKILL.md "technical-scope drift"
run_contract "$repo" check 3
expect_status 30 $? "code drift on a technical-scope issue keeps exit 30"
contains "but the drift is reported for the paragraph" "CODE_DRIFT" "$OUTPUT"
contains "and names the changed file" "skills/scope/SKILL.md" "$OUTPUT"
run_contract "$repo" write 3 --section delivery --file "$DELIVERY_A"
expect_status 0 $? "re-plan the technical issue at the new tip"

# --- 13. legacy Linear scope is surfaced for the read-only compatibility path ---
cat >"$TMP_ROOT/legacy-linear.md" <<'EOF'
## Scope authority

- **Scope basis:** Linear
- **Linear:** [VOL-123](https://linear.app/volta/issue/VOL-123/some-title)
- **Scope version:** 2026-09-01T10:00:00.000Z
EOF
seed_issue 4 "Legacy Linear-scoped issue" "$TMP_ROOT/legacy-linear.md"
run_contract "$repo" check 4
expect_status 30 $? "check on a legacy Linear-scoped issue is NO_PRODUCT"
contains "the Linear identifier is reported for the compatibility path" "VOL-123" "$OUTPUT"
run_contract "$repo" read 4 --json
[ "$(printf '%s' "$OUTPUT" | jget linear)" = '["VOL-123"]' ] && ok "read lists the Linear reference once" || no "read lists the Linear reference once" "$OUTPUT"
run_contract "$repo" write 4 --section product --file "$PRODUCT_A"
expect_status 0 $? "scope can add a product contract on top of a legacy body"
body="$(issue_body 4)"
python3 - "$body" <<'EOF' && ok "the product section is inserted first and the legacy text kept" || no "legacy insertion order"
import sys
b = sys.argv[1]
assert b.startswith("<!-- contract:product "), b[:80]
assert "**Linear:** [VOL-123]" in b, b
EOF

# --- 14. an epic child plans against the parent's product contract -------------
seed_issue 5 "Child of #2" "$TMP_ROOT/plain.md" 2
run_contract "$repo" write 5 --section delivery --file "$DELIVERY_A" --product-issue 2 --json
expect_status 0 $? "a child delivery contract can name the parent's product contract"
[ "$(printf '%s' "$OUTPUT" | jget stamp.product)" = "#2" ] && ok "the child stamp names the parent" || no "the child stamp names the parent" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget stamp.fp)" = "$fp_a" ] && ok "the child stamp carries the parent's fingerprint" || no "the child stamp carries the parent's fingerprint" "$OUTPUT"
run_contract "$repo" check 5
expect_status 0 $? "check on the child follows the stamp to the parent"
run_contract "$repo" read 5 --json
expect_status 0 $? "read on the child succeeds"
[ "$(printf '%s' "$OUTPUT" | jget product_issue)" = "2" ] && ok "read on the child names the parent as the product issue" || no "read on the child names the parent" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget product.fingerprint)" = "$fp_a" ] && ok "read on the child includes the parent's product contract" || no "read on the child includes the parent's product contract" "$OUTPUT"
run_contract "$repo" read 5 --section product
expect_status 0 $? "read --section product on the child prints the parent's product text"
run_contract "$repo" read 5
contains "the summary says where the product contract came from" "product contract (from #2)" "$OUTPUT"
run_contract "$repo" write 2 --section product --file "$PRODUCT_B"
expect_status 0 $? "the parent product contract moves to v2"
run_contract "$repo" check 5
expect_status 10 $? "the child now reports CONTRACT_DRIFT against its parent"
seed_issue 6 "Child without stamp" "$TMP_ROOT/plain.md" 2
run_contract "$repo" write 6 --section delivery --file "$DELIVERY_A" --json
expect_status 0 $? "a child with a GitHub parent inherits the parent's product contract without --product-issue"
[ "$(printf '%s' "$OUTPUT" | jget stamp.product)" = "#2" ] && ok "the inherited parent is stamped" || no "the inherited parent is stamped" "$OUTPUT"
run_contract "$repo" write 6 --section delivery --file "$DELIVERY_A" --product-issue 3
expect_status 30 $? "naming a product issue that has no product contract is refused"

# --- 15. dry runs write nothing --------------------------------------------------
before="$(edit_calls)"
run_contract "$repo" write 2 --section product --file "$PRODUCT_A" --dry-run
expect_status 0 $? "dry run exits 0"
contains "dry run shows the body it would write" "<!-- contract:product v=3" "$OUTPUT"
[ "$(edit_calls)" = "$before" ] && ok "dry run makes no edit call" || no "dry run makes no edit call"
run_contract "$repo" create --title "Never created" --file "$PRODUCT_A" --dry-run
expect_status 0 $? "create --dry-run exits 0"
[ ! -f "$STORE/7.json" ] && ok "create --dry-run creates nothing" || no "create --dry-run creates nothing"

# --- 16. a lost write is caught by the read-back --------------------------------
GH_STUB_EDIT_NOOP=1 run_contract "$repo" write 2 --section product --file "$PRODUCT_A"
expect_status 11 $? "a write GitHub did not keep is reported as a read-back mismatch"
contains "the mismatch is explained" "after the write does not match" "$OUTPUT"

# --- 17. CRLF from GitHub does not break the read-back or the fingerprint -------
GH_STUB_CRLF=1 run_contract "$repo" write 2 --section product --file "$PRODUCT_A"
expect_status 0 $? "a CRLF read-back still verifies"
GH_STUB_CRLF=1 run_contract "$repo" check 5
expect_status 0 $? "check reads CRLF bodies and still matches the fingerprint"

# --- 18. gh failures are errors, not silent results -----------------------------
GH_STUB_FAIL=1 run_contract "$repo" check 2
expect_status 1 $? "a gh failure is exit 1"
contains "the gh error is reported" "api.github.com" "$OUTPUT"
run_contract "$repo" check 99
expect_status 1 $? "a missing issue is exit 1"

# --- 19. refusals on bad input ---------------------------------------------------
printf '\n\n' >"$TMP_ROOT/empty.md"
run_contract "$repo" write 2 --section product --file "$TMP_ROOT/empty.md"
expect_status 1 $? "empty section text is refused"
printf '## Outcome\n\n<!-- contract:product v=9 fp=x at=y -->\n' >"$TMP_ROOT/markers.md"
run_contract "$repo" write 2 --section product --file "$TMP_ROOT/markers.md"
expect_status 1 $? "section text carrying contract markers is refused"
elsewhere="$(new_repo elsewhere)"
(cd "$elsewhere" && git remote set-url origin https://github.com/someone/else.git)
run_contract "$elsewhere" write 2 --section product --file "$PRODUCT_B"
expect_status 1 $? "stamping from a checkout of another repository is refused"
contains "the refusal names both repositories" "someone/else" "$OUTPUT"
run_contract "$elsewhere" write 2 --section product --file "$PRODUCT_B" --commit abc12345 --json
expect_status 0 $? "--commit lets the caller supply the scoped-at commit instead"
[ "$(printf '%s' "$OUTPUT" | jget stamp.at)" = "abc12345" ] && ok "the supplied commit is stamped" || no "the supplied commit is stamped" "$OUTPUT"

# --- 20. a hand-edited product section is noticed -------------------------------
python3 - "$STORE/2.json" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["body"] = d["body"].replace("Agents plan from one issue, always.", "Agents plan from one issue, edited by hand."); json.dump(d, open(p, "w"))
EOF
run_contract "$repo" write 5 --section delivery --file "$DELIVERY_A" --product-issue 2
expect_status 0 $? "re-plan the child against the hand-edited parent"
run_contract "$repo" check 5 --no-code
expect_status 0 $? "check still runs"
contains "check notes the product contract was edited outside /scope" "edited outside /scope" "$OUTPUT"

# --- 21. --commit must be a commit id -------------------------------------------
before="$(edit_calls)"
run_contract "$elsewhere" write 2 --section product --file "$PRODUCT_B" --commit main
expect_status 1 $? "a branch name is refused as --commit"
contains "the refusal states the rule" "7-40 hex" "$OUTPUT"
run_contract "$elsewhere" write 2 --section product --file "$PRODUCT_B" --commit "feature x"
expect_status 1 $? "a value that would break the marker is refused as --commit"
[ "$(edit_calls)" = "$before" ] && ok "refused --commit values make no edit call" || no "refused --commit values make no edit call"

# --- 22. scoped-at is the default-branch tip, not HEAD --------------------------
repo2="$(new_repo tipcheck)"
(cd "$repo2" && git checkout -qb feature/x && echo local >>other/notes.md && git commit -qam "local only")
run_contract "$repo2" create --title "Tip check" --file "$PRODUCT_A" --json
expect_status 0 $? "create from a feature branch with local commits"
n2="$(printf '%s' "$OUTPUT" | jget number)"
at2="$(printf '%s' "$OUTPUT" | jget stamp.at)"
[ "$at2" = "$(tip "$repo2")" ] && ok "scoped-at is origin's default-branch tip" || no "scoped-at is origin's default-branch tip" "$at2 vs $(tip "$repo2")"
[ "$at2" != "$(git -C "$repo2" rev-parse --short=8 HEAD)" ] && ok "scoped-at is not the feature-branch HEAD" || no "scoped-at is not the feature-branch HEAD"

# --- 23. check from a subdirectory still sees drift under the watched paths -----
run_contract "$repo2" write "$n2" --section delivery --file "$DELIVERY_A" --product-fingerprint "$fp_a"
expect_status 0 $? "delivery planned on the tip-check issue"
commit_push "$repo2" skills/scope/SKILL.md "watched change"
run_contract "$repo2/skills" check "$n2"
expect_status 12 $? "check run from a subdirectory reports the watched change"
contains "the subdirectory check names the file" "skills/scope/SKILL.md" "$OUTPUT"
run_contract "$repo2/skills" drift --since "$(printf '%s' "$OUTPUT" | sed -n 's/^code drift \([0-9a-f]*\)\.\..*/\1/p' | head -1)" -- skills/scope
expect_status 12 $? "drift run from a subdirectory with root-relative paths sees the change"
run_contract "$repo2" check "$n2" --no-fetch
expect_status 12 $? "--no-fetch still compares against the last known tip"

# --- 24. a wrapped Paths watched bullet keeps every path ------------------------
DELIVERY_WRAPPED="$TMP_ROOT/delivery-wrapped.md"
printf '## Drift report\n\n- **Paths watched:** `skills/scope/`,\n  `other/notes.md`\n- **What changed:** nothing.\n\n## Requirement-to-proof matrix\n\n| Scope ID | Required behavior |\n|---|---|\n| SR-01 / AC-1 | wrapped |\n' >"$DELIVERY_WRAPPED"
run_contract "$repo2" write "$n2" --section delivery --file "$DELIVERY_WRAPPED" --product-fingerprint "$fp_a"
expect_status 0 $? "delivery with a wrapped Paths watched bullet is written"
run_contract "$repo2" read "$n2" --json
[ "$(printf '%s' "$OUTPUT" | jget delivery.paths_watched)" = '["skills/scope/", "other/notes.md"]' ] && ok "both paths of the wrapped bullet are watched" || no "both paths of the wrapped bullet are watched" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget delivery.matrix_identifiers.AC)" = '["AC-1"]' ] && ok "AC-1 is read from the matrix" || no "AC-1 is read from the matrix" "$OUTPUT"
run_contract "$repo2" check "$n2" --no-code --json
[ "$(printf '%s' "$OUTPUT" | jget not_in_matrix)" = '["SR-02"]' ] && ok "AC-1 in the matrix satisfies AC-01 in the product contract" || no "AC-1 satisfies AC-01" "$OUTPUT"

# --- 25. text before and between the sections survives a rewrite byte for byte --
printf 'Intro Matt typed.\n' >"$TMP_ROOT/intro.md"
seed_issue 40 "Intro issue" "$TMP_ROOT/intro.md"
run_contract "$repo2" write 40 --section product --file "$PRODUCT_A"
run_contract "$repo2" write 40 --section delivery --file "$DELIVERY_A" --product-fingerprint "$fp_a"
python3 - "$STORE/40.json" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["body"] = "Hand-written preamble\n\n" + d["body"]; json.dump(d, open(p, "w"))
EOF
before_body="$(issue_body 40)"
run_contract "$repo2" write 40 --section product --file "$PRODUCT_B"
expect_status 0 $? "rewrite the product section of an issue with text before and after it"
python3 - "$before_body" "$(issue_body 40)" <<'EOF' && ok "everything outside the product section is byte-identical after the rewrite" || no "text outside the product section changed"
import sys
before, after = sys.argv[1], sys.argv[2]
def outside(b):
    start = b.index("<!-- contract:product "); end = b.index("<!-- /contract:product -->") + len("<!-- /contract:product -->")
    return b[:start], b[end:]
assert outside(before) == outside(after), (outside(before), outside(after))
assert outside(after)[0].startswith("Hand-written preamble")
assert "Intro Matt typed." in outside(after)[1] and "<!-- contract:delivery " in outside(after)[1]
EOF

# --- 26. an edit that lands while the write is prepared is not overwritten ------
before="$(edit_calls)"
GH_STUB_RACE=1 run_contract "$repo2" write 40 --section product --file "$PRODUCT_A"
expect_status 10 $? "a body that changed between read and write is refused"
contains "the refusal says the body changed meanwhile" "changed while this write" "$OUTPUT"
[ "$(edit_calls)" = "$before" ] && ok "the raced write makes no edit call" || no "the raced write makes no edit call"

# --- 27. the written text must be the approved text -----------------------------
before="$(edit_calls)"
run_contract "$repo2" write 40 --section product --file "$PRODUCT_A" --approved-fingerprint "$fp_b"
expect_status 10 $? "text that no longer matches the approved fingerprint is refused"
contains "the refusal names both fingerprints" "$fp_a" "$OUTPUT"
[ "$(edit_calls)" = "$before" ] && ok "the unapproved write makes no edit call" || no "the unapproved write makes no edit call"
run_contract "$repo2" write 40 --section product --file "$PRODUCT_A" --approved-fingerprint "$fp_a"
expect_status 0 $? "text matching the approved fingerprint is written"

# --- 28. an epic child is created under the parent that holds the product contract
run_contract "$repo2" create --section delivery --title "Child of $n2" --file "$DELIVERY_A" --parent "$n2" --product-issue "$n2" --label child --json
expect_status 0 $? "create --section delivery with --parent and --product-issue"
[ "$(printf '%s' "$OUTPUT" | jget stamp.product)" = "#$n2" ] && ok "the created child names the parent in its stamp" || no "the created child names the parent" "$OUTPUT"
grep -q -- "--parent $n2" "$STORE/calls.log" && ok "the parent link is passed to gh issue create" || no "the parent link is passed to gh issue create"
child="$(printf '%s' "$OUTPUT" | jget number)"
run_contract "$repo2" check "$child" --no-code
expect_status 0 $? "check on the created child follows its stamp to the parent"

# --- 29. a create whose body did not land names the new issue -------------------
GH_STUB_CREATE_EMPTY=1 run_contract "$repo2" create --title "Lost body" --file "$PRODUCT_A"
expect_status 11 $? "a created issue with a lost body is a read-back mismatch"
contains "the error says the issue exists and must not be recreated" "do not create again" "$OUTPUT"
contains "the error names the issue URL" "https://github.com/test/repo/issues/" "$OUTPUT"

# --- 30. malformed and unreadable sections are errors, not tracebacks -----------
printf '<!-- contract:product v=1 fp=abcd1234 at=abcd1234 date=2026-01-01 -->\n# Product contract\n\nno end marker\n' >"$TMP_ROOT/malformed.md"
seed_issue 41 "Malformed" "$TMP_ROOT/malformed.md"
run_contract "$repo2" check 41
expect_status 1 $? "a start marker without a body or end marker is refused"
contains "the refusal says malformed" "malformed" "$OUTPUT"
python3 - "$STORE/40.json" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["body"] = d["body"].replace("<!-- contract:product v=3 ", "<!-- contract:product v=abc ", 1); json.dump(d, open(p, "w"))
EOF
run_contract "$repo2" write 40 --section product --file "$PRODUCT_B"
expect_status 1 $? "a hand-edited version stamp is reported, not a traceback"
contains "the message says the stamp is unreadable" "unreadable" "$OUTPUT"
lacks "no Python traceback leaks" "Traceback" "$OUTPUT"

# --- 31. read --section exit codes ---------------------------------------------
run_contract "$repo2" read 2 --section delivery
expect_status 20 $? "read --section delivery on a scoped-only issue is 20"
run_contract "$repo2" read 3 --section product
expect_status 30 $? "read --section product on a technical issue is 30"

# --- 32. same text, wrong stamp: re-stamped at the same version -----------------
seed_issue 42 "Restamp" "$TMP_ROOT/plain.md"
run_contract "$repo2" write 42 --section product --file "$PRODUCT_A"
python3 - "$STORE/42.json" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["body"] = d["body"].replace("fp=", "fp=dead", 1); json.dump(d, open(p, "w"))
EOF
run_contract "$repo2" write 42 --section product --file "$PRODUCT_A" --json
expect_status 0 $? "writing the same text over a hand-edited stamp succeeds"
[ "$(printf '%s' "$OUTPUT" | jget status)" = "WRITTEN" ] && ok "it is WRITTEN, not ALREADY_CURRENT" || no "it is WRITTEN" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget stamp.v)" = "1" ] && ok "the version does not change for a re-stamp" || no "the version does not change for a re-stamp" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget stamp.fp)" = "$fp_a" ] && ok "the stamp is corrected" || no "the stamp is corrected" "$OUTPUT"

# --- 33. an empty body and a usage error ----------------------------------------
: >"$TMP_ROOT/emptybody.md"
seed_issue 43 "Empty body" "$TMP_ROOT/emptybody.md"
run_contract "$repo2" write 43 --section product --file "$PRODUCT_A"
expect_status 0 $? "a product section is written into an empty body"
[ "$(issue_body 43 | head -c 22)" = "<!-- contract:product " ] && ok "the empty body now starts with the section" || no "the empty body now starts with the section"
run_contract "$repo2" write
expect_status 2 $? "a usage error exits 2"

# --- 34. an epic child in another repository plans against its cross-repo parent
# The product contract sits on coach/repo#477; the child is founder/repo#97.
seed_issue 477 "Office hours" "$TMP_ROOT/plain.md" "" coach/repo
run_contract "$repo2" write 477 -R coach/repo --section product --file "$PRODUCT_A" --commit abcdef1
expect_status 0 $? "the cross-repo parent gets a product contract"
seed_issue 97 "Founder side of office hours" "$TMP_ROOT/plain.md" "coach/repo#477" founder/repo
: >"$STORE/calls.log"
run_contract "$repo2" write 97 -R founder/repo --section delivery --file "$DELIVERY_A" --json
expect_status 0 $? "a child inherits the product contract of a parent in another repository"
[ "$(printf '%s' "$OUTPUT" | jget stamp.product)" = "coach/repo#477" ] && ok "the inherited cross-repo parent is stamped with its repository" || no "the inherited cross-repo parent is stamped with its repository" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget stamp.fp)" = "$fp_a" ] && ok "the child stamp carries the cross-repo parent's fingerprint" || no "the child stamp carries the cross-repo parent's fingerprint" "$OUTPUT"
grep -q "^issue view 477 -R coach/repo " "$STORE/calls.log" && ! grep -q "^issue view 477 -R founder/repo " "$STORE/calls.log" && ok "the parent is fetched from its own repository" || no "the parent is fetched from its own repository"
run_contract "$repo2" check 97 -R founder/repo --no-code --json
expect_status 0 $? "check on the cross-repo child follows its stamp to the parent"
[ "$(printf '%s' "$OUTPUT" | jget product_repo)" = "coach/repo" ] && ok "check names the parent's repository" || no "check names the parent's repository" "$OUTPUT"
run_contract "$repo2" read 97 -R founder/repo
contains "the summary names the cross-repo product issue" "product contract (from coach/repo#477)" "$OUTPUT"
seed_issue 98 "Founder issue with no parent" "$TMP_ROOT/plain.md" "" founder/repo
run_contract "$repo2" write 98 -R founder/repo --section delivery --file "$DELIVERY_A" --product-issue coach/repo#477 --json
expect_status 0 $? "--product-issue accepts owner/repo#N"
[ "$(printf '%s' "$OUTPUT" | jget stamp.product)" = "coach/repo#477" ] && ok "the named cross-repo product issue is stamped" || no "the named cross-repo product issue is stamped" "$OUTPUT"
[ "$(printf '%s' "$OUTPUT" | jget stamp.fp)" = "$fp_a" ] && ok "the named cross-repo product fingerprint is stamped, not fp=none" || no "the named cross-repo product fingerprint is stamped" "$OUTPUT"
run_contract "$repo2" create -R founder/repo --section delivery --title "Another founder child" --file "$DELIVERY_A" --product-issue coach/repo#477 --commit abcdef1 --json
expect_status 0 $? "create --product-issue accepts owner/repo#N"
[ "$(printf '%s' "$OUTPUT" | jget stamp.product)" = "coach/repo#477" ] && ok "the created child names the cross-repo product issue" || no "the created child names the cross-repo product issue" "$OUTPUT"
run_contract "$repo2" write 477 -R coach/repo --section product --file "$PRODUCT_B" --commit abcdef1
expect_status 0 $? "the cross-repo product contract moves to v2"
run_contract "$repo2" check 98 -R founder/repo --no-code
expect_status 10 $? "the cross-repo child reports CONTRACT_DRIFT against the moved product contract"
run_contract "$repo2" write 98 -R founder/repo --section delivery --file "$DELIVERY_A" --product-issue coach/repo
expect_status 2 $? "a malformed --product-issue is a usage error"
run_contract "$repo2" write 98 -R founder/repo --section delivery --file "$DELIVERY_A" --product-issue coach/repo2
expect_status 2 $? "a repository without # before the number is a usage error, not a different repository's issue"
seed_issue 99 "Child of an unreadable parent link" "$TMP_ROOT/plain.md" "" founder/repo
python3 - "$STORE/founder__repo/99.json" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["parent"] = {"number": 477, "url": "https://ghe.example.com/coach/repo/issues/477"}; json.dump(d, open(p, "w"))
EOF
seed_issue 477 "Same number, unrelated issue" "$TMP_ROOT/plain.md" "" founder/repo
run_contract "$repo2" write 477 -R founder/repo --section product --file "$PRODUCT_A" --commit abcdef1
run_contract "$repo2" check 99 -R founder/repo --no-code
expect_status 1 $? "a parent link the script cannot read is an error, not a guess at the child's repository"
contains "the error names the unreadable parent link" "ghe.example.com" "$OUTPUT"

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
