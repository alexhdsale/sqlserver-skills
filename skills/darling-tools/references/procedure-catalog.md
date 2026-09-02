# DarlingData procedure catalog

Condensed from the upstream READMEs at
https://github.com/erikdarlingdata/DarlingData (commit recorded in
`UPSTREAM_COMMITS.txt`). Every procedure also takes `@help bit`, `@debug bit`,
`@version varchar OUTPUT`, `@version_date datetime OUTPUT`. Run `@help = 1`
when a parameter below is rejected: the procedures move fast.

Support: only Microsoft-supported SQL Server versions. Most need
`VIEW SERVER STATE`; Query Store procedures need read access to the target
database's Query Store views.

Common logging block (sp_PressureDetector, sp_HealthParser,
sp_HumanEventsBlockViewer, sp_QuickieStore): `@log_to_table bit = 0`,
`@log_database_name sysname = NULL (current)`, `@log_schema_name = NULL (dbo)`,
`@log_table_name_prefix = '<ProcName>'`, `@log_retention_days int = 30`
(0 = keep forever).

---

## sp_PressureDetector

Point-in-time CPU and memory pressure, with running queries. Result sets:
wait stats since startup, file size/stall/activity, tempdb config, memory
consumers, low-memory indicators, memory config, current memory grants, CPU
config and retained utilization, thread counts, THREADPOOL waits (use the DAC
if the server is thread-starved), currently executing queries.

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `@what_to_check` | varchar | `all` | `all`, `cpu`, `memory` |
| `@skip_queries` | bit | 0 | skip running-query result set |
| `@skip_plan_xml` | bit | 0 | skip plan XML for running queries (cheaper) |
| `@minimum_disk_latency_ms` | smallint | 100 | floor for reporting file stalls |
| `@cpu_utilization_threshold` | smallint | 50 | floor for reporting high CPU |
| `@skip_waits` | bit | 0 | |
| `@skip_perfmon` | bit | 0 | |
| `@sample_seconds` | tinyint | 0 | 0-255; >0 takes a before/after sample and reports deltas |
| `@troubleshoot_blocking` | bit | 0 | show blocking chains instead of pressure analysis |
| logging block | | | see above; prefix `PressureDetector` |

## sp_PerfCheck

Prioritized health check, server + every accessible user database.
SQL Server 2016 SP2+, Azure SQL DB supported. Two result sets: server
information, then findings sorted by `priority` (10 Critical, 20 High,
30 Medium, 40 Low, 50 Informational) with `priority_label`. Findings in the
`Errors` category mean a collection step could not run; never treat them as
"clean".

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `@database_name` | sysname | NULL | NULL = all user databases |
| `@slow_read_ms` | decimal(10,2) | 20.0 | Medium above this, High above 5x |
| `@slow_write_ms` | decimal(10,2) | 20.0 | same scale |
| `@significant_wait_threshold_pct` | decimal(38,2) | 10.0 | min % of uptime to report a wait |
| `@wait_high_pct` | decimal(38,2) | 50.0 | resource wait High threshold (% of uptime) |
| `@wait_medium_pct` | decimal(38,2) | 20.0 | resource wait Medium threshold |
| `@memory_grant_warning` | int | 100 | forced grants cumulative, Medium |
| `@memory_grant_critical` | int | 10000 | forced grants cumulative, High |
| `@memory_grant_timeout_warning` | decimal(38,2) | 10.0 | grant timeouts, Medium |
| `@memory_grant_timeout_critical` | decimal(38,2) | 100.0 | grant timeouts, High |

NULL or negative threshold falls back to default. Check id ranges: 1000 server
config and trace flags, 2000 tempdb, 3000 storage (only files with >1,000
reads/writes), 4000 server health (dumps, forced grants, token cache,
LPIM/IFI box-only), 5000 default trace (autogrow, autoshrink, DBCC, deadlock
rate), 6000 waits by category / stolen memory / signal wait / SOS_SCHEDULER_YIELD,
7000 database config, 7100 file growth settings.

## sp_HumanEvents

