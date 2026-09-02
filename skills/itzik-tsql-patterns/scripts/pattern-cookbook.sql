/*******************************************************************************
 * Itzik T-SQL patterns - Runnable cookbook
 *
 * Purpose : Self-contained sample schema in tempdb plus one runnable example
 *           of each pattern from references/. Use to verify a rewrite's
 *           semantics before applying it to real tables.
 * Targets : SQL Server 2012+ unless a section says otherwise.
 * Safety  : Creates and drops tables in tempdb only.
 ******************************************************************************/
USE tempdb;
SET NOCOUNT ON;

DROP TABLE IF EXISTS #Transactions, #Events, #Sessions, #Orders;

CREATE TABLE #Transactions (actid int NOT NULL, tranid int NOT NULL, val money NOT NULL,
                            PRIMARY KEY (actid, tranid));
INSERT #Transactions VALUES
 (1,1,4.00),(1,2,-2.00),(1,3,5.00),(1,4,2.00),(1,5,1.00),(1,6,3.00),(1,7,-4.00),
 (2,1,2.00),(2,2,1.00),(2,3,5.00),(2,4,1.00),(2,5,-5.00),(2,6,4.00),
 (3,1,-3.00),(3,2,3.00),(3,3,-2.00),(3,4,1.00),(3,5,4.00);

CREATE TABLE #Events (userid int NOT NULL, ts datetime2(0) NOT NULL, PRIMARY KEY (userid, ts));
INSERT #Events VALUES
 (1,'20260901 08:00'),(1,'20260901 08:10'),(1,'20260901 08:25'),(1,'20260901 10:00'),(1,'20260901 10:05'),
 (2,'20260901 09:00'),(2,'20260901 09:45'),(2,'20260901 09:50');

CREATE TABLE #Sessions (userid int NOT NULL, startdt datetime2(0) NOT NULL, enddt datetime2(0) NOT NULL);
INSERT #Sessions VALUES
 (1,'20260901 08:00','20260901 09:00'),(1,'20260901 08:30','20260901 10:00'),
 (1,'20260901 10:00','20260901 11:00'),(1,'20260901 12:00','20260901 13:00'),
 (2,'20260901 09:00','20260901 09:30'),(2,'20260901 09:45','20260901 10:15');

CREATE TABLE #Orders (orderid int NOT NULL PRIMARY KEY, custid int NOT NULL, orderdate date NOT NULL, val money NOT NULL);
INSERT #Orders VALUES
 (1,1,'20260801',100),(2,1,'20260803',250),(3,1,'20260803',80),(4,1,'20260810',40),
 (5,2,'20260802',500),(6,2,'20260815',75),(7,3,'20260805',10);
CREATE INDEX IX_Orders_POC ON #Orders (custid, orderdate DESC, orderid DESC) INCLUDE (val);

/*──── 1. Running total: ROWS, not RANGE ─────────────────────────────────────*/
SELECT actid, tranid, val,
       balance_rows  = SUM(val) OVER (PARTITION BY actid ORDER BY tranid ROWS UNBOUNDED PRECEDING),
       balance_range = SUM(val) OVER (PARTITION BY actid ORDER BY tranid)  -- default RANGE; same here because tranid unique, slower plan
FROM #Transactions
ORDER BY actid, tranid;

/*──── 2. Top-N per group, both shapes ───────────────────────────────────────*/
WITH C AS
(
  SELECT custid, orderid, orderdate, val,
         rn = ROW_NUMBER() OVER (PARTITION BY custid ORDER BY orderdate DESC, orderid DESC)
  FROM #Orders
)
SELECT * FROM C WHERE rn <= 2 ORDER BY custid, rn;

