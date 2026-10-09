-- ============================================================================
-- 06_INTELLIGENCE.SQL - search, anomaly detection, semantic view, agent,
-- live-event alert and on-demand refresh DAG.
-- Run with snowflake/run_intelligence.py (substitutes validated __DEMO_DB__ /
-- __DEMO_WH__ / __ALERT_EMAIL__). Requires 00-05, plus 08 (Snowflake only) or
-- aws/setup_aws.py (AWS build) for RAW.LIVE_EVENTS.
-- Alerts and tasks are created SUSPENDED; run them with EXECUTE ALERT / EXECUTE TASK.
-- ============================================================================
USE DATABASE __DEMO_DB__;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;

-- ---------- Synthetic surveillance knowledge base (clearly synthetic SOPs) ----------
-- These are internal procedures of a fictional bank, not regulatory text.
CREATE OR REPLACE TABLE SEARCH.SURVEILLANCE_DOCS AS
WITH rules AS (
  SELECT DISTINCT r.DETECTION_RULE, e.DESK
  FROM RAW.EMPLOYEE_DAILY r JOIN RAW.EMPLOYEES e ON e.ID = r.ENTITY_ID
  WHERE r.CONFIRMED_COUNT > 0
)
SELECT
  'SOP-' || LPAD(ROW_NUMBER() OVER (ORDER BY DESK, DETECTION_RULE)::VARCHAR, 3, '0') AS DOC_ID,
  'SOP' AS DOC_TYPE,
  DESK,
  DETECTION_RULE,
  DESK || ' desk - ' || DETECTION_RULE || ' alert review' AS TITLE,
  'Synthetic demo SOP for a fictional bank. Desk: ' || DESK || '. Detection rule: ' || DETECTION_RULE || '. '
  || 'Step 1: open a surveillance case, link the alert and preserve the related communications and trade records. '
  || 'Step 2: ' || CASE
       WHEN DETECTION_RULE = 'Front-running' THEN 'compare the employee''s own or proprietary orders with client orders in the same instrument in the 30 minutes before each client order.'
       WHEN DETECTION_RULE = 'Insider-information keyword' THEN 'read the flagged messages in context, identify the instrument referred to, and check whether it was on the watch or restricted list at the time.'
       WHEN DETECTION_RULE = 'Restricted-list trade' THEN 'confirm the instrument was on the restricted list at execution time and whether a pre-clearance exception was approved.'
       WHEN DETECTION_RULE = 'Off-channel communication' THEN 'identify the unapproved channel referenced in captured messages, request the employee''s attestation and recover the business communications to an approved archive.'
       WHEN DETECTION_RULE = 'Wash trade' THEN 'pull matched trades where both sides trace to the same book or linked counterparties, and check for a legitimate risk-transfer reason.'
       WHEN DETECTION_RULE = 'Personal account dealing' THEN 'compare personal-account trades with the pre-clearance log and the desk''s client activity in the same instrument.'
       ELSE 'review the alerted activity against the employee''s role and escalate if unexplained.'
     END
  || ' Step 3: if after-hours messaging exceeds 20% of the day''s messages or the flagged-term rate exceeds 6 per 100 messages after review, keep the case open and notify the supervisor. '
  || 'Step 4: record the disposition; if a breach is confirmed, escalate the case to the compliance investigations team for a decision on further reporting.' AS CONTENT
FROM rules;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.SURVEILLANCE_SOP_SEARCH
  ON CONTENT
  ATTRIBUTES DESK, DETECTION_RULE
  WAREHOUSE = __DEMO_WH__
  TARGET_LAG = '7 days'
AS (SELECT DOC_ID, TITLE, DESK, DETECTION_RULE, CONTENT FROM SEARCH.SURVEILLANCE_DOCS);

