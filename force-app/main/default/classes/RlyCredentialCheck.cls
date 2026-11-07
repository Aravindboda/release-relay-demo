/**
 * @description One refresh of the Credentials dashboard (build 49): gather runs every check (RlyCredentialHubChecks,
 * RlyCredentialOrgChecks) and, when Slack is on, posts one alert for the items that just turned Critical, Expired or
 * Failed (RlyCredentialAlert) — callouts only; save then upserts the rows by Key__c and removes the ones gone. A request
 * calls gather before any DML and save after its last callout. A pass makes at most BUDGET callouts: orgs that don't fit
 * wait for the next pass, oldest checked first. Runs nightly with the pipeline's archive call (RlyCredentialNightly) and
 * from Check now on the Pipeline tab (RlyCredentialController); no Apex runs in the background.
 */
public with sharing class RlyCredentialCheck {

    /** @description Most callouts one pass makes. */
    public static final Integer BUDGET = 40;
    /** @description The Slack row's key. */
    public static final String SLACK_KEY = 'slack';

    /** @description What one pass found, kept until it is saved. */
    public class Pass {
        /** @description The rows found, by key. */
        public Map<String, RLY_Credential_Status__c> found = new Map<String, RLY_Credential_Status__c>();
        /** @description Saved rows to remove, by key. */
        public Set<String> goneKeys = new Set<String>();
        /** @description The hub's certificates (lower-case developer name) and their expiry. */
        public Map<String, Date> hubCerts = new Map<String, Date>();
        /** @description The rows saved before this pass, by key. */
        public Map<String, RLY_Credential_Status__c> saved = new Map<String, RLY_Credential_Status__c>();
        /** @description Orgs checked this pass. */
        public Integer orgsChecked = 0;
        /** @description Orgs left for the next pass. */
        public Integer orgsLeft = 0;
        /** @description What the Slack alert did, or null. */
        public String alertResult;
        /** @description Items that just turned Critical, Expired or Failed. */
        public List<RLY_Credential_Status__c> turnedBad = new List<RLY_Credential_Status__c>();
        /** @description Most callouts this pass may make. */
        public Integer budget = BUDGET;
        private Integer startCallouts = Limits.getCallouts();

        /**
         * @description Whether the pass can still make this many callouts.
         * @param calls how many
         * @return true when they fit
         */
        public Boolean roomFor(Integer calls) {
            Integer used = Limits.getCallouts() - startCallouts;
            return used + calls <= budget && Limits.getCallouts() + calls <= Limits.getLimitCallouts();
        }

        /**
         * @description Adds (or replaces) a row found.
         * @param r the row
         */
        public void add(RLY_Credential_Status__c r) {
            found.put(r.Key__c, r);
            goneKeys.remove(r.Key__c);
        }

        /**
         * @description Removes a saved row, unless this pass found it.
         * @param key its key
         */
        public void gone(String key) {
            if (!found.containsKey(key)) {
                goneKeys.add(key);
            }
        }

        /**
         * @description After a scope was read in full: saved rows under the prefix that weren't found are gone.
         * @param prefix the key prefix
         */
        public void replaceScope(String prefix) {
            for (String key : saved.keySet()) {
                if (key.startsWith(prefix) && !found.containsKey(key)) {
                    goneKeys.add(key);
                }
            }
        }

        /**
         * @description How many callouts the pass made.
         * @return the count
         */
        public Integer callouts() {
            return Limits.getCallouts() - startCallouts;
        }
    }

    /**
     * @description Runs every check and the Slack alert: callouts only, no DML.
     * @return the pass, to save once the request's callouts are done
     */
    public static Pass gather() {
        Pass p = new Pass();
        p.saved = RlyCredentialStore.byKey();
        p.budget = BUDGET - 1; // room for the Slack alert
        RlyCredentialHubChecks.git(p);
        RlyCredentialHubChecks.slack(p);
        RlyCredentialHubChecks.certificates(p);
        RlyCredentialOrgChecks.run(p);
        removeOrphans(p);
        for (RLY_Credential_Status__c r : p.found.values()) {
            RLY_Credential_Status__c before = p.saved.get(r.Key__c);
            RlyCredentialRows.carry(r, before);
            if (RlyCredentialRows.turnedBad(r, before)) {
                p.turnedBad.add(r);
            }
        }
        p.budget = BUDGET;
        p.alertResult = RlyCredentialAlert.post(p.turnedBad);
        return p;
    }

    /**
     * @description Saves what the pass found and removes what's gone (DML only), and the Slack record's last result.
     * @param p the pass
     */
    public static void save(Pass p) {
        if (p == null) {
            return;
        }
        List<RLY_Credential_Status__c> removals = new List<RLY_Credential_Status__c>();
        for (String key : p.goneKeys) {
            RLY_Credential_Status__c s = p.saved.get(key);
            if (s != null) {
                removals.add(new RLY_Credential_Status__c(Id = s.Id));
            }
        }
        RlyCredentialStore.save(p.found.values(), removals);
        RlySlack.saveResults();
    }

    /**
     * @description A short summary of the pass, for the nightly answer and the page.
     * @param p the pass
     * @return for example "12 checked, 1 needs attention, 2 orgs left for the next pass"
     */
    public static String summary(Pass p) {
        Integer attention = 0;
        for (RLY_Credential_Status__c r : p.found.values()) {
            attention += RlyCredentialRows.ATTENTION.contains(r.Status__c) ? 1 : 0;
        }
        String text = p.found.size() + ' checked, ' + attention + (attention == 1 ? ' needs attention' : ' need attention');
        if (p.orgsLeft > 0) {
            text += ', ' + p.orgsLeft + (p.orgsLeft == 1 ? ' org' : ' orgs') + ' left for the next pass';
        }
        return text;
    }

    // Rows of orgs that are no longer registered.
    private static void removeOrphans(Pass p) {
        Set<String> orgIds = new Set<String>();
        for (RLY_Org__c o : RlyCredentialStore.orgs()) {
            orgIds.add(String.valueOf(o.Id));
        }
        for (String key : p.saved.keySet()) {
            List<String> parts = key.split(':');
            Boolean orgScoped = parts.size() >= 2 && (parts[0] == 'cert' || parts[0] == 'user' || parts[0] == 'signin') && parts[1] != 'hub';
            if (orgScoped && !orgIds.contains(parts[1])) {
                p.gone(key);
            }
        }
    }
}
