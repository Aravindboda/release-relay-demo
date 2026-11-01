/**
 * @description Checks the details of an org before it's registered or changed. Each problem is a sentence
 * (without the full stop) the page shows.
 */
public with sharing class RlyOrgValidator {

    /** @description Longest consumer key the encrypted field holds. */
    public static final Integer KEY_LENGTH = 175;

    private static final Set<String> ROLES = new Set<String>{ 'Developer', 'Stage', 'Hub', 'Back_Promote' };
    private static final Set<String> BACK_PROMOTE_WHEN = new Set<String>{ 'Manual', 'After_Deploy' };
    private static final Set<String> LOGIN_TYPES = new Set<String>{ 'Production', 'Sandbox' };
    private static final Pattern DOMAIN = Pattern.compile('^https://[A-Za-z0-9.-]+\\.(salesforce|force)\\.com/?$');
    private static final Pattern API_NAME = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');
    private static final Pattern ENV_NAME = Pattern.compile('^[A-Za-z0-9 _.-]{1,80}$');
    private static final Pattern BRANCH_NAME = Pattern.compile('^[A-Za-z0-9._/-]{1,100}$');
    private static final Set<String> APPROVAL_IN = new Set<String>{ RlyApprover.IN_SALESFORCE, RlyApprover.IN_SLACK, RlyApprover.IN_GIT };
    private static final Pattern ORG_NAME = Pattern.compile('^[A-Za-z0-9 _.-]{1,40}$');

    /**
     * @description Every problem with the org's details.
     * @param o the details sent
     * @param saved the org as saved (null for a new org): a blank key keeps its key
     * @return the problems (empty when all is well)
     */
    public static List<String> validate(RLY_Org__c o, RLY_Org__c saved) {
        List<String> problems = identityProblems(o);
        problems.addAll(signInProblems(o, saved));
        if (isBad(o.Git_Environment__c, ENV_NAME)) {
            problems.add('Git environment has characters that aren\'t allowed');
        }
        if (isBad(o.Branch__c, BRANCH_NAME)) {
            problems.add('Branch has characters that aren\'t allowed');
        }
        problems.addAll(approvalProblems(o));
        return problems;
    }

    // Where releases are approved, and the Slack channel they post to.
    private static List<String> approvalProblems(RLY_Org__c o) {
        List<String> problems = new List<String>();
        if (String.isNotBlank(o.Approval_In__c) && !APPROVAL_IN.contains(o.Approval_In__c)) {
            problems.add('Pick where releases are approved: In Salesforce, In Slack or In the Git provider');
        }
        if (String.isNotBlank(o.Back_Promote_When__c) && !BACK_PROMOTE_WHEN.contains(o.Back_Promote_When__c)) {
            problems.add('Pick when a back promote org gets the changes: Manual or After_Deploy');
        }
        if (String.isNotBlank(o.Slack_Channel__c) && !RlySlackRules.isChannel(o.Slack_Channel__c)) {
            problems.add('Slack channel must be a channel name such as #channel-name, or a channel ID');
        }
        return problems;
    }

    /**
     * @description The consumer key sent with the details, trimmed: Consumer_Key__c, or Client_Id__c from older pages.
     * @param o the details sent
     * @return the key, or null when none was sent
     */
    public static String submittedKey(RLY_Org__c o) {
        if (String.isNotBlank(o.Consumer_Key__c)) {
            return o.Consumer_Key__c.trim();
        }
        return String.isBlank(o.Client_Id__c) ? null : o.Client_Id__c.trim();
    }

    private static List<String> identityProblems(RLY_Org__c o) {
        List<String> problems = new List<String>();
        if (!matches(o.Name, ORG_NAME)) {
            problems.add('Org name is required: up to 40 letters, numbers, spaces, dots, dashes or underscores');
        }
        if (!ROLES.contains(o.Role__c)) {
            problems.add('Pick a role: Developer, Stage, Hub or Back promote');
        }
        if (!matches(o.My_Domain__c, DOMAIN)) {
            problems.add('My Domain URL must look like https://yourdomain.my.salesforce.com');
        }
        if (!LOGIN_TYPES.contains(o.Login_Type__c)) {
            problems.add('Pick a login type: Production or Sandbox');
        }
        return problems;
    }

    private static List<String> signInProblems(RLY_Org__c o, RLY_Org__c saved) {
        List<String> problems = new List<String>();
        if (String.isBlank(o.Username__c) || !o.Username__c.contains('@') || o.Username__c.trim().length() > 255) {
            problems.add('Integration username must be a Salesforce username');
        }
        if (!keyIsUsable(submittedKey(o), saved)) {
            problems.add('Consumer key is required: the consumer key of the org\'s External Client App');
        }
        if (!matches(o.Certificate__c, API_NAME)) {
            problems.add('Hub certificate must be the API name of a certificate in this hub');
        }
        return problems;
    }

    // A new key must fit and have no spaces; no key is fine only when the org already has one saved.
    private static Boolean keyIsUsable(String key, RLY_Org__c saved) {
        if (key == null) {
            return saved != null && RlyOrgSession.consumerKey(saved) != null;
        }
        return key.length() <= KEY_LENGTH && !key.contains(' ');
    }

    private static Boolean matches(String value, Pattern p) {
        return String.isNotBlank(value) && p.matcher(value.trim()).matches();
    }

    private static Boolean isBad(String optionalValue, Pattern p) {
        return String.isNotBlank(optionalValue) && !p.matcher(optionalValue.trim()).matches();
    }

    /**
     * @description Reads the org details the page sends.
     * @param orgJson the org's fields as JSON
     * @return the org
     */
    public static RLY_Org__c readInput(String orgJson) {
        try {
            return (RLY_Org__c) JSON.deserialize(orgJson, RLY_Org__c.class);
        } catch (Exception e) {
            throw new AuraHandledException('The org details couldn\'t be read.');
        }
    }
}
