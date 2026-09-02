# SQL Server Performance Skills — Install & Usage Guide

Prepared for Alexey · 2026-09-02

## 1. What is installed right now

Two skill sets are installed in this Cowork session and are already active (I can invoke them by name or they trigger automatically from your wording):

| Skill | Source | What it does |
|---|---|---|
| `sql-server` | chrishuffman5/sqlserver | Router. Classifies your request, checks version/platform, dispatches to the right domain skill |
| `sqlserver-monitoring` | chrishuffman5/sqlserver | Waits methodology, DMVs, Query Store, XEvents, blocking/deadlocks. 11 read-only scripts |
| `sqlserver-engineering` | chrishuffman5/sqlserver | Indexing, plans, CE/stats, parameter sniffing, partitioning, columnstore. 8 scripts |
| `sqlserver-infrastructure` | chrishuffman5/sqlserver | max memory, MAXDOP/CTFP, tempdb, trace flags, NUMA, storage |
| `sqlserver-operations` | chrishuffman5/sqlserver | Backups, CHECKDB, Ola, Agent, patching, space |
| `sqlserver-ha-clustering` | chrishuffman5/sqlserver | AGs, FCI, mirroring endpoints, log shipping, replication |
| `sqlserver-cloud` | chrishuffman5/sqlserver | Azure SQL DB/MI, SQL on Azure VM, AWS RDS, Cloud SQL, migration tooling |
| `sqlserver-security` | chrishuffman5/sqlserver | Auth, permissions, TDE/AE/TLS, RLS, DDM, audit, hardening |
| `sqlserver-advisor` | chrishuffman5/sqlserver | Offline: capture DMVs once to CSV → DuckDB → prioritized findings report |
| `sqlserver-query-plans` | erikdarlingdata/claude-plugins | Reads a `.sqlplan`, computes true self-time per operator, per-execution row estimates, explains what is actually slow. Ships `extract.py` |

Plus your pre-existing `sqlserver-dba` account skill (FRK / sp_WhoIsActive / Ola oriented). The three sets overlap on purpose: `sqlserver-dba` is your house style, `chrishuffman5` brings the script library and cloud/HA breadth, and Erik's plugin is the deepest single-purpose plan reader available anywhere.

## 2. How skills actually work (the mechanics)

A skill is a folder containing `SKILL.md` (YAML front-matter with `name` + `description`, then instructions) and optional `references/` and `scripts/`. Nothing runs on its own. The agent (me, Claude Code, Copilot CLI, SSMS Copilot) keeps only the `description` of every installed skill in context. When your request matches the trigger words in a description, the agent opens the full `SKILL.md`, follows its workflow, and pulls in `references/*.md` and `scripts/*.sql` on demand. So a skill costs almost nothing until it's needed, and then it injects the expert playbook.

Practical consequences:

- Wording matters. "My instance is slow, PAGEIOLATCH_SH waits are high" fires `sqlserver-monitoring`. "Here's the .sqlplan, why is it slow" fires `sqlserver-query-plans`. "Analyze this database and tell me what to fix" fires `sqlserver-advisor`.
- You can force a skill: in Claude Code type `/sqlserver-monitoring ...`; in Cowork just say "use the sqlserver-query-plans skill on this file".
- Scripts are read-only diagnostics, but they are still community code. Read the header of each `.sql` before running it on production; several need `VIEW SERVER STATE`.
- Skills give the agent knowledge, not access. To run the scripts against a live instance the agent needs a path to the server: `sqlcmd`, an MCP server, or you paste result sets back.

## 3. Three ways to use them

### A. In this Cowork session (already working)

Paste output (sp_BlitzFirst, sp_WhoIsActive, wait stats, `sys.dm_db_missing_index_details`, a Query Store grid, or attach a `.sqlplan` / `.xml`) and ask a question. Examples that route correctly:

- "Attach `slow_proc.sqlplan`. What is actually slow and would a covering index help?" → `sqlserver-query-plans` runs `extract.py`, ranks operators by self-time, checks EstimateRows/ActualExecutions, then `sqlserver-engineering` proposes the index.
- "Here's `sys.dm_os_wait_stats` from prod after 3 days uptime, plus PLE and memory grants pending. Diagnose." → `sqlserver-monitoring` waits methodology.
- "Give me a read-only capture script bundle for a SQL 2019 Enterprise box, then I'll upload the CSVs." → `sqlserver-advisor` stage 2; you run the collectors, attach the CSVs, I load them into DuckDB here and produce the prioritized report.
- "Should this Azure SQL DB be GP 8 vCore or Hyperscale? Here's the DTU/CPU history." → `sqlserver-cloud`.

