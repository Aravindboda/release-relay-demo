/**
 * Pipeline tab: the orgs registered in the Release Relay hub.
 *   getOrgs     every registered org, with its last check
 *   saveOrg     add or change one (admins); its sign-in is checked next by checkOrg
 *   checkOrg    signs in and reads the org's identity, newest API version and whether it has
 *               source tracking; records the result and any recommendation
 */
public with sharing class RlyOrgController {

    public static final String ADMIN_PERMISSION = 'RLY_Admin';
    private static final Set<String> ROLES = new Set<String>{ 'Developer', 'Stage', 'Hub' };
    private static final Set<String> LOGIN_TYPES = new Set<String>{ 'Production', 'Sandbox' };
    private static final Pattern DOMAIN = Pattern.compile('^https://[A-Za-z0-9.-]+\\.(salesforce|force)\\.com/?$');
    private static final Pattern API_NAME = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');
    private static final Pattern ENV_NAME = Pattern.compile('^[A-Za-z0-9 _.-]{1,80}$');
    private static final Pattern BRANCH_NAME = Pattern.compile('^[A-Za-z0-9._/-]{1,100}$');
    private static final Pattern ORG_NAME = Pattern.compile('^[A-Za-z0-9 _.-]{1,40}$');

    public static final String TRACKING_HINT_SANDBOX = 'Turn on source tracking for faster change lists: in production, '
        + 'Setup > Dev Hub > Enable Source Tracking in Developer and Developer Pro Sandboxes, then refresh this sandbox. '
        + 'Partial and Full Copy sandboxes don\'t support it. Until then, changes are listed with the Metadata API.';
    public static final String TRACKING_HINT_NONE = 'Source tracking isn\'t available for this org type, so changes are listed with the Metadata API.';

    public class HubInfo {
        @AuraEnabled public String hubDomain;
        @AuraEnabled public Boolean isAdmin;
        @AuraEnabled public List<RLY_Org__c> orgs;
    }

    @AuraEnabled
    public static HubInfo getOrgs() {
        HubInfo h = new HubInfo();
        h.hubDomain = URL.getOrgDomainUrl().toExternalForm();
        h.isAdmin = isAdmin();
        h.orgs = new Data().allOrgs();
        return h;
    }

    /** Adds or updates a registered org. Identity fields are cleared when the domain or user changes. */
    @AuraEnabled
    public static Id saveOrg(String orgJson) {
        if (!isAdmin()) {
            throw new AuraHandledException('Registering orgs needs the Release Relay Admin permission set.');
        }
        RLY_Org__c input;
        try {
            input = (RLY_Org__c) JSON.deserialize(orgJson, RLY_Org__c.class);
        } catch (Exception e) {
            throw new AuraHandledException('The org details couldn\'t be read.');
        }
        List<String> problems = validate(input);
        if (!problems.isEmpty()) {
            throw new AuraHandledException(String.join(problems, '. ') + '.');
        }
        Data data = new Data();
        if (data.nameTaken(input.Name.trim(), input.Id)) {
            throw new AuraHandledException('An org named ' + input.Name.trim() + ' is already registered.');
        }
        RLY_Org__c row = new RLY_Org__c(
            Id = input.Id,
            Name = input.Name.trim(),
            Role__c = input.Role__c,
            My_Domain__c = input.My_Domain__c.trim().removeEnd('/'),
            Login_Type__c = input.Login_Type__c,
            Username__c = input.Username__c.trim(),
            Client_Id__c = input.Client_Id__c.trim(),
            Certificate__c = input.Certificate__c.trim(),
            Git_Environment__c = String.isBlank(input.Git_Environment__c) ? null : input.Git_Environment__c.trim(),
            Branch__c = String.isBlank(input.Branch__c) ? null : input.Branch__c.trim()
        );
        if (row.Id != null) {
            RLY_Org__c old = data.byId(row.Id);
            if (old.My_Domain__c != row.My_Domain__c || old.Username__c != row.Username__c) {
                // A different org or user: forget what the last check read, so it isn't taken for a refresh.
                row.Status__c = 'Not checked';
                row.Status_Message__c = null;
                row.Org_Id__c = null;
                row.Org_Type__c = null;
                row.Is_Sandbox__c = false;
                row.Api_Version__c = null;
                row.Source_Tracking__c = 'Unknown';
            }
        } else {
            row.Status__c = 'Not checked';
            row.Source_Tracking__c = 'Unknown';
        }
        data.save(row);
        return row.Id;
    }

    /** Signs in to the org and records what it finds. Callouts first, one save at the end. */
    @AuraEnabled
    public static RLY_Org__c checkOrg(Id orgId) {
        if (!isAdmin()) {
            throw new AuraHandledException('Checking orgs needs the Release Relay Admin permission set.');
        }
        Data data = new Data();
        RLY_Org__c org = data.byId(orgId);
        RLY_Org__c result = check(org);
        data.save(result);
        return data.byId(orgId);
    }

    /** The check itself, without saving. */
    @TestVisible
    private static RLY_Org__c check(RLY_Org__c org) {
        RLY_Org__c out = new RLY_Org__c(Id = org.Id, Last_Checked__c = Datetime.now());
        List<String> notes = new List<String>();
        try {
            out.Api_Version__c = newestApiVersion(org);

            Map<String, Object> info = (Map<String, Object>) firstRecord(RlyOrgSession.getJson(org,
                RlyOrgSession.queryPath('SELECT Id, Name, OrganizationType, IsSandbox FROM Organization LIMIT 1', false)));
            String orgId = String.valueOf(info.get('Id'));
            out.Org_Type__c = info.get('OrganizationType') == null ? null : String.valueOf(info.get('OrganizationType')).left(80);
            out.Is_Sandbox__c = info.get('IsSandbox') == true;
            if (String.isNotBlank(org.Org_Id__c) && org.Org_Id__c != orgId) {
                notes.add('The Org Id changed since the last check, so this sandbox was refreshed. The new Org Id is saved.');
            }
            out.Org_Id__c = orgId;

            out.Source_Tracking__c = hasSourceTracking(org) ? 'Available' : 'Not available';
            if (out.Source_Tracking__c == 'Not available') {
                notes.add(out.Is_Sandbox__c ? TRACKING_HINT_SANDBOX : TRACKING_HINT_NONE);
            }
            if (org.Login_Type__c == 'Production' && out.Is_Sandbox__c) {
                notes.add('This org is a sandbox: set Login type to Sandbox.');
            }
            out.Status__c = 'Connected';
        } catch (Exception e) {
            out.Status__c = 'Failed';
            notes.add(e.getMessage());
        }
        out.Status_Message__c = notes.isEmpty() ? null : String.join(notes, '\n').left(2000);
        return out;
    }

    /** Newest version from /services/data, or the hub's own when the list is empty. */
    private static String newestApiVersion(RLY_Org__c org) {
        Object versions = RlyOrgSession.getJson(org, '/services/data/');
        String newest = RlyOrgSession.API_VERSION;
        Decimal best = 0;
        if (versions instanceof List<Object>) {
            for (Object o : (List<Object>) versions) {
                String v = String.valueOf(((Map<String, Object>) o).get('version'));
                Decimal d;
                try {
                    d = Decimal.valueOf(v);
                } catch (Exception e) {
                    continue;
                }
                if (d > best) {
                    best = d;
                    newest = v;
                }
            }
        }
        return newest;
    }

    /** Source tracking exists when the Tooling API can query SourceMember. */
    private static Boolean hasSourceTracking(RLY_Org__c org) {
        HttpResponse res = RlyOrgSession.send(org, 'GET',
            RlyOrgSession.queryPath('SELECT Id FROM SourceMember LIMIT 1', true), null,
            new Map<String, String>{ 'Accept' => 'application/json' });
        if (res.getStatusCode() == 200) {
            return true;
        }
        String body = String.valueOf(res.getBody());
        if (res.getStatusCode() == 400 && (body.contains('INVALID_TYPE') || body.contains('not supported'))) {
            return false;
        }
        throw new RlyOrgSession.SignInException('Couldn\'t tell whether ' + org.Name + ' has source tracking: HTTP '
            + res.getStatusCode() + ' ' + body.left(300));
    }

    private static Object firstRecord(Object body) {
        List<Object> records = (List<Object>) ((Map<String, Object>) body).get('records');
        if (records == null || records.isEmpty()) {
            throw new RlyOrgSession.SignInException('The org returned no Organization record. Does the integration user have API access?');
        }
        return records[0];
    }

    @TestVisible
    private static List<String> validate(RLY_Org__c o) {
        List<String> problems = new List<String>();
        if (String.isBlank(o.Name) || !ORG_NAME.matcher(o.Name.trim()).matches()) {
            problems.add('Org name is required: up to 40 letters, numbers, spaces, dots, dashes or underscores');
        }
        if (!ROLES.contains(o.Role__c)) {
            problems.add('Pick a role: Developer, Stage or Hub');
        }
        if (String.isBlank(o.My_Domain__c) || !DOMAIN.matcher(o.My_Domain__c.trim()).matches()) {
            problems.add('My Domain URL must look like https://yourdomain.my.salesforce.com');
        }
        if (!LOGIN_TYPES.contains(o.Login_Type__c)) {
            problems.add('Pick a login type: Production or Sandbox');
        }
        if (String.isBlank(o.Username__c) || !o.Username__c.contains('@') || o.Username__c.trim().length() > 255) {
            problems.add('Integration username must be a Salesforce username');
        }
        if (String.isBlank(o.Client_Id__c) || o.Client_Id__c.trim().length() > 255 || o.Client_Id__c.trim().contains(' ')) {
            problems.add('Client Id is required: the consumer key of the org\'s External Client App');
        }
        if (String.isBlank(o.Certificate__c) || !API_NAME.matcher(o.Certificate__c.trim()).matches()) {
            problems.add('Hub certificate must be the API name of a certificate in this hub');
        }
        if (String.isNotBlank(o.Git_Environment__c) && !ENV_NAME.matcher(o.Git_Environment__c.trim()).matches()) {
            problems.add('Git environment has characters that aren\'t allowed');
        }
        if (String.isNotBlank(o.Branch__c) && !BRANCH_NAME.matcher(o.Branch__c.trim()).matches()) {
            problems.add('Branch has characters that aren\'t allowed');
        }
        return problems;
    }

    public static Boolean isAdmin() {
        return FeatureManagement.checkPermission(ADMIN_PERMISSION);
    }

    /** Registered orgs are read by every hub user and changed only after the admin checks above. */
    private without sharing class Data {
        public List<RLY_Org__c> allOrgs() {
            return [SELECT Id, Name, Role__c, My_Domain__c, Login_Type__c, Username__c, Client_Id__c, Certificate__c,
                           Git_Environment__c, Branch__c, Stage_Order__c, Org_Id__c, Org_Type__c, Is_Sandbox__c, Api_Version__c, Source_Tracking__c,
                           Status__c, Status_Message__c, Last_Checked__c
                    FROM RLY_Org__c ORDER BY Role__c, Name LIMIT 200];
        }
        public RLY_Org__c byId(Id orgId) {
            List<RLY_Org__c> rows = [SELECT Id, Name, Role__c, My_Domain__c, Login_Type__c, Username__c, Client_Id__c, Certificate__c,
                                            Git_Environment__c, Branch__c, Stage_Order__c, Org_Id__c, Org_Type__c, Is_Sandbox__c, Api_Version__c, Source_Tracking__c,
                                            Status__c, Status_Message__c, Last_Checked__c
                                     FROM RLY_Org__c WHERE Id = :orgId];
            if (rows.isEmpty()) {
                throw new AuraHandledException('That org isn\'t registered any more.');
            }
            return rows[0];
        }
        public Boolean nameTaken(String name, Id exceptId) {
            return ![SELECT Id FROM RLY_Org__c WHERE Name = :name AND Id != :exceptId LIMIT 1].isEmpty();
        }
        public void save(RLY_Org__c row) {
            upsert row;
        }
    }
}
