/**
 * @description Slack reminders and daily digests, sent when due (POST /services/apexrest/rly/slack-due, RlySlackDueRest).
 * The pipeline's hourly schedule (pipeline files v24, job slack-due) calls it as the hub's pipeline user, once per pass
 * until it answers done; no Apex runs in the background. Only orgs with a Slack channel and reminders or the digest on
 * are read: an org with them off is never checked.
 *   Reminders  RlySlackReminders (waiting for approval, or manual steps to do after a deploy)
 *   Digest     once a day per org from its digest hour (hub time zone): deployed yesterday, waiting for approval, manual
 *              steps to do, failed; nothing to say → no message
 * At most RlySlackPoster.MAX_POSTS messages per call; Slack's "busy" (429) ends the call and the next hour carries on.
 * Callouts first, then the saves (Slack_Reminded__c, Slack_Digest_Sent__c).
 * Answer: {done, pass, sent, skipped, reason}; when there is nothing to do, {idle:true, done:true, sent:0, skipped:0, reason}
 * (build 56, D20: skipped is always a count, so the job's log line reads '0 skipped', not 'true skipped').
 */
public with sharing class RlySlackDue {

    /** @description Said when Slack answers "busy". */
    public static final String BUSY = RlySlackPoster.BUSY;

    /** @description For tests: the moment the call runs at (null: now). */
    @TestVisible
    private static Datetime testNow;
    // The hub time zone's offset from GMT at the call's moment, in seconds.
    private static Integer offsetSeconds = 0;

    /**
     * @description Handles one call.
     * @param body the request body ({runUrl, pass}); unknown keys are ignored
     * @return the answer
     */
    public static Map<String, Object> handle(String body) {
        Object pass = RlySyncParse.parsedOrEmpty(body).get('pass');
        String why = whySkipped();
        List<RLY_Org__c> orgs = why == null ? RlySlackDueStore.dueOrgs() : new List<RLY_Org__c>();
        if (why == null && orgs.isEmpty()) {
            why = 'No org has Slack reminders or the daily digest on.';
        }
        if (why != null) {
            return new Map<String, Object>{ 'idle' => true, 'done' => true, 'sent' => 0, 'skipped' => 0, 'reason' => why, 'pass' => pass };
        }
        Datetime now = testNow == null ? System.now() : testNow;
        offsetSeconds = RlySlackDueReads.hubTimeZone().getOffset(now) / 1000;
        Datetime localNow = now.addSeconds(offsetSeconds);
        RlySlackPoster poster = new RlySlackPoster();
        RlySlackReminders reminders = new RlySlackReminders(now, poster);
        reminders.send(orgs, localNow.hourGmt());
        Set<Id> digested = digests(orgs, localNow, poster);
        RlySlackDueStore.markReminded(reminders.reminded);
        RlySlackDueStore.markDigest(digested, localNow.dateGmt());
        return new Map<String, Object>{ 'done' => poster.done, 'pass' => pass, 'sent' => poster.sent, 'skipped' => poster.refused,
            'reason' => poster.reason };
    }

    // Why the call does nothing: not an admin, not the production hub, or Slack off.
    private static String whySkipped() {
        if (!RlyOrgController.isAdmin()) {
            return 'The pipeline\'s hub user needs Release Relay Admin.';
        }
        if (!RlyHubGuard.isHub()) {
            return 'This isn\'t the production hub: Slack reminders go out from production only.';
        }
        return RlySlack.isOn() ? null : 'Slack is off (Pipeline tab, Slack).';
    }

    // Each org's digest, once a day from its hour; an org with nothing to say is marked done without a message.
    private static Set<Id> digests(List<RLY_Org__c> orgs, Datetime localNow, RlySlackPoster poster) {
        Set<Id> digested = new Set<Id>();
        Date today = localNow.dateGmt();
        Datetime yesterday = Datetime.newInstanceGmt(today.addDays(-1), Time.newInstance(0, 0, 0, 0)).addSeconds(-offsetSeconds);
        Set<Id> due = new Set<Id>();
        for (RLY_Org__c o : orgs) {
            if (digestDue(o, localNow)) {
                due.add(o.Id);
            }
        }
        Map<Id, Map<String, List<RLY_Release__c>>> lines = RlySlackDueReads.digests(due, yesterday);
        for (RLY_Org__c o : orgs) {
            if (!due.contains(o.Id) || poster.stopped) {
                continue;
            }
            String text = RlySlackNudge.digest(o, lines.get(o.Id), today);
            if (text == null || poster.post(new Map<String, Object>{ 'channel' => o.Slack_Channel__c.trim(), 'text' => text })) {
                digested.add(o.Id);
            }
        }
        return digested;
    }

    private static Boolean digestDue(RLY_Org__c o, Datetime localNow) {
        return o.Slack_Digest__c == true && localNow.hourGmt() >= RlySlackNudge.digestHourOf(o) && o.Slack_Digest_Sent__c != localNow.dateGmt();
    }
}
