/*******************************************************************************
 * Darling Data tools - "The server is slow right now" triage
 *
 * Purpose : Three passes with sp_PressureDetector: cheap snapshot, live
 *           10-second sample, then blocking chains if lock waits showed up.
 * Targets : SQL Server 2016+, Azure SQL DB / MI, AWS RDS.
 * Safety  : Read-only. Pass 2 sleeps for @sample_seconds inside the procedure.
 * Reading : references/interpretation-rules.md, section sp_PressureDetector.
 ******************************************************************************/

/* Pass 1: snapshot without plan XML (fast, safe on a struggling server) */
EXEC dbo.sp_PressureDetector
    @what_to_check    = 'all',
    @skip_plan_xml    = 1,
    @minimum_disk_latency_ms   = 100,
    @cpu_utilization_threshold = 50;

/* Pass 2: live delta. Use when cumulative waits are dominated by history. */
EXEC dbo.sp_PressureDetector
    @what_to_check  = 'all',
    @sample_seconds = 10,
    @skip_plan_xml  = 1;

/* Pass 3: only if LCK_M_* waits or blocking_session_id appeared above */
EXEC dbo.sp_PressureDetector
    @troubleshoot_blocking = 1;

/* Optional: memory-only, with plans, when RESOURCE_SEMAPHORE dominated */
-- EXEC dbo.sp_PressureDetector @what_to_check = 'memory';

/* Baseline job body (Agent, every 15 min): log instead of returning */
-- EXEC dbo.sp_PressureDetector
--     @log_to_table = 1, @log_database_name = N'DBA', @log_schema_name = N'dbo',
--     @log_table_name_prefix = N'PressureDetector', @log_retention_days = 30;
