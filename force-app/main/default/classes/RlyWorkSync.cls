/**
 * @description Work items (build 40): a release's moment for its tickets, and posting it. A release's moment comes
 * from its status (Raised from DEV1, Ready for approval in SIT, Waiting to deploy to PROD, Deployed to SIT, Checks
 * failed in SIT, Rolled back in SIT, Rejected…); each ticket row keeps the moment last posted, so a moment is posted
 * once. With a tracker integration it's posted to the ticket through the ticket's own tracker (RlyWorkTracker, build
 * 47); without one, or with that tracker off or not posting, the row records it as tracked here. Runs from page reads (the release page after each check, the Work items tab): every callout first,
 * then one save, never a callout after DML.
 */
public with sharing class RlyWorkSync {

    /** @description Posted to the tracker. */
    public static final String POSTED = 'Posted';
    /** @description The post failed (Try again posts it again). */
    public static final String FAILED = 'Failed';
    /** @description No integration: Release Relay keeps the status. */
    public static final String TRACKED_HERE = 'Tracked here';
    /** @description Most tickets posted in one call. */
    public static final Integer PER_CALL = 10;

    /**
     * @description The moment a release's tickets are at, or null while nothing new happens (a deploy running).
     * @param rel the release, with its orgs' names
     * @return the moment
     */
    public static String momentOf(RLY_Release__c rel) {
        String target = rel.Target_Org__r == null ? 'the target' : rel.Target_Org__r.Name;
        if (String.isNotBlank(rel.Rollback_Status__c) && rel.Rollback_Status__c.containsIgnoreCase('rolled back')) {
            return 'Rolled back in ' + target;
        }
        switch on rel.Status__c {
            when 'Deployed' {
                return 'Deployed to ' + target;
            }
            when 'Checks failed' {
                return 'Checks failed in ' + target;
            }
            when 'Deploy failed', 'Failed' {
                return 'Deploy failed in ' + target;
            }
            when 'Ready for approval' {
                return RlyWorkGate.isWaiting(rel) || rel.Approval_Status__c == 'Approved' ? 'Waiting to deploy to ' + target
                    : 'Ready for approval in ' + target;
            }
            when 'Rejected', 'Closed' {
                return rel.Status__c;
            }
            when 'Deploying' {
                return null;
            }
            when else {
                return RlyPromotion.typeOf(rel) == RlyPromotion.TYPE_RELEASE || rel.Source_Org__r == null
                    ? 'Raised' + (rel.Source_Org__r == null ? '' : ' from ' + rel.Source_Org__r.Name) : 'Promoted to ' + target;
            }
        }
    }

    /**
     * @description Posts a release's moment to its tickets that haven't had it, and lets a release waiting for an
     * approved change deploy once the change allows it. Callouts first, then the saves.
     * @param releaseId the release
     * @return true when something was saved
     */
    public static Boolean postRelease(Id releaseId) {
        RLY_Release__c rel = RlyWorkStore.release(releaseId);
        if (rel == null) {
            return false;
        }
        List<RLY_Work_Item__c> changed = postAll(RlyWorkStore.forRelease(releaseId), rel);
        RLY_Release__c full = RlyWorkGate.isWaiting(rel) ? RlyReleaseStore.release(releaseId) : null; // every field the save writes
        Boolean releaseChanged = full != null && RlyWorkGate.retry(full);
        RlyWorkStore.save(changed, null, null);
        if (releaseChanged) {
            RlyReleaseStore.save(full);
        }
        return releaseChanged || !changed.isEmpty();
    }

    /**
     * @description The Work items tab: posts the newest releases' moments their tickets haven't had (up to PER_CALL).
     * @return how many tickets were updated
     */
    public static Integer postRecent() {
        List<RLY_Work_Item__c> changed = new List<RLY_Work_Item__c>();
        for (RLY_Work_Item__c w : RlyWorkStore.recent()) {
            if (changed.size() >= PER_CALL) {
                break;
            }
            changed.addAll(postAll(new List<RLY_Work_Item__c>{ w }, w.Release__r));
        }
        RlyWorkStore.save(changed, null, null);
        return changed.size();
    }

    // The rows whose moment changed, posted (or recorded as tracked here); no DML.
    private static List<RLY_Work_Item__c> postAll(List<RLY_Work_Item__c> rows, RLY_Release__c rel) {
        List<RLY_Work_Item__c> out = new List<RLY_Work_Item__c>();
        String moment = rel == null ? null : momentOf(rel);
        if (moment == null) {
            return out;
        }
        RlyWorkTypes.Message m = new RlyWorkTypes.Message();
        m.moment = moment;
        m.text = textOf(rel, moment);
        m.data = dataOf(rel, moment);
        for (RLY_Work_Item__c w : rows) {
            if (moment != w.Posted_State__c && out.size() < PER_CALL) {
                out.add(postOne(w, m, RlyWorkRouting.trackerOf(w)));
            }
        }
        return out;
    }

    // One ticket's row after posting the moment through its own tracker (or recording it as tracked here); a ticket
    // saved before build 47 gets the tracker its pattern matches.
    private static RLY_Work_Item__c postOne(RLY_Work_Item__c w, RlyWorkTypes.Message m, RLY_Work_Tracker__c s) {
        RLY_Work_Item__c row = new RLY_Work_Item__c(Key__c = w.Key__c, Synced_On__c = System.now(), Sync_Status__c = TRACKED_HERE,
            Sync_Message__c = m.moment, Posted_State__c = m.moment);
        if (w.Tracker__c == null && s != null && s.Id != null) {
            row.Tracker__c = s.Id;
        }
        if (RlyWorkTracker.posts(s)) {
            m.ticket = w.Ticket__c;
            RlyWorkTypes.Outcome o = RlyWorkTracker.post(s, m);
            row.Sync_Status__c = o.ok ? POSTED : FAILED;
            row.Sync_Message__c = o.message == null ? null : o.message.left(255);
            row.Posted_State__c = o.ok ? m.moment : w.Posted_State__c;
        }
        return row;
    }

    // Release Relay: REL-00044 "Title": Deployed to SIT (7 Nov 2026 2:05 PM) <link>
    private static String textOf(RLY_Release__c rel, String moment) {
        return 'Release Relay: ' + rel.Name + ' "' + String.valueOf(rel.Title__c).left(120) + '": ' + moment + ' (' + System.now().format() + ')\n'
            + linkOf(rel);
    }

    private static Map<String, Object> dataOf(RLY_Release__c rel, String moment) {
        return new Map<String, Object>{ 'release' => rel.Name, 'title' => rel.Title__c, 'status' => rel.Status__c,
            'org' => rel.Target_Org__r == null ? null : rel.Target_Org__r.Name, 'url' => linkOf(rel), 'momentText' => moment };
    }

    private static String linkOf(RLY_Release__c rel) {
        return URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/RLY_Release__c/' + rel.Id + '/view';
    }
}
