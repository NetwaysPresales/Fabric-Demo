# Module 9 — AI Agents & Copilot

**Story chapter:** *"Talk to your governed gold layer"*

~10–15 min (optional +15). **Mention + quick demo** — the agentic layer on everything we built.

> **UI-only module** — no `run.ps1`. Copilot and Data Agents are interactive portal experiences. Follow the steps below.

---

## Where this fits

| Before | This module | Future |
| --- | --- | --- |
| Gold tables, Direct Lake model, live telemetry — all governed | **Copilot** assists builders; **agents** answer business questions | Fabric IQ ontologies, Database Hub (roadmap) |

We've shown Contoso's **data estate**. Now we show the **AI layer**: same OneLake items, same Purview labels, same capacity — but natural language for builders (Copilot) and consumers (Data Agent, Power BI agent, Operations agent).

---

## Prerequisites (read before promising live demo)

| Requirement | Detail |
| --- | --- |
| **Capacity** | Paid **F2+** (not trial) |
| **Tenant admin** | Copilot switches enabled |
| **UAE North / non-US-EU** | Enable *"Data sent to Azure OpenAI can be processed outside your capacity's geographic region"* (+ storage/history toggles for Data agents) |
| **Fallback** | If off → demo via screenshots; explain compliance trade-off |

Our demo env: **F4, UAE North** — confirm toggles before Module 9 live.

---

## 8.1 Copilot woven through Fabric (callbacks to earlier modules)

| Surface | Where we already saw it | Try saying |
| --- | --- | --- |
| **Notebooks** | Module 1 | *"Explain this notebook"* / *"Dedupe fact_sales"* |
| **SQL** | Modules 2–3 | Autocomplete / NL → T-SQL |
| **Power BI** | Module 4 | *"Create regional sales page"* |
| **KQL** | Module 5 | NL → KQL for freezer breaches |

**Say:** *"Same governance — Copilot reads items you already secured in OneLake."*

---

## 8.2 Fabric Data Agent — NL over YOUR data

Answers business questions over lakehouse / warehouse / semantic model → publish to Teams / Copilot Studio.

1. **+ New item → Data agent** → **`retail_data_agent`**.
2. **Data sources:** `lh_retail` gold, `wh_retail`, `sm_retail_directlake`.
3. **Instructions:** e.g. *"net sales = SUM(net_amount)"*.
4. Ask: *"Which region had highest net sales?"* / *"Top 5 categories by units?"*
5. **Publish** → Teams / Copilot Studio.

**Say:** *"Grounded Q&A on gold — not a generic ChatGPT. This is the 'talk to your data product' moment."*

---

## 8.3 Power BI agent

- Open **`rpt_retail_overview`** → **Copilot** → *"What's driving North region sales?"*
- Self-service NL on the **Direct Lake semantic model** from Module 4.

---

## 8.4 Operations agent (Real-Time, preview)

- Eventhouse / Real-Time hub → agent experience.
- *"Which stores breached freezer threshold in the last hour?"*
- Pairs with **Activator** (Module 5). Preview availability varies by region.

---

## 8.5 Future outlook (mention)

| Direction | Meaning |
| --- | --- |
| **Database Hub** | Transactional DBs managed alongside analytics |
| **Fabric IQ / Ontologies** | Business entities + relationships — agents reason over *meaning*, not just tables |
| **Agentic apps on Fabric** | Apps built directly on Fabric backend (Build 2026 direction) |

---

## Full story arc — closing line

> *"Contoso landed batch sales in OneLake, served SQL and BI without copies, mirrored live orders, alerted on freezer failures, governed the estate, shipped Dev→Test, and now asks questions in plain English — all on one platform."*

---

## Checklist

- [ ] At least one Copilot surface live (or screenshot)
- [ ] Data Agent queried gold (or walked steps)
- [ ] Power BI agent + Operations agent + Fabric IQ mentioned

**End of workshop** — pause capacity: `pwsh module-0-setup/setup.ps1 -Action pause`
