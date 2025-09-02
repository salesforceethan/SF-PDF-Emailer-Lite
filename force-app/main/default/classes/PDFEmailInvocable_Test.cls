@IsTest
private class PDFEmailInvocable_Test {

    // Utility: make a clean email for test user
    private static String em(Integer i) {
        return 'user' + i + '@example.com';
    }

    @IsTest
    static void testAccount_SendPlain_WithCc() {
        // Data
        Account a = new Account(Name = 'Acme Test');
        insert a;

        // Build request (plain text body)
        PDFEmailInvocable.Request req = new PDFEmailInvocable.Request();
        req.recordId = a.Id;
        req.toEmails  = em(1) + ', ' + em(2);      // multiple "To"
        req.ccEmails  = em(3) + '; ' + em(4);      // multiple "CC"
        req.subject   = 'PDF for {Account.Name}';
        req.body      = 'Hello {Account.Name}, today is {Today}';
        req.useHtml   = false;

        // Execute
        List<PDFEmailInvocable.Result> res = PDFEmailInvocable.send(new List<PDFEmailInvocable.Request>{ req });

        // Assert
        System.assertEquals(1, res.size(), 'one result');
        System.assertEquals(true,  res[0].success, 'send should succeed');
        System.assert(res[0].message != null && res[0].message.contains('Email sent to:'), 'success message should mention recipients');
    }

    @IsTest
    static void testContact_SendHtml_SkipsWhatId() {
        // Data
        Contact c = new Contact(LastName = 'Person', Email = em(5));
        insert c;

        // Build request (HTML body path)
        PDFEmailInvocable.Request req = new PDFEmailInvocable.Request();
        req.recordId = c.Id;
        req.toEmails  = c.Email;                   // only "To"
        req.ccEmails  = em(6);                     // one CC
        req.subject   = 'PDF for Contact: {Contact.Name}';
        req.body      = '<p>Hello {Contact.Name}</p>';
        req.useHtml   = true;

        // Execute
        List<PDFEmailInvocable.Result> res = PDFEmailInvocable.send(new List<PDFEmailInvocable.Request>{ req });

        // Assert
        System.assertEquals(1, res.size());
        System.assertEquals(true, res[0].success, 'Contact send should succeed');
        // We can’t directly assert WhatId, but success implies no INVALID_ID_FIELD from setWhatId on Contact
    }

    @IsTest
    static void testCase_And_Opportunity() {
        // Data
        Case cs = new Case(Subject = 'Test Case');
        insert cs;
        Opportunity opp = new Opportunity(
            Name='Test Opp',
            StageName='Prospecting',
            CloseDate=Date.today().addDays(30)
        );
        insert opp;

        // Requests for both sObjects in one call each
        PDFEmailInvocable.Request rc = new PDFEmailInvocable.Request();
        rc.recordId = cs.Id;
        rc.toEmails = em(7);
        rc.subject  = 'PDF for Case: {Case.CaseNumber}';
        rc.body     = 'Case body';
        rc.useHtml  = false;

        PDFEmailInvocable.Request ro = new PDFEmailInvocable.Request();
        ro.recordId = opp.Id;
        ro.toEmails = em(8) + ' ' + em(9); // whitespace-delimited accepted
        ro.subject  = 'PDF for Opp: {Opportunity.Name}';
        ro.body     = 'Opp body';
        ro.useHtml  = false;

        List<PDFEmailInvocable.Result> out1 = PDFEmailInvocable.send(new List<PDFEmailInvocable.Request>{ rc });
        List<PDFEmailInvocable.Result> out2 = PDFEmailInvocable.send(new List<PDFEmailInvocable.Request>{ ro });

        System.assertEquals(true, out1[0].success, 'Case send ok');
        System.assertEquals(true, out2[0].success, 'Opp send ok');
    }

    @IsTest
    static void testValidation_NoToEmails_Fails() {
        Account a = new Account(Name = 'No To Emails Inc');
        insert a;

        PDFEmailInvocable.Request req = new PDFEmailInvocable.Request();
        req.recordId = a.Id;
        req.toEmails = '';            // empty to force failure
        req.ccEmails = em(10);        // CC alone should NOT send (per current lite behavior)
        req.subject  = 'Subject';
        req.body     = 'Body';
        req.useHtml  = false;

        List<PDFEmailInvocable.Result> res = PDFEmailInvocable.send(new List<PDFEmailInvocable.Request>{ req });

        System.assertEquals(false, res[0].success, 'should fail without To emails');
        System.assert(res[0].message != null && res[0].message.contains('No valid'), 'message indicates invalid recipient state');
    }
}