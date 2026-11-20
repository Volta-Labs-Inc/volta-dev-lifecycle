#!/usr/bin/env python3
"""contract.py - the product and delivery contract sections of a GitHub issue.

One GitHub issue per outcome carries two fixed sections. The product contract is
written only by /scope; the delivery contract is written by /document directly
below it. For an epic the product contract sits on the parent and each child
carries its own delivery contract. This script owns the mechanics so that no
skill edits an issue body by hand:

  - splicing one section into the body without touching the other section or
    any text the script did not write;
  - the content fingerprint that stamps each product contract (first 8 hex
    characters of a SHA-256 over the normalized section text) and the version
    that increments only when that fingerprint changes;
  - the delivery contract's record of which product contract (version and
    fingerprint) and which default-branch commit it was planned against;
  - the drift checks: contract drift (the product fingerprint moved since the
    delivery contract was planned) and code drift (what changed on the default
    branch, under the paths the delivery contract watches, since planning);
  - a read-back after every write that verifies the body and the fingerprint.

The script never decides anything on its own. Every write still goes through
the skill's approval card and the user's explicit approval; the script only
makes the approved write exact and checkable.

Usage:
  contract.py fingerprint <file|-> [--section product|delivery] [--json]
  contract.py read <issue> [-R owner/repo] [--section product|delivery] [--repo-path DIR] [--json]
  contract.py create --title <title> --file <section.md> [--section product|delivery]
                     [-R owner/repo] [--label L ...] [--parent N] [--product-issue [owner/repo]#N]
                     [--product-fingerprint FP] [--approved-fingerprint FP]
                     [--commit SHA | --repo-path DIR] [--no-fetch] [--dry-run] [--json]
  contract.py write <issue> --section product|delivery --file <section.md>
                     [-R owner/repo] [--expect-fingerprint FP] [--product-fingerprint FP]
                     [--approved-fingerprint FP] [--product-issue [owner/repo]#N]
                     [--commit SHA | --repo-path DIR] [--no-fetch] [--dry-run] [--json]
  contract.py check <issue> [-R owner/repo] [--repo-path DIR] [--no-code] [--no-fetch] [--json]
  contract.py drift --since SHA [--until SHA] [--repo-path DIR] [--no-fetch] [--json] [--] [path ...]

--repo-path may be any directory inside the checkout; git questions are asked at its root.
--commit must be a commit id (7-40 hex characters), never a branch or tag name.
--product-issue takes N, #N, or owner/repo#N; an epic parent in another repository is
followed automatically, and its delivery stamp records product=owner/repo#N.

Exit codes:
  0   done: written, already current, or in sync
  10  refused: the section on GitHub is not the one the caller expected (stale), the
      text differs from the approved draft, the body changed while the write was
      being prepared, or the product contract changed since the delivery contract
      was planned
  11  the write landed but the read-back does not match what was approved
  12  code drift: files under the watched paths changed since the delivery
      contract was planned (contract itself in sync)
  20  the issue has no delivery contract
  30  no product contract is reachable from the issue (a technical-scope issue
      still gets its code-drift lines)
  1   error: gh or git failure, unknown commit, malformed section
  2   usage error (argparse)

Testing: set GH_BIN to a stub executable to avoid live GitHub calls.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

GH_BIN = os.environ.get("GH_BIN", "gh")
FINGERPRINT_LENGTH = 8
SECTION_KINDS = ("product", "delivery")
SECTION_TITLES = {"product": "Product contract", "delivery": "Delivery contract"}

EXIT_OK = 0
EXIT_STALE = 10
EXIT_READBACK = 11
EXIT_CODE_DRIFT = 12
EXIT_NO_DELIVERY = 20
EXIT_NO_PRODUCT = 30
EXIT_ERROR = 1

START_RE = re.compile(r"<!--\s*contract:(product|delivery)((?:\s+[a-z-]+=[^\s>]+)*)\s*-->[ \t]*\n?")
ATTR_RE = re.compile(r"([a-z-]+)=([^\s>]+)")
ID_RE = re.compile(r"\b(SR|AC|TR|D)-\d+(?:\.\d+)*\b")
MATRIX_HEADING_RE = re.compile(r"^#+\s*Requirement-to-proof matrix", re.I | re.M)
NEXT_H2_RE = re.compile(r"^##\s", re.M)
PATHS_WATCHED_RE = re.compile(
    r"^\s*(?:[-*]\s*)?\**\s*Paths watched\s*:?\**\s*:?\s*(.+?)\s*$", re.I | re.M
)
LINEAR_URL_RE = re.compile(r"https?://linear\.app/[^/\s]+/issue/([A-Z][A-Z0-9]*-\d+)")
LINEAR_FIELD_RE = re.compile(
    r"^\s*(?:[-*]\s*)?\**\s*Linear\s*:?\**\s*:?\s*\[?([A-Z][A-Z0-9]*-\d+)\b", re.M
)
ISSUE_URL_RE = re.compile(r"https://github\.com/[^/\s]+/[^/\s]+/issues/(\d+)")
ISSUE_URL_REPO_RE = re.compile(r"^https://github\.com/([^/\s]+/[^/\s]+)/issues/(\d+)")
# A repository must be followed by #, so owner/repo2 is refused rather than read as owner/repo issue 2.
ISSUE_REF_RE = re.compile(r"^(?:([\w.-]+/[\w.-]+)#|#)?(\d+)$")
COMMIT_RE = re.compile(r"^[0-9a-f]{7,40}$")
SECTION_HEADING_RE = re.compile(r"#\s+(Product|Delivery) contract\s*", re.I)


class ContractError(Exception):
    def __init__(self, message: str, exit_code: int = EXIT_ERROR) -> None:
        super().__init__(message)
        self.exit_code = exit_code


# --- text -----------------------------------------------------------------------


def normalize(text: str) -> str:
    """Line endings to LF, trailing whitespace off every line, no blank edges.

    GitHub returns the stored body with whatever line endings it was saved with
    (the web editor saves CRLF), so the fingerprint must not depend on them.
    """
    lines = [line.rstrip() for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines) + "\n" if lines else ""


def fingerprint(text: str) -> str:
    return hashlib.sha256(normalize(text).encode("utf-8")).hexdigest()[:FINGERPRINT_LENGTH]


def normalize_id(identifier: str) -> str:
    """AC-01 and AC-1 name the same requirement (the progress mod agrees)."""
    return re.sub(r"\d+", lambda m: str(int(m.group(0))), identifier.upper())


def identifiers(text: str) -> Dict[str, List[str]]:
    found: Dict[str, List[str]] = {"SR": [], "AC": [], "D": [], "TR": []}
    seen = set()
    for match in ID_RE.finditer(text):
        key = normalize_id(match.group(0))
        if key in seen:
            continue
        seen.add(key)
        found[match.group(1).upper()].append(match.group(0).upper())
    return found


def matrix_slice(delivery_content: str) -> str:
    """The requirement-to-proof matrix, cut the way the orchestrate-progress mod cuts it:
    from the matrix heading to the next level-two heading."""
    start = MATRIX_HEADING_RE.search(delivery_content)
    if not start:
        return ""
    rest = delivery_content[start.start():]
    end = NEXT_H2_RE.search(rest, 1)
    return rest if not end else rest[: end.start()]


def watched_paths(delivery_content: str) -> List[str]:
    """The `Paths watched:` field of the drift report. A Markdown bullet may wrap
    onto indented continuation lines; they belong to the field until a blank line
    or the next bullet."""
    match = PATHS_WATCHED_RE.search(delivery_content)
    if not match:
        return []
    line = match.group(1)
    rest = delivery_content[match.end():].split("\n")[1:]
    for continuation in rest:
        if not continuation.strip() or not continuation[:1].isspace() or re.match(r"^\s*[-*]\s", continuation):
            break
        line += " " + continuation.strip()
    tokens = re.findall(r"`([^`]+)`", line) or [part.strip() for part in line.split(",")]
    paths = [token.strip() for token in tokens if token.strip()]
    if len(paths) == 1 and paths[0].lower().rstrip(".") in {"none", "n/a", "whole repository"}:
        return []
    return paths


def linear_refs(body: str) -> List[str]:
    refs: List[str] = []
    for match in list(LINEAR_URL_RE.finditer(body)) + list(LINEAR_FIELD_RE.finditer(body)):
        if match.group(1) not in refs:
            refs.append(match.group(1))
    return refs


def today() -> str:
    return datetime.now(timezone.utc).date().isoformat()


def stamp_int(value: Optional[str], what: str) -> int:
    try:
        return int(str(value).lstrip("#"))
    except (TypeError, ValueError):
        raise ContractError(
            f"the {what} stamp is unreadable ({value!r}); the hidden marker was edited by hand. "
            "Repair the marker's value in the issue body (for example v=2), then rerun"
        )


IssueRef = Tuple[str, int]


def parse_issue_ref(value: Optional[str]) -> Optional[Tuple[Optional[str], int]]:
    """N, #N, or owner/repo#N. No repository means the issue's own repository."""
    match = ISSUE_REF_RE.match(str(value or "").strip())
    if not match:
        return None
    return match.group(1), int(match.group(2))


