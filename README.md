# salesforce-pdf-emailer-lite


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

## 📚 Admin Guide
See the full guide here: https://developer.salesforce.com/docs/atlas.en-us.salesforce1appadmin.meta/salesforce1appadmin/salesforce1_admin_guide_intro.htm

- Install & setup steps
- Org-Wide Email + DKIM recommendations
- How to add **PDF Field Config** CMDT records to control which fields/sections appear

---

## 🧪 Testing
Works in any sandbox. Comes with Apex tests for core logic.

---

## 📝 License
MIT

