#!/usr/bin/env bash
# Skill hygiene. Run before every commit:  scripts/check.sh
# Fails on: SKILL.md over 500 lines, missing frontmatter, a description over
# 1024 chars, a broken relative link, an orphan reference file, a skill missing
# from the entry skill, a build.sh failure. Warns on SKILL.md over 3000 words.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTRY="outlayer"
MAX_LINES=500
MAX_WORDS=3000
MAX_DESC=1024
fail=0
say() { echo "FAIL  $*"; fail=1; }
warn() { echo "WARN  $*"; }

for skill_md in "$ROOT"/*/SKILL.md; do
  dir="$(dirname "$skill_md")"
  name="$(basename "$dir")"

  # frontmatter
  [[ "$(head -1 "$skill_md")" == "---" ]] || say "$name: SKILL.md does not start with frontmatter"
  grep -q '^name: ' "$skill_md" || say "$name: frontmatter has no name"
  grep -q '^description: ' "$skill_md" || say "$name: frontmatter has no description"
  desc_len="$(awk '/^description:/{print length($0)-13; exit}' "$skill_md")"
  [[ "${desc_len:-0}" -le $MAX_DESC ]] || say "$name: description is $desc_len chars (max $MAX_DESC)"

  # size
  lines="$(wc -l < "$skill_md" | tr -d " ")"; words="$(wc -w < "$skill_md" | tr -d " ")"
  [[ "$lines" -le $MAX_LINES ]] || say "$name: SKILL.md is $lines lines (max $MAX_LINES) — move a section to references/"
  [[ "$words" -le $MAX_WORDS ]] || warn "$name: SKILL.md is $words words (guideline $MAX_WORDS) — consider moving a section to references/"

  # relative links resolve (markdown links and `references/x.md` mentions; http links skipped)
  while IFS= read -r f; do
    fd="$(dirname "$f")"
    while IFS= read -r link; do
      [[ -z "$link" ]] && continue
      target="${link%%#*}"
      [[ -e "$fd/$target" || -e "$dir/$target" ]] || say "$name: ${f#$dir/} links to missing $link"
    done < <(grep -oE '\]\([^)#:]+\.md[^)]*\)|`(references|rules)/[A-Za-z0-9_./-]+\.md`' "$f" 2>/dev/null | sed 's/^](//;s/)$//;s/`//g')
  done < <(find "$dir" -type f -name '*.md')

  # orphan references: every references/*.md is named somewhere in the skill
  for ref in "$dir"/references/*.md; do
    [[ -f "$ref" ]] || continue
    rn="$(basename "$ref")"
    if ! grep -rq --include='*.md' --exclude="$rn" -- "$rn" "$dir"; then
      say "$name: references/$rn is not linked from anywhere in the skill"
    fi
  done
done

# the entry skill routes to every other skill
for skill_md in "$ROOT"/*/SKILL.md; do
  name="$(basename "$(dirname "$skill_md")")"
  [[ "$name" == "$ENTRY" ]] && continue
  grep -q "skills.outlayer.ai/$name/SKILL.md" "$ROOT/$ENTRY/SKILL.md" \
    || say "$ENTRY/SKILL.md has no row for $name"
done

# nothing generated is tracked
if git -C "$ROOT" ls-files --error-unmatch web-ui/public >/dev/null 2>&1; then
  say "web-ui/public is tracked in git — it is a build artifact"
fi

# the site builds
if bash "$ROOT/web-ui/build.sh" >/dev/null 2>&1; then
  rm -rf "$ROOT/web-ui/public"
else
  say "web-ui/build.sh failed"
fi

if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
