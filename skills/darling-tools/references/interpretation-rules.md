# Reading DarlingData output

Thresholds below are the ones the procedures themselves use, or the ones Erik
Darling uses in his write-ups. Quote them when you rank a finding, so the user
can see why it is High rather than Low.

## sp_PressureDetector

**Wait stats result set.** Cumulative since startup. Columns show wait time,
percent of uptime, average per wait, and signal share. Read it as "what has
this server historically waited on", not "what is wrong now". For "now", run
again with `@sample_seconds = 10` and read the sample columns.

- `RESOURCE_SEMAPHORE`: queries waiting for memory grants. Look at the memory
  grants result set: `requested_memory_kb` vs `granted_memory_kb` vs
  `used_memory_kb`, and `ideal_memory_kb`. Many small grants waiting behind a
  few huge ones is the usual shape; the huge ones are the tuning targets, not
  the server memory setting.
- `RESOURCE_SEMAPHORE_QUERY_COMPILE`: compile memory contention, points at
  plan cache churn (unparameterized SQL) or enormous queries.
- `THREADPOOL`: worker starvation. The running-queries set will show tasks
  in `SUSPENDED` with no scheduler. Cause is almost always blocking or
  parallelism fan-out, not "max worker threads". Use the DAC if the procedure
  itself cannot get a thread.
- `SOS_SCHEDULER_YIELD` with high signal-wait share: CPU pressure. Cross-check
  the CPU result set (`retained utilization`) and the running queries by
  `cpu_time`.
- `CXPACKET` / `CXCONSUMER`: parallelism, informational unless paired with
  `CXSYNC_PORT` skew or high overall CPU. Fix the query or CTFP/MAXDOP, not
  the wait.
- `PAGEIOLATCH_*`: reads from disk. Combine with the file stall result set:
  `avg_read_stall_ms` above `@minimum_disk_latency_ms` on data files means
  storage is slow *for this workload*; PLE alone is not evidence.
- `WRITELOG` / `LOGBUFFER`: log write latency, check the log file stall row.
- `LCK_M_*`: blocking. Re-run with `@troubleshoot_blocking = 1` for the chain.

**Memory result sets.** Low-memory indicators non-zero, or
`stolen memory` > 30% of max (sp_PerfCheck 6002 High), or a memory clerk
other than the buffer pool above 1 GB (USERSTORE_TOKENPERM, CACHESTORE_SQLCP,
OBJCP) are actionable; `available physical memory` alone is not.

**Running queries.** Sorted by start time. Columns include wait info, blocking
session, memory grant, CPU, reads, and plan XML (skip with
`@skip_plan_xml = 1`). Anything with a `blocking_session_id` goes to the
blocking path. Anything with `granted_memory_kb` in the GB range and low
`used_memory_kb` is a grant estimate problem (cardinality or wide sorts).

**Blocking mode (`@troubleshoot_blocking = 1`).** Root blockers first. The
head blocker's `wait_type` tells you why *it* is slow (often `ASYNC_NETWORK_IO`
= client not consuming, or a sleeping session with an open transaction).
Killing the head is a `[DATA-LOSS RISK]`-class action: it rolls back.

## sp_PerfCheck

Read priority 10 and 20 rows first and in full. Then group 30s by category.
Do not list 40/50 rows to the user unless asked; summarize their count.

- `Configuration Pending Reconfigure` (1007) and `Offline CPU Schedulers`
  (4001) and `Memory Dumps` (4102) are Critical because they mean the server
  is not what it looks like. Resolve before any tuning.
- `Max Server Memory Too Close To Physical Memory` (1002): leave the OS 10%
  or 4 GB, whichever is larger, plus whatever else runs on the box.
- `Cost Threshold for Parallelism` (1004): High only while still at 5. Erik's
  usual starting point is 50; raise it before touching MAXDOP.
- `MAXDOP Not Configured` (1003) is Low, on purpose. Set it per the NUMA
  guidance, but it is rarely the root cause.
- Wait findings (6001) are named by category (`Storage-Related Waits`,
  `Lock / Blocking Waits`, `TempDB Contention Waits`, `Transaction Log Waits`,
  `CPU / Scheduling Waits`, `Parallelism Waits`, `Memory-Related Waits`,
  `Availability Group Waits`, `Azure SQL Throttling Waits`, ...). The wait
  type and its meaning are in `object_name`. Severity: resource waits High at
  `@wait_high_pct` of uptime or 1 s average, Medium at `@wait_medium_pct` or
  250 ms average; parallelism needs 100% of uptime for Medium; everything
  else Low.
