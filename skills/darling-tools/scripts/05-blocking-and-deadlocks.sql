/*******************************************************************************
 * Darling Data tools - Blocking now, blocking history, deadlocks
 *
 * Purpose : Current chains via sp_PressureDetector, live capture via
 *           sp_HumanEvents, history via sp_HumanEventsBlockViewer, and
 *           deadlocks via sp_HealthParser.
 * Targets : SQL Server 2016+, Azure SQL DB / MI, AWS RDS.
 * Safety  : Sections 1, 3, 4 read-only. Section 2 is [CONFIG CHANGE]
 *           (blocked process threshold + temporary XE session).
 * Reading : references/interpretation-rules.md.
 ******************************************************************************/

/* 1. Right now: root blockers first */
EXEC dbo.sp_PressureDetector @troubleshoot_blocking = 1;

/* 2. Capture the next 60 seconds of blocking (>= 2 s) with plans.
      Prerequisite [CONFIG CHANGE]:
        EXEC sys.sp_configure N'show advanced options', 1; RECONFIGURE;
        EXEC sys.sp_configure N'blocked process threshold', 5; RECONFIGURE;
      Rollback: set 'blocked process threshold' back to 0.                    */
-- EXEC dbo.sp_HumanEvents
--     @event_type           = 'blocking',
--     @blocking_duration_ms = 2000,
--     @seconds_sample       = 60,
--     @database_name        = N'YourDatabase';

/* 3. History from any blocked_process_report session (or system_health) */
EXEC dbo.sp_HumanEventsBlockViewer
    @session_name         = N'system_health',
    @start_date           = DATEADD(DAY, -3, SYSDATETIME()),
    @skip_execution_plans = 1,      /* findings first; rerun with 0 for plans */
    @max_blocking_events  = 2000;

/* Dedicated BPR session written to a file target (see references/procedure-catalog.md) */
-- EXEC dbo.sp_HumanEventsBlockViewer @session_name = N'blocked_process_report', @target_type = N'event_file';

/* BPR XML stored in a table (timestamp column MUST be UTC) */
-- EXEC dbo.sp_HumanEventsBlockViewer
--     @target_type = N'table', @target_database = N'DBA', @target_schema = N'dbo',
--     @target_table = N'blocked_process_report', @target_column = N'event_data',
--     @timestamp_column = N'event_time_utc';

/* 4. Deadlocks and blocking as seen by system_health, last 7 days */
EXEC dbo.sp_HealthParser
    @what_to_check = 'locking',
    @start_date    = DATEADD(DAY, -7, SYSDATETIME()),
    @warnings_only = 0;

/* Deadlock rate context comes from sp_PerfCheck check 5103 (> 9/day Medium, > 50/day High) */
