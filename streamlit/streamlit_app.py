import streamlit as st
import pandas as pd
import json
import re
from snowflake.snowpark.context import get_active_session

session = get_active_session()

st.set_page_config(page_title="MAS Regulatory Compliance", layout="wide")
st.title("MAS Regulatory Compliance & Record Keeping")
st.caption("Singapore FSI Demo — Snowflake + Amazon Bedrock + QuickSight")

with st.sidebar:
    st.markdown("### Architecture")
    st.code("""
┌──────────────────────────┐
│     Amazon S3 Bucket     │
│  (Records + Filings)    │
└─────────┬────────────────┘
          │ Snowpipe
          ▼
┌──────────────────────────┐
│      Snowflake           │
│  ┌────────────────────┐  │
│  │ RAW Schema         │  │
│  │ Trades, Comms,     │  │
│  │ Filings, Watchlist │  │
│  └────────┬───────────┘  │
│           ▼              │
│  ┌────────────────────┐  │
│  │ CURATED Schema     │  │
│  │ Dynamic Tables:    │  │
│  │ • Enriched Comms   │  │
│  │ • Trade Surveill.  │  │
│  │ • Compliance Events│  │
│  └────────┬───────────┘  │
│           ▼              │
│  ┌────────────────────┐  │
│  │ AI Schema          │  │
│  │ • Cortex Search    │  │
│  │ • Bedrock Review   │  │
│  │ • STR Generation   │  │
│  └────────────────────┘  │
└───────────┬──────────────┘
            │ External Access
            ▼
┌──────────────────────────┐
│   Amazon Bedrock         │
│   Claude Sonnet 4        │
└──────────────────────────┘
""", language=None)
    st.divider()
    st.caption("Built for Singapore FSI")

tab1, tab2, tab3, tab4 = st.tabs([
    "Regulation Search",
    "Communication Review",
    "Compliance Dashboard",
    "Regulatory Reports"
])


def parse_result(raw):
    result = str(raw).strip()
    if result.startswith("```"):
        result = re.sub(r"^```(?:json)?\s*", "", result)
        result = re.sub(r"\s*```$", "", result)
    try:
        return json.loads(result)
    except Exception:
        m = re.search(r'\{.*\}', result, re.DOTALL)
        if m:
            try:
                return json.loads(m.group())
            except Exception:
                return {"error": result}
        return {"error": result}


with tab1:
    st.header("Regulation & Policy Search")
    st.markdown("Search across **MAS Notices, internal policies, and compliance documents** using **Snowflake Cortex Search** — semantic RAG for instant regulatory answers.")
    st.divider()

    st.markdown("**Try one of these:**")
    samples = [
        "How long must trade records be retained under MAS Notice 610?",
        "What are the penalties for insider trading in Singapore?",
        "What is the Chinese Wall policy for investment banking?",
        "What are FATCA reporting thresholds for Singapore banks?",
        "What triggers enhanced due diligence under MAS 626?",
        "Can employees trade restricted list securities?",
    ]
    cols = st.columns(3)
    selected = None
    for i, s in enumerate(samples):
        with cols[i % 3]:
            if st.button(s, key=f"search_{i}", use_container_width=True):
                selected = s

    st.divider()
    search_input = st.text_input("Or type your own search:", placeholder="e.g., What are the record retention requirements?")
    query = selected or search_input

    if query:
        st.markdown(f"**Search:** {query}")
        with st.spinner("Searching compliance documents..."):
            try:
                safe_q = query.replace('"', '\\"').replace("'", "''")
                raw = session.sql(f"""
                    SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                        'FSI_REGULATORY_COMPLIANCE.AI.COMPLIANCE_SEARCH_SERVICE',
                        '{{"query": "{safe_q}", "columns": ["CONTENT", "DOC_TYPE", "TITLE", "JURISDICTION"], "limit": 5}}'
                    ) AS RESULTS
                """).collect()[0][0]

                results = json.loads(raw) if isinstance(raw, str) else raw
                hits = results.get("results", [])

                if not hits:
                    st.warning("No matching documents found.")
                else:
                    st.divider()
                    st.markdown(f"**{len(hits)} matching documents found:**")
                    for idx, hit in enumerate(hits):
                        score = hit.get("@scores", {}).get("cosine_similarity", 0)
                        title = hit.get("TITLE", "Unknown")
                        doc_type = hit.get("DOC_TYPE", "Unknown")
                        jurisdiction = hit.get("JURISDICTION", "")
                        content = hit.get("CONTENT", "")

                        relevance = "High" if score > 0.65 else "Medium" if score > 0.55 else "Low"
                        color = "green" if score > 0.65 else "orange" if score > 0.55 else "red"

                        st.markdown(f"### {idx+1}. {title}")
                        st.markdown(f"**Type:** {doc_type} | **Jurisdiction:** {jurisdiction} | **Relevance:** :{color}[{relevance}] ({score:.2f})")
                        st.info(content[:500] + ("..." if len(content) > 500 else ""))

                    st.divider()
                    st.markdown("**AI Summary**")
                    with st.spinner("Generating answer with Cortex AI..."):
                        context_parts = [f"[{h.get('TITLE', '')}]\n{h.get('CONTENT', '')}" for h in hits]
                        context = "\n\n".join(context_parts)
                        safe_ctx = context.replace("'", "''").replace("\\", "\\\\")
                        safe_query = query.replace("'", "''")
                        summary = session.sql(f"""
                            SELECT SNOWFLAKE.CORTEX.COMPLETE('claude-4-sonnet',
                                'You are a regulatory compliance expert at a Singapore MAS-regulated bank.
                                Answer the question based ONLY on the documents below. Be specific about regulatory requirements, thresholds, and penalties.
                                Reference document titles. Write dollar amounts as plain text.

                                QUESTION: {safe_query}

                                DOCUMENTS:
                                {safe_ctx}')
                        """).collect()[0][0]
                        answer = str(summary).strip()
                        if answer.startswith('"') and answer.endswith('"'):
                            answer = answer[1:-1]
                        answer = answer.replace("\\n", "\n").replace('$', '\\$')
                        st.markdown(answer)
            except Exception as e:
                st.error(f"Search error: {e}")


