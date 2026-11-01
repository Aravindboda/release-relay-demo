/**
 * @description Builds the release page's Manual steps card (RlyManualSteps.StepBoard): the release's steps (for a
 * promotion, those of the releases it carries first, in order; for a back promote sync, the steps it took), and per org
 * the steps are done in (route order: stages, the hub, then back promote orgs) the runs in deploy order.
 */
public with sharing class RlyManualStepBoard {

    /**
     * @description The board of a release.
     * @param releaseId the release
     * @return the board
     */
    public static RlyManualSteps.StepBoard build(Id releaseId) {
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null) {
            throw new RlyReleaseException('Release not found.');
        }
        RlyManualSteps.StepBoard b = new RlyManualSteps.StepBoard();
        b.canEdit = RlyManualStepRules.canEdit(rel);
        b.canCheck = RlyManualSteps.canCheck();
        List<Id> definers = RlyManualStepRuns.definersOf(rel);
        Map<Id, List<RLY_Manual_Step__c>> byRelease = new Map<Id, List<RLY_Manual_Step__c>>();
        Set<Id> stepIds = new Set<Id>();
        for (RLY_Manual_Step__c s : RlyManualStepStore.stepsOf(new Set<Id>(definers))) {
            if (!byRelease.containsKey(s.Release__c)) {
                byRelease.put(s.Release__c, new List<RLY_Manual_Step__c>());
            }
            byRelease.get(s.Release__c).add(s);
            stepIds.add(s.Id);
        }
        for (Id definer : definers) {
            for (RLY_Manual_Step__c s : byRelease.containsKey(definer) ? byRelease.remove(definer) : new List<RLY_Manual_Step__c>()) {
                b.steps.add(toStep(s));
            }
        }
        List<RLY_Manual_Step_Run__c> runs = RlyManualStepStore.runsFor(stepIds, rel.Id);
        addTakenSteps(b, runs, stepIds);
        b.orgs = byOrg(runs);
        return b;
    }

    // A back promote sync's steps come from the releases it took them from: listed in its deploy order.
    private static void addTakenSteps(RlyManualSteps.StepBoard b, List<RLY_Manual_Step_Run__c> runs, Set<Id> stepIds) {
        List<Id> taken = new List<Id>();
        for (RLY_Manual_Step_Run__c r : runs) {
            if (!stepIds.contains(r.Step__c) && !taken.contains(r.Step__c)) {
                taken.add(r.Step__c);
            }
        }
        Map<Id, RLY_Manual_Step__c> steps = new Map<Id, RLY_Manual_Step__c>(RlyManualStepStore.stepsById(new Set<Id>(taken)));
        for (Id stepId : taken) {
            if (steps.containsKey(stepId)) {
                b.steps.add(toStep(steps.get(stepId)));
            }
        }
    }

    // The runs per org, orgs in route order.
    private static List<RlyManualSteps.OrgRuns> byOrg(List<RLY_Manual_Step_Run__c> runs) {
        Map<String, RlyManualSteps.OrgRuns> bySortKey = new Map<String, RlyManualSteps.OrgRuns>();
        Map<Id, RlyManualSteps.OrgRuns> byId = new Map<Id, RlyManualSteps.OrgRuns>();
        for (RLY_Manual_Step_Run__c r : runs) {
            if (!byId.containsKey(r.Org__c)) {
                RlyManualSteps.OrgRuns fresh = new RlyManualSteps.OrgRuns();
                fresh.orgId = r.Org__c;
                fresh.orgName = r.Org__r.Name;
                byId.put(r.Org__c, fresh);
                bySortKey.put(sortKey(r.Org__r), fresh);
            }
            RlyManualSteps.OrgRuns o = byId.get(r.Org__c);
            RlyManualSteps.RunRow row = toRun(r);
            o.runs.add(row);
            if (row.status == RlyManualSteps.STATUS_TO_DO) {
                o.open++;
                o.beforeOpen += row.timing == RlyManualSteps.TIMING_BEFORE ? 1 : 0;
            }
        }
        List<String> keys = new List<String>(bySortKey.keySet());
        keys.sort();
        List<RlyManualSteps.OrgRuns> out = new List<RlyManualSteps.OrgRuns>();
        for (String k : keys) {
            out.add(bySortKey.get(k));
        }
        return out;
    }

    // Stages by their order, then the hub, then back promote orgs and others, each by name.
    private static String sortKey(RLY_Org__c o) {
        Map<String, String> rank = new Map<String, String>{ 'Stage' => '1', 'Hub' => '2', 'Back_Promote' => '3' };
        String r = rank.containsKey(o.Role__c) ? rank.get(o.Role__c) : '4';
        String stageOrder = o.Stage_Order__c == null ? '99999' : String.valueOf(o.Stage_Order__c.intValue()).leftPad(5, '0');
        return r + stageOrder + o.Name.toLowerCase() + '|' + o.Id;
    }

    private static RlyManualSteps.StepRow toStep(RLY_Manual_Step__c s) {
        RlyManualSteps.StepRow x = new RlyManualSteps.StepRow();
        x.id = s.Id;
        x.title = s.Title__c;
        x.instructions = s.Instructions__c;
        x.category = s.Category__c;
        x.timing = s.Timing__c;
        x.sequence = s.Sequence__c == null ? null : s.Sequence__c.intValue();
        x.backPromote = s.Back_Promote__c == true;
        x.orgScope = s.Org_Scope__c;
        x.fromRelease = s.Release__r == null ? null : s.Release__r.Name;
        return x;
    }

    private static RlyManualSteps.RunRow toRun(RLY_Manual_Step_Run__c r) {
        RlyManualSteps.RunRow x = new RlyManualSteps.RunRow();
        x.id = r.Id;
        x.stepId = r.Step__c;
        x.title = r.Step__r.Title__c;
        x.timing = r.Step__r.Timing__c;
        x.category = r.Step__r.Category__c;
        x.status = r.Status__c;
        x.doneBy = r.Done_By__r == null ? null : r.Done_By__r.Name;
        x.doneOn = r.Done_On__c;
        x.note = r.Note__c;
        x.orderNo = r.Order__c == null ? null : r.Order__c.intValue();
        x.fromRelease = r.Step__r.Release__r == null ? null : r.Step__r.Release__r.Name;
        return x;
    }
}
