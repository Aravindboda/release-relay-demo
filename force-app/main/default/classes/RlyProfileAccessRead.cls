/**
 * @description One read of profile access in an org (RlyProfileAccessReader): the org, the profiles and rows asked,
 * the Ids found for SetupEntityAccess, the sections read, and the values read so far.
 */
public with sharing class RlyProfileAccessRead {

    /** @description The org read. */
    public RLY_Org__c org;
    /** @description The profiles asked: metadata name by the name Setup shows. */
    public Map<String, String> profileByLabel = new Map<String, String>();
    /** @description The rows asked: keys by section. */
    public Map<String, Set<String>> keysBySection = new Map<String, Set<String>>();
    /** @description Custom metadata types and settings asked: section|key by lower-case API name. */
    public Map<String, List<String>> rowsByEntity = new Map<String, List<String>>();
    /** @description Components found for SetupEntityAccess: section|key by 15-character Id. */
    public Map<String, List<String>> rowsById = new Map<String, List<String>>();
    /** @description Sections read without an error. */
    public Set<String> done = new Set<String>();
    /** @description The values read. */
    public RlyProfileAccessReader.Values out = new RlyProfileAccessReader.Values();

    /**
     * @description A read of these profiles and rows.
     * @param org the org
     * @param profiles the profiles
     * @param rows the rows asked
     */
    public RlyProfileAccessRead(RLY_Org__c org, List<RlyProfileAccessReader.Profile> profiles, List<RlyProfileAccessRules.Row> rows) {
        this.org = org;
        for (RlyProfileAccessReader.Profile p : profiles) {
            profileByLabel.put(p.label, p.profile);
        }
        for (RlyProfileAccessRules.Row r : rows) {
            if (!keysBySection.containsKey(r.section)) {
                keysBySection.put(r.section, new Set<String>());
            }
            keysBySection.get(r.section).add(r.key);
        }
        for (String section : new List<String>{ RlyProfileAccessRules.METADATA_TYPES, RlyProfileAccessRules.SETTINGS }) {
            for (String k : keysOf(section)) {
                addTo(rowsByEntity, k.toLowerCase(), section + '|' + k);
            }
        }
    }

    /**
     * @description Whether a section is asked.
     * @param section the section
     * @return true when it has rows
     */
    public Boolean wants(String section) {
        return keysBySection.containsKey(section);
    }

    /**
     * @description The keys asked in a section.
     * @param section the section
     * @return the keys (empty when none)
     */
    public List<String> keysOf(String section) {
        return wants(section) ? new List<String>(keysBySection.get(section)) : new List<String>();
    }

    /**
     * @description The profiles' names as Setup shows them, quoted for SOQL: ('A', 'B').
     * @return the list
     */
    public String profileList() {
        return RlyProfileAccessQueries.quoted(new List<String>(profileByLabel.keySet()));
    }

    /**
     * @description Notes a component found by Id, for SetupEntityAccess.
     * @param id its Id
     * @param rowKey section|key
     */
    public void addId(String id, String rowKey) {
        if (String.isNotBlank(id)) {
            addTo(rowsById, id.left(15), rowKey);
        }
    }

    /**
     * @description One SetupEntityAccess row: the profile has that class, page, permission, type, setting or app.
     * @param r the row
     */
    public void readAccess(Map<String, Object> r) {
        String profile = profileByLabel.get(RlyProfileAccessRows.profileName(r));
        List<String> rowKeys = rowsById.get(String.valueOf(r.get('SetupEntityId')).left(15));
        if (profile == null || rowKeys == null) {
            return;
        }
        for (String rowKey : rowKeys) {
            String section = rowKey.substringBefore('|');
            out.rows.put(RlyProfileAccessRows.rowKey(profile, section, rowKey.substringAfter('|')), RlyProfileAccessRows.granted(section));
        }
    }

    /**
     * @description Rows whose section was read but that have no entry: no access (a tab: Hidden).
     */
    public void fillDefaults() {
        for (String section : keysBySection.keySet()) {
            if (done.contains(section)) {
                fillSection(section);
            }
        }
    }

    private void fillSection(String section) {
        for (String profile : profileByLabel.values()) {
            for (String key : keysBySection.get(section)) {
                String rowKey = RlyProfileAccessRows.rowKey(profile, section, key);
                if (!out.rows.containsKey(rowKey)) {
                    out.rows.put(rowKey, RlyProfileAccessRows.noAccess(section));
                }
            }
        }
    }

    private static void addTo(Map<String, List<String>> m, String key, String value) {
        if (!m.containsKey(key)) {
            m.put(key, new List<String>());
        }
        m.get(key).add(value);
    }
}