with tab2:
    st.header("Communication Review")
    st.markdown("Review **flagged communications** from the surveillance system. Run AI-powered compliance assessment via **Amazon Bedrock**.")
    st.divider()

    flagged_df = session.sql("""
        SELECT COMM_ID, COMM_TYPE, SENDER_NAME, SUBJECT, SEVERITY, REVIEW_STATUS, COMM_TS,
               RESTRICTION_TYPE, RESTRICTED_INSTRUMENTS
        FROM FSI_REGULATORY_COMPLIANCE.CURATED.ENRICHED_COMMUNICATIONS
        WHERE REVIEW_STATUS != 'CLEAN'
        ORDER BY
            CASE SEVERITY WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END,
            COMM_TS DESC
    """).to_pandas()

    if flagged_df.empty:
        st.info("No flagged communications to review.")
    else:
        sev_counts = flagged_df["SEVERITY"].value_counts()
        c1, c2, c3, c4 = st.columns(4)
        c1.metric("Total Flagged", len(flagged_df))
        c2.metric("Critical", sev_counts.get("CRITICAL", 0))
        c3.metric("High", sev_counts.get("HIGH", 0))
        c4.metric("Medium", sev_counts.get("MEDIUM", 0))

        st.divider()

        severity_filter = st.multiselect("Filter by Severity", ["CRITICAL", "HIGH", "MEDIUM"], default=["CRITICAL", "HIGH"])
        filtered = flagged_df[flagged_df["SEVERITY"].isin(severity_filter)] if severity_filter else flagged_df

        labels = [f"{r['COMM_ID']} — [{r['SEVERITY']}] {r['SENDER_NAME']}: {r['SUBJECT']}" for _, r in filtered.iterrows()]
        if labels:
            selected_label = st.selectbox("Select Communication to Review", labels)
            idx = labels.index(selected_label)
            comm_row = filtered.iloc[idx]
            comm_id = comm_row["COMM_ID"]

            full_comm = session.sql(f"""
                SELECT * FROM FSI_REGULATORY_COMPLIANCE.CURATED.ENRICHED_COMMUNICATIONS WHERE COMM_ID = '{comm_id}'
            """).to_pandas().iloc[0]

            st.divider()
            col_l, col_r = st.columns([2, 1])
            with col_l:
                st.markdown(f"**From:** {full_comm['SENDER_NAME']} ({full_comm['SENDER']})")
                st.markdown(f"**To:** {full_comm['RECIPIENTS']}")
                st.markdown(f"**Subject:** {full_comm['SUBJECT']}")
                st.markdown(f"**Type:** {full_comm['COMM_TYPE']} | **Date:** {full_comm['COMM_TS']}")
                st.divider()
                st.markdown("**Content:**")
                st.warning(full_comm["BODY"])
            with col_r:
                sev = full_comm["SEVERITY"]
                sev_color = {"CRITICAL": "red", "HIGH": "orange", "MEDIUM": "blue"}.get(sev, "gray")
                st.markdown(f"### Severity: :{sev_color}[{sev}]")
                st.markdown(f"**Status:** {full_comm['REVIEW_STATUS']}")
                if full_comm.get("RESTRICTION_TYPE"):
                    st.markdown(f"**Watchlist:** {full_comm['RESTRICTION_TYPE']}")
                    st.markdown(f"**Restricted:** {full_comm['RESTRICTED_INSTRUMENTS']}")

            st.divider()
            if st.button("Review with Amazon Bedrock", type="primary", use_container_width=True):
                with st.spinner("Amazon Bedrock analyzing communication..."):
                    raw = session.sql(f"CALL FSI_REGULATORY_COMPLIANCE.AI.REVIEW_COMMUNICATION('{comm_id}')").collect()[0][0]
                    result = parse_result(raw)

                if "error" in result:
                    st.error(f"Bedrock error: {result['error']}")
                else:
                    assessment = result.get("assessment", "UNKNOWN")
                    a_color = {"VIOLATION": "red", "POTENTIAL_VIOLATION": "orange", "SUSPICIOUS": "yellow", "CLEAR": "green"}.get(assessment, "gray")
                    st.markdown(f"### Assessment: :{a_color}[{assessment}]")
                    st.markdown(f"**Severity:** {result.get('severity', 'N/A')}")
                    st.markdown(f"**Escalation Required:** {'Yes' if result.get('escalation_required') else 'No'}")
                    reasoning = result.get("reasoning", "").replace('$', '\\$')
                    st.info(f"**Reasoning:** {reasoning}")
                    if result.get("violation_types"):
                        st.markdown("**Violation Types:** " + ", ".join(result["violation_types"]))
                    if result.get("recommended_actions"):
                        st.markdown("**Recommended Actions:**")
                        for a in result["recommended_actions"]:
                            st.markdown(f"- {a}")
                    if result.get("regulatory_references"):
                        st.markdown("**Regulatory References:** " + ", ".join(result["regulatory_references"]))


