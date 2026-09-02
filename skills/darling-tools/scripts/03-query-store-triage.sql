/*******************************************************************************
 * Darling Data tools - Query Store triage with sp_QuickieStore
 *
 * Purpose : The four calls that answer most "which query" questions:
 *           high-impact (Pareto), sort by the wait you found, regression
 *           against a baseline window, and parameter-sensitive plan shapes.
 * Targets : Any platform with Query Store enabled in the target database.
 * Safety  : Read-only. Dates are local time; the procedure converts to UTC.
 * Reading : references/interpretation-rules.md, section sp_QuickieStore.
 ******************************************************************************/

DECLARE @db sysname = N'YourDatabase';

/* 1. Who matters? One row per plan, Pareto across cpu/duration/reads/writes/memory/executions */
EXEC dbo.sp_QuickieStore
    @database_name    = @db,
    @find_high_impact = 1,
    @start_date       = DATEADD(DAY, -7, SYSDATETIME()),
    @format_output    = 0;           /* raw numbers so you can compute */

/* 2. Follow the wait. Replace @sort_order with the wait category from
      sp_PressureDetector / sp_PerfCheck:
        cpu pressure      -> 'total cpu' then 'cpu'
        PAGEIOLATCH       -> 'total logical reads'
        RESOURCE_SEMAPHORE-> 'memory' and 'memory waits'
        LCK_M_*           -> 'lock waits'
        WRITELOG          -> 'total log'
        tempdb            -> 'total tempdb'                                  */
EXEC dbo.sp_QuickieStore
    @database_name = @db,
    @sort_order    = 'total cpu',
    @top           = 20,
    @workdays      = 1,              /* business hours only; @work_start/@work_end default 9am-5pm */
    @expert_mode   = 1;              /* context settings, per-plan waits, QS config */

/* 3. Did it get worse? Baseline = known-good week; main window = since the change */
EXEC dbo.sp_QuickieStore
    @database_name                  = @db,
    @sort_order                     = 'cpu',
    @start_date                     = '2026-08-26',
    @end_date                       = '2026-09-02',
    @regression_baseline_start_date = '2026-08-12',
    @regression_baseline_end_date   = '2026-08-19',
    @regression_comparator          = 'absolute',
    @regression_direction           = 'regressed',
    @include_query_hash_totals      = 1;   /* compare the query even if plan_id changed */

/* 4. Same plan, wildly different runtimes: parameter sensitivity candidates */
EXEC dbo.sp_QuickieStore
    @database_name            = @db,
    @find_parameter_sensitive = 1,
    @sort_order               = 'cpu';

/* Drill into one query once you have its ids */
-- EXEC dbo.sp_QuickieStore @database_name = @db, @include_query_ids = '1234', @expert_mode = 1;

/* Timeouts and errors only */
-- EXEC dbo.sp_QuickieStore @database_name = @db, @execution_type_desc = 'failed', @sort_order = 'duration';

/* Every Query-Store-enabled database at once */
-- EXEC dbo.sp_QuickieStore @get_all_databases = 1, @exclude_databases = N'ReportServer,ReportServerTempDB', @find_high_impact = 1;

/* No Query Store? Same Pareto idea against the plan cache */
-- EXEC dbo.sp_QuickieCache @database_name = @db, @impact_threshold = 0.50, @top = 10;
-- EXEC dbo.sp_QuickieCache @find_single_use_plans = 1, @find_duplicate_plans = 1;
