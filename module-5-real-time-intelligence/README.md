# Module 5 — Real-Time Intelligence

**Story chapter:** *"The store calls for help — before the batch job runs"*

~20 min · **UI** + KQL scripts in this folder. **Protect this time** — highest wow factor.

---

## Where this fits

| Before | This module | After |
| --- | --- | --- |
| Batch sales in gold (Modules 1–4) | **Live** store telemetry | Module 8 Operations agent asks questions over this stream |

Contoso's stores have IoT sensors: **freezer** temperature, **HVAC**, **foot traffic**, **checkout queue** depth. A freezer failure can't wait for tomorrow's POS export. **Real-Time Intelligence** ingests events, stores them in **Eventhouse**, dashboards them in seconds, and **Activator** pings Teams when thresholds breach.

```
telemetry.ndjson → Eventstream → Eventhouse (KQL) → Real-Time Dashboard
                                      │
                                      └── Activator → Teams / email alert
```

Sample events: `module-0-setup/data/telemetry.ndjson`.

---

## 5.1 Prepare KQL table

1. Open **`eh_telemetry`** eventhouse → KQL database **`eh_telemetry`**.
2. Run **`eventhouse_setup.kql`** — creates `StoreTelemetry` + JSON mapping `telemetry_map`.

---

## 5.2 Eventstream — ingest live events

1. **+ New item → Eventstream** → **`es_telemetry`**.
2. **Add source:** Sample data **or** Custom endpoint + push from `telemetry.ndjson`.
3. **Add destination → Eventhouse** → `eh_telemetry` / table **`StoreTelemetry`** / mapping **`telemetry_map`**.
4. **Publish** — watch live preview.

**Say:** *"Eventstream = no-code routing, filtering, windowing. Same platform as batch — not a separate Azure service to wire up."*

---

## 5.3 Real-Time Dashboard

1. **+ New → Real-Time Dashboard** → **`rtd_stores`**.
2. Paste queries from **`dashboard_queries.kql`**:
   - **A** — latest per sensor (stat/table tile)
   - **B** — 1-min averages (`render timechart`)
3. Auto-refresh ~30s.

---

## 5.4 Activator — the money moment

1. From Eventstream or KQL query **C** → **Set alert / Create Activator**.
2. **Condition:** `sensor == "freezer"` AND `value > 5`.
3. **Action:** Teams message or email.
4. **Push a breaching event** (freezer value > 5) → alert fires live.

**Say:** *"Sub-second detection → Teams. Pair with Module 8 Operations agent for NL diagnostics over live telemetry."*

> **Copilot:** KQL queryset → NL to KQL. Module 8 for Operations agent.

---

## Talking points (RTI platform)

| Component | Role |
| --- | --- |
| **Real-Time Hub** | Tenant catalog of streams; connectors (Event Hubs, Kinesis, Pub/Sub, Debezium CDC) |
| **Eventstream** | Ingest + transform + route |
| **Eventhouse / KQL** | Durable store + query language |
| **Activator** | Event-driven rules → Teams / email / Power Automate |

---

## Checklist → Module 6

- [ ] Events flowing Eventstream → Eventhouse
- [ ] Live dashboard tile
- [ ] Activator fired on threshold breach

**Next:** [`module-6-orchestration-governance/`](../module-6-orchestration-governance/README.md) — orchestrate and govern the whole estate.
