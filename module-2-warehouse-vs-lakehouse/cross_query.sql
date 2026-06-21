/* =====================================================================
   Module 2 - Cross-item T-SQL (run in wh_retail)
   The punchline: ONE T-SQL surface joining a WAREHOUSE table to a
   LAKEHOUSE table (and even the mirrored SQL DB), all zero-copy in OneLake.
   ===================================================================== */

-- Warehouse fact  x  Lakehouse category dimension  (three-part naming)
SELECT TOP 20
    f.sale_date,
    s.region,
    c.category,
    SUM(f.net_sales) AS net_sales
FROM dbo.fact_sales_daily              AS f          -- warehouse table
JOIN dbo.dim_store                     AS s ON s.store_id = f.store_id
CROSS JOIN lh_retail.gold.sales_by_category AS c     -- lakehouse table
GROUP BY f.sale_date, s.region, c.category
ORDER BY net_sales DESC;
GO

-- You can also reach the mirrored operational data (after Module 3 runs):
-- SELECT TOP 10 * FROM sqldb_orders.dbo.Orders;   -- mirrored Delta, read-only

/* Talking point: no ETL between warehouse and lakehouse to make this join work.
   They are different front doors over the same OneLake storage. */