def issue_ref_arg(value: str) -> Tuple[Optional[str], int]:
    ref = parse_issue_ref(value)
    if ref is None:
        raise argparse.ArgumentTypeError(f"expected N, #N or owner/repo#N, not {value!r}")
    return ref


def stamp_ref(value: Optional[str], what: str) -> Tuple[Optional[str], int]:
    ref = parse_issue_ref(value)
    if ref is None:
        raise ContractError(
            f"the {what} stamp is unreadable ({value!r}); the hidden marker was edited by hand. "
            "Repair the marker's value in the issue body (for example product=#2 or product=owner/repo#2), then rerun"
        )
    return ref


def same_ref(a: IssueRef, b: IssueRef) -> bool:
    return a[0].lower() == b[0].lower() and a[1] == b[1]


def ref_label(ref: IssueRef, home_repo: str) -> str:
    """#N inside the home repository, owner/repo#N outside it."""
    return f"#{ref[1]}" if ref[0].lower() == home_repo.lower() else f"{ref[0]}#{ref[1]}"


def detect_kind(text: str) -> Optional[str]:
    first = text.lstrip("\n").split("\n", 1)[0]
    match = SECTION_HEADING_RE.fullmatch(first.strip())
    return match.group(1).lower() if match else None


# --- sections -------------------------------------------------------------------


class Section:
    def __init__(self, kind: str, attrs: Dict[str, str], span: Tuple[int, int], content: str) -> None:
        self.kind = kind
        self.attrs = attrs
        self.span = span
        self.content = content

    @property
    def fingerprint(self) -> str:
        return fingerprint(self.content)


def parse_sections(body: str) -> Dict[str, Section]:
    sections: Dict[str, Section] = {}
    for start in START_RE.finditer(body):
        kind = start.group(1)
        if kind in sections:
            raise ContractError(f"the body holds two {kind} contract sections; fix the issue by hand first")
        attrs = dict(ATTR_RE.findall(start.group(2)))
        body_marker = re.compile(r"<!--\s*contract:%s:body\s*-->[ \t]*\n?" % kind).search(body, start.end())
        end_marker = re.compile(r"<!--\s*/contract:%s\s*-->" % kind).search(body, start.end())
        if not body_marker or not end_marker or body_marker.start() > end_marker.start():
            raise ContractError(f"the {kind} contract section is malformed (missing body or end marker)")
        content = body[body_marker.end(): end_marker.start()]
        sections[kind] = Section(kind, attrs, (start.start(), end_marker.end()), content)
    return sections


def prepare_content(kind: str, raw: str) -> str:
    """The agent supplies the text under the section heading. Drop a heading it
    pasted anyway, and refuse text that would break the section markers."""
    text = normalize(raw)
    lines = text.split("\n")
    if lines and re.fullmatch(r"#\s+%s\s*" % re.escape(SECTION_TITLES[kind]), lines[0], re.I):
        lines.pop(0)
        while lines and not lines[0].strip():
            lines.pop(0)
        text = normalize("\n".join(lines))
    if not text.strip():
        raise ContractError(f"the {kind} contract text is empty")
    if re.search(r"<!--\s*/?contract:", text):
        raise ContractError("the section text contains contract markers; remove them, the script writes its own")
    return text


