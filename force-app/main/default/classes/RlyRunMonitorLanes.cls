/**
 * @description The Pipeline Monitor's Route: one lane per org, grouped and ordered as on the Pipeline tab
 * (RlyRouteController.getSetup: the developer orgs, then the stages in route order with production last, then the back
 * promote orgs), never a fixed list. A lane's run is the newest run whose target org is that org's GitHub environment or
 * name; a developer org also gets the Raise runs of releases raised from it. A lane shows its run when it is still
 * going or started today; otherwise the run is its "last run" and the lane says No runs today.
 */
public with sharing class RlyRunMonitorLanes {

    private static final String RAISE = 'Raise';
    private static final Map<String, String> GROUP_LABELS = new Map<String, String>{
        'development' => 'Development', 'route' => 'Route', 'backpromote' => 'Back promote'
    };

    /** @description The runs indexed for the lanes. */
    private class Index {
        /** @description The newest run per target org key. */
        public Map<String, RLY_Pipeline_Run__c> byTarget = new Map<String, RLY_Pipeline_Run__c>();
        /** @description The newest Raise run per source org of its release. */
        public Map<Id, RLY_Pipeline_Run__c> raisedFrom = new Map<Id, RLY_Pipeline_Run__c>();
        /** @description The start of today. */
        public Datetime today;
    }

    /**
     * @description The lanes.
     * @param window the recent runs and the runs still going, newest first
     * @param today the start of the viewer's today
     * @return the lanes, in route order
     */
    public static List<RlyRunMonitorViews.Lane> build(List<RLY_Pipeline_Run__c> window, Datetime today) {
        Index idx = index(window);
        idx.today = today;
        RlyRouteController.Setup setup = RlyRouteController.getSetup();
        List<RlyRunMonitorViews.Lane> out = new List<RlyRunMonitorViews.Lane>();
        for (RLY_Org__c o : setup.developers) {
            RlyRunMonitorViews.Lane l = lane(o, 'development', 'developer org');
            attach(l, newer(latestFor(o, idx), idx.raisedFrom.get(o.Id)), idx);
            out.add(l);
        }
        Integer stageNo = 0;
        for (RLY_Org__c o : setup.stages) {
            Boolean isStage = o.Role__c == 'Stage';
            stageNo += isStage ? 1 : 0;
            RlyRunMonitorViews.Lane l = lane(o, 'route', isStage ? 'stage ' + stageNo : 'production');
            attach(l, latestFor(o, idx), idx);
            out.add(l);
        }
        for (RLY_Org__c o : setup.backPromoteOrgs) {
            RlyRunMonitorViews.Lane l = lane(o, 'backpromote', 'back promote');
            attach(l, latestFor(o, idx), idx);
            out.add(l);
        }
        return out;
    }

    private static Index index(List<RLY_Pipeline_Run__c> window) {
        Index idx = new Index();
        for (RLY_Pipeline_Run__c r : window) {
            String k = RlyRunMonitorRows.key(r.Target_Org__c);
            if (k != '' && !idx.byTarget.containsKey(k)) {
                idx.byTarget.put(k, r);
            }
            Id source = r.Release__c == null || r.Workflow_Step__c != RAISE ? null : r.Release__r.Source_Org__c;
            if (source != null && !idx.raisedFrom.containsKey(source)) {
                idx.raisedFrom.put(source, r);
            }
        }
        return idx;
    }

    private static RLY_Pipeline_Run__c latestFor(RLY_Org__c o, Index idx) {
        RLY_Pipeline_Run__c byEnv = idx.byTarget.get(RlyRunMonitorRows.key(o.Git_Environment__c));
        return newer(byEnv, idx.byTarget.get(RlyRunMonitorRows.key(o.Name)));
    }

    private static RLY_Pipeline_Run__c newer(RLY_Pipeline_Run__c a, RLY_Pipeline_Run__c b) {
        if (a == null || b == null) {
            return a == null ? b : a;
        }
        return b.Started__c > a.Started__c ? b : a;
    }

    private static RlyRunMonitorViews.Lane lane(RLY_Org__c o, String groupKey, String role) {
        RlyRunMonitorViews.Lane l = new RlyRunMonitorViews.Lane();
        l.orgId = o.Id;
        l.name = o.Name;
        l.groupKey = groupKey;
        l.groupLabel = GROUP_LABELS.get(groupKey);
        l.roleText = role;
        l.environment = o.Git_Environment__c;
        return l;
    }

    // Today's (or a still going) run is the lane's run; an older one is its last run.
    private static void attach(RlyRunMonitorViews.Lane l, RLY_Pipeline_Run__c run, Index idx) {
        if (run == null) {
            return;
        }
        Boolean current = RlyRunMonitorStore.ACTIVE.contains(run.Status__c) || (run.Started__c != null && run.Started__c >= idx.today);
        if (current) {
            l.run = RlyRunMonitorRows.row(run);
        } else {
            l.lastRun = RlyRunMonitorRows.row(run);
        }
    }
}