SELECT C.custid, A.orderid, A.orderdate, A.val
FROM (SELECT DISTINCT custid FROM #Orders) AS C
CROSS APPLY (SELECT TOP (2) orderid, orderdate, val
             FROM #Orders AS O WHERE O.custid = C.custid
             ORDER BY orderdate DESC, orderid DESC) AS A
ORDER BY C.custid, A.orderdate DESC, A.orderid DESC;

/*──── 3. Gaps (missing tranids) ─────────────────────────────────────────────*/
DELETE FROM #Transactions WHERE actid = 1 AND tranid IN (3, 4);
WITH C AS (SELECT actid, tranid, nxt = LEAD(tranid) OVER (PARTITION BY actid ORDER BY tranid) FROM #Transactions)
SELECT actid, gap_start = tranid + 1, gap_end = nxt - 1 FROM C WHERE nxt - tranid > 1;

/*──── 4. Islands (value minus row number) ───────────────────────────────────*/
WITH C AS (SELECT actid, tranid, grp = tranid - ROW_NUMBER() OVER (PARTITION BY actid ORDER BY tranid) FROM #Transactions)
SELECT actid, island_start = MIN(tranid), island_end = MAX(tranid) FROM C GROUP BY actid, grp ORDER BY actid, island_start;

/*──── 5. Sessionization: new session after 30 min idle (LAG + running sum) ──*/
WITH C AS
(
  SELECT userid, ts,
         is_start = CASE WHEN DATEDIFF(MINUTE, LAG(ts) OVER (PARTITION BY userid ORDER BY ts), ts) > 30
                           OR LAG(ts) OVER (PARTITION BY userid ORDER BY ts) IS NULL THEN 1 ELSE 0 END
  FROM #Events
),
G AS (SELECT *, session_id = SUM(is_start) OVER (PARTITION BY userid ORDER BY ts ROWS UNBOUNDED PRECEDING) FROM C)
SELECT userid, session_id, session_start = MIN(ts), session_end = MAX(ts), events = COUNT(*)
FROM G GROUP BY userid, session_id ORDER BY userid, session_id;
/* expected: user 1 -> two sessions (08:00-08:25, 10:00-10:05); user 2 -> two (09:00, 09:45-09:50) */

/*──── 6. Packing intervals (touching intervals merge with >=) ───────────────*/
WITH C AS
(
  SELECT *, prev_max_end = MAX(enddt) OVER (PARTITION BY userid ORDER BY startdt, enddt
                                            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
  FROM #Sessions
),
G AS
(
  SELECT *, grp = SUM(CASE WHEN prev_max_end IS NULL OR startdt > prev_max_end THEN 1 ELSE 0 END)
                  OVER (PARTITION BY userid ORDER BY startdt, enddt ROWS UNBOUNDED PRECEDING)
  FROM C
)
SELECT userid, packed_start = MIN(startdt), packed_end = MAX(enddt)
FROM G GROUP BY userid, grp ORDER BY userid, packed_start;
/* expected: user 1 -> 08:00-11:00 (three merge, 10:00 touches) and 12:00-13:00; user 2 -> two */

/*──── 7. Max concurrent sessions (event stream) ─────────────────────────────*/
WITH E AS
(
  SELECT userid, ts = startdt, delta = +1 FROM #Sessions
  UNION ALL
  SELECT userid, ts = enddt,   delta = -1 FROM #Sessions
),
R AS (SELECT userid, ts, open_cnt = SUM(delta) OVER (PARTITION BY userid ORDER BY ts, delta ROWS UNBOUNDED PRECEDING) FROM E)
SELECT userid, max_concurrent = MAX(open_cnt) FROM R GROUP BY userid;

/*──── 8. Keyset paging ──────────────────────────────────────────────────────*/
DECLARE @last_orderdate date = '20260803', @last_orderid int = 3, @pagesize int = 2;
SELECT TOP (@pagesize) orderid, custid, orderdate, val
FROM #Orders
WHERE orderdate < @last_orderdate OR (orderdate = @last_orderdate AND orderid < @last_orderid)
ORDER BY orderdate DESC, orderid DESC;

/*──── 9. Carry last non-null forward (pre-2022 form) ────────────────────────*/
;WITH S AS
(
  SELECT * FROM (VALUES (1, NULL), (2, 10), (3, NULL), (4, NULL), (5, 20), (6, NULL)) AS V(id, price)
),
C AS
(
  SELECT *, grp = MAX(CASE WHEN price IS NOT NULL THEN id END) OVER (ORDER BY id ROWS UNBOUNDED PRECEDING)
  FROM S
)
SELECT id, price, filled = MAX(price) OVER (PARTITION BY grp) FROM C ORDER BY id;
/* 2022+: SELECT id, price, LAST_VALUE(price) IGNORE NULLS OVER (ORDER BY id ROWS UNBOUNDED PRECEDING) FROM S */

/*──── 10. Relational division: customers with orders on BOTH 2026-08-03 and 2026-08-10 ─*/
WITH Req AS (SELECT d FROM (VALUES (CAST('20260803' AS date)), ('20260810')) AS V(d))
SELECT DISTINCT O.custid
FROM #Orders AS O
WHERE NOT EXISTS (SELECT 1 FROM Req AS R
                  WHERE NOT EXISTS (SELECT 1 FROM #Orders AS O2 WHERE O2.custid = O.custid AND O2.orderdate = R.d));

/*──── 11. Median via two ROW_NUMBERs ────────────────────────────────────────*/
WITH C AS
(
  SELECT actid, val,
         rn  = ROW_NUMBER() OVER (PARTITION BY actid ORDER BY val),
         cnt = COUNT(*) OVER (PARTITION BY actid)
  FROM #Transactions
)
SELECT actid, median = AVG(1.0 * val) FROM C WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2) GROUP BY actid;

DROP TABLE IF EXISTS #Transactions, #Events, #Sessions, #Orders;
