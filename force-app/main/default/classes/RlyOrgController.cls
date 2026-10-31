/**
 * @description Pipeline tab: the orgs registered in the Release Relay hub.
 *   getOrgs     every registered org, with its last check and a masked hint of its consumer key
 *   saveOrg     add or change one (admins); its sign-in is checked next by checkOrg
 *   checkOrg    signs in and reads the org's identity, newest API version and whether it has
 *               source tracking (RlyOrgCheck); records the result and any recommendation
 * The consumer key is encrypted at rest (Consumer_Key__c) and never sent to the browser.
 */
public with sharing class RlyOrgController {

    /** @description The custom permission admins have. */
    public static final String ADMIN_PERMISSION = 'RLY_Admin';

    /** @description What the Pipeline tab shows about the registered orgs. */
    public class PipelineOrgs {
        /** @description This hub's My Domain URL, for the Remote Site Setting steps. */
        @AuraEnabled public String hubDomain;
        /** @description The current user is an admin. */
        @AuraEnabled public Boolean isAdmin;
        /** @description Every registered org, without its consumer key. */
        @AuraEnabled public List<RLY_Org__c> orgs;
        /** @description Org Id to a masked hint of its consumer key (last four characters). */
        @AuraEnabled public Map<Id, String> keyHints = new Map<Id, String>();
        /** @description Where releases into an org can be approved, from the hub's connections. */
        @AuraEnabled public List<ApprovalOption> approvalOptions = new List<ApprovalOption>();
        /** @description Slack is on and its app answers (auth.test), so orgs can be approved from their Slack card. */
        @AuraEnabled public Boolean slackAvailable = false;
        /** @description The Git provider's name (for the "also require reviewers" toggle), or null without a Git connection. */
        @AuraEnabled public String gitProvider;
    }

    /** @description One choice for Approval_In__c. */
    public class ApprovalOption {
        /** @description The picklist value: Salesforce, Slack or Git. */
        @AuraEnabled public String value;
        /** @description What the page shows, for example In Salesforce. */
        @AuraEnabled public String label;

        /**
         * @description An option.
         * @param value the picklist value
         * @param label what the page shows
         */
        public ApprovalOption(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    /**
     * @description Every registered org, with a masked hint of each consumer key.
     * @return the orgs
     */
    @AuraEnabled
    public static PipelineOrgs getOrgs() {
        Data data = new Data();
        PipelineOrgs p = new PipelineOrgs();
        p.hubDomain = URL.getOrgDomainUrl().toExternalForm();
        p.isAdmin = isAdmin();
        p.orgs = data.allOrgs();
        for (RLY_Org__c k : data.keys()) {
            p.keyHints.put(k.Id, RlyOrgSession.keyHint(k));
        }
        p.approvalOptions = approvalOptions();
        p.slackAvailable = RlySlack.isConnected();
        p.gitProvider = RlyGitName.labelFor(RlyReleaseStore.git());
        return p;
    }

    /**
     * @description Where releases can be approved: always in Salesforce; in Slack when Slack is on; in the Git provider
     * when a Git connection exists (labelled with the provider's name).
     * @return the options
     */
    public static List<ApprovalOption> approvalOptions() {
        List<ApprovalOption> out = new List<ApprovalOption>{ new ApprovalOption(RlyApprover.IN_SALESFORCE, 'In Salesforce') };
        if (RlySlack.isOn()) {
            out.add(new ApprovalOption(RlyApprover.IN_SLACK, 'In Slack'));
        }
        String provider = RlyGitName.labelFor(RlyReleaseStore.git());
        if (provider != null) {
            out.add(new ApprovalOption(RlyApprover.IN_GIT, 'In ' + provider));
        }
        return out;
    }

    /**
     * @description Adds or updates a registered org. Identity fields are cleared when the domain or user changes.
     * When an existing org is saved with a blank consumer key, the saved key is kept.
     * @param orgJson the org's fields as JSON (Consumer_Key__c for the key)
     * @return the org's Id
     */
    @AuraEnabled
    public static Id saveOrg(String orgJson) {
        if (!isAdmin()) {
            throw new AuraHandledException('Registering orgs needs the Release Relay Admin permission set.');
        }
        RLY_Org__c input = readInput(orgJson);
        Data data = new Data();
        RLY_Org__c saved = input.Id == null ? null : data.byId(input.Id);
        List<String> problems = RlyOrgValidator.validate(input, saved);
        if (!problems.isEmpty()) {
            throw new AuraHandledException(String.join(problems, '. ') + '.');
        }
        if (data.nameTaken(input.Name.trim(), input.Id)) {
            throw new AuraHandledException('An org named ' + input.Name.trim() + ' is already registered.');
        }
        RLY_Org__c row = buildRow(input);
        applyStatus(row, saved);
        data.save(row);
        return row.Id;
    }

    private static RLY_Org__c readInput(String orgJson) {
        try {
            return (RLY_Org__c) JSON.deserialize(orgJson, RLY_Org__c.class);
        } catch (Exception e) {
            throw new AuraHandledException('The org details couldn\'t be read.');
        }
    }

    private static RLY_Org__c buildRow(RLY_Org__c input) {
        RLY_Org__c row = new RLY_Org__c(
            Id = input.Id,
            Name = input.Name.trim(),
            Role__c = input.Role__c,
            Environment__c = String.isBlank(input.Environment__c) ? null : input.Environment__c,
            My_Domain__c = input.My_Domain__c.trim().removeEnd('/'),
            Login_Type__c = input.Login_Type__c,
            Username__c = input.Username__c.trim(),
            Certificate__c = input.Certificate__c.trim(),
            Git_Environment__c = String.isBlank(input.Git_Environment__c) ? null : input.Git_Environment__c.trim(),
            Branch__c = String.isBlank(input.Branch__c) ? null : input.Branch__c.trim(),
            Slack_Channel__c = String.isBlank(input.Slack_Channel__c) ? null : input.Slack_Channel__c.trim(),
            Slack_Post__c = input.Slack_Post__c == true
        );
        applyApproval(row, input);
        // A new key goes to the encrypted field and clears the old plain one; no key keeps what's saved.
        String key = RlyOrgValidator.submittedKey(input);
        if (key != null) {
            row.Consumer_Key__c = key;
            row.Client_Id__c = null;
        }
        return row;
    }

    // The approval toggles. A page that still sends Approval_In__c (and no toggle) is read the old way.
    private static void applyApproval(RLY_Org__c row, RLY_Org__c input) {
        Boolean toggles = input.isSet('Approve_In_Salesforce__c') || input.isSet('Approve_In_Slack__c') || input.isSet('Require_Git_Review__c');
        String legacy = toggles ? null : input.Approval_In__c;
        row.Approve_In_Slack__c = toggles ? input.Approve_In_Slack__c == true : legacy == RlyApprover.IN_SLACK;
        row.Approve_In_Salesforce__c = toggles ? input.Approve_In_Salesforce__c == true : legacy != RlyApprover.IN_SLACK;
        row.Require_Git_Review__c = toggles ? input.Require_Git_Review__c == true : legacy == RlyApprover.IN_GIT;
        if (!row.Approve_In_Salesforce__c && !row.Approve_In_Slack__c) {
            row.Approve_In_Salesforce__c = true;
        }
        row.Approval_In__c = null;
    }

    private static void applyStatus(RLY_Org__c row, RLY_Org__c saved) {
        if (saved == null) {
            row.Status__c = 'Not checked';
            row.Source_Tracking__c = 'Unknown';
        } else if (saved.My_Domain__c != row.My_Domain__c || saved.Username__c != row.Username__c) {
            // A different org or user: forget what the last check read, so it isn't taken for a refresh.
            row.Status__c = 'Not checked';
            row.Status_Message__c = null;
            row.Org_Id__c = null;
            row.Org_Type__c = null;
            row.Is_Sandbox__c = false;
            row.Api_Version__c = null;
            row.Source_Tracking__c = 'Unknown';
        }
    }

    /**
     * @description Signs in to the org and records what it finds. Callouts first, one save at the end. A consumer key
     * still in the old Client_Id__c field moves to the encrypted Consumer_Key__c in the same save.
     * @param orgId the org
     * @return the org as saved, without its consumer key
     */
    @AuraEnabled
    public static RLY_Org__c checkOrg(Id orgId) {
        if (!isAdmin()) {
            throw new AuraHandledException('Checking orgs needs the Release Relay Admin permission set.');
        }
        Data data = new Data();
        RLY_Org__c org = data.byId(orgId);
        RLY_Org__c result = RlyOrgCheck.run(org);
        if (String.isBlank(org.Consumer_Key__c) && String.isNotBlank(org.Client_Id__c)) {
            result.Consumer_Key__c = org.Client_Id__c.trim();
            result.Client_Id__c = null;
        }
        data.save(result);
        return data.view(orgId);
    }

    /**
     * @description Whether the current user is a Release Relay admin.
     * @return true for admins
     */
    public static Boolean isAdmin() {
        return FeatureManagement.checkPermission(ADMIN_PERMISSION);
    }

    /** @description Registered orgs are shared hub records: read in system mode, changed only after the admin checks above. */
    private without sharing class Data {

        /**
         * @description Every registered org for the page: no consumer key fields.
         * @return the orgs
         */
        public List<RLY_Org__c> allOrgs() {
            return [SELECT Id, Name, Role__c, My_Domain__c, Login_Type__c, Environment__c, Username__c, Certificate__c,
                           Git_Environment__c, Branch__c, Stage_Order__c, Approval_In__c, Approve_In_Salesforce__c, Approve_In_Slack__c, Require_Git_Review__c, Slack_Channel__c, Slack_Post__c, Org_Id__c, Org_Type__c, Is_Sandbox__c, Api_Version__c, Source_Tracking__c,
                           Status__c, Status_Message__c, Last_Checked__c
                    FROM RLY_Org__c WITH SYSTEM_MODE ORDER BY Role__c, Name LIMIT 200];
        }

        /**
         * @description The consumer keys of every org, to build the masked hints (never returned as they are).
         * @return Id and both key fields of each org
         */
        public List<RLY_Org__c> keys() {
            return [SELECT Id, Consumer_Key__c, Client_Id__c FROM RLY_Org__c WITH SYSTEM_MODE ORDER BY Role__c, Name LIMIT 200];
        }

        /**
         * @description One org with every field, consumer key included: for Apex only.
         * @param orgId the org
         * @return the org
         */
        public RLY_Org__c byId(Id orgId) {
            List<RLY_Org__c> rows = [SELECT Id, Name, Role__c, My_Domain__c, Login_Type__c, Environment__c, Username__c, Consumer_Key__c, Client_Id__c,
                                            Certificate__c, Git_Environment__c, Branch__c, Stage_Order__c, Approval_In__c, Approve_In_Salesforce__c, Approve_In_Slack__c, Require_Git_Review__c, Slack_Channel__c, Slack_Post__c, Org_Id__c, Org_Type__c,
                                            Is_Sandbox__c, Api_Version__c, Source_Tracking__c, Status__c, Status_Message__c, Last_Checked__c
                                     FROM RLY_Org__c WHERE Id = :orgId WITH SYSTEM_MODE];
            if (rows.isEmpty()) {
                throw new AuraHandledException('That org isn\'t registered any more.');
            }
            return rows[0];
        }

        /**
         * @description One org for the page: no consumer key fields.
         * @param orgId the org
         * @return the org
         */
        public RLY_Org__c view(Id orgId) {
            return [SELECT Id, Name, Role__c, My_Domain__c, Login_Type__c, Environment__c, Username__c, Certificate__c,
                           Git_Environment__c, Branch__c, Stage_Order__c, Approval_In__c, Approve_In_Salesforce__c, Approve_In_Slack__c, Require_Git_Review__c, Slack_Channel__c, Slack_Post__c, Org_Id__c, Org_Type__c, Is_Sandbox__c, Api_Version__c,
                           Source_Tracking__c, Status__c, Status_Message__c, Last_Checked__c
                    FROM RLY_Org__c WHERE Id = :orgId WITH SYSTEM_MODE LIMIT 1];
        }

        /**
         * @description Whether another org already has this name.
         * @param name the name
         * @param exceptId the org being saved, or null
         * @return true when taken
         */
        public Boolean nameTaken(String name, Id exceptId) {
            return ![SELECT Id FROM RLY_Org__c WHERE Name = :name AND Id != :exceptId WITH SYSTEM_MODE LIMIT 1].isEmpty();
        }

        /**
         * @description Saves an org (admins only; checked by the callers).
         * @param row the fields to save
         */
        public void save(RLY_Org__c row) {
            upsert as system row;
        }
    }
}
