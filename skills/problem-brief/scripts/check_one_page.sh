#!/usr/bin/env bash
# Checks a filled Problem Brief. Exit 0: all passed. Exit 1: something to fix.
# Exit 3: nothing to fix so far, but the printed page count couldn't be checked.
# Usage: check_one_page.sh <path-to-html>
set -u

file="${1:-}"
if [ -z "$file" ] || [ ! -f "$file" ]; then
  echo "Usage: check_one_page.sh <path-to-html>" >&2
  exit 2
fi

abs="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
template="$(cd "$(dirname "$0")/.." && pwd)/assets/problem-brief-template.html"

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

template = open(sys.argv[2], encoding="utf-8").read()
report(style(source) == style(template), "Template styling: unchanged",
       "Template styling: changed. Start again from the template and change only the placeholders")

headings = [" ".join(h.split()) for h in re.findall(r"<h2>(.*?)</h2>", page, flags=re.S)]
sections = [h for h in headings if h != "The first quarter"]
expected = ["The problem", "Solution hypothesis", "Target result", "Done means", "Change log"]
report(sections == expected, "Template sections: all present and in order",
       "Template sections: expected " + ", ".join(expected) + ". Found " + ", ".join(headings or ["none"]))

labels = ["Problem brief", "Prepared for", "Problem Lead", "Technical Lead", "Version", "What it costs",
          "How often", "Root cause", "Verb", "Metric", "From", "To", "By"]
pieces = [" ".join(p.split()) for p in re.findall(r">([^<>]+)<", page)]
absent = [label for label in labels if label not in pieces]
report(not absent, "Template labels: all present", "Template labels missing: " + ", ".join(absent))

left = sorted(set(re.findall(r"\{\{[A-Z0-9_]*\}\}", no_comments)))
report(not left, "Placeholders: all filled", "Unfilled placeholders: " + " ".join(left))

report("<!--" not in source, "Template comments: removed", "Template comments are still in the file")

match = re.search(r"<h2>The problem</h2>\s*<p>(.*?)</p>", page, flags=re.S)
words = len(html.unescape(re.sub(r"<[^>]+>", " ", match.group(1))).split()) if match else 0
report(match is not None and words <= 150, f"Problem paragraph: {words} words",
       f"Problem paragraph: {words} words (must be found, and 150 or fewer)")

text = html.unescape(re.sub(r"<[^>]+>", " ", page))
terms = r"economic buyer|functional buyer|technical buyer|\bSME\b|greenlight|\bbet\b|champion|resistor"
found = sorted({m.group(0).lower() for m in re.finditer(terms, text, flags=re.I)})
report(not found, "Internal vocabulary: none found", "Internal vocabulary on the page: " + ", ".join(found))

done = re.search(r'<ol class="done">(.*?)</ol>', page, flags=re.S)
items = re.findall(r"<li>(.*?)</li>", done.group(1), flags=re.S) if done else []
unwrapped = [i for i in items if not re.fullmatch(r"\s*<span>.*</span>\s*", i, flags=re.S)]
report(items and not unwrapped, "Done means layout: every item wrapped",
       f"Done means layout: {len(unwrapped)} of {len(items)} items need their text inside a span")

version_match = re.search(r'<span class="k">Version</span>\s*<span class="v[^"]*">(.*?)</span>', page, flags=re.S)
version = " ".join(html.unescape(re.sub(r"<[^>]+>", " ", version_match.group(1))).split()) if version_match else ""
number = re.search(r"(\d+)\.\d+", version)
final = number is not None and int(number.group(1)) >= 1 and "draft" not in version.lower()
gaps = len(re.findall(r'class="[^"]*\btbc\b', page)) + len(re.findall(r"\bTBD\b", text))
cost = re.search(r"<b>What it costs</b>\s*<span>(.*?)</span>\s*</div>", page, flags=re.S)
cost_text = html.unescape(re.sub(r"<[^>]+>", " ", cost.group(1))) if cost else ""
quantified = re.search(r"\d", cost_text) is not None
if not number:
    report(False, "", f"Version: '{version}' has no version number")
elif final:
    report(gaps == 0 and quantified, f"1.0 check: {version} has no gaps and a quantified cost (verification is not checked)",
           f"1.0 check: {version} has {gaps} gap(s)"
           + ("" if quantified else " and no number in What it costs")
           + ". Keep it a draft until they are filled and verified")
else:
    report(True, f"Version: {version} ({gaps} gap(s) to fill before 1.0)", "")

sys.exit(1 if failed else 0)
PY
status=$?

chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$chrome" ]; then
  echo "Printed pages: NOT CHECKED, Google Chrome isn't installed at the usual path"
  [ "$status" -eq 0 ] && status=3
  exit "$status"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
"$chrome" --headless=new --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$tmp/brief.pdf" "file://$abs" >/dev/null 2>&1

if [ ! -s "$tmp/brief.pdf" ]; then
  echo "Printed pages: NOT CHECKED, Chrome didn't produce a PDF"
  [ "$status" -eq 0 ] && status=3
  exit "$status"
fi

pages="$(python3 -I -c '
import re, sys
print(len(re.findall(rb"/Type\s*/Page[^s]", open(sys.argv[1], "rb").read())))
' "$tmp/brief.pdf")"

if [ "$pages" = "1" ]; then
  echo "Printed pages: 1"
else
  echo "Printed pages: $pages (must be 1)"
  status=1
fi
exit "$status"
