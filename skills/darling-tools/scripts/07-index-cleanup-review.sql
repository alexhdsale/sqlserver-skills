/*******************************************************************************
 * Darling Data tools - Unused and duplicate index review (sp_IndexCleanup, BETA)
 *
 * Purpose : Produce a review list of duplicate / subset indexes first, then
 *           unused ones, with the guard queries needed before any DROP.
 * Targets : SQL Server 2012+, Azure SQL DB / MI, AWS RDS.
 * Safety  : The procedure is read-only but EMITS DDL. Nothing here executes
 *           that DDL. Any DROP is [SCHEMA CHANGE] and needs: uptime covering a
 *           full business cycle, constraint / hint / replication checks, a
 *           captured CREATE INDEX rollback, and explicit confirmation.
 * Reading : references/interpretation-rules.md, section sp_IndexCleanup.
 ******************************************************************************/

DECLARE @db sysname = N'YourDatabase';

/* 0. Is usage data even meaningful? */
SELECT sqlserver_start_time,
       uptime_days = DATEDIFF(DAY, sqlserver_start_time, SYSDATETIME())
FROM sys.dm_os_sys_info;
/* < 14 days: the procedure warns; < 7 days: it forces @dedupe_only = 1 */

/* 1. Duplicates and key-subset indexes only (safe first pass) */
EXEC dbo.sp_IndexCleanup
    @database_name = @db,
    @dedupe_only   = 1,
    @sort_order    = 'object';

/* 2. Unused candidates, ignoring tiny tables and lightly-read indexes */
EXEC dbo.sp_IndexCleanup
    @database_name = @db,
    @min_rows      = 10000,
    @min_size_gb   = 0.10,
    @min_reads     = 0,
    @min_writes    = 100;      /* only indexes that cost something to maintain */

/* 3. Guard checks for one candidate before you even propose the DROP */
-- DECLARE @schema sysname = N'dbo', @table sysname = N'Orders', @index sysname = N'IX_Orders_Something';
-- SELECT i.name, i.is_unique, i.is_primary_key, i.is_unique_constraint, i.has_filter, i.filter_definition
-- FROM sys.indexes AS i
-- WHERE i.object_id = OBJECT_ID(QUOTENAME(@schema) + N'.' + QUOTENAME(@table)) AND i.name = @index;
-- /* referenced by a hint or plan guide? */
-- SELECT OBJECT_SCHEMA_NAME(m.object_id), OBJECT_NAME(m.object_id)
-- FROM sys.sql_modules AS m WHERE m.definition LIKE N'%' + @index + N'%';
-- SELECT name FROM sys.plan_guides WHERE hints LIKE N'%' + @index + N'%';
-- /* replication article? */
-- SELECT 1 FROM sys.tables AS t WHERE t.object_id = OBJECT_ID(QUOTENAME(@schema) + N'.' + QUOTENAME(@table)) AND (t.is_replicated = 1 OR t.is_published = 1);

/* 4. Prefer disable-then-drop: [SCHEMA CHANGE], rollback = ALTER INDEX ... REBUILD */
-- ALTER INDEX [IX_Orders_Something] ON [dbo].[Orders] DISABLE;
-- -- wait one business cycle --
-- ALTER INDEX [IX_Orders_Something] ON [dbo].[Orders] REBUILD;   /* rollback */
