/**
 * @description The Credentials dashboard's rows for the pages (build 49): each saved row with its days left and how to
 * renew its kind, worst first. No queries and no callouts.
 */
public with sharing class RlyCredentialViews {

    /** @description One row for the pages. */
    public class Row {
        /** @description Its key. */
        @AuraEnabled public String key;
        /** @description Certificate, Git token, Slack, Integration user or Org sign-in. */
        @AuraEnabled public String kind;
        /** @description What it is. */
        @AuraEnabled public String name;
        /** @description Its org, or null. */
        @AuraEnabled public String orgName;
        /** @description OK, Expiring, Critical, Expired, Failed or Unknown. */
        @AuraEnabled public String status;
        /** @description When it expires, or null. */
        @AuraEnabled public Date expiresOn;
        /** @description Days left, or null. */
        @AuraEnabled public Integer daysLeft;
        /** @description When it was last checked. */
        @AuraEnabled public Datetime lastChecked;
        /** @description When it was last OK. */
        @AuraEnabled public Datetime lastOk;
        /** @description What the check found. */
        @AuraEnabled public String message;
        /** @description How to renew this kind. */
        @AuraEnabled public String renew;
    }

    /**
     * @description The rows for the pages, worst first, then by kind and name.
     * @param rows the saved rows
     * @return the page rows
     */
    public static List<Row> sorted(List<RLY_Credential_Status__c> rows) {
        Map<String, List<Row>> byStatus = new Map<String, List<Row>>();
        for (RLY_Credential_Status__c s : rows) {
            Row r = rowOf(s);
            String status = RlyCredentialRows.WORST_FIRST.contains(r.status) ? r.status : RlyCredentialRows.UNKNOWN;
            if (!byStatus.containsKey(status)) {
                byStatus.put(status, new List<Row>());
            }
            byStatus.get(status).add(r);
        }
        List<Row> out = new List<Row>();
        for (String status : RlyCredentialRows.WORST_FIRST) {
            if (byStatus.containsKey(status)) {
                out.addAll(byStatus.get(status));
            }
        }
        return out;
    }

    /**
     * @description A saved row for the pages.
     * @param s the row
     * @return the page row
     */
    public static Row rowOf(RLY_Credential_Status__c s) {
        Row r = new Row();
        r.key = s.Key__c;
        r.kind = s.Kind__c;
        r.name = s.Name;
        r.orgName = s.Org__r == null ? null : s.Org__r.Name;
        r.status = String.isBlank(s.Status__c) ? RlyCredentialRows.UNKNOWN : s.Status__c;
        r.expiresOn = s.Expires_On__c;
        r.daysLeft = s.Expires_On__c == null ? null : RlyCredentialRows.today().daysBetween(s.Expires_On__c);
        r.lastChecked = s.Last_Checked__c;
        r.lastOk = s.Last_OK__c;
        r.message = s.Message__c;
        r.renew = howToRenew(s.Kind__c, s.Name);
        return r;
    }

    /**
     * @description How to renew a credential of this kind.
     * @param kind the kind
     * @param name the row's name (the provider shows in it for Git tokens)
     * @return the line
     */
    public static String howToRenew(String kind, String name) {
        if (kind == RlyCredentialRows.KIND_CERT) {
            return 'Setup → Certificate and Key Management → create a new certificate, upload it to each org\'s connected app, '
                + 'then update SF_JKS in GitHub / GitLab (and the org\'s Certificate on the Pipeline tab).';
        }
        if (kind == RlyCredentialRows.KIND_GIT) {
            return name != null && name.startsWith('GitLab')
                ? 'Create a new project access token in GitLab and paste it into the RLY_Git_GitLab credential\'s principal.'
                : 'Regenerate the token in GitHub (a bot account or GitHub App, not a person) and paste it into the RLY_Git_GitHub credential\'s principal.';
        }
        if (kind == RlyCredentialRows.KIND_SLACK) {
            return 'Reinstall the Slack app or paste its bot token into the RLY_Slack credential\'s principal.';
        }
        if (kind == RlyCredentialRows.KIND_USER) {
            return 'Activate the integration user in the org, or register a new one on the org (Pipeline → the org → Edit).';
        }
        return 'Open the org on the Pipeline tab and Check its sign-in; see the guide\'s sign-in problems for the fix.';
    }

}
