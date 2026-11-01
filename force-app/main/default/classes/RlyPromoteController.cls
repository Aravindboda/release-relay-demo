/**
 * @description Promote tab: per stage, the releases deployed to it and waiting to go to its next stop (hotfixes first,
 * then oldest deploy first), and promoting a choice of them as one promotion (RlyPromotion). Approvers and admins promote.
 */
public with sharing class RlyPromoteController {

    /** @description What the Promote tab shows. */
    public class PromoteBoard {
        /** @description The current user may promote (approvers and admins). */
        @AuraEnabled public Boolean canPromote;
        /** @description Each stage with a next stop, in route order. */
        @AuraEnabled public List<PromoteStage> stages = new List<PromoteStage>();
    }

    /** @description One stage and its next stop. */
    public class PromoteStage {
        /** @description The stage org. */
        @AuraEnabled public Id stageId;
        /** @description Its name. */
        @AuraEnabled public String stageName;
        /** @description Its branch. */
        @AuraEnabled public String stageBranch;
        /** @description The next stop. */
        @AuraEnabled public Id nextId;
        /** @description Its name. */
        @AuraEnabled public String nextName;
        /** @description Its branch. */
        @AuraEnabled public String nextBranch;
        /** @description Releases waiting in the stage: hotfixes first, then oldest deploy first. */
        @AuraEnabled public List<Ready> ready = new List<Ready>();
    }

    /** @description A release waiting to be promoted. */
    public class Ready {
        /** @description The release. */
        @AuraEnabled public Id id;
        /** @description Its number. */
        @AuraEnabled public String name;
        /** @description Its title. */
        @AuraEnabled public String title;
        /** @description A hotfix. */
        @AuraEnabled public Boolean isHotfix;
        /** @description Why it's a hotfix, or null. */
        @AuraEnabled public String hotfixReason;
        /** @description When it was deployed to the stage. */
        @AuraEnabled public Datetime deployedOn;
        /** @description Who raised it. */
        @AuraEnabled public String raisedBy;
        /** @description Its test classes. */
        @AuraEnabled public List<String> tests;
        /** @description Its number of components. */
        @AuraEnabled public Integer componentCount;
        /** @description Its number of deletions. */
        @AuraEnabled public Integer deletionCount;
        /** @description Its number of manual steps (they travel with it; getSteps lists them). */
        @AuraEnabled public Integer manualSteps = 0;
    }

    /**
     * @description The stages and what waits in each.
     * @return the board
     */
    @AuraEnabled
    public static PromoteBoard getPromote() {
        try {
            PromoteBoard board = new PromoteBoard();
            board.canPromote = canPromote();
            List<RLY_Org__c> route = RlyRouteRules.ordered(RlyReleaseStore.routeOrgs());
            Map<Id, PromoteStage> byStage = new Map<Id, PromoteStage>();
            for (Integer i = 0; i < route.size() - 1; i++) {
                if (route[i].Role__c == 'Stage') {
                    PromoteStage s = toStage(route[i], route[i + 1]);
                    board.stages.add(s);
                    byStage.put(s.stageId, s);
                }
            }
            List<RLY_Release__c> waiting = RlyPromoteStore.readyIn(byStage.keySet());
            Map<Id, Integer> stepCounts = RlyManualStepStore.stepCounts(new Map<Id, RLY_Release__c>(waiting).keySet());
            for (RLY_Release__c r : waiting) {
                Ready x = toReady(r);
                x.manualSteps = stepCounts.containsKey(r.Id) ? stepCounts.get(r.Id) : 0;
                byStage.get(r.Target_Org__c).ready.add(x);
            }
            return board;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Promotes releases from a stage to its next stop: saves the promotion (it starts on its page).
     * @param requestJson {stageId, releaseIds:[...], title}
     * @return the promotion's Id
     */
    @AuraEnabled
    public static Id promote(String requestJson) {
        try {
            if (!canPromote()) {
                throw new RlyReleaseException('Only approvers can promote releases (permission set Release Relay Approver).');
            }
            RlyPromotion.Request req = (RlyPromotion.Request) JSON.deserialize(requestJson, RlyPromotion.Request.class);
            return RlyPromotion.create(req);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    private static Boolean canPromote() {
        return RlyApprovalService.canApprove() || RlyOrgController.isAdmin();
    }

    private static PromoteStage toStage(RLY_Org__c stage, RLY_Org__c nextOrg) {
        PromoteStage s = new PromoteStage();
        s.stageId = stage.Id;
        s.stageName = stage.Name;
        s.stageBranch = stage.Branch__c;
        s.nextId = nextOrg.Id;
        s.nextName = nextOrg.Name;
        s.nextBranch = nextOrg.Branch__c;
        return s;
    }

    private static Ready toReady(RLY_Release__c r) {
        Ready x = new Ready();
        x.id = r.Id;
        x.name = r.Name;
        x.title = r.Title__c;
        x.isHotfix = r.Is_Hotfix__c == true;
        x.hotfixReason = r.Hotfix_Reason__c;
        x.deployedOn = r.Last_Synced__c;
        x.raisedBy = r.CreatedBy == null ? null : r.CreatedBy.Name;
        x.tests = RlyReleasePhase.tests(r);
        x.componentCount = r.Component_Count__c == null ? 0 : r.Component_Count__c.intValue();
        x.deletionCount = r.Deletion_Count__c == null ? 0 : r.Deletion_Count__c.intValue();
        return x;
    }

    private static AuraHandledException handled(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }
}
