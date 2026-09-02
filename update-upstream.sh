#!/usr/bin/env bash
# Re-syncs the vendored skills from their upstream repos. Run, review `git diff`, commit.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP=$(mktemp -d)
git clone --depth 1 -q https://github.com/chrishuffman5/sqlserver.git "$TMP/ch"
git clone --depth 1 -q https://github.com/erikdarlingdata/claude-plugins.git "$TMP/ed"
git clone --depth 1 -q https://github.com/MicrosoftDocs/Agent-Skills.git "$TMP/ms"
for s in sql-server sqlserver-advisor sqlserver-cloud sqlserver-engineering sqlserver-ha-clustering sqlserver-infrastructure sqlserver-monitoring sqlserver-operations sqlserver-security; do
  rm -rf "$ROOT/skills/$s"; cp -r "$TMP/ch/skills/$s" "$ROOT/skills/$s"
done
rm -rf "$ROOT/skills/sqlserver-query-plans"; cp -r "$TMP/ed/plugins/sqlserver-query-plans/skills/query-plan-analysis" "$ROOT/skills/sqlserver-query-plans"
for s in azure-sql-database azure-sql-managed-instance azure-sql-virtual-machines; do
  rm -rf "$ROOT/skills/$s"; cp -r "$TMP/ms/skills/$s" "$ROOT/skills/$s"
done
{
  echo "chrishuffman5/sqlserver $(git -C "$TMP/ch" rev-parse HEAD)"
  echo "erikdarlingdata/claude-plugins $(git -C "$TMP/ed" rev-parse HEAD)"
  echo "MicrosoftDocs/Agent-Skills $(git -C "$TMP/ms" rev-parse HEAD)"
} > "$ROOT/UPSTREAM_COMMITS.txt"
rm -rf "$TMP"
echo "synced; review with: git status && git diff"
