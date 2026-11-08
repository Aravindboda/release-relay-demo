/**
 * @description Settles an add to an open release once its hub run tells (build 52). The add's components are counted and
 * listed when the run starts (RlyAppendRun), but the branch gets them only when the run's raise step works: raise.json
 * Opened (or a run that ended green) confirms the add; raise.json Failed, or a run that failed without one, undoes it:
 * the add's items are removed after the save, the release's counts, tests and deletions go back to before the add, and
 * the release says "Not added: the pipeline failed" with the retry (Add changes again). Only the hub run is read: a later
 * Check again (another run) never undoes an add.
 */
public with sharing class RlyAppendSettle {

    private static final String OPENED = 'Opened';
    private static final String FAILED = 'Failed';

    /**
     * @description Reads the hub run's raise.json while an add waits for it, and confirms or undoes the add.
     * @param rel the release, read by RlyCheckReader
     * @param git the Git provider
     * @param run the release's run, or null
     */
    public static void settle(RLY_Release__c rel, RlyGit git, RlyGit.Run run) {
        RlyAppendRun.State st = RlyAppendRun.stateOf(rel);
        if (!st.confirming || rel.Pending_Run__c != RlyAppendRun.HUB_RUN) {
            return;
        }
        Map<String, Object> raise = RlyPipelineRun.result(git, rel, 'raise');
        String outcome = outcomeOf(raise == null ? null : String.valueOf(raise.get('status')), run);
        if (outcome == OPENED) {
            RlyAppendRun.settled(rel);
        } else if (outcome == FAILED) {
            Object said = raise == null ? null : raise.get('message');
            notAdded(rel, st, said == null ? 'the run failed before it added them; open the run for the reason' : String.valueOf(said));
        }
    }

    /**
     * @description What the run says of the add: Opened (made), Failed (not made) or null (not known yet).
     * @param raiseStatus raise.json's status, or null when there is none for this run
     * @param run the run, or null
     * @return Opened, Failed or null
     */
    public static String outcomeOf(String raiseStatus, RlyGit.Run run) {
        if (raiseStatus == OPENED || raiseStatus == FAILED) {
            return raiseStatus;
        }
        if (run == null || !run.completed()) {
            return null;
        }
        return run.failed() ? FAILED : OPENED;
    }

    /**
     * @description Undoes an add the pipeline didn't make: its items go (after the save), the release's counts, tests
     * and deletions go back, and the release says why and how to retry.
     * @param rel the release
     * @param st its add state
     * @param why what the run said
     */
    public static void notAdded(RLY_Release__c rel, RlyAppendRun.State st, String why) {
        RlyAppendRun.removeLater(itemsOf(rel.Id, st));
        Decimal count = (rel.Component_Count__c == null ? 0 : rel.Component_Count__c) - st.components.size();
        rel.Component_Count__c = count < 0 ? Decimal.valueOf(0) : count;
        List<String> deletions = without(RlyDeletions.of(rel), new Set<String>(st.deletions));
        rel.Deletions__c = deletions.isEmpty() ? null : String.join(deletions, ',').left(RlyDeletions.MAX_LENGTH);
        rel.Deletion_Count__c = deletions.size();
        rel.Test_Classes__c = String.join(without(RlyReleasePhase.tests(rel), new Set<String>(st.tests)), ',');
        String text = 'Not added: the pipeline failed to add the changes from ' + st.fromOrg + ' (' + why.left(800) + '). '
            + rel.Name + ' is as it was before the add: press Add changes to try again.';
        rel.Error_Message__c = text.left(2000);
        RlyReleaseLog.add(rel, RlyAppendRun.ADDED_EVENT, text);
        RlyAppendRun.settled(rel);
    }

    // The release's items the add brought (its components, and its deletions marked as such).
    private static List<RLY_Release_Item__c> itemsOf(Id releaseId, RlyAppendRun.State st) {
        Set<String> comps = new Set<String>(st.components);
        Set<String> dels = new Set<String>(st.deletions);
        List<RLY_Release_Item__c> out = new List<RLY_Release_Item__c>();
        for (RLY_Release_Item__c i : RlyReleaseStore.items(releaseId)) {
            String key = i.Metadata_Type__c + ':' + i.Component_Name__c;
            if (i.Is_Deletion__c == true ? dels.contains(key) : comps.contains(key)) {
                out.add(new RLY_Release_Item__c(Id = i.Id));
            }
        }
        return out;
    }

    private static List<String> without(List<String> values, Set<String> gone) {
        List<String> out = new List<String>();
        for (String v : values) {
            if (!gone.contains(v)) {
                out.add(v);
            }
        }
        return out;
    }
}
