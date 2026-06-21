# Module 3 — SQL Database in Fabric + Mirroring

**Story chapter:** *"Operational + analytical — no nightly ETL"*

~15 min · **UI** + **`oltp_seed.sql`** in this folder.

> **Two ways to do this module:**
> - **Code:** `pwsh module-3-sql-database-mirroring/run.ps1` — creates `sqldb_orders` and seeds orders (they mirror to OneLake automatically).
> - **UI follow-along:** the steps below.

---

## Where this fits

| Before | This module | After |
| --- | --- | --- |
| Batch POS data in lakehouse gold | Live **order app** on Fabric SQL DB | Mirrored Delta in OneLake; can be blended with gold in a notebook |

Contoso's e-commerce team runs an **order-management app** against **`sqldb_orders`**. Finance and ops want those orders in the **same analytical estate** as POS sales — without a fragile nightly sync job.

**Mirroring** copies committed OLTP changes to Delta in OneLake within ~**30 seconds**. Mirroring compute is **free**; you pay storage + query compute.

---

## 3.1 Create the operational schema

1. **Create the SQL database** (if it doesn't exist yet): workspace → **+ New item → SQL database** → name **`sqldb_orders`** → **Create**. *(Already exists if you ran `module-3-sql-database-mirroring/run.ps1`.)* Then open it → **New query**.
2. Paste **`oltp_seed.sql`** → run the **schema** section once (`dbo.Orders`, `dbo.OrderItems`).

This is a real OLTP engine — IDENTITY columns, defaults, ACID — i.e. an application database, not a warehouse.

---

## 3.2 Insert orders → watch the mirror (headline)

1. Run the **INSERT** section of `oltp_seed.sql`.
2. Confirm in OLTP: `SELECT TOP 20 * FROM dbo.Orders ORDER BY order_id DESC;`
3. Switch to **SQL analytics endpoint** of the same database (or open the mirrored endpoint item).
4. Same query — rows appear as **Delta in OneLake** within ~30s.

Translytical: the app writes here while analysts query the mirrored copy — one source of truth, no pipeline schedule.

Optional (translytical blend): create a **shortcut** in `lh_retail` → `Files/orders_shortcut` to the mirrored `Orders`, then read it in a notebook and join to `gold.sales_by_store_day` — POS batch + live orders in one Spark session, zero copy.

---

## 3.3 Confirm mirroring status

1. **`sqldb_orders`** → **Replication / Mirroring** (or Monitor replication).
2. Status = **Running**, all tables mirrored.

~30s mirroring SLO with free mirror compute; combined with GraphQL, schema source control, and deployment-pipeline support, it serves as a real application backend.

> **Copilot:** SQL editor completion + NL-to-SQL. Module 9 for agents.

---

## Checklist → Module 4

- [ ] Orders inserted in OLTP
- [ ] Same rows visible on analytics endpoint within ~30s
- [ ] Mirroring = Running

**Next:** [`module-4-direct-lake-powerbi/`](../module-4-direct-lake-powerbi/README.md) — executives consume gold via Direct Lake.
