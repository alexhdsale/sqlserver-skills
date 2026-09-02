/*******************************************************************************
 * Darling Data tools - Inventory installed procedures and versions
 *
 * Purpose : Lists which DarlingData procedures exist in the current database
 *           and returns each one's @version / @version_date so the agent can
 *           tell whether a parameter from the catalog is available.
 * Targets : SQL Server 2016+, Azure SQL DB / MI, AWS RDS. Run in the database
 *           where the procedures were installed (usually master).
 * Safety  : Read-only.
 ******************************************************************************/
SET NOCOUNT ON;

DECLARE @procs TABLE (name sysname PRIMARY KEY);
INSERT @procs (name) VALUES
    (N'sp_PressureDetector'), (N'sp_PerfCheck'), (N'sp_HumanEvents'),
    (N'sp_HumanEventsBlockViewer'), (N'sp_QuickieStore'), (N'sp_QuickieCache'),
    (N'sp_QueryReproBuilder'), (N'sp_HealthParser'), (N'sp_LogHunter'),
    (N'sp_IndexCleanup'), (N'sp_QueryStoreCleanup');

/* Section 1: presence and last modification */
SELECT
    p.name,
    installed      = CASE WHEN o.object_id IS NULL THEN 'NO' ELSE 'yes' END,
    modify_date    = o.modify_date,
    schema_name    = SCHEMA_NAME(o.schema_id)
FROM @procs AS p
LEFT JOIN sys.objects AS o
  ON o.name = p.name
 AND o.type = 'P'
ORDER BY p.name;

/* Section 2: version output for each installed procedure */
DECLARE @name sysname, @sql nvarchar(max),
        @version varchar(30), @version_date datetime;
DECLARE @out TABLE (name sysname, version varchar(30), version_date datetime);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT p.name FROM @procs AS p
    WHERE EXISTS (SELECT 1 FROM sys.objects AS o WHERE o.name = p.name AND o.type = 'P');
OPEN c;
FETCH NEXT FROM c INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'EXEC dbo.' + QUOTENAME(@name)
             + N' @help = 1, @version = @v OUTPUT, @version_date = @d OUTPUT;';
    BEGIN TRY
        /* @help = 1 short-circuits before any collection; result sets are discarded */
        EXEC sys.sp_executesql @sql,
             N'@v varchar(30) OUTPUT, @d datetime OUTPUT',
             @v = @version OUTPUT, @d = @version_date OUTPUT;
        INSERT @out VALUES (@name, @version, @version_date);
    END TRY
    BEGIN CATCH
        INSERT @out VALUES (@name, 'ERROR: ' + LEFT(ERROR_MESSAGE(), 20), NULL);
    END CATCH;
    FETCH NEXT FROM c INTO @name;
END;
CLOSE c; DEALLOCATE c;

SELECT name, version, version_date,
       age_days = DATEDIFF(DAY, version_date, GETDATE())
FROM @out
ORDER BY name;

/* Anything older than ~90 days: re-install from
   https://github.com/erikdarlingdata/DarlingData/raw/main/Install-All/DarlingData.sql */
