# sqlserver-skills

Alexey's SQL Server performance-tuning skill collection for AI agents (Claude Code, Claude Cowork, GitHub Copilot CLI, Codex CLI, SSMS 22 Copilot Agent mode). Fifteen skills in the open `SKILL.md` format, packaged as a Claude Code plugin marketplace.

| Skill | Upstream | Covers |
|---|---|---|
| `sql-server` | chrishuffman5/sqlserver | Router, version/edition/platform matrices |
| `sqlserver-monitoring` | chrishuffman5/sqlserver | Waits, DMVs, Query Store, XEvents, blocking, deadlocks — 11 scripts |
| `sqlserver-engineering` | chrishuffman5/sqlserver | Indexing, plans, CE/stats, parameter sniffing, partitioning, columnstore — 8 scripts |
| `sqlserver-query-plans` | erikdarlingdata/claude-plugins | `.sqlplan` analysis with correct self-time attribution; `scripts/extract.py` |
| `sqlserver-advisor` | chrishuffman5/sqlserver | Offline capture → DuckDB → prioritized findings |
| `sqlserver-infrastructure` | chrishuffman5/sqlserver | Memory, MAXDOP, tempdb, trace flags, storage, Linux/containers |
| `sqlserver-operations` | chrishuffman5/sqlserver | Backup/restore, CHECKDB, maintenance, Agent, patching |
| `sqlserver-ha-clustering` | chrishuffman5/sqlserver | AGs, FCI, mirroring, log shipping, replication, DR |
| `sqlserver-cloud` | chrishuffman5/sqlserver | Azure SQL DB/MI, SQL on Azure VM, AWS RDS, Cloud SQL, migration |
| `sqlserver-security` | chrishuffman5/sqlserver | Auth, permissions, TDE/AE/TLS, RLS, DDM, audit, hardening |
| `azure-sql-database` | MicrosoftDocs/Agent-Skills | Tiers, scaling, performance troubleshooting (official) |
| `azure-sql-managed-instance` | MicrosoftDocs/Agent-Skills | MI operations and tuning (official) |
| `azure-sql-virtual-machines` | MicrosoftDocs/Agent-Skills | SQL on Azure VM (official) |
| `darling-tools` | this repo (wraps erikdarlingdata/DarlingData) | Run and interpret sp_PressureDetector, sp_PerfCheck, sp_QuickieStore, sp_QuickieCache, sp_HumanEvents, sp_HealthParser, sp_LogHunter, sp_IndexCleanup, sp_QueryReproBuilder — parameter catalog, interpretation thresholds, 9 scripts |
| `itzik-tsql-patterns` | this repo (original, Itzik Ben-Gan style) | Window functions, gaps/islands, top-N per group, paging, interval packing, set-based rewrites, POC indexing, batch mode — 7 references, numbers/calendar tables, runnable cookbook |

## Install

Claude Code (plugin, auto-routes):

```
/plugin marketplace add alexhdsale/sqlserver-skills
/plugin install sqlserver-skills@alexhdsale
```

Everything else (copies `skills/*` into `~/.claude/skills`, `~/.agents/skills`, `~/.copilot/skills` — picked up by Claude Code, Codex, Copilot CLI and SSMS 22 Copilot):

```powershell
git clone https://github.com/alexhdsale/sqlserver-skills.git
cd sqlserver-skills
.\install.ps1          # Windows
./install.sh           # Linux / macOS
```

claude.ai / Cowork account skills: zip any folder under `skills/` and upload it under Settings → Capabilities → Skills.

## Use

Just describe the task; the agent matches the skill by description. Examples:

- "PAGEIOLATCH_SH is 40% of waits on PRODSQL01, PLE 300. Here's dm_os_wait_stats." → `sqlserver-monitoring`
- "Attached `usp_GetOrders.sqlplan`. What's actually slow?" → `sqlserver-query-plans`
- "Design a covering index for this predicate, estimate write overhead, include rollback." → `sqlserver-engineering`
- "Run the capture bundle, here are the CSVs, give me a prioritized health report." → `sqlserver-advisor`
- "GP 8 vCore vs Hyperscale for this workload?" → `azure-sql-database` / `sqlserver-cloud`
- "Run sp_PressureDetector, here is the output. Memory or CPU?" → `darling-tools`
- "Rewrite this running-balance cursor as a window function." → `itzik-tsql-patterns`

Give the agent server access with `sqlcmd`, Microsoft's MSSQL MCP, or Erik Darling's Performance Studio / Performance Monitor MCP servers. Diagnostic scripts are read-only but review headers before running on production; they require `VIEW SERVER STATE`.

`docs/GUIDE.md` has the full usage guide and the ranked list of guru tuning assets.

## Keeping upstream in sync

```
./update-upstream.sh && git diff --stat && git commit -am "sync upstream"
```

`darling-tools` and `itzik-tsql-patterns` are authored here, not vendored. The script records the DarlingData commit the procedure catalog was written against in `UPSTREAM_COMMITS.txt`; when it moves, re-check `skills/darling-tools/references/procedure-catalog.md` against the upstream README parameter tables.

`UPSTREAM_COMMITS.txt` records the exact upstream commits vendored.

## Licenses

Vendored skills keep their upstream licenses: chrishuffman5/sqlserver (MIT), erikdarlingdata/claude-plugins (MIT), MicrosoftDocs/Agent-Skills (CC BY 4.0 / MIT for code). See `THIRD_PARTY/`. Repo glue (README, CLAUDE.md, installers) is MIT.
