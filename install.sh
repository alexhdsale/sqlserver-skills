#!/usr/bin/env bash
# Installs every skill in this repo for Claude Code, Codex CLI and GitHub Copilot CLI (Linux/macOS).
# Usage: git clone https://github.com/alexhdsale/sqlserver-skills.git && cd sqlserver-skills && ./install.sh
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)/skills"
for t in "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.copilot/skills"; do
  mkdir -p "$t"
  for s in "$SRC"/*/; do
    n=$(basename "$s"); rm -rf "$t/$n"; cp -r "$s" "$t/$n"; echo "installed $n -> $t/$n"
  done
done
echo; echo "Done. Restart Claude Code / Copilot. Or: /plugin marketplace add alexhdsale/sqlserver-skills && /plugin install sqlserver-skills@alexhdsale"
