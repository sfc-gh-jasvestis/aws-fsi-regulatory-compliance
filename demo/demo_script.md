# Demo Script: MAS Regulatory Compliance & Record Keeping
## 3.75-Minute Recorded Walkthrough (~3:45)
**Format**: Screen recording with voiceover
**Target**: Customer meeting / booth loop / social share
**Pre-requisites**: Data loaded, Streamlit deployed, QuickSight dashboard published

---

## Two Personas

| Persona | Role | Tool | What they care about |
|---|---|---|---|
| **Compliance Officer** | Day-to-day surveillance | Streamlit in Snowflake | Flagged communications, trade violations, regulation search, STR generation |
| **Head of Compliance / CCO** | Executive oversight | Amazon QuickSight + Amazon Q | Alert trends, severity distribution, employee risk, retention compliance |

---

## What's Built

| Layer | Component | Detail |
|---|---|---|
| **Ingest (AWS)** | Amazon S3 | Trade records, communications, regulatory filings |
| **RAW** | 5 tables | TRADE_RECORDS (200), COMMUNICATIONS (215), REGULATORY_FILINGS (15), EMPLOYEE_WATCHLIST (10), COMPLIANCE_DOCUMENTS (12) |
| **CURATED** | 4 Dynamic Tables | ENRICHED_COMMUNICATIONS, TRADE_SURVEILLANCE, COMPLIANCE_EVENTS (410 flagged events), RECORD_RETENTION_STATUS |
| **AI** | Cortex Search | Semantic search over 12 MAS regulations and internal policies |
| | Bedrock SP | REVIEW_COMMUNICATION — compliance assessment per flagged comm |
| | Bedrock SP | GENERATE_STR — formal Suspicious Transaction Report narrative |
| **Consumption** | Streamlit | 4-tab Compliance Officer app (Regulation Search, Communication Review, Compliance Dashboard, Regulatory Reports) |
| | QuickSight | 2-sheet dashboard (Compliance Overview + Trade Surveillance) + Q Topic |

**Current data**: 410 flagged events | 107 CRITICAL | 152 HIGH | 151 MEDIUM | 21 trade violations | 210 communications flagged | 10 employees on watchlist

---

## Pre-Recording Checklist

- [ ] Verify Dynamic Tables: `SHOW DYNAMIC TABLES IN DATABASE FSI_REGULATORY_COMPLIANCE` (all ACTIVE)
- [ ] Open Streamlit: `FSI_REGULATORY_COMPLIANCE.APP.REGULATORY_COMPLIANCE_APP`
- [ ] Test Cortex Search: Tab 1 (Regulation Search), click "How long must trade records be retained under MAS Notice 610?" — confirm results appear
- [ ] Test Bedrock: Tab 2 (Communication Review), filter CRITICAL, select **COM-0097** (David Tan — "Re: DBS position sizing before announcement"), click Review — confirm VIOLATION response
- [ ] Open QuickSight: https://us-west-2.quicksight.aws.amazon.com/sn/dashboards/regulatory-compliance-dashboard
- [ ] Test Amazon Q: ask "Which instrument has the highest notional exposure?"
- [ ] Audio: quiet room, external mic
- [ ] Resolution: 1920x1080

---

## Script

### [0:00–0:45] THE PROBLEM & ARCHITECTURE (Show: Architecture Diagram)

> *"Singapore's MAS requires banks to retain all trade records and communications for 5 years, monitor for insider trading, and file Suspicious Transaction Reports within 15 business days. With millions of daily communications and trades, how do you find the needle in the haystack — and prove compliance at scale?*
>
> *Here's the architecture. On the left, Amazon S3 — that's where trade records, communications, and regulatory filings land. Snowpipe streams them into Snowflake's RAW layer — five tables, all append-only. Dynamic Tables in the CURATED layer handle the heavy lifting: enriching communications against the employee watchlist, running trade surveillance, rolling everything up into a single compliance event queue. On the AI layer, Cortex Search provides semantic search over MAS regulations, and Amazon Bedrock powers the compliance review and STR generation. Finally, two consumption layers: Streamlit for the Compliance Officer's daily workflow, and QuickSight for executive oversight."*

**Screen**: Architecture diagram — walk through left to right: S3 → Snowpipe → RAW (5 tables) → Dynamic Tables (CURATED) → AI (Cortex Search + Bedrock) → Streamlit / QuickSight

---

### [0:45–1:15] DATA PIPELINE (Show: Snowsight)

> *"Once data lands in the RAW layer, Dynamic Tables take over — no ETL jobs, no scheduling. ENRICHED_COMMUNICATIONS joins every incoming message against the employee watchlist. COMPLIANCE_EVENTS rolls up flagged communications and trade violations into one queue. 410 events, continuously refreshed, 5-minute target lag, zero pipelines to maintain."*

**Screen**: Show Dynamic Table lineage in Snowsight UI (click on COMPLIANCE_EVENTS → Graph tab) — narrate while pointing at the flow.