def human_stamp(kind: str, attrs: Dict[str, str]) -> str:
    if kind == "product":
        return (
            "_Product contract v{v} · fingerprint `{fp}` · scoped at default-branch commit `{at}` "
            "· {date} · written by /scope_"
        ).format(**attrs)
    where = f" ({attrs['product']})" if attrs.get("product") else ""
    if attrs.get("fp", "none") == "none":
        planned = "planned without a product contract (technical scope or legacy Linear scope)"
    else:
        planned = "planned against product contract v{v} `{fp}`{where}".format(where=where, **attrs)
    return "_Delivery contract · {planned} at default-branch commit `{at}` · {date} · written by /document_".format(
        planned=planned, **attrs
    )


def render_section(kind: str, content: str, attrs: Dict[str, str]) -> str:
    attr_text = " ".join(f"{key}={value}" for key, value in attrs.items())
    return (
        f"<!-- contract:{kind} {attr_text} -->\n"
        f"# {SECTION_TITLES[kind]}\n\n"
        f"{human_stamp(kind, attrs)}\n\n"
        f"<!-- contract:{kind}:body -->\n"
        f"{normalize(content)}"
        f"<!-- /contract:{kind} -->"
    )


def splice(body: str, kind: str, rendered: str, sections: Dict[str, Section]) -> str:
    """Replace the section in place, or insert it: the product contract goes
    first, the delivery contract directly below the product contract. Text the
    script did not write is kept where it was."""
    body = body.replace("\r\n", "\n").replace("\r", "\n")
    if kind in sections:
        start, end = sections[kind].span
        return body[:start] + rendered + body[end:]
    if kind == "delivery" and "product" in sections:
        _start, end = sections["product"].span
        return body[:end] + "\n\n" + rendered + body[end:]
    rest = body.lstrip("\n")
    return rendered + ("\n\n" + rest if rest.strip() else "\n")


# --- processes ------------------------------------------------------------------


def run(command: List[str], cwd: Optional[str] = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(command, cwd=cwd, capture_output=True, text=True, encoding="utf-8", check=False)
    except FileNotFoundError as exc:
        raise ContractError(f"{command[0]} is not installed or not on PATH") from exc


def gh(args: List[str]) -> str:
    result = run([GH_BIN] + args)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "unknown failure").strip().splitlines()
        raise ContractError(f"gh {' '.join(args[:2])} failed: {detail[-1] if detail else 'unknown failure'}")
    return result.stdout


def git(args: List[str], cwd: str, ok_codes: Tuple[int, ...] = (0,)) -> subprocess.CompletedProcess:
    result = run(["git"] + args, cwd=cwd)
    if result.returncode not in ok_codes:
        detail = (result.stderr or result.stdout or "").strip().splitlines()
        raise ContractError(f"git {' '.join(args[:2])} failed: {detail[-1] if detail else 'unknown failure'}")
    return result


# --- GitHub ---------------------------------------------------------------------


def resolve_repo(repo: Optional[str], cwd: str = ".") -> str:
    if repo:
        return repo
    result = run([GH_BIN, "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"], cwd=os.path.abspath(cwd))
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "unknown failure").strip().splitlines()
        raise ContractError(f"gh repo view failed: {detail[-1] if detail else 'unknown failure'}")
    slug = result.stdout.strip()
    if not slug:
        raise ContractError("could not detect the repository; pass -R owner/repo")
    return slug


def fetch_issue(repo: str, number: int) -> Dict[str, Any]:
    raw = gh(["issue", "view", str(number), "-R", repo, "--json", "number,title,state,url,body,parent,labels"])
    try:
        issue = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ContractError(f"gh returned an unreadable issue #{number}") from exc
    issue["body"] = (issue.get("body") or "").replace("\r\n", "\n").replace("\r", "\n")
    return issue


def edit_issue_body(repo: str, number: int, body: str) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as handle:
        handle.write(body)
        path = handle.name
    try:
        gh(["issue", "edit", str(number), "-R", repo, "--body-file", path])
    finally:
        os.unlink(path)


def create_issue(repo: str, title: str, body: str, labels: List[str], parent: Optional[int]) -> Tuple[int, str]:
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as handle:
        handle.write(body)
        path = handle.name
    args = ["issue", "create", "-R", repo, "--title", title, "--body-file", path]
    for label in labels:
        args += ["--label", label]
    if parent:
        args += ["--parent", str(parent)]
    try:
        output = gh(args)
    finally:
        os.unlink(path)
    urls = ISSUE_URL_RE.findall(output)
    if len(urls) != 1:
        raise ContractError(
            "issue creation returned no single issue URL; check GitHub before retrying:\n" + output.strip()
        )
    url_match = ISSUE_URL_RE.search(output)
    assert url_match is not None
    return int(url_match.group(1)), url_match.group(0)


# --- git ------------------------------------------------------------------------


def is_git_checkout(path: str) -> bool:
    result = run(["git", "rev-parse", "--is-inside-work-tree"], cwd=path)
    return result.returncode == 0 and result.stdout.strip() == "true"


def repo_root(path: str) -> str:
    """Pathspecs given to git log/diff are relative to the directory git runs in,
    so every git question is asked at the top of the checkout."""
    path = os.path.abspath(path)
    if not os.path.isdir(path):
        raise ContractError(f"{path} is not a directory")
    if not is_git_checkout(path):
        raise ContractError(f"{path} is not inside a git checkout; pass --repo-path or --commit")
    return git(["rev-parse", "--show-toplevel"], path).stdout.strip()


def repo_slug_of_checkout(path: str) -> Optional[str]:
    result = run(["git", "remote", "get-url", "origin"], cwd=path)
    if result.returncode != 0:
        return None
    url = result.stdout.strip()
    url = re.sub(r"^git@([^:]+):", r"https://\1/", url)
    url = re.sub(r"^ssh://git@([^/]+)/", r"https://\1/", url)
    url = re.sub(r"\.git/?$", "", url).rstrip("/")
    match = re.search(r"github\.com/([^/]+/[^/]+)$", url)
    return match.group(1) if match else None


def ensure_checkout_of(repo: str, path: str) -> str:
    """Return the root of the checkout at path after confirming it is a checkout of repo."""
    root = repo_root(path)
    slug = repo_slug_of_checkout(root)
    if slug and slug.lower() != repo.lower():
        raise ContractError(
            f"{root} is a checkout of {slug}, not {repo}; run from a checkout of {repo} or pass --commit"
        )
    return root


