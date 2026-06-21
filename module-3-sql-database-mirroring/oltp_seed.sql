/* =====================================================================
   Module 3 - SQL Database in Fabric (sqldb_orders)
   Run this IN the 'sqldb_orders' SQL database query editor.
   Story: operational OLTP writes that auto-mirror to OneLake as Delta.
   ===================================================================== */

-- 1) Operational schema (run once)
IF OBJECT_ID('dbo.Orders') IS NULL
CREATE TABLE dbo.Orders (
    order_id      INT IDENTITY(1,1) PRIMARY KEY,
    store_id      INT          NOT NULL,
    customer_name NVARCHAR(100) NOT NULL,
    order_ts      DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    status        VARCHAR(20)   NOT NULL DEFAULT 'NEW',
    order_total   DECIMAL(12,2) NOT NULL
);
GO

IF OBJECT_ID('dbo.OrderItems') IS NULL
CREATE TABLE dbo.OrderItems (
    order_item_id INT IDENTITY(1,1) PRIMARY KEY,
    order_id      INT NOT NULL,
    product_id    INT NOT NULL,
    quantity      INT NOT NULL,
    line_amount   DECIMAL(12,2) NOT NULL
);
GO

-- 2) LIVE during the demo: insert a few operational orders, then switch to the
--    SQL analytics endpoint / OneLake and show these rows mirrored within ~30s.
INSERT INTO dbo.Orders (store_id, customer_name, status, order_total) VALUES
 (1, N'Aisha K.',   'NEW',     349.90),
 (3, N'Omar R.',    'PAID',    1299.00),
 (7, N'Lina M.',    'PAID',     59.50),
 (2, N'Yousef A.',  'SHIPPED', 875.25),
 (5, N'Maryam S.',  'NEW',     220.00);
GO

INSERT INTO dbo.OrderItems (order_id, product_id, quantity, line_amount) VALUES
 (1, 14, 2, 349.90),
 (2, 88, 1, 1299.00),
 (3, 5,  3, 59.50),
 (4, 102, 2, 875.25),
 (5, 47, 1, 220.00);
GO

-- 3) Show current operational state (transactional engine)
SELECT TOP 20 * FROM dbo.Orders ORDER BY order_id DESC;

/* Talking points:
   - This is a real OLTP engine (ACID, IDENTITY, defaults) optimized for app writes.
   - A background process mirrors these tables to OneLake as open Delta/Parquet (~30s SLO).
   - Mirroring compute is FREE - you pay only OneLake storage + analytical query compute.
   - Downstream analysts get a read-only SQL analytics endpoint over the mirrored Delta. */
