/**
 * @description Reads and activates flow versions in a registered org through the Tooling API (RlyOrgSession):
 * FlowDefinition by DeveloperName gives the active and the latest version and the latest version's status
 * (Active, Draft, Obsolete, InvalidDraft); activating sets the definition's Metadata.activeVersionNumber.
 *
 * Activation (checked against Salesforce docs, build 15): the Metadata API FlowDefinition reference says "To activate a
 * flow, modify the metadata object and set the activeVersionNumber to the version number to activate" (0 or omitted
 * deactivates). The Tooling API exposes the same FlowDefinition with a Metadata field, so the hub sends
 * PATCH /tooling/sobjects/FlowDefinition/<Id> with {"Metadata":{"activeVersionNumber":n}} (as POST with
 * ?_HttpMethod=PATCH, which the REST API accepts for PATCH); release tools document the same call. The integration user
 * needs API access and the right to manage flows (Manage Flow; not confirmed in the pages read, so a refusal is kept per
 * org and flow). Flow test coverage: Process Automation Settings "Deploy processes and flows as active" with a Flow Test
 * Coverage percentage governs production deploys that make a flow active; the docs read tie it to deploying as active,
 * not to activating an already deployed version afterwards, and don't say either way for this call, so production can
 * still refuse it (the org's reason is shown). Setting Metadata replaces the definition's metadata: its description is
 * not sent, so an admin-set definition description can be cleared.
 */
public with sharing class RlyFlowVersions {

    /** @description A flow's versions in an org. */
    public class FlowInfo {
        /** @description The flow's API name. */
        @AuraEnabled public String name;
        /** @description The latest version's number, or null when the org doesn't have the flow. */
        @AuraEnabled public Integer latest;
        /** @description The active version's number, or null when no version is active. */
        @AuraEnabled public Integer active;
        /** @description The latest version's status: Active, Draft, Obsolete or InvalidDraft (null when missing). */
        @AuraEnabled public String latestStatus;
        /** @description The FlowDefinition's Id in that org (Apex only). */
        public String definitionId;
    }

    /**
     * @description The versions of some flows in an org: one entry per name asked, in that order (latest null when
     * the org doesn't have it). Names that can't be flow API names are left out.
     * @param org the registered org, with its sign-in fields
     * @param names the flows' API names
     * @return the versions
     */
    public static List<FlowInfo> read(RLY_Org__c org, List<String> names) {
        List<String> asked = new List<String>();
        for (String n : names == null ? new List<String>() : names) {
            if (RlyFlowChoices.isFlowName(n == null ? null : n.trim()) && !asked.contains(n.trim())) {
                asked.add(n.trim());
            }
        }
        if (asked.isEmpty()) {
            return new List<FlowInfo>();
        }
        Map<String, FlowInfo> found = query(org, asked);
        List<FlowInfo> out = new List<FlowInfo>();
        for (String n : asked) {
            FlowInfo f = found.get(n.toLowerCase());
            if (f == null) {
                f = new FlowInfo();
                f.name = n;
            }
            out.add(f);
        }
        return out;
    }

    private static Map<String, FlowInfo> query(RLY_Org__c org, List<String> asked) {
        String soql = 'SELECT Id, DeveloperName, ActiveVersion.VersionNumber, LatestVersion.VersionNumber, LatestVersion.Status '
            + 'FROM FlowDefinition WHERE DeveloperName IN (\'' + String.join(asked, '\',\'') + '\')';
        Map<String, Object> body = (Map<String, Object>) RlyOrgSession.getJson(org, RlyOrgSession.toolingQueryPath(soql));
        Map<String, FlowInfo> out = new Map<String, FlowInfo>();
        for (Object o : body.get('records') instanceof List<Object> ? (List<Object>) body.get('records') : new List<Object>()) {
            Map<String, Object> rec = (Map<String, Object>) o;
            FlowInfo f = new FlowInfo();
            f.name = String.valueOf(rec.get('DeveloperName'));
            f.definitionId = RlyEvidenceText.str(rec.get('Id'));
            Map<String, Object> activeVersion = asMap(rec.get('ActiveVersion'));
            Map<String, Object> latestVersion = asMap(rec.get('LatestVersion'));
            f.active = versionOf(activeVersion);
            f.latest = versionOf(latestVersion);
            f.latestStatus = RlyEvidenceText.str(latestVersion.get('Status'));
            out.put(f.name.toLowerCase(), f);
        }
        return out;
    }

    /**
     * @description Makes a flow's latest version the active one.
     * @param org the registered org, with its sign-in fields
     * @param f the flow, as read (definitionId and latest set)
     * @return null when it worked, otherwise the org's reason
     */
    public static String activateLatest(RLY_Org__c org, FlowInfo f) {
        String path = '/services/data/v' + RlyOrgSession.API_VERSION + '/tooling/sobjects/FlowDefinition/' + f.definitionId + '?_HttpMethod=PATCH';
        String body = JSON.serialize(new Map<String, Object>{ 'Metadata' => new Map<String, Object>{ 'activeVersionNumber' => f.latest } });
        HttpResponse res = RlyOrgSession.send(org, new RlyOrgSession.Call('POST', path).withBody(body)
            .withHeader('Content-Type', 'application/json').withHeader('Accept', 'application/json'));
        Integer code = res.getStatusCode();
        return code >= 200 && code < 300 ? null : errorOf(res);
    }

    // The message(s) of a REST error answer: [{"message","errorCode"}].
    private static String errorOf(HttpResponse res) {
        String body = String.valueOf(res.getBody());
        try {
            List<String> parts = new List<String>();
            for (Object o : (List<Object>) JSON.deserializeUntyped(body)) {
                Map<String, Object> m = asMap(o);
                parts.add(RlyEvidenceText.text(RlyEvidenceText.str(m.get('errorCode'))) + ': ' + RlyEvidenceText.text(RlyEvidenceText.str(m.get('message'))));
            }
            return ('HTTP ' + res.getStatusCode() + ' ' + String.join(parts, '; ')).left(500);
        } catch (Exception e) {
            return ('HTTP ' + res.getStatusCode() + ' ' + body).left(500);
        }
    }

    private static Map<String, Object> asMap(Object o) {
        return o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
    }

    private static Integer versionOf(Map<String, Object> flowVersion) {
        Object n = flowVersion.get('VersionNumber');
        return n == null ? null : Integer.valueOf(String.valueOf(n).substringBefore('.'));
    }
}
