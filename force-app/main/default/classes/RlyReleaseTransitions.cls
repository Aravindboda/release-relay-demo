/**
 * @description Turns what a save changed on releases into history events (RlyReleaseLog): the pull request opened, the
 * code scan and the validation finished (or the scan's findings were accepted), approvals (first and second approver,
 * approved automatically by the org's rule), rejection, deploy or deploy failure, the branches merged back, a back
 * promote sync deployed (the last ones in RlyReleaseOutcomes). RlyReleaseStore.saveAll calls it with the releases as they were before the save, so every path
 * that moves a release (the page's reads, approvals in Salesforce or Slack, manual steps, back promote) is recorded once.
 * The history never stops a save: a release it can't read is skipped.
 */
public with sharing class RlyReleaseTransitions {

    private static final Set<String> FINISHED = new Set<String>{ 'Passed', 'Failed', 'Skipped', 'Error' };

    /**
     * @description Adds the events of the changes between the saved and the new releases.
     * @param priorRows the releases as they were (RlyReleaseStore), by Id
     * @param rels the releases as saved now
     */
    public static void record(Map<Id, RLY_Release__c> priorRows, List<RLY_Release__c> rels) {
        for (RLY_Release__c rel : rels) {
            RLY_Release__c old = priorRows.get(rel.Id);
            if (old == null) {
                continue;
            }
            try {
                checks(old, rel);
                RlyReleaseOutcomes.approvals(old, rel);
                RlyReleaseOutcomes.outcome(old, rel);
            } catch (SObjectException e) {
                continue; // a release read without some field: no history for it, the save goes on
            }
        }
    }

    // The pull request, the code scan and the validation.
    private static void checks(RLY_Release__c old, RLY_Release__c rel) {
        if (String.isBlank(old.PR_URL__c) && String.isNotBlank(rel.PR_URL__c)) {
            String num = rel.PR_Number__c == null ? '' : ' #' + rel.PR_Number__c.intValue();
            RlyReleaseLog.add(rel, 'Pull_Request', 'Pull request' + num + ' opened into ' + rel.Target_Branch__c)
                .byActor(null, RlyReleaseLog.VIA_GIT).withReference(rel.PR_URL__c);
        }
        if (old.Scan_Status__c != rel.Scan_Status__c) {
            scan(rel);
        }
        if (old.Validation_Status__c != rel.Validation_Status__c && FINISHED.contains(rel.Validation_Status__c)) {
            RlyEvidenceText.Validation v = RlyEvidenceText.validationOf(rel.Validation_Result__c);
            RlyReleaseLog.add(rel, 'Validation', 'Validation in ' + targetName(rel) + ' ' + rel.Validation_Status__c + v.suffix())
                .inOrg(rel.Target_Org__c).withReference(v.deployId);
        }
    }

    private static void scan(RLY_Release__c rel) {
        if (rel.Scan_Status__c == 'Bypassed') {
            RlyReleaseLog.add(rel, 'Scan', 'Code scan findings accepted: ' + RlyEvidenceText.text(rel.Scan_Bypass_Reason__c))
                .byActor(rel.Scan_Bypassed_By__c, RlyReleaseLog.VIA_SALESFORCE);
        } else if (FINISHED.contains(rel.Scan_Status__c)) {
            RlyReleaseLog.add(rel, 'Scan', 'Code scan ' + rel.Scan_Status__c + RlyEvidenceText.scanCounts(rel));
        }
    }

    /**
     * @description Via__c for an Approved_Via__c value: Salesforce, Slack and Rule as they are, a Git provider's name as Git.
     * @param approvedVia Approved_Via__c
     * @return the Via__c value
     */
    public static String viaOf(String approvedVia) {
        if (approvedVia == RlyReleaseLog.VIA_SALESFORCE || approvedVia == RlyReleaseLog.VIA_SLACK || approvedVia == RlyReleaseLog.VIA_RULE) {
            return approvedVia;
        }
        return String.isBlank(approvedVia) ? RlyReleaseLog.VIA_SALESFORCE : RlyReleaseLog.VIA_GIT;
    }

    /**
     * @description The target org's name (or the target branch).
     * @param rel the release
     * @return the name
     */
    public static String targetName(RLY_Release__c rel) {
        return rel.Target_Org__r == null ? RlyEvidenceText.text(rel.Target_Branch__c) : rel.Target_Org__r.Name;
    }
}
