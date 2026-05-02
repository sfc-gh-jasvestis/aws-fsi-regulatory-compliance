# MAS Regulatory Compliance & Record Keeping
### Snowflake + AWS | Singapore FSI Demo

> A compliance surveillance platform for Singapore MAS-regulated banks — real-time communication monitoring, trade surveillance, Cortex Search over regulations, and AI-powered STR generation via Amazon Bedrock.

---

## Two Personas, One Governed Platform

| Persona | Tool | What they see |
|---|---|---|
| **Compliance Officer** | Streamlit in Snowflake | Flagged communications, trade violations, regulation search, STR generation |
| **Head of Compliance** | Amazon QuickSight + Amazon Q | Event trends, severity distribution, employee risk, retention compliance |

---

## Architecture

```
AWS Data Plane                     Snowflake AI Data Cloud
───────────────────                ──────────────────────────────────
Amazon S3 (records)        ──────▶ RAW (Snowpipe auto-ingest)
                                   CURATED (Dynamic Tables, 5 min lag)
                                   ├── ENRICHED_COMMUNICATIONS
                                   ├── TRADE_SURVEILLANCE
                                   ├── COMPLIANCE_EVENTS
                                   └── RECORD_RETENTION_STATUS
Amazon Bedrock (Claude)    ◀─────▶ AI (External Access, SigV4 → Converse API)
                                   ├── REVIEW_COMMUNICATION SP
                                   ├── GENERATE_STR SP
                                   └── Cortex Search (12 MAS regulations)
Amazon QuickSight          ◀─────  CURATED Views (DIRECT_QUERY)
```

| Layer | AWS | Snowflake |
|---|---|---|
| **Ingest** | S3 | Snowpipe, External Stages |
| **Transform** | — | Dynamic Tables (RAW → CURATED, 5 min lag) |
| **Detect** | — | Watchlist cross-reference, keyword flagging, restricted instrument matching |
| **Investigate** | Amazon Bedrock (Claude Sonnet 4.5) | Streamlit (Compliance Officer app) |
| **Search** | — | Cortex Search (semantic RAG over MAS Notices + internal policies) |
| **Report** | Amazon QuickSight + Amazon Q | Datasets + Q Topic (NLP queries) |

---

## Repository Structure

```
fsi-regulatory-compliance/
├── snowflake/
│   ├── 00_setup.sql              # DB, schemas, warehouse
│   ├── 01_integrations.sql       # S3 storage integration, Bedrock EAI
│   ├── 02_raw_tables.sql         # 5 raw tables
│   └── 03_curated.sql            # 4 Dynamic Tables
├── streamlit/
│   ├── streamlit_app.py          # 4-tab Compliance Officer app
│   └── snowflake.yml             # Snowflake CLI deploy config
├── quicksight/
│   └── deploy.sh                 # Datasets + Q topic deployment
├── demo/
│   └── demo_script.md            # 3.5-min video narration
└── README.md
```

---

## Quick Start

### Prerequisites
- Snowflake account with ACCOUNTADMIN
- `snow` CLI configured
- AWS CLI with Bedrock access (us-west-2)
- S3 bucket with Snowflake storage integration

### 1. Build Snowflake Platform
Run the SQL files in order (00 → 03) against your Snowflake account, then generate synthetic data using AI_COMPLETE (embedded in the build scripts).

### 2. Deploy AI Layer
The Cortex Search service and Bedrock stored procedures are created as part of the build. Update the Bedrock secret with real AWS credentials:
```sql
ALTER SECRET FSI_REGULATORY_COMPLIANCE.AI.BEDROCK_SECRET
    SET SECRET_STRING = '{"aws_access_key_id":"AKIA...","aws_secret_access_key":"..."}';
```

### 3. Deploy Streamlit App
```bash
cd streamlit && snow streamlit deploy --replace --connection <CONNECTION>
```

### 4. Deploy QuickSight
```bash
bash quicksight/deploy.sh
```

### 5. Health Check
```sql
SELECT
    (SELECT COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.RAW.TRADE_RECORDS)       AS trades,
    (SELECT COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.RAW.COMMUNICATIONS)      AS comms,
    (SELECT COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.CURATED.COMPLIANCE_EVENTS) AS events,
    (SELECT COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.RAW.COMPLIANCE_DOCUMENTS)  AS docs;
```
Expected: 200 trades, 200 comms, 400 events, 12 docs.

---

## Streamlit App (4 Tabs)

| Tab | Feature | Key Snowflake Capability |
|---|---|---|
| **Regulation Search** | Semantic search over MAS Notices + AI summary | Cortex Search + AI_COMPLETE |
| **Communication Review** | Flagged comms queue + Bedrock compliance assessment | Dynamic Tables + External Access |
| **Compliance Dashboard** | KPIs, severity charts, employee breakdown, retention status | Dynamic Tables |
| **Regulatory Reports** | STR narrative generation for watchlist employees | Bedrock Converse API |

---

## Synthetic Data

| Table | Rows | Content |
|---|---|---|
| TRADE_RECORDS | 200 | SGX-listed instruments, 10 traders, 5 venues |
| COMMUNICATIONS | 200 | Emails/chats, ~45% flagged as suspicious |
| REGULATORY_FILINGS | 15 | STRs, FATCA, MAS Notices, audits |
| EMPLOYEE_WATCHLIST | 10 | Restricted traders with instrument restrictions |
| COMPLIANCE_DOCUMENTS | 12 | MAS Notices 610/626/637, internal policies |

---

## Demo Script

| Script | Duration | Use |
|---|---|---|
| `demo/demo_script.md` | 3.5 min | Recorded video walkthrough |

---

## SE Demo Account Notes

- **Network policy**: If your account blocks external IPs, create a user-level network policy for `QUICKSIGHT_FSI_SVC` allowing QuickSight us-west-2 IPs (54.70.204.128/27).
- **Bedrock model**: Uses `us.anthropic.claude-sonnet-4-5-20250929-v1:0`. The older `-20250514` model is marked legacy.
- **Cortex Search**: Indexes 12 documents. Add more to `COMPLIANCE_DOCUMENTS` table and the service auto-refreshes within 1 hour.

---

## Legal

This is a personal project and is **not an official Snowflake offering**. It comes with no support or warranty. Do not use in production without thorough review and testing.
