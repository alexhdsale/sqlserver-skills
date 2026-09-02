/*******************************************************************************
 * Darling Data tools - Timed Extended Events samples with sp_HumanEvents
 *
 * Purpose : Short, bounded XE captures for query, wait, compile and recompile
 *           analysis. Starts with the cheapest safe configuration.
 * Targets : SQL Server 2016+. Azure SQL DB / MI: ring_buffer target only.
 * Safety  : [CONFIG CHANGE] creates a temporary event session for
 *           @seconds_sample, then drops it. Plan capture adds overhead:
 *           first pass uses @skip_plans = 1. Never use @gimme_danger = 1 on
 *           production. Do not run without a named server and confirmation.
 * Reading : references/interpretation-rules.md, section sp_HumanEvents.
 ******************************************************************************/

/* 1. What is running? 30-second sample, queries over 100 ms, no plans */
EXEC dbo.sp_HumanEvents
    @event_type        = 'query',
    @query_duration_ms = 100,
    @seconds_sample    = 30,
    @skip_plans        = 1,
    @query_sort_order  = 'cpu';

/* 2. Second pass with plans, narrowed to one database and app */
-- EXEC dbo.sp_HumanEvents
--     @event_type        = 'query',
--     @query_duration_ms = 500,
--     @seconds_sample    = 20,
--     @skip_plans        = 0,
--     @database_name     = N'YourDatabase',
--     @client_app_name   = N'YourApp',
--     @query_sort_order  = 'avg duration';

/* 3. Live wait profile per query/database (cumulative DMVs are polluted by history) */
EXEC dbo.sp_HumanEvents
    @event_type       = 'waits',
    @wait_duration_ms = 10,
    @seconds_sample   = 30;

/* Specific waits only */
-- EXEC dbo.sp_HumanEvents @event_type = 'waits', @wait_type = N'RESOURCE_SEMAPHORE,LCK_M_X,PAGEIOLATCH_SH', @seconds_sample = 30;

/* 4. Compile and recompile storms */
EXEC dbo.sp_HumanEvents @event_type = 'compiles',   @seconds_sample = 20;
EXEC dbo.sp_HumanEvents @event_type = 'recompiles', @seconds_sample = 20;

/* 5. Big memory grants only */
-- EXEC dbo.sp_HumanEvents @event_type = 'query', @requested_memory_mb = 1024, @seconds_sample = 60, @skip_plans = 1;

/* 6. Sample 20% of sessions on a very busy server */
-- EXEC dbo.sp_HumanEvents @event_type = 'query', @session_id = 'sample', @sample_divisor = 5, @seconds_sample = 30, @skip_plans = 1;

/* Permanent session + logging (needs the Agent job from the upstream repo,
   sp_HumanEvents/sp_Human Events Agent Job Example.sql). [CONFIG CHANGE]      */
-- EXEC dbo.sp_HumanEvents
--     @event_type = 'query', @query_duration_ms = 1000, @skip_plans = 1,
--     @keep_alive = 1, @custom_name = N'slow_queries',
--     @output_database_name = N'DBA', @output_schema_name = N'dbo',
--     @delete_retention_days = 7;
/* Rollback for permanent sessions */
-- EXEC dbo.sp_HumanEvents @cleanup = 1, @output_database_name = N'DBA', @output_schema_name = N'dbo';
