# Ranking, deduplication, top-N per group

## The four ranking functions

| Function | Ties | Gaps after ties | Typical use |
|---|---|---|---|
| `ROW_NUMBER()` | arbitrary (add a tiebreaker) | n/a | dedup, paging, "one row per group" |
| `RANK()` | same rank | yes | "top 3 with ties, may return more" |
| `DENSE_RANK()` | same rank | no | "top 3 distinct values" |
| `NTILE(n)` | fills first tiles | n/a | bucketing; uneven when rows % n != 0 |

Always make `ROW_NUMBER` deterministic: `ORDER BY orderdate DESC, orderid DESC`.
A non-deterministic ordering column makes dedup delete different rows on
each run and makes paging skip or repeat rows.

## Top-N per group

**Pattern A: ROW_NUMBER in a CTE.** Best when N is a meaningful fraction of
each group, or groups are few and large. One ordered scan of the supporting
index; filter after.

```sql
WITH C AS
(
  SELECT custid, orderid, orderdate, val,
         rn = ROW_NUMBER() OVER (PARTITION BY custid
                                 ORDER BY orderdate DESC, orderid DESC)
  FROM Sales.Orders
)
SELECT custid, orderid, orderdate, val
FROM C
WHERE rn <= 3;
```

Index: `(custid, orderdate DESC, orderid DESC) INCLUDE (val)`. With it the
plan is Index Scan, Segment, Sequence Project, Filter, no Sort.

**Pattern B: CROSS APPLY with TOP.** Best when there are many groups and N
is tiny, *and* you have a small driving table of group keys (customers) and
the index above. The optimizer does one seek per group; cost is
O(groups × N) instead of scanning all orders.

```sql
SELECT C.custid, A.orderid, A.orderdate, A.val
FROM Sales.Customers AS C
CROSS APPLY
(
  SELECT TOP (3) O.orderid, O.orderdate, O.val
  FROM Sales.Orders AS O
  WHERE O.custid = C.custid
  ORDER BY O.orderdate DESC, O.orderid DESC
) AS A;
```

Use `OUTER APPLY` to keep customers with no orders. Same index.

**Pattern C: TOP with ties / DENSE_RANK** when the business rule is "all
rows that tie for the third-highest value":

```sql
WITH C AS
(
  SELECT *, drk = DENSE_RANK() OVER (PARTITION BY custid ORDER BY val DESC)
  FROM Sales.Orders
)
SELECT * FROM C WHERE drk <= 3;
```

**Rule of thumb** (Itzik's own): density decides. Low density in the
partitioning column (many distinct customers, few orders each): ROW_NUMBER
scan. High density (few customers, huge order counts): APPLY + TOP with
seeks. When in doubt, the ROW_NUMBER version is more predictable; measure.

## "Latest row per key" without the CTE (2022+)

`FIRST_VALUE` / `LAST_VALUE` with an explicit full frame:

```sql
SELECT DISTINCT custid,
       last_orderid = FIRST_VALUE(orderid) OVER (PARTITION BY custid
                          ORDER BY orderdate DESC, orderid DESC
                          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
FROM Sales.Orders;
```

`LAST_VALUE` with the default frame returns the *current* row; always spell
out `ROWS BETWEEN ... AND UNBOUNDED FOLLOWING`. `DISTINCT` here costs a
Sort/Hash; the ROW_NUMBER CTE is usually cheaper. On 2022+ `MAX(...) OVER`
plus `IGNORE NULLS` in `FIRST_VALUE`/`LAST_VALUE`/`LAG`/`LEAD` removes a
class of self-joins ("last non-null price").

## Deduplication

Delete through the CTE; the engine deletes the underlying rows:

```sql
WITH D AS
(
  SELECT *, rn = ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC, id DESC)
  FROM dbo.Contacts
)
DELETE FROM D WHERE rn > 1;   /* [DATA-LOSS RISK] preview with SELECT first, batch if large */
```

For large tables batch it (`DELETE TOP (5000)` in a loop keyed by the CTE
predicate, or stage keys into a temp table) to keep the log and locks small.

## Median and percentiles

`PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY val) OVER (PARTITION BY g)` is
simple but returns the value on every row (add `DISTINCT` or wrap). The
classic two-ROW_NUMBER median is faster on large groups:

```sql
WITH C AS
(
  SELECT g, val,
         rn = ROW_NUMBER() OVER (PARTITION BY g ORDER BY val),
         cnt = COUNT(*)     OVER (PARTITION BY g)
  FROM T
)
SELECT g, median = AVG(1.0 * val)
FROM C
WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
GROUP BY g;
```

## Traps

- Window functions cannot appear in `WHERE`/`HAVING`/`GROUP BY`; they are
  computed in SELECT. Hoist to a CTE.
- `ORDER BY` inside `OVER` on a non-unique column with `ROW_NUMBER` is
  nondeterministic. Add the key.
- `TOP` without `ORDER BY` in APPLY is "any N rows".
- `RANK` for top-N can return far more than N with heavy ties; say which one
  the user asked for.
