/**
 * @description The Home tab's route board (RlyHomeController): the developer orgs as one stop, then the stages by
 * Stage_Order__c, then the hub. Per stop: its connection (RLY_Org__c.Status__c, "Not checked N days" after a week),
 * the newest release raised from it (developer orgs) or deployed to it (newest Deployed event), and one count: open
 * releases raised from the developer orgs, releases ready to promote from a stage (RlyPromoteStore.readyIn, as the
 * Promote tab counts them) or releases waiting for approval into the hub. Back promote orgs are not on the route.
 * Orgs, releases and events are shared hub records, read in system mode in the private inner without sharing class.
 */
public with sharing class RlyHomeRoute {

    /** @description Stop kind: the developer orgs. */
    public static final String KIND_DEVELOPER = 'developer';
    /** @description Stop kind: a stage. */
    public static final String KIND_STAGE = 'stage';
    /** @description Stop kind: the hub (production). */
    public static final String KIND_HUB = 'hub';
    /** @description An org counts as not checked after this many days. */
    public static final Integer STALE_DAYS = 7;

    private static final String ROLE_DEVELOPER = 'Developer';
    private static final String ROLE_STAGE = 'Stage';
    private static final String ROLE_OF_HUB = 'Hub';
    private static final String ORG_CONNECTED = 'Connected';
    private static final String TONE_OK = 'ok';
    private static final String TONE_WAIT = 'wait';
    private static final String TONE_BAD = 'bad';
    private static final String TONE_NONE = 'none';

    /** @description The route board. */
    public class Route {
        /** @description The route has at least one stage (otherwise the card says to set it in Pipeline). */
        @AuraEnabled public Boolean isSet = false;
        /** @description The route in one line, for example "DEV1 → SIT → PROD". */
        @AuraEnabled public String path;
        /** @description The stops, in route order. */
        @AuraEnabled public List<Stop> stops = new List<Stop>();
    }

    /** @description One stop of the route. */
    public class Stop {
        /** @description The org (the first developer org for the developer stop). */
        @AuraEnabled public Id orgId;
        /** @description The org's name, or "N developer orgs". */
        @AuraEnabled public String name;
        /** @description developer, stage or hub. */
        @AuraEnabled public String kind;
        /** @description Its role in words: "Developer", "Stage 1", "Hub · production". */
        @AuraEnabled public String roleText;
        /** @description Its connection in words: "Connected", "Failed", "Not checked 8 days". */
        @AuraEnabled public String statusText;
        /** @description The connection's tone: ok, wait, bad or none. */
        @AuraEnabled public String statusTone;
        /** @description The newest release raised from it or deployed to it, or null. */
        @AuraEnabled public Id lastId;
        /** @description That release's number. */
        @AuraEnabled public String lastName;
        /** @description That release's title. */
        @AuraEnabled public String lastTitle;
        /** @description When it was raised or deployed. */
        @AuraEnabled public Datetime lastOn;
        /** @description Who raised or deployed it. */
        @AuraEnabled public String lastBy;
        /** @description Developer: open releases raised from it. Stage: ready to promote. Hub: waiting for approval into it. */
        @AuraEnabled public Integer count = 0;
        /** @description Stage: hotfixes among the releases ready to promote. */
        @AuraEnabled public Integer hotfixCount = 0;
        /** @description Stage: the next stop's name. */
        @AuraEnabled public String nextName;
    }

    /** @description The route's orgs split by role. */
    private class Orgs {
        /** @description The developer orgs. */
        public List<RLY_Org__c> developers = new List<RLY_Org__c>();
        /** @description The stages, in route order. */
        public List<RLY_Org__c> stages = new List<RLY_Org__c>();
        /** @description The hub, or null. */
        public RLY_Org__c hub;
    }

    /**
     * @description The route board.
     * @return the route
     */
    public static Route read() {
        Data store = new Data();
        Orgs orgs = split(store.routeOrgs());
        Route r = new Route();
        r.isSet = !orgs.stages.isEmpty();
        if (!orgs.developers.isEmpty()) {
            r.stops.add(developerStop(orgs.developers, store));
        }
        Map<Id, RLY_Release_Event__c> lastDeploys = store.lastDeploys();
        Map<Id, List<RLY_Release__c>> ready = readyByStage(orgs.stages);
        for (Integer i = 0; i < orgs.stages.size(); i++) {
            RLY_Org__c next = i + 1 < orgs.stages.size() ? orgs.stages[i + 1] : orgs.hub;
            Stop s = orgStop(orgs.stages[i], KIND_STAGE, 'Stage ' + (i + 1));
            s.nextName = next == null ? null : next.Name;
            countReady(s, ready.get(s.orgId));
            withDeploy(s, lastDeploys.get(s.orgId));
            r.stops.add(s);
        }
        if (orgs.hub != null) {
            Stop h = orgStop(orgs.hub, KIND_HUB, 'Hub · production');
            h.count = store.waitingInto(orgs.hub.Id);
            withDeploy(h, lastDeploys.get(h.orgId));
            r.stops.add(h);
        }
        List<String> names = new List<String>();
        for (Stop s : r.stops) {
            names.add(s.name);
        }
        r.path = String.join(names, ' → ');
        return r;
    }

    private static Orgs split(List<RLY_Org__c> rows) {
        Orgs o = new Orgs();
        for (RLY_Org__c org : rows) {
            if (org.Role__c == ROLE_DEVELOPER) {
                o.developers.add(org);
            } else if (org.Role__c == ROLE_STAGE) {
                o.stages.add(org);
            } else if (o.hub == null) {
                o.hub = org;
            }
        }
        return o;
    }

    private static Stop developerStop(List<RLY_Org__c> developers, Data store) {
        Stop s = orgStop(developers[0], KIND_DEVELOPER, ROLE_DEVELOPER);
        Set<Id> ids = new Map<Id, RLY_Org__c>(developers).keySet();
        if (developers.size() > 1) {
            s.name = developers.size() + ' developer orgs';
            s.roleText = 'Developer orgs';
            for (RLY_Org__c o : developers) {
                worstStatus(s, o);
            }
        }
        s.count = store.openFrom(ids, RlyReleaseQuery.STATE_STATUSES.get(RlyReleaseQuery.STATE_OPEN));
        RLY_Release__c last = store.newestFrom(ids);
        if (last != null) {
            s.lastId = last.Id;
            s.lastName = last.Name;
            s.lastTitle = last.Title__c;
            s.lastOn = last.CreatedDate;
            s.lastBy = last.CreatedBy == null ? null : last.CreatedBy.Name;
        }
        return s;
    }

    // The developer stop shows the first org that isn't connected, or Connected.
    private static void worstStatus(Stop s, RLY_Org__c o) {
        if (s.statusTone == TONE_OK) {
            setStatus(s, o);
        }
    }

    private static Stop orgStop(RLY_Org__c o, String kind, String roleText) {
        Stop s = new Stop();
        s.orgId = o.Id;
        s.name = o.Name;
        s.kind = kind;
        s.roleText = roleText;
        setStatus(s, o);
        return s;
    }

    /**
     * @description An org's connection in words and its tone.
     * @param s the stop to fill
     * @param o the org, with Status__c and Last_Checked__c
     */
    private static void setStatus(Stop s, RLY_Org__c o) {
        String status = String.isBlank(o.Status__c) ? 'Not checked' : o.Status__c;
        s.statusText = status;
        s.statusTone = status == 'Failed' ? TONE_BAD : (status == 'Refreshed' ? TONE_WAIT : TONE_NONE);
        if (status != ORG_CONNECTED) {
            return;
        }
        Integer days = o.Last_Checked__c == null ? 0 : o.Last_Checked__c.date().daysBetween(Date.today());
        s.statusText = days > STALE_DAYS ? 'Not checked ' + days + ' days' : ORG_CONNECTED;
        s.statusTone = days > STALE_DAYS ? TONE_WAIT : TONE_OK;
    }

    private static Map<Id, List<RLY_Release__c>> readyByStage(List<RLY_Org__c> stages) {
        Map<Id, List<RLY_Release__c>> out = new Map<Id, List<RLY_Release__c>>();
        if (stages.isEmpty()) {
            return out;
        }
        for (RLY_Release__c r : RlyPromoteStore.readyIn(new Map<Id, RLY_Org__c>(stages).keySet())) {
            if (!out.containsKey(r.Target_Org__c)) {
                out.put(r.Target_Org__c, new List<RLY_Release__c>());
            }
            out.get(r.Target_Org__c).add(r);
        }
        return out;
    }

    private static void countReady(Stop s, List<RLY_Release__c> ready) {
        if (ready == null) {
            return;
        }
        s.count = ready.size();
        for (RLY_Release__c r : ready) {
            s.hotfixCount += RlyHotfix.isHotfix(r) ? 1 : 0;
        }
    }

    private static void withDeploy(Stop s, RLY_Release_Event__c e) {
        if (e == null) {
            return;
        }
        s.lastId = e.Release__c;
        s.lastName = e.Release__r.Name;
        s.lastTitle = e.Release__r.Title__c;
        s.lastOn = e.Occurred_On__c;
        s.lastBy = e.Actor__r == null ? null : e.Actor__r.Name;
    }

    /** @description Shared hub orgs, releases and events, read in system mode. */
    private without sharing class Data {

        /**
         * @description The orgs on the route: developer orgs by name, stages in route order, the hub.
         * @return the orgs, without sign-in fields
         */
        public List<RLY_Org__c> routeOrgs() {
            return [SELECT Id, Name, Role__c, Stage_Order__c, Status__c, Last_Checked__c FROM RLY_Org__c
                    WHERE Role__c IN ('Developer', 'Stage', 'Hub')
                    WITH SYSTEM_MODE ORDER BY Stage_Order__c ASC NULLS LAST, Name ASC LIMIT 200];
        }

        /**
         * @description The newest Deployed event per org.
         * @return org Id to its newest Deployed event
         */
        public Map<Id, RLY_Release_Event__c> lastDeploys() {
            Map<Id, RLY_Release_Event__c> out = new Map<Id, RLY_Release_Event__c>();
            for (RLY_Release_Event__c e : [SELECT Id, Org__c, Release__c, Release__r.Name, Release__r.Title__c, Actor__r.Name, Occurred_On__c
                                           FROM RLY_Release_Event__c WHERE Event_Type__c = 'Deployed' AND Org__c != null
                                               AND Release__c != null
                                           WITH SYSTEM_MODE ORDER BY Occurred_On__c DESC LIMIT 500]) {
                if (!out.containsKey(e.Org__c)) {
                    out.put(e.Org__c, e);
                }
            }
            return out;
        }

        /**
         * @description How many releases raised from some orgs are in some statuses.
         * @param orgIds the source orgs
         * @param statuses the statuses
         * @return the count
         */
        public Integer openFrom(Set<Id> orgIds, Set<String> statuses) {
            return [SELECT COUNT() FROM RLY_Release__c WHERE Source_Org__c IN :orgIds AND Status__c IN :statuses
                    AND Release_Type__c != 'Back_Promote' WITH SYSTEM_MODE LIMIT 10000];
        }

        /**
         * @description The newest release raised from some orgs.
         * @param orgIds the source orgs
         * @return the release, or null
         */
        public RLY_Release__c newestFrom(Set<Id> orgIds) {
            List<RLY_Release__c> rows = [SELECT Id, Name, Title__c, CreatedDate, CreatedBy.Name FROM RLY_Release__c
                                         WHERE Source_Org__c IN :orgIds WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description How many releases wait for approval into an org.
         * @param orgId the target org
         * @return the count
         */
        public Integer waitingInto(Id orgId) {
            return [SELECT COUNT() FROM RLY_Release__c WHERE Target_Org__c = :orgId AND Status__c = 'Ready for approval'
                    WITH SYSTEM_MODE LIMIT 10000];
        }
    }
}
