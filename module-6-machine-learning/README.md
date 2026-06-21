# Module 6 — Machine Learning

**Story chapter:** *"Predict, don't just report"*

~20 min · **Notebook** (Fabric Data Science + MLflow).

> **Two ways to do this module:**
> - **Code:** `pwsh module-6-machine-learning/run.ps1` — uploads + runs `ml_sales_forecast` (trains, MLflow-logs, registers the model, writes `gold.sales_predictions`).
> - **UI follow-along:** import the notebook and run it cell-by-cell (steps below).
> Prereq: Module 1 produced `gold.sales_by_store_day`.

---

## Where this fits

| Before | This module | After |
| --- | --- | --- |
| Gold tables describe **what happened** (Modules 1–4) | A model predicts **what's next** | Predictions become a gold data product; Module 9 agents can query it |

Contoso's BI shows yesterday's sales. The next question is forward-looking: *"What will each store sell tomorrow?"* Fabric is a **full data-science platform** — built-in **MLflow** tracking + **model registry**, Spark/sklearn/SynapseML — so we train on the **same gold tables** the report uses, with no data leaving OneLake.

```
gold.sales_by_store_day ─► features ─► train (sklearn + MLflow autolog)
                                          │
                                          ├─► Experiment: retail-sales-forecast
                                          ├─► Registered model: retail_sales_forecaster
                                          └─► gold.sales_predictions (Delta, scored)
```

---

## 6.1 Open / import the notebook

- **Code path:** `run.ps1` uploads `ml_sales_forecast` with the default lakehouse (`lh_retail`) already bound.
- **UI path:** workspace → **+ New item → Import notebook** → `module-6-machine-learning/ml_sales_forecast.ipynb`, then attach **`lh_retail`** as the default lakehouse.

## 6.2 Run it (the four steps in the notebook)

1. **Load** `gold.sales_by_store_day` into pandas.
2. **Feature engineering** — day-of-week, region (one-hot), units, transactions; target = `net_sales`.
3. **Train + track** — `RandomForestRegressor` with **`mlflow.sklearn.autolog()`**; logs params/metrics and **registers** `retail_sales_forecaster`.
4. **Score + write back** — predictions → **`gold.sales_predictions`** (Delta).

The same OneLake gold tables feed BI and ML. MLflow tracking and the model registry are native to Fabric — no separate ML service — and the scored output is just another gold table any engine or agent can read.

## 6.3 Show the artifacts (UI)

- Workspace → **Experiments** → **`retail-sales-forecast`** → open the run → params, `mae`, `r2`, the model artifact.
- Workspace → the **`retail_sales_forecaster`** registered model → versions.
- `lh_retail` → **Tables** → **`gold.sales_predictions`** (predicted vs actual + `abs_error`).

> **Copilot:** the notebook Copilot pane can explain the model code or suggest features. Model output flows into Module 9's Data Agent ("which stores are predicted to underperform?").

---

## Checklist → Module 7

- [ ] MLflow run logged under `retail-sales-forecast`
- [ ] `retail_sales_forecaster` registered
- [ ] `gold.sales_predictions` written

**Next:** [`module-7-orchestration-governance/`](../module-7-orchestration-governance/README.md) — orchestrate (you could schedule this notebook in a pipeline) and govern the estate.
