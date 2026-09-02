# Gaps and islands

Input: a sequence column (integer or date) per partition with holes.
**Gaps** = missing ranges. **Islands** = maximal runs of consecutive values.

## Gaps

Each row's value against the next row's value:

```sql
WITH C AS
(
  SELECT seqval, nxt = LEAD(seqval) OVER (ORDER BY seqval)
  FROM dbo.T
)
SELECT gap_start = seqval + 1, gap_end = nxt - 1
FROM C
WHERE nxt - seqval > 1;
```

Dates: `DATEADD(DAY, 1, dt)` / `DATEDIFF(DAY, dt, nxt) > 1`. Index on the
sequence column; plan is one ordered scan.

## Islands, method 1: value minus row number

Consecutive values and consecutive row numbers advance together, so their
difference is constant within an island:

```sql
WITH C AS
(
  SELECT seqval,
         grp = seqval - ROW_NUMBER() OVER (ORDER BY seqval)
  FROM dbo.T
)
SELECT island_start = MIN(seqval), island_end = MAX(seqval)
FROM C
GROUP BY grp
ORDER BY island_start;
```

Dates: `grp = DATEADD(DAY, -ROW_NUMBER() OVER (ORDER BY dt), dt)`.
Per partition: add `PARTITION BY` to the ROW_NUMBER and to the GROUP BY.
Requires **unique** values; with duplicates use `DENSE_RANK` instead of
`ROW_NUMBER`.

## Islands, method 2: LAG plus conditional running sum

Handles duplicates, tolerances ("gap of up to 3 days still counts as the
same island"), and any "start a new group when condition" rule. This is the
general-purpose version; prefer it when the rule is anything but "exactly
consecutive".

```sql
WITH C AS
(
  SELECT userid, ts,
         is_start = CASE WHEN DATEDIFF(MINUTE,
                                LAG(ts) OVER (PARTITION BY userid ORDER BY ts),
                                ts) > 30
                         OR LAG(ts) OVER (PARTITION BY userid ORDER BY ts) IS NULL
                         THEN 1 ELSE 0 END
  FROM dbo.Events
),
G AS
(
  SELECT *, session_id = SUM(is_start) OVER (PARTITION BY userid ORDER BY ts
                                             ROWS UNBOUNDED PRECEDING)
  FROM C
)
SELECT userid, session_id,
       session_start = MIN(ts), session_end = MAX(ts), events = COUNT(*)
FROM G
GROUP BY userid, session_id;
```

Index: `(userid, ts)`. Both windows share the ordering: one scan, no Sort.
This is sessionization; the same shape gives "runs of the same status",
"streaks", "contiguous price bands".

## Islands of equal values (runs)

"Consecutive days where status = 'up'": two row numbers, one overall and
one per status; their difference identifies the run:

```sql
WITH C AS
(
  SELECT dt, status,
         grp = ROW_NUMBER() OVER (ORDER BY dt)
             - ROW_NUMBER() OVER (PARTITION BY status ORDER BY dt)
  FROM dbo.Daily
)
SELECT status, run_start = MIN(dt), run_end = MAX(dt), days = COUNT(*)
FROM C
GROUP BY status, grp
ORDER BY run_start;
```

Needs a dense sequence (no missing dates) or a `DATEDIFF`-based row key;
with holes, use the LAG method with an explicit "new run when status changes
or date not adjacent" flag.

## Islands with a minimum length, longest streak

Filter after grouping: `HAVING COUNT(*) >= 5`, or
`SELECT TOP (1) ... ORDER BY COUNT(*) DESC`.

## Filling gaps (densification)

Join to a numbers or calendar table (see scripts) and use `LEFT JOIN` +
`ISNULL`, or the carry-forward pattern from the window-aggregates reference.

```sql
SELECT D.dt, val = ISNULL(T.val, 0)
FROM dbo.Calendar AS D
LEFT JOIN dbo.T ON T.dt = D.dt
WHERE D.dt BETWEEN @from AND @to;
```

## Traps

- Method 1 breaks silently with duplicate sequence values (two rows get the
  same ROW_NUMBER delta only if values are unique). Check uniqueness or use
  DENSE_RANK.
- Time zones and DST: define islands on UTC or on `date`, not on local
  datetime.
- `DATEDIFF(DAY, ...)` counts midnight crossings, not 24-hour spans; for
  timestamps use `DATEDIFF(SECOND, ...)` or compare `CAST(... AS date)`.
- The `ROWS UNBOUNDED PRECEDING` in method 2 is mandatory; the default RANGE
  frame would merge peers with equal `ts`.
