---
name: itzik-tsql-patterns
description: "Set-based T-SQL query patterns in the style of Itzik Ben-Gan: window functions (ranking, offset, aggregate frames, running and moving totals), gaps and islands, top-N-per-group, paging with OFFSET-FETCH and seek-based keyset paging, interval packing and overlap joins, date and number tables, relational division, pivot/unpivot, cursor-to-set-based rewrites, APPLY patterns, batch mode on rowstore trick, and the indexing (POC) rules that make them fast. WHEN: \"rewrite this cursor\", \"running total\", \"gaps and islands\", \"consecutive rows\", \"top 1 per group\", \"latest row per customer\", \"paging\", \"OFFSET FETCH\", \"LAG/LEAD\", \"window function\", \"OVER clause\", \"packing intervals\", \"overlapping dates\", \"numbers table\", \"tally table\", \"calendar table\", \"pivot\", \"relational division\", \"set-based\", \"why is my window function slow\", \"batch mode\", \"Itzik\", \"Ben-Gan\", \"T-SQL Querying\"."
license: MIT
metadata:
  version: "1.0.0"
---

# T-SQL query patterns (Itzik Ben-Gan school)

You write and rewrite T-SQL the way Itzik Ben-Gan teaches it: think in sets,
express the logic declaratively, then make the optimizer's job easy with the
right index and the right window frame. Assume an expert reader who knows
the syntax; what they want is the *right pattern*, its trap, and the index
that makes it a single ordered scan.

Original content written for this repo; the patterns are the well-known ones
from Itzik's books and articles (*T-SQL Querying*, *T-SQL Window Functions*,
*T-SQL Fundamentals*, SQL Server Pro / itziktsql.com). Buy the books.

## How to work

1. **Name the pattern before writing SQL.** Most "hard" T-SQL requests are one
   of: ranking / dedup, running or moving aggregate, gaps, islands, top-N per
   group, paging, interval packing, overlap join, relational division,
   pivot, or a cursor that is really a window function. Say which.
2. **Establish version and compatibility level.** Window aggregates with
   frames need 2012+; `STRING_AGG` 2017+; batch mode on rowstore, `APPROX_*`,
   `WINDOW` clause and `IS DISTINCT FROM` 2022+ (compat 160); `GREATEST` /
   `LEAST`, `DATE_BUCKET`, `GENERATE_SERIES` 2022+. Do not propose a syntax
   the server cannot run; offer the pre-2022 equivalent.
3. **Write the logical-processing-order version first** (FROM, WHERE, GROUP
   BY, HAVING, SELECT, ORDER BY), then hoist window functions into a CTE or
   derived table when you need to filter on them: window functions are
   evaluated in SELECT, so `WHERE rn = 1` needs the CTE.
4. **Choose the frame deliberately.** `ROWS` not `RANGE` for running totals;
   the default frame when you write `ORDER BY` without a frame is
   `RANGE UNBOUNDED PRECEDING`, which uses an on-disk spool and treats peers
   as one group. Say so every time you emit a running aggregate.
5. **State the index.** POC: Partitioning, Ordering, Covering. Key =
   partition columns then order columns; INCLUDE the rest. One index that
   satisfies the window's ordering removes the Sort and lets multiple
   windows share a scan.
6. **Test with the rows that break it:** duplicates in the ordering column,
   NULLs, empty partitions, single-row groups, boundary dates, ties at the
   Nth row, intervals that touch but do not overlap.
7. **Do not chase micro-optimizations before the plan says to.** Hand the
   plan to **sqlserver-query-plans** if the rewrite is not obviously faster;
   hand the index decision to **sqlserver-engineering** if it competes with
   existing indexes.

## Pattern index

| Need | Reference | Key idea |
|---|---|---|
| Ranking, dedup, top-N per group, "latest row" | `references/ranking-and-top-n.md` | `ROW_NUMBER` in CTE; `CROSS APPLY ... TOP (n)` when groups are many and N is small |
| Running / moving / cumulative aggregates, LAG/LEAD, percent of total | `references/window-aggregates.md` | `ROWS UNBOUNDED PRECEDING`; frame choice; avoid RANGE spool |
| Gaps, islands, consecutive sequences, sessionization | `references/gaps-and-islands.md` | `value - ROW_NUMBER()` grouping; `LAG` + conditional running sum for date islands with tolerance |
| Paging, keyset paging, OFFSET-FETCH | `references/paging.md` | seek on `(sort cols, key)`; OFFSET cost grows with page number |
| Intervals: packing, overlap join, allocation | `references/intervals-and-dates.md` | start/end event stream with running sum; date and numbers tables |
| Cursor / loop to set-based, relational division, pivot, string split/agg | `references/set-based-rewrites.md` | conditional aggregation; `EXISTS` vs `IN`; `STRING_AGG`; `APPLY` |
| Batch mode on rowstore, window function performance, `WINDOW` clause | `references/performance-notes.md` | empty columnstore trick pre-2022; sort elimination; parallelism |

Helper objects: `scripts/numbers-table.sql` (on-the-fly and persisted),
`scripts/calendar-table.sql`, `scripts/pattern-cookbook.sql` (runnable
examples of every pattern against a self-contained sample schema).

## Output format for the user

Pattern name in one line, then the query, then the index, then the trap it
avoids and the version floor. When rewriting a cursor, show the original's
semantics as a sentence ("for each account in date order, carry the balance
forward") before the set-based version, so the user can confirm you preserved
them. Non-query DDL (indexes, persisted tables) is `[SCHEMA CHANGE]` with a
rollback per repo conventions.
