/**
 * @description Creates the runs of manual steps (RlyManualSteps), in the same transaction as the record that needs them:
 * a release raised into its first stage (its steps whose scope includes that org), a promotion (every carried release's
 * steps for the next stop, carried releases in Carried_Releases__c order, then each step's sequence) and a back promote
 * sync (RlyBackPromoteSteps: the steps marked Back_Promote__c of every release deployed to the hub since that org's last
 * sync, in deploy order).
 * One run per step per org: a step already done (or not needed) in an org gets no new run there, and a run still to do
 * moves to the release now deploying into that org. DML only.
 */
public with sharing class RlyManualStepRuns {

    /** @description The runs one deploy needs. */
    public class Plan {
        /** @description The release deploying into the org. */
        public Id releaseId;
        /** @description The org. */
        public Id orgId;
        /** @description Its name (for the steps' org scope). */
        public String orgName;
        /** @description The releases whose steps it takes, in deploy order. */
        public List<Id> definers = new List<Id>();
        /** @description A back promote org: only steps marked Back_Promote__c. */
        public Boolean backPromoteOnly = false;
    }

    /** @description What create works with: the steps by release, the existing runs, and what to save or delete. */
    private class Work {
        /** @description The steps, by the release that defined them. */
        public Map<Id, List<RLY_Manual_Step__c>> byRelease = new Map<Id, List<RLY_Manual_Step__c>>();
        /** @description The existing runs of those steps in the plans' orgs, newest first. */
        public List<RLY_Manual_Step_Run__c> existingRuns = new List<RLY_Manual_Step_Run__c>();
        /** @description The newest existing run per step and org. */
        public Map<String, RLY_Manual_Step_Run__c> existing = new Map<String, RLY_Manual_Step_Run__c>();
        /** @description The runs to save, per step and org. */
        public Map<String, RLY_Manual_Step_Run__c> toSave = new Map<String, RLY_Manual_Step_Run__c>();
        /** @description The runs to delete. */
        public List<RLY_Manual_Step_Run__c> toDelete = new List<RLY_Manual_Step_Run__c>();
    }

    /**
     * @description The releases whose steps a release takes: those a promotion carries (in order), then its own.
     * @param rel the release, with Id and Carried_Releases__c
     * @return the release Ids
     */
    public static List<Id> definersOf(RLY_Release__c rel) {
        List<Id> out = RlyCarried.ids(rel);
        out.add(rel.Id);
        return out;
    }

    /**
     * @description The plan for a release deploying into an org on the route.
     * @param rel the release, with Id and Carried_Releases__c
     * @param org the org it deploys into
     * @return the plan
     */
    public static Plan planFor(RLY_Release__c rel, RLY_Org__c org) {
        Plan p = new Plan();
        p.releaseId = rel.Id;
        p.orgId = org.Id;
        p.orgName = org.Name;
        p.definers = definersOf(rel);
        return p;
    }

    /**
     * @description Saves the steps of a release just raised and their runs in its first stage.
     * @param rel the release, saved
     * @param steps its steps (RlyManualStepRules.fromInputs), not saved
     * @param target the first stage
     */
    public static void addToRaised(RLY_Release__c rel, List<RLY_Manual_Step__c> steps, RLY_Org__c target) {
        if (steps.isEmpty()) {
            return;
        }
        for (RLY_Manual_Step__c s : steps) {
            s.Release__c = rel.Id;
        }
        RlyManualStepStore.saveSteps(steps);
        create(new List<Plan>{ planFor(rel, target) });
    }

    /**
     * @description The runs of a promotion just saved: every carried release's steps for the next stop.
     * @param promotion the promotion, saved, with Carried_Releases__c
     * @param nextOrg the next stop
     */
    public static void forPromotion(RLY_Release__c promotion, RLY_Org__c nextOrg) {
        create(new List<Plan>{ planFor(promotion, nextOrg) });
    }

    /**
     * @description After a release's steps changed: its runs in its current target, again.
     * @param rel the release, with Target_Org__c and Target_Org__r.Name
     */
    public static void refresh(RLY_Release__c rel) {
        if (rel.Target_Org__c != null && rel.Target_Org__r != null) {
            create(new List<Plan>{ planFor(rel, rel.Target_Org__r) });
        }
    }

    /**
     * @description Creates, moves and renumbers the runs the plans need, and deletes a deploy's runs still to do whose
     * step no longer applies to it.
     * @param plans the plans
     */
    public static void create(List<Plan> plans) {
        Set<Id> definerIds = new Set<Id>();
        Set<Id> orgIds = new Set<Id>();
        for (Plan p : plans) {
            definerIds.addAll(p.definers);
            orgIds.add(p.orgId);
        }
        Work w = new Work();
        for (RLY_Manual_Step__c s : RlyManualStepStore.stepsOf(definerIds)) {
            if (!w.byRelease.containsKey(s.Release__c)) {
                w.byRelease.put(s.Release__c, new List<RLY_Manual_Step__c>());
            }
            w.byRelease.get(s.Release__c).add(s);
        }
        Set<Id> stepIds = new Set<Id>();
        for (List<RLY_Manual_Step__c> steps : w.byRelease.values()) {
            stepIds.addAll(new Map<Id, RLY_Manual_Step__c>(steps).keySet());
        }
        w.existingRuns = RlyManualStepStore.runsIn(stepIds, orgIds);
        for (RLY_Manual_Step_Run__c r : w.existingRuns) {
            if (!w.existing.containsKey(key(r.Step__c, r.Org__c))) {
                w.existing.put(key(r.Step__c, r.Org__c), r);
            }
        }
        for (Plan p : plans) {
            place(p, w);
        }
        RlyManualStepStore.saveRuns(w.toSave.values());
        RlyManualStepStore.deleteRuns(w.toDelete);
    }

    // The plan's runs, numbered in order; its runs still to do for steps it no longer takes are deleted.
    private static void place(Plan p, Work w) {
        Set<Id> kept = new Set<Id>();
        Integer position = 0;
        for (RLY_Manual_Step__c s : stepsInOrder(p, w)) {
            kept.add(s.Id);
            RLY_Manual_Step_Run__c r = w.existing.containsKey(key(s.Id, p.orgId)) ? w.existing.get(key(s.Id, p.orgId))
                : new RLY_Manual_Step_Run__c(Step__c = s.Id, Org__c = p.orgId, Status__c = RlyManualSteps.STATUS_TO_DO);
            if (r.Status__c == RlyManualSteps.STATUS_TO_DO) {
                position++;
                r.Release__c = p.releaseId;
                r.Order__c = position;
                w.toSave.put(key(s.Id, p.orgId), r);
            }
        }
        for (RLY_Manual_Step_Run__c r : w.existingRuns) {
            if (r.Org__c == p.orgId && r.Release__c == p.releaseId && r.Status__c == RlyManualSteps.STATUS_TO_DO && !kept.contains(r.Step__c)) {
                w.toDelete.add(r);
            }
        }
    }

    // The steps the plan takes: each definer once, in order, then each step's sequence; filtered by scope.
    private static List<RLY_Manual_Step__c> stepsInOrder(Plan p, Work w) {
        List<RLY_Manual_Step__c> out = new List<RLY_Manual_Step__c>();
        Set<Id> seen = new Set<Id>();
        for (Id definer : p.definers) {
            List<RLY_Manual_Step__c> steps = seen.add(definer) && w.byRelease.containsKey(definer) ? w.byRelease.get(definer)
                : new List<RLY_Manual_Step__c>();
            for (RLY_Manual_Step__c s : steps) {
                if (applies(p, s)) {
                    out.add(s);
                }
            }
        }
        return out;
    }

    private static Boolean applies(Plan p, RLY_Manual_Step__c s) {
        return p.backPromoteOnly ? s.Back_Promote__c == true : RlyManualStepScope.inScope(s, p.orgName);
    }

    private static String key(Id stepId, Id orgId) {
        return String.valueOf(stepId) + '|' + String.valueOf(orgId);
    }
}
