# Flow Performance & Reliability Monitor

This guide outlines a lightweight, Salesforce-native monitor that surfaces Flow failures, slowness, and limit pressure, and highlights regressions after releases. It is designed to run alongside this package without requiring code changes to the existing flows.

---

## Goals

Answer the following questions continuously:

1. **Which flows are failing most?**
2. **Which flows are slow?**
3. **Which flows are hitting limits (CPU, SOQL, DML, etc.)?**
4. **Did anything suddenly degrade after a release?**

---

## Recommended Data Sources

Choose one or both sources depending on your org’s entitlements and appetite for detail:

### Option A: Event Monitoring (Preferred)

Use **Flow Execution** events to capture performance and limit usage for every run.

**What you get:**

- Duration and CPU time per flow run
- SOQL/DML usage and row counts
- Outcome (success/failure)
- Flow name, version, and user context

**How to capture:**

- Enable **Event Monitoring** and subscribe to **Flow Execution** events.
- Stream events into a custom object via **Event Monitoring Analytics App**, **Data Cloud**, or an **Apex/Eventing pipeline**.

### Option B: Flow Interview Logs (Fallback)

Use **Flow Interviews** and **Flow Interview Logs** to identify failures and error details.

**What you get:**

- Failed interviews, error messages, and timestamps
- Less granular performance metrics

**How to capture:**

- Report on standard objects for **Failed Flow Interviews**.
- Optionally ETL into a custom object for trend analysis.

---

## Suggested Custom Object Schema

Create a lightweight logging object (example: `Flow_Execution_Observation__c`) that stores one row per flow run.

**Core fields**

- `Flow_Name__c` (Text)
- `Flow_Version__c` (Text)
- `Start_Time__c` (Date/Time)
- `Duration_Ms__c` (Number)
- `Cpu_Time_Ms__c` (Number)
- `Soql_Queries__c` (Number)
- `Soql_Rows__c` (Number)
- `Dml_Statements__c` (Number)
- `Dml_Rows__c` (Number)
- `Outcome__c` (Picklist: Success, Failure)
- `Error_Message__c` (Long Text)
- `User_Id__c` (Lookup/User)
- `Release_Tag__c` (Text)

**Why:** this normalizes telemetry for reporting without depending on event retention windows.

---

## Dashboard & Report Pack

Build a small set of reports and a dashboard titled **“Flow Performance & Reliability Monitor.”**

### 1) Which flows are failing most?

**Report:** _Failures by Flow (Last 30 Days)_

- Filter: `Outcome = Failure`
- Group rows by `Flow_Name__c`
- Sort by `Row Count DESC`

**Dashboard widget:** Bar chart: _Top 10 Failed Flows_.

### 2) Which flows are slow?

**Report:** _Median/95th Duration by Flow_

- Filter: `Outcome = Success`
- Add summary statistics on `Duration_Ms__c`
- Group rows by `Flow_Name__c`

**Dashboard widget:** Table or bar chart showing median and p95 by flow.

### 3) Which flows are hitting limits?

**Report:** _Limit Pressure by Flow_

- Filter: `Cpu_Time_Ms__c > 9000` **OR** `Soql_Queries__c > 80` **OR** `Dml_Statements__c > 140`
- Group rows by `Flow_Name__c`

**Dashboard widget:** Stacked bar chart showing counts by limit type.

### 4) Did anything suddenly degrade after a release?

**Report:** _Release-over-Release Delta_

- Require `Release_Tag__c` to be set (see below)
- Compare medians of `Duration_Ms__c` and failure rate across releases

**Dashboard widget:** Line chart of median duration and failure rate over time with release markers.

---

## Release Tagging Strategy

To detect regressions after release:

1. Create a **Custom Metadata Type**: `Release_Tag__mdt` with fields:
   - `Release_Name__c`
   - `Start_Date__c`
   - `End_Date__c`
2. On ingestion, set `Release_Tag__c` by matching `Start_Time__c` to the active release window.
3. Add a “Release” dashboard filter for quick comparisons.

---

## Alerting & Notifications

Add lightweight alerts so issues surface quickly:

- **Failure spike alert**: If `Failure Rate > 5%` for any flow over 1 hour, post to Slack/Email.
- **Performance regression**: If p95 duration increases by >50% compared to prior week.
- **Limit pressure**: If any flow exceeds 80% of CPU or SOQL limits repeatedly.

Implementation options:

- Scheduled Flow + Email Alert
- Apex scheduled job reading summary reports
- Slack via webhook action

---

## Minimal Viable Build Checklist

1. Enable Event Monitoring (or fallback to Flow Interview reporting).
2. Create `Flow_Execution_Observation__c` custom object.
3. Build ingestion pipeline (Data Cloud, Apex, or ETL).
4. Create the dashboard with 4 core widgets.
5. Add release tagging and alerting.

---

## Notes & Guardrails

- Keep retention at least 90 days so trends are meaningful.
- Add object/field-level security for all monitoring data.
- If Event Monitoring is not available, start with the Failure dashboard and gradually expand.
