/**
 * @description Record type visibility and page layout assignments of profiles, which SOQL can't read: readMetadata
 * (up to 10 profiles a call), its answer scanned as text for recordTypeVisibilities and layoutAssignments without
 * building an XML document. A profile too large to read, or a refused call, leaves those rows unread with a note.
 */
public with sharing class RlyProfileAccessLayouts {

    private static final Integer PROFILES_PER_CALL = 10;
    private static final String RECORD_TYPE = 'recordType';

    /** @description What a read wants from readMetadata answers, and where the values go. */
    public class Want {
        /** @description The profiles asked: metadata name by lower-case name (as sent and decoded). */
        public Map<String, String> profiles = new Map<String, String>();
        /** @description The record types asked, in lower case. */
        public Set<String> recordTypes = new Set<String>();
        /** @description The layout rows asked (record type, or object for its master layout), in lower case. */
        public Set<String> layouts = new Set<String>();
        /** @description Where the values go. */
        public RlyProfileAccessReader.Values out;
    }

    /**
     * @description Reads the record types and layouts the read asks for each of its profiles.
     * @param rd the read
     */
    public static void read(RlyProfileAccessRead rd) {
        List<String> profiles = new List<String>(rd.profileByLabel.values());
        for (Integer i = 0; i < profiles.size(); i += PROFILES_PER_CALL) {
            Want w = new Want();
            w.out = rd.out;
            w.recordTypes = lowered(rd.keysOf(RlyProfileAccessRules.RECORD_TYPES));
            w.layouts = lowered(rd.keysOf(RlyProfileAccessRules.LAYOUTS));
            String names = '';
            for (Integer j = i; j < Math.min(i + PROFILES_PER_CALL, profiles.size()); j++) {
                names += '<met:fullNames>' + RlySoapClient.esc(profiles[j]) + '</met:fullNames>';
                w.profiles.put(profiles[j].toLowerCase(), profiles[j]);
                w.profiles.put(EncodingUtil.urlDecode(profiles[j], 'UTF-8').toLowerCase(), profiles[j]);
            }
            try {
                readBody(RlySoapClient.post(rd.org, '<met:readMetadata><met:type>Profile</met:type>' + names + '</met:readMetadata>').getBody(), w);
            } catch (Exception e) {
                rd.out.notes.add('Couldn\'t read record types and layouts in ' + rd.org.Name + ': ' + e.getMessage().left(200));
            }
        }
    }

    /**
     * @description Reads a readMetadata answer.
     * @param body the answer
     * @param w what's wanted, and where it goes
     */
    public static void readBody(String body, Want w) {
        String text = body == null ? '' : body;
        String fault = RlySoapClient.between(text, '<faultstring>', '</faultstring>');
        if (fault != null) {
            throw new RlyMetadata.MetadataException(fault.unescapeXml());
        }
        Integer pos = text.indexOf('<records');
        while (pos >= 0) {
            Integer close = text.indexOf('</records>', pos);
            if (close < 0) {
                break;
            }
            String chunk = text.substring(pos, close);
            String name = value(chunk, 'fullName');
            String profile = name == null ? null : w.profiles.get(name.toLowerCase());
            if (profile != null) {
                readRecordTypes(profile, chunk, w);
                readLayouts(profile, chunk, w);
            }
            pos = text.indexOf('<records', close);
        }
    }

    // Record types listed, then the ones asked but not listed: not visible.
    private static void readRecordTypes(String profile, String chunk, Want w) {
        for (String block : blocks(chunk, 'recordTypeVisibilities')) {
            String rt = value(block, RECORD_TYPE);
            if (rt != null && w.recordTypes.contains(rt.toLowerCase())) {
                w.out.rows.put(RlyProfileAccessRows.rowKey(profile, RlyProfileAccessRules.RECORD_TYPES, rt),
                    new Map<String, String>{ 'visible' => flag(value(block, 'visible')), 'default' => flag(value(block, 'default')) });
            }
        }
        for (String rt : w.recordTypes) {
            String rowKey = RlyProfileAccessRows.rowKey(profile, RlyProfileAccessRules.RECORD_TYPES, rt);
            if (!w.out.rows.containsKey(rowKey)) {
                w.out.rows.put(rowKey, RlyProfileAccessRows.noAccess(RlyProfileAccessRules.RECORD_TYPES));
            }
        }
    }

    // A layout row is keyed by its record type, or by its object for the master layout.
    private static void readLayouts(String profile, String chunk, Want w) {
        for (String block : blocks(chunk, 'layoutAssignments')) {
            String layout = value(block, 'layout');
            String rt = value(block, RECORD_TYPE);
            String key = rt != null ? rt : String.valueOf(layout).substringBefore('-');
            if (layout != null && w.layouts.contains(key.toLowerCase())) {
                w.out.rows.put(RlyProfileAccessRows.rowKey(profile, RlyProfileAccessRules.LAYOUTS, key), new Map<String, String>{ 'layout' => layout });
            }
        }
    }

    // Every <tag>…</tag> in a chunk.
    private static List<String> blocks(String chunk, String tag) {
        List<String> out = new List<String>();
        String open = '<' + tag + '>';
        String close = '</' + tag + '>';
        Integer pos = chunk.indexOf(open);
        while (pos >= 0) {
            Integer closeAt = chunk.indexOf(close, pos);
            if (closeAt < 0) {
                break;
            }
            out.add(chunk.substring(pos + open.length(), closeAt));
            pos = chunk.indexOf(open, closeAt);
        }
        return out;
    }

    private static String value(String chunk, String name) {
        String v = RlySoapClient.between(chunk, '<' + name + '>', '</' + name + '>');
        return v == null ? null : v.unescapeXml();
    }

    private static String flag(String value) {
        return value == 'true' ? 'true' : 'false';
    }

    private static Set<String> lowered(List<String> values) {
        Set<String> out = new Set<String>();
        for (String v : values) {
            out.add(v.toLowerCase());
        }
        return out;
    }
}
