#!/usr/bin/env bash
# Regenerates the Articles section of README.md from files in articles/.
# Idempotent. Sorts by date desc; within a date, by git first-commit time asc
# (falls back to file mtime for uncommitted files).
# Run after adding or removing articles.

set -euo pipefail

cd "$(dirname "$0")/.."

ARTICLES_DIR="articles"
README="README.md"
START_MARKER="<!-- ARTICLES:START -->"
END_MARKER="<!-- ARTICLES:END -->"

[[ -d "$ARTICLES_DIR" ]] || { echo "Error: $ARTICLES_DIR not found" >&2; exit 1; }
[[ -f "$README" ]] || { echo "Error: $README not found" >&2; exit 1; }
grep -q "$START_MARKER" "$README" || { echo "Error: $START_MARKER not in $README" >&2; exit 1; }
grep -q "$END_MARKER" "$README" || { echo "Error: $END_MARKER not in $README" >&2; exit 1; }

to_pretty_date() {
  date -j -f "%Y-%m-%d" "$1" "+%B %-d, %Y" 2>/dev/null \
    || date -d "$1" "+%B %-d, %Y" 2>/dev/null \
    || echo "$1"
}

metadata=$(
  for f in "$ARTICLES_DIR"/*.md; do
    filename=$(basename "$f")
    date_iso=${filename:0:10}
    title=$(grep -m1 '^# ' "$f" | sed 's/^# //')
    guest=$(grep -m1 '^\*A guest post from ' "$f" \
      | sed -E 's/^\*A guest post from ([^,]+),.*/\1/' || echo "")
    sort_key=$(git log --diff-filter=A --format=%at -- "$f" 2>/dev/null | tail -1)
    [[ -z "$sort_key" ]] && sort_key=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo "0")
    printf '%s\t%s\t%s\t%s\t%s\n' "$date_iso" "$sort_key" "$filename" "$title" "$guest"
  done | sort -k1,1r -k2,2n
)

current_date=""
section="## Articles"$'\n'
while IFS=$'\t' read -r date_iso sort_key filename title guest; do
  if [[ "$date_iso" != "$current_date" ]]; then
    pretty=$(to_pretty_date "$date_iso")
    section+=$'\n'"### $pretty"$'\n\n'
    current_date="$date_iso"
  fi
  link="[$title]($ARTICLES_DIR/$filename)"
  if [[ -n "$guest" ]]; then
    section+="- $link · *guest: $guest*"$'\n'
  else
    section+="- $link"$'\n'
  fi
done <<< "$metadata"

section_file=$(mktemp)
printf '%s' "$section" > "$section_file"

awk -v start="$START_MARKER" -v end="$END_MARKER" -v sfile="$section_file" '
  $0 == start {
    print; print ""
    while ((getline line < sfile) > 0) print line
    close(sfile)
    skip = 1
    next
  }
  $0 == end { skip = 0 }
  !skip { print }
' "$README" > "$README.tmp"

rm -f "$section_file"
mv "$README.tmp" "$README"

article_count=$(grep -c '^- \[' "$README" || true)
echo "Updated $README — $article_count articles listed."
