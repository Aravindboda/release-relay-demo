/**
 * @description New Release, step Profile access: the developer org's profiles, what the picked profiles have now in
 * the developer org and in the release's target, and a release's profile access for its page.
 */
public with sharing class RlyProfileAccessController {

    /** @description What the page asks to read. */
    public class Ask {
        /** @description The developer org. */
        public Id orgId;
        /** @description The profiles (metadata name and label). */
        public List<RlyProfileAccessReader.Profile> profiles;
        /** @description The rows (section and key). */
        public List<RlyProfileAccessRules.Row> rows;
    }

    /** @description What the profiles have now, in the developer org and in the target. */
    public class Answer {
        /** @description The developer org's values. */
        @AuraEnabled public RlyProfileAccessReader.Values source;
        /** @description The target's values (empty when it couldn't be read: see its notes). */
        @AuraEnabled public RlyProfileAccessReader.Values target;
        /** @description The developer org's name. */
        @AuraEnabled public String sourceName;
        /** @description The target's name. */
        @AuraEnabled public String targetName;
    }

    /**
     * @description The developer org's profiles.
     * @param orgId the developer org
     * @return its profiles, by name
     */
    @AuraEnabled
    public static List<RlyProfileAccessReader.Profile> profiles(Id orgId) {
        try {
            return RlyProfileAccessReader.profiles(RlyChangesController.source(orgId));
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e, 'Couldn\'t list the profiles: ');
        }
    }

    /**
     * @description What the picked profiles have now for the rows, in the developer org and in the release's target.
     * @param askJson the Ask, as JSON
     * @return the answer
     */
    @AuraEnabled
    public static Answer readAccess(String askJson) {
        try {
            Ask ask = (Ask) JSON.deserialize(askJson, Ask.class);
            RLY_Org__c source = RlyChangesController.source(ask.orgId);
            List<RlyProfileAccessReader.Profile> profiles = ask.profiles == null ? new List<RlyProfileAccessReader.Profile>() : ask.profiles;
            List<RlyProfileAccessRules.Row> rows = ask.rows == null ? new List<RlyProfileAccessRules.Row>() : ask.rows;
            if (profiles.size() > RlyProfileAccessRules.MAX_PROFILES || rows.size() > RlyProfileAccessRules.MAX_ROWS) {
                throw new RlyReleaseException('Pick up to ' + RlyProfileAccessRules.MAX_PROFILES + ' profiles and '
                    + RlyProfileAccessRules.MAX_ROWS + ' rows.');
            }
            List<RlyProfileAccessRules.Row> checkedRows = askedRows(rows);
            Answer a = new Answer();
            a.sourceName = source.Name;
            a.source = RlyProfileAccessReader.read(source, profiles, checkedRows);
            a.target = new RlyProfileAccessReader.Values();
            try {
                RLY_Org__c target = RlyRaiseRules.route(source.Id).target;
                a.targetName = target.Name;
                a.target = RlyProfileAccessReader.read(RlyReleaseStore.org(target.Id), profiles, checkedRows);
            } catch (Exception e) {
                a.target.notes.add('Couldn\'t read the target\'s profiles: ' + e.getMessage().left(200));
            }
            return a;
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e, 'Couldn\'t read the profile access: ');
        }
    }

    // The rows asked, each checked as a row the release could send (with a stand-in value).
    private static List<RlyProfileAccessRules.Row> askedRows(List<RlyProfileAccessRules.Row> rows) {
        List<RlyProfileAccessRules.Row> out = new List<RlyProfileAccessRules.Row>();
        for (RlyProfileAccessRules.Row r : rows) {
            RlyProfileAccessRules.Row probe = new RlyProfileAccessRules.Row();
            probe.section = r.section;
            probe.key = r.key;
            probe.values = new Map<String, String>();
            RlyProfileAccessRules.ProfileRows p = new RlyProfileAccessRules.ProfileRows();
            p.profile = 'Check';
            p.rows = new List<RlyProfileAccessRules.Row>{ probe };
            RlyProfileAccessRules.checked(new List<RlyProfileAccessRules.ProfileRows>{ p });
            out.add(probe);
        }
        return out;
    }

    /**
     * @description A release's profile access, for its page.
     * @param releaseId the release
     * @return its profiles and rows (empty when it has none)
     */
    @AuraEnabled(cacheable=true)
    public static List<RlyProfileAccessRules.ProfileRows> forRelease(Id releaseId) {
        try {
            return RlyProfileAccessRules.fromField(RlyReleaseStore.profileAccess(releaseId));
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }
}
