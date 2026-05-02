# Demo Script: MAS Regulatory Compliance & Record Keeping
## 3.5-Minute Recorded Walkthrough
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
| **RAW** | 5 tables | TRADE_RECORDS (200), COMMUNICATIONS (200), REGULATORY_FILINGS (15), EMPLOYEE_WATCHLIST (10), COMPLIANCE_DOCUMENTS (12) |
| **CURATED** | 4 Dynamic Tables | ENRICHED_COMMUNICATIONS, TRADE_SURVEILLANCE, COMPLIANCE_EVENTS (400 flagged events), RECORD_RETENTION_STATUS |
| **AI** | Cortex Search | Semantic search over 12 MAS regulations and internal policies |
| | Bedrock SP | REVIEW_COMMUNICATION — compliance assessment per flagged comm |
| | Bedrock SP | GENERATE_STR — formal Suspicious Transaction Report narrative |
| **Consumption** | Streamlit | 4-tab Compliance Officer app |
| | QuickSight | 2-sheet dashboard (Compliance Overview + Trade Surveillance) + Q Topic |

**Current data**: 400 flagged events | 107 CRITICAL | 142 HIGH | 151 MEDIUM | 21 trade violations | 200 communications reviewed | 10 employees on watchlist

---

## Pre-Recording Checklist

- [ ] Verify Dynamic Tables: `SHOW DYNAMIC TABLES IN DATABASE FSI_REGULATORY_COMPLIANCE` (all ACTIVE)
- [ ] Open Streamlit: `FSI_REGULATORY_COMPLIANCE.APP.REGULATORY_COMPLIANCE_APP`
- [ ] Test Cortex Search: Tab 1, search "record retention" — confirm results appear
- [ ] Test Bedrock: Tab 2, select COM-0001 (CRITICAL), click Review — confirm VIOLATION response
- [ ] Open QuickSight: https://us-west-2.quicksight.aws.amazon.com/sn/dashboards/regulatory-compliance-dashboard
- [ ] Test Amazon Q: ask "How many critical events by employee?"
- [ ] Audio: quiet room, external mic
- [ ] Resolution: 1920x1080

---

## Script

### [0:00–0:30] THE PROBLEM (Show: Architecture Diagram)

> *"Singapore's MAS requires banks to retain all trade records and communications for 5 years, monitor for insider trading, and file Suspicious Transaction Reports within 15 business days. With millions of daily communications and trades, how do you find the needle in the haystack — and prove compliance at scale?"*

**Screen**: Architecture diagram (S3 → Snowpipe → RAW → Dynamic Tables → AI → Streamlit/QuickSight)

---

### [0:30–1:00] DATA PIPELINE (Show: Snowsight)

> *"Trade records and communications land in Amazon S3 and flow into Snowflake via Snowpipe. Dynamic Tables automatically enrich each communication by cross-referencing the employee watchlist — flagging any message from a restricted person discussing restricted instruments. Zero orchestration, zero scheduling."*

**Screen**: Run in Snowsight:
```sql
SELECT 'TRADES' AS SOURCE, COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.RAW.TRADE_RECORDS
UNION ALL SELECT 'COMMUNICATIONS', COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.RAW.COMMUNICATIONS
UNION ALL SELECT 'FLAGGED EVENTS', COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.CURATED.COMPLIANCE_EVENTS;
```
Expected output: 200 trades, 200 communications, 400 flagged events.

Then show Dynamic Table lineage in Snowsight UI (click on COMPLIANCE_EVENTS → Graph tab).

---

### [1:00–1:30] REGULATION SEARCH (Show: Streamlit Tab 1)

> *"The Compliance Officer starts by searching regulations. 'How long must trade records be retained?' — Cortex Search finds MAS Notice 610 instantly, and Cortex AI generates a grounded answer citing the specific 5-year requirement for trade confirmations, settlement instructions, and voice recordings."*

**Screen**: Tab 1 → Click "How long must trade records be retained under MAS Notice 610?" → Show 5 results with relevance scores → AI Summary paragraph

---

### [1:30–2:00] COMMUNICATION REVIEW (Show: Streamlit Tab 2)

> *"Next, the flagged communication queue. 107 CRITICAL severity events need attention. Here's David Tan emailing about 'DBS position sizing before an announcement.' He's on the restricted list for DBS access to material non-public information. One click sends this to Amazon Bedrock."*

**Screen**: Tab 2 → Filter CRITICAL + HIGH → Select a suspicious communication → Show email body → Click "Review with Amazon Bedrock" → Show response: VIOLATION, CRITICAL severity, escalation required, MAS Notice SFA04-N11 referenced

---

### [2:00–2:30] STR GENERATION (Show: Streamlit Tab 4)

> *"Violation confirmed. Now generate the Suspicious Transaction Report. Bedrock compiles all evidence — flagged emails, restricted trades, existing filings — into a formal MAS-ready STR narrative. What used to take a compliance team 3 days now takes 5 seconds."*

**Screen**: Tab 4 → Select "EMP-001 — David Tan (Equities Trading)" → Show compliance events table → Click "Generate STR with Amazon Bedrock" → Show: STRONG evidence, IMMEDIATE urgency, estimated financial impact, full narrative paragraph

---

### [2:30–3:15] EXECUTIVE VIEW — QUICKSIGHT (Show: QuickSight Dashboard)

> *"The Head of Compliance needs executive visibility. QuickSight connects directly to Snowflake — no ETL, no data movement. Two sheets: Compliance Overview shows 400 flagged events with severity breakdown by employee. Trade Surveillance shows 21 violations across restricted instruments. And with Amazon Q, just ask: 'Which employees have the most critical events?'"*

**Screen**: QuickSight dashboard → Sheet 1 (Compliance Overview): KPI, severity chart, employee chart → Sheet 2 (Trade Surveillance): trades by status, by instrument → Amazon Q bar: "How many critical events by employee?"

---

### [3:15–3:30] CLOSE

> *"One platform. Trade records, communications, and regulatory filings — all governed, all searchable, all AI-ready. Snowflake for the data foundation. Amazon Bedrock for intelligent compliance review. QuickSight for executive reporting. MAS compliance at Singapore scale."*

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
