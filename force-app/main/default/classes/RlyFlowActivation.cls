/**
 * @description After a successful deploy into an org (a release, a promotion or a back promote sync just Deployed), the
 * hub activates the flows chosen Activate (RlyFlowChoices): it signs in to that org (RlyOrgSession, the org's
 * RLY_Org__c record; the hub org is registered too), reads each flow's versions and, when the latest version isn't the
 * active one, makes it active (RlyFlowVersions.activate: Tooling API FlowDefinition Metadata.activeVersionNumber). A back
 * promote sync activates the flows of the hub deploys it carries. Results per org and flow go to Flow_Results__c (JSON
 * [{org, flow, version, status: Activated | Already active | Failed, message}]) and to the history. Callouts only: the
 * caller saves the release (and the history) afterwards.
 */
public with sharing class RlyFlowActivation {

    /** @description Result status: the hub activated the latest version. */
    public static final String ACTIVATED = 'Activated';
    /** @description Result status: the latest version was active already. */
    public static final String ALREADY_ACTIVE = 'Already active';
    /** @description Result status: it couldn't be activated (message says why). */
    public static final String FAILED = 'Failed';

    /** @description One flow in one org. */
    public class Outcome {
        /** @description The org's name. */
        public String org;
        /** @description The flow's API name. */
        public String flow;
        /** @description The version now active (or the one that couldn't be activated), or null. */
        public Integer version;
        /** @description Activated, Already active or Failed. */
        public String status;
        /** @description Why it failed, or null. */
        public String message;
    }

    /**
     * @description Activates the chosen flows when the release has just been deployed.
     * @param rel the release, as read now (Status__c Deployed), with Target_Org__c and Flow_Actions__c
     * @param oldStatus its status before this read
     */
    public static void afterRead(RLY_Release__c rel, String oldStatus) {
        if (oldStatus == 'Deployed' || rel.Status__c != 'Deployed' || rel.Target_Org__c == null) {
            return;
        }
        List<String> names = namesFor(rel);
        if (names.isEmpty()) {
            return;
        }
        RLY_Org__c org = RlyReleaseStore.org(rel.Target_Org__c);
        List<Outcome> outcomes = activateAll(org, names);
        rel.Flow_Results__c = merged(rel.Flow_Results__c, outcomes);
        for (Outcome o : outcomes) {
            String detail = o.status == FAILED ? 'Flow ' + o.flow + ' couldn\'t be activated in ' + o.org + ': ' + o.message
                : 'Flow ' + o.flow + ' ' + (o.status == ACTIVATED ? 'activated' : 'already active') + ' in ' + o.org + ' (version ' + o.version + ')';
            RlyReleaseLog.add(rel, 'Flow_Activated', detail).inOrg(rel.Target_Org__c);
        }
    }

    // The release's own Activate flows; a back promote sync: those of the hub deploys it carries.
    private static List<String> namesFor(RLY_Release__c rel) {
        if (RlyPromotion.typeOf(rel) != RlyPromotion.TYPE_BACK_PROMOTE) {
            return RlyFlowChoices.toActivate(rel);
        }
        RLY_Org__c hub = RlyPromoteStore.hub();
        RLY_Org__c target;
        for (RLY_Org__c o : RlyPromoteStore.backPromoteOrgs()) {
            target = o.Id == rel.Target_Org__c ? o : target;
        }
        if (hub == null || target == null) {
            return new List<String>();
        }
        List<RLY_Release__c> carried = RlyBackPromoteSteps.behind(target, RlyPromoteStore.hubDeployed(hub.Id));
        RLY_Release__c merged = new RLY_Release__c(Flow_Actions__c = RlyFlowChoices.toField(RlyFlowChoices.union(carried)));
        return RlyFlowChoices.toActivate(merged);
    }

    /**
     * @description Signs in to the org and activates each flow's latest version; a sign-in or read failure fails them all.
     * @param org the org, with its sign-in fields
     * @param names the flows
     * @return the outcome per flow
     */
    public static List<Outcome> activateAll(RLY_Org__c org, List<String> names) {
        List<Outcome> out = new List<Outcome>();
        List<RlyFlowVersions.FlowInfo> infos;
        try {
            infos = RlyFlowVersions.read(org, names);
        } catch (Exception e) {
            for (String n : names) {
                out.add(outcome(org.Name, n, e.getMessage()));
            }
            return out;
        }
        for (RlyFlowVersions.FlowInfo f : infos) {
            out.add(activateOne(org, f));
        }
        return out;
    }

    private static Outcome activateOne(RLY_Org__c org, RlyFlowVersions.FlowInfo f) {
        if (f.latest == null || f.definitionId == null) {
            return outcome(org.Name, f.name, org.Name + ' doesn\'t have this flow.');
        }
        if (f.active == f.latest) {
            Outcome same = outcome(org.Name, f.name, null);
            same.version = f.latest;
            same.status = ALREADY_ACTIVE;
            return same;
        }
        String problem;
        try {
            problem = RlyFlowVersions.activateLatest(org, f);
        } catch (Exception e) {
            problem = e.getMessage();
        }
        Outcome o = outcome(org.Name, f.name, problem);
        o.version = f.latest;
        o.status = problem == null ? ACTIVATED : FAILED;
        return o;
    }

    private static Outcome outcome(String orgName, String flow, String problem) {
        Outcome o = new Outcome();
        o.org = orgName;
        o.flow = flow;
        o.status = FAILED;
        o.message = problem == null ? null : problem.left(500);
        return o;
    }

    /**
     * @description Adds outcomes to the stored results: one entry per org and flow, the newest kept.
     * @param resultsJson Flow_Results__c
     * @param outcomes the new outcomes
     * @return the JSON to store
     */
    public static String merged(String resultsJson, List<Outcome> outcomes) {
        Map<String, Object> byKey = new Map<String, Object>();
        for (Object o : RlyFlowResults.parse(resultsJson)) {
            Map<String, Object> m = (Map<String, Object>) o;
            byKey.put(String.valueOf(m.get('org')) + '|' + String.valueOf(m.get('flow')), m);
        }
        for (Outcome o : outcomes) {
            byKey.put(o.org + '|' + o.flow, new Map<String, Object>{ 'org' => o.org, 'flow' => o.flow, 'version' => o.version,
                'status' => o.status, 'message' => o.message });
        }
        return JSON.serialize(byKey.values()).left(32768);
    }
}
