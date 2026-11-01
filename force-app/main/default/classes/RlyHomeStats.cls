/**
 * @description The Home tab's numbers (RlyHomeController): the KPI tiles from aggregate queries on RLY_Release__c and
 * RLY_Release_Event__c, the deploys per week (Deployed and Deploy_Failed events, the last 8 weeks, weeks from Monday)
 * and the 50 newest events of every release. Releases and their events are shared hub records that every Release Relay
 * user sees, so the queries run in system mode, in the private inner without sharing class, and only read.
 */
public with sharing class RlyHomeStats {

    /** @description How many weeks the deploys chart shows (this week included). */
    public static final Integer WEEK_COUNT = 8;
    /** @description How many events Recent activity lists. */
    public static final Integer ACTIVITY_SIZE = 50;

    private static final String STATUS_READY = 'Ready for approval';
    private static final String STATUS_CHECKS_FAILED = 'Checks failed';
    private static final String EVENT_DEPLOYED = 'Deployed';
    /** @description The events the deploys chart counts. */
    private static final Set<String> CHART_EVENTS = new Set<String>{ EVENT_DEPLOYED, 'Deploy_Failed' };
    private static final String ROLE_OF_HUB = 'Hub';
    private static final Integer DETAIL_LENGTH = 500;
    private static final Long DAY_MS = 86400000L;
    /** @description Statuses of a release that is running (as the Releases tab polls them). */
    private static final Set<String> RUNNING_STATUSES = new Set<String>{ 'Submitted', 'Retrieving', 'Workflow running',
        'Validating', 'Deploying' };

    /** @description The KPI tiles. */
    public class Kpis {
        /** @description Releases still open (RlyReleaseQuery open state), back promote syncs left out. */
        @AuraEnabled public Integer openCount = 0;
        /** @description Open releases with a run going. */
        @AuraEnabled public Integer runningCount = 0;
        /** @description Open hotfixes. */
        @AuraEnabled public Integer hotfixCount = 0;
        /** @description Releases ready for approval. */
        @AuraEnabled public Integer waitingCount = 0;
        /** @description Of those, the ones the viewer can approve. */
        @AuraEnabled public Integer waitingForYou = 0;
        /** @description Releases whose checks failed. */
        @AuraEnabled public Integer checksFailed = 0;
        /** @description Of those, the viewer's own. */
        @AuraEnabled public Integer checksFailedYours = 0;
        /** @description Deployed events since Monday. */
        @AuraEnabled public Integer deployedWeek = 0;
        /** @description Of those, deploys into the hub (production). */
        @AuraEnabled public Integer deployedToHub = 0;
        /** @description Rolled_Back events in the last 30 days. */
        @AuraEnabled public Integer rollbacks = 0;
        /** @description The release of the newest of them, or null. */
        @AuraEnabled public String lastRollbackName;
        /** @description When it was rolled back, or null. */
        @AuraEnabled public Datetime lastRollbackOn;
        /** @description Average days from raising a release to its first deploy, releases deployed in the last 30 days; null without any. */
        @AuraEnabled public Decimal leadDays;
        /** @description How many releases that average counts. */
        @AuraEnabled public Integer leadCount = 0;
    }

    /** @description One week of the deploys chart. */
    public class WeekBar {
        /** @description The Monday the week starts on. */
        @AuraEnabled public Date weekStart;
        /** @description Deployed events that week. */
        @AuraEnabled public Integer deployed = 0;
        /** @description Deploy_Failed events that week. */
        @AuraEnabled public Integer failed = 0;
    }

    /** @description One org's deploys this week. */
    public class OrgWeek {
        /** @description The org. */
        @AuraEnabled public String orgName;
        /** @description Deployed events since Monday. */
        @AuraEnabled public Integer deployed = 0;
        /** @description Deploy_Failed events since Monday. */
        @AuraEnabled public Integer failed = 0;
    }

    /** @description One event of Recent activity. */
    public class ActivityRow {
        /** @description The event record. */
        @AuraEnabled public Id id;
        /** @description Its release. */
        @AuraEnabled public Id releaseId;
        /** @description The release number, for example REL-00042. */
        @AuraEnabled public String releaseName;
        /** @description Event_Type__c API value, for example Deployed or Rolled_Back. */
        @AuraEnabled public String eventType;
        /** @description The org it happened in, or null. */
        @AuraEnabled public String orgName;
        /** @description Who did it, or null. */
        @AuraEnabled public String actorName;
        /** @description Salesforce, Slack, Git, Rule or Pipeline, or null. */
        @AuraEnabled public String via;
        /** @description What happened, in one line (up to 500 characters). */
        @AuraEnabled public String detail;
        /** @description When it happened. */
        @AuraEnabled public Datetime occurredOn;
    }

    /**
     * @description The KPI tiles.
     * @param waitingForYou how many releases the viewer can approve (RlyHomeNeeds)
     * @return the tiles
     */
    public static Kpis kpis(Integer waitingForYou) {
        Data store = new Data();
        Kpis k = new Kpis();
        k.waitingForYou = waitingForYou == null ? 0 : waitingForYou;
        for (AggregateResult g : store.statusCounts()) {
            addStatus(k, g);
        }
        k.checksFailedYours = store.checksFailedBy(UserInfo.getUserId());
        Datetime monday = Datetime.newInstance(weekStart(Date.today()), Time.newInstance(0, 0, 0, 0));
        for (AggregateResult g : store.deployedSince(monday)) {
            Integer n = (Integer) g.get('eventCount');
            k.deployedWeek += n;
            k.deployedToHub += (String) g.get('orgRole') == ROLE_OF_HUB ? n : 0;
        }
        List<RLY_Release_Event__c> rolledBack = store.rollbacks();
        k.rollbacks = rolledBack.size();
        if (!rolledBack.isEmpty()) {
            k.lastRollbackName = rolledBack[0].Release__r.Name;
            k.lastRollbackOn = rolledBack[0].Occurred_On__c;
        }
        addLeadTime(k, store.recentDeploys());
        return k;
    }

    // One group of the status counts (a status and the hotfix flag).
    private static void addStatus(Kpis k, AggregateResult g) {
        String status = (String) g.get('relStatus');
        Integer n = (Integer) g.get('relCount');
        if (RlyReleaseQuery.STATE_STATUSES.get(RlyReleaseQuery.STATE_OPEN).contains(status)) {
            k.openCount += n;
            k.hotfixCount += (Boolean) g.get('relHot') == true ? n : 0;
        }
        k.runningCount += RUNNING_STATUSES.contains(status) ? n : 0;
        k.waitingCount += status == STATUS_READY ? n : 0;
        k.checksFailed += status == STATUS_CHECKS_FAILED ? n : 0;
    }

    // Raise to first deploy: the events come oldest first, so the first one per release is its first deploy.
    private static void addLeadTime(Kpis k, List<RLY_Release_Event__c> deploys) {
        Map<Id, Long> spans = new Map<Id, Long>();
        for (RLY_Release_Event__c e : deploys) {
            if (!spans.containsKey(e.Release__c) && e.Occurred_On__c != null && e.Release__r.CreatedDate != null) {
                spans.put(e.Release__c, Math.max(0L, e.Occurred_On__c.getTime() - e.Release__r.CreatedDate.getTime()));
            }
        }
        Long total = 0L;
        for (Long span : spans.values()) {
            total += span;
        }
        k.leadCount = spans.size();
        k.leadDays = spans.isEmpty() ? null : (Decimal.valueOf(total) / DAY_MS / spans.size()).setScale(1);
    }

    /**
     * @description The Monday of a day's week.
     * @param day the day
     * @return its Monday (the day itself on a Monday)
     */
    public static Date weekStart(Date day) {
        Integer weekday = Integer.valueOf(Datetime.newInstance(day, Time.newInstance(12, 0, 0, 0)).format('u'));
        return day.addDays(1 - weekday);
    }

    /**
     * @description Deploys and failed deploys per week: this week and the 7 before it.
     * @return the weeks, oldest first
     */
    public static List<WeekBar> weeks() {
        Date firstMonday = weekStart(Date.today()).addDays(-7 * (WEEK_COUNT - 1));
        List<WeekBar> bars = new List<WeekBar>();
        for (Integer i = 0; i < WEEK_COUNT; i++) {
            WeekBar b = new WeekBar();
            b.weekStart = firstMonday.addDays(7 * i);
            bars.add(b);
        }
        Datetime since = Datetime.newInstance(firstMonday, Time.newInstance(0, 0, 0, 0));
        for (AggregateResult g : new Data().deploysByDay(since)) {
            Integer index = firstMonday.daysBetween((Date) g.get('eventDay')) / 7;
            if (index >= 0 && index < WEEK_COUNT) {
                addDay(bars[index], (String) g.get('eventType'), (Integer) g.get('eventCount'));
            }
        }
        return bars;
    }

    /**
     * @description Deploys and failed deploys since Monday, per org.
     * @return the orgs, by name
     */
    public static List<OrgWeek> thisWeekByOrg() {
        Map<String, OrgWeek> byOrg = new Map<String, OrgWeek>();
        Datetime monday = Datetime.newInstance(weekStart(Date.today()), Time.newInstance(0, 0, 0, 0));
        for (AggregateResult g : new Data().deploysByOrg(monday)) {
            String orgName = (String) g.get('orgName');
            if (!byOrg.containsKey(orgName)) {
                OrgWeek w = new OrgWeek();
                w.orgName = orgName;
                byOrg.put(orgName, w);
            }
            Integer n = (Integer) g.get('eventCount');
            if ((String) g.get('eventType') == EVENT_DEPLOYED) {
                byOrg.get(orgName).deployed += n;
            } else {
                byOrg.get(orgName).failed += n;
            }
        }
        return byOrg.values();
    }

    private static void addDay(WeekBar bar, String eventType, Integer n) {
        if (eventType == EVENT_DEPLOYED) {
            bar.deployed += n;
        } else {
            bar.failed += n;
        }
    }

    /**
     * @description The 50 newest events of every release.
     * @return the rows, newest first
     */
    public static List<ActivityRow> activity() {
        List<ActivityRow> out = new List<ActivityRow>();
        for (RLY_Release_Event__c e : new Data().newestEvents()) {
            ActivityRow r = new ActivityRow();
            r.id = e.Id;
            r.releaseId = e.Release__c;
            r.releaseName = e.Release__r == null ? null : e.Release__r.Name;
            r.eventType = e.Event_Type__c;
            r.orgName = e.Org__r == null ? null : e.Org__r.Name;
            r.actorName = e.Actor__r == null ? null : e.Actor__r.Name;
            r.via = e.Via__c;
            r.detail = e.Detail__c == null ? null : e.Detail__c.left(DETAIL_LENGTH);
            r.occurredOn = e.Occurred_On__c;
            out.add(r);
        }
        return out;
    }

    /** @description Shared hub releases and events, read in system mode. */
    private without sharing class Data {

        /**
         * @description Releases per status and hotfix flag, back promote syncs left out.
         * @return groups with relStatus, relHot and relCount
         */
        public List<AggregateResult> statusCounts() {
            return [SELECT Status__c relStatus, Is_Hotfix__c relHot, COUNT(Id) relCount FROM RLY_Release__c
                    WHERE Release_Type__c != 'Back_Promote' WITH SYSTEM_MODE GROUP BY Status__c, Is_Hotfix__c LIMIT 200];
        }

        /**
         * @description How many of a user's releases have failed checks.
         * @param userId the user
         * @return the count
         */
        public Integer checksFailedBy(Id userId) {
            return [SELECT COUNT() FROM RLY_Release__c WHERE CreatedById = :userId AND Status__c = :STATUS_CHECKS_FAILED
                    WITH SYSTEM_MODE LIMIT 10000];
        }

        /**
         * @description Deployed events since a moment, per role of the org.
         * @param since the start
         * @return groups with orgRole and eventCount
         */
        public List<AggregateResult> deployedSince(Datetime since) {
            return [SELECT Org__r.Role__c orgRole, COUNT(Id) eventCount FROM RLY_Release_Event__c
                    WHERE Event_Type__c = :EVENT_DEPLOYED AND Occurred_On__c >= :since
                    WITH SYSTEM_MODE GROUP BY Org__r.Role__c LIMIT 20];
        }

        /**
         * @description Rolled_Back events of the last 30 days.
         * @return the events, newest first
         */
        public List<RLY_Release_Event__c> rollbacks() {
            return [SELECT Id, Release__r.Name, Occurred_On__c FROM RLY_Release_Event__c
                    WHERE Event_Type__c = 'Rolled_Back' AND Occurred_On__c = LAST_N_DAYS:30
                    WITH SYSTEM_MODE ORDER BY Occurred_On__c DESC LIMIT 1000];
        }

        /**
         * @description Deployed events of the last 30 days, with the release's creation time.
         * @return the events, oldest first
         */
        public List<RLY_Release_Event__c> recentDeploys() {
            return [SELECT Id, Release__c, Release__r.CreatedDate, Occurred_On__c FROM RLY_Release_Event__c
                    WHERE Event_Type__c = :EVENT_DEPLOYED AND Occurred_On__c = LAST_N_DAYS:30 AND Release__c != null
                        AND Release__r.Release_Type__c != 'Back_Promote'
                    WITH SYSTEM_MODE ORDER BY Occurred_On__c ASC LIMIT 2000];
        }

        /**
         * @description Deployed and Deploy_Failed events since a moment, per type and day (the user's time zone).
         * @param since the start
         * @return groups with eventType, eventDay and eventCount
         */
        public List<AggregateResult> deploysByDay(Datetime since) {
            return [SELECT Event_Type__c eventType, DAY_ONLY(convertTimezone(Occurred_On__c)) eventDay, COUNT(Id) eventCount
                    FROM RLY_Release_Event__c
                    WHERE Event_Type__c IN :CHART_EVENTS AND Occurred_On__c >= :since
                    WITH SYSTEM_MODE GROUP BY Event_Type__c, DAY_ONLY(convertTimezone(Occurred_On__c)) LIMIT 200];
        }

        /**
         * @description Deployed and Deploy_Failed events since a moment, per org and type.
         * @param since the start
         * @return groups with orgName, eventType and eventCount, by org name
         */
        public List<AggregateResult> deploysByOrg(Datetime since) {
            return [SELECT Org__r.Name orgName, Event_Type__c eventType, COUNT(Id) eventCount FROM RLY_Release_Event__c
                    WHERE Event_Type__c IN :CHART_EVENTS AND Occurred_On__c >= :since AND Org__c != null
                    WITH SYSTEM_MODE GROUP BY Org__r.Name, Event_Type__c ORDER BY Org__r.Name LIMIT 200];
        }

        /**
         * @description The newest events of every release.
         * @return up to 50 events, newest first
         */
        public List<RLY_Release_Event__c> newestEvents() {
            return [SELECT Id, Event_Type__c, Release__c, Release__r.Name, Org__r.Name, Actor__r.Name, Via__c, Detail__c, Occurred_On__c
                    FROM RLY_Release_Event__c WITH SYSTEM_MODE ORDER BY Occurred_On__c DESC NULLS LAST, CreatedDate DESC
                    LIMIT :ACTIVITY_SIZE];
        }
    }
}
