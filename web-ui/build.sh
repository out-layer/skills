#!/usr/bin/env bash
set -euo pipefail

# Build script for skills.outlayer.ai
# Scans outlayer-skills/ for skill directories, symlinks each into the web
# root, and generates index.html: one card per skill, every .md file in the
# skill linked directly (SKILL.md first, then references/… and rules/…).
# The `outlayer` skill is the entry point and is listed first.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_ROOT="$(dirname "$SCRIPT_DIR")"
WEB_ROOT="$SCRIPT_DIR/public"
ENTRY="outlayer"

# Clean previous build
rm -rf "$WEB_ROOT"
mkdir -p "$WEB_ROOT"

# Collect skills: every directory with a SKILL.md, except web-ui
skills=()
for dir in "$SKILLS_ROOT"/*/; do
  name="$(basename "$dir")"
  [[ "$name" == "web-ui" ]] && continue
  [[ -f "$dir/SKILL.md" ]] || continue
  skills+=("$name")
done

# Sort, then move the entry skill to the front
IFS=$'\n' skills=($(sort <<<"${skills[*]}")); unset IFS
if printf '%s\n' "${skills[@]}" | grep -qx "$ENTRY"; then
  skills=("$ENTRY" $(printf '%s\n' "${skills[@]}" | grep -vx "$ENTRY"))
fi

# Symlink each skill directory into public/
for skill in "${skills[@]}"; do
  ln -s "$SKILLS_ROOT/$skill" "$WEB_ROOT/$skill"
done

# Extract description from SKILL.md frontmatter
get_description() {
  local skill_md="$SKILLS_ROOT/$1/SKILL.md"
  awk '
    BEGIN { in_front=0 }
    /^---$/ { in_front++; next }
    in_front==1 && /^description:/ {
      sub(/^description:[[:space:]]*/, "")
      print
      exit
    }
  ' "$skill_md"
}

# Build skill cards HTML
skill_cards=""
for skill in "${skills[@]}"; do
  desc="$(get_description "$skill")"
  # Every .md file in the skill, SKILL.md first, then the rest by path
  file_links="<a href=\"/$skill/SKILL.md\" class=\"file-link\">SKILL.md</a> "
  while IFS= read -r rel; do
    [[ "$rel" == "SKILL.md" ]] && continue
    file_links+="<a href=\"/$skill/$rel\" class=\"file-link\">$rel</a> "
  done < <(cd "$SKILLS_ROOT/$skill" && find . -type f -name '*.md' | sed 's|^\./||' | sort)
  card_class="skill-card"
  [[ "$skill" == "$ENTRY" ]] && card_class="skill-card entry"
  skill_cards+="
    <div class=\"$card_class\">
      <h2><a href=\"/$skill/SKILL.md\">$skill</a></h2>
      <p class=\"desc\">${desc:-<em>No description</em>}</p>
      <div class=\"files\">$file_links</div>
    </div>"
done

# Generate index.html
cat > "$WEB_ROOT/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OutLayer Skills</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #0d1117;
      color: #c9d1d9;
      padding: 2rem;
      max-width: 900px;
      margin: 0 auto;
    }
    h1 {
      font-size: 1.8rem;
      color: #f0f6fc;
      margin-bottom: 0.3rem;
    }
    .subtitle {
      color: #8b949e;
      margin-bottom: 2rem;
      font-size: 0.95rem;
    }
    .subtitle code { color: #c9d1d9; }
    .skill-card {
      background: #161b22;
      border: 1px solid #30363d;
      border-radius: 8px;
      padding: 1.2rem 1.5rem;
      margin-bottom: 1rem;
    }
    .skill-card.entry { border-color: #58a6ff; }
    .skill-card h2 {
      font-size: 1.15rem;
      margin-bottom: 0.4rem;
    }
    .skill-card h2 a {
      color: #58a6ff;
      text-decoration: none;
    }
    .skill-card h2 a:hover { text-decoration: underline; }
    .desc {
      color: #8b949e;
      font-size: 0.9rem;
      margin-bottom: 0.6rem;
      line-height: 1.4;
    }
    .files { display: flex; flex-wrap: wrap; gap: 0.5rem; }
    .file-link {
      font-size: 0.8rem;
      color: #c9d1d9;
      background: #21262d;
      padding: 0.2rem 0.6rem;
      border-radius: 4px;
      text-decoration: none;
      border: 1px solid #30363d;
    }
    .file-link:hover { border-color: #58a6ff; color: #58a6ff; }
    .meta {
      margin-top: 2rem;
      color: #484f58;
      font-size: 0.8rem;
    }
  </style>
</head>
<body>
  <h1>OutLayer Skills</h1>
  <p class="subtitle">${#skills[@]} skills &mdash; point an agent at <code>https://skills.outlayer.ai/$ENTRY/SKILL.md</code> and it finds the rest</p>
  ${skill_cards}
  <p class="meta">Built $(date -u '+%Y-%m-%d %H:%M UTC')</p>
</body>
</html>
HTMLEOF

echo "Built ${#skills[@]} skills into $WEB_ROOT"
