# Module 1 — OneLake & the Lakehouse

**Story chapter:** *"Land and refine Contoso's batch sales data"*

~20 min · Mostly **notebooks**, with two **UI** moments (attach lakehouse, create a shortcut).

---

## Where this fits

| Before | This module | After |
| --- | --- | --- |
| Module 0 provisioned `lh_retail` + uploaded CSVs | Medallion pipeline: bronze → silver → gold | Module 2 queries gold from warehouse T-SQL; Module 4 builds Direct Lake on gold |

Contoso's POS systems drop three CSV files every night. We land them in **bronze** (raw), conform them in **silver** (dimensions + facts + V-Order), and publish **gold** KPI tables that the rest of the demo consumes — **without ever copying data out of OneLake**.

---

## Notebooks (run in order)

Each `.ipynb` includes **markdown cells** with story context, step-by-step explanations, presenter notes, and success criteria. Open them in Fabric and read the markdown before running code.

| Order | Notebook | Story beat | Key output |
| --- | --- | --- | --- |
| 1 | `00_setup.ipynb` | Prepare the lakehouse | `bronze`, `silver`, `gold` schemas |
| 2 | `01_bronze_ingest.ipynb` | Land nightly POS export | `bronze.stores/products/sales` |
| 3 | `02_silver_transform.ipynb` | Make data trustworthy | `silver.dim_*`, `silver.fact_sales` + V-Order |
| 4 | `03_gold_aggregate.ipynb` | Publish data products | `gold.sales_by_store_day`, `gold.sales_by_category` |
| 5 | `04_vorder_demo.ipynb` | Prove V-Order | Size/time comparison in `demo` schema |
| 6 | `05_shortcuts.ipynb` | Federate without copying | Shortcut under `Files/` (UI preferred on stage) |
| 7 | `06_cross_engine_reads.ipynb` | Capstone: one copy, many engines | `gold.sales_by_region` for Module 2 |

Imported by `pwsh module-0-setup/setup.ps1 -Action notebooks`. Every notebook starts with `%run 00_setup`.

---

## 1.1 Attach the lakehouse (UI — do this first)

1. Open workspace **`Fabric-Demo-Workshop`** → notebook **`00_setup`**.
2. Explorer → **Lakehouses** → **+ Add** → **Existing lakehouse** → **`lh_retail`** → **Add** (must show **pinned** as default).
3. Run all cells in `00_setup`. Expect schemas created + three CSVs listed under `Files/bronze/`.

> Empty `Files/bronze`? Run `pwsh module-0-setup/setup.ps1 -Action data` or upload `stores.csv`, `products.csv`, `sales.csv` from `module-0-setup/data/`.

**Say:** *"OneLake is OneDrive for data. The lakehouse is our Spark workspace on top of it — Tables and Files, one storage account."*

---

## 1.2 Bronze → Silver → Gold (notebooks)

Run **`01`** through **`03`** in order. Read the markdown in each notebook as you go.

| Step | What happens | What to show the room |
| --- | --- | --- |
| **01 Bronze** | CSV → Delta tables | Tables appear in Explorer — no separate import step |
| **02 Silver** | Clean, join, V-Order fact | Business rules (filter bad qty, compute net sales) |
| **03 Gold** | Aggregates for BI | Category ranking — feeds Module 4 report |

**Say:** *"Same files, no movement. Bronze = audit trail, silver = trusted model, gold = what we share with the business."*

> **Copilot:** Notebook Copilot pane → *"Explain this notebook"* or *"Write PySpark to dedupe fact_sales"*. Full agent tour in Module 8.

---

## 1.3 V-Order demo (notebook `04`)

Run **`04_vorder_demo`**. Compares file size and query time with V-Order on vs off.

**Say:** *"V-Order is a write-time layout tax that pays back on every Power BI and warehouse read. Warehouse gets it free; Spark opts in."*

---

## 1.4 Shortcuts — zero-copy federation (UI headline)

**UI (recommended on stage):**
1. `lh_retail` → **Files** → **New shortcut**.
2. Source: **Microsoft OneLake** (easiest) or **ADLS / S3 / GCS** (needs connection).
3. Finish — data appears under `Files/` with **no bytes copied**.

**Say:** *"Post-merger, multi-cloud, ministry sharing — don't migrate, point at it."*

**Code (optional):** `05_shortcuts` — REST API path; may fail on self-referential targets; UI is more reliable live.

---

## 1.5 Capstone (notebook `06`)

Run **`06_cross_engine_reads`** — Spark reads gold, optionally blends mirrored orders (after Module 3), writes **`gold.sales_by_region`** for the warehouse.

**Say:** *"One set of Delta files — Spark, SQL, Power BI, mirroring — zero copy."*

---

## Checklist before Module 2

- [ ] `bronze`, `silver`, `gold` tables visible in `lh_retail`
- [ ] V-Order comparison shown (`04`)
- [ ] A shortcut under `Files/` (`05` or UI)
- [ ] `gold.sales_by_region` exists (`06`)

**Next:** [`module-2-warehouse-vs-lakehouse/`](../module-2-warehouse-vs-lakehouse/README.md) — SQL devs meet the same data in `wh_retail`.
