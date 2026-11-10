/**
 * @description Where a release deployed to the hub was sent (the release page's Back promote step): Off, or per back
 * promote org "Sent to <org>: <state>", "<org>: waiting for Sync now" or "<org>: not sent".
 */
public with sharing class RlyBackPromoteSummary {

    private static final Map<String, String> LABELS = new Map<String, String>{
        'Submitted' => 'Queued', 'Ready for approval' => 'Waiting for approval', 'Deploying' => 'Syncing',
        'Deployed' => 'Deployed', 'Failed' => 'Failed', 'Rejected' => 'Rejected'
    };
    private static final Set<String> OPEN = new Set<String>{ 'Submitted', 'Deploying' };

    /** @description Off, or each org's state, or null for releases that didn't deploy to the hub. */
    public String text;
    /** @description A sync since the deploy is queued or running: the page keeps checking. */
    public Boolean pending = false;

    /**
     * @description Where a release deployed to the hub was sent: Off, or per back promote org "Sent to <org>: <state>",
     * "<org>: waiting for Sync now" or "<org>: not sent".
     * @param rel the release, with Target_Org__r.Role__c
     * @return the summary (text null for releases that didn't deploy to the hub)
     */
    public static RlyBackPromoteSummary forRelease(RLY_Release__c rel) {
        RlyBackPromoteSummary s = new RlyBackPromoteSummary();
        if (rel.Status__c != 'Deployed' || !RlyBackPromoteQueue.isHubDeploy(rel)) {
            return s;
        }
        if (!RlyBackPromote.isOn(RlyReleaseStore.git())) {
            s.text = 'Off';
            return s;
        }
        Datetime since = rel.Last_Synced__c == null ? rel.CreatedDate : rel.Last_Synced__c.addSeconds(-5);
        List<RLY_Release__c> latest = RlyPromoteStore.latestSyncs();
        List<String> parts = new List<String>();
        for (RLY_Org__c o : RlyPromoteStore.backPromoteOrgs()) {
            parts.add(s.part(o, syncSince(o.Id, since, latest)));
        }
        s.text = parts.isEmpty() ? 'No back promote org registered' : String.join(parts, ' · ');
        return s;
    }

    // One org's part; a queued or running sync keeps the page checking.
    private String part(RLY_Org__c o, RLY_Release__c sync) {
        if (sync == null) {
            return o.Name + (RlyBackPromote.whenOf(o) == RlyBackPromote.WHEN_MANUAL ? ': waiting for Sync now' : ': not sent');
        }
        pending = pending || OPEN.contains(sync.Status__c);
        return 'Sent to ' + o.Name + ': ' + (LABELS.containsKey(sync.Status__c) ? LABELS.get(sync.Status__c) : sync.Status__c);
    }

    // The newest sync to the org made since the deploy (latest is newest first).
    private static RLY_Release__c syncSince(Id orgId, Datetime since, List<RLY_Release__c> latest) {
        for (RLY_Release__c r : latest) {
            if (r.Target_Org__c == orgId && (since == null || r.CreatedDate >= since)) {
                return r;
            }
        }
        return null;
    }
}
