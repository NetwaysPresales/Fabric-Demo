# Module 7 — Orchestration, Governance & Security

**Story chapter:** *"Run Contoso's estate safely at scale"*

~15–18 min · Mix of **live build** (pipeline/dataflow) and **show-and-tell** (domains, Purview, security).

> **UI-only module** — no `run.ps1`. Pipelines, dataflows, domains, Purview, and network security are portal/admin features. Follow the steps below.

---

## Where this fits

| Before | This module | After |
| --- | --- | --- |
| Batch + streaming + BI built ad hoc | **Repeatable** ingestion + **governed** sharing | Module 8 ships changes via Git/pipelines |

Contoso now has lakehouse gold, warehouse tables, mirrored orders, Direct Lake reports, and live telemetry. Enterprise IT asks: *Who owns Retail data? How do we label confidential reports? How does Spark reach private Azure SQL without public internet?*

---

## 6.1 Data Pipeline — orchestration

1. Open **`pl_ingest`** (or **+ New → Data pipeline**).
2. **Copy data:** source = `Files/bronze` or HTTP CSV → destination = lakehouse table.
3. **Notebook activity:** **`02_silver_transform`**.
4. Connect **Copy → Notebook** (On success) → **Run**.

**Say:** *"Copy = cheap bulk move. Pipeline = orchestration with If/ForEach/Wait. Notebooks/dataflows = business logic."*

---

## 6.2 Dataflow Gen2 — citizen transforms

1. **+ New → Dataflow Gen2** → **`df_clean`**.
2. **Get data → CSV** → Power Query steps (types, trim, unpivot).
3. Destination = **`lh_retail`** → **Publish**.

**Say:** *"300+ transforms, friendly for analysts — but row-by-row costs more CU. Pair with pipelines."*

---

## 6.3 Governance (show-and-tell)

| Topic | Demo | Narrative |
| --- | --- | --- |
| **Domains / Data mesh** | Admin portal → Domains → assign workspace to **Retail** | Gold tables = domain **data products** shared via Shortcuts |
| **Purview labels** | `sm_retail_directlake` → **Confidential** | Label follows export to Excel/PDF |
| **Lineage** | Workspace → **View → Lineage** | `sqldb_orders` → `lh_retail` → model → `rpt_retail_overview` |
| **DLP** | Mention | Blocks oversharing PII |

---

## 6.4 Security & networking

### Workspace identity (provisioned in Module 0)
- **Workspace settings → Workspace identity** — Entra managed identity (no secrets in pipelines).
- Backbone for Trusted Workspace Access + Managed Private Endpoints.

### Trusted Workspace Access
- Storage firewall = deny public → workspace identity allow-listed → Shortcuts/`COPY INTO` still work.

### Managed Private Endpoints
- Spark/pipelines reach **private** Azure SQL/ADLS over Azure backbone.
- Target owner approves Private Link in Azure portal.

**Say:** *"Fabric is multi-tenant SaaS — enterprises use identity + private endpoints, not VPNs to 'the Fabric server'."*

---

## Checklist → Module 8

- [ ] Pipeline: copy → notebook
- [ ] Dataflow Gen2 with Power Query steps
- [ ] Domain, sensitivity label, lineage view
- [ ] Workspace identity + Trusted Access / MPE explained

**Next:** [`module-8-alm-capacity/`](../module-8-alm-capacity/README.md) — ship to Test/Prod and read the CU meter.
