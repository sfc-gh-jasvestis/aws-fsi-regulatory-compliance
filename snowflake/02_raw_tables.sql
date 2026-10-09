-- Synthetic employee-day surveillance observations for a fictional Singapore bank.
-- Nothing is seeded as a prediction. Randomness is HASH-seeded, so every rebuild
-- is reproducible: per-employee breach propensity, drift between supervisory
-- reviews, missed reviews, desk-weighted detection rules, false-positive alerts,
-- watchlist effects, and two market-wide news events.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

CREATE TABLE RAW.EMPLOYEES AS
WITH employees AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS EMPLOYEE_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 40))
), draws AS (
  SELECT EMPLOYEE_INDEX,
         MOD(ABS(HASH(EMPLOYEE_INDEX, 'tenure')), 1000000) / 1e6 AS U_TENURE,
         MOD(ABS(HASH(EMPLOYEE_INDEX, 'rate')), 1000000) / 1e6 AS U_RATE,
         MOD(ABS(HASH(EMPLOYEE_INDEX, 'review')), 1000000) / 1e6 AS U_REVIEW,
         MOD(ABS(HASH(EMPLOYEE_INDEX, 'discipline')), 1000000) / 1e6 AS U_DISCIPLINE,
         MOD(ABS(HASH(EMPLOYEE_INDEX, 'watch')), 1000000) / 1e6 AS U_WATCH
  FROM employees
)
SELECT 'EMP-' || LPAD(EMPLOYEE_INDEX::VARCHAR, 4, '0') AS ID,
       'Synthetic employee ' || LPAD(EMPLOYEE_INDEX::VARCHAR, 4, '0') AS NAME,
       -- Deterministic spread (5 and 8 are coprime): every seniority and desk is present.
       CASE MOD(EMPLOYEE_INDEX, 5) WHEN 0 THEN 'Analyst' WHEN 1 THEN 'Associate'
            WHEN 2 THEN 'Vice President' WHEN 3 THEN 'Director' ELSE 'Managing Director' END AS SENIORITY,
       CASE MOD(EMPLOYEE_INDEX, 8) WHEN 0 THEN 'Equities' WHEN 1 THEN 'Equities' WHEN 2 THEN 'Equities'
            WHEN 3 THEN 'FX' WHEN 4 THEN 'FX' WHEN 5 THEN 'Rates'
            WHEN 6 THEN 'Credit' ELSE 'Wealth Advisory' END AS DESK,
       EMPLOYEE_INDEX,
       IFF(U_WATCH < 0.25, 1, 0) AS ON_WATCHLIST,
       ROUND(0.5 + U_TENURE * 14.5, 1) AS YEARS_AT_FIRM,
       -- Base daily probability of a policy breach 0.4%-3%; ~15% of employees
       -- are repeat offenders (x3), and watchlisted employees x1.5.
       (0.004 + U_RATE * 0.026) * IFF(U_RATE > 0.85, 3, 1) * IFF(U_WATCH < 0.25, 1.5, 1) AS BASE_BREACH_RATE,
       7 * (1 + FLOOR(U_REVIEW * 3)) AS REVIEW_INTERVAL_DAYS,
       0.55 + U_DISCIPLINE * 0.45 AS REVIEW_COMPLETION_PROB,
       'Active' AS STATUS
FROM draws;

