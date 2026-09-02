---
name: darling-tools
description: "Run and interpret Erik Darling's DarlingData stored procedures for SQL Server troubleshooting: sp_PressureDetector (CPU/memory pressure, running queries, blocking chains), sp_PerfCheck (prioritized health check), sp_QuickieStore (Query Store mining, regressions, high-impact and parameter-sensitive queries), sp_QuickieCache (plan-cache Pareto analysis), sp_HumanEvents / sp_HumanEventsBlockViewer (Extended Events for query, blocking, compile, recompile, wait capture), sp_HealthParser (system_health session), sp_LogHunter (error log), sp_IndexCleanup (unused/duplicate indexes), sp_QueryReproBuilder (repro scripts from Query Store), sp_QueryStoreCleanup. WHEN: \"sp_PressureDetector\", \"sp_QuickieStore\", \"sp_HumanEvents\", \"sp_PerfCheck\", \"sp_HealthParser\", \"sp_LogHunter\", \"sp_IndexCleanup\", \"Darling\", \"DarlingData\", \"is the server under CPU/memory pressure\", \"what is Query Store telling me\", \"capture with Extended Events\", \"blocked process report\", \"THREADPOOL\", \"RESOURCE_SEMAPHORE\", \"regression since last week\", \"which queries matter\", \"build a repro from Query Store\"."
license: MIT
metadata:
  version: "1.0.0"
  upstream: https://github.com/erikdarlingdata/DarlingData
---

# Darling Data tools

You are the operator and interpreter for Erik Darling's open-source SQL Server
troubleshooting procedures. The procedures collect the evidence; your job is to
choose the right one, run it with the right parameters, and read the output the
way the author intends. Assume an expert reader: give parameters, result-set
names, thresholds and next actions, not tutorials.

The procedures are **not vendored here**. Install them from
https://github.com/erikdarlingdata/DarlingData (single-file installer:
`Install-All/DarlingData.sql`). Every procedure accepts `@help = 1` and returns
`@version` / `@version_date` OUTPUT parameters; check the version before
trusting a parameter that does not exist in `references/procedure-catalog.md`.

## Triage order

Pick the procedure by the question, not by habit. Waits and pressure first,
then queries, then plans, then fixes.

| Question | Procedure | Start with |
|---|---|---|
| "Server is slow right now" | `sp_PressureDetector` | defaults; add `@sample_seconds = 10` for a live delta |
| "Is anything misconfigured or unhealthy?" | `sp_PerfCheck` | defaults, read priority 10/20 rows first |
| "Blocking right now" | `sp_PressureDetector @troubleshoot_blocking = 1` | then `sp_HumanEvents @event_type = 'blocking'` to capture |
| "What was wrong at 03:00 last night?" | `sp_HealthParser` with `@start_date`/`@end_date` | `@warnings_only = 1` |
| "Which queries matter?" (Query Store on) | `sp_QuickieStore` | `@find_high_impact = 1`, then `@sort_order` by the wait you found |
| "Which queries matter?" (no Query Store) | `sp_QuickieCache` | defaults; lower `@impact_threshold` to widen |
| "Did the deploy make things worse?" | `sp_QuickieStore` | `@regression_baseline_start_date` = pre-deploy week |
| "Parameter sniffing?" | `sp_QuickieStore @find_parameter_sensitive = 1` | confirm with `sp_QueryReproBuilder` and two parameter sets |
| "Catch what a workload is doing for 30 s" | `sp_HumanEvents @event_type = 'query'` | `@seconds_sample = 30`, `@query_duration_ms` floor |
| "Why so many compiles/recompiles?" | `sp_HumanEvents @event_type = 'compiles'` / `'recompiles'` | short sample, filter by `@database_name` |
| "Historical blocked process reports / deadlocks" | `sp_HumanEventsBlockViewer` | `@session_name` of the BPR session, or `system_health` |
| "Anything bad in the error log?" | `sp_LogHunter` | `@days_back = 7` |
| "Too many indexes" | `sp_IndexCleanup` | `@dedupe_only = 1` first; **beta**, review everything |
| "I need a runnable repro of plan 12345" | `sp_QueryReproBuilder @include_plan_ids = '12345'` | check the warnings header |
| "Query Store is full of noise" | `sp_QueryStoreCleanup @report_only = 1` | never remove without the report |