Then run the count query to prove the pipeline is live:
```sql
SELECT 'TRADES' AS SOURCE, COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.RAW.TRADE_RECORDS
UNION ALL SELECT 'COMMUNICATIONS', COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.RAW.COMMUNICATIONS
UNION ALL SELECT 'FLAGGED EVENTS', COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.CURATED.COMPLIANCE_EVENTS;
```
Expected output: 200 trades, 215 communications, 410 flagged events.

> *"And here's the real power — David Tan is on the restricted list for DBS. He sends an email about 'DBS position sizing before an announcement' — the Dynamic Table flags it CRITICAL automatically."*

```sql
SELECT COMM_ID, SENDER_NAME, SUBJECT, SEVERITY FROM FSI_REGULATORY_COMPLIANCE.CURATED.ENRICHED_COMMUNICATIONS
WHERE SENDER_NAME = 'David Tan' AND SEVERITY = 'CRITICAL' LIMIT 3;
```

---

### [1:15–1:45] REGULATION SEARCH (Show: Streamlit Tab 1 — "Regulation Search")

> *"The Compliance Officer starts by searching regulations. 'How long must trade records be retained?' — Cortex Search finds MAS Notice 610 instantly, and Cortex AI generates a grounded answer citing the specific 5-year requirement for trade confirmations, settlement instructions, and voice recordings."*

**Screen**: Tab 1 → Click "How long must trade records be retained under MAS Notice 610?" → Show 5 results with relevance scores → AI Summary paragraph

---

### [1:45–2:30] COMMUNICATION REVIEW (Show: Streamlit Tab 2 — "Communication Review")

> *"Next, the flagged communication queue. 107 CRITICAL severity events need attention. Here's David Tan — he's on the restricted list for DBS, OCBC, UOB, and SGX due to access to material non-public information. He's emailed about 'DBS position sizing before an announcement' — telling a colleague to increase their position before market open. Classic insider trading signal. One click sends this to Amazon Bedrock for AI-powered compliance assessment."*

**Screen**: Tab 2 → Filter CRITICAL → Select **COM-0097** ("David Tan: Re: DBS position sizing before announcement") → Show email body → Click "Review with Amazon Bedrock" → Show response: VIOLATION, CRITICAL severity, escalation required, regulatory references

> *"Bedrock immediately classifies it as a VIOLATION with CRITICAL severity, cites the relevant MAS regulation, and recommends escalation. What used to require a compliance analyst spending hours now takes 5 seconds."*

---

### [2:30–3:00] STR GENERATION (Show: Streamlit Tab 4 — "Regulatory Reports")

> *"Violation confirmed. Now we generate the Suspicious Transaction Report. Select David Tan from the watchlist — we can see all his compliance events: flagged emails, restricted trades. Bedrock compiles the evidence into a formal MAS-ready STR narrative with evidence strength, urgency assessment, and estimated financial impact."*

**Screen**: Tab 4 → Select "EMP-001 — David Tan (Equities Trading)" → Show compliance events table (38 events) → Click "Generate STR with Amazon Bedrock" → Show: evidence strength, filing urgency, estimated financial impact, full narrative paragraph

> *"From detection to formal filing — one workflow, one platform."*

---

### [3:00–3:30] EXECUTIVE VIEW — QUICKSIGHT (Show: QuickSight Dashboard)

> *"Now we shift persona. The Head of Compliance needs executive visibility without digging through individual cases. QuickSight connects directly to Snowflake — no ETL, no data movement. Compliance Overview shows 410 flagged events with severity breakdown by employee. Trade Surveillance shows 21 violations across restricted instruments. And with Amazon Q, the CCO asks: 'Which instrument has the highest notional exposure?' — instant concentration risk insight, no analyst required."*

**Screen**: QuickSight dashboard → Sheet 1 (Compliance Overview): KPI, severity chart, employee chart → Sheet 2 (Trade Surveillance): trades by status, by instrument → Amazon Q bar: "Which instrument has the highest notional exposure?"

---

### [3:30–3:45] CLOSE (Stay on: QuickSight Sheet 2 — Trade Surveillance)

> *"21 trade violations across restricted instruments. Over 50 million SGD in notional exposure — all detected, reviewed, and reported from one platform. Snowflake for the data foundation. Amazon Bedrock for intelligent compliance review. QuickSight for executive reporting. MAS compliance at Singapore scale."*

---

## Key Demo Questions to Anticipate

1. **"How is this different from existing e-discovery tools?"**
   → Real-time Dynamic Tables vs batch. AI-native with Bedrock + Cortex Search. No separate search index to maintain.

2. **"How does it handle voice recordings?"**
   → Amazon Transcribe outputs to S3 → Snowpipe ingests transcripts identically. Same watchlist cross-reference applies.

3. **"What about PDPA (Singapore data privacy)?"**
   → Snowflake Horizon governance: masking policies on PII columns, row access policies, role-based access control.

4. **"How fast is the Bedrock review?"**
   → ~3-5 seconds per communication. Batch review possible for bulk processing.

5. **"Can this integrate with existing GRC tools?"**
   → Yes. Snowflake shares data via DIRECT_QUERY (QuickSight), API (Snowflake REST), or data sharing (partner GRC platforms).
