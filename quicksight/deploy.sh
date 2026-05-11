#!/usr/bin/env bash
set -euo pipefail

REGION="us-west-2"
ACCT=$(aws sts get-caller-identity --query Account --output text)
DS_ID="fsi-snowflake-ds"
DS_ARN="arn:aws:quicksight:${REGION}:${ACCT}:datasource/${DS_ID}"
QS_USER_ARN="arn:aws:quicksight:us-west-2:${ACCT}:user/default/${ACCT}"

fail() { echo "FAILED: $1"; exit 1; }
ok()   { echo "  OK: $1"; }

echo "=== Regulatory Compliance QuickSight Deployment ==="

# Dataset 1: Compliance Events
echo "Creating dataset: regulatory-compliance-events..."
aws quicksight create-data-set \
  --aws-account-id "$ACCT" --region "$REGION" \
  --data-set-id "regulatory-compliance-events" \
  --name "Compliance Events" \
  --import-mode DIRECT_QUERY \
  --physical-table-map '{
    "events": {
      "CustomSql": {
        "DataSourceArn": "'"${DS_ARN}"'",
        "Name": "ComplianceEvents",
        "SqlQuery": "SELECT EVENT_ID, EVENT_TYPE, EMPLOYEE_ID, EMPLOYEE_NAME, DESCRIPTION, SEVERITY, STATUS, EVENT_TS FROM FSI_REGULATORY_COMPLIANCE.CURATED.COMPLIANCE_EVENTS",
        "Columns": [
          {"Name": "EVENT_ID", "Type": "STRING"},
          {"Name": "EVENT_TYPE", "Type": "STRING"},
          {"Name": "EMPLOYEE_ID", "Type": "STRING"},
          {"Name": "EMPLOYEE_NAME", "Type": "STRING"},
          {"Name": "DESCRIPTION", "Type": "STRING"},
          {"Name": "SEVERITY", "Type": "STRING"},
          {"Name": "STATUS", "Type": "STRING"},
          {"Name": "EVENT_TS", "Type": "DATETIME"}
        ]
      }
    }
  }' \
  --permissions '[{"Principal":"'"${QS_USER_ARN}"'","Actions":["quicksight:DescribeDataSet","quicksight:DescribeDataSetPermissions","quicksight:PassDataSet","quicksight:DescribeIngestion","quicksight:ListIngestions","quicksight:UpdateDataSet","quicksight:DeleteDataSet","quicksight:CreateIngestion","quicksight:CancelIngestion","quicksight:UpdateDataSetPermissions"]}]' \
  2>&1 && ok "Dataset: regulatory-compliance-events" || fail "Dataset creation"

# Dataset 2: Trade Surveillance
echo "Creating dataset: regulatory-trade-surveillance..."
aws quicksight create-data-set \
  --aws-account-id "$ACCT" --region "$REGION" \
  --data-set-id "regulatory-trade-surveillance" \
  --name "Trade Surveillance" \
  --import-mode DIRECT_QUERY \
  --physical-table-map '{
    "trades": {
      "CustomSql": {
        "DataSourceArn": "'"${DS_ARN}"'",
        "Name": "TradeSurveillance",
        "SqlQuery": "SELECT TRADE_ID, INSTRUMENT, SIDE, QUANTITY, PRICE, NOTIONAL_SGD, VENUE, TRADER_ID, TRADER_NAME, DEPARTMENT, COUNTERPARTY, TRADE_TS, COMPLIANCE_STATUS, SEVERITY FROM FSI_REGULATORY_COMPLIANCE.CURATED.TRADE_SURVEILLANCE",
        "Columns": [
          {"Name": "TRADE_ID", "Type": "STRING"},
          {"Name": "INSTRUMENT", "Type": "STRING"},
          {"Name": "SIDE", "Type": "STRING"},
          {"Name": "QUANTITY", "Type": "DECIMAL"},
          {"Name": "PRICE", "Type": "DECIMAL"},
          {"Name": "NOTIONAL_SGD", "Type": "DECIMAL"},
          {"Name": "VENUE", "Type": "STRING"},
          {"Name": "TRADER_ID", "Type": "STRING"},
          {"Name": "TRADER_NAME", "Type": "STRING"},
          {"Name": "DEPARTMENT", "Type": "STRING"},
          {"Name": "COUNTERPARTY", "Type": "STRING"},
          {"Name": "TRADE_TS", "Type": "DATETIME"},
          {"Name": "COMPLIANCE_STATUS", "Type": "STRING"},
          {"Name": "SEVERITY", "Type": "STRING"}
        ]
      }
    }
  }' \
  --permissions '[{"Principal":"'"${QS_USER_ARN}"'","Actions":["quicksight:DescribeDataSet","quicksight:DescribeDataSetPermissions","quicksight:PassDataSet","quicksight:DescribeIngestion","quicksight:ListIngestions","quicksight:UpdateDataSet","quicksight:DeleteDataSet","quicksight:CreateIngestion","quicksight:CancelIngestion","quicksight:UpdateDataSetPermissions"]}]' \
  2>&1 && ok "Dataset: regulatory-trade-surveillance" || fail "Dataset creation"