- `High Signal Wait Ratio` (6101) / `High SOS_SCHEDULER_YIELD` (6102): 25%
  fires, 30% Medium, 50% High. This is CPU scheduling pressure, confirm with
  sp_PressureDetector CPU set.
- Storage (3001/3002): only files with > 1,000 reads/writes count, Medium at
  20 ms, High at 100 ms. `Multiple Slow Files on Storage Location` (3003)
  points at the volume, not the file.
- `Large Security Token Cache` (4104): 1 GB fires, 2 GB Medium, 5 GB High.
  Fix with the repo's `Clear Token Perm` job, or reduce the number of
  distinct logins / sysadmin-less connections that churn tokens.
- `High Number of Deadlocks` (5103): > 9/day Medium, > 50/day High. Go to
  sp_HealthParser locking section or sp_HumanEventsBlockViewer.
- Database 7000s: `Auto-Shrink` (7001) and `Delayed Durability` (7008) are
  Medium because they cause damage; `Query Store Not Enabled` (7006) is
  Informational but blocks sp_QuickieStore, so mention it.
- 7103 log growth "not exactly 64 MB" applies only to SQL 2022+, Azure SQL
  DB, MI (VLF sizing change).

## sp_QuickieStore

**Which sort to use.**

| Symptom from waits / pressure | `@sort_order` | then |
|---|---|---|
| CPU pressure, signal waits | `total cpu` (workload) and `cpu` (per call) | `@find_parameter_sensitive = 1` |
| PAGEIOLATCH, slow reads | `total logical reads` | index or rewrite, **sqlserver-engineering** |
| RESOURCE_SEMAPHORE | `memory` and `memory waits` | grant estimate vs used |
| LCK_M_* | `lock waits` | look at duration vs cpu gap |
| Log waits | `total log` / `log io waits` | batch size, index count, durability |
| tempdb | `total tempdb` | spills, table variables, sorts |
| "something regressed" | keep `cpu`, add regression baseline | |
| Unknown | `@find_high_impact = 1` | |

**Reading the main result set.** One row per plan_id. Key columns:
`query_id`, `plan_id`, `execution_count`, `avg_*`, `total_*`, `last_execution`,
`query_sql_text`, `query_plan` (XML), `is_forced_plan`, `plan_forcing_type`,
`compatibility_level`, `count_executions` by execution type. With
`@expert_mode = 1` you also get context settings (SET options: a plan-shape
difference between SSMS and the app is often `ARITHABORT`), wait stats by
category per plan, Query Store options (state, capture mode, size, cleanup),
and on 2022+ plan feedback / hints / variants.

- `avg_duration` >> `avg_cpu`: the query waits. Look at its wait category
  columns (lock, buffer io, network io, memory, parallelism). Network io
  means the client is slow to consume; do not tune the query.
- `avg_cpu` close to `avg_duration` and high: work. Plan goes to
  **sqlserver-query-plans**.
- `plan count by hashes` sort: many plans for one query_hash is instability;
  parameter sensitivity, recompiles or unparameterized text.
- `execution_type_desc` `aborted`/`exception` rows: timeouts. Sort by
  `duration` with `@execution_type_desc = 'failed'` to find client timeouts.
- `avg_memory` in the GB range with `avg_tempdb` spills: estimate too high
  and too low at once, classic sniffing.
- `is_forced_plan = 1` with `force_failure_count` > 0: forced plan is not
  being applied (index dropped, schema change). Un-force or fix.

**Regression mode.** `@regression_baseline_start_date` = the known-good
window; main `@start_date`/`@end_date` = now. Rows are sorted by change in the
`@sort_order` metric. `absolute` finds the biggest raw jump, `relative` finds
the biggest ratio (small queries can top it). Use `@include_query_hash_totals`
when the plan_id changed between windows so you compare the query, not the
plan.

**High impact mode.** Pareto across CPU, duration, reads, writes, memory,
executions. `impact_score` near 1.0 with a single dominant dimension is the
tuning target; a flat workload (no query above threshold) means server-level
settings or storage, not query tuning.

