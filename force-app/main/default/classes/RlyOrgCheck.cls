/**
 * @description The sign-in check of a registered org: signs in and reads the org's identity, its newest API
 * version and whether it has source tracking, with any recommendation. Callouts only; the caller saves.
 */
public with sharing class RlyOrgCheck {

    /** @description Shown for a sandbox without source tracking. */
    public static final String TRACKING_HINT_SANDBOX = 'Turn on source tracking for faster change lists: in production, '
        + 'Setup > Dev Hub > Enable Source Tracking in Developer and Developer Pro Sandboxes, then refresh this sandbox. '
        + 'Partial and Full Copy sandboxes don\'t support it. Until then, changes are listed with the Metadata API.';
    /** @description Shown for other orgs without source tracking. */
    public static final String TRACKING_HINT_NONE = 'Source tracking isn\'t available for this org type, so changes are listed with the Metadata API.';

    /**
     * @description The check itself, without saving.
     * @param org the org, with its sign-in fields and the Org Id on file
     * @return the fields to save: status, message, identity, API version and source tracking
     */
    public static RLY_Org__c run(RLY_Org__c org) {
        RLY_Org__c out = new RLY_Org__c(Id = org.Id, Last_Checked__c = Datetime.now());
        List<String> notes = new List<String>();
        try {
            out.Api_Version__c = newestApiVersion(org);
            readIdentity(org, out, notes);
            readTracking(org, out, notes);
            out.Status__c = 'Connected';
        } catch (Exception e) {
            out.Status__c = 'Failed';
            notes.add(e.getMessage());
        }
        out.Status_Message__c = notes.isEmpty() ? null : String.join(notes, '\n').left(2000);
        return out;
    }

    private static void readIdentity(RLY_Org__c org, RLY_Org__c out, List<String> notes) {
        Map<String, Object> info = (Map<String, Object>) firstRecord(RlyOrgSession.getJson(org,
            RlyOrgSession.queryPath('SELECT Id, Name, OrganizationType, IsSandbox FROM Organization LIMIT 1')));
        String orgId = String.valueOf(info.get('Id'));
        out.Org_Type__c = info.get('OrganizationType') == null ? null : String.valueOf(info.get('OrganizationType')).left(80);
        out.Is_Sandbox__c = info.get('IsSandbox') == true;
        if (String.isNotBlank(org.Org_Id__c) && org.Org_Id__c != orgId) {
            notes.add('The Org Id changed since the last check, so this sandbox was refreshed. The new Org Id is saved.');
        }
        out.Org_Id__c = orgId;
    }

    private static void readTracking(RLY_Org__c org, RLY_Org__c out, List<String> notes) {
        out.Source_Tracking__c = hasSourceTracking(org) ? 'Available' : 'Not available';
        if (out.Source_Tracking__c == 'Not available') {
            notes.add(out.Is_Sandbox__c ? TRACKING_HINT_SANDBOX : TRACKING_HINT_NONE);
        }
        if (org.Login_Type__c == 'Production' && out.Is_Sandbox__c) {
            notes.add('This org is a sandbox: open it, press Edit and save so its Login type is read from the My Domain URL.');
        }
    }

    // Newest version from /services/data, or the hub's own when the list is empty.
    private static String newestApiVersion(RLY_Org__c org) {
        Object versions = RlyOrgSession.getJson(org, '/services/data/');
        String newest = RlyOrgSession.API_VERSION;
        Decimal best = 0;
        if (versions instanceof List<Object>) {
            for (Object o : (List<Object>) versions) {
                String v = String.valueOf(((Map<String, Object>) o).get('version'));
                Decimal d = toVersion(v);
                if (d != null && d > best) {
                    best = d;
                    newest = v;
                }
            }
        }
        return newest;
    }

    private static Decimal toVersion(String v) {
        try {
            return Decimal.valueOf(v);
        } catch (Exception e) {
            return null;
        }
    }

    // Source tracking exists when the Tooling API can query SourceMember.
    private static Boolean hasSourceTracking(RLY_Org__c org) {
        HttpResponse res = RlyOrgSession.send(org, new RlyOrgSession.Call('GET',
            RlyOrgSession.toolingQueryPath('SELECT Id FROM SourceMember LIMIT 1')).withHeader('Accept', 'application/json'));
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
}
