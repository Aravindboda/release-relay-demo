/**
 * @description Turns the platform's sign-in errors into the step to fix, from a table of rules:
 * the first rule whose words appear in the error gives the advice.
 */
public with sharing class RlySignInAdvice {

    private static final String FALLBACK = 'The hub couldn\'t sign in to {org}.';
    private static final List<Rule> RULES = new List<Rule>{
        new Rule(new List<String>{ 'unauthorized endpoint', 'remote site' },
            'Add {domain} as a Remote Site Setting in the hub (Setup > Remote Site Settings).'),
        new Rule(new List<String>{ 'certificate', 'keystore', 'key not found' },
            'Check Hub certificate: "{certificate}" must be the API name of a certificate in this hub (Setup > Certificate and Key Management).'),
        new Rule(new List<String>{ 'client identifier', 'invalid_client_id', 'invalid_client' },
            'Check Consumer key: it must be the consumer key of the External Client App in {org}.'),
        new Rule(new List<String>{ 'hasn\'t approved', 'has not approved', 'not approved' },
            'Pre-authorize the integration user in {org}\'s External Client App: Permitted Users = Admin approved users are pre-authorized, then add the user\'s profile or permission set.'),
        new Rule(new List<String>{ 'audience' },
            'Check the My Domain URL: the Login type is read from it (a .sandbox. URL signs in as a sandbox).'),
        new Rule(new List<String>{ 'inactive', 'not found', 'invalid' },
            'Check Integration username: it must be an active user in {org}.').alsoNeeding('user'),
        new Rule(new List<String>{ 'invalid_grant' },
            'The org refused the login. Check that its External Client App has the JWT bearer flow on, the hub certificate uploaded, and the user pre-authorized.')
    };

    /** @description One row of the table: words to look for, and the advice when one of them appears. */
    public class Rule {
        /** @description The advice; {domain}, {certificate} and {org} are filled in. */
        public String advice;
        private List<String> anyOf;
        private String required;

        /**
         * @description A rule that applies when the error contains any of the words.
         * @param anyOf lower-case words or phrases
         * @param advice the advice; {domain}, {certificate} and {org} are filled in
         */
        public Rule(List<String> anyOf, String advice) {
            this.anyOf = anyOf;
            this.advice = advice;
        }

        /**
         * @description Makes the rule apply only when this word appears too.
         * @param word a lower-case word
         * @return this rule
         */
        public Rule alsoNeeding(String word) {
            this.required = word;
            return this;
        }

        /**
         * @description Whether the rule applies to the error.
         * @param lower the error, in lower case
         * @return true when it applies
         */
        public Boolean appliesTo(String lower) {
            if (required != null && !lower.contains(required)) {
                return false;
            }
            for (String word : anyOf) {
                if (lower.contains(word)) {
                    return true;
                }
            }
            return false;
        }
    }

    /**
     * @description The step to fix for a sign-in error, followed by the error itself.
     * @param raw the platform's error message
     * @param org the org the hub tried to sign in to
     * @return the advice, at most 2000 characters
     */
    public static String explain(String raw, RLY_Org__c org) {
        String m = String.isBlank(raw) ? '' : raw;
        String lower = m.toLowerCase();
        String advice = FALLBACK;
        for (Rule r : RULES) {
            if (r.appliesTo(lower)) {
                advice = r.advice;
                break;
            }
        }
        return (fill(advice, org) + (String.isBlank(m) ? '' : ' (' + m.left(400) + ')')).left(2000);
    }

    private static String fill(String advice, RLY_Org__c org) {
        return advice.replace('{domain}', RlyOrgSession.baseUrl(org))
            .replace('{certificate}', String.valueOf(org.Certificate__c))
            .replace('{org}', String.valueOf(org.Name));
    }
}
