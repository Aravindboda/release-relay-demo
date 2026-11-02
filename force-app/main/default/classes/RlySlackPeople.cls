/**
 * @description Who someone is in Slack: users.lookupByEmail (an email to a member ID; needs users:read.email) and
 * users.info (a member ID to a name and email; needs users:read, and users:read.email for the email), and the scopes
 * the bot token holds (auth.test's x-oauth-scopes header). A Slack account that is deleted (deactivated) counts as not
 * found. Callouts only: nothing is saved here.
 */
public with sharing class RlySlackPeople {

    /** @description The scopes the approver features need. */
    public static final List<String> NEEDED_SCOPES = new List<String>{ 'chat:write', 'users:read', 'users:read.email' };
    /** @description The scope lookups by email need. */
    public static final String EMAIL_SCOPE = 'users:read.email';

    private static final Set<String> NOT_FOUND = new Set<String>{ 'users_not_found', 'user_not_found' };

    /** @description A Slack account. */
    public class Person {
        /** @description The member ID (U… or W…), upper case. */
        public String memberId;
        /** @description The display or real name. */
        public String name;
        /** @description The email on the Slack profile, or null when the token can't read it. */
        public String email;
        /** @description The Slack workspace (team) ID. */
        public String teamId;
    }

    /**
     * @description The Slack account with this email (users.lookupByEmail).
     * @param email the email
     * @return the account, or null when Slack has none (or only a deactivated one)
     */
    public static Person byEmail(String email) {
        try {
            return person(RlySlackApi.read('users.lookupByEmail', new Map<String, String>{ 'email' => email.trim() }));
        } catch (RlySlackApi.SlackException e) {
            if (NOT_FOUND.contains(RlySlackApi.code(e))) {
                return null;
            }
            throw e;
        }
    }

    /**
     * @description The Slack account with this member ID (users.info).
     * @param memberId the member ID
     * @return the account, or null when Slack has none (or it is deactivated)
     */
    public static Person byId(String memberId) {
        try {
            return person(RlySlackApi.read('users.info', new Map<String, String>{ 'user' => memberId }));
        } catch (RlySlackApi.SlackException e) {
            if (NOT_FOUND.contains(RlySlackApi.code(e))) {
                return null;
            }
            throw e;
        }
    }

    /**
     * @description Asks Slack which scopes the bot token holds (one auth.test call).
     * @return the scopes, or null when Slack didn't say
     */
    public static Set<String> tokenScopes() {
        RlySlackApi.call('auth.test', new Map<String, Object>());
        return parseScopes(RlySlackApi.scopes());
    }

    /**
     * @description The scopes in an x-oauth-scopes value.
     * @param header comma separated scopes, or null
     * @return the scopes, or null when header is blank
     */
    public static Set<String> parseScopes(String header) {
        if (String.isBlank(header)) {
            return null;
        }
        Set<String> out = new Set<String>();
        for (String s : header.split(',')) {
            if (String.isNotBlank(s)) {
                out.add(s.trim().toLowerCase());
            }
        }
        return out;
    }

    /**
     * @description The needed scopes the token doesn't hold.
     * @param held the scopes held (null: unknown, nothing reported missing)
     * @return the missing scopes, in NEEDED_SCOPES order
     */
    public static List<String> missing(Set<String> held) {
        List<String> out = new List<String>();
        if (held == null) {
            return out;
        }
        for (String s : NEEDED_SCOPES) {
            if (!held.contains(s)) {
                out.add(s);
            }
        }
        return out;
    }

    /**
     * @description What the page says about missing scopes.
     * @param missingScopes the missing scopes
     * @return the sentence, or null when none is missing
     */
    public static String missingText(List<String> missingScopes) {
        if (missingScopes == null || missingScopes.isEmpty()) {
            return null;
        }
        return 'Slack app is missing ' + String.join(missingScopes, ', ') + ' — add it and reinstall.';
    }

    // users.lookupByEmail and users.info answer { ok, user: { id, name, deleted, team_id, profile: { email, real_name } } }.
    private static Person person(Map<String, Object> answer) {
        Map<String, Object> u = RlySlackPayload.child(answer, 'user');
        if (u.get('deleted') == true || String.isBlank(RlySlackPayload.text(u, 'id'))) {
            return null;
        }
        Map<String, Object> profile = RlySlackPayload.child(u, 'profile');
        Person p = new Person();
        p.memberId = RlySlackPayload.text(u, 'id').toUpperCase();
        p.teamId = RlySlackPayload.text(u, 'team_id');
        p.email = RlySlackPayload.text(profile, 'email');
        String realName = RlySlackPayload.text(profile, 'real_name');
        p.name = String.isNotBlank(realName) ? realName : RlySlackPayload.text(u, 'name');
        return p;
    }
}
