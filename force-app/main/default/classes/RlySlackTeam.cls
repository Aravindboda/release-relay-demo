/**
 * @description The hub's Slack workspace (build 48). Testing or saving the Slack connection records the workspace
 * (team) ID the bot token belongs to (auth.test team_id) on the Slack record, after the callout; from then on button
 * presses and forms from any other workspace are refused (RlySlackAction).
 */
public with sharing class RlySlackTeam {

    private static final Pattern TEAM_ID = Pattern.compile('[TE][A-Z0-9]{2,19}');
    // The team ID auth.test gave in this request (RlySlackController.connection).
    private static String seenTeamId;

    /**
     * @description Notes the team ID from an auth.test answer.
     * @param authTest the answer
     */
    public static void noteFrom(Map<String, Object> authTest) {
        Object id = authTest == null ? null : authTest.get('team_id');
        seenTeamId = isTeamId(id == null ? null : String.valueOf(id)) ? String.valueOf(id) : null;
    }

    /**
     * @description The team ID auth.test gave in this request, or null.
     * @return the team ID
     */
    public static String lastSeen() {
        return seenTeamId;
    }

    /**
     * @description Saves the team ID auth.test gave (DML: after the callouts), when there is one and it changed.
     */
    public static void remember() {
        RLY_Notification__c s = RlySlack.settings();
        if (s != null && seenTeamId != null && !seenTeamId.equals(s.Slack_Team_Id__c)) {
            RlySlack.saveSettings(new RLY_Notification__c(Id = s.Id, Slack_Team_Id__c = seenTeamId));
        }
    }

    /**
     * @description Whether a payload comes from the hub's workspace: once the team ID is recorded, the payload's
     * team.id must be it.
     * @param s the Slack settings
     * @param p the payload
     * @return true when it may be handled
     */
    public static Boolean isOurs(RLY_Notification__c s, Map<String, Object> p) {
        if (s == null || String.isBlank(s.Slack_Team_Id__c)) {
            return true;
        }
        String team = RlySlackPayload.text(RlySlackPayload.child(p, 'team'), 'id');
        return team != null && team.equals(s.Slack_Team_Id__c.trim());
    }

    /**
     * @description Whether a value is a Slack workspace (team) ID, such as T024BE7LD.
     * @param teamId the value
     * @return true when it is
     */
    public static Boolean isTeamId(String teamId) {
        return teamId != null && TEAM_ID.matcher(teamId).matches();
    }
}
