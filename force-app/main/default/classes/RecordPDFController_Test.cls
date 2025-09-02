@isTest
private class RecordPDFController_Test {

    @isTest
    static void testAccountPDFController() {
        Account acct = new Account(Name = 'Test Account');
        insert acct;

        Test.startTest();
        ApexPages.StandardController sc = new ApexPages.StandardController(acct);
        RecordPDFController ctrl = new RecordPDFController(sc);
        System.assertNotEquals(null, ctrl.AccountName, 'AccountName should be populated');
        System.assert(ctrl.fields != null && ctrl.fields.size() >= 0, 'Fields list should be initialized');
        Test.stopTest();
    }

    @isTest
    static void testContactPDFController() {
        Account acct = new Account(Name = 'Parent Account');
        insert acct;
        Contact con = new Contact(FirstName = 'Test', LastName = 'Contact', AccountId = acct.Id, Email = 'test@example.com');
        insert con;

        Test.startTest();
        ApexPages.StandardController sc = new ApexPages.StandardController(con);
        RecordPDFController ctrl = new RecordPDFController(sc);
        System.assert(ctrl.AccountName != null, 'Contact title should populate');
        Test.stopTest();
    }

    @isTest
    static void testCasePDFController() {
        Account acct = new Account(Name = 'Case Parent');
        insert acct;
        Case c = new Case(Subject = 'Test Case', AccountId = acct.Id);
        insert c;

        Test.startTest();
        ApexPages.StandardController sc = new ApexPages.StandardController(c);
        RecordPDFController ctrl = new RecordPDFController(sc);
        System.assert(ctrl.AccountName.contains('Case'), 'Case title should include Case');
        Test.stopTest();
    }

    @isTest
    static void testOpportunityPDFController() {
        Account acct = new Account(Name = 'Opp Parent');
        insert acct;
        Opportunity opp = new Opportunity(Name = 'Test Opp', AccountId = acct.Id, StageName = 'Prospecting', CloseDate = Date.today());
        insert opp;

        Test.startTest();
        ApexPages.StandardController sc = new ApexPages.StandardController(opp);
        RecordPDFController ctrl = new RecordPDFController(sc);
        System.assert(ctrl.AccountName.contains('Test Opp'), 'Opportunity title should include name');
        Test.stopTest();
    }
}