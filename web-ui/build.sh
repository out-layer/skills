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

# Sort by name; the page orders them by section below.
IFS=$'\n' skills=($(sort <<<"${skills[*]}")); unset IFS

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

# ---------------------------------------------------------------------------
# The page. Three sections: the entry skill and the two platform skills, the
# connectors in one frame, the builder's tools at the bottom. A card shows the
# first clause of the skill's own description — the part before the first
# " — " or ". " — so the page has no copy of its own to drift.
# ---------------------------------------------------------------------------

PLATFORM=(outlayer agent-custody)
LIBRARY=outlayer-connectors
TOOLS=(outlayer-cli building-outlayer-apps)

# The first clause of the description: what the skill IS, in one line.
get_tagline() {
  get_description "$1" | sed -E 's/ — .*$//; s/\. .*$//; s/\.$//'
}

# One stroke glyph per skill, 24px, currentColor. Unknown skills get the file.
icon_for() {
  case "$1" in
    outlayer) echo '<rect x="4" y="8" width="16" height="11" rx="3"/><path d="M12 4v4M9 13h.01M15 13h.01M9 16h6"/>';;
    agent-custody) echo '<rect x="3" y="7" width="18" height="12" rx="2"/><path d="M3 11h18M16 15h2"/>';;
    outlayer-connectors) echo '<path d="M9 3v4M15 3v4M7 7h10v4a5 5 0 01-10 0V7zM12 16v5"/>';;
    gmail-connector) echo '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M3 7l9 6 9-6"/>';;
    github-connector) echo '<circle cx="6" cy="6" r="2"/><circle cx="6" cy="18" r="2"/><circle cx="18" cy="7" r="2"/><path d="M6 8v8M18 9c0 4-3 5-7 5.5-2 .3-4 1-5 2.5"/>';;
    mercury-connector) echo '<path d="M3 9l9-5 9 5H3zM5 9v7M9.5 9v7M14.5 9v7M19 9v7M3 16h18M2 19h20"/>';;
    hyperliquid-connector) echo '<path d="M6 3v3M6 15v6M4 6h4v9H4zM12 5v2M12 13v5M10 7h4v6h-4zM18 3v2M18 12v9M16 5h4v7h-4z"/>';;
    polymarket-connector) echo '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M8.5 8.5h.01M15.5 15.5h.01M15.5 8.5h.01M8.5 15.5h.01M12 12h.01"/>';;
    outlayer-cli) echo '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M7 10l3 2-3 2M12 14h5"/>';;
    building-outlayer-apps) echo '<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9L12 3zM12 12l8-4.5M12 12v9M12 12L4 7.5"/>';;
    *) echo '<path d="M6 3h8l4 4v14H6zM14 3v4h4M9 12h6M9 16h6"/>';;
  esac
}

svg_icon() {
  echo "<svg class=\"icon\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\">$(icon_for "$1")</svg>"
}

card() {
  local skill="$1" tag file_links rel
  tag="$(get_tagline "$skill")"
  file_links="<a href=\"/$skill/SKILL.md\" class=\"file-link\">SKILL.md</a> "
  while IFS= read -r rel; do
    [[ "$rel" == "SKILL.md" ]] && continue
    file_links+="<a href=\"/$skill/$rel\" class=\"file-link\">$rel</a> "
  done < <(cd "$SKILLS_ROOT/$skill" && find . -type f -name '*.md' | sed 's|^\./||' | sort)
  local cls="skill-card"; [[ "$skill" == "$ENTRY" ]] && cls="skill-card entry"
  cat <<CARD
    <div class="$cls">
      <div class="head">$(svg_icon "$skill")<h2><a href="/$skill/SKILL.md">$skill</a></h2></div>
      <p class="desc">${tag:-<em>No description</em>}</p>
      <div class="files">$file_links</div>
    </div>
CARD
}

in_list() { local x="$1"; shift; printf '%s\n' "$@" | grep -qx "$x"; }

platform_cards=""; library_card=""; connector_cards=""; tool_cards=""; other_cards=""
for skill in "${PLATFORM[@]}"; do in_list "$skill" "${skills[@]}" && platform_cards+="$(card "$skill")"; done
in_list "$LIBRARY" "${skills[@]}" && library_card="$(card "$LIBRARY")"
for skill in "${skills[@]}"; do
  [[ "$skill" == *-connector ]] && connector_cards+="$(card "$skill")"
done
for skill in "${TOOLS[@]}"; do in_list "$skill" "${skills[@]}" && tool_cards+="$(card "$skill")"; done
for skill in "${skills[@]}"; do
  in_list "$skill" "${PLATFORM[@]}" "${TOOLS[@]}" "$LIBRARY" && continue
  [[ "$skill" == *-connector ]] && continue
  other_cards+="$(card "$skill")"
done

SITE="https://skills.outlayer.ai"
DESCRIPTION="What an AI agent reads to use OutLayer: a TEE-held multi-chain wallet, connectors to Gmail, GitHub, Mercury Bank, Hyperliquid and Polymarket, and the CLI. One entry skill routes to the rest."

