#!/usr/bin/env bash
# Checks a filled Solution Brief. Exit 0: all passed. Exit 1: something to fix.
# Usage: check_brief.sh <path-to-html>
set -u

file="${1:-}"
if [ -z "$file" ] || [ ! -f "$file" ]; then
  echo "Usage: check_brief.sh <path-to-html>" >&2
  exit 2
fi

abs="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
template="$(cd "$(dirname "$0")/.." && pwd)/assets/solution-brief-template.html"

python3 -I - "$abs" "$template" <<'PY'
import html, re, sys

source = open(sys.argv[1], encoding="utf-8").read()
no_comments = re.sub(r"<!--.*?-->", " ", source, flags=re.S)
page = re.sub(r"<(style|script)\b.*?</\1>", " ", no_comments, flags=re.S | re.I)
failed = False

def report(ok, passed, problem):
    global failed
    print(passed if ok else problem)
    failed = failed or not ok

def style(markup):
    found = re.search(r"<style\b.*?</style>", markup, flags=re.S | re.I)
    return " ".join(found.group(0).split()) if found else ""

def text_of(fragment):
    return " ".join(html.unescape(re.sub(r"<[^>]+>", " ", fragment)).split())

template = open(sys.argv[2], encoding="utf-8").read()
report(style(source) == style(template), "Template styling: unchanged",
       "Template styling: changed. Start again from the template and change only the placeholders")

headings = [" ".join(h.split()) for h in re.findall(r"<h2>(.*?)</h2>", page, flags=re.S)]
expected = ["What success means", "The approach", "Options considered", "Risks",
            "Constraints", "Increments", "Verification", "Open questions", "Change log"]
report(headings == expected, "Template sections: all present and in order",
       "Template sections: expected " + ", ".join(expected) + ". Found " + ", ".join(headings or ["none"]))

labels = ["Solution brief", "Problem brief", "Builder", "Volta owner", "Version", "Verb", "Metric",
          "From", "To", "By", "Why it moves the metric", "If the highest risk is real",
          "Security and privacy", "Systems it touches", "Guardrails"]
pieces = [" ".join(p.split()) for p in re.findall(r">([^<>]+)<", page)]
absent = [label for label in labels if label not in pieces]
report(not absent, "Template labels: all present", "Template labels missing: " + ", ".join(absent))

options = [" ".join(o.split()) for o in re.findall(r'<th scope="row">([^<]*)</th>', page)]
missing = [o for o in ["Do nothing", "Use what they already have", "Buy", "Build"] if o not in options]
report(not missing, "Options considered: all four present", "Options considered missing: " + ", ".join(missing))

risk_table = re.search(r"<h2>Risks</h2>.*?<tbody>(.*?)</tbody>", page, flags=re.S)
risk_rows = re.findall(r"<tr>(.*?)</tr>", risk_table.group(1), flags=re.S) if risk_table else []
risk_names = [text_of(re.search(r"<th[^>]*>(.*?)</th>", r, flags=re.S).group(1)) for r in risk_rows if "<th" in r]
report(risk_names == ["Value", "Viability", "Feasibility", "Usability"], "Risks: all four present and in order",
       "Risks: expected Value, Viability, Feasibility, Usability. Found " + ", ".join(risk_names or ["none"]))

left = sorted(set(re.findall(r"\{\{[A-Z0-9_]*\}\}", no_comments)))
report(not left, "Placeholders: all filled", "Unfilled placeholders: " + " ".join(left))
report("<!--" not in source, "Template comments: removed", "Template comments are still in the file")

match = re.search(r"<h2>The approach</h2>\s*<p>(.*?)</p>", page, flags=re.S)
words = len(text_of(match.group(1)).split()) if match else 0
report(match is not None and 0 < words <= 150, f"Approach paragraph: {words} words",
       f"Approach paragraph: {words} words (must be found, and 150 or fewer)")

verification = re.search(r"<h2>Verification</h2>.*?<tbody>(.*?)</tbody>", page, flags=re.S)
rows = re.findall(r"<tr>(.*?)</tr>", verification.group(1), flags=re.S) if verification else []
names = [text_of(re.search(r"<th[^>]*>(.*?)</th>", r, flags=re.S).group(1)) if "<th" in r else "" for r in rows]
solved = [n for n in names if n.lower().startswith("solved")]
done_rows = [n for n in names if re.match(r"done \d+", n, flags=re.I)]
report(len(solved) == 1, "Verification: one Solved row for the target",
       "Verification: needs exactly one row named 'Solved: ...' for the target")
safe_rows = [n for n in names if re.match(r"safe \d+", n, flags=re.I)]
report(len(safe_rows) >= 1, f"Verification: {len(safe_rows)} Safe rows",
       "Verification: needs at least one 'Safe N: ...' row, or one saying the approach touches no new data or access, and why")
report(len(done_rows) >= 1, f"Verification: {len(done_rows)} Done rows",
       "Verification: needs one 'Done N: ...' row per Done means item on the problem brief")
empty = [names[i] or f"row {i+1}" for i, r in enumerate(rows)
         if any(not text_of(c) for c in re.findall(r"<td>(.*?)</td>", r, flags=re.S))
         or len(re.findall(r"<td>", r)) != 3]
report(not empty, "Verification: every row has a criterion, evidence and who confirms when",
       "Verification rows with an empty or missing cell: " + ", ".join(empty))

def fact(label):
    found = re.search(r'<span class="k">' + label + r'</span>\s*<span class="v[^"]*">(.*?)</span>\s*<span class="sub">(.*?)</span>', page, flags=re.S)
    return (text_of(found.group(1)), text_of(found.group(2))) if found else ("", "")

version = fact("Version")[0]
number = re.search(r"(\d+)\.\d+", version)
final = number is not None and int(number.group(1)) >= 1 and "draft" not in version.lower()
if not number:
    report(False, "", f"Version: '{version}' has no version number")
elif final:
    text = text_of(page)
    gaps = len(re.findall(r'class="[^"]*\btbc\b', page)) + len(re.findall(r"\bTBD\b", text))
    report(gaps == 0, f"Version {version}: no gaps", f"Version {version}: {gaps} gaps left. Use a Draft version until every gap is filled")
    problem_version = re.search(r"(\d+)\.\d+", fact("Problem brief")[0])
    report(problem_version is not None and int(problem_version.group(1)) >= 1 and "draft" not in fact("Problem brief")[0].lower(),
           f"Version {version}: problem brief is at 1.0 or later",
           f"Version {version}: the problem brief shown is not at 1.0. Use a Draft version")
    for who, word in [("Builder", "submitted"), ("Volta owner", "approved")]:
        note = fact(who)[1].lower()
        report(word in note and bool(re.search(r"\d", note)),
               f"Version {version}: {who} {word}, with a date",
               f"Version {version}: {who} note must say {word}, with a date")
    ratings = [text_of(c) for r in risk_rows for c in re.findall(r"<td>(.*?)</td>", r, flags=re.S)[1:2]]
    bad = [n for n, rating in zip(risk_names, ratings) if rating.lower() not in ("low", "medium", "high")]
    report(not bad, f"Version {version}: every risk rated Low, Medium or High",
           f"Version {version}: rate these risks Low, Medium or High: " + ", ".join(bad))
else:
    print(f"Version: {version} (draft)")

sys.exit(1 if failed else 0)
PY
