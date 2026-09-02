# Window aggregates: running, moving, cumulative, offset

## Frames

```
<agg>(expr) OVER (PARTITION BY p ORDER BY o <frame>)
<frame> := ROWS  BETWEEN <start> AND <end>
        |  RANGE BETWEEN <start> AND <end>
<start>/<end> := UNBOUNDED PRECEDING | n PRECEDING | CURRENT ROW | n FOLLOWING | UNBOUNDED FOLLOWING
```

- **No frame written but ORDER BY present** = `RANGE BETWEEN UNBOUNDED
  PRECEDING AND CURRENT ROW`. Two consequences: peers (equal `o`) are
  included as a block, so a "running total" over a date with duplicates jumps
  by the whole day at once; and the engine uses an on-disk worktable
  (Window Spool with `RANGE`) instead of the in-memory fast track. Always
  write `ROWS UNBOUNDED PRECEDING` for a running total.
- `ROWS` with a bounded frame (`ROWS BETWEEN 2 PRECEDING AND CURRENT ROW`)
  over a small window is a cheap in-memory spool; frames up to roughly 10k
  rows stay in memory (the fast-track threshold), beyond that the spool goes
  to a worktable.
- `RANGE` with `n PRECEDING` (value-based frames like "last 30 days") is
  **not supported** in SQL Server; emulate with a self-join / APPLY or a
  running sum of an event stream (see intervals reference).
- `UNBOUNDED FOLLOWING` frames compute "remaining total"; `ROWS BETWEEN
  UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` is the whole partition
  (same as no ORDER BY at all, which is cheaper: use `OVER (PARTITION BY p)`).

## Running total

```sql
SELECT actid, tranid, val,
       balance = SUM(val) OVER (PARTITION BY actid
                                ORDER BY tranid
                                ROWS UNBOUNDED PRECEDING)
FROM dbo.Transactions;
```

Index: `(actid, tranid) INCLUDE (val)`. Plan: Index Scan (ordered), Segment,
Sequence Project, Segment, Window Spool, Stream Aggregate. No Sort, no
worktable I/O.

This replaces every "running balance" cursor and every triangular self-join
(`JOIN T2 ON T2.actid = T1.actid AND T2.tranid <= T1.tranid`), which is
O(n²) per partition.

## Moving average / last N rows

```sql
AVG(val) OVER (PARTITION BY actid ORDER BY tranid
               ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
```

For "last 7 *days*" (value-based) when days have gaps, either densify with
a calendar table (LEFT JOIN calendar, then ROWS frame works) or use APPLY:

```sql
SELECT D.actid, D.dt, D.val,
       avg7 = A.avg7
FROM dbo.Daily AS D
CROSS APPLY
(
  SELECT AVG(1.0 * D2.val) AS avg7
  FROM dbo.Daily AS D2
  WHERE D2.actid = D.actid
    AND D2.dt >  DATEADD(DAY, -7, D.dt)
    AND D2.dt <= D.dt
) AS A;
```

## Percent of total, difference from group aggregate

Window aggregate without ORDER BY is the whole partition; no spool:

```sql
SELECT custid, orderid, val,
       pct_of_cust = 100.0 * val / SUM(val) OVER (PARTITION BY custid),
       pct_of_all  = 100.0 * val / SUM(val) OVER (),
       diff_from_avg = val - AVG(val) OVER (PARTITION BY custid)
FROM Sales.OrderValues;
```

Combining with GROUP BY: window functions run *after* grouping, so
`SUM(SUM(val)) OVER ()` is legal and is the way to get a grand total next to
group totals.

## Offset functions

```sql
LAG(val)         OVER (PARTITION BY actid ORDER BY tranid)             -- previous
LEAD(val, 2, 0)  OVER (PARTITION BY actid ORDER BY tranid)             -- two ahead, default 0
FIRST_VALUE(val) OVER (PARTITION BY actid ORDER BY tranid ROWS UNBOUNDED PRECEDING)
LAST_VALUE(val)  OVER (PARTITION BY actid ORDER BY tranid
                       ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)
```

Rules: `LAG`/`LEAD` take no frame; `FIRST_VALUE`/`LAST_VALUE` do, and
`LAST_VALUE` with the default frame is the current row (the classic bug).
2022+: `IGNORE NULLS` on all four: "carry last non-null forward" without a
gaps-and-islands construction.

Pre-2022 "last non-null" (carry forward):

```sql
WITH C AS
(
  SELECT *, grp = MAX(CASE WHEN val IS NOT NULL THEN tranid END)
                   OVER (PARTITION BY actid ORDER BY tranid ROWS UNBOUNDED PRECEDING)
  FROM T
)
SELECT *, filled = MAX(val) OVER (PARTITION BY actid, grp)
FROM C;
```

## Conditional running sum (state machines in one pass)

Running `SUM(CASE ...)` over an ordered stream is the general tool for
"count how many are open at this point", "flag when cumulative exceeds
budget", "assign session ids". See gaps-and-islands and intervals references.

## Multiple windows in one query

Windows with the same `PARTITION BY` + `ORDER BY` share one Sort/scan.
Different orderings each add a Sort. Order your window functions so the
ones sharing an ordering are adjacent, and index for the most expensive
one. 2022+ `WINDOW` clause names a window once:

```sql
SELECT ..., SUM(val) OVER W, AVG(val) OVER W
FROM T
WINDOW W AS (PARTITION BY actid ORDER BY tranid ROWS UNBOUNDED PRECEDING);
```

## Traps checklist

- Default frame is RANGE: peers and spool. Write ROWS.
- `LAST_VALUE` default frame ends at current row.
- Window functions in SELECT see rows *after* WHERE: a filter on the base
  table changes LAG/LEAD neighbours. If you need neighbours from the
  unfiltered set, compute in a CTE, filter after.
- `COUNT(*) OVER (ORDER BY x)` with RANGE counts peers as a block; use
  `ROW_NUMBER` for a strict running count.
- Aggregates over `DISTINCT` inside a window (`COUNT(DISTINCT x) OVER (...)`)
  are not supported; use `DENSE_RANK` tricks or a pre-aggregated CTE.