If you connect a folder from your PC (Add folder in the desktop app), I can read `.sqlplan` files and CSV captures straight from it and write the reports back beside them.

### B. On your workstation in Claude Code / Copilot CLI / SSMS 22 Copilot (persistent, with live server access)

Claude Code native plugins (recommended; auto-updates from GitHub):

```
/plugin marketplace add chrishuffman5/sqlserver
/plugin install sqlserver@sqlserver
/plugin marketplace add erikdarlingdata/claude-plugins
/plugin install sqlserver-query-plans@erikdarling
```

Or copy the skill folders once so Claude Code, Codex, Copilot CLI and SSMS Copilot all see them (PowerShell):

```powershell
git clone https://github.com/chrishuffman5/sqlserver.git
git clone https://github.com/erikdarlingdata/claude-plugins.git
foreach ($d in "$HOME\.claude\skills", "$HOME\.agents\skills") {
  New-Item -ItemType Directory -Force $d | Out-Null
  Copy-Item -Recurse -Force sqlserver\skills\* $d
  Copy-Item -Recurse -Force claude-plugins\plugins\sqlserver-query-plans\skills\query-plan-analysis "$d\sqlserver-query-plans"
}
```

SSMS 22's Copilot Agent mode discovers skills in `~/.claude/skills` and `~/.agents/skills` too, so the same folders light up inside SSMS.

Then give the agent a way to reach the server. Pick one:

