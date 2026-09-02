# Paging

## OFFSET-FETCH (2012+)

```sql
SELECT orderid, orderdate, custid, val
FROM Sales.Orders
ORDER BY orderdate DESC, orderid DESC
OFFSET @pagesize * (@pagenum - 1) ROWS FETCH NEXT @pagesize ROWS ONLY;
```

Index: `(orderdate DESC, orderid DESC) INCLUDE (custid, val)` or, better for
wide rows, a narrow index on the sort keys and let the plan do
`OFFSET`/`TOP` on the narrow index then a Nested Loops lookup for only the
page's rows. The optimizer does this when the covering columns are not in
the index: scan narrow index, Top with offset, then Key Lookup for page rows
only.

Cost is proportional to `offset + pagesize`: page 1,000 reads a million
rows. Fine for the first tens of pages, wrong for deep paging and infinite
scroll.

Deterministic ordering is mandatory: always end `ORDER BY` with the key.
Otherwise pages overlap or skip rows between requests.

## Keyset (seek) paging

Pass the last row of the previous page, not a page number. Constant cost per
page regardless of depth; the standard for APIs and infinite scroll.

```sql
SELECT TOP (@pagesize) orderid, orderdate, custid, val
FROM Sales.Orders
WHERE orderdate < @last_orderdate
   OR (orderdate = @last_orderdate AND orderid < @last_orderid)
ORDER BY orderdate DESC, orderid DESC;
```

Same index. The `OR` predicate on a composite key seeks correctly on 2012+
(two seek ranges merged). Equivalent row-constructor form
`(orderdate, orderid) < (@d, @id)` is **not** supported in T-SQL; write the
OR form. For the first page, pass sentinel maxima or branch the query;
do not use `OPTION (RECOMPILE)` as a substitute for two well-formed queries.

Limitations: you cannot jump to page N, and the sort key must be immutable
for the row (no paging by a value that updates).

## ROW_NUMBER paging (2005-2008)

```sql
WITH C AS
(
  SELECT *, rn = ROW_NUMBER() OVER (ORDER BY orderdate DESC, orderid DESC)
  FROM Sales.Orders
)
SELECT * FROM C
WHERE rn BETWEEN @first AND @last
ORDER BY rn;
```

Same cost profile as OFFSET. Optimizer applies a TOP over the row number
(`rn <= @last`) so it stops early; keep the upper bound in the predicate.

## Total row count with a page

`COUNT(*) OVER ()` in the paged query is convenient but forces the whole
set to be scanned before the TOP; on large tables run the count separately
or cache it. With keyset paging, do not return a total at all.

## Paging with filters and joins

Apply the filter inside the paged set before OFFSET/TOP; then join the page
to the wide tables:

```sql
WITH P AS
(
  SELECT orderid
  FROM Sales.Orders
  WHERE custid = @custid
  ORDER BY orderdate DESC, orderid DESC
  OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY
)
SELECT O.*, C.companyname
FROM P
JOIN Sales.Orders AS O ON O.orderid = P.orderid
JOIN Sales.Customers AS C ON C.custid = O.custid
ORDER BY O.orderdate DESC, O.orderid DESC;
```

Index for the filter + sort: `(custid, orderdate DESC, orderid DESC)`.

## Traps

- `ORDER BY` in a CTE/derived table is only allowed with `TOP`/`OFFSET`, and
  does not guarantee outer order. Repeat the `ORDER BY` in the outer query.
- Page number from the client as `int` overflow: `@pagesize * (@pagenum - 1)`
  in bigint.
- Sort on a non-indexed expression (e.g. `ORDER BY total_value DESC` computed)
  makes every page scan and sort everything; materialize the sort key or
  index a persisted computed column.
- Different `ORDER BY` per user choice = different index per sort; if only
  a few sorts are common, index those and let the rest be slow honestly.
