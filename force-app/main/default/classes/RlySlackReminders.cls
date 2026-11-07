/**
 * @description Slack reminders for one call (RlySlackDue): releases into orgs with reminders on that wait for approval
 * (approvers) or, deployed, still have manual steps to do in that org (deploy team), longer than the org's hours since
 * they last moved and not nudged within them. One message per release, in its Slack thread (else the org's channel);
 * quiet between QUIET_FROM and QUIET_UNTIL in the hub's time zone. Reads, then callouts; the caller saves.
 */
public with sharing class RlySlackReminders {

    /** @description Reminders aren't sent before this hour (hub time zone). */
    public static final Integer QUIET_UNTIL = 7;
    /** @description Reminders aren't sent from this hour (hub time zone). */
    public static final Integer QUIET_FROM = 20;
    private static final Set<String> APPROVER_SETS = new Set<String>{ 'RLY_Approver', 'RLY_Admin' };
    private static final Set<String> DEPLOY_SETS = new Set<String>{ 'RLY_Deploy_Team', 'RLY_Admin' };
    private static final Long HOUR_MS = 3600000L;

    /** @description Releases nudged, with the moment. */
    public Map<Id, Datetime> reminded = new Map<Id, Datetime>();
    private Datetime now;
    private RlySlackPoster poster;
    private Map<Id, Datetime> moved;
    private Map<Id, Integer> steps;
    private String approverWho;
    private String deployWho;

    /**
     * @description One call's reminders.
     * @param now the call's moment
     * @param poster the call's messages
     */
    public RlySlackReminders(Datetime now, RlySlackPoster poster) {
        this.now = now;
        this.poster = poster;
    }

    /**
     * @description Sends the reminders that are due.
     * @param orgs the orgs (only those with reminders on are used)
     * @param localHour the hour now in the hub's time zone
     */
    public void send(List<RLY_Org__c> orgs, Integer localHour) {
        Map<Id, RLY_Org__c> byId = new Map<Id, RLY_Org__c>();
        for (RLY_Org__c o : orgs) {
            if (o.Slack_Reminders__c == true) {
                byId.put(o.Id, o);
            }
        }
        if (byId.isEmpty()) {
            return;
        }
        if (localHour < QUIET_UNTIL || localHour >= QUIET_FROM) {
            poster.reason += 'Quiet hours: reminders wait until ' + QUIET_UNTIL + ' AM. ';
            return;
        }
        List<RLY_Release__c> rels = RlySlackDueStore.waiting(byId.keySet());
        Set<Id> relIds = new Map<Id, RLY_Release__c>(rels).keySet();
        moved = RlySlackDueStore.lastMoved(relIds);
        steps = RlySlackDueStore.stepsToDo(relIds);
        for (RLY_Release__c rel : rels) {
            if (poster.stopped) {
                return;
            }
            remindIfDue(rel, byId.get(rel.Target_Org__c));
        }
    }

    // Due: waited at least the org's hours, not nudged within them, and (deployed) with steps still to do.
    private void remindIfDue(RLY_Release__c rel, RLY_Org__c org) {
        RlySlackNudge.Wait w = new RlySlackNudge.Wait();
        w.hours = hoursSince(moved.containsKey(rel.Id) ? moved.get(rel.Id) : rel.CreatedDate);
        w.steps = steps.containsKey(rel.Id) ? steps.get(rel.Id) : 0;
        if (!isDue(rel, RlySlackNudge.hoursOf(org), w)) {
            return;
        }
        w.who = org.Slack_Mentions__c == true ? whoFor(rel) : '';
        if (poster.post(messageFor(rel, org, w))) {
            reminded.put(rel.Id, now);
        }
    }

    private Boolean isDue(RLY_Release__c rel, Integer period, RlySlackNudge.Wait w) {
        Boolean recent = rel.Slack_Reminded__c != null && hoursSince(rel.Slack_Reminded__c) < period;
        Boolean waits = rel.Status__c == RlySlackDueStore.READY || w.steps > 0;
        return waits && w.hours >= period && !recent;
    }

    // In the release's Slack thread when it has one, else the org's channel.
    private static Map<String, Object> messageFor(RLY_Release__c rel, RLY_Org__c org, RlySlackNudge.Wait w) {
        Boolean inThread = String.isNotBlank(rel.Slack_Ts__c) && String.isNotBlank(rel.Slack_Channel_Id__c);
        Map<String, Object> msg = new Map<String, Object>{ 'channel' => inThread ? rel.Slack_Channel_Id__c : org.Slack_Channel__c.trim(),
            'text' => RlySlackNudge.reminder(rel, w) };
        if (inThread) {
            msg.put('thread_ts', rel.Slack_Ts__c);
        }
        return msg;
    }

    // The approvers' or the deploy team's mentions, read once per call.
    private String whoFor(RLY_Release__c rel) {
        Boolean ready = rel.Status__c == RlySlackDueStore.READY;
        if (ready && approverWho == null) {
            approverWho = RlySlackNudge.mentions(RlySlackDueReads.memberIds(RlySlackDueReads.holders(APPROVER_SETS)).values());
        }
        if (!ready && deployWho == null) {
            deployWho = RlySlackNudge.mentions(RlySlackDueReads.memberIds(RlySlackDueReads.holders(DEPLOY_SETS)).values());
        }
        return ready ? approverWho : deployWho;
    }

    private Integer hoursSince(Datetime moment) {
        return moment == null ? 0 : (Integer) ((now.getTime() - moment.getTime()) / HOUR_MS);
    }
}
