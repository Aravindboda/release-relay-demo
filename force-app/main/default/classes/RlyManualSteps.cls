/**
 * @description Manual steps: work a release needs that can't be deployed as metadata (profile or permission access, a
 * data load, a setup setting). A step (RLY_Manual_Step__c) belongs to the release that defined it and travels with it
 * through every org on the route, in order, and to back promote orgs. Each org's deploy gets a run per step
 * (RLY_Manual_Step_Run__c) that the deployment team checks off (RlyManualStepCheck). A deploy into an org waits for its
 * Before deploy runs (RlyManualStepGate). This class holds the values and the shapes the pages use.
 */
public with sharing class RlyManualSteps {

    /** @description Timing__c: done before the deploy into an org starts. */
    public static final String TIMING_BEFORE = 'Before_Deploy';
    /** @description Timing__c: open work once the deploy is done (the default). */
    public static final String TIMING_AFTER = 'After_Deploy';
    /** @description Run Status__c: not done yet (the default). */
    public static final String STATUS_TO_DO = 'To_Do';
    /** @description Run Status__c: done. */
    public static final String STATUS_DONE = 'Done';
    /** @description Run Status__c: not needed in this org (with a note). */
    public static final String STATUS_NOT_NEEDED = 'Not_Needed';
    /** @description Category__c: profile or permission access (the default). */
    public static final String CATEGORY_DEFAULT = 'Permissions';
    /** @description The Category__c values. */
    public static final Set<String> CATEGORIES = new Set<String>{ 'Permissions', 'Data', 'Setup', 'Other' };
    /** @description The most manual steps one release can have. */
    public static final Integer MAX_STEPS = 50;
    /** @description The longest title. */
    public static final Integer TITLE_LENGTH = 120;

    /** @description A manual step as the New Release page and the release page send it. */
    public class StepInput {
        /** @description The step's Id when it is edited (saveStep), or null for a new step. */
        public Id id;
        /** @description The release it belongs to (saveStep, for a new step). */
        public Id releaseId;
        /** @description What the step is (required, up to 120 characters). */
        public String title;
        /** @description What exactly to do. */
        public String instructions;
        /** @description Permissions (default), Data, Setup or Other. */
        public String category;
        /** @description Before_Deploy or After_Deploy (default). */
        public String timing;
        /** @description Its order within the release (1, 2, 3...); blank goes last. */
        public Integer sequence;
        /** @description Also done in back promote orgs (default true). */
        public Boolean backPromote;
        /** @description Blank for every org on the route, otherwise org names, comma separated. */
        public String orgScope;
    }

    /** @description The release page's Manual steps card. */
    public class StepBoard {
        /** @description The current user may add, edit, reorder and delete steps (who raised it, or an admin, until it's first deployed). */
        @AuraEnabled public Boolean canEdit = false;
        /** @description The current user may check steps off (deployment team or admin). */
        @AuraEnabled public Boolean canCheck = false;
        /** @description The steps, incl. those of the releases a promotion carries, in order. */
        @AuraEnabled public List<StepRow> steps = new List<StepRow>();
        /** @description Per org the steps are done in, in route order (back promote orgs last). */
        @AuraEnabled public List<OrgRuns> orgs = new List<OrgRuns>();
    }

    /** @description One manual step. */
    public class StepRow {
        /** @description The step. */
        @AuraEnabled public Id id;
        /** @description Its title. */
        @AuraEnabled public String title;
        /** @description What exactly to do. */
        @AuraEnabled public String instructions;
        /** @description Permissions, Data, Setup or Other. */
        @AuraEnabled public String category;
        /** @description Before_Deploy or After_Deploy. */
        @AuraEnabled public String timing;
        /** @description Its order within its release. */
        @AuraEnabled public Integer sequence;
        /** @description Also done in back promote orgs. */
        @AuraEnabled public Boolean backPromote;
        /** @description Blank for every org on the route, otherwise org names. */
        @AuraEnabled public String orgScope;
        /** @description The number of the release that defined it. */
        @AuraEnabled public String fromRelease;
    }

    /** @description The steps of one org's deploy. */
    public class OrgRuns {
        /** @description The org. */
        @AuraEnabled public Id orgId;
        /** @description Its name. */
        @AuraEnabled public String orgName;
        /** @description How many runs are still to do. */
        @AuraEnabled public Integer open = 0;
        /** @description How many Before deploy runs are still to do. */
        @AuraEnabled public Integer beforeOpen = 0;
        /** @description The runs, in order. */
        @AuraEnabled public List<RunRow> runs = new List<RunRow>();
    }

    /** @description One step in one org. */
    public class RunRow {
        /** @description The run. */
        @AuraEnabled public Id id;
        /** @description Its step. */
        @AuraEnabled public Id stepId;
        /** @description The step's title. */
        @AuraEnabled public String title;
        /** @description Before_Deploy or After_Deploy. */
        @AuraEnabled public String timing;
        /** @description Permissions, Data, Setup or Other. */
        @AuraEnabled public String category;
        /** @description To_Do, Done or Not_Needed. */
        @AuraEnabled public String status;
        /** @description Who marked it, or null. */
        @AuraEnabled public String doneBy;
        /** @description When, or null. */
        @AuraEnabled public Datetime doneOn;
        /** @description The deployment team's note, or null. */
        @AuraEnabled public String note;
        /** @description Its position in the org's deploy. */
        @AuraEnabled public Integer orderNo;
        /** @description The number of the release that defined the step. */
        @AuraEnabled public String fromRelease;
    }

    /** @description How many runs one deploy has, and how many are still to do. */
    public class Counts {
        /** @description Before deploy runs. */
        public Integer beforeCount = 0;
        /** @description Before deploy runs still to do. */
        public Integer beforeOpen = 0;
        /** @description After deploy runs. */
        public Integer afterCount = 0;
        /** @description After deploy runs still to do. */
        public Integer afterOpen = 0;

        /**
         * @description Every run.
         * @return the number of runs
         */
        public Integer total() {
            return beforeCount + afterCount;
        }

        /**
         * @description The runs still to do.
         * @return the number
         */
        public Integer open() {
            return beforeOpen + afterOpen;
        }
    }

    /**
     * @description "1 manual step" or "2 manual steps".
     * @param n the number
     * @return the words
     */
    public static String stepWords(Integer n) {
        return n + (n == 1 ? ' manual step' : ' manual steps');
    }

    /**
     * @description Whether the current user may check manual steps off.
     * @return true for the deployment team and admins
     */
    public static Boolean canCheck() {
        return FeatureManagement.checkPermission('RLY_Deploy_Team') || RlyOrgController.isAdmin();
    }
}
