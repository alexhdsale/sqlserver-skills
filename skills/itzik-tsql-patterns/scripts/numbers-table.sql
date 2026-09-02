/*******************************************************************************
 * Itzik T-SQL patterns - Numbers (tally) table
 *
 * Purpose : Fast on-the-fly number generator (inline TVF, cross-joined CTEs,
 *           no reads, no recursion) and an optional persisted table for
 *           densification, string splitting, interval explosion, test data.
 * Targets : SQL Server 2008+ (TVF), 2022+ GENERATE_SERIES alternative shown.
 * Safety  : [SCHEMA CHANGE] creates dbo.GetNums and optionally dbo.Nums.
 *           Rollback: DROP FUNCTION dbo.GetNums; DROP TABLE dbo.Nums;
 ******************************************************************************/

/* 1. Inline TVF: GetNums(@low, @high). Up to 4 billion rows via 8 cross joins. */
CREATE OR ALTER FUNCTION dbo.GetNums(@low bigint = 1, @high bigint)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
  WITH
    L0 AS (SELECT 1 AS c FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) AS D(c)),  -- 16
    L1 AS (SELECT 1 AS c FROM L0 AS A CROSS JOIN L0 AS B),   -- 256
    L2 AS (SELECT 1 AS c FROM L1 AS A CROSS JOIN L1 AS B),   -- 65,536
    L3 AS (SELECT 1 AS c FROM L2 AS A CROSS JOIN L2 AS B),   -- 4,294,967,296
    Nums AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rownum FROM L3)
  SELECT TOP (@high - @low + 1)
         rownum,
         n = @low + rownum - 1
  FROM Nums
  ORDER BY rownum;
GO

/* Usage */
-- SELECT n FROM dbo.GetNums(1, 1000000);
-- SELECT DATEADD(DAY, n - 1, '20260101') AS dt FROM dbo.GetNums(1, 365);

/* 2. SQL Server 2022+ built-in equivalent */
-- SELECT value AS n FROM GENERATE_SERIES(1, 1000000);
-- SELECT DATEADD(DAY, value, CAST('20260101' AS date)) FROM GENERATE_SERIES(0, 364);

/* 3. Persisted table when the TVF shows up in a hot plan (join estimate is fixed) */
-- CREATE TABLE dbo.Nums (n int NOT NULL CONSTRAINT PK_Nums PRIMARY KEY CLUSTERED);
-- INSERT dbo.Nums (n) SELECT n FROM dbo.GetNums(1, 1000000);
-- /* Data compression is worth it: */
-- ALTER TABLE dbo.Nums REBUILD WITH (DATA_COMPRESSION = PAGE);
