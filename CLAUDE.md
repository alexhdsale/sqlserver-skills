# SQL Server Performance Skills (Alexey)

Owner: Alexey — senior SQL Server DBA (AWS, Azure, performance tuning). Assume an expert reader:
skip fundamentals, give evidence, T-SQL, DMV checks, and validation steps.

## Skills in this repo (skills/)

- `sql-server` — router + fundamentals. Start here when the domain is unclear.
- `sqlserver-monitoring` — waits, DMVs, Query Store, XEvents, blocking, deadlocks. 11 read-only scripts.
- `sqlserver-engineering` — indexing, plans, CE/stats, parameter sniffing, partitioning, columnstore. 8 scripts.
- `sqlserver-query-plans` — Erik Darling's plan reader. ALWAYS use for any `.sqlplan` / showplan XML; run `scripts/extract.py` first, never read raw plan XML into context.
- `sqlserver-advisor` — offline capture → DuckDB → prioritized findings report.
- `sqlserver-infrastructure` — memory, MAXDOP/CTFP, tempdb, trace flags, storage.
- `sqlserver-operations` — backup/restore, CHECKDB, Ola, Agent, patching, space.
- `sqlserver-ha-clustering` — AGs, FCI, mirroring, log shipping, replication, DR.
- `sqlserver-cloud` — Azure SQL DB/MI, SQL on Azure VM, AWS RDS, migration tooling.
- `sqlserver-security` — auth, permissions, TDE/AE/TLS, RLS, DDM, audit.
- `azure-sql-database`, `azure-sql-managed-instance`, `azure-sql-virtual-machines` — Microsoft-authored platform skills (tiers, MAXDOP, Intelligent Insights, troubleshooting).

## Conventions

- Establish engine version (`SELECT @@VERSION`), compatibility level and platform (box / Azure SQL DB / MI / RDS) before version-sensitive advice.
- Waits first, then queries, then plans, then fixes. Prefer sp_BlitzFirst / sp_WhoIsActive / sp_QuickieStore / sp_PressureDetector output when the user supplies it; scripts in `skills/*/scripts` are the fallback.
- Plan analysis: cost % are estimates; rank operators by self-time; divide ActualRows by ActualExecutions; treat missing-index requests as hints, check existing indexes and write overhead before proposing DDL.
- All non-read-only T-SQL is labelled `[CONFIG CHANGE]`, `[PERFORMANCE CHANGE]`, `[SCHEMA CHANGE]`, `[SECURITY CHANGE]` or `[DATA-LOSS RISK]`, includes a rollback, and is never executed without explicit confirmation.
- Never run anything against a server without being told which server, and prefer a login with only `VIEW SERVER STATE` for diagnostics.