cp "$SCRIPT_DIR/assets/favicon.svg" "$WEB_ROOT/favicon.svg"
cp "$SCRIPT_DIR/assets/og.png" "$WEB_ROOT/og.png"

# Generate index.html
cat > "$WEB_ROOT/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OutLayer Skills</title>
  <meta name="description" content="$DESCRIPTION">
  <link rel="canonical" href="$SITE/">
  <link rel="icon" type="image/svg+xml" href="/favicon.svg">
  <meta name="theme-color" content="#cc6600">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="OutLayer Skills">
  <meta property="og:title" content="OutLayer Skills">
  <meta property="og:description" content="$DESCRIPTION">
  <meta property="og:url" content="$SITE/">
  <meta property="og:image" content="$SITE/og.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="OutLayer Skills — what an AI agent reads to use OutLayer">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="OutLayer Skills">
  <meta name="twitter:description" content="$DESCRIPTION">
  <meta name="twitter:image" content="$SITE/og.png">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #0d1117;
      color: #c9d1d9;
      padding: 2rem 1rem 3rem;
      max-width: 900px;
      margin: 0 auto;
    }
    h1 { font-size: 1.8rem; color: #f0f6fc; margin-bottom: 0.3rem; display: flex; align-items: center; gap: 0.6rem; }
    h1 img { width: 32px; height: 32px; border-radius: 7px; }
    .subtitle { color: #8b949e; margin-bottom: 2rem; font-size: 0.95rem; }
    .subtitle code { color: #c9d1d9; }
    .section { margin-bottom: 1.5rem; }
    .section > h3 { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.06em; color: #8b949e; margin: 0 0 0.6rem 0.2rem; }
    .frame { border: 1px solid #30363d; border-radius: 12px; padding: 1rem; background: #0f141b; }
    .frame > h3 { font-size: 0.95rem; color: #f0f6fc; margin-bottom: 0.2rem; }
    .frame > .frame-desc { color: #8b949e; font-size: 0.85rem; margin-bottom: 0.9rem; }
    .frame .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 0.75rem; }
    .frame .skill-card { margin: 0; }
    .frame > .skill-card { margin-bottom: 0.75rem; border-color: #3d444d; }
    .skill-card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 1rem 1.2rem; margin-bottom: 0.75rem; }
    .skill-card.entry { border-color: #cc6600; }
    .head { display: flex; align-items: center; gap: 0.6rem; margin-bottom: 0.35rem; }
    .icon { width: 22px; height: 22px; color: #e0842a; flex: none; }
    .skill-card h2 { font-size: 1.05rem; }
    .skill-card h2 a { color: #58a6ff; text-decoration: none; }
    .skill-card h2 a:hover { text-decoration: underline; }
    .desc { color: #8b949e; font-size: 0.88rem; margin-bottom: 0.6rem; line-height: 1.4; }
    .files { display: flex; flex-wrap: wrap; gap: 0.4rem; }
    .file-link { font-size: 0.78rem; color: #c9d1d9; background: #21262d; padding: 0.15rem 0.5rem; border-radius: 4px; text-decoration: none; border: 1px solid #30363d; }
    .file-link:hover { border-color: #58a6ff; color: #58a6ff; }
    footer { margin-top: 2.5rem; padding-top: 1rem; border-top: 1px solid #21262d; color: #8b949e; font-size: 0.85rem; display: flex; flex-wrap: wrap; gap: 0.4rem 1.2rem; align-items: center; }
    footer a { color: #c9d1d9; text-decoration: none; }
    footer a:hover { color: #58a6ff; }
    footer .meta { color: #484f58; margin-left: auto; font-size: 0.78rem; }
  </style>
</head>
<body>
  <h1><img src="/favicon.svg" alt="">OutLayer Skills</h1>
  <p class="subtitle">${#skills[@]} skills &mdash; point an agent at <code>$SITE/$ENTRY/SKILL.md</code> and it finds the rest</p>

  <div class="section">
${platform_cards}
  </div>

  <div class="section frame">
    <h3>Connectors</h3>
    <p class="frame-desc">Outside services an agent acts on as its owner — under a policy the owner sets, from inside the enclave that holds its wallet. Read the library skill first: the call, the payment key, the trial, the refusal codes. Each connector's skill adds its operations and policy.</p>
${library_card}
    <div class="grid">
${connector_cards}
    </div>
  </div>
${other_cards:+
  <div class="section">
${other_cards}
  </div>}
  <div class="section">
    <h3>For builders</h3>
${tool_cards}
  </div>

  <footer>
    <a href="https://outlayer.ai">outlayer.ai</a>
    <a href="https://app.outlayer.ai">app.outlayer.ai</a>
    <a href="https://app.outlayer.ai/docs">Docs</a>
    <a href="https://github.com/out-layer/skills">Source</a>
    <span class="meta">Built $(date -u '+%Y-%m-%d %H:%M UTC')</span>
  </footer>
</body>
</html>
HTMLEOF

echo "Built ${#skills[@]} skills into $WEB_ROOT"