1. `sqlcmd` (Brent Ozar's preferred approach). Claude Code will run `sqlcmd -S srv -d db -E -i script.sql -W -s ","` itself. Use a login with `VIEW SERVER STATE` only.
2. Microsoft's official MSSQL MCP server (Azure-Samples/SQL-AI-samples, `MssqlMcp/dotnet`, has a read-only switch).
3. Erik Darling's Performance Studio MCP (13 plan/Query Store tools) and Performance Monitor MCP (77 read-only tools over your collected waits, blocking, deadlocks, grants, file I/O). `claude mcp add --transport http --scope user performance-studio http://localhost:5152/`.

Example Claude Code session once wired up:

```
> Use sqlserver-monitoring. Run scripts/02-wait-stats.sql and 05-blocking.sql against PRODSQL01
  via sqlcmd, then tell me the top three bottlenecks with evidence.
> Now pull the plan for query_id 4471 from Query Store and analyze it with sqlserver-query-plans.
> Draft the index with sqlserver-engineering, include a rollback, and estimate write overhead.
```

### C. As account skills in claude.ai / Cowork on every device

Settings → Capabilities → Skills → Upload. Use the per-skill zips in this delivery (`sqlserver-monitoring.zip`, `sqlserver-engineering.zip`, `sqlserver-query-plans.zip`, etc.). Each zip has the skill folder at its root, which is the format claude.ai expects. Upload only the ones you want; the router (`sql-server.zip`) is optional in claude.ai because I route by description anyway.

## 4. A suggested daily workflow

1. Triage (5 min): sp_BlitzFirst @ExpertMode or `sqlserver-monitoring/scripts/01-server-health.sql` + `02-wait-stats.sql`. Paste to Claude.
2. Find the query: sp_BlitzCache / sp_QuickieStore / `09-query-store-analysis.sql`.
3. Read the plan: save `.sqlplan`, hand it to `sqlserver-query-plans`. Trust its self-time ranking over SSMS cost percentages.
4. Fix: `sqlserver-engineering` for rewrite or index; verify with sp_BlitzIndex @TableName (or its `@AI = 2` prompt pasted here) for duplicate/overlap and write cost.
5. Weekly: `sqlserver-advisor` capture → DuckDB → prioritized report, trend week over week.

## 5. Top 15 — guru-grade performance / query tuning assets, by priority

Ranked for a SQL Server + Azure + AWS performance tuner. "Skill" means a SKILL.md package an agent loads; "Tool + AI hook" means a guru tool with a built-in AI or MCP surface that plugs into the same workflow. Only two of the gurus you named ship agent-native assets (Erik Darling and Brent Ozar); Itzik Ben-Gan does not, so his material appears as the thing to wrap.

| # | Asset | Author | Type | Why it ranks here |
|---|---|---|---|---|
| 1 | sqlserver-query-plans (erikdarlingdata/claude-plugins, v1.5.4) | Erik Darling | Skill | Only plan reader written by a top tuner. Corrects the classic LLM mistakes (cost % as measurement, cumulative times, EstimateRows vs ActualRows/executions, verbatim missing-index DDL). UTF-16-safe extractor. Installed. |
| 2 | Performance Studio + MCP server (30 rules, 13 MCP tools) | Erik Darling | Tool + AI hook | Free plan analyzer: spills, grant ratio, 10x misestimates, key/RID lookups, thread skew, late filters, implicit conversions, UDFs. SSMS 18–22 extension. Feeds #1 with live Query Store plans. |
| 3 | Performance Monitor Lite + MCP (42 collectors, 77 read-only tools) | Erik Darling | Tool + AI hook | Replaces a paid monitor. Supports 2016–2025, Azure SQL DB/MI, RDS. AI questions are answered from your captured data, not generic advice. |
| 4 | First Responder Kit with @AI (sp_BlitzCache, sp_BlitzIndex, sp_BlitzFirst @EmergencyMode, sp_BlitzPlanCompare) | Brent Ozar | Tool + AI hook | July 2026 release: `@AI = 2` builds a token-minimized prompt (metrics + text + plan, or index/FK/datatype metadata) you paste to me; `@AI = 1` calls the API from SQL 2025/Azure SQL. |
| 5 | sqlserver-monitoring + sqlserver-engineering (chrishuffman5) | C. Huffman | Skill | Installed. 19 DMV/Query Store/index/plan-cache/sniffing scripts with a waits-first methodology. Broadest SQL Server-specific script library in skill form. |
| 6 | sqlserver-advisor (chrishuffman5) | C. Huffman | Skill | Installed. Offline DuckDB analysis modeled on Erik's "Lite" pattern; one read-only pass, iterate locally, trend weekly. |
| 7 | Darling Data procs: sp_PressureDetector, sp_PerfCheck, sp_QuickieStore, sp_QuickieCache, sp_HumanEvents, sp_HealthParser, sp_LogHunter, sp_IndexCleanup, sp_QueryReproBuilder | Erik Darling | Tool + skill (`darling-tools`, this repo) | The consultant toolkit for memory/CPU pressure, Query Store mining, XEvents. Wrapped: parameter catalog, interpretation thresholds, 9 scripts. Installed. |
| 8 | sp_WhoIsActive | Adam Machanic | Tool (wrap as skill) | Live activity, blocking chains, `@get_plans`, `@get_task_info=2`. Ideal first script for a monitoring skill to run. |
| 9 | Glenn Berry SQL Server Diagnostic Information Queries (monthly, per version, Azure SQL DB/MI editions) | Glenn Berry | Tool (wrap as skill) | 70+ numbered queries with interpretation notes per result set — practically a SKILL.md already. Highest-value candidate to convert. |
| 10 | Azure SQL Database / Managed Instance / SQL VM skills (MicrosoftDocs/Agent-Skills) | Microsoft | Skill | Official, updated Aug 2026: tier selection, MAXDOP, Intelligent Insights, high-CPU, deadlock and Hyperscale troubleshooting. |
| 11 | Ola Hallengren Maintenance Solution | Ola Hallengren | Tool (wrap as skill) | Index/stats maintenance parameters, CommandLog analysis. A skill around it prevents Claude inventing rebuild thresholds. |
| 12 | Itzik Ben-Gan T-SQL patterns (T-SQL Querying, Window Functions, Fundamentals) | Itzik Ben-Gan | Skill (`itzik-tsql-patterns`, this repo) | Original write-up of the patterns: window frames, gaps/islands, top-N, paging, interval packing, cursor rewrites, POC indexing, batch mode on rowstore. Installed. |
| 13 | Paul Randal / SQLskills wait-type and latch library (SQLskills Wait Types Library, Pro SQL Server Internals) | Paul Randal | Reference (wrap as skill) | The canonical "what does this wait mean and what do I do" source. A `references/waits.md` built from it makes any monitoring skill markedly better. |
| 14 | Hugo Kornelis SQL Server Execution Plan Reference | Hugo Kornelis | Reference (wrap as skill) | Operator-by-operator semantics, the depth Erik's `references/operators.md` points toward. Perfect companion to #1. |
| 15 | hmohamed01/SQL-Expert and vince-winkintel/sql-server-skills | Community | Skill | Lighter than #5 but well-focused on SARGability, implicit conversions, parameter sniffing and sqlcmd-driven DMV diagnostics. Useful as second opinions. |

Notes on the ranking: 1–6 are installable today and were verified here; 7–9 and 11 are gurus' tools that have no skill wrapper yet — that wrapper is the single biggest gap in the ecosystem and is easy to build; 12–14 are knowledge sources that would become skills' `references/` folders. Both `darling-tools` and `itzik-tsql-patterns` now exist in this repo (v1.1.0).
