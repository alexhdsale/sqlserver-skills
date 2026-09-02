/*******************************************************************************
 * Darling Data tools - "What happened at 03:00?" (system_health + error log)
 *
 * Purpose : Reconstruct a past incident from data SQL Server already kept:
 *           sp_HealthParser over the system_health session and sp_LogHunter
 *           over the error logs, aligned on the same window.
 * Targets : SQL Server 2016+, MI. sp_LogHunter is not available on Azure SQL
 *           DB; on RDS error log access goes through rdsadmin.
 * Safety  : Read-only.
 * Reading : references/interpretation-rules.md, sections sp_HealthParser and
 *           sp_LogHunter.
 ******************************************************************************/

DECLARE @from datetime2(0) = '2026-09-02 02:30',
        @to   datetime2(0) = '2026-09-02 04:00';

/* 1. Warnings only, all areas, hourly wait buckets */
EXEC dbo.sp_HealthParser
    @what_to_check              = 'all',
    @start_date                 = @from,
    @end_date                   = @to,
    @warnings_only              = 1,
    @wait_round_interval_minutes = 15;

/* 2. Full detail for the area the warnings pointed at ('waits','disk','cpu','memory','system','locking') */
-- EXEC dbo.sp_HealthParser @what_to_check = 'memory', @start_date = @from, @end_date = @to;

/* 3. Error log, same window, everything interesting in time order */
EXEC dbo.sp_LogHunter
    @start_date = @from,
    @end_date   = @to;

/* Last 7 days, current log only, plus a custom string */
-- EXEC dbo.sp_LogHunter @days_back = 7, @first_log_only = 1, @custom_message = N'AppDomain';

/* Faster but shorter history for HealthParser */
-- EXEC dbo.sp_HealthParser @use_ring_buffer = 1, @warnings_only = 1;
