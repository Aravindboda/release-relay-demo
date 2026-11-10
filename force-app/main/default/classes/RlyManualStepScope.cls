/**
 * @description The org scope of a manual step (Org_Scope__c): blank for every org on the route, otherwise the names of the
 * registered orgs it applies to, comma separated. Back promote orgs take the steps marked Back_Promote__c instead.
 */
public with sharing class RlyManualStepScope {

    /**
     * @description Checks a scope: blank for every org on the route; otherwise the names, each a registered org.
     * @param orgScope the scope as sent
     * @param orgNames the registered orgs' names, lower case (RlyManualStepRules.knownOrgNames)
     * @return the names, comma separated, or null for every org
     */
    public static String checked(String orgScope, Set<String> orgNames) {
        List<String> names = scopeNames(orgScope);
        for (String n : names) {
            if (!orgNames.contains(n.toLowerCase())) {
                throw new RlyReleaseException('There\'s no registered org named ' + n + ' for this manual step.');
            }
        }
        String joined = String.join(names, ', ');
        if (joined.length() > 255) {
            throw new RlyReleaseException('Pick fewer orgs for this manual step (up to 255 characters of names).');
        }
        return names.isEmpty() ? null : joined;
    }

    /**
     * @description The org names in a scope.
     * @param orgScope Org_Scope__c, or null
     * @return the names, trimmed (empty for every org on the route)
     */
    public static List<String> scopeNames(String orgScope) {
        List<String> out = new List<String>();
        for (String s : String.isBlank(orgScope) ? new List<String>() : orgScope.split(',')) {
            if (String.isNotBlank(s)) {
                out.add(s.trim());
            }
        }
        return out;
    }

    /**
     * @description Whether a step is done in an org on the route.
     * @param step the step, with Org_Scope__c
     * @param orgName the org's name
     * @return true when the scope is blank or names the org
     */
    public static Boolean inScope(RLY_Manual_Step__c step, String orgName) {
        List<String> names = scopeNames(step.Org_Scope__c);
        if (names.isEmpty()) {
            return true;
        }
        for (String n : names) {
            if (n.equalsIgnoreCase(orgName)) {
                return true;
            }
        }
        return false;
    }
}