with tab3:
    st.header("Compliance Dashboard")

    kpi_df = session.sql("""
        SELECT
            (SELECT COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.RAW.TRADE_RECORDS) +
            (SELECT COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.RAW.COMMUNICATIONS) +
            (SELECT COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.RAW.REGULATORY_FILINGS) AS TOTAL_RECORDS,
            (SELECT COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.CURATED.COMPLIANCE_EVENTS) AS TOTAL_FLAGGED,
            (SELECT COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.CURATED.COMPLIANCE_EVENTS WHERE SEVERITY = 'CRITICAL') AS CRITICAL_COUNT,
            (SELECT COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.RAW.EMPLOYEE_WATCHLIST) AS WATCHLIST_SIZE,
            (SELECT COUNT(*) FROM FSI_REGULATORY_COMPLIANCE.RAW.REGULATORY_FILINGS WHERE STATUS = 'FILED') AS FILINGS_SUBMITTED
    """).to_pandas()

    c1, c2, c3, c4, c5 = st.columns(5)
    c1.metric("Total Records", f"{kpi_df['TOTAL_RECORDS'].iloc[0]:,}")
    c2.metric("Flagged Events", f"{kpi_df['TOTAL_FLAGGED'].iloc[0]:,}")
    c3.metric("Critical", f"{kpi_df['CRITICAL_COUNT'].iloc[0]}")
    c4.metric("Watchlist", f"{kpi_df['WATCHLIST_SIZE'].iloc[0]}")
    c5.metric("STRs Filed", f"{kpi_df['FILINGS_SUBMITTED'].iloc[0]}")

    st.divider()

    col_left, col_right = st.columns(2)
    with col_left:
        st.subheader("Events by Severity")
        sev_df = session.sql("""
            SELECT SEVERITY, COUNT(*) AS CNT
            FROM FSI_REGULATORY_COMPLIANCE.CURATED.COMPLIANCE_EVENTS
            GROUP BY SEVERITY ORDER BY
                CASE SEVERITY WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END
        """).to_pandas()
        st.bar_chart(sev_df.set_index("SEVERITY")["CNT"])

    with col_right:
        st.subheader("Events by Type")
        type_df = session.sql("""
            SELECT EVENT_TYPE, COUNT(*) AS CNT
            FROM FSI_REGULATORY_COMPLIANCE.CURATED.COMPLIANCE_EVENTS
            GROUP BY EVENT_TYPE
        """).to_pandas()
        st.bar_chart(type_df.set_index("EVENT_TYPE")["CNT"])

    st.divider()

    col_l2, col_r2 = st.columns(2)
    with col_l2:
        st.subheader("Flagged by Employee")
        emp_df = session.sql("""
            SELECT EMPLOYEE_NAME, COUNT(*) AS CNT
            FROM FSI_REGULATORY_COMPLIANCE.CURATED.COMPLIANCE_EVENTS
            GROUP BY EMPLOYEE_NAME ORDER BY CNT DESC LIMIT 10
        """).to_pandas()
        st.bar_chart(emp_df.set_index("EMPLOYEE_NAME")["CNT"])

    with col_r2:
        st.subheader("Record Retention Status")
        ret_df = session.sql("""
            SELECT RECORD_TYPE, TOTAL_RECORDS, RECORDS_PAST_RETENTION, RETENTION_YEARS, REGULATION
            FROM FSI_REGULATORY_COMPLIANCE.CURATED.RECORD_RETENTION_STATUS
        """).to_pandas()
        st.table(ret_df.set_index("RECORD_TYPE"))

    st.divider()
    st.subheader("Recent Compliance Events")
    events_df = session.sql("""
        SELECT EVENT_ID, EVENT_TYPE, EMPLOYEE_NAME, DESCRIPTION, SEVERITY, STATUS, EVENT_TS
        FROM FSI_REGULATORY_COMPLIANCE.CURATED.COMPLIANCE_EVENTS
        ORDER BY EVENT_TS DESC LIMIT 20
    """).to_pandas()
    st.dataframe(events_df, use_container_width=True)


