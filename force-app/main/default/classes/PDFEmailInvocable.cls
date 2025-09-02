public with sharing class PDFEmailInvocable {
    // Guardrail: keep well below Salesforce’s ~25MB email limit (headers, body, etc.)
    private static final Integer MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024; // 20 MB

    @InvocableMethod(label='Send Record PDF Email' description='Generate a PDF for the record and email it to the provided address(es).')
    public static List<Result> send(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        // Determine object from first valid recordId
        String objectApiName = null;
        for (Request r : requests) {
            if (r != null && r.recordId != null) {
                try {
                    objectApiName = r.recordId.getSObjectType().getDescribe().getName();
                    break;
                } catch (Exception ignore) {}
            }
        }
        if (String.isBlank(objectApiName)) {
            for (Integer i = 0; i < requests.size(); i++) results.add(error('Missing or invalid recordId.'));
            return results;
        }

        // Load records (for token merge + filename + WhatId rules)
        Set<Id> ids = new Set<Id>();
        for (Request r : requests) if (r != null && r.recordId != null) ids.add(r.recordId);
        Map<Id, SObject> recMap = loadRecords(objectApiName, ids);

        // Optional: template defaults by object (safe if CMDT not present)
        TemplateDefaults defs = loadTemplateDefaults(objectApiName);

        for (Request r : requests) {
            try {
                if (r == null || r.recordId == null) { results.add(error('Missing recordId.')); continue; }
                SObject rec = recMap.get(r.recordId);
                if (rec == null) { results.add(error(objectApiName + ' not found or not accessible: ' + String.valueOf(r.recordId))); continue; }

                // --- Recipients: To (required) ---
                List<String> toList = splitEmails(r.toEmails);
                if (toList.isEmpty()) { results.add(error('No valid recipient email(s).')); continue; }

                // --- Recipients: CC (optional; passed from Flow) ---
                List<String> ccList = splitEmails(r.ccEmails);

                // --- Subject & Body (Flow can override; else defaults) ---
                String subj = String.isBlank(r.subject)
                    ? mergeTokens(String.isBlank(defs.subject) ? defaultSubjectFallback(objectApiName) : defs.subject, rec, objectApiName)
                    : mergeTokens(r.subject, rec, objectApiName);

                String bod = String.isBlank(r.body)
                    ? mergeTokens(String.isBlank(defs.body) ? defaultBodyFallback(objectApiName) : defs.body, rec, objectApiName)
                    : mergeTokens(r.body, rec, objectApiName);

                Boolean useHtml = (r.useHtml == null ? defs.useHtml : r.useHtml);

                // --- Generate PDF with the correct VF page ---
                Blob pdfBlob;
                if (Test.isRunningTest()) {
                    pdfBlob = Blob.valueOf('TEST_PDF');
                } else {
                    PageReference pdfPage = getPdfPageForSObject(objectApiName);
                    pdfPage.getParameters().put('id', String.valueOf(r.recordId));
                    pdfBlob = pdfPage.getContentAsPDF();
                }

                // --- Attachment size guardrail ---
                Integer blobSize = pdfBlob == null ? 0 : pdfBlob.size();
                if (blobSize <= 0) {
                    results.add(error('Failed to generate PDF content.'));
                    continue;
                }
                if (blobSize > MAX_ATTACHMENT_BYTES) {
                    Decimal sizeMb = (Decimal.valueOf(blobSize) / 1048576).setScale(2);
                    Decimal maxMb  = (Decimal.valueOf(MAX_ATTACHMENT_BYTES) / 1048576).setScale(0);
                    results.add(error('PDF is too large to email (' + String.valueOf(sizeMb) + ' MB). Please reduce content or try fewer sections. Max ~' + String.valueOf(maxMb) + ' MB.'));
                    continue;
                }

                // --- Filename ---
                String baseName = sanitizeFilename(getRecordName(rec));
                if (String.isBlank(baseName)) baseName = String.valueOf(r.recordId);
                if (baseName.length() > 80) baseName = baseName.substring(0, 80);
                String dateStamp = DateTime.now().formatGmt('yyyy-MM-dd');
                String fileLabel = objectApiName + '_' + baseName + '_' + dateStamp + '.pdf';

                // --- Attachment ---
                Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
                att.setFileName(fileLabel);
                att.setBody(pdfBlob);
                att.setContentType('application/pdf');

                // --- Compose email (with Contact-specific linkage logic) ---
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

                Boolean usedTargetObject = false;
                Id contactId = (objectApiName == 'Contact') ? (Id)rec.get('Id') : null;
                String contactEmail = null;
                if (objectApiName == 'Contact') {
                    try { contactEmail = (String) rec.get('Email'); } catch (Exception ignore) {}
                }

                // Case A: Contact + exactly one To that equals the Contact's Email -> use TargetObjectId for proper activity on Contact
                if (contactId != null
                    && contactEmail != null
                    && toList.size() == 1
                    && contactEmail.equalsIgnoreCase(toList[0])) {

                    mail.setTargetObjectId(contactId);  // sends to Contact + auto-logs activity on Contact
                    usedTargetObject = true;
                    if (!ccList.isEmpty()) mail.setCcAddresses(ccList);

                } else {
                    // Case B: Generic path (multiple To's or different recipient)
                    mail.setToAddresses(toList);
                    if (!ccList.isEmpty()) mail.setCcAddresses(ccList);
                }

                // Subject/body
                mail.setSubject(subj);
                if (useHtml) {
                    mail.setHtmlBody(sanitizeHtml(bod));
                    mail.setPlainTextBody(htmlToPlainText(bod));
                } else {
                    mail.setPlainTextBody(bod);
                }
                mail.setFileAttachments(new Messaging.EmailFileAttachment[] { att });

                // Activity logging
                mail.setSaveAsActivity(true);

                // Avoid invalid WhatId on Contact/Lead
                if (objectApiName != 'Contact' && objectApiName != 'Lead') {
                    try { mail.setWhatId(r.recordId); } catch (Exception ignore) {}
                }

                // Prefer a verified Org-Wide Email Address if available; retry without if it fails
                Id oweaId = getDefaultOrgWideEmailId();
                if (oweaId != null) mail.setOrgWideEmailAddressId(oweaId);

                Messaging.SendEmailResult[] sendRes;
                try {
                    sendRes = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
                } catch (Exception e1) {
                    try { mail.setOrgWideEmailAddressId(null); } catch (Exception ignore) {}
                    sendRes = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
                }

                if (sendRes == null || sendRes.isEmpty() || !sendRes[0].isSuccess()) {
                    String err = (sendRes != null && !sendRes.isEmpty() && sendRes[0].getErrors() != null && !sendRes[0].getErrors().isEmpty())
                        ? sendRes[0].getErrors()[0].getMessage()
                        : 'Unknown error while sending.';
                    results.add(error('Failed to send: ' + err));
                    continue;
                }

                // If we couldn't use TargetObjectId for a Contact, create a Task so the Contact still gets an activity
                if (objectApiName == 'Contact' && !usedTargetObject && contactId != null) {
                    try {
                        Task t = new Task();
                        t.Status = 'Completed';
                        t.Subject = 'Email: ' + subj;
                        t.ActivityDate = Date.today();
                        t.WhoId = contactId;  // relate to Contact

                        // Optionally also relate to the Account (if present)
                        try {
                            Id acctId = (Id) rec.get('AccountId');
                            if (acctId != null) t.WhatId = acctId;
                        } catch (Exception ignoreW) {}

                        t.Description = (useHtml ? htmlToPlainText(bod) : bod);
                        if (t.Description != null && t.Description.length() > 32000)
                            t.Description = t.Description.substring(0, 32000);

                        insert t;
                    } catch (Exception ignoreTask) {
                        // If Task insert fails, we still consider the email a success
                    }
                }

                results.add(ok('Email sent to: ' + String.join(toList, '; ')
                               + (ccList.isEmpty() ? '' : ' (cc: ' + String.join(ccList, '; ') + ')')));
            } catch (Exception ex) {
                results.add(error('Unexpected error: ' + ex.getMessage()));
            }
        }
        return results;
    }

    // ===== Invocable IO =====
    public class Request {
        @InvocableVariable(required=true label='Record Id') public Id recordId;
        @InvocableVariable(required=true label='To Email(s)' description='Comma/semicolon/space separated list of emails') public String toEmails;
        @InvocableVariable(label='CC Email(s)' description='Optional comma/semicolon/space separated list of CC emails') public String ccEmails;
        @InvocableVariable(label='Subject') public String subject;
        @InvocableVariable(label='Body') public String body;
        @InvocableVariable(label='Send as HTML?') public Boolean useHtml;
    }
    public class Result { @InvocableVariable public Boolean success; @InvocableVariable public String message; public Result() {} }
    private static Result ok(String msg) { Result r = new Result(); r.success = true; r.message = msg; return r; }
    private static Result error(String msg) { Result r = new Result(); r.success = false; r.message = msg; return r; }

    // ===== Page selection =====
    private static PageReference getPdfPageForSObject(String objectApiName) {
        if (objectApiName == 'Account')     return Page.AccountPDF_v2;
        if (objectApiName == 'Contact')     return Page.ContactPDF_v2;
        if (objectApiName == 'Opportunity') return Page.OpportunityPDF_v2;
        if (objectApiName == 'Case')        return Page.CasePDF_v2;
        return Page.AccountPDF_v2; // fallback
    }

    // ===== Record loading (dynamic) =====
    private static Map<Id, SObject> loadRecords(String objectApiName, Set<Id> ids) {
        Map<Id, SObject> out = new Map<Id, SObject>();
        if (ids == null || ids.isEmpty()) return out;

        List<String> fieldCombos = new List<String>{
            'Id, Name, Owner.Email',
            'Id, Name',
            'Id'
        };
        for (String fields : fieldCombos) {
            try {
                String soql = 'SELECT ' + fields + ' FROM ' + objectApiName + ' WHERE Id IN :ids';
                for (SObject s : Database.query(soql)) out.put((Id)s.get('Id'), s);
                if (!out.isEmpty()) return out;
            } catch (Exception ignore) {}
        }
        return out;
    }

    private static String getRecordName(SObject rec) {
        if (rec == null) return null;
        try { Object v = rec.get('Name'); return v == null ? null : String.valueOf(v); }
        catch (Exception e) { return null; }
    }

    // ===== CMDT defaults (by object) =====
    private class TemplateDefaults { String subject; String body; Boolean useHtml; TemplateDefaults(String s, String b, Boolean h){subject=s; body=b; useHtml=(h==null)?false:h;} }
    private static TemplateDefaults loadTemplateDefaults(String objectApiName) {
        try {
            String soql =
                'SELECT Default_Subject__c, Default_Body__c, Use_Html__c, Active__c ' +
                'FROM PDF_Email_Template__mdt ' +
                'WHERE Object_API_Name__c = :obj AND Active__c = true LIMIT 1';
            String finalSoql = soql.replace(':obj', '\'' + String.escapeSingleQuotes(objectApiName) + '\'');
            List<SObject> rows = Database.query(finalSoql);
            if (!rows.isEmpty()) {
                SObject t = rows[0];
                return new TemplateDefaults(
                    (String)t.get('Default_Subject__c'),
                    (String)t.get('Default_Body__c'),
                    (Boolean)t.get('Use_Html__c')
                );
            }
        } catch (Exception ignore) {}
        return new TemplateDefaults(null, null, false);
    }

    // ===== Token merge & helpers =====
    private static Set<String> extractFieldTokens(String template, String prefix) {
        Set<String> fields = new Set<String>();
        if (String.isBlank(template)) return fields;
        Pattern p = Pattern.compile('\\{' + prefix + '\\.([A-Za-z0-9_\\.]+)\\}');
        Matcher m = p.matcher(template);
        while (m.find()) fields.add(m.group(1));
        return fields;
    }
    private static String mergeTokens(String template, SObject rec, String prefix) {
        if (String.isBlank(template) || rec == null) return template;
        String out = template.replace('{Today}', Date.today().format());
        Set<String> fields = extractFieldTokens(template, prefix);
        for (String f : fields) {
            String token = '{' + prefix + '.' + f + '}';
            String replacement = '';
            try {
                if (f.contains('.')) {
                    List<String> parts = f.split('\\.');
                    if (parts.size() == 2 && parts[0] == 'Owner' && parts[1] == 'Email') {
                        SObject owner = rec.getSObject('Owner');
                        replacement = owner == null ? '' : String.valueOf(owner.get('Email'));
                    }
                } else {
                    Object v = rec.get(f);
                    replacement = v == null ? '' : String.valueOf(v);
                }
            } catch (Exception ignore) {}
            out = out.replace(token, replacement);
        }
        return out;
    }

    private static List<String> splitEmails(String raw) {
        List<String> out = new List<String>();
        if (String.isBlank(raw)) return out;
        for (String p : raw.split('[,;\\s]+')) {
            String e = p == null ? null : p.trim();
            if (String.isNotBlank(e) && isValidEmail(e)) out.add(e);
        }
        return out;
    }
    private static Boolean isValidEmail(String em) {
        if (String.isBlank(em)) return false;
        Pattern p = Pattern.compile('(?i)^[A-Z0-9._%+\\-\\\']+@[A-Z0-9.\\-]+\\.[A-Z]{2,}$');
        return p.matcher(em).matches();
    }
    private static String sanitizeFilename(String s) { if (s == null) return 'file'; return s.replaceAll('[^A-Za-z0-9 _.-]', ''); }
    private static String sanitizeHtml(String html) {
        if (String.isBlank(html)) return html;
        String out = html;
        out = out.replaceAll('(?is)<\\s*(script|iframe|object|embed|link|meta|style)[\\s\\S]*?>[\\s\\S]*?<\\s*/\\s*\\1\\s*>', '');
        out = out.replaceAll('(?is)on\\w+\\s*=\\s*([\'"]).*?\\1', '');
        out = out.replaceAll('(?is)javascript\\s*:', '');
        return out;
    }
    private static String htmlToPlainText(String html) {
        if (String.isBlank(html)) return html;
        String out = html;
        out = out.replaceAll('(?is)<br\\s*/?>', '\n');
        out = out.replaceAll('(?is)</p\\s*>', '\n\n');
        out = out.replaceAll('(?is)<[^>]+>', '');
        return out.trim();
    }

    private static Id getDefaultOrgWideEmailId() {
        try {
            List<OrgWideEmailAddress> rows = [
                SELECT Id, Address, DisplayName, IsAllowAllProfiles
                FROM OrgWideEmailAddress
                ORDER BY IsAllowAllProfiles DESC, CreatedDate ASC
                LIMIT 1
            ];
            if (!rows.isEmpty()) return rows[0].Id;
        } catch (Exception ignore) {}
        return null;
    }

    private static String defaultSubjectFallback(String objectApiName) { return objectApiName + ' PDF'; }
    private static String defaultBodyFallback(String objectApiName) { return 'Please find the attached ' + objectApiName + ' PDF.'; }
}