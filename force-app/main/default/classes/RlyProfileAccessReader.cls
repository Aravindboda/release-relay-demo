/**
 * @description Reads profile access in a registered org for New Release's Profile access step: the org's profiles
 * (listMetadata for their metadata names, SOQL for the names Setup shows) and, for the profiles and rows asked, what
 * each profile has now.
 *
 * Calls per read: one composite request (up to 25 queries) for field, object, tab and system permissions plus the Ids
 * of the classes, pages, custom permissions, custom metadata types, custom settings and apps asked
 * (RlyProfileAccessQueries); one more for their access (SetupEntityAccess) when any were found; and readMetadata (up
 * to 10 profiles a call) only when record types or layouts are asked, since SOQL can't read those
 * (RlyProfileAccessLayouts). A query that fails leaves its rows unread, with a note (RlyProfileAccessComposite).
 */
public with sharing class RlyProfileAccessReader {

    /** @description One profile of an org. */
    public class Profile {
        /** @description Its metadata name (its file name: Admin for System Administrator). */
        @AuraEnabled public String profile;
        /** @description Its name as Setup shows it. */
        @AuraEnabled public String label;
    }

    /** @description What an org's profiles have now, by profile|section|key (key in lower case). */
    public class Values {
        /** @description The values read, by profile|section|key. */
        @AuraEnabled public Map<String, Map<String, String>> rows = new Map<String, Map<String, String>>();
        /** @description What couldn't be read, in the page's words. */
        @AuraEnabled public List<String> notes = new List<String>();
    }

    /**
     * @description The org's profiles, by name.
     * @param org the registered org
     * @return its profiles
     */
    public static List<Profile> profiles(RLY_Org__c org) {
        Map<String, String> labelById = new Map<String, String>();
        for (Object o : RlyChangeFinder.rowsOf((Map<String, Object>) RlyOrgSession.getJson(org,
                RlyOrgSession.queryPath('SELECT Id, Name FROM Profile ORDER BY Name LIMIT 2000')))) {
            Map<String, Object> r = (Map<String, Object>) o;
            labelById.put(String.valueOf(r.get('Id')).left(15), String.valueOf(r.get('Name')));
        }
        Map<String, Profile> byLabel = new Map<String, Profile>();
        for (RlyMetadata.FileProp f : RlyMetadataList.call(org, '<met:queries><met:type>Profile</met:type></met:queries>'
                + '<met:asOfVersion>' + RlyOrgSession.API_VERSION + '</met:asOfVersion>')) {
            Profile p = new Profile();
            p.profile = f.fullName;
            String label = f.id == null ? null : labelById.get(f.id.left(15));
            p.label = label == null ? EncodingUtil.urlDecode(f.fullName, 'UTF-8') : label;
            byLabel.put(p.label.toLowerCase() + '|' + p.profile, p);
        }
        List<String> keys = new List<String>(byLabel.keySet());
        keys.sort();
        List<Profile> out = new List<Profile>();
        for (String k : keys) {
            out.add(byLabel.get(k));
        }
        return out;
    }

    /**
     * @description What the profiles have now for the rows asked.
     * @param org the registered org
     * @param profiles the profiles (metadata name and label)
     * @param rows the rows asked (section and key; values are ignored)
     * @return the values, by profile|section|key
     */
    public static Values read(RLY_Org__c org, List<Profile> profiles, List<RlyProfileAccessRules.Row> rows) {
        RlyProfileAccessRead rd = new RlyProfileAccessRead(org, profiles, rows);
        if (profiles.isEmpty() || rows.isEmpty()) {
            return rd.out;
        }
        RlyProfileAccessComposite.runAll(rd, RlyProfileAccessQueries.first(rd));
        List<RlyProfileAccessQueries.Sub> access = RlyProfileAccessQueries.access(rd);
        if (!access.isEmpty()) {
            RlyProfileAccessComposite.runAll(rd, access);
        }
        if (rd.wants(RlyProfileAccessRules.RECORD_TYPES) || rd.wants(RlyProfileAccessRules.LAYOUTS)) {
            RlyProfileAccessLayouts.read(rd);
        }
        rd.fillDefaults();
        return rd.out;
    }
}
