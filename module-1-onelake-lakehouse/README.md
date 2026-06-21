# Module 1 — OneLake & the Lakehouse

**Story chapter:** *"Land and refine Contoso's batch sales data"*

~20 min · A **Task flow** + **Copy job** (UI), then the **medallion notebooks**.

> **Two ways to do this module:**
> - **Code:** `pwsh module-1-onelake-lakehouse/run.ps1` — creates the lakehouse, uploads CSVs + notebooks, runs `00`–`04` (end result: bronze/silver/gold tables).
> - **UI follow-along:** the steps below — import the task flow, build the Copy job, then run the notebooks.
>
> Prereq either way: `pwsh module-0-setup/setup.ps1 -Action infra` (workspace + Blob CSVs + connection).

---

## Where this fits

| Before | This module | After |
| --- | --- | --- |
| Module 0 (`setup.ps1 -Action infra`) provisioned the workspace + Blob CSVs | Medallion pipeline: bronze → silver → gold | Module 2 queries gold from warehouse T-SQL; Module 4 builds Direct Lake on gold |

Contoso's POS systems drop three CSV files every night. We land them in **bronze** (raw), conform them in **silver** (dimensions + facts + V-Order), and publish **gold** KPI tables that the rest of the demo consumes — **without ever copying data out of OneLake**.

---

## Notebooks (run in order)

Each `.ipynb` includes **markdown cells** with story context, step-by-step explanations, and success criteria. Open them in Fabric and read the markdown before running code.

| Order | Notebook | Story beat | Key output |
| --- | --- | --- | --- |
| 1 | `00_config.ipynb` | Prepare the lakehouse | `bronze`, `silver`, `gold` schemas |
| 2 | `01_bronze_ingest.ipynb` | Land nightly POS export | `bronze.stores/products/sales` |
| 3 | `02_silver_transform.ipynb` | Make data trustworthy | `silver.dim_*`, `silver.fact_sales` + V-Order |
| 4 | `03_gold_aggregate.ipynb` | Publish data products | `gold.sales_by_store_day`, `sales_by_category`, `sales_by_region` |
| 5 | `04_vorder_demo.ipynb` | Prove V-Order | Size/time comparison in `demo` schema |

**The notebooks are not in the workspace yet.** `setup.ps1` (infra) does **not** upload them — they're uploaded by `pwsh module-1-onelake-lakehouse/run.ps1` (code path), or you **import them manually** for the UI path (§1.1). Every notebook starts with `%run 00_config`.

---

## 1.0 Ingest from Blob with a Copy job + a Task flow (UI — the headline)

Contoso's nightly CSVs land in **Azure Blob Storage** (`ntwfabricdemostg/retail-raw/bronze/`, from `setup.ps1 -Action storage`). Rather than the data magically appearing in the lakehouse, we **ingest it live** with a Copy job and document the whole estate with a **Task flow**.

> **No upfront setup:** the **lakehouse is created inside the Copy job** (§1.0b) and the **notebooks are imported in §1.1**. (Skip both if you ran `run.ps1`.)

### 1.0a — Import the Task flow (the visual map)

A **Task flow** is a canvas of typed **tasks** (boxes) connected as a graph, each assigned a real Fabric item — the workspace's blueprint. Import the ready-made flow instead of hand-placing every box:

1. Open the **task flow** canvas (below the item list) → **Set up a task flow** → **Import** → choose [`demo-task-flow.json`](demo-task-flow.json) from this folder.
2. It lays out the demo as a graph with **two parallel branches** — a **batch** path and a **real-time** path — that converge at Distribute/Govern:

   ```
   BATCH                                                                ┌─► Develop (wh_retail) ─┐
   Copy job ─┐                                                          │                        │
             ├─► lh_retail ─► Medallion (notebooks/dataflow) ──────────►├─► ML forecast ─────────┼─► Power BI ─┐
   Mirror ───┘        │                                                 └────────────────────────┘            │
                      └─► Govern (Domains/Purview/OneLake security)                                            ├─► Distribute
   REAL-TIME                                                                                                   │   (Data agent
   Eventstream (from Event Hub) ─► Eventhouse (KQL) ─┬─► Real-Time Dashboard ───────────────────────────────────┘    + deploy)
                                                     └─► Activator (+ metrics)
   ```
3. Assign the real item to each task as it's built across the modules (table below). To add/adjust a task by hand, use **+ Add a task** (types: Get/Mirror/Store/Prepare/Analyze and train/Develop/Visualize/Track/Distribute/Govern data).

| Branch | Task (type) | Item assigned | Module |
| --- | --- | --- | --- |
| Batch | **Get data** | `cj_blob_to_bronze` (Copy job) | 1 |
| Batch | **Mirror data** | `sqldb_orders` (mirroring) | 3 |
| Batch | **Store data** | `lh_retail` (lakehouse) | 1 |
| Batch | **Prepare data** | notebooks `01`–`03`, `df_clean` (Dataflow Gen2) | 1, 7 |
| Batch | **Analyze & train** | `ml_sales_forecast` → `retail_sales_forecaster` | 6 |
| Batch | **Develop** | `wh_retail` (warehouse) | 2 |
| Batch | **Visualize** | `sm_retail_directlake`, `rpt_retail_overview` (Power BI) | 4 |
| **Real-time** | **Get data** | `es_telemetry` (Eventstream, from the Event Hub) | 5 |
| **Real-time** | **Store data** | `eh_telemetry` (eventhouse / KQL) | 5 |
| **Real-time** | **Visualize** | `rtd_stores` (Real-Time Dashboard) | 5 |
| **Real-time** | **Track data** | `act_store_alerts` (Activator), Capacity Metrics | 5, 8 |
| Both | **Distribute data** | `retail_data_agent` (Data Agent), `dp_retail` (deployment) | 8, 9 |
| Both | **Govern data** | Domains, Purview labels + lineage, OneLake security | 7 |

