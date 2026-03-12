#!/usr/bin/env bash
set -euo pipefail

# Build script for skills.outlayer.ai
# Scans outlayer-skills/ for skill directories, generates index.html,
# and symlinks all skill files into the web root.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_ROOT="$(dirname "$SCRIPT_DIR")"
WEB_ROOT="$SCRIPT_DIR/public"

# Clean previous build
rm -rf "$WEB_ROOT"
mkdir -p "$WEB_ROOT"

# Collect skills (all dirs except web-ui)
skills=()
for dir in "$SKILLS_ROOT"/*/; do
  name="$(basename "$dir")"
  [[ "$name" == "web-ui" ]] && continue
  [[ -d "$dir" ]] || continue
  skills+=("$name")
done

# Sort skills
IFS=$'\n' skills=($(sort <<<"${skills[*]}")); unset IFS

# Symlink each skill directory into public/
for skill in "${skills[@]}"; do
  ln -s "$SKILLS_ROOT/$skill" "$WEB_ROOT/$skill"
done

# Extract description from SKILL.md frontmatter
get_description() {
  local skill_md="$SKILLS_ROOT/$1/SKILL.md"
  [[ -f "$skill_md" ]] || return
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
  # List files in skill directory
  file_links=""
  for f in "$SKILLS_ROOT/$skill"/*; do
    [[ -f "$f" ]] || continue
    fname="$(basename "$f")"
    file_links+="<a href=\"/$skill/$fname\" class=\"file-link\">$fname</a> "
  done
  skill_cards+="
    <div class=\"skill-card\">
      <h2><a href=\"/$skill/\">$skill</a></h2>
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
    .skill-card {
      background: #161b22;
      border: 1px solid #30363d;
      border-radius: 8px;
      padding: 1.2rem 1.5rem;
      margin-bottom: 1rem;
    }
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
  <p class="subtitle">${#skills[@]} skills available &mdash; <code>skills.outlayer.ai</code></p>
  ${skill_cards}
  <p class="meta">Built $(date -u '+%Y-%m-%d %H:%M UTC')</p>
</body>
</html>
HTMLEOF

echo "Built ${#skills[@]} skills into $WEB_ROOT"
