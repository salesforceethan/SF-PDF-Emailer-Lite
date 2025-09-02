public with sharing class AccountPDFController {
    // Backwards-compatible flat list
    public List<FieldWrapper> fields { get; private set; }

    // Grouped output for PDFs (sectioned)
    public List<SectionWrapper> sections { get; private set; }

    // Friendly record title (used by all VF pages)
    public String AccountName { get; private set; }

    // Simple wrappers
    public class FieldWrapper {
        public String Label { get; set; }
        public String Value { get; set; }
        public FieldWrapper(String label, String value) {
            this.Label = label;
            this.Value = value;
        }
    }

    public class SectionWrapper {
        public String Label { get; set; }
        public Integer SortOrder { get; set; }
        public List<FieldWrapper> Items { get; set; }
        public SectionWrapper(String label, Integer sortOrder) {
            this.Label = label;
            this.SortOrder = sortOrder == null ? 0 : sortOrder;
            this.Items = new List<FieldWrapper>();
        }
    }

    public AccountPDFController(ApexPages.StandardController stdCtrl) {
        fields = new List<FieldWrapper>();
        sections = new List<SectionWrapper>();

        Id recordId = stdCtrl.getId();
        if (recordId == null) return;

        // Determine target object API name (Account, Contact, etc.)
        String objectApiName = recordId.getSObjectType().getDescribe().getName();

        // Get field describes dynamically
        Map<String, Schema.SObjectField> fieldDescribeMap =
            Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();

        // ------------- Read custom metadata for this object -------------
        List<PDF_Field_Config__mdt> mdRecords = new List<PDF_Field_Config__mdt>();
        try {
            mdRecords = [SELECT Field_API_Name__c, Display_Label__c, Section_Label__c, Sort_Order__c
                         FROM PDF_Field_Config__mdt
                         WHERE Object_API_Name__c = :objectApiName
                         AND Include__c = true
                         ORDER BY Section_Label__c, Sort_Order__c NULLS LAST];
        } catch (Exception e) {
            mdRecords = new List<PDF_Field_Config__mdt>();
        }

        // Build final list of field API names (in order) and also capture section grouping if metadata exists
        List<String> fieldApiOrder = new List<String>();
        Map<String, SectionWrapper> sectionMap = new Map<String, SectionWrapper>();
        List<String> sectionOrder = new List<String>();

        Boolean usingMetadata = (mdRecords != null && !mdRecords.isEmpty());

        if (usingMetadata) {
            // Use the metadata ordering and grouping
            for (PDF_Field_Config__mdt md : mdRecords) {
                String fldApi = md.Field_API_Name__c;
                if (String.isBlank(fldApi)) continue;
                if (!fieldDescribeMap.containsKey(fldApi)) continue;
                Schema.DescribeFieldResult dfr = fieldDescribeMap.get(fldApi).getDescribe();
                if (!dfr.isAccessible()) continue;

                fieldApiOrder.add(fldApi);

                String secLabel = String.isBlank(md.Section_Label__c) ? 'Details' : md.Section_Label__c;
                Integer sortOrder = md.Sort_Order__c == null ? 0 : Integer.valueOf(md.Sort_Order__c);

                if (!sectionMap.containsKey(secLabel)) {
                    sectionMap.put(secLabel, new SectionWrapper(secLabel, sortOrder));
                    sectionOrder.add(secLabel);
                }
            }
        } else {
            // No metadata configured — default to all accessible fields
            for (String api : fieldDescribeMap.keySet()) {
                Schema.DescribeFieldResult dfr = fieldDescribeMap.get(api).getDescribe();
                if (dfr.isAccessible()) {
                    fieldApiOrder.add(api);
                }
            }
            // One default section
            sectionMap.put('Details', new SectionWrapper('Details', 0));
            sectionOrder.add('Details');
        }

        // --- Ensure essential fields for titles are queried ---
        // Case: we need CaseNumber and AccountId to build a friendly title like "Case 00001026 for {Account.Name}"
        if (objectApiName == 'Case') {
            List<String> mustHave = new List<String>{ 'CaseNumber', 'AccountId' };
            for (String api : mustHave) {
                if (fieldDescribeMap.containsKey(api)) {
                    Schema.DescribeFieldResult dfr = fieldDescribeMap.get(api).getDescribe();
                    if (dfr.isAccessible() && !fieldApiOrder.contains(api)) {
                        fieldApiOrder.add(api);
                    }
                }
            }
        }

        // ------------- Query the record dynamically -------------
        SObject fullRec;
        try {
            String fieldList = String.join(fieldApiOrder, ',');
            String safeId = String.escapeSingleQuotes(String.valueOf(recordId));
            String soql = 'SELECT ' + fieldList + ' FROM ' + objectApiName + ' WHERE Id = \'' + safeId + '\' LIMIT 1';
            fullRec = Database.query(soql);
        } catch (Exception qex) {
            // Fallback to minimal queries to avoid hard failure
            try {
                String base = 'SELECT Id';
                if (objectApiName == 'Case') base += ', CaseNumber, AccountId';
                base += ', Name'; // harmless if not present; will be ignored in try/catch below
                String fallbackSoql = base + ' FROM ' + objectApiName + ' WHERE Id = \'' + String.escapeSingleQuotes(String.valueOf(recordId)) + '\' LIMIT 1';
                fullRec = Database.query(fallbackSoql);
            } catch (Exception fallbackEx) {
                fullRec = null;
            }
        }

        // ------------- Friendly record title -------------
        try {
            if (fullRec == null) {
                AccountName = '';
            } else if (objectApiName == 'Case') {
                String cnum = '';
                try { cnum = String.valueOf(fullRec.get('CaseNumber')); } catch (Exception ignore) {}
                // Resolve Account name if we queried AccountId above
                String acctName = '';
                try {
                    Id aid = (Id) fullRec.get('AccountId');
                    if (aid != null) {
                        // We'll resolve names below anyway if AccountId was in field list; but handle direct query too
                        acctName = resolveSingleName('Account', aid);
                    }
                } catch (Exception ignore) {}
                AccountName = 'Case ' + (String.isBlank(cnum) ? '' : cnum) + (String.isBlank(acctName) ? '' : ' for ' + acctName);
            } else {
                // Default: try Name
                if (fullRec.get('Name') != null) {
                    AccountName = String.valueOf(fullRec.get('Name'));
                } else {
                    AccountName = '';
                }
            }
        } catch (Exception ignore) {
            AccountName = '';
        }

        if (fullRec == null) return;

        // ------------- Collect reference ids to resolve friendly names (single-target refs only) -------------
        Map<String, String> lookupFieldToType = new Map<String, String>(); // fieldApi => typeName
        Map<String, Set<Id>> refIdsPerType = new Map<String, Set<Id>>();

        for (String apiName : fieldApiOrder) {
            Schema.DescribeFieldResult dfr = fieldDescribeMap.get(apiName).getDescribe();
            if (dfr.getType() == Schema.DisplayType.Reference) {
                List<Schema.SObjectType> refTo = dfr.getReferenceTo();
                if (refTo != null && refTo.size() == 1) {
                    Object raw = fullRec.get(apiName);
                    if (raw != null) {
                        Id refId = (Id) raw;
                        String typeName = refTo[0].getDescribe().getName();
                        if (!refIdsPerType.containsKey(typeName)) refIdsPerType.put(typeName, new Set<Id>());
                        refIdsPerType.get(typeName).add(refId);
                        lookupFieldToType.put(apiName, typeName);
                    }
                }
            }
        }

        // Resolve names for each type we collected
        Map<Id, String> refIdToName = new Map<Id, String>();
        for (String typeName : refIdsPerType.keySet()) {
            Set<Id> ids2 = refIdsPerType.get(typeName);
            if (ids2 == null || ids2.isEmpty()) continue;
            List<String> quoted = new List<String>();
            for (Id i : ids2) quoted.add('\'' + String.escapeSingleQuotes(String.valueOf(i)) + '\'');

            String q = 'SELECT Id, Name FROM ' + typeName + ' WHERE Id IN (' + String.join(quoted, ',') + ')';
            try {
                for (SObject sobj : Database.query(q)) {
                    Id sid = (Id) sobj.get('Id');
                    String nm = (sobj.get('Name') == null) ? String.valueOf(sid) : String.valueOf(sobj.get('Name'));
                    refIdToName.put(sid, nm);
                }
            } catch (Exception e) { /* skip resolution on failure */ }
        }

        // If Case title didn't get Account name earlier, try to fill from resolved refs now
        if (objectApiName == 'Case' && String.isBlank(AccountName)) {
            try {
                String cnum = String.valueOf(fullRec.get('CaseNumber'));
                String acctName = '';
                Id aid = (Id) fullRec.get('AccountId');
                if (aid != null && refIdToName.containsKey(aid)) acctName = refIdToName.get(aid);
                AccountName = 'Case ' + (String.isBlank(cnum) ? '' : cnum) + (String.isBlank(acctName) ? '' : ' for ' + acctName);
            } catch (Exception ignore) {}
        }

        // ------------- Build sections and flat fields list -------------
        if (usingMetadata) {
            for (String secLabel : sectionOrder) {
                if (!sectionMap.containsKey(secLabel)) {
                    sectionMap.put(secLabel, new SectionWrapper(secLabel, 0));
                }
            }
        }

        // Skip compound address objects
        Set<String> skipCompoundFields = new Set<String>{'BillingAddress', 'ShippingAddress'};

        for (String apiName : fieldApiOrder) {
            if (skipCompoundFields.contains(apiName)) continue;

            Schema.DescribeFieldResult dfr = fieldDescribeMap.get(apiName).getDescribe();
            String labelToUse = dfr.getLabel();
            Object rawVal = fullRec.get(apiName);
            if (rawVal == null) continue; // only show populated values

            String displayVal;
            if (dfr.getType() == Schema.DisplayType.Reference && lookupFieldToType.containsKey(apiName)) {
                Id rid = (Id) rawVal;
                displayVal = refIdToName.containsKey(rid) ? refIdToName.get(rid) : String.valueOf(rid);
            } else {
                displayVal = String.valueOf(rawVal);
            }

            if (usingMetadata) {
                for (PDF_Field_Config__mdt md : mdRecords) {
                    if (md.Field_API_Name__c == apiName) {
                        if (!String.isBlank(md.Display_Label__c)) {
                            labelToUse = md.Display_Label__c;
                        }
                        break;
                    }
                }
            }

            String secLabel = 'Details';
            Integer secOrder = 0;
            if (usingMetadata) {
                for (PDF_Field_Config__mdt md : mdRecords) {
                    if (md.Field_API_Name__c == apiName) {
                        secLabel = String.isBlank(md.Section_Label__c) ? 'Details' : md.Section_Label__c;
                        secOrder = md.Sort_Order__c == null ? 0 : Integer.valueOf(md.Sort_Order__c);
                        break;
                    }
                }
            }
            if (!sectionMap.containsKey(secLabel)) {
                sectionMap.put(secLabel, new SectionWrapper(secLabel, secOrder));
                sectionOrder.add(secLabel);
            }

            SectionWrapper sec = sectionMap.get(secLabel);
            sec.Items.add(new FieldWrapper(labelToUse, displayVal));

            fields.add(new FieldWrapper(labelToUse, displayVal));
        }

        // Convert sectionMap -> sections list preserving sectionOrder
        sections = new List<SectionWrapper>();
        for (String sl : sectionOrder) {
            if (sectionMap.containsKey(sl)) {
                sections.add(sectionMap.get(sl));
            }
        }
        if (sections.isEmpty()) {
            sections.add(new SectionWrapper('Details', 0));
            sections[0].Items = fields;
        }
    }

    // Helper to resolve a single Name by Id/type when needed
    private String resolveSingleName(String typeName, Id recId) {
        try {
            List<SObject> rows = Database.query('SELECT Id, Name FROM ' + typeName + ' WHERE Id = :recId LIMIT 1');
            if (!rows.isEmpty()) {
                Object nm = rows[0].get('Name');
                return nm == null ? String.valueOf(recId) : String.valueOf(nm);
            }
        } catch (Exception ignore) {}
        return '';
    }
}