> **Event Hub** is an Azure resource, not a Fabric item, so it isn't a task-flow node — the **Eventstream** ("Get data", real-time) is its in-Fabric representation. Every other demo item maps to a task above.

### 1.0b — Copy job: Blob → `lh_retail` `Files/bronze`

1. **+ New item → Copy job** → name **`cj_blob_to_bronze`**.
2. **Source:** *Azure Blob Storage* → **New connection** (the Copy job creates it inline) → account `ntwfabricdemostg`, auth **Account key** → container `retail-raw`, folder `bronze/` → the 3 CSVs.
3. **Destination:** **New → Lakehouse** → name **`lh_retail`** (tick **Lakehouse schemas** if offered) — the lakehouse is created here. Target **Files**, then:
   - **Folder path:** **root** (`Files`), not `bronze`. With **Copy behavior = Preserve hierarchy** the job carries the source's `bronze/` folder, so root → `Files/bronze/*.csv`. (Setting `bronze` would nest to `Files/bronze/bronze/`.)
   - **Copy behavior:** **Preserve hierarchy** (keeps the original file names — `01_bronze_ingest` reads them by name).
   - **File name:** blank · **Add header to file:** on · **Column mapping:** default (schema-agnostic — bronze stays raw).
4. **Save → Run**, then confirm the 3 CSVs under `lh_retail → Files/bronze`.
5. In the Task flow, attach `cj_blob_to_bronze` to **Get data** and `lh_retail` to **Store data**.

The Copy job moves bytes from blob into OneLake with no notebook; the medallion transforms come next.

> **Testing shortcut:** `pwsh module-0-setup/setup.ps1 -Action data` uploads the CSVs straight to `Files/bronze`, skipping the Copy job (used by the headless smoke test).

---

## 1.1 Import the notebooks + attach the lakehouse (UI)

`lh_retail` already exists (created by the Copy job in §1.0b). Skip this section if you ran `run.ps1` — it imported and bound the notebooks for you.

1. **+ New item → Import notebook** → upload all 5 `.ipynb` from this folder (`00_config` … `04_vorder_demo`).
2. Open **`00_config`** → Explorer → **Lakehouses** → **+ Add** → **Existing lakehouse** → **`lh_retail`** → **Add** (must show **pinned** as default).
3. Run all cells in `00_config`. Expect schemas created + three CSVs listed under `Files/bronze/`.

> Empty `Files/bronze`? Run `pwsh module-0-setup/setup.ps1 -Action data` or upload `stores.csv`, `products.csv`, `sales.csv` from `module-0-setup/data/`.

OneLake is "OneDrive for data"; the lakehouse sits on top of it as the Spark workspace — Tables and Files in one storage account.

---

## 1.2 Bronze → Silver → Gold (notebooks)

Run **`01`** through **`03`** in order. Read the markdown in each notebook as you go.

| Step | What happens | What to show the room |
| --- | --- | --- |
| **01 Bronze** | CSV → Delta tables | Tables appear in Explorer — no separate import step |
| **02 Silver** | Clean, join, V-Order fact | Business rules (filter bad qty, compute net sales) |
| **03 Gold** | Aggregates for BI | Category ranking — feeds Module 4 report |

Same files, no movement: bronze = raw audit trail, silver = trusted model, gold = the business-shared layer.

> **Copilot:** Notebook Copilot pane → *"Explain this notebook"* or *"Write PySpark to dedupe fact_sales"*. Full agent tour in Module 9.

---

## 1.3 V-Order (notebook `04`)

Run **`04_vorder_demo`**. It scales the fact to ~2M rows, writes it with V-Order **off vs on** (`OPTIMIZE … VORDER`), and compares file size + an indicative read time.

V-Order is a write-time Parquet layout. The big read win is in **Verti-Scan engines (Power BI, SQL)** and **Direct Lake — which requires V-Order**; **Spark** sees only ~10% on average, so the notebook's Spark timing is intentionally modest. The warehouse (Module 2) applies V-Order automatically; in Spark it's off by default. The real payoff is shown live in **Module 4 (Direct Lake)**.

---

## Checklist before Module 2

- [ ] `bronze`, `silver`, `gold` tables visible in `lh_retail`
- [ ] `gold.sales_by_store_day`, `sales_by_category`, `sales_by_region` written (`03`)
- [ ] V-Order written + compared (`04`)

**Next:** [`module-2-warehouse-vs-lakehouse/`](../module-2-warehouse-vs-lakehouse/README.md) — SQL devs meet the same data in `wh_retail`.
