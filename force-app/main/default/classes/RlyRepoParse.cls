/**
 * @description Reads .relay/values.json and .relay/gates.json the way the pipeline does (RlyRepoSettings): keys
 * starting with _ are ignored at every level, a value must be text, a gate must be in its range (failAtPriority a
 * whole number from 1 to 5, coverage a number from 0 to 100, requireForApex true).
 */
public with sharing class RlyRepoParse {

    private static final String NOT_SET = 'Not set';
    private static final String IGNORED_PREFIX = '_';

    /**
     * @description A file's JSON object; a blank or missing file is an empty object.
     * @param text the file's content, or null
     * @return the object
     */
    public static Map<String, Object> objectOf(String text) {
        if (String.isBlank(text)) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>) JSON.deserializeUntyped(text);
    }

    /**
     * @description The named values under "values", in the file's order; a name that doesn't map environments to
     * values is left out, as the pipeline ignores it.
     * @param root the values file
     * @return the rows
     */
    public static List<RlyRepoSettings.ValueRow> valueRows(Map<String, Object> root) {
        List<RlyRepoSettings.ValueRow> rows = new List<RlyRepoSettings.ValueRow>();
        Map<String, Object> named = section(root, 'values');
        for (String name : named.keySet()) {
            Object perEnvironment = named.get(name);
            if (!name.startsWith(IGNORED_PREFIX) && perEnvironment instanceof Map<String, Object>) {
                rows.add(rowOf(name, (Map<String, Object>) perEnvironment));
            }
        }
        return rows;
    }

    private static RlyRepoSettings.ValueRow rowOf(String name, Map<String, Object> perEnvironment) {
        RlyRepoSettings.ValueRow row = new RlyRepoSettings.ValueRow();
        row.name = name;
        for (String environment : perEnvironment.keySet()) {
            Object value = perEnvironment.get(environment);
            if (!environment.startsWith(IGNORED_PREFIX) && value instanceof String) {
                row.byEnvironment.put(environment, (String) value);
            }
        }
        return row;
    }

    /**
     * @description Every environment name the rows use, first seen first.
     * @param rows the value rows
     * @return the names
     */
    public static List<String> environments(List<RlyRepoSettings.ValueRow> rows) {
        List<String> out = new List<String>();
        for (RlyRepoSettings.ValueRow row : rows) {
            for (String environment : row.byEnvironment.keySet()) {
                if (!out.contains(environment)) {
                    out.add(environment);
                }
            }
        }
        return out;
    }

    /**
     * @description The four gates in words, or none when the file sets nothing (only _ keys, or empty).
     * @param root the gates file
     * @return the rows
     */
    public static List<RlyRepoSettings.GateRow> gateRows(Map<String, Object> root) {
        List<RlyRepoSettings.GateRow> rows = new List<RlyRepoSettings.GateRow>();
        if (!hasSettings(root)) {
            return rows;
        }
        Map<String, Object> coverage = section(root, 'coverage');
        rows.add(scanGate(section(root, 'scan').get('failAtPriority')));
        rows.add(percentGate(new List<String>{ 'perClass', 'Coverage per class', 'Each deployed Apex class ≥ ' }, coverage.get('minimumPerClass'), NOT_SET));
        rows.add(percentGate(new List<String>{ 'orgWide', 'Coverage org-wide', 'Org-wide coverage ≥ ' }, coverage.get('minimumOrgWide'),
            NOT_SET + ' (Salesforce\'s 75% in production)'));
        List<String> tests = new List<String>{ 'tests', 'Tests for Apex' };
        rows.add(section(root, 'tests').get('requireForApex') == true ? setTo(tests, 'Required when a release has Apex') : unset(tests, NOT_SET));
        return rows;
    }

    private static Boolean hasSettings(Map<String, Object> root) {
        for (String key : root.keySet()) {
            if (!key.startsWith(IGNORED_PREFIX)) {
                return true;
            }
        }
        return false;
    }

    // scan.failAtPriority: a whole number from 1 (most serious) to 5.
    private static RlyRepoSettings.GateRow scanGate(Object value) {
        List<String> names = new List<String>{ 'scan', 'Code scan' };
        if (value == null) {
            return unset(names, NOT_SET);
        }
        Decimal priority = numberOf(value);
        if (priority == null || priority != priority.round(System.RoundingMode.DOWN) || priority < 1 || priority > 5) {
            return unset(names, 'Not valid in the file: failAtPriority must be a whole number from 1 to 5');
        }
        return setTo(names, 'Fails at priority ' + priority.intValue() + ' or higher (1 = most serious)');
    }

    // A coverage minimum: a number from 0 to 100. names: key, label, text before the number.
    private static RlyRepoSettings.GateRow percentGate(List<String> names, Object value, String unsetText) {
        if (value == null) {
            return unset(names, unsetText);
        }
        Decimal percent = numberOf(value);
        if (percent == null || percent < 0 || percent > 100) {
            return unset(names, 'Not valid in the file: must be a number from 0 to 100');
        }
        return setTo(names, names[2] + percent.stripTrailingZeros().toPlainString() + '%');
    }

    // A JSON number (Integer, Long or Decimal once read), or null for anything else.
    private static Decimal numberOf(Object value) {
        Boolean isNumber = value instanceof Integer || value instanceof Long || value instanceof Decimal;
        return isNumber ? Decimal.valueOf(String.valueOf(value)) : null;
    }

    // A gate the file sets. names: key, label.
    private static RlyRepoSettings.GateRow setTo(List<String> names, String text) {
        RlyRepoSettings.GateRow row = unset(names, text);
        row.isSet = true;
        return row;
    }

    // A gate the file doesn't set (or sets to something the pipeline can't use). names: key, label.
    private static RlyRepoSettings.GateRow unset(List<String> names, String text) {
        RlyRepoSettings.GateRow row = new RlyRepoSettings.GateRow();
        row.key = names[0];
        row.label = names[1];
        row.text = text;
        return row;
    }

    // An object inside the file, or an empty one when it's missing or not an object.
    private static Map<String, Object> section(Map<String, Object> root, String key) {
        Object value = root.get(key);
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : new Map<String, Object>();
    }
}
