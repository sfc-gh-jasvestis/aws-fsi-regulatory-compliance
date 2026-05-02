# Demo Script: MAS Regulatory Compliance & Record Keeping

## Duration: 3.5 minutes (recorded demo)

---

## Act 1: The Problem (0:00 - 0:30)

### Voiceover:
"Singapore's MAS requires banks to retain all trade records and communications for 5 years, monitor for insider trading, and file Suspicious Transaction Reports within 15 business days. With millions of daily communications and trades, how do you find the needle in the haystack — and prove compliance at scale?"

### Visual:
Architecture diagram showing S3 + Snowflake + Bedrock + QuickSight integration.

---

## Act 2: Data Pipeline (0:30 - 1:00)

### Voiceover:
"Trade records and communications land in Amazon S3 and flow into Snowflake via Snowpipe. Dynamic Tables automatically enrich each communication by cross-referencing the employee watchlist — flagging any message from a restricted person discussing restricted instruments. No orchestration needed."

### Visual:
Snowsight showing:
- RAW schema: 200 trades, 200 communications, 15 filings, 10 watchlist entries
- CURATED schema: Dynamic Tables refreshing every 5 minutes
- COMPLIANCE_EVENTS: 400 flagged events with severity scoring

---

## Act 3: Persona 1 — Compliance Officer (1:00 - 2:30)

### Scene 1: Regulation Search (1:00 - 1:30)
**Voiceover:** "First, the Compliance Officer uses Cortex Search to instantly find the relevant MAS Notice. Ask: 'How long must trade records be retained?' — and get a grounded AI answer citing MAS Notice 610."

**Action:** Tab 1 → Type query → Show results with relevance scores → AI summary

### Scene 2: Communication Review (1:30 - 2:00)
**Voiceover:** "Next, review a flagged communication. This email from David Tan mentions DBS position sizing before an announcement — and he's on the watchlist for DBS access to MNPI. One click sends this to Amazon Bedrock for assessment."

**Action:** Tab 2 → Select CRITICAL severity comm → Click "Review with Amazon Bedrock" → Show VIOLATION assessment with regulatory references

### Scene 3: STR Generation (2:00 - 2:30)
**Voiceover:** "When violations are confirmed, generate a formal Suspicious Transaction Report. Bedrock compiles evidence from flagged communications, restricted trades, and existing filings into a MAS-ready STR narrative — in seconds, not days."

**Action:** Tab 4 → Select employee → Click "Generate STR" → Show narrative + urgency + evidence strength

---

## Act 4: Compliance Dashboard (2:30 - 3:15)

### Voiceover:
"The dashboard gives executive visibility: 415 total records under management, 400 flagged events, critical violations by employee and department. Record retention is at 100% compliance — MAS Notice 610 covered."

### Visual:
Tab 3 — KPIs, severity charts, employee breakdown, retention status table

---

## Act 5: Close (3:15 - 3:30)

### Voiceover:
"One platform. Trade records, communications, and regulatory filings — all governed, all searchable, all AI-ready. Snowflake for the data foundation, Amazon Bedrock for intelligent compliance review, and QuickSight for executive reporting. MAS compliance at scale."

---

## Demo Day Checklist

- [ ] Bedrock secret populated with valid AWS credentials
- [ ] Dynamic Tables showing ACTIVE status
- [ ] Cortex Search service responding to queries
- [ ] At least 5 CRITICAL/HIGH severity communications visible
- [ ] Regulatory filings showing STR and FATCA entries

## Key Demo Questions to Anticipate

1. "How is this different from existing e-discovery tools?"
   → Real-time Dynamic Tables vs batch processing. AI-native with Bedrock + Cortex.

2. "How does it handle voice recordings?"
   → S3 can store transcripts from Amazon Transcribe; Snowpipe ingests them identically.

3. "What about PDPA (Singapore data privacy)?"
   → Horizon governance with masking policies on PII columns. Role-based access control.

4. "How fast is the Bedrock review?"
   → ~3-5 seconds per communication. Batch review possible for bulk processing.
