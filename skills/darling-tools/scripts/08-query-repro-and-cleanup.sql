/*******************************************************************************
 * Darling Data tools - Build a repro from Query Store; clean Query Store noise
 *
 * Purpose : sp_QueryReproBuilder turns a plan_id / query_id into a runnable
 *           script with the compiled parameter values and SET options.
 *           sp_QueryStoreCleanup reports (and only on confirmation removes)
 *           system / maintenance / duplicate entries.
 * Targets : Any platform with Query Store enabled.
 * Safety  : ReproBuilder is read-only. QueryStoreCleanup with
 *           @report_only = 0 is [DATA-LOSS RISK]: removed history has no
 *           rollback and breaks regression comparisons.
 * Reading : references/interpretation-rules.md.
 ******************************************************************************/

DECLARE @db sysname = N'YourDatabase';

/* 1. Repro for specific plans (click executable_query in SSMS) */
EXEC dbo.sp_QueryReproBuilder
    @database_name    = @db,
    @include_plan_ids = N'12345,67890';

/* Repro for a procedure, last 24 h; include filters intersect */
-- EXEC dbo.sp_QueryReproBuilder @database_name = @db, @procedure_schema = N'dbo',
--     @procedure_name = N'usp_GetOrders', @start_date = DATEADD(DAY, -1, SYSDATETIME());

/* Repro from one plan XML you already have (bypasses Query Store) */
-- DECLARE @plan xml = (SELECT ... );
-- EXEC dbo.sp_QueryReproBuilder @query_plan_xml = @plan;

/* Read the script header: temp table / table variable / parameter embedding /
   parameter count mismatch (local variables) / encrypted module / restricted text
   warnings tell you what the repro cannot reproduce on its own.              */

/* 2. Query Store noise: REPORT first, always */
EXEC dbo.sp_QueryStoreCleanup
    @database_name   = @db,
    @cleanup_targets = 'all',        /* system + maintenance (+ @custom_query_filter) */
    @dedupe_by       = 'all',
    @min_age_days    = 7,
    @report_only     = 1;

/* [DATA-LOSS RISK] only after the report was reviewed and the user confirmed */
-- EXEC dbo.sp_QueryStoreCleanup @database_name = @db, @cleanup_targets = 'all', @dedupe_by = 'all', @min_age_days = 7, @report_only = 0;