def default_branch(cwd: str) -> str:
    result = run(["git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], cwd=cwd)
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip().split("/", 1)[1] if "/" in result.stdout.strip() else result.stdout.strip()
    for candidate in ("main", "master"):
        if run(["git", "rev-parse", "--verify", "--quiet", f"refs/remotes/origin/{candidate}"], cwd=cwd).returncode == 0:
            return candidate
        if run(["git", "rev-parse", "--verify", "--quiet", f"refs/heads/{candidate}"], cwd=cwd).returncode == 0:
            return candidate
    raise ContractError("could not determine the default branch; set origin/HEAD or pass --commit")


def default_branch_tip(cwd: str, fetch: bool = True) -> Tuple[str, str, List[str]]:
    """Return (short sha, ref used, notes). Fetches origin first so the commit
    is the default branch as GitHub has it, not as this checkout last saw it."""
    notes: List[str] = []
    branch = default_branch(cwd)
    has_origin = run(["git", "remote", "get-url", "origin"], cwd=cwd).returncode == 0
    if has_origin and fetch:
        fetched = run(["git", "fetch", "--quiet", "origin", branch], cwd=cwd)
        if fetched.returncode != 0:
            notes.append(f"fetch of origin/{branch} failed; using the last known tip")
    for ref in ([f"origin/{branch}"] if has_origin else []) + [branch]:
        result = run(["git", "rev-parse", "--short=8", "--verify", "--quiet", ref], cwd=cwd)
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip(), ref, notes
    raise ContractError(f"could not resolve the tip of {branch}")


def resolve_commit(cwd: str, ref: str) -> str:
    result = run(["git", "rev-parse", "--short=8", "--verify", "--quiet", ref + "^{commit}"], cwd=cwd)
    if result.returncode != 0 or not result.stdout.strip():
        raise ContractError(f"commit {ref} is not known to the checkout at {cwd}")
    return result.stdout.strip()


def code_drift(cwd: str, since: str, until: Optional[str], paths: List[str], fetch: bool = True) -> Dict[str, Any]:
    notes: List[str] = []
    if until:
        until_sha, until_ref = resolve_commit(cwd, until), until
    else:
        # Fetch first: the planning commit may exist only on origin so far.
        until_sha, until_ref, fetch_notes = default_branch_tip(cwd, fetch=fetch)
        notes += fetch_notes
    since_sha = resolve_commit(cwd, since)
    pathspec = ["--"] + paths if paths else []
    ancestor = run(["git", "merge-base", "--is-ancestor", since_sha, until_sha], cwd=cwd).returncode == 0
    if not ancestor:
        notes.append(f"{since_sha} is not an ancestor of {until_sha}; the default branch history moved under it")
    log = git(["log", "--no-decorate", "--format=%h %s", f"{since_sha}..{until_sha}"] + pathspec, cwd).stdout
    commits = [line for line in log.splitlines() if line.strip()]
    status = git(["diff", "--name-status", since_sha, until_sha] + pathspec, cwd).stdout
    files = [line for line in status.splitlines() if line.strip()]
    shortstat = git(["diff", "--shortstat", since_sha, until_sha] + pathspec, cwd).stdout.strip()
    return {
        "since": since_sha,
        "until": until_sha,
        "until_ref": until_ref,
        "paths": paths,
        "commits": commits,
        "files": files,
        "shortstat": shortstat,
        "changed": bool(files),
        "notes": notes,
    }


def format_drift(report: Dict[str, Any]) -> str:
    watching = ", ".join(report["paths"]) if report["paths"] else "the whole repository (no paths watched)"
    lines = [f"code drift {report['since']}..{report['until']} ({report['until_ref']}), watching: {watching}"]
    lines.append(f"commits: {len(report['commits'])}")
    lines += [f"  {line}" for line in report["commits"][:40]]
    if len(report["commits"]) > 40:
        lines.append(f"  ... {len(report['commits']) - 40} more")
    lines.append(f"files: {len(report['files'])} changed" + (f" ({report['shortstat']})" if report["shortstat"] else ""))
    lines += [f"  {line}" for line in report["files"][:80]]
    if len(report["files"]) > 80:
        lines.append(f"  ... {len(report['files']) - 80} more")
    lines += [f"note: {note}" for note in report["notes"]]
    lines.append("status: " + ("CHANGED" if report["changed"] else "NO_CHANGE"))
    return "\n".join(lines)


# --- shared command pieces ------------------------------------------------------


def planning_commit(args: argparse.Namespace, repo: str) -> Tuple[str, List[str]]:
    if getattr(args, "commit", None):
        commit = args.commit.strip().lower()
        if not COMMIT_RE.match(commit):
            raise ContractError(f"--commit must be a commit id of 7-40 hex characters, not {args.commit!r} (a branch or tag name moves)")
        return commit, []
    root = ensure_checkout_of(repo, args.repo_path)
    sha, _ref, notes = default_branch_tip(root, fetch=not args.no_fetch)
    return sha, notes


def require_approved(args: argparse.Namespace, content: str) -> None:
    approved = (getattr(args, "approved_fingerprint", None) or "").strip().lower()
    if approved and approved != fingerprint(content):
        raise ContractError(
            f"the section text fingerprints to {fingerprint(content)}, not the approved {approved}; "
            "the draft changed after approval, so re-review and re-approve it",
            EXIT_STALE,
        )


def read_file(path: str) -> str:
    if path == "-":
        return sys.stdin.read()
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def emit(args: argparse.Namespace, payload: Dict[str, Any], text: str) -> None:
    if getattr(args, "json", False):
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print(text)


def label_names(issue: Dict[str, Any]) -> List[str]:
    return [label.get("name", "") if isinstance(label, dict) else str(label) for label in issue.get("labels") or []]


def verify_readback(
    repo: str,
    number: int,
    intended: str,
    kind: str,
    attrs: Dict[str, str],
    title: Optional[str] = None,
    labels: Optional[List[str]] = None,
    parent: Optional[int] = None,
) -> Dict[str, Any]:
    issue = fetch_issue(repo, number)
    saved = issue["body"]
    problems: List[str] = []
    if normalize(saved) != normalize(intended):
        problems.append("the saved body differs from the approved body")
    if title is not None and (issue.get("title") or "").strip() != title.strip():
        problems.append(f"title on GitHub is {issue.get('title')!r}, expected {title!r}")
    if labels:
        missing = [label for label in labels if label not in label_names(issue)]
        if missing:
            problems.append("labels missing on GitHub: " + ", ".join(missing))
    if parent is not None:
        saved_parent = issue.get("parent") or {}
        if not isinstance(saved_parent, dict) or saved_parent.get("number") != parent:
            problems.append(f"parent on GitHub is {saved_parent!r}, expected #{parent}")
    try:
        section = parse_sections(saved).get(kind)
    except ContractError as exc:
        section = None
        problems.append(str(exc))
    if section is None:
        problems.append(f"the {kind} contract section is missing after the write")
    else:
        for key, value in attrs.items():
            if section.attrs.get(key) != value:
                problems.append(f"stamp {key}={section.attrs.get(key)!r} on GitHub, expected {value!r}")
        if kind == "product" and section.fingerprint != attrs["fp"]:
            problems.append(f"fingerprint on GitHub is {section.fingerprint}, expected {attrs['fp']}")
    if problems:
        raise ContractError(
            f"read-back of #{number} after the write does not match: " + "; ".join(problems) + f" ({issue.get('url')})",
            EXIT_READBACK,
        )
    return issue


def parent_ref(repo: str, issue: Dict[str, Any]) -> Optional[IssueRef]:
    """GitHub allows a parent in another repository and names that repository only in
    the parent's URL; a parent without a URL is taken to be in the issue's repository."""
    parent = issue.get("parent") or {}
    if not isinstance(parent, dict) or not parent.get("number"):
        return None
    url = parent.get("url")
    if not url:
        return repo, int(parent["number"])
    url_match = ISSUE_URL_REPO_RE.match(url)
    if not url_match:
        # Guessing the child's repository would read an unrelated issue that shares the number.
        raise ContractError(f"cannot tell which repository the parent {url} is in; pass --product-issue owner/repo#N")
    return url_match.group(1), int(parent["number"])


def product_for(
    repo: str, issue: Dict[str, Any], sections: Dict[str, Section], product_issue: Optional[Tuple[Optional[str], int]]
) -> Tuple[Optional[Section], IssueRef, List[str]]:
    """Find the product contract this issue plans against: the one named by the
    delivery stamp or --product-issue, else the issue's own, else its parent's."""
    notes: List[str] = []
    own_ref: IssueRef = (repo, int(issue["number"]))
    if product_issue:
        named: IssueRef = (product_issue[0] or repo, product_issue[1])
        if not same_ref(named, own_ref):
            other = parse_sections(fetch_issue(named[0], named[1])["body"]).get("product")
            if other is None:
                notes.append(f"{ref_label(named, repo)} has no product contract section")
            return other, named, notes
    own = sections.get("product")
    if own is not None:
        return own, own_ref, notes
    parent = parent_ref(repo, issue)
    if parent:
        inherited = parse_sections(fetch_issue(parent[0], parent[1])["body"]).get("product")
        if inherited is not None:
            notes.append(f"product contract read from parent {ref_label(parent, repo)}")
            return inherited, parent, notes
    return None, own_ref, notes


# --- commands -------------------------------------------------------------------


def cmd_fingerprint(args: argparse.Namespace) -> int:
    text = read_file(args.file)
    kind = args.kind or detect_kind(text)
    value = fingerprint(prepare_content(kind, text) if kind else text)
    emit(args, {"fingerprint": value}, value)
    return EXIT_OK


def describe(repo: str, issue: Dict[str, Any], sections: Dict[str, Section]) -> Dict[str, Any]:
    body = issue["body"]
    product = sections.get("product")
    delivery = sections.get("delivery")
    payload: Dict[str, Any] = {
        "repo": repo,
        "number": issue["number"],
        "title": issue.get("title"),
        "state": issue.get("state"),
        "url": issue.get("url"),
        "linear": linear_refs(body),
        "product": None,
        "delivery": None,
    }
    if product:
        payload["product"] = {
            "version": product.attrs.get("v"),
            "stamped_fingerprint": product.attrs.get("fp"),
            "fingerprint": product.fingerprint,
            "scoped_at": product.attrs.get("at"),
            "date": product.attrs.get("date"),
            "identifiers": identifiers(product.content),
            "content": product.content,
        }
    if delivery:
        matrix = matrix_slice(delivery.content)
        payload["delivery"] = {
            "planned_product_issue": delivery.attrs.get("product"),
            "planned_version": delivery.attrs.get("v"),
            "planned_fingerprint": delivery.attrs.get("fp"),
            "planned_at": delivery.attrs.get("at"),
            "date": delivery.attrs.get("date"),
            "paths_watched": watched_paths(delivery.content),
            "matrix_identifiers": identifiers(matrix) if matrix else None,
            "identifiers": identifiers(delivery.content),
            "content": delivery.content,
        }
    return payload


def summarize(payload: Dict[str, Any]) -> str:
    lines = [f"#{payload['number']} {payload.get('title') or ''} [{payload.get('state') or '?'}] {payload.get('url') or ''}".rstrip()]
    product = payload.get("product")
    delivery = payload.get("delivery")
    if product:
        ids = product["identifiers"]
        lines.append(
            f"product contract: v{product['version']} fingerprint {product['fingerprint']}"
            + (f" (stamped {product['stamped_fingerprint']})" if product["stamped_fingerprint"] != product["fingerprint"] else "")
            + f", scoped at {product['scoped_at']}, {product['date']}; "
            + f"SR {len(ids['SR'])}, AC {len(ids['AC'])}, D {len(ids['D'])}"
        )
    else:
        lines.append("product contract: none")
    if delivery:
        where = f" of {delivery['planned_product_issue']}" if delivery.get("planned_product_issue") else ""
        lines.append(
            f"delivery contract: planned against v{delivery['planned_version']} {delivery['planned_fingerprint']}{where}"
            f" at {delivery['planned_at']}, {delivery['date']}; paths watched: "
            + (", ".join(delivery["paths_watched"]) or "none (check compares the whole repository)")
        )
        if delivery.get("matrix_identifiers") is None:
            lines.append("  warning: no 'Requirement-to-proof matrix' heading in the delivery contract")
    else:
        lines.append("delivery contract: none")
    if payload.get("linear"):
        lines.append("linear references: " + ", ".join(payload["linear"]))
    return "\n".join(lines)


def cmd_read(args: argparse.Namespace) -> int:
    repo = resolve_repo(args.repo, args.repo_path)
    issue = fetch_issue(repo, args.issue)
    sections = parse_sections(issue["body"])
    notes: List[str] = []
    product_issue: IssueRef = (repo, int(issue["number"]))
    if "product" not in sections:
        # An epic child carries only a delivery contract; its product contract is the parent's.
        delivery = sections.get("delivery")
        planned = stamp_ref(delivery.attrs["product"], "delivery product-issue") if delivery is not None and delivery.attrs.get("product") else None
        product, product_issue, notes = product_for(repo, issue, sections, planned)
        if product is not None:
            sections = dict(sections)
            sections["product"] = product
    payload = describe(repo, issue, sections)
    payload["product_issue"] = product_issue[1]
    payload["product_repo"] = product_issue[0]
    payload["notes"] = notes
    if args.section:
        section = sections.get(args.section)
        if section is None:
            raise ContractError(f"#{args.issue} has no {args.section} contract section", EXIT_NO_PRODUCT if args.section == "product" else EXIT_NO_DELIVERY)
        if args.json:
            print(json.dumps(payload[args.section], indent=2, sort_keys=True))
        else:
            sys.stdout.write(section.content)
        return EXIT_OK
    text = summarize(payload)
    if not same_ref(product_issue, (repo, int(issue["number"]))):
        text = text.replace("product contract: ", f"product contract (from {ref_label(product_issue, repo)}): ", 1)
    emit(args, payload, text + "".join(f"\nnote: {note}" for note in notes))
    return EXIT_OK


def build_product(args: argparse.Namespace, repo: str, content: str, current: Optional[Section]) -> Tuple[Dict[str, str], List[str]]:
    new_fp = fingerprint(content)
    notes: List[str] = []
    if current is not None:
        if args.expect_fingerprint and args.expect_fingerprint != current.fingerprint:
            raise ContractError(
                f"stale: the product contract on GitHub is {current.fingerprint} (v{current.attrs.get('v')}), "
                f"not {args.expect_fingerprint}; read it again before updating",
                EXIT_STALE,
            )
        version = stamp_int(current.attrs.get("v"), "product version") + 1
    else:
        if args.expect_fingerprint:
            raise ContractError("stale: there is no product contract on GitHub to update", EXIT_STALE)
        version = 1
    commit, commit_notes = planning_commit(args, repo)
    notes += commit_notes
    return {"v": str(version), "fp": new_fp, "at": commit, "date": today()}, notes


def build_delivery(args: argparse.Namespace, repo: str, issue: Dict[str, Any], sections: Dict[str, Section]) -> Tuple[Dict[str, str], List[str]]:
    product, product_ref, notes = product_for(repo, issue, sections, args.product_issue)
    if product is None:
        if args.product_fingerprint:
            raise ContractError("stale: no product contract is reachable, but one was expected", EXIT_STALE)
        if args.product_issue:
            raise ContractError(f"{ref_label(product_ref, repo)} has no product contract section", EXIT_NO_PRODUCT)
        notes.append("no product contract: the delivery contract is stamped fp=none (technical scope or legacy Linear scope)")
        version, fp = "none", "none"
    else:
        if args.product_fingerprint and args.product_fingerprint != product.fingerprint:
            raise ContractError(
                f"stale: the product contract is now {product.fingerprint} (v{product.attrs.get('v')}), "
                f"not {args.product_fingerprint}; re-read it and reconcile the delivery contract first",
                EXIT_STALE,
            )
        version, fp = product.attrs.get("v", "?"), product.fingerprint
    commit, commit_notes = planning_commit(args, repo)
    notes += commit_notes
    attrs: Dict[str, str] = {}
    if not same_ref(product_ref, (repo, int(issue["number"]))):
        attrs["product"] = ref_label(product_ref, repo)
    attrs.update({"v": version, "fp": fp, "at": commit, "date": today()})
    return attrs, notes


def cmd_write(args: argparse.Namespace) -> int:
    repo = resolve_repo(args.repo, args.repo_path)
    content = prepare_content(args.section, read_file(args.file))
    require_approved(args, content)
    issue = fetch_issue(repo, args.issue)
    sections = parse_sections(issue["body"])
    notes: List[str] = []
    if args.section == "product":
        current = sections.get("product")
        if current is not None and args.expect_fingerprint and args.expect_fingerprint != current.fingerprint:
            raise ContractError(
                f"stale: the product contract on GitHub is {current.fingerprint} (v{current.attrs.get('v')}), "
                f"not {args.expect_fingerprint}; read it again before updating",
                EXIT_STALE,
            )
        if current is not None and current.fingerprint == fingerprint(content):
            if current.attrs.get("fp") == current.fingerprint:
                payload = {"status": "ALREADY_CURRENT", "number": issue["number"], "url": issue["url"], "version": current.attrs.get("v"), "fingerprint": current.fingerprint}
                emit(args, payload, f"ALREADY_CURRENT: #{issue['number']} product contract v{current.attrs.get('v')} {current.fingerprint} is unchanged; nothing written")
                return EXIT_OK
            # Same text, wrong stamp: somebody edited the stamp by hand. Re-stamp without a new version.
            commit, notes = planning_commit(args, repo)
            attrs = {"v": str(stamp_int(current.attrs.get("v"), "product version")), "fp": current.fingerprint, "at": commit, "date": today()}
            notes.append(f"the stamp said {current.attrs.get('fp')} for text that fingerprints to {current.fingerprint}; re-stamped at the same version")
        else:
            attrs, notes = build_product(args, repo, content, current)
        delivery = sections.get("delivery")
        if delivery is not None and delivery.attrs.get("fp") not in (None, attrs["fp"]):
            notes.append(
                f"the delivery contract was planned against v{delivery.attrs.get('v')} {delivery.attrs.get('fp')}; "
                "it needs /document reconciliation before anyone builds"
            )
    else:
        attrs, notes = build_delivery(args, repo, issue, sections)
    rendered = render_section(args.section, content, attrs)
    new_body = splice(issue["body"], args.section, rendered, sections)
    payload: Dict[str, Any] = {"number": issue["number"], "url": issue["url"], "section": args.section, "stamp": attrs, "notes": notes}
    if args.dry_run:
        payload["status"] = "DRY_RUN"
        payload["body"] = new_body
        emit(args, payload, f"DRY_RUN: #{issue['number']} would receive this body:\n\n{new_body}\n" + "".join(f"\nnote: {note}" for note in notes))
        return EXIT_OK
    # The fetch above may have been seconds ago (a git fetch sits in between). Refuse to
    # overwrite an edit that landed meanwhile; the body is replaced whole.
    fresh = fetch_issue(repo, args.issue)
    if normalize(fresh["body"]) != normalize(issue["body"]):
        raise ContractError(
            f"stale: the body of #{args.issue} changed while this write was being prepared; read it again and retry",
            EXIT_STALE,
        )
    edit_issue_body(repo, args.issue, new_body)
    verify_readback(repo, args.issue, new_body, args.section, attrs)
    payload["status"] = "WRITTEN"
    label = f"v{attrs['v']} fingerprint {attrs['fp']}" if args.section == "product" else f"planned against v{attrs['v']} {attrs['fp']}"
    emit(
        args,
        payload,
        f"WRITTEN: #{issue['number']} {args.section} contract {label} at {attrs['at']}; read back and verified\n{issue['url']}"
        + "".join(f"\nnote: {note}" for note in notes),
    )
    return EXIT_OK


def cmd_create(args: argparse.Namespace) -> int:
    repo = resolve_repo(args.repo, args.repo_path)
    content = prepare_content(args.section, read_file(args.file))
    require_approved(args, content)
    notes: List[str] = []
    if args.section == "product":
        commit, notes = planning_commit(args, repo)
        attrs = {"v": "1", "fp": fingerprint(content), "at": commit, "date": today()}
    else:
        pseudo_issue = {"number": 0, "parent": {"number": args.parent} if args.parent else None}
        attrs, notes = build_delivery(args, repo, pseudo_issue, {})
    body = render_section(args.section, content, attrs) + "\n"
    payload: Dict[str, Any] = {"section": args.section, "stamp": attrs, "notes": notes, "title": args.title, "repo": repo}
    if args.dry_run:
        payload["status"] = "DRY_RUN"
        payload["body"] = body
        emit(args, payload, f"DRY_RUN: would create in {repo}: {args.title}\n\n{body}" + "".join(f"\nnote: {note}" for note in notes))
        return EXIT_OK
    number, url = create_issue(repo, args.title, body, args.label or [], args.parent)
    try:
        verify_readback(repo, number, body, args.section, attrs, title=args.title, labels=args.label or [], parent=args.parent)
    except ContractError as exc:
        raise ContractError(f"issue #{number} was created ({url}) but its read-back failed; inspect it, do not create again: {exc}", exc.exit_code) from exc
    payload.update({"status": "CREATED", "number": number, "url": url})
    label = f"v{attrs['v']} fingerprint {attrs['fp']}" if args.section == "product" else f"planned against v{attrs['v']} {attrs['fp']}"
    emit(args, payload, f"CREATED: #{number} with the {args.section} contract, {label} at {attrs['at']}; read back and verified\n{url}" + "".join(f"\nnote: {note}" for note in notes))
    return EXIT_OK


def code_drift_lines(args: argparse.Namespace, repo: str, delivery: Section, payload: Dict[str, Any]) -> Tuple[List[str], bool]:
    """Run the code comparison a delivery contract asks for; return the report lines and whether anything changed."""
    planned_at = delivery.attrs.get("at")
    if args.no_code:
        return ["code drift: not checked (--no-code)"], False
    if not planned_at or planned_at == "none":
        return ["code drift: not checked; the delivery contract records no planning commit"], False
    root = ensure_checkout_of(repo, args.repo_path)
    report = code_drift(root, planned_at, None, watched_paths(delivery.content), fetch=not args.no_fetch)
    payload["code_drift"] = report
    return [format_drift(report)], report["changed"]


def cmd_check(args: argparse.Namespace) -> int:
    repo = resolve_repo(args.repo, args.repo_path)
    issue = fetch_issue(repo, args.issue)
    sections = parse_sections(issue["body"])
    delivery = sections.get("delivery")
    planned_product = None
    if delivery is not None and delivery.attrs.get("product"):
        planned_product = stamp_ref(delivery.attrs["product"], "delivery product-issue")
    product, product_ref, notes = product_for(repo, issue, sections, planned_product)
    payload: Dict[str, Any] = {
        "number": issue["number"],
        "url": issue["url"],
        "product_issue": product_ref[1],
        "product_repo": product_ref[0],
        "linear": linear_refs(issue["body"]),
        "notes": notes,
    }
    lines: List[str] = []
    if product is None:
        payload["status"] = "NO_PRODUCT"
        lines.append(f"NO_PRODUCT: no product contract is reachable from #{issue['number']}")
        if delivery is not None:
            lines.append(f"  the delivery contract was planned with fp={delivery.attrs.get('fp')} at {delivery.attrs.get('at')}")
        if payload["linear"]:
            lines.append("  legacy Linear scope referenced: " + ", ".join(payload["linear"]) + " (read it with the linear CLI, read-only)")
        else:
            lines.append("  no Linear reference either: technical scope, or /scope has not written the product contract")
        if delivery is not None:
            # A technical-scope issue still planned against a commit; what moved since then matters just as much.
            drift_lines, changed = code_drift_lines(args, repo, delivery, payload)
            lines += drift_lines
            if changed:
                lines.append("CODE_DRIFT: files under the watched paths changed since the delivery contract was planned; write the drift paragraph before building.")
        emit(args, payload, "\n".join(lines + [f"note: {n}" for n in notes]))
        return EXIT_NO_PRODUCT
    payload["product"] = {"version": product.attrs.get("v"), "fingerprint": product.fingerprint, "scoped_at": product.attrs.get("at")}
    if product.attrs.get("fp") != product.fingerprint:
        notes.append(
            f"the product contract on {ref_label(product_ref, repo)} was edited outside /scope: stamped {product.attrs.get('fp')}, "
            f"content is {product.fingerprint}; /scope should re-stamp it"
        )
    if delivery is None:
        payload["status"] = "NO_DELIVERY"
        lines.append(f"NO_DELIVERY: #{issue['number']} has a product contract (v{product.attrs.get('v')} {product.fingerprint}, scoped at {product.attrs.get('at')}) and no delivery contract; run /document")
        emit(args, payload, "\n".join(lines + [f"note: {n}" for n in notes]))
        return EXIT_NO_DELIVERY
    planned_fp = delivery.attrs.get("fp")
    payload["delivery"] = {"planned_version": delivery.attrs.get("v"), "planned_fingerprint": planned_fp, "planned_at": delivery.attrs.get("at"), "paths_watched": watched_paths(delivery.content)}
    product_ids = identifiers(product.content)
    matrix = matrix_slice(delivery.content)
    matrix_ids = identifiers(matrix) if matrix else identifiers(delivery.content)
    covered = {normalize_id(i) for kind in ("SR", "AC") for i in matrix_ids[kind]}
    missing = [i for kind in ("SR", "AC") for i in product_ids[kind] if normalize_id(i) not in covered]
    payload["not_in_matrix"] = missing
    if planned_fp != product.fingerprint:
        payload["status"] = "CONTRACT_DRIFT"
        lines.append(
            f"CONTRACT_DRIFT: the delivery contract was planned against product contract v{delivery.attrs.get('v')} {planned_fp}; "
            f"the product contract is now v{product.attrs.get('v')} {product.fingerprint}. Stop and run /document reconciliation."
        )
        if missing:
            lines.append("  product identifiers with no row in the requirement-to-proof matrix: " + ", ".join(missing))
        emit(args, payload, "\n".join(lines + [f"note: {n}" for n in notes]))
        return EXIT_STALE
    lines.append(f"contract: IN_SYNC (product contract v{product.attrs.get('v')} {product.fingerprint}; delivery planned against it at {delivery.attrs.get('at')})")
    if missing:
        lines.append("  product identifiers with no row in the requirement-to-proof matrix: " + ", ".join(missing) + " (deferred, or missing proof?)")
    exit_code = EXIT_OK
    status = "IN_SYNC"
    drift_lines, changed = code_drift_lines(args, repo, delivery, payload)
    lines += drift_lines
    if changed:
        status, exit_code = "CODE_DRIFT", EXIT_CODE_DRIFT
        lines.append(
            "CODE_DRIFT: files under the watched paths changed since the delivery contract was planned. "
            "Read them and write the drift paragraph: what changed, and whether any requirement, decision, or the experience artifact is affected."
        )
    payload["status"] = status
    emit(args, payload, "\n".join(lines + [f"note: {n}" for n in notes]))
    return exit_code


def cmd_drift(args: argparse.Namespace) -> int:
    root = repo_root(args.repo_path)
    report = code_drift(root, args.since, args.until, args.paths, fetch=not args.no_fetch)
    emit(args, report, format_drift(report))
    return EXIT_CODE_DRIFT if report["changed"] else EXIT_OK


# --- entry point ----------------------------------------------------------------


def add_common(parser: argparse.ArgumentParser, repo: bool = True, commit: bool = False) -> None:
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    if repo:
        parser.add_argument("-R", "--repo", help="owner/repo; default: the repository of the current checkout")
    parser.add_argument("--repo-path", default=".", help="checkout used for git questions; default: the current directory")
    parser.add_argument("--no-fetch", action="store_true", help="do not fetch origin before resolving the default branch")
    if commit:
        parser.add_argument("--commit", help="default-branch commit to stamp instead of resolving it from --repo-path")


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="contract.py", description="Product and delivery contract sections of a GitHub issue.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_fp = sub.add_parser("fingerprint", help="fingerprint of a section body")
    p_fp.add_argument("file", help="file holding the section text, or - for stdin")
    p_fp.add_argument("--section", dest="kind", choices=SECTION_KINDS, help="strip a pasted section heading first")
    p_fp.add_argument("--json", action="store_true")
    p_fp.set_defaults(func=cmd_fingerprint)

    p_read = sub.add_parser("read", help="show the sections and their stamps")
    p_read.add_argument("issue", type=int)
    p_read.add_argument("--section", choices=SECTION_KINDS, help="print only this section's text")
    add_common(p_read)
    p_read.set_defaults(func=cmd_read)

    p_create = sub.add_parser("create", help="create an issue that holds one section")
    p_create.add_argument("--title", required=True)
    p_create.add_argument("--file", required=True, help="section text, or - for stdin")
    p_create.add_argument("--section", choices=SECTION_KINDS, default="product")
    p_create.add_argument("--label", action="append")
    p_create.add_argument("--parent", type=int, help="create as a sub-issue of this parent")
    p_create.add_argument("--product-issue", type=issue_ref_arg, help="delivery only: the issue holding the product contract (N or owner/repo#N)")
    p_create.add_argument("--product-fingerprint", help="delivery only: refuse unless the product contract still has this fingerprint")
    p_create.add_argument("--approved-fingerprint", help="refuse unless the section text still fingerprints to the approved value")
    p_create.add_argument("--dry-run", action="store_true")
    add_common(p_create, commit=True)
    p_create.set_defaults(func=cmd_create)

    p_write = sub.add_parser("write", help="create or replace one section on an existing issue")
    p_write.add_argument("issue", type=int)
    p_write.add_argument("--section", choices=SECTION_KINDS, required=True)
    p_write.add_argument("--file", required=True, help="section text, or - for stdin")
    p_write.add_argument("--expect-fingerprint", help="product only: refuse unless the current product contract has this fingerprint")
    p_write.add_argument("--product-fingerprint", help="delivery only: refuse unless the product contract still has this fingerprint")
    p_write.add_argument("--product-issue", type=issue_ref_arg, help="delivery only: the issue holding the product contract (epic parent; N or owner/repo#N)")
    p_write.add_argument("--approved-fingerprint", help="refuse unless the section text still fingerprints to the approved value")
    p_write.add_argument("--dry-run", action="store_true")
    add_common(p_write, commit=True)
    p_write.set_defaults(func=cmd_write)

    p_check = sub.add_parser("check", help="contract drift and code drift for an issue")
    p_check.add_argument("issue", type=int)
    p_check.add_argument("--no-code", action="store_true", help="skip the code drift comparison")
    add_common(p_check)
    p_check.set_defaults(func=cmd_check)

    p_drift = sub.add_parser("drift", help="what changed on the default branch under paths since a commit")
    p_drift.add_argument("--since", required=True)
    p_drift.add_argument("--until", help="default: the default branch tip after a fetch")
    p_drift.add_argument("paths", nargs="*")
    add_common(p_drift, repo=False)
    p_drift.set_defaults(func=cmd_drift)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except ContractError as exc:
        print(f"contract: {exc}", file=sys.stderr)
        return exc.exit_code


if __name__ == "__main__":
    sys.exit(main())