-- ---------- After-hours messaging anomaly detection (train first 75 days, detect last 15) ----------
CREATE OR REPLACE VIEW ML.AFTER_HOURS_SERIES AS
SELECT ENTITY_ID, EVENT_DATE::TIMESTAMP_NTZ AS TS, AFTER_HOURS_PCT::FLOAT AS AFTER_HOURS
FROM RAW.EMPLOYEE_DAILY;
CREATE OR REPLACE VIEW ML.AFTER_HOURS_TRAIN AS
SELECT * FROM ML.AFTER_HOURS_SERIES WHERE TS < (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.AFTER_HOURS_SERIES);
CREATE OR REPLACE VIEW ML.AFTER_HOURS_DETECT AS
SELECT * FROM ML.AFTER_HOURS_SERIES WHERE TS >= (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.AFTER_HOURS_SERIES);

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION ML.AFTER_HOURS_ANOMALY_MODEL(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.AFTER_HOURS_TRAIN'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'AFTER_HOURS',
  LABEL_COLNAME => '');

CREATE OR REPLACE TABLE ML.AFTER_HOURS_ANOMALIES AS
SELECT SERIES::VARCHAR AS ENTITY_ID, TS::DATE AS EVENT_DATE, Y AS AFTER_HOURS, FORECAST AS EXPECTED,
       LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, PERCENTILE
