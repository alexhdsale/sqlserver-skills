# Performance notes for window functions and set-based code

## POC index

Partitioning, Ordering, Covering. Index key = `PARTITION BY` columns, then
`ORDER BY` columns (matching ASC/DESC), `INCLUDE` everything else the query
touches. With a POC index the plan reads in order and skips the Sort;
without it a Sort over the whole input precedes every window, and with
several windows on different orderings there is one Sort each.

Filter columns in `WHERE` that reduce the set before the window go **first**
in the key (they become seek predicates), then P, then O.

## Row mode operators

- **Segment + Sequence Project**: ranking functions; cheap.
- **Segment + Window Spool + Stream Aggregate**: window aggregates. The spool
  is in-memory (fast track) for `ROWS` frames with `UNBOUNDED PRECEDING` and
  for short bounded frames; `RANGE` frames, frames that end after the current
  row, and long frames use an on-disk worktable. `SET STATISTICS IO` shows a
  `Worktable` with reads when the spool went to disk; `ROWS` vs `RANGE` is
  usually the difference between 0 and millions of worktable reads.
- Frame `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` is computed
  incrementally (one pass). `ROWS BETWEEN 100 PRECEDING AND CURRENT ROW`
  re-aggregates the frame per row unless it is small; for large bounded
  frames use two running sums (`SUM(x) OVER (... UNBOUNDED PRECEDING)` minus
  `LAG` of the same sum by 100) which is O(n).

## Batch mode

Batch-mode Window Aggregate (2016+ with a columnstore index present; 2019+
batch mode on rowstore with compat 150 when the optimizer judges the table
large enough) replaces the Window Spool entirely. Typical gain on running
totals and moving aggregates over millions of rows is 5-30x.

**The empty columnstore trick (pre-2019, or when batch mode on rowstore
does not kick in):** add a filtered nonclustered columnstore index that
matches no rows, which unlocks batch mode for the whole plan:

```sql
CREATE NONCLUSTERED COLUMNSTORE INDEX ncci_batchmode
ON dbo.Transactions (actid)
WHERE actid = -1 AND actid = -2;   /* contradiction, zero rows */
```

`[SCHEMA CHANGE]`; rollback `DROP INDEX`. Verify in the plan that the
Window Aggregate operator shows `Actual Execution Mode: Batch`. On 2019+
prefer letting batch mode on rowstore happen; check
`sys.database_scoped_configurations` for `BATCH_MODE_ON_ROWSTORE` and the
compat level.

Batch mode requires a frame of `ROWS UNBOUNDED PRECEDING`-type or
`RANGE`-type running frames; arbitrary bounded frames may fall back to row
mode.

## Parallelism

Window functions parallelize per partition. A query with no `PARTITION BY`
(global running total) is serialized at the window: either accept it, or
partition by a bucket and stitch with a second window over per-bucket
totals. Ranking without partition on a huge table: same story.

## Sort elimination checklist

1. Does the index key order match `PARTITION BY` + `ORDER BY` exactly,
   including direction? (A backward scan can satisfy all-DESC, not mixed.)
2. Are all windows in the query using the same ordering? If not, group the
   query into CTEs so each ordering is materialized once, or accept one
   Sort.
3. Is a `WHERE` predicate on a leading key column turning the scan into a
   seek + ordered range?
4. Is the outer `ORDER BY` the same as the window ordering? If yes, free.

## Cardinality and window functions

The optimizer estimates window function outputs poorly (`rn = 1` filter on a
CTE is estimated at a fixed selectivity). When a downstream join misbehaves,
materialize the windowed result into a temp table with a clustered index and
let statistics do their job. Table variables lack statistics (until 2019's
deferred compilation, and still no histogram); temp tables are the default
for intermediate sets over ~1,000 rows.

## Things that look set-based but are not

- Scalar UDF in SELECT or WHERE: per-row execution, no parallelism
  (pre-2019, and 2019+ only inlines eligible ones). Inline TVF instead.
- Multi-statement TVF joined to a big table: fixed estimate, serial.
- Correlated subquery per row that the optimizer cannot decorrelate
  (aggregate with `TOP`, or referencing outer columns in a `HAVING`): rewrite
  as window or APPLY.
- `SELECT ... INTO #t` inside a loop, or `WHILE` over a `ROW_NUMBER` list.
- `CASE` with a subquery in each branch: each branch executes per row.

## Measuring

`SET STATISTICS IO, TIME ON`, compare *logical reads including Worktable*
and CPU time, not elapsed alone. For two candidate rewrites run each twice
(warm cache), with `DBCC DROPCLEANBUFFERS` only on a test box. Use
`sp_QuickieStore` (darling-tools skill) to confirm the production effect
after deployment with a regression baseline.
