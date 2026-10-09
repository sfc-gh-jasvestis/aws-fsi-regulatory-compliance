# Conduct Surveillance

**Singapore - Banking**
Use case: Communication and trade surveillance, and record keeping

> Surveillance for 40 front-office employees across 5 desks at a fictional Singapore bank: dynamic tables, a holdout-evaluated conduct-breach classifier, an alert-volume forecast and grounded AI answers.

## Why Snowflake

- **Dynamic tables** reconcile alerts, confirmed breaches, escalated cases, supervisory review compliance and record capture coverage from RAW data, with checks in `run_core.py`
- **Conduct-breach classification** gives a holdout-evaluated next-7-day probability per employee
- **Alert forecast** projects 14 days of bank-wide alert volume with prediction intervals, for surveillance staffing
- **Grounded AI**: the Cortex Agent (Analyst over a semantic view, plus Search over SOPs) shows its SQL and SOP citations
- **Live surveillance**: a native simulator (Snowflake only) or Firehose, S3 and Snowpipe (AWS build), then an alert and email

## What is built

| | |
|---|---|
| Dimension table | `RAW.EMPLOYEES` (40 rows) |
| Fact table | `RAW.EMPLOYEE_DAILY` (3,600 employee-days, 90 days) |
| Curated layer | `CURATED.KPI_SUMMARY`, `PERFORMANCE_SUMMARY`, `RULE_SUMMARY`, `TREND_ANALYSIS` |
| ML | `ML.BREACH_RISK_SCORES`, `ML.BREACH_RISK_HOLDOUT_METRICS`, `ML.ALERT_FORECAST`, `ML.AFTER_HOURS_ANOMALIES` |

Desks: Equities, FX, Rates, Credit, Wealth Advisory.
Seniority: Analyst, Associate, Vice President, Director, Managing Director.

## KPI cards (live from `CURATED.KPI_SUMMARY`; no fallback values)

| Card | Value from the seeded data |
|---|---|
| Alert Precision | 28.7% |
| Alerts Raised | 574 |
| Confirmed Breaches | 165 |
| Cases Escalated | 73 |
| Notional Surveilled (SGD M) | 203,581 |
| Communications Captured | 357,293 |
| Supervisory Review Compliance | 82.8% |
| Employees Monitored | 40 |
| Record Capture Coverage | 71.7% |
| Channels Pending Capture | 12 |

Values are synthetic. A rebuild reproduces them because the data is HASH-seeded; dates are relative to the build day.

## Demo flow

1. Executive Cockpit: KPIs, daily alerts against confirmed breaches, alerts and confirmed breaches by detection rule, employee table
2. Predictive: holdout metrics, risk bands, 14-day alert forecast, after-hours messaging anomalies
3. Record Keeping: supervisory review compliance, record capture coverage and pending channels, review compliance against confirmed breaches, then generate the action memo
4. Live Surveillance: run `CALL APP.SIMULATE_EVENTS(20)` (Snowflake only) or `python aws/publish_events.py --count 20` (AWS build). Then run `EXECUTE ALERT APP.LIVE_EVENT_ALERT` and show the alert log and email.
5. Ask AI: the Cortex Agent answers metric questions through the semantic view and cites SOPs from Cortex Search. The SQL is shown.
6. QuickSight (AWS build): the same Snowflake tables through DIRECT_QUERY
7. Architecture: both builds side by side

## Talking points

- About one alert in four is confirmed as a breach (28.7%). Most alert reviews end as false positives, which is where surveillance analyst time goes.
- Insider-information keyword alerts produce the most confirmed breaches. Market-wide news event alerts hit a whole desk at once and are never confirmed.
- The risk model is evaluated on a time-based holdout: precision 0.37 and recall 0.22 at 0.5, against a 0.22 base rate. Present it as triage, not a verdict.
- Market-wide news events are excluded from model training, because they are not employee-driven.
- The SOPs and record-keeping policy are synthetic internal policies of the fictional bank, not regulatory text.

## Business impact

Use only the sourced references in `README.md` (Business Impact).
