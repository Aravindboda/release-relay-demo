/**
 * @description "Open org" on the release page and in the Manual steps card: every org on the release's route (its source,
 * each stage in route order, the back promote orgs when back promote is on, and its target) with the
 * org's name, environment and login address (its My Domain followed by "/", which shows the login page or signs in with
 * single sign-on). Only for Release Relay admins and the deployment team (RlyManualSteps.canCheck); everyone else gets
 * an empty list. The hub (production) is never listed: users already work in it, so a release that only touches the hub
 * gets an empty list and the page shows no menu. Never carries sign-in details: the address only.
 */
public with sharing class RlyOrgLinks {

    // The hub is left out: users already work there.
    private static final String PRODUCTION_ROLE = 'Hub';

    /** @description One org the release passes through, as the Open org menu shows it. */
    public class OrgLink {
        /** @description The RLY_Org__c record. */
        @AuraEnabled public Id orgId;
        /** @description Its name. */
        @AuraEnabled public String name;
        /** @description Its environment's label, for example Partial Copy, or null. */
        @AuraEnabled public String environment;
        /** @description Its login address: the My Domain URL followed by "/". */
        @AuraEnabled public String loginUrl;
    }

    /**
     * @description The orgs on the release's route with their login addresses, in route order; empty for users who are
     * neither admins nor on the deployment team.
     * @param rel the release, with Source_Org__c and Target_Org__c
     * @return the links (the hub and orgs without a My Domain are left out)
     */
    public static List<OrgLink> forRelease(RLY_Release__c rel) {
        List<OrgLink> out = new List<OrgLink>();
        if (rel == null || !RlyManualSteps.canCheck()) {
            return out;
        }
        Set<Id> added = new Set<Id>();
        for (RLY_Org__c o : routeOf(rel)) {
            String address = loginUrlOf(o.My_Domain__c);
            if (address != null && o.Role__c != PRODUCTION_ROLE && added.add(o.Id)) {
                out.add(linkOf(o, address));
            }
        }
        return out;
    }

    /**
     * @description An org's login address: its My Domain over https, followed by "/".
     * @param myDomain the My Domain URL, for example https://acme.my.salesforce.com
     * @return the address, or null when there is no https My Domain
     */
    public static String loginUrlOf(String myDomain) {
        String trimmed = myDomain == null ? '' : myDomain.trim().removeEnd('/');
        return trimmed.startsWithIgnoreCase('https://') && trimmed.length() > 8 ? trimmed + '/' : null;
    }

    // Source, stages (the hub is dropped by forRelease), back promote orgs when on, then the target (already listed unless a back promote org).
    private static List<RLY_Org__c> routeOf(RLY_Release__c rel) {
        Map<Id, RLY_Org__c> byId = new Map<Id, RLY_Org__c>();
        List<RLY_Org__c> stages = new List<RLY_Org__c>();
        List<RLY_Org__c> backOrgs = new List<RLY_Org__c>();
        for (RLY_Org__c o : new OrgAccess().orgs()) {
            byId.put(o.Id, o);
            if (o.Role__c == RlyBackPromote.ROLE) {
                backOrgs.add(o);
            } else if (RlyRouteRules.isStage(o)) {
                stages.add(o);
            }
        }
        List<RLY_Org__c> out = new List<RLY_Org__c>();
        addIfKnown(out, byId.get(rel.Source_Org__c));
        out.addAll(RlyRouteRules.ordered(stages));
        if (RlyBackPromote.isOn(RlyReleaseStore.git())) {
            out.addAll(backOrgs);
        }
        addIfKnown(out, byId.get(rel.Target_Org__c));
        return out;
    }

    private static void addIfKnown(List<RLY_Org__c> out, RLY_Org__c o) {
        if (o != null) {
            out.add(o);
        }
    }

    private static OrgLink linkOf(RLY_Org__c o, String address) {
        OrgLink l = new OrgLink();
        l.orgId = o.Id;
        l.name = o.Name;
        l.environment = o.Environment__c;
        l.loginUrl = address;
        return l;
    }

    /** @description Org records are Release Relay's own configuration, read for every Release Relay user: system mode. */
    private without sharing class OrgAccess {

        /**
         * @description The registered orgs with their environment label and My Domain only (no sign-in fields).
         * @return the orgs, by name
         */
        public List<RLY_Org__c> orgs() {
            return [SELECT Id, Name, Role__c, Stage_Order__c, toLabel(Environment__c), My_Domain__c
                    FROM RLY_Org__c WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }
    }
}
