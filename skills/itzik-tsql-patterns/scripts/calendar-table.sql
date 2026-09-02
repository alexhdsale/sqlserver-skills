/*******************************************************************************
 * Itzik T-SQL patterns - Calendar table
 *
 * Purpose : Persisted date dimension for densification, business-day math,
 *           week/quarter reporting, and interval-to-day allocation.
 * Targets : SQL Server 2012+ (uses dbo.GetNums from numbers-table.sql or
 *           GENERATE_SERIES on 2022+).
 * Safety  : [SCHEMA CHANGE] creates dbo.Calendar. Rollback: DROP TABLE dbo.Calendar;
 *           Populate holidays from your own list; the column is left NULL/0.
 ******************************************************************************/

CREATE TABLE dbo.Calendar
(
    dt              date        NOT NULL CONSTRAINT PK_Calendar PRIMARY KEY CLUSTERED,
    year            smallint    NOT NULL,
    quarter         tinyint     NOT NULL,
    month           tinyint     NOT NULL,
    day             tinyint     NOT NULL,
    day_of_week     tinyint     NOT NULL,   -- 1 = Monday ... 7 = Sunday, independent of DATEFIRST
    iso_week        tinyint     NOT NULL,
    iso_year        smallint    NOT NULL,
    month_start     date        NOT NULL,
    month_end       date        NOT NULL,
    is_weekend      bit         NOT NULL,
    is_holiday      bit         NOT NULL CONSTRAINT DF_Calendar_holiday DEFAULT (0),
    is_business_day AS CONVERT(bit, CASE WHEN is_weekend = 0 AND is_holiday = 0 THEN 1 ELSE 0 END) PERSISTED,
    business_day_seq int        NULL        -- running count of business days, filled below
);

DECLARE @from date = '20100101', @to date = '20401231';

INSERT dbo.Calendar (dt, year, quarter, month, day, day_of_week, iso_week, iso_year,
                     month_start, month_end, is_weekend)
SELECT
    dt,
    YEAR(dt), DATEPART(QUARTER, dt), MONTH(dt), DAY(dt),
    day_of_week = (DATEPART(WEEKDAY, dt) + @@DATEFIRST - 2) % 7 + 1,
    iso_week    = DATEPART(ISO_WEEK, dt),
    iso_year    = CASE WHEN DATEPART(ISO_WEEK, dt) >= 52 AND MONTH(dt) = 1 THEN YEAR(dt) - 1
                       WHEN DATEPART(ISO_WEEK, dt) = 1  AND MONTH(dt) = 12 THEN YEAR(dt) + 1
                       ELSE YEAR(dt) END,
    month_start = DATEFROMPARTS(YEAR(dt), MONTH(dt), 1),
    month_end   = EOMONTH(dt),
    is_weekend  = CASE WHEN (DATEPART(WEEKDAY, dt) + @@DATEFIRST - 2) % 7 + 1 IN (6, 7) THEN 1 ELSE 0 END
FROM (SELECT DATEADD(DAY, n - 1, @from) AS dt
      FROM dbo.GetNums(1, DATEDIFF(DAY, @from, @to) + 1)) AS D;

/* Mark holidays here, e.g.: UPDATE dbo.Calendar SET is_holiday = 1 WHERE dt IN ('20260101', ...); */

/* Business-day sequence: "add 5 business days" becomes a seek on this column */
;WITH C AS
(
  SELECT dt, business_day_seq,
         seq = SUM(CASE WHEN is_business_day = 1 THEN 1 ELSE 0 END)
               OVER (ORDER BY dt ROWS UNBOUNDED PRECEDING)
  FROM dbo.Calendar
)
UPDATE C SET business_day_seq = seq;

CREATE UNIQUE INDEX UX_Calendar_bizseq ON dbo.Calendar (business_day_seq, dt);

/* Usage:
   -- business days between two dates
   SELECT b.business_day_seq - a.business_day_seq
   FROM dbo.Calendar AS a JOIN dbo.Calendar AS b ON b.dt = @d2 WHERE a.dt = @d1;
   -- date 5 business days after @d
   SELECT MIN(dt) FROM dbo.Calendar
   WHERE is_business_day = 1
     AND business_day_seq = (SELECT business_day_seq FROM dbo.Calendar WHERE dt = @d) + 5;
*/
