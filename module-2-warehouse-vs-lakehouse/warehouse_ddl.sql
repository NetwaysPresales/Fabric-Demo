/* =====================================================================
   Module 2 - Fabric Data Warehouse (wh_retail)
   Run this IN the 'wh_retail' warehouse query editor.
   Story: native T-SQL DDL/DML + multi-table ACID, serving the gold layer.
   ===================================================================== */

-- 1) A curated serving table built FROM the lakehouse gold tables via three-part naming.
--    (Within one workspace, the warehouse can read lakehouse tables directly - zero copy.)
DROP TABLE IF EXISTS dbo.dim_store;
CREATE TABLE dbo.dim_store (
    store_id INT NOT NULL,
    store_name VARCHAR(100),
    city VARCHAR(60),
    region VARCHAR(20)
);

INSERT INTO dbo.dim_store (store_id, store_name, city, region)
SELECT DISTINCT store_id, store_name, city, region
FROM lh_retail.gold.sales_by_store_day;   -- cross-item query: warehouse -> lakehouse
GO

-- 2) Native warehouse fact (CTAS) - V-Order is applied automatically in the Warehouse.
DROP TABLE IF EXISTS dbo.fact_sales_daily;
CREATE TABLE dbo.fact_sales_daily AS
SELECT sale_date, store_id, net_sales, units, transactions
FROM lh_retail.gold.sales_by_store_day;
GO

-- 3) A multi-table transaction (something the lakehouse SQL endpoint CANNOT do)
BEGIN TRAN;
    UPDATE dbo.fact_sales_daily SET net_sales = net_sales * 1.00 WHERE region IS NULL;
    INSERT INTO dbo.dim_store (store_id, store_name, city, region)
        VALUES (999, 'Pop-up Kiosk', 'Dubai', 'Central');
COMMIT TRAN;
GO

SELECT TOP 20 * FROM dbo.fact_sales_daily ORDER BY sale_date DESC;

/* Talking points:
   - Warehouse = SQL devs/DBAs: full DDL/DML, stored procs, multi-table ACID, zero-copy clones.
   - Lakehouse SQL endpoint = READ-ONLY (writes happen in Spark).
   - Both read/write the same Delta in OneLake - choice is persona + transaction needs. */