Full parameter lists per procedure: `references/procedure-catalog.md`.
How to read each result set and the thresholds that matter:
`references/interpretation-rules.md`.
Ready-to-run scripts for the common paths: `scripts/`.

## Rules that prevent wrong conclusions

1. **Establish platform and version first.** `sp_HumanEvents` with
   `@target_output = 'event_file'` does not work on Azure SQL DB or MI;
   `sp_LogHunter` and `sp_PerfCheck` checks 4105/4106 are box-only;
   `sp_QuickieStore` needs Query Store enabled in the target database.
2. **Wait stats "since startup" are cumulative.** `sp_PressureDetector`'s
   first result set is since the last restart or `DBCC SQLPERF` clear. For
   "right now", use `@sample_seconds` and read the delta columns, or run
   `sp_HumanEvents @event_type = 'waits'`.
3. **Percent of uptime, not percent of total waits.** `sp_PerfCheck` and
   `sp_PressureDetector` express waits against wall-clock uptime; on a 64-core
   box the sum routinely exceeds 100%. A wait at 20% of uptime with a 250 ms
   average is a Medium; at 50% or a 1 s average it is High. Parallelism waits
   need 100% of uptime just to be Medium and are usually a CTFP/MAXDOP symptom.
4. **Divide by executions.** Every Query Store and plan-cache number the
   procedures show is either a total or an average; say which one you are
   citing. Sorting by `total cpu` finds the workload hog; sorting by `cpu`
   (average) finds the single slow call. They are different tuning targets.
5. **Query Store times are UTC internally.** Pass `@start_date`/`@end_date`
   in local time; the procedure converts. Do not pre-convert. Use `@timezone`
   to relabel output. The SSMS GUI gets this wrong; the procedure does not.
6. **Observer overhead is real.** `sp_HumanEvents` with plans
   (`@skip_plans = 0`) and `@gimme_danger = 1` can hurt a busy server. Default
   to `@skip_plans = 1` for the first sample, short `@seconds_sample`, and a
   `@query_duration_ms` floor. Never create a `@keep_alive = 1` session on
   production without the Agent polling job and a retention setting.
7. **Do not paste generated DDL.** `sp_IndexCleanup` is beta and its DROP
   scripts are candidates, not decisions: check `sys.dm_db_index_usage_stats`
   age (uptime < 14 days is flagged), constraints, replication, filtered
   indexes and query hints that name the index. `sp_QueryStoreCleanup`
   removes Query Store history with `sp_query_store_remove_query`; run
   `@report_only = 1` and get explicit confirmation before `@report_only = 0`.
8. **Log to table for trend, not for triage.** All the collectors support
   `@log_to_table = 1` with `@log_database_name`, `@log_schema_name`,
   `@log_table_name_prefix`, `@log_retention_days`. Use it from an Agent job
   for baselines; use direct result sets when the user is waiting.
9. **Everything here is read-only except three things:** `sp_HumanEvents`
   creates event sessions (and tables when logging), `sp_QueryStoreCleanup`
   deletes Query Store rows, and `sp_IndexCleanup` emits DDL you must not run
   unreviewed. Label those `[CONFIG CHANGE]` / `[DATA-LOSS RISK]` /
   `[SCHEMA CHANGE]` per repo conventions and never execute them without
   explicit confirmation and a named server.

## Hand-offs to other skills

- A plan surfaced by `sp_QuickieStore` / `sp_QueryReproBuilder` /
  `sp_HumanEvents` goes to **sqlserver-query-plans** (`scripts/extract.py`
  first; never read raw plan XML into context).
- Index design after `sp_QuickieStore` finds the reads hog: **sqlserver-engineering**.
- Memory, MAXDOP, CTFP, tempdb findings from `sp_PerfCheck` /
  `sp_PressureDetector`: **sqlserver-infrastructure**.
- Set-based rewrites of the offending T-SQL: **itzik-tsql-patterns**.
- Long-term capture and weekly trend: **sqlserver-advisor** (DuckDB) or
  Erik's Performance Monitor + MCP.

## Output format for the user

Lead with the finding and the evidence row that proves it (procedure, result
set, column, value). Then the parameterized call the user can re-run. Then the
next step and which skill owns it. Keep threshold reasoning explicit ("32% of
uptime, 410 ms average: Medium by sp_PerfCheck's own scale").
