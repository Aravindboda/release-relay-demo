/**
 * @description The Slack app's scope check for the Approvers window and the Slack connection Edit: one auth.test call
 * (Slack sends the bot token's scopes in the x-oauth-scopes header), each needed scope and whether the token holds it,
 * kept on the Slack record (Slack_Scopes__c) after the callout. The admin check is the caller's.
 */
public with sharing class RlySlackScopes {

    /** @description The Slack app's scopes as auth.test reports them. */
    public class ScopeCheck {
        /** @description Each needed scope and whether the token holds it. */
        @AuraEnabled public List<ScopeItem> items = new List<ScopeItem>();
        /** @description The sentence about missing scopes, or null. */
        @AuraEnabled public String missingText;
        /** @description Why the check couldn't run, or null. */
        @AuraEnabled public String problem;
        /** @description When it ran. */
        @AuraEnabled public Datetime checkedOn;
    }

    /** @description One needed scope. */
    public class ScopeItem {
        /** @description The scope. */
        @AuraEnabled public String name;
        /** @description The token holds it. */
        @AuraEnabled public Boolean ok = false;
    }

    /**
     * @description Checks the Slack app's scopes (one auth.test call; Slack sends them in x-oauth-scopes) and keeps them
     * on the Slack record (Slack_Scopes__c) after the callout.
     * @return the check
     */
    public static ScopeCheck check() {
        ScopeCheck out = new ScopeCheck();
        out.checkedOn = System.now();
        Set<String> held;
        try {
            held = RlySlackPeople.tokenScopes();
        } catch (Exception e) {
            out.problem = RlySlackLookup.problemText(e);
            return out;
        }
        if (held == null) {
            out.problem = 'Slack didn\'t list the bot token\'s scopes.';
            return out;
        }
        for (String s : RlySlackPeople.NEEDED_SCOPES) {
            ScopeItem i = new ScopeItem();
            i.name = s;
            i.ok = held.contains(s);
            out.items.add(i);
        }
        out.missingText = RlySlackPeople.missingText(RlySlackPeople.missing(held));
        RLY_Notification__c saved = RlySlack.settings();
        if (saved != null) {
            RlySlack.saveSettings(new RLY_Notification__c(Id = saved.Id, Slack_Scopes__c = String.join(new List<String>(held), ',').left(255)));
        }
        return out;
    }
}
