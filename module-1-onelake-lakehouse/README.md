# Module 1 — OneLake & the Lakehouse

**Story chapter:** *"Land and refine Contoso's batch sales data"*

~20 min · Mostly **notebooks**, with two **UI** moments (attach lakehouse, create a shortcut).

> **Two ways to do this module:**
> - **Code:** `pwsh module-1-onelake-lakehouse/run.ps1` — creates the lakehouse, uploads CSVs + notebooks, runs `00`–`06` (end result: bronze/silver/gold tables).
> - **UI follow-along:** the steps below (build the Copy job + Task flow, then run the notebooks yourself).
> Prereq either way: `pwsh module-0-setup/setup.ps1 -Action infra`.

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
| 1 | `00_config.ipynb` | Prepare the lakehouse | `bronze`, `silver`, `gold` schemas |
| 2 | `01_bronze_ingest.ipynb` | Land nightly POS export | `bronze.stores/products/sales` |
| 3 | `02_silver_transform.ipynb` | Make data trustworthy | `silver.dim_*`, `silver.fact_sales` + V-Order |
| 4 | `03_gold_aggregate.ipynb` | Publish data products | `gold.sales_by_store_day`, `gold.sales_by_category` |
| 5 | `04_vorder_demo.ipynb` | Prove V-Order | Size/time comparison in `demo` schema |
| 6 | `05_shortcuts.ipynb` | Federate without copying | Shortcut under `Files/` (UI preferred on stage) |
| 7 | `06_cross_engine_reads.ipynb` | Capstone: one copy, many engines | `gold.sales_by_region` for Module 2 |

Uploaded by `pwsh module-1-onelake-lakehouse/run.ps1` (or import manually). Every notebook starts with `%run 00_config`.

---

## 1.0 Ingest raw files from Blob with a Copy job + a Task flow (UI — the headline)

Contoso's nightly CSVs land in **Azure Blob Storage** (`ntwfabricdemostg/retail-raw/bronze/`), created by `pwsh module-0-setup/setup.ps1 -Action storage`. Instead of magically having data in the lakehouse, we **ingest it live** and wrap it in a **Task flow** so the workspace shows an end-to-end map.

### 1.0a — Build the Task flow (the visual map)

1. In `Fabric-Demo-Workshop`, top of the item list → **Tasks** / **+ Task flow** (or **Set up a task flow**).
2. Pick a blank flow (or the "Data ingestion and orchestration" template).
3. Add tasks (boxes) and name them to match our story:
   - **Get data** → **Store** → **Prepare/Transform** → **Serve**
4. You'll attach real items to each task as you create them — this is the canvas we keep filling in.

**Say:** *"A Task flow is the workspace's blueprint — Get data, Store, Transform, Serve. It documents and links the items, so a newcomer sees the whole pipeline at a glance."*

### 1.0b — Connection to the blob (once)

1. **Settings (gear) → Manage connections and gateways → New → Cloud**.
2. **Connection type:** *Azure Blob Storage*. **Account:** `ntwfabricdemostg`.
3. **Authentication:** *Account key* (or *Workspace identity* if Trusted Access is set up — Module 7). **Create**.

> Scripted shortcut: `pwsh module-0-setup/setup.ps1 -Action connection` (best-effort; falls back to this UI path).

### 1.0c — Copy job: Blob → `lh_retail` `Files/bronze`

1. Workspace → **+ New item → Copy job** → name it **`cj_blob_to_bronze`**.
2. **Source:** *Azure Blob Storage* → your connection → container `retail-raw`, folder `bronze/` → select the 3 CSVs.
3. **Destination:** **Lakehouse** `lh_retail` → **Files** → folder `bronze` (so files land exactly where the notebooks read).
4. **Mode:** *Copy* (full). **Save**, then **Run**.
5. Watch the run succeed; open `lh_retail → Files/bronze` → the 3 CSVs are now there.
6. **In the Task flow**, attach `cj_blob_to_bronze` to **Get data** and `lh_retail` to **Store**.

**Say:** *"The Copy job is the managed ingestion engine — no notebook needed to move bytes from blob into OneLake. In the Task flow it becomes the 'Get data' step."*

> **Alternative for testing:** `pwsh module-0-setup/setup.ps1 -Action data` uploads the same CSVs straight to `Files/bronze`, skipping the Copy job (used by the headless smoke test).

---

## 1.1 Attach the lakehouse (UI — before the notebooks)

1. Open workspace **`Fabric-Demo-Workshop`** → notebook **`00_config`**.
2. Explorer → **Lakehouses** → **+ Add** → **Existing lakehouse** → **`lh_retail`** → **Add** (must show **pinned** as default).
3. Run all cells in `00_config`. Expect schemas created + three CSVs listed under `Files/bronze/`.

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

> **Copilot:** Notebook Copilot pane → *"Explain this notebook"* or *"Write PySpark to dedupe fact_sales"*. Full agent tour in Module 9.

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
