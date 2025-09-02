public with sharing class AccountPDF_EmailController {
    public Id recordId { get; set; }
    public String recipientType { get; set; } // 'Owner', 'Contact', 'Other'
    public Id selectedContactId { get; set; }
    public String otherEmail { get; set; }
    public String subject { get; set; }
    public String body { get; set; }

    // contacts list for picklist
    public List<Contact> contacts { get; set; }
    public Account acct { get; set; }

    public AccountPDF_EmailController(ApexPages.StandardController std) {
        this.recordId = std.getId();
        this.recipientType = 'Owner';
        // load minimal account + owner email
        try {
            acct = [SELECT Id, Name, Owner.Email FROM Account WHERE Id = :recordId LIMIT 1];
        } catch (Exception e) {
            acct = null;
        }

        // load contacts on the account for dropdown (only those with email)
        contacts = new List<Contact>();
        if (recordId != null) {
            try {
                contacts = [SELECT Id, Name, Email FROM Contact WHERE AccountId = :recordId AND Email != null ORDER BY Name LIMIT 200];
            } catch (Exception e) {
                contacts = new List<Contact>();
            }
        }

        this.subject = acct != null ? 'Account PDF: ' + acct.Name : 'Account PDF';
        this.body = acct != null ? ('Please find attached the Account PDF for ' + acct.Name + '.') : 'Please find attached the PDF.';
    }

    // select options for the contact picklist
    public List<SelectOption> getContactOptions() {
        List<SelectOption> opts = new List<SelectOption>();
        opts.add(new SelectOption('', '-- Select contact --'));
        for (Contact c : contacts) {
            String label = c.Name + (String.isNotBlank(c.Email) ? ' (' + c.Email + ')' : '');
            opts.add(new SelectOption(c.Id, label));
        }
        return opts;
    }

    public PageReference cancelAction() {
        PageReference pr = new PageReference('/' + recordId);
        pr.setRedirect(true);
        return pr;
    }

    public PageReference sendEmail() {
    List<String> toAddresses = new List<String>();

    if (recipientType == 'Owner') {
        if (acct != null && acct.Owner != null && String.isNotBlank(String.valueOf(acct.Owner.get('Email')))) {
            toAddresses.add(String.valueOf(acct.Owner.get('Email')));
        }
    } else if (recipientType == 'Contact') {
        if (selectedContactId != null) {
            try {
                Contact c = [SELECT Email FROM Contact WHERE Id = :selectedContactId LIMIT 1];
                if (String.isNotBlank(c.Email)) toAddresses.add(c.Email);
            } catch (Exception e) { /* fall through */ }
        }
    } else if (recipientType == 'Other') {
        if (String.isNotBlank(otherEmail)) {
            toAddresses.add(otherEmail.trim());
        }
    }

        if (toAddresses.isEmpty()) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'No valid recipient email found. Please choose a contact, owner, or enter an email address.'));
            return null;
        }

        try {
            // Render the AccountPDF_v2 page as PDF
            PageReference pdfPage = Page.AccountPDF_v2;
            pdfPage.getParameters().put('id', String.valueOf(recordId));
            // important: getContentAsPDF runs synchronously and returns the PDF blob
            Blob pdfBlob = pdfPage.getContentAsPDF();

            // Create file attachment for email
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            String fileLabel = 'Account_' + (acct != null && acct.Name != null ? acct.Name.replaceAll('[^A-Za-z0-9 _-]','') : String.valueOf(recordId)) + '.pdf';
            attachment.setFileName(fileLabel);
            attachment.setBody(pdfBlob);
            attachment.setContentType('application/pdf');

            // Compose and send email
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);
            mail.setSubject(String.isBlank(subject) ? ('Account PDF: ' + (acct != null ? acct.Name : '')) : subject);
            mail.setPlainTextBody(String.isBlank(body) ? '' : body);
            mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attachment });

            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

            // success message then redirect to record
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, 'Email sent successfully.'));
            PageReference pr = new PageReference('/' + recordId);
            pr.setRedirect(true);
            return pr;
        } catch (Exception ex) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Error sending email: ' + ex.getMessage()));
            return null;
        }
    }
}