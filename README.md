# PDF Emailer Lite for Salesforce

Generate and email PDFs from **Account, Contact, Case, Opportunity** with a simple Flow UI.  
Logs activities automatically, supports Org-Wide Email, and includes a 20MB attachment guardrail.

---

## 🚀 Install

[![Install in Production](https://img.shields.io/badge/Install-Production-blue)](https://login.salesforce.com/packaging/installPackage.apexp?p0=04ta500000AhlAn)  
[![Install in Sandbox](https://img.shields.io/badge/Install-Sandbox-orange)](https://test.salesforce.com/packaging/installPackage.apexp?p0=04ta500000AhlAn)

> After install, assign the **PDF_Emailer_Lite_Permissions** permission set and add the two **Quick Actions** (Print PDF, Email PDF) to layouts for Account, Contact, Case, Opportunity.

---

## ✨ Features

- Print clean PDFs from 4 core objects (VF pages)
- Email the PDF via a Flow (To + optional CC)
- Activities auto-logged (Contact-aware)
- Uses Org-Wide Email if configured
- 20MB attachment guardrail
- Optional field/section curation via **Custom Metadata**

---

## 📚 Admin Setup Guide

### 1. Permission Set

Assign **PDF_Emailer_Lite_Permissions** to users who need access.

### 2. Quick Actions

- Go to Object Manager → (Account/Contact/Case/Opportunity)
- Edit Page Layouts → add **Print PDF** and **Email PDF** actions

### 3. Org-Wide Email (optional, recommended)

- Setup → Org-Wide Email Addresses
- Add & verify a shared email (e.g. support@company.com)
- The package automatically uses it if available

### 4. Custom Metadata (optional)

- Setup → Custom Metadata Types → _PDF Email Template_ or _Related List Config_
- Add records to control:
  - Default subjects/bodies
  - Which fields/related lists appear on PDFs
- Example: Add a record with `Object_API_Name = Account` and set subject to _"Account Summary for {Account.Name}"_

---

## 📈 Flow Performance & Reliability Monitor

Looking to track slow or failing flows, limit pressure, or regressions after releases? Use the monitoring blueprint below to stand up a lightweight dashboard in your org.

- [Flow Performance & Reliability Monitor](docs/flow-performance-reliability-monitor.md)

---

## 🧪 Testing

- Works in any sandbox
- Comes with Apex tests for core logic

---

▶️ Video Walkthrough

📺 Coming soon: YouTube Setup Guide

---

## 📝 License

MIT
