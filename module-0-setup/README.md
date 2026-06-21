# Module 0 — Setup

**Story chapter:** *"Build the stage for Contoso Retail"*

Read this **first**. Gets you from nothing to a workspace with every item the demo needs.

---

## The story you're setting up

Before Contoso's data engineers can refine sales or operations can watch freezer sensors, you need a **Fabric workspace** on capacity with the right items:

| Item | Name | Used in |
| --- | --- | --- |
| Lakehouse (schemas on) | `lh_retail` | Modules 1, 2, 4, 6, 8 |
| Warehouse | `wh_retail` | Module 2 |
| SQL Database | `sqldb_orders` | Module 3 |
| Eventhouse + KQL DB | `eh_telemetry` | Module 5 |
| Pipeline shell | `pl_ingest` | Module 6 |
| Notebooks `00`–`06` | module-1 folder | Module 1 |
| Second workspace | `Fabric-Demo-Workshop-Test` | Module 7 deployment pipeline |

```
Orders (SQL DB) ──mirror──┐
                          ▼
POS CSVs ──► lh_retail (bronze→silver→gold) ──► wh_retail ──► Direct Lake / Power BI
Telemetry ──► eh_telemetry ──► Eventstream / Activator
```

---

## Two setup paths

| Path | Who | How |
| --- | --- | --- |
| **A — Scripted** | You have Azure CLI + capacity rights | `setup.ps1 -Action all` |
| **B — Manual** | Portal-only / Fabric trial | Click-by-click in §3b below |

> Trainer shared a workspace? Skip to **§4 Follow the demo**.

---

## Prerequisites

**Everyone:** browser, https://app.fabric.microsoft.com, Fabric-enabled tenant, capacity or **60-day trial**.

**Path A also:** Azure CLI (`az login`), PowerShell 7 (`pwsh`), Contributor on a resource group (or existing capacity in `.env`).

---

## Path A — Scripted setup

From **repo root**:

```powershell
Copy-Item .env.example .env          # edit AZURE_SUBSCRIPTION_ID, REGION, CAPACITY_NAME
pwsh module-0-setup/setup.ps1 -Action deps
pwsh module-0-setup/setup.ps1 -Action all    # provision + data + notebooks
pwsh module-0-setup/setup.ps1 -Action run    # smoke-test notebooks
pwsh module-0-setup/setup.ps1 -Action pause  # stop billing when idle
```

### `setup.ps1` actions

| `-Action` | Does |
| --- | --- |
| `deps` | Azure CLI check + `microsoft-fabric` extension |
| `provision` | RG, capacity, workspaces, all items, workspace identity |
| `data` | Generate CSVs/NDJSON, upload to `Files/bronze` |
| `notebooks` | Upload Module 1 notebooks (default lakehouse bound) |
| `all` | deps + provision + data + notebooks |
| `run` | Headless notebook smoke test |
| `pause` / `resume` / `status` | Capacity billing |
| `teardown` | Delete workspaces (optional `-DeleteResourceGroup`) |

Notebook libraries (`pyspark`, `notebookutils`) ship with the **Fabric runtime** — no `requirements.txt`.

---

## Path B — Manual portal setup

1. **Workspace** → `Fabric-Demo-Workshop` → License = capacity or Trial.
2. **+ New item:** Lakehouse `lh_retail` (**Lakehouse schemas** ✓), Warehouse `wh_retail`, SQL database `sqldb_orders`, Eventhouse `eh_telemetry`, Pipeline `pl_ingest`.
3. **Import notebooks** from `module-1-onelake-lakehouse/` (7 files).
4. **Upload data:** `module-0-setup/data/*.csv` → `lh_retail/Files/bronze/`.
5. **Second workspace** `Fabric-Demo-Workshop-Test` for Module 7.

---

## Follow the demo

Open **Fabric-Demo-Workshop** → start **Module 1**.

### OneLake intro (say before Module 1)

Click `lh_retail` and point out:
- **One storage** for the tenant ("OneDrive for data")
- **Tables** (Delta) vs **Files** (unstructured)
- **Zero-copy** — every engine reads the same Delta files
- **Shortcuts** — federate external storage without copying

| # | Next folder |
| --- | --- |
| 1 | `module-1-onelake-lakehouse/` |
| 2–8 | Continue in order |

If items won't load → capacity paused → `setup.ps1 -Action resume`.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Capacity not visible after provision | Wait ~1 min, re-run |
| Fabric token error | `az login` |
| Spark cold start 2–3 min | Pre-run first cell of `01` before demo |
| Empty `Files/bronze` | `-Action data` or manual upload |

## Cost

Pause when idle: `pwsh module-0-setup/setup.ps1 -Action pause`. Trial = 60 days free.

**Next:** [`module-1-onelake-lakehouse/`](../module-1-onelake-lakehouse/README.md)
