/**
 * @description The rules for adding changes to an open release (RlyAppendService): a normal release (not a promotion,
 * back promote or manual-steps-only release) with an open pull request whose checks failed or that waits for approval,
 * not approved yet, by the user who raised it or an admin; and which picked components and deletions are new to it.
 */
public with sharing class RlyAppendRules {

    private static final Set<String> OPEN_FOR_ADDS = new Set<String>{ 'Checks failed', 'Ready for approval' };

    /**
     * @description Whether the current user may add changes to the release now.
     * @param rel the release, as RlyReleaseStore reads it
     * @return true when the Add changes button shows
     */
    public static Boolean mayAppend(RLY_Release__c rel) {
        return whyNot(rel) == null;
    }

    /**
     * @description The release, refused when changes can't be added to it now (whyNot).
     * @param releaseId the release
     * @return the release, as RlyReleaseStore reads it
     */
    public static RLY_Release__c checked(Id releaseId) {
        RLY_Release__c rel = releaseId == null ? null : RlyReleaseStore.release(releaseId);
        String why = whyNot(rel);
        if (why != null) {
            throw new RlyReleaseException(why);
        }
        return rel;
    }

    // Why changes can't be added now, or null.
    private static String whyNot(RLY_Release__c rel) {
        if (rel == null) {
            return 'Release not found.';
        }
        if (RlyPromotion.typeOf(rel) != RlyPromotion.TYPE_RELEASE || RlyManualOnly.isManualOnly(rel)) {
            return 'Changes can be added only to a release raised from a developer org.';
        }
        if (!OPEN_FOR_ADDS.contains(rel.Status__c) || rel.Approval_Status__c == 'Approved' || rel.PR_Number__c == null) {
            return 'Changes can be added to an open release whose checks failed or that waits for approval, before it\'s approved.';
        }
        if (rel.CreatedById != UserInfo.getUserId() && !RlyOrgController.isAdmin()) {
            return 'Only the person who raised ' + rel.Name + ' or an admin can add changes to it.';
        }
        return null;
    }

    /**
     * @description The request as a raise request, for the raise's own rules (RlyDeletionRules).
     * @param req the request
     * @return a raise request with its components and deletions
     */
    public static RlyRaiseService.RaiseRequest asRaise(RlyAppendService.AppendRequest req) {
        RlyRaiseService.RaiseRequest r = new RlyRaiseService.RaiseRequest();
        r.items = req.items;
        r.deletions = req.deletions;
        return r;
    }

    /**
     * @description What's in the release.
     * @param releaseId the release
     * @return Type:Name of its components, and -Type:Name of its deletions
     */
    public static Set<String> keysIn(Id releaseId) {
        Set<String> out = new Set<String>();
        for (RLY_Release_Item__c i : RlyReleaseStore.items(releaseId)) {
            out.add((i.Is_Deletion__c == true ? '-' : '') + i.Metadata_Type__c + ':' + i.Component_Name__c);
        }
        return out;
    }

    /**
     * @description The components not in the release yet; one the release deletes is refused.
     * @param items the components picked
     * @param inRelease keysIn
     * @return the new components
     */
    public static List<RlyRaiseService.Item> notIn(List<RlyRaiseService.Item> items, Set<String> inRelease) {
        List<RlyRaiseService.Item> out = new List<RlyRaiseService.Item>();
        for (RlyRaiseService.Item i : items) {
            String k = i.type + ':' + i.name;
            if (inRelease.contains('-' + k)) {
                throw new RlyReleaseException(i.type + ' ' + i.name + ' is both added and deleted.');
            }
            if (!inRelease.contains(k)) {
                out.add(i);
            }
        }
        return out;
    }

    /**
     * @description The new deletions, checked the way a raise checks them; one that the release adds is refused.
     * @param req the request
     * @param source the developer org
     * @param inRelease keysIn
     * @return Type:Name of each new deletion
     */
    public static List<String> newDeletions(RlyAppendService.AppendRequest req, RLY_Org__c source, Set<String> inRelease) {
        List<String> out = new List<String>();
        for (String k : RlyDeletionRules.deletions(asRaise(req), source)) {
            if (inRelease.contains(k)) {
                throw new RlyReleaseException(k.substringBefore(':') + ' ' + k.substringAfter(':') + ' is both added and deleted.');
            }
            if (!inRelease.contains('-' + k)) {
                out.add(k);
            }
        }
        return out;
    }

    /**
     * @description The test classes sent that the release doesn't run yet.
     * @param req the request
     * @param rel the release
     * @return the new test classes
     */
    public static Set<String> newTests(RlyAppendService.AppendRequest req, RLY_Release__c rel) {
        Set<String> tests = RlyTestRule.testNames(req.testClasses);
        tests.removeAll(RlyReleasePhase.tests(rel));
        return tests;
    }
}
