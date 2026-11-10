/**
 * @description Checks one profile's rows for RlyProfileAccessRules: a known section, a name the profile file can hold
 * for it, and values it accepts ("true"/"false"; a tab's DefaultOn, DefaultOff or Hidden; a layout of the same object).
 */
public with sharing class RlyProfileAccessRowCheck {

    private static final String NAME_PART = '[A-Za-z][A-Za-z0-9_]{0,79}';
    private static final Pattern NAME = Pattern.compile('^' + NAME_PART + '$');
    private static final Pattern DOTTED = Pattern.compile('^' + NAME_PART + '\\.' + NAME_PART + '$');
    private static final Pattern OBJECT_OR_DOTTED = Pattern.compile('^' + NAME_PART + '(\\.' + NAME_PART + ')?$');
    private static final Pattern TAB = Pattern.compile('^[A-Za-z][A-Za-z0-9_-]{0,79}$');
    private static final Pattern LAYOUT = Pattern.compile('^' + NAME_PART + '-[^<>&"/\\\\]{1,170}$');

    /**
     * @description One profile's rows, checked; rows without values are left out.
     * @param profile the profile's name (for the errors)
     * @param sent the rows, or null
     * @return the checked rows, in the order sent
     */
    public static List<RlyProfileAccessRules.Row> checkedRows(String profile, List<RlyProfileAccessRules.Row> sent) {
        List<RlyProfileAccessRules.Row> out = new List<RlyProfileAccessRules.Row>();
        Set<String> seen = new Set<String>();
        for (RlyProfileAccessRules.Row r : sent == null ? new List<RlyProfileAccessRules.Row>() : sent) {
            RlyProfileAccessRules.Row kept = checkedRow(profile, r);
            if (kept.values.isEmpty()) {
                continue;
            }
            if (!seen.add(kept.section + '|' + kept.key.toLowerCase())) {
                throw new RlyReleaseException(profile + ': ' + kept.key + ' is listed twice under '
                    + RlyProfileAccessRules.sectionLabel(kept.section) + '.');
            }
            out.add(kept);
        }
        return out;
    }

    private static RlyProfileAccessRules.Row checkedRow(String profile, RlyProfileAccessRules.Row r) {
        String section = r == null ? null : r.section;
        if (section == null || !RlyProfileAccessRules.VALUES_OF.containsKey(section)) {
            throw new RlyReleaseException(profile + ': "' + String.valueOf(section).left(40) + '" isn\'t a profile section Release Relay can send.');
        }
        String key = r.key == null ? '' : r.key.trim();
        if (!keyPattern(section).matcher(key).matches()) {
            throw new RlyReleaseException(profile + ': "' + key.left(80) + '" isn\'t a valid name for '
                + RlyProfileAccessRules.sectionLabel(section) + '.');
        }
        RlyProfileAccessRules.Row kept = new RlyProfileAccessRules.Row();
        kept.section = section;
        kept.key = key;
        kept.values = checkedValues(kept, r.values == null ? new Map<String, String>() : r.values);
        return kept;
    }

    // The section's values that were sent, each checked.
    private static Map<String, String> checkedValues(RlyProfileAccessRules.Row row, Map<String, String> sent) {
        Map<String, String> out = new Map<String, String>();
        for (String name : RlyProfileAccessRules.VALUES_OF.get(row.section)) {
            String v = sent.get(name);
            if (String.isNotBlank(v)) {
                out.put(name, checkedValue(row, name, v.trim()));
            }
        }
        return out;
    }

    // A record type and a field are Object.Name; a layout row is about a record type or (its master layout) an object.
    private static Pattern keyPattern(String section) {
        Map<String, Pattern> special = new Map<String, Pattern>{ RlyProfileAccessRules.FIELDS => DOTTED,
            RlyProfileAccessRules.RECORD_TYPES => DOTTED, RlyProfileAccessRules.LAYOUTS => OBJECT_OR_DOTTED, RlyProfileAccessRules.TABS => TAB };
        return special.containsKey(section) ? special.get(section) : NAME;
    }

    private static String checkedValue(RlyProfileAccessRules.Row row, String name, String v) {
        Boolean ok;
        if (row.section == RlyProfileAccessRules.TABS) {
            ok = RlyProfileAccessRules.TAB_VISIBILITIES.contains(v);
        } else if (row.section == RlyProfileAccessRules.LAYOUTS) {
            ok = LAYOUT.matcher(v).matches() && v.substringBefore('-').equalsIgnoreCase(row.key.substringBefore('.'));
        } else {
            ok = v == 'true' || v == 'false';
        }
        if (!ok) {
            throw new RlyReleaseException('"' + v.left(80) + '" isn\'t a valid ' + name + ' for ' + row.key + '.');
        }
        return v;
    }
}