# Q Topic
echo "Creating Q topic: regulatory-compliance-q-topic..."
Q_TOPIC_DEF=$(mktemp)
cat > "$Q_TOPIC_DEF" <<EOJSON
{
  "AwsAccountId": "${ACCT}",
  "TopicId": "regulatory-compliance-q-topic",
  "Topic": {
    "Name": "MAS Regulatory Compliance",
    "Description": "Compliance events, trade surveillance, and regulatory filings for Singapore MAS-regulated bank",
    "DataSets": [{
      "DatasetArn": "arn:aws:quicksight:${REGION}:${ACCT}:dataset/regulatory-compliance-events",
      "DatasetName": "Compliance Events",
      "Columns": [
        {"ColumnName": "EVENT_ID", "ColumnFriendlyName": "Event ID", "ColumnSynonyms": ["alert","flag"], "IsIncludedInTopic": true},
        {"ColumnName": "EVENT_TYPE", "ColumnFriendlyName": "Event Type", "ColumnDescription": "Communication or Trade", "ColumnSynonyms": ["type","category"], "IsIncludedInTopic": true},
        {"ColumnName": "EMPLOYEE_ID", "ColumnFriendlyName": "Employee ID", "IsIncludedInTopic": true},
        {"ColumnName": "EMPLOYEE_NAME", "ColumnFriendlyName": "Employee", "ColumnSynonyms": ["trader","person","staff"], "IsIncludedInTopic": true},
        {"ColumnName": "DESCRIPTION", "ColumnFriendlyName": "Description", "IsIncludedInTopic": true},
        {"ColumnName": "SEVERITY", "ColumnFriendlyName": "Severity", "ColumnSynonyms": ["risk","priority","level"], "IsIncludedInTopic": true},
        {"ColumnName": "STATUS", "ColumnFriendlyName": "Status", "ColumnSynonyms": ["state","flag type"], "IsIncludedInTopic": true},
        {"ColumnName": "EVENT_TS", "ColumnFriendlyName": "Event Time", "ColumnSynonyms": ["date","when","timestamp"], "IsIncludedInTopic": true}
      ]
    }]
  }
}
EOJSON

aws quicksight create-topic --cli-input-json "file://${Q_TOPIC_DEF}" --region "$REGION" 2>&1 \
  && ok "Q Topic: regulatory-compliance-q-topic" || echo "  WARN: Q Topic may already exist"
rm -f "$Q_TOPIC_DEF"

aws quicksight update-topic-permissions \
  --aws-account-id "$ACCT" --region "$REGION" \
  --topic-id "regulatory-compliance-q-topic" \
  --grant-permissions '[{"Principal":"'"${QS_USER_ARN}"'","Actions":["quicksight:DescribeTopic","quicksight:DescribeTopicPermissions","quicksight:DescribeTopicRefresh","quicksight:ListTopicReviewedAnswers","quicksight:CreateTopicReviewedAnswer","quicksight:DeleteTopicReviewedAnswer","quicksight:PassTopic"]}]' \
  2>&1 && ok "Q Topic permissions" || echo "  WARN: permissions"

echo ""
echo "=== Regulatory Compliance QuickSight Done ==="
echo "Q Topic ready for: 'How many critical events by employee?' or 'Which department has the most violations?'"
