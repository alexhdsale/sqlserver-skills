# Set-based rewrites

## Recognize the cursor

| Loop does | Set-based tool |
|---|---|
| carries a value from the previous row | `LAG`, running `SUM ... ROWS UNBOUNDED PRECEDING` |
| counts/sums up to the current row | window aggregate |
| "for each group, take the first/last/top N" | `ROW_NUMBER` CTE or `CROSS APPLY TOP` |
| builds a comma list per group | `STRING_AGG` (2017+) or `FOR XML PATH` |
| looks up the matching row in another table per iteration | `JOIN` / `APPLY` |
| decides based on whether *any* row matches | `EXISTS` |
| decides based on whether *all* rows match | `NOT EXISTS (... WHERE NOT ...)` (relational division) |
| updates a row using values from a related set | `UPDATE ... FROM` with a joined derived table, or `MERGE` for upsert |
| processes batches to limit log growth | keep the loop, but make each iteration a set (`DELETE TOP (n)` keyed) |
| runs DDL / procs per object | genuinely procedural; the cursor is fine (use `LOCAL FAST_FORWARD`) |

Only the last two are legitimate loops. The others have a set-based form
that is one ordered scan.

Process: (1) write the loop's semantics in a sentence; (2) identify the
ordering and partitioning the loop implies; (3) pick the tool; (4) write the
query; (5) diff outputs on a copy with `EXCEPT` in both directions before
replacing.

## Running balance cursor → window

Cursor: "for each account, in transaction order, balance += amount".
Set: `SUM(amount) OVER (PARTITION BY actid ORDER BY tranid ROWS UNBOUNDED PRECEDING)`.
See window-aggregates reference. Beware the "quirky update" (`UPDATE @var =
col = @var + col`): undocumented order guarantees; do not recommend.

## Relational division ("customers who bought all products in set S")

```sql
SELECT C.custid
FROM Sales.Customers AS C
WHERE NOT EXISTS
(
  SELECT P.productid
  FROM dbo.RequiredProducts AS P
  WHERE NOT EXISTS
  (
    SELECT 1 FROM Sales.OrderDetails AS OD
    JOIN Sales.Orders AS O ON O.orderid = OD.orderid
    WHERE O.custid = C.custid AND OD.productid = P.productid
  )
);
```

Counting alternative when S is small and known:
`GROUP BY custid HAVING COUNT(DISTINCT productid) = (SELECT COUNT(*) FROM S)`
after filtering to products in S. Exact division ("all of S and nothing
else") adds a `NOT EXISTS` for products outside S.

## EXISTS vs IN vs JOIN for semi-joins

- `EXISTS` and `IN` (non-nullable subquery column) produce the same plan;
  `NOT IN` with a nullable column returns nothing when any NULL exists, so
  use `NOT EXISTS`.
- `JOIN` + `DISTINCT` to emulate a semi-join adds a sort/hash; use `EXISTS`.
- Anti-join: `NOT EXISTS`, or `LEFT JOIN ... WHERE B.key IS NULL` (same
  plan, choose by readability).

## Conditional aggregation and PIVOT

```sql
SELECT custid,
       q1 = SUM(CASE WHEN DATEPART(QUARTER, orderdate) = 1 THEN val END),
       q2 = SUM(CASE WHEN DATEPART(QUARTER, orderdate) = 2 THEN val END),
       q3 = SUM(CASE WHEN DATEPART(QUARTER, orderdate) = 3 THEN val END),
       q4 = SUM(CASE WHEN DATEPART(QUARTER, orderdate) = 4 THEN val END)
FROM Sales.OrderValues
GROUP BY custid;
```

Prefer this to `PIVOT`: multiple aggregates, no implicit grouping surprises
(PIVOT groups by every column not in the aggregate or spreading list, so
always pivot a derived table with exactly the three columns). Dynamic column
lists require dynamic SQL either way; build it with `STRING_AGG(QUOTENAME(x),
',')` and `sp_executesql`, never by concatenating user input.

`UNPIVOT` drops NULLs; `CROSS APPLY (VALUES ...)` keeps them and is more
flexible:

```sql
SELECT custid, quarter, val
FROM dbo.Wide
CROSS APPLY (VALUES (1, q1), (2, q2), (3, q3), (4, q4)) AS V(quarter, val);
```

## Strings

- Split: `STRING_SPLIT(@list, ',')` (2016+; `enable_ordinal` 2022+ for
  order). For predicates prefer a table-valued parameter over a CSV.
- Aggregate: `STRING_AGG(name, ', ') WITHIN GROUP (ORDER BY name)` (2017+);
  pre-2017 `STUFF((SELECT ',' + name ... FOR XML PATH(''), TYPE).value(...), 1, 1, '')`.
- Large IN lists: load into a temp table with a clustered index and join;
  the parser cost of thousands of literals alone is measurable.

## APPLY as the general tool

`CROSS APPLY` calls a table expression per outer row: top-N per group,
per-row TVF calls, "unpivot with VALUES", reusable computed expressions
(`CROSS APPLY (VALUES (col1 * col2)) AS X(total)` so `total` can be reused
in SELECT/WHERE/ORDER BY without repeating the expression). Inline TVFs
inline into the plan; multi-statement TVFs do not (fixed 100-row estimate
pre-2017, interleaved execution 2017+ helps but still serializes). Scalar
UDFs in predicates kill parallelism pre-2019; 2019+ inlines some.

## Upsert

```sql
MERGE dbo.Target WITH (HOLDLOCK) AS T
USING @rows AS S ON T.key = S.key
WHEN MATCHED AND (T.val <> S.val) THEN UPDATE SET val = S.val
WHEN NOT MATCHED THEN INSERT (key, val) VALUES (S.key, S.val);
```

`HOLDLOCK`/`SERIALIZABLE` is required for correctness under concurrency; or
use the two-statement `UPDATE ... ; INSERT ... WHERE NOT EXISTS` inside a
transaction with `UPDLOCK, HOLDLOCK` on the existence check. MERGE has a
history of bugs; on versions before 2022 CU, prefer the two-statement form
for anything with triggers, filtered indexes or indexed views.

## Batching a large modification (the legitimate loop)

```sql
DECLARE @rc int = 1;
WHILE @rc > 0
BEGIN
  DELETE TOP (5000) FROM dbo.Log WHERE logdate < @cutoff;
  SET @rc = @@ROWCOUNT;
  /* optional: WAITFOR DELAY '00:00:00.2' to yield to the log / AG */
END;
```

Index on the predicate column so each batch is a seek. `[DATA-LOSS RISK]`
label, preview count first.