FROM TABLE(ML.AFTER_HOURS_ANOMALY_MODEL!DETECT_ANOMALIES(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.AFTER_HOURS_DETECT'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'AFTER_HOURS'));

-- ---------- Semantic view ----------
CREATE OR REPLACE SEMANTIC VIEW APP.COMPLIANCE_ANALYTICS
  TABLES (
    employees AS CURATED.PERFORMANCE_SUMMARY PRIMARY KEY (ENTITY_ID)
      COMMENT = 'One row per front-office employee, 90-day totals',
    risk AS ML.BREACH_RISK_SCORES PRIMARY KEY (ENTITY_ID)
      COMMENT = 'Latest next-7-day conduct-breach probability per employee',
    rules AS CURATED.RULE_SUMMARY PRIMARY KEY (DETECTION_RULE)
      COMMENT = 'Alerts, confirmed breaches and escalated cases by detection rule, 90 days',
    daily AS CURATED.TREND_ANALYSIS PRIMARY KEY (METRIC_DATE)
      COMMENT = 'Bank-wide totals per day'
  )
  RELATIONSHIPS (risk_employee AS risk (ENTITY_ID) REFERENCES employees)
  FACTS (
    employees.alerts_f AS ALERT_COUNT,
    employees.confirmed_f AS CONFIRMED_COUNT,
    employees.escalated_f AS ESCALATED_COUNT,
    employees.messages_f AS MESSAGE_COUNT,
    employees.trades_f AS TRADE_COUNT,
    employees.notional_f AS NOTIONAL_SGD,
    employees.review_due_f AS REVIEW_DUE,
    employees.review_done_f AS REVIEW_COMPLETED,
    risk.breach_prob_f AS BREACH_PROB_7D,
    rules.rule_alerts_f AS ALERT_COUNT,
    rules.rule_confirmed_f AS CONFIRMED_COUNT,
    rules.rule_escalated_f AS ESCALATED_COUNT,
    rules.rule_notional_f AS FLAGGED_NOTIONAL_SGD,
    daily.day_alerts_f AS ALERT_COUNT,
    daily.day_confirmed_f AS CONFIRMED_COUNT,
    daily.day_messages_f AS MESSAGE_COUNT
  )
  DIMENSIONS (
    employees.employee_id AS ENTITY_ID WITH SYNONYMS = ('employee', 'trader', 'staff id', 'entity'),
    employees.employee_name AS ENTITY_NAME,
    employees.desk AS DESK WITH SYNONYMS = ('trading desk', 'business line', 'team'),
    employees.seniority AS SENIORITY WITH SYNONYMS = ('rank', 'title', 'grade'),
    employees.on_watchlist AS ON_WATCHLIST COMMENT = '1 if the employee is on the internal conduct watchlist',
    risk.risk_band AS RISK_BAND COMMENT = 'High >= 0.5, Medium >= 0.25, else Low',
    risk.scored_as_of AS SCORED_AS_OF,
    rules.detection_rule AS DETECTION_RULE WITH SYNONYMS = ('rule', 'scenario', 'typology'),
    daily.metric_date AS METRIC_DATE
  )
  METRICS (
    employees.employee_count AS COUNT(employees.employee_id) WITH SYNONYMS = ('number of employees', 'headcount', 'entities'),
    employees.alert_precision_pct AS 100 * SUM(employees.confirmed_f) / NULLIF(SUM(employees.alerts_f), 0)
      COMMENT = 'Confirmed breaches / alerts raised',
    employees.alerts_raised AS SUM(employees.alerts_f) WITH SYNONYMS = ('alerts', 'alert volume'),
    employees.confirmed_breaches AS SUM(employees.confirmed_f) WITH SYNONYMS = ('true positives', 'confirmed alerts', 'breaches'),
    employees.cases_escalated AS SUM(employees.escalated_f) WITH SYNONYMS = ('escalations', 'escalated cases'),
    employees.communications_captured AS SUM(employees.messages_f) WITH SYNONYMS = ('messages', 'communications'),
    employees.trades AS SUM(employees.trades_f),
    employees.total_notional_sgd AS SUM(employees.notional_f) WITH SYNONYMS = ('volume', 'traded value'),
    employees.review_compliance_pct AS 100 * SUM(employees.review_done_f) / NULLIF(SUM(employees.review_due_f), 0)
      COMMENT = 'Supervisory reviews completed / reviews due',
    risk.avg_breach_prob AS AVG(risk.breach_prob_f),
    rules.rule_alerts AS SUM(rules.rule_alerts_f),
    rules.rule_confirmed AS SUM(rules.rule_confirmed_f),
    rules.rule_escalated AS SUM(rules.rule_escalated_f),
    rules.rule_precision_pct AS 100 * SUM(rules.rule_confirmed_f) / NULLIF(SUM(rules.rule_alerts_f), 0),
    daily.daily_alerts AS SUM(daily.day_alerts_f),
    daily.daily_confirmed AS SUM(daily.day_confirmed_f),
    daily.daily_messages AS SUM(daily.day_messages_f)
  )
  COMMENT = 'Synthetic Singapore bank conduct surveillance analytics (demo)';

-- ---------- Cortex Agent ----------
CREATE OR REPLACE AGENT APP.COMPLIANCE_AGENT
  COMMENT = 'Conduct surveillance assistant over a synthetic Singapore bank'
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-5
instructions:
  response: "Answer only from tool results. State that data is synthetic. Give employee IDs and numbers with units. Do not state regulatory requirements; refer to the bank's internal SOPs."
  orchestration: "Use compliance_analyst for employees, desks, alerts, confirmed breaches, escalated cases, alert precision, supervisory review compliance, detection rules and breach risk. Use sop_search for review procedures."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: compliance_analyst
      description: "Employees, alerts, confirmed breaches, escalated cases, alert precision, communications captured, notional, review compliance, detection rules and conduct-breach risk scores"
  - tool_spec:
      type: cortex_search
      name: sop_search
      description: "Synthetic surveillance alert-review SOPs by desk and detection rule"
tool_resources:
  compliance_analyst:
    semantic_view: __DEMO_DB__.APP.COMPLIANCE_ANALYTICS
    execution_environment:
      type: warehouse
      warehouse: __DEMO_WH__
  sop_search:
    name: __DEMO_DB__.SEARCH.SURVEILLANCE_SOP_SEARCH
    max_results: 3
    id_column: DOC_ID
    title_column: TITLE
$$;

-- ---------- Live-event alert ----------
CREATE TABLE IF NOT EXISTS APP.ALERT_LOG (
  ALERTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), EMPLOYEE_ID VARCHAR,
  EVENT_TS TIMESTAMP_NTZ, CHANNEL VARCHAR, FLAGGED_TERMS NUMBER, SOP_HINT VARCHAR);

CREATE OR REPLACE NOTIFICATION INTEGRATION SG_REGCOMP_EMAIL_INT
  TYPE = EMAIL ENABLED = TRUE ALLOWED_RECIPIENTS = ('__ALERT_EMAIL__');

CREATE OR REPLACE PROCEDURE APP.LOG_LIVE_ALERTS()
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  n NUMBER;
BEGIN
  INSERT INTO APP.ALERT_LOG (EMPLOYEE_ID, EVENT_TS, CHANNEL, FLAGGED_TERMS, SOP_HINT)
    SELECT t.EMPLOYEE_ID, t.EVENT_TS, t.CHANNEL, t.FLAGGED_TERMS,
           'Check ' || e.DESK || ' desk SOPs; current risk band ' || COALESCE(r.RISK_BAND, 'n/a')
    FROM RAW.LIVE_EVENTS t
    JOIN RAW.EMPLOYEES e ON e.ID = t.EMPLOYEE_ID
    LEFT JOIN ML.BREACH_RISK_SCORES r ON r.ENTITY_ID = t.EMPLOYEE_ID
    WHERE t.STATUS = 'ALERT'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.EMPLOYEE_ID = t.EMPLOYEE_ID AND l.EVENT_TS = t.EVENT_TS);
  n := SQLROWCOUNT;
  IF (n > 0) THEN
    CALL SYSTEM$SEND_EMAIL('SG_REGCOMP_EMAIL_INT', '__ALERT_EMAIL__',
      '[Demo] Conduct surveillance alert',
      'New live surveillance alerts logged in APP.ALERT_LOG: ' || :n || '. Data is synthetic.');
  END IF;
  RETURN n;
