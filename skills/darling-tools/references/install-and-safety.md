# Installing and running the DarlingData procedures safely

## Install

Single file, all procedures, into `master` (or a DBA utility database):

```
https://github.com/erikdarlingdata/DarlingData/raw/main/Install-All/DarlingData.sql
```

Per-procedure files live in each folder, e.g.
`sp_QuickieStore/sp_QuickieStore.sql`, `sp_PressureDetector/sp_PressureDetector.sql`,
`sp_HumanEvents/sp_HumanEvents.sql` and `sp_HumanEvents/sp_HumanEventsBlockViewer.sql`.

Do not install into `master` on Azure SQL Database; install into the user
database you are troubleshooting. On Managed Instance and RDS, `master` is fine.

Check what is installed and how old it is (see `scripts/00-check-versions.sql`).
The procedures change often; a parameter in the catalog may not exist in an
older build. `@help = 1` is authoritative.

## Permissions

| Procedure | Needs |
|---|---|
| sp_PressureDetector, sp_PerfCheck, sp_QuickieCache, sp_HealthParser | `VIEW SERVER STATE` (`VIEW SERVER PERFORMANCE STATE` on 2022+ is enough for most) |
| sp_QuickieStore, sp_QueryReproBuilder, sp_QueryStoreCleanup | `VIEW DATABASE STATE` on the target db; cleanup needs `ALTER` on the database |
| sp_HumanEvents | `ALTER ANY EVENT SESSION`, plus `CREATE TABLE` in the output database when logging; `sp_configure` rights for blocked process threshold |
| sp_HumanEventsBlockViewer | `VIEW SERVER STATE`; read on the target table when `@target_type = 'table'` |
| sp_LogHunter | `xp_readerrorlog` (sysadmin or `securityadmin` + explicit grant) |
| sp_IndexCleanup | `VIEW DATABASE STATE`, read on `sys.dm_db_*` and object metadata |

Prefer a diagnostic login with only `VIEW SERVER STATE` for everything except
sp_HumanEvents and the two mutating procedures.

## Platform matrix

| | Box | Azure SQL MI | Azure SQL DB | AWS RDS |
|---|---|---|---|---|
| sp_PressureDetector | yes | yes | yes (instance rows limited) | yes |
| sp_PerfCheck | yes | yes (4105/4106 skipped) | yes | yes (4105/4106 skipped) |
| sp_QuickieStore / ReproBuilder / StoreCleanup | yes | yes | yes | yes |
| sp_QuickieCache | yes | yes | yes | yes |
| sp_HumanEvents | yes | ring_buffer only | ring_buffer only | yes, ring_buffer safest |
| sp_HumanEventsBlockViewer | yes | yes | yes (ring_buffer / table) | yes |
| sp_HealthParser | yes | yes | limited | yes |
| sp_LogHunter | yes | yes | no | `rdsadmin` log access varies |
| sp_IndexCleanup | yes | yes | yes | yes (`rdsadmin` excluded) |

## Overhead and safety ranking

| Procedure | Cost | Mutates? |
|---|---|---|
| sp_LogHunter | reads log files, cheap | no |
| sp_PressureDetector | DMV reads; `@skip_plan_xml = 1` and `@skip_queries = 1` make it near-free | no |
| sp_PerfCheck | DMV + default trace reads, seconds | no |
| sp_HealthParser | parses system_health XML, can take a minute on busy servers; `@use_ring_buffer = 1` is faster | no |
| sp_QuickieStore | reads Query Store views; large stores take time, narrow the window | no (`@log_to_table` writes to the DBA db only) |
| sp_QuickieCache | scans plan cache DMVs once | no |
| sp_QueryReproBuilder | parses plan XML for matched plans; filter tightly | no |
| sp_HumanEventsBlockViewer | parses BPR XML; `@max_blocking_events` caps it | no |
| sp_HumanEvents | **creates XE sessions**; plan capture and zero-duration waits add real overhead | yes: sessions, tables, views |
| sp_IndexCleanup | metadata + usage DMVs | no, but emits DDL |
| sp_QueryStoreCleanup | `sp_query_store_remove_query` | **yes, deletes** |

## Change-control labels (repo convention)

- Enabling `blocked process threshold`, creating XE sessions, Agent jobs:
  `[CONFIG CHANGE]`, include the `ALTER EVENT SESSION ... STATE = STOP` /
  `DROP EVENT SESSION` rollback.
- Any index DDL from sp_IndexCleanup: `[SCHEMA CHANGE]`, include the
  `CREATE INDEX` rollback captured from `sys.indexes` before dropping.
- sp_QueryStoreCleanup with `@report_only = 0`: `[DATA-LOSS RISK]`; there is
  no rollback for removed Query Store rows.
- Never execute any of these without explicit confirmation and a named
  server.