**Parameter-sensitive mode.** One row per query_hash + plan_hash; high
coefficient of variation with meaningful total work. Confirm with
`sp_QueryReproBuilder` on the fast and slow parameter sets before recommending
`OPTION (RECOMPILE)`, `OPTIMIZE FOR`, or a plan guide. On 2022+, check whether
PSP optimization already created variants (`@only_queries_with_variants = 1`).

## sp_QuickieCache

Plan cache is volatile: results reflect what survived since the last cache
clear, restart, or memory pressure event. Check `plan age distribution` in the
first result set before trusting the numbers; a cache that is mostly minutes
old cannot rank a daily workload. `single-use plan bloat` per database means
`optimize for ad hoc workloads` or forced parameterization is worth
discussing. `duplicate plan detection` per hash is the same instability signal
as Query Store's `plan count by hashes`.

## sp_HumanEvents

**Query session.** Result sets are sorted by `@query_sort_order`. Look at the
`statement` vs `batch` level rows; the statement rows carry the plan. Rows
with `spills` > 0 or `memory grant` far above use are the same signals as
Query Store, but for a live sample of a workload that Query Store may be
aggregating away (short-lived ad hoc queries, temp table churn).

**Blocking session.** Output is blocked process report XML parsed into
blocker / blocked pairs with `wait_resource`, `lock_mode`,
`transaction_isolation_level`, `last_transaction_started`. A blocker whose
`status` is `sleeping` holds an open transaction and is idle: application
bug. `isolation_level` `serializable` from an ORM (`TransactionScope`
default) is a frequent cause.

**Waits session.** Per-query and per-database wait breakdown for the sample.
This is the right tool when cumulative waits are polluted by history.

**Compiles / recompiles.** Count by object and by reason
(`statistics changed`, `temp table changed`, `SET option change`,
`OPTION (RECOMPILE)`). Thousands of compiles per minute from ad hoc text is
a parameterization problem; recompiles from statistics on temp tables inside
one procedure is a "too many temp tables / KEEP PLAN" discussion.

## sp_HumanEventsBlockViewer

Findings rollup at the end names the pattern (long-running head blocker,
lock escalation, isolation level, missing index causing scans under locks).
The plans result set is for the queries involved; if the same head blocker
recurs, its plan goes to **sqlserver-query-plans**. Use
`@skip_execution_plans = 1` for the first pass on large sessions.

## sp_HealthParser

Its wait data comes from `system_health`'s periodic snapshot, bucketed by
`@wait_round_interval_minutes`, so it answers "when did waits change", which
cumulative DMVs cannot. `Potential I/O issues` come from the
`sp_server_diagnostics` IO subsystem component and `Memory conditions` from
its resource component; a `warning` there is the engine's own judgment. The
deadlock XML result set is the same `xml_deadlock_report` SSMS shows, already
extracted. The blocked process report here is limited to what
`sp_server_diagnostics` captures; for full history use a dedicated BPR session
and sp_HumanEventsBlockViewer.

## sp_LogHunter

Everything is time-ordered on purpose: read the rows around the hit. Common
hits that matter: I/O requests taking longer than 15 seconds, latch timeouts,
`A significant part of sql server process memory has been paged out`,
`AppDomain ... unloaded` (CLR memory), non-yielding scheduler, deadlocked
schedulers, stack dumps, login failures in bursts, corruption errors (823,
824, 825), AG role changes, long-running recovery. Each of those maps to a
different owner (storage, memory config, code, security, HA).

## sp_IndexCleanup

Treat output as a review list. For each candidate confirm: uptime covers a
full business cycle (month-end, quarter-end); the index is not a unique or
primary key constraint; not referenced by a hint, filtered index, indexed
view, replication article, or foreign-key seek; and the "subset" replacement
actually covers its predicates and included columns. Prefer disabling
(`ALTER INDEX ... DISABLE`) for a cycle before dropping. All emitted DDL is
`[SCHEMA CHANGE]` with a rollback (`CREATE INDEX` script kept).

## sp_QueryStoreCleanup

Run `@report_only = 1` and show the counts by target. Removing rows deletes
history that regression comparisons rely on; if the user is mid-investigation,
defer. `@min_age_days` keeps recent entries. Forced plans are never removed.
Label the real run `[DATA-LOSS RISK]`.
