/**
 * @description Build 60 (D38): the target org has changes its branch doesn't (someone changed a layout or permission set
 * there by hand), for components this release brings, so deploying it would replace them. The latest validation keeps
 * them on Org_Drift__c ([{component, items}]); while it's set, an approver confirms on the release page that they'll be
 * replaced (the Slack card can't), and History records who did.
 */
public with sharing class RlyOrgDrift {

    /** @description Event_Type__c of the History event. */
    public static final String EVENT = 'Drift_Accepted';

    /** @description One component the target org changed. */
    public class Entry {
        /** @description Type:Name. */
        public String component;
        /** @description The lines the target org has that its branch doesn't. */
        public List<String> items;
    }

    /**
     * @description The components the target org changed, from the latest validation.
     * @param rel the release, with Org_Drift__c
     * @return the components (empty when none)
     */
    public static List<Entry> entries(RLY_Release__c rel) {
        if (rel == null || String.isBlank(rel.Org_Drift__c)) {
            return new List<Entry>();
        }
        try {
            List<Entry> parsed = (List<Entry>) JSON.deserialize(rel.Org_Drift__c, List<Entry>.class);
            return parsed == null ? new List<Entry>() : parsed;
        } catch (JSONException e) {
            return new List<Entry>();
        }
    }

    /**
     * @description Refuses an approval that hasn't confirmed the target's own changes will be replaced; records it when it has.
     * @param rel the release, with Org_Drift__c and Target_Org__r.Name
     * @param who who approves, with acknowledgedDrift
     */
    public static void require(RLY_Release__c rel, RlyApprover who) {
        List<Entry> drift = entries(rel);
        if (drift.isEmpty() || who == null) {
            return;
        }
        String org = rel.Target_Org__r == null ? 'The target org' : rel.Target_Org__r.Name;
        if (who.via == RlyApprover.VIA_SLACK) {
            throw new RlyReleaseException(org + ' has its own changes to ' + words(drift.size())
                + ' that this release would replace. Approve it on the release page in Salesforce, where the approver confirms that.');
        }
        if (who.acknowledgedDrift != true) {
            throw new RlyReleaseException('Tick "I know ' + org + '\'s own changes to these ' + words(drift.size())
                + ' will be replaced" to approve, or bring them into the branch first.');
        }
        RlyReleaseLog.add(rel, EVENT, (who.name == null ? 'The approver' : who.name) + ' confirmed that ' + org
            + '\'s own changes to ' + names(drift) + ' will be replaced').byActor(who.userId, who.via);
    }

    private static String words(Integer n) {
        return n + (n == 1 ? ' component' : ' components');
    }

    private static String names(List<Entry> drift) {
        List<String> out = new List<String>();
        for (Entry e : drift) {
            out.add(String.isBlank(e.component) ? '?' : e.component.substringAfter(':'));
        }
        return String.join(out, ', ').left(1000);
    }
}