with tab4:
    st.header("Regulatory Reports")
    st.markdown("Generate a **Suspicious Transaction Report (STR)** narrative using **Amazon Bedrock** for any employee on the watchlist.")
    st.divider()

    watchlist_df = session.sql("""
        SELECT EMPLOYEE_ID, EMPLOYEE_NAME, DEPARTMENT, RESTRICTION_TYPE, RESTRICTED_INSTRUMENTS, REASON
        FROM FSI_REGULATORY_COMPLIANCE.RAW.EMPLOYEE_WATCHLIST
        ORDER BY EMPLOYEE_ID
    """).to_pandas()

    st.subheader("Employee Watchlist")
    st.dataframe(watchlist_df, use_container_width=True)

    st.divider()

    labels = [f"{r['EMPLOYEE_ID']} — {r['EMPLOYEE_NAME']} ({r['DEPARTMENT']})" for _, r in watchlist_df.iterrows()]
    selected_emp = st.selectbox("Select Employee for STR Generation", labels)
    emp_id = selected_emp.split(" — ")[0]

    emp_events = session.sql(f"""
        SELECT EVENT_TYPE, DESCRIPTION, SEVERITY, EVENT_TS
        FROM FSI_REGULATORY_COMPLIANCE.CURATED.COMPLIANCE_EVENTS
        WHERE EMPLOYEE_ID = '{emp_id}'
        ORDER BY EVENT_TS DESC LIMIT 10
    """).to_pandas()

    if not emp_events.empty:
        st.markdown(f"**{len(emp_events)} compliance events for {selected_emp}:**")
        st.dataframe(emp_events, use_container_width=True)
    else:
        st.info("No compliance events found for this employee.")

    st.divider()

    filings_df = session.sql("""
        SELECT FILING_ID, FILING_TYPE, TITLE, STATUS, FILED_DATE
        FROM FSI_REGULATORY_COMPLIANCE.RAW.REGULATORY_FILINGS
        ORDER BY FILED_DATE DESC
    """).to_pandas()
    st.subheader("Regulatory Filings")
    st.dataframe(filings_df, use_container_width=True)

    st.divider()

    if st.button("Generate STR with Amazon Bedrock", type="primary", use_container_width=True):
        with st.spinner("Amazon Bedrock generating Suspicious Transaction Report..."):
            raw = session.sql(f"CALL FSI_REGULATORY_COMPLIANCE.AI.GENERATE_STR('{emp_id}')").collect()[0][0]
            result = parse_result(raw)

        if "error" in result:
            st.error(f"Error: {result['error']}")
        else:
            st.success("STR Generated Successfully")
            col1, col2, col3 = st.columns(3)
            col1.metric("Evidence Strength", result.get("evidence_strength", "N/A"))
            col2.metric("Filing Urgency", result.get("filing_urgency", "N/A"))
            col3.metric("Est. Impact (SGD)", f"${result.get('estimated_financial_impact_sgd', 0):,.0f}")

            st.divider()
            st.markdown("### Summary")
            summary = result.get("summary", "").replace('$', '\\$')
            st.info(summary)

            st.markdown("### STR Narrative")
            narrative = result.get("str_narrative", "").replace('$', '\\$')
            st.markdown(narrative)

            if result.get("violation_categories"):
                st.markdown("### Violation Categories")
                for v in result["violation_categories"]:
                    st.markdown(f"- {v}")

            if result.get("recommended_actions"):
                st.markdown("### Recommended Actions")
                for a in result["recommended_actions"]:
                    st.markdown(f"- {a}")
