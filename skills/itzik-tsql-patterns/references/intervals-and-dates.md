# Intervals, overlaps, packing, and date handling

Convention: half-open intervals `[start, end)`. Two intervals overlap when
`a.start < b.end AND b.start < a.end`. Closed intervals (`<=`) make "touching"
intervals overlap; decide once and state it.

## Overlap join

```sql
SELECT A.id, B.id
FROM dbo.Intervals AS A
JOIN dbo.Intervals AS B
  ON  A.id < B.id
  AND A.startdt < B.enddt
  AND B.startdt < A.enddt;
```

The optimizer can only seek on one side of the range. Index `(startdt, enddt)`
gives a seek on `B.startdt < A.enddt` and a residual on the other predicate;
for long tables with short intervals, add a bound on how long an interval
can be (`B.startdt > DATEADD(DAY, -@maxlen, A.startdt)`) so the seek range
is narrow. This is the "interval length bound" trick; without it every row
scans half the table.

## Packing intervals (merge overlapping/adjacent into maximal ranges)

Event-stream method: turn each interval into a +1 at start and a −1 at end,
running sum tells how many intervals are open; where it drops to 0 an
island ends.

```sql
WITH E AS
(
  SELECT userid, ts = startdt, delta = +1 FROM dbo.Sessions
  UNION ALL
  SELECT userid, ts = enddt,   delta = -1 FROM dbo.Sessions
),
R AS
(
  SELECT userid, ts, delta,
         open_cnt = SUM(delta) OVER (PARTITION BY userid ORDER BY ts, delta
                                     ROWS UNBOUNDED PRECEDING)
  FROM E
),
S AS
(
  SELECT userid, ts,
         is_start = CASE WHEN delta = 1 AND open_cnt = 1 THEN 1 ELSE 0 END,
         is_end   = CASE WHEN delta = -1 AND open_cnt = 0 THEN 1 ELSE 0 END
  FROM R
  WHERE (delta = 1 AND open_cnt = 1) OR (delta = -1 AND open_cnt = 0)
),
G AS
(
  SELECT userid, ts, is_start,
         grp = (ROW_NUMBER() OVER (PARTITION BY userid ORDER BY ts) - 1) / 2
  FROM S
)
SELECT userid, packed_start = MIN(ts), packed_end = MAX(ts)
FROM G
GROUP BY userid, grp;
```

`ORDER BY ts, delta` inside the sum sorts an end (−1) before a start (+1)
at the same timestamp: touching intervals `[1,3)` and `[3,5)` do **not**
merge. Swap to `ORDER BY ts, delta DESC` if adjacent should merge. Index
`(userid, startdt, enddt)` plus one on `(userid, enddt)`; the UNION ALL
reads each once.

Simpler alternative when intervals are few per partition: `MAX(enddt) OVER
(... ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)` compared to the
current start flags a new island; then the conditional running-sum island
pattern. Same result, one scan, fewer CTEs:

```sql
WITH C AS
(
  SELECT *, prev_max_end = MAX(enddt) OVER (PARTITION BY userid ORDER BY startdt, enddt
                                            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
  FROM dbo.Sessions
),
G AS
(
  SELECT *, grp = SUM(CASE WHEN startdt > prev_max_end OR prev_max_end IS NULL THEN 1 ELSE 0 END)
                  OVER (PARTITION BY userid ORDER BY startdt, enddt ROWS UNBOUNDED PRECEDING)
  FROM C
)
SELECT userid, MIN(startdt), MAX(enddt) FROM G GROUP BY userid, grp;
```

Use `>=` for "touching merges".

## Max concurrent intervals

Same event stream; `MAX(open_cnt)` per partition, or the timestamp where it
peaks. Beats the correlated `COUNT(*)` subquery per start point by orders of
magnitude.

## Allocation / proration by day

Explode intervals to days with a calendar (or numbers) table, then aggregate:

```sql
SELECT C.dt, SUM(S.rate) AS revenue
FROM dbo.Subscriptions AS S
JOIN dbo.Calendar AS C
  ON C.dt >= S.startdt AND C.dt < S.enddt
GROUP BY C.dt;
```

Prefer this over `DATEDIFF`-based arithmetic when rules per day matter
(weekends, holidays flagged in the calendar).

## Point-in-time lookups (SCD type 2, price history)

"Price valid on date d": `WHERE d >= valid_from AND d < valid_to` with index
`(productid, valid_from, valid_to)`. When `valid_to` is nullable for the
current row, store a sentinel (`9999-12-31`) instead of NULL so the seek
works and the predicate stays simple. Or use `APPLY TOP (1) ... WHERE
valid_from <= d ORDER BY valid_from DESC`, which needs only `(productid,
valid_from DESC)`.

## Dates and times

- Store `date` when you mean a day; `datetime2(0..3)` when you mean an
  instant; `datetimeoffset` only when the offset is data. Never `datetime`
  for new work (3.33 ms rounding).
- Range predicates, not functions on the column:
  `WHERE dt >= @d AND dt < DATEADD(DAY, 1, @d)`, never
  `WHERE CAST(dt AS date) = @d` (2008+ can still seek on the CAST form for
  `date`, but it is the only exception; do not rely on it for other
  functions).
- Language-neutral literals: `'20260902'` or `'2026-09-02T00:00:00'`.
  `'2026-09-02'` is ambiguous under `SET DATEFORMAT dmy` for `datetime`.
- `DATEDIFF` counts boundary crossings. `DATEDIFF(YEAR, '20251231',
  '20260101') = 1`. Age: `DATEDIFF(YEAR, dob, today) - CASE WHEN
  DATEADD(YEAR, DATEDIFF(YEAR, dob, today), dob) > today THEN 1 ELSE 0 END`.
- Beginning of period: `DATEADD(MONTH, DATEDIFF(MONTH, 0, dt), 0)`; 2022+
  `DATETRUNC(MONTH, dt)` and `DATE_BUCKET(WEEK, 1, dt, @anchor)` for custom
  week starts.
- `EOMONTH(dt)` for month end; `DATEFROMPARTS` for construction;
  `AT TIME ZONE` for conversions (returns `datetimeoffset`; cast back).
- Week numbers depend on `DATEFIRST`; use `ISO_WEEK` datepart or a calendar
  table column for reports.