CREATE TABLE RAW.EMPLOYEE_DAILY AS
WITH days AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS DAY_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 90))
), market_events AS (
  -- Two market-wide news events; every employee on the desk is alerted.
  SELECT * FROM VALUES (27, 'Equities'), (64, 'FX') AS o(DAY_INDEX, DESK)
), base AS (
  SELECT e.ID AS ENTITY_ID, e.EMPLOYEE_INDEX, e.DESK, e.YEARS_AT_FIRM,
         e.BASE_BREACH_RATE, e.REVIEW_INTERVAL_DAYS, e.REVIEW_COMPLETION_PROB,
         d.DAY_INDEX,
         DATEADD('day', d.DAY_INDEX - 89, CURRENT_DATE()) AS EVENT_DATE,
         MOD(d.DAY_INDEX + e.EMPLOYEE_INDEX * 5, e.REVIEW_INTERVAL_DAYS) AS DAYS_SINCE_REVIEW,
         MOD(ABS(HASH(e.ID, d.DAY_INDEX, 'sus')), 1000000) / 1e6 AS U_SUS,
         MOD(ABS(HASH(e.ID, d.DAY_INDEX, 'detect')), 1000000) / 1e6 AS U_DETECT,
         MOD(ABS(HASH(e.ID, d.DAY_INDEX, 'fp')), 1000000) / 1e6 AS U_FP,
         MOD(ABS(HASH(e.ID, d.DAY_INDEX, 'rule')), 1000000) / 1e6 AS U_RULE,
         MOD(ABS(HASH(e.ID, d.DAY_INDEX, 'done')), 1000000) / 1e6 AS U_DONE,
         MOD(ABS(HASH(e.ID, d.DAY_INDEX, 'trades')), 1000000) / 1e6 AS U_TRADES,
         MOD(ABS(HASH(e.ID, d.DAY_INDEX, 'noise')), 1000000) / 1e6 AS U_NOISE,
         MOD(ABS(HASH(e.ID, d.DAY_INDEX, 'esc')), 1000000) / 1e6 AS U_ESC,
         m.DESK IS NOT NULL AS MARKET_EVENT
  FROM RAW.EMPLOYEES e CROSS JOIN days d
  LEFT JOIN market_events m ON m.DAY_INDEX = d.DAY_INDEX AND m.DESK = e.DESK
), review AS (
  SELECT *,
         IFF(DAYS_SINCE_REVIEW = 0, 1, 0) AS REVIEW_DUE,
         IFF(DAYS_SINCE_REVIEW = 0 AND U_DONE < REVIEW_COMPLETION_PROB, 1, 0) AS REVIEW_COMPLETED,
         -- Conduct drift rises between supervisory reviews; weak review discipline carries it over.
         DAYS_SINCE_REVIEW / REVIEW_INTERVAL_DAYS + (1 - REVIEW_COMPLETION_PROB) AS DRIFT
  FROM base
), activity AS (
  SELECT *,
         CASE WHEN U_SUS < LEAST(0.5, BASE_BREACH_RATE * (0.4 + 1.6 * DRIFT) * (1 + 1 / (1 + YEARS_AT_FIRM))) / 4 THEN 2
              WHEN U_SUS < LEAST(0.5, BASE_BREACH_RATE * (0.4 + 1.6 * DRIFT) * (1 + 1 / (1 + YEARS_AT_FIRM))) THEN 1
              ELSE 0 END AS BREACH_COUNT
  FROM review
), alerts AS (
  SELECT *,
         -- Rules catch about 85% of breaches; the rest goes undetected.
         IFF(MARKET_EVENT, 0, IFF(U_DETECT < 0.85, BREACH_COUNT, 0)) AS CONFIRMED_COUNT,
         -- False positives: higher for high-volume desks.
         IFF(MARKET_EVENT, 1, IFF(U_FP < CASE DESK WHEN 'Equities' THEN 0.14 WHEN 'FX' THEN 0.12
                                                   WHEN 'Rates' THEN 0.10 WHEN 'Credit' THEN 0.10
                                                   ELSE 0.08 END, 1, 0)) AS FALSE_POSITIVE_COUNT
  FROM activity
), measured AS (
  SELECT *,
         CONFIRMED_COUNT + FALSE_POSITIVE_COUNT AS ALERT_COUNT,
         ROUND(CASE DESK WHEN 'Equities' THEN 60 WHEN 'FX' THEN 120 WHEN 'Rates' THEN 25
                         WHEN 'Credit' THEN 15 ELSE 10 END
               * (0.7 + 0.6 * U_TRADES) * (1 + 0.5 * BREACH_COUNT)) AS TRADE_COUNT,
         ROUND(CASE DESK WHEN 'Wealth Advisory' THEN 140 ELSE 90 END
               * (0.7 + 0.6 * U_NOISE) * (1 + 0.6 * BREACH_COUNT)) AS MESSAGE_COUNT,
         CASE DESK WHEN 'Equities' THEN 85000 WHEN 'FX' THEN 1200000 WHEN 'Rates' THEN 5000000
                   WHEN 'Credit' THEN 900000 ELSE 150000 END
           * (0.8 + 0.4 * U_NOISE) AS AVG_TICKET_SGD
  FROM alerts
)
SELECT ENTITY_ID || '-' || TO_CHAR(EVENT_DATE, 'YYYYMMDD') AS EVENT_ID,
       ENTITY_ID, EVENT_DATE,
       MESSAGE_COUNT, TRADE_COUNT,
       ROUND(TRADE_COUNT * AVG_TICKET_SGD, 2) AS NOTIONAL_SGD,
       ALERT_COUNT, CONFIRMED_COUNT,
       IFF(CONFIRMED_COUNT > 0 AND U_ESC < 0.6, 1, 0) AS CASES_ESCALATED,
       CASE WHEN ALERT_COUNT = 0 THEN 'None'
            WHEN MARKET_EVENT THEN 'Market-wide news event'
            WHEN DESK = 'Equities' THEN IFF(U_RULE < 0.4, 'Front-running', IFF(U_RULE < 0.75, 'Insider-information keyword', 'Restricted-list trade'))
            WHEN DESK = 'FX' THEN IFF(U_RULE < 0.45, 'Off-channel communication', IFF(U_RULE < 0.8, 'Insider-information keyword', 'Personal account dealing'))
            WHEN DESK = 'Rates' THEN IFF(U_RULE < 0.5, 'Wash trade', 'Off-channel communication')
            WHEN DESK = 'Credit' THEN IFF(U_RULE < 0.45, 'Restricted-list trade', IFF(U_RULE < 0.8, 'Insider-information keyword', 'Wash trade'))
            ELSE IFF(U_RULE < 0.5, 'Personal account dealing', IFF(U_RULE < 0.75, 'Off-channel communication', 'Restricted-list trade')) END AS DETECTION_RULE,
       REVIEW_DUE, REVIEW_COMPLETED,
       ROUND(4 + 6 * DRIFT + 9 * BREACH_COUNT + U_NOISE * 3, 2) AS AFTER_HOURS_PCT,
       ROUND(0.5 + 1.5 * DRIFT + 4 * BREACH_COUNT + U_NOISE * 1.2, 2) AS FLAGGED_TERM_RATE,
       CURRENT_TIMESTAMP() AS LOADED_AT
FROM measured;

-- Communication-channel capture coverage per employee (record-keeping snapshot).
CREATE TABLE RAW.RECORDKEEPING AS
SELECT ID AS ENTITY_ID,
       CASE DESK WHEN 'Equities' THEN 'Recorded voice line' WHEN 'FX' THEN 'Bloomberg chat'
                 WHEN 'Rates' THEN 'Recorded voice line' WHEN 'Credit' THEN 'Email'
                 ELSE 'Approved mobile messaging' END AS CHANNEL,
       1 + MOD(ABS(HASH(ID, 'req')), 4) AS REQUIRED_QTY,
       MOD(ABS(HASH(ID, 'file')), 5) AS CAPTURED_QTY,
       IFF(MOD(ABS(HASH(ID, 'file')), 5) < 1 + MOD(ABS(HASH(ID, 'req')), 4),
           MOD(ABS(HASH(ID, 'pending')), 3), 0) AS PENDING_QTY,
       CURRENT_DATE() AS SNAPSHOT_DATE
FROM RAW.EMPLOYEES;
