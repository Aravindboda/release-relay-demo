/**
 * @description The rules for manual steps (RlyManualSteps): a step needs a title (up to 120 characters), a category and
 * a timing from the picklists, an order from 1 to 9999 and, when it is limited to some orgs, the names of registered
 * orgs; a release has up to 50 steps. Who raised the release, or an admin, adds and changes its steps until it is first
 * deployed (or ends); back promote syncs have no steps of their own.
 */
public with sharing class RlyManualStepRules {

    private static final Set<String> LOCKED = new Set<String>{ 'Deploying', 'Deployed', 'Deploy failed', 'Rejected', 'Closed', 'Failed' };
    private static final Integer MAX_SEQUENCE = 9999;

    /**
     * @description Checks the steps sent with a new release and builds them (not saved, no release yet). A step without
     * an order gets its position in the list.
     * @param inputs the steps, or null
     * @return the steps
     */
    public static List<RLY_Manual_Step__c> fromInputs(List<RlyManualSteps.StepInput> inputs) {
        List<RLY_Manual_Step__c> out = new List<RLY_Manual_Step__c>();
        if (inputs == null || inputs.isEmpty()) {
            return out;
        }
        if (inputs.size() > RlyManualSteps.MAX_STEPS) {
            throw new RlyReleaseException('A release can have up to ' + RlyManualSteps.MAX_STEPS + ' manual steps.');
        }
        Set<String> orgNames = knownOrgNames();
        for (Integer i = 0; i < inputs.size(); i++) {
            RLY_Manual_Step__c step = toStep(inputs[i], orgNames);
            step.Sequence__c = step.Sequence__c == null ? i + 1 : step.Sequence__c;
            out.add(step);
        }
        return out;
    }

    /**
     * @description Checks one step and builds it (not saved; Id and release are left to the caller).
     * @param input the step as sent
     * @param orgNames the registered orgs' names, lower case (knownOrgNames)
     * @return the step
     */
    public static RLY_Manual_Step__c toStep(RlyManualSteps.StepInput input, Set<String> orgNames) {
        if (input == null || String.isBlank(input.title) || input.title.trim().length() > RlyManualSteps.TITLE_LENGTH) {
            throw new RlyReleaseException('Give each manual step a title (up to ' + RlyManualSteps.TITLE_LENGTH + ' characters).');
        }
        return new RLY_Manual_Step__c(Title__c = input.title.trim(),
            Instructions__c = String.isBlank(input.instructions) ? null : input.instructions.trim().left(32768),
            Category__c = categoryOf(input.category), Timing__c = timingOf(input.timing), Sequence__c = sequenceOf(input.sequence),
            Back_Promote__c = input.backPromote != false, Org_Scope__c = RlyManualStepScope.checked(input.orgScope, orgNames));
    }

    private static Integer sequenceOf(Integer sequence) {
        if (sequence != null && (sequence < 1 || sequence > MAX_SEQUENCE)) {
            throw new RlyReleaseException('A manual step\'s order is a number from 1 to ' + MAX_SEQUENCE + '.');
        }
        return sequence;
    }

    private static String categoryOf(String category) {
        if (String.isBlank(category)) {
            return RlyManualSteps.CATEGORY_DEFAULT;
        }
        if (!RlyManualSteps.CATEGORIES.contains(category.trim())) {
            throw new RlyReleaseException('Pick the manual step\'s category: Permissions, Data, Setup or Other.');
        }
        return category.trim();
    }

    private static String timingOf(String timing) {
        if (String.isBlank(timing)) {
            return RlyManualSteps.TIMING_AFTER;
        }
        String t = timing.trim();
        if (t != RlyManualSteps.TIMING_BEFORE && t != RlyManualSteps.TIMING_AFTER) {
            throw new RlyReleaseException('Say when the manual step is done: Before_Deploy or After_Deploy.');
        }
        return t;
    }

    /**
     * @description The names of the registered stages, hub and back promote orgs, lower case.
     * @return the names
     */
    public static Set<String> knownOrgNames() {
        Set<String> out = new Set<String>();
        List<RLY_Org__c> orgs = new List<RLY_Org__c>(RlyReleaseStore.routeOrgs());
        orgs.addAll(RlyPromoteStore.backPromoteOrgs());
        for (RLY_Org__c o : orgs) {
            out.add(o.Name.toLowerCase());
        }
        return out;
    }

    /**
     * @description Whether the current user may add, change or delete the release's steps: who raised it, or an admin,
     * until it is first deployed (or ends). Back promote syncs have no steps of their own.
     * @param rel the release, with CreatedById, Status__c and Release_Type__c
     * @return true when allowed
     */
    public static Boolean canEdit(RLY_Release__c rel) {
        if (rel == null || LOCKED.contains(rel.Status__c) || String.isNotBlank(rel.Merge_Commit__c)
                || RlyPromotion.typeOf(rel) == RlyPromotion.TYPE_BACK_PROMOTE) {
            return false;
        }
        return rel.CreatedById == UserInfo.getUserId() || RlyOrgController.isAdmin();
    }

    /**
     * @description Refuses a change to the release's steps when canEdit says no.
     * @param rel the release
     */
    public static void requireEdit(RLY_Release__c rel) {
        if (!canEdit(rel)) {
            throw new RlyReleaseException('Manual steps can be changed by the person who raised the release, or an admin, until it\'s first deployed.');
        }
    }
}
