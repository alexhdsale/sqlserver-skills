/*******************************************************************************
 * Darling Data tools - Prioritized health check
 *
 * Purpose : sp_PerfCheck server-wide, then a single database, then a
 *           loosened-threshold run for latency-tolerant systems.
 * Targets : SQL Server 2016 SP2+, Azure SQL DB / MI, AWS RDS.
 * Safety  : Read-only. Reads the default trace (7 days) when readable.
 * Reading : priority 10/20 rows first; "Errors" category = a check that could
 *           not run, never a clean result. references/interpretation-rules.md.
 ******************************************************************************/

/* All user databases, default thresholds */
EXEC dbo.sp_PerfCheck;

/* One database */
-- EXEC dbo.sp_PerfCheck @database_name = N'YourDatabase';

/* Busy OLTP on shared storage: raise storage floors, keep wait thresholds */
-- EXEC dbo.sp_PerfCheck @slow_read_ms = 50.0, @slow_write_ms = 50.0;

/* Report only waits that exceed 15% of uptime */
-- EXEC dbo.sp_PerfCheck @significant_wait_threshold_pct = 15.0;