END;
$$;

CREATE OR REPLACE ALERT APP.LIVE_EVENT_ALERT
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM RAW.LIVE_EVENTS t
    WHERE t.STATUS = 'ALERT'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.EMPLOYEE_ID = t.EMPLOYEE_ID AND l.EVENT_TS = t.EVENT_TS)))
  THEN CALL APP.LOG_LIVE_ALERTS();

-- ---------- On-demand refresh DAG (suspended; run with EXECUTE TASK APP.TASK_REFRESH_CURATED) ----------
CREATE OR REPLACE PROCEDURE APP.REFRESH_CURATED()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  ALTER DYNAMIC TABLE CURATED.PERFORMANCE_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.TREND_ANALYSIS REFRESH;
  ALTER DYNAMIC TABLE CURATED.RULE_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.KPI_SUMMARY REFRESH;
  RETURN 'refreshed';
END;
$$;

CREATE OR REPLACE TASK APP.TASK_REFRESH_CURATED
  WAREHOUSE = __DEMO_WH__
AS
  CALL APP.REFRESH_CURATED();

CREATE OR REPLACE TASK APP.TASK_RESCORE_RISK
  WAREHOUSE = __DEMO_WH__
  AFTER APP.TASK_REFRESH_CURATED
AS
  CREATE OR REPLACE TABLE ML.BREACH_RISK_SCORES COPY GRANTS AS
  WITH latest AS (
    SELECT * FROM ML.BREACH_FEATURES QUALIFY ROW_NUMBER() OVER (PARTITION BY ENTITY_ID ORDER BY EVENT_DATE DESC) = 1
  ), p AS (
    SELECT ENTITY_ID, EVENT_DATE,
           ML.BREACH_RISK_MODEL!PREDICT(INPUT_DATA => OBJECT_CONSTRUCT(
             'DESK', DESK, 'ON_WATCHLIST', ON_WATCHLIST, 'YEARS_AT_FIRM', YEARS_AT_FIRM,
             'AFTER_HOURS_PCT', AFTER_HOURS_PCT, 'FLAGGED_TERM_RATE', FLAGGED_TERM_RATE,
             'AFTER_HOURS_7D', AFTER_HOURS_7D, 'CONFIRMED_30D', CONFIRMED_30D)) AS PRED
    FROM latest
  )
  SELECT ENTITY_ID, EVENT_DATE AS SCORED_AS_OF, ROUND(PRED:probability:BREACH::FLOAT, 4) AS BREACH_PROB_7D,
         CASE WHEN PRED:probability:BREACH::FLOAT >= 0.5 THEN 'High'
              WHEN PRED:probability:BREACH::FLOAT >= 0.25 THEN 'Medium' ELSE 'Low' END AS RISK_BAND,
         CURRENT_TIMESTAMP() AS SCORED_AT
  FROM p;