Creates and reads Extended Event sessions for five scenarios. Default is a
timed sample returned as result sets; `@keep_alive = 1` creates a permanent
session for an Agent job to poll into tables. **Can harm performance**:
plans and zero-duration waits add observer overhead.

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `@event_type` | sysname | `query` | `blocking`, `query`, `waits`, `recompiles`, `compiles` |
| `@query_duration_ms` | decimal | 500 | floor; 0 captures everything; fractional ms allowed |
| `@query_sort_order` | nvarchar | `cpu` | `cpu`, `reads`, `writes`, `duration`, `memory`, `spills`, `avg <metric>`, `event_time` |
| `@skip_plans` | bit | 0 | set 1 for the first pass on a busy server |
| `@keep_prepare_rpc` | bit | 0 | include sp_prepare/sp_execute traffic (driver behaviour, e.g. pyodbc fast_executemany) |
| `@blocking_duration_ms` | int | 500 | floor for blocked process report |
| `@wait_type` | nvarchar | `all` | single or CSV list; `all` = curated "interesting" list |
| `@wait_duration_ms` | int | 10 | floor per wait |
| `@client_app_name`, `@client_hostname`, `@database_name`, `@username`, `@object_name`, `@object_schema` | sysname | blank / dbo | inclusive filters |
| `@session_id` | nvarchar | blank | integer, or `sample` with `@sample_divisor` (default 5, SPID % n) |
| `@requested_memory_mb` | int | 0 | only queries asking for at least this grant |
| `@seconds_sample` | tinyint | 10 | sample length |
| `@gimme_danger` | bit | 0 | remove duration floors on wait events; test only |
| `@target_output` | sysname | `ring_buffer` | `event_file` not available on Azure SQL DB / MI |
| `@keep_alive` | bit | 0 | permanent session |
| `@custom_name` | sysname | blank | name for the permanent session |
| `@output_database_name`, `@output_schema_name` | sysname | blank / dbo | logging target for permanent sessions |
| `@delete_retention_days` | int | 3 | positive integer |
| `@cleanup` | bit | 0 | drops all sessions, tables and views; needs output db + schema |
| `@max_memory_kb` | bigint | 102400 | ring buffer size |

Blocking capture requires `blocked process threshold` (seconds) to be set
via `sp_configure` (5 s is the usual value); the procedure tells you if it is
not.

## sp_HumanEventsBlockViewer

Parses any XE session that captures `sqlserver.blocked_process_report`,
including `system_health`, or a table holding BPR XML. Returns blocking
chains, plans of involved queries, and a findings rollup.

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `@session_name` | sysname | `keeper_HumanEvents_blocking` | any BPR session; `system_health` works |
| `@target_type` | sysname | NULL | `event_file`, `ring_buffer`, `table` |
| `@start_date`, `@end_date` | datetime2 | NULL (last 7 days) | |
| `@database_name`, `@object_name` | sysname | NULL | object must be schema-prefixed |
| `@target_database`, `@target_schema`, `@target_table`, `@target_column`, `@timestamp_column` | sysname | NULL | when `@target_type = 'table'`; timestamp column **must be UTC** |
| `@max_blocking_events` | int | 5000 | 0 = unlimited |
| `@skip_execution_plans` | bit | 0 | jump straight to findings |
| logging block | | | prefix `HumanEventsBlockViewer` |

## sp_QuickieStore

Query Store navigator. Default: top 10 by average CPU, last 7 days, current
database. Dates converted to UTC internally; pass local time.

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `@database_name` | sysname | current | Query Store must be enabled |
| `@sort_order` | varchar | `cpu` | averages: `cpu`, `logical reads`, `physical reads`, `writes`, `duration`, `memory`, `log`, `tempdb`, `executions`, `recent`, `rows`, `plan count by hashes`; waits: `cpu waits`, `lock waits`, `latch waits`, `buffer latch waits`, `buffer io waits`, `log io waits`, `network io waits`, `parallel waits`, `memory waits`, `total waits`; totals: `total cpu`, `total logical reads`, `total physical reads`, `total writes`, `total duration`, `total memory`, `total log`, `total tempdb`, `total rows` |
| `@top` | bigint | 10 | |
| `@start_date`, `@end_date` | datetimeoffset | last 7 days / NULL | |
| `@timezone` | sysname | NULL | display override; see `sys.time_zone_info` |
| `@execution_count` | bigint | NULL | minimum executions |
| `@duration_ms` | bigint | NULL | minimum duration |
| `@execution_type_desc` | nvarchar | NULL | `regular`, `aborted`, `exception`, `failed` (= aborted + exception) |
| `@procedure_schema`, `@procedure_name` | sysname | NULL / dbo | wildcards allowed in name |
| `@include_plan_ids`, `@include_query_ids`, `@include_query_hashes`, `@include_plan_hashes`, `@include_sql_handles` | nvarchar | NULL | CSV; include filters AND across lists |
| `@ignore_plan_ids`, `@ignore_query_ids`, `@ignore_query_hashes`, `@ignore_plan_hashes`, `@ignore_sql_handles` | nvarchar | NULL | CSV |
| `@query_text_search`, `@query_text_search_not` | nvarchar | NULL | wildcards added if missing |
| `@escape_brackets`, `@escape_character` | bit / nchar | 0 / `\` | for ORM text with `[ ]` |
| `@only_queries_with_hints`, `_feedback`, `_variants`, `_forced_plans`, `_forced_plan_failures` | bit | 0 | 2022+ features |
| `@wait_filter` | varchar | NULL | `cpu`, `lock`, `latch`, `buffer latch`, `buffer io`, `log io`, `network io`, `parallelism`, `memory` |
| `@query_type` | varchar | NULL | `ad hoc` or `proc` |
| `@expert_mode` | bit | 0 | extra columns and result sets (context settings, wait stats, plan feedback, hints, variants) |
| `@hide_help_table` | bit | 0 | |
| `@format_output` | bit | 1 | 0 for raw numbers (use 0 when you will compute) |
| `@get_all_databases` | bit | 0 | with `@include_databases` / `@exclude_databases` CSV |
| `@workdays` | bit | 0 | with `@work_start` (9am) / `@work_end` (5pm) |
| `@regression_baseline_start_date`, `@regression_baseline_end_date` | datetimeoffset | NULL / +7 days | compare main window against this baseline |
| `@regression_comparator` | varchar | `absolute` | `relative` or `absolute` |
| `@regression_direction` | varchar | `regressed` | `regressed`, `improved`, `magnitude` |
| `@include_query_hash_totals` | bit | 0 | totals by query hash (skewed by forced plans / plan guides) |
| `@find_high_impact` | bit | 0 | Pareto: the vital few across cpu, duration, reads, writes, memory, executions |
| `@primary_window` | nvarchar | NULL | with high impact: `business`, `off-hours`, `weekend` |
| `@find_parameter_sensitive` | bit | 0 | one row per query_hash + plan_hash ranked by coefficient of variation of `@sort_order` metric, weighted by log of total work |
| `@include_maintenance` | bit | 0 | include index/stats maintenance |
| `@troubleshoot_performance` | bit | 0 | SET STATISTICS XML for the procedure's own queries |
| logging block | | | prefix `QuickieStore` |

## sp_QuickieCache

Plan-cache companion. Aggregates `dm_exec_query_stats`, `_procedure_stats`,
`_function_stats`, `_trigger_stats`, takes top N per dimension (CPU,
duration, reads, writes, memory grant, spills, executions), scores with
`PERCENT_RANK` counting only dimensions where the query is >= 0.1% of total.
Three result sets: cache health (plan age, single-use bloat, duplicates,
USERSTORE_TOKENPERM), high-impact queries with diagnostic signals, workload
profile (Concentrated / Moderate / Flat). SQL 2016 SP1+ for grants/spills.

| Parameter | Type | Default |
|---|---|---|
| `@top` | bigint | 10 (candidates per dimension) |
| `@sort_order` | varchar | `cpu` (secondary sort after impact_score) |
| `@database_name` | sysname | NULL |
| `@start_date`, `@end_date` | datetime | NULL (plan creation time) |
| `@minimum_execution_count` | bigint | 2 |
| `@ignore_system_databases` | bit | 1 |
| `@impact_threshold` | decimal(3,2) | 0.50 |
| `@find_single_use_plans`, `@find_duplicate_plans` | bit | 0 |

Diagnostics emitted: parameter sniffing (>30% CPU/reads variance), plan
instability (multiple plans per hash), wait-bound (duration >> CPU), wasteful
grants (<10% used), tempdb spills, row-count variance, rare-but-expensive,
high frequency (>100 exec/min).

## sp_QueryReproBuilder

Turns Query Store entries into runnable scripts: parameter declarations
removed, compiled parameter values from the plan, context SET options
decoded, `sp_executesql` wrapper for parameterized queries, embedded
constants for OPTION(RECOMPILE) plans. `executable_query` is a clickable XML
column in SSMS. Same include/ignore/text/procedure filters as
sp_QuickieStore, plus `@query_plan_xml xml` to process one plan directly.
Warnings in the script header: temp table, table variable, parameter
embedding, parameter count mismatch (local variables), plan too large,
encrypted module, restricted text.

## sp_HealthParser

Parses the `system_health` session for performance data only (no errors or
security). Result sets: queries with significant waits, waits by count, waits
by duration, I/O issues, CPU task details, memory conditions, overall system
health, limited blocked process report, deadlock XML, plans for blocked and
deadlocked queries when available.

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `@what_to_check` | varchar | `all` | `waits`, `disk`, `cpu`, `memory`, `system`, `locking` |
| `@start_date`, `@end_date` | datetimeoffset | 7 days back / now | converted to UTC |
| `@warnings_only` | bit | 0 | |
| `@database_name` | sysname | NULL | blocking filter |
| `@wait_duration_ms` | bigint | 500 | |
| `@wait_round_interval_minutes` | bigint | 60 | bucket size for wait trend |
| `@skip_locks`, `@skip_waits` | bit | 0 | |
| `@pending_task_threshold` | int | 10 | |
| `@use_ring_buffer` | bit | 0 | faster but shorter history |
| logging block | | | prefix `HealthParser` |

## sp_LogHunter

Searches all error logs for a curated list of bad things, ordered by time so
you see context. Box and MI only.

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `@days_back` | int | -7 | sign normalized automatically |
| `@start_date`, `@end_date` | datetime | NULL | |
| `@custom_message` | nvarchar | NULL | literal, no wildcards |
| `@custom_message_only` | bit | 0 | |
| `@first_log_only` | bit | 0 | current log only |
| `@language_id` | int | 1033 | |

## sp_IndexCleanup (BETA)

Finds unused and duplicate/subset indexes and emits candidate scripts.
Requires SQL 2012+. Warns when uptime < 14 days; forces `@dedupe_only = 1`
when uptime < 7 days. System databases and `rdsadmin` always excluded.

| Parameter | Type | Default |
|---|---|---|
| `@database_name` | sysname | NULL |
| `@schema_name`, `@table_name` | sysname | NULL |
| `@min_reads`, `@min_writes` | bigint | 0 |
| `@min_size_gb` | decimal(10,2) | 0 |
| `@min_rows` | bigint | 0 |
| `@dedupe_only` | bit | 0 |
| `@get_all_databases` | bit | 0 (+ `@include_databases` / `@exclude_databases`) |
| `@sort_order` | varchar(20) | `default` (by script type) or `object` (group per index) |

## sp_QueryStoreCleanup

Removes noise from Query Store via `sp_query_store_remove_query`. Forced
plans are always protected. **Destructive.**

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `@database_name` | sysname | current | |
| `@cleanup_targets` | varchar(100) | `all` | `system` (`FROM sys.%`), `maintenance`, `custom`, `none`, CSV combos |
| `@custom_query_filter` | nvarchar(1024) | NULL | LIKE pattern |
| `@dedupe_by` | varchar(50) | `all` | `query_hash`, `plan_hash`, `none` |
| `@min_age_days` | int | NULL | only queries last executed before this |
| `@report_only` | bit | 0 | **set 1 first** |
