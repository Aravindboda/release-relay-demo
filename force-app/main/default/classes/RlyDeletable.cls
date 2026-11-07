/**
 * @description Which components a deploy can't delete, and why (build 37.1): Delete from the branch shows them greyed
 * with the reason, Find deleted components leaves them out, and raising refuses them (RlyDeletionRules).
 *   standard objects and fields (no __ suffix)           Salesforce's own
 *   org settings (…Settings)                              changed, never deleted
 *   standard value sets                                   remove values instead (they become inactive)
 *   standard profiles (Admin, Standard, ReadOnly…)        Salesforce's own
 *   CustomLabels, translations and the one-file-per-object rule sets (Workflow, SharingRules, AssignmentRules,
 *   AutoResponseRules, EscalationRules, MatchingRules)    change the file instead
 * Managed package components (a name with another namespace, ns__…) are a separate reason (managedReason): install or
 * upgrade the package instead.
 */
public with sharing class RlyDeletable {

    /** @description Standard objects and fields. */
    public static final String STANDARD = 'Salesforce\'s own objects and fields can\'t be deleted.';
    /** @description Org settings. */
    public static final String SETTINGS = 'Org settings can be changed by a release, not deleted.';
    /** @description Managed package components. */
    public static final String MANAGED = 'Managed package: install or upgrade the package instead.';

    // Salesforce's standard profiles, as their files are named in source format.
    private static final Set<String> STANDARD_PROFILES = new Set<String>{
        'admin', 'standard', 'readonly', 'contractmanager', 'marketingprofile', 'solutionmanager', 'standardaul',
        'chatter free user', 'chatter external user', 'chatter moderator user', 'guest license user',
        'customer community user', 'customer community login user', 'customer community plus user',
        'customer community plus login user', 'partner community user', 'partner community login user',
        'high volume customer portal user', 'authenticated website', 'minimum access - salesforce',
        'analytics cloud integration user', 'analytics cloud security user', 'identity user', 'external identity user',
        'force.com - free user', 'force.com - app subscription user', 'gold partner user', 'silver partner user',
        'salesforce api only system integrations', 'minimum access - api only integrations'
    };
    // Types that keep every rule (or text) of an object or of the org in one file.
    private static final Map<String, String> ONE_FILE = new Map<String, String>{
        'CustomLabels' => 'All custom labels are in one file: delete a label by removing it from that file.',
        'Translations' => 'Translations are changed, not deleted: remove the texts from the file.',
        'CustomObjectTranslation' => 'Translations are changed, not deleted: remove the texts from the file.',
        'Workflow' => 'An object\'s workflow is one file: remove the rules from it instead.',
        'SharingRules' => 'An object\'s sharing rules are one file: remove the rules from it instead.',
        'AssignmentRules' => 'An object\'s assignment rules are one file: remove the rules from it instead.',
        'AutoResponseRules' => 'An object\'s auto-response rules are one file: remove the rules from it instead.',
        'EscalationRules' => 'An object\'s escalation rules are one file: remove the rules from it instead.',
        'MatchingRules' => 'An object\'s matching rules are one file: remove the rules from it instead.'
    };
    // Suffixes a custom name ends with; a __ left after removing one means a namespace (ns__).
    private static final Pattern SUFFIX_PATTERN = Pattern.compile('__(c|mdt|e|b|x|r|kav|ka|s|pc|pr|Share|History|Feed|ChangeEvent|hd|hst|chn|dlm|dll)$');

    /** @description A component that can't be deleted, and why. */
    public class Blocked {
        /** @description Type:Name. */
        @AuraEnabled public String key;
        /** @description Why. */
        @AuraEnabled public String reason;
    }

    /**
     * @description Why a deploy can't delete a component, or null when it can.
     * @param type the metadata type
     * @param name the component's full name
     * @return the reason, or null
     */
    public static String whyNot(String type, String name) {
        if (String.isBlank(type) || String.isBlank(name)) {
            return null;
        }
        String own = ownReason(type, name);
        return own != null ? own : ONE_FILE.get(type);
    }

    // Salesforce's own objects, fields, settings, value sets and profiles.
    private static String ownReason(String type, String name) {
        if ((type == 'CustomObject' || type == 'CustomField') && !ownName(type, name).contains('__')) {
            return STANDARD;
        }
        if (type.endsWith('Settings')) {
            return SETTINGS;
        }
        if (type == 'StandardValueSet') {
            return 'Standard value sets can\'t be deleted: remove values from the set instead (they become inactive).';
        }
        Boolean standardProfile = type == 'Profile' && STANDARD_PROFILES.contains(decoded(name).toLowerCase());
        return standardProfile ? 'Salesforce\'s standard profiles can\'t be deleted.' : null;
    }

    /**
     * @description Whether a component comes from a managed package: a part of its name carries a namespace other than
     * the org's own (ns__Name, ns__Object__c, Account.ns__Field__c).
     * @param name the component's full name
     * @param orgNamespace the developer org's own namespace, or blank
     * @return MANAGED, or null
     */
    public static String managedReason(String name, String orgNamespace) {
        if (String.isBlank(name)) {
            return null;
        }
        String own = String.isBlank(orgNamespace) ? null : orgNamespace.toLowerCase() + '__';
        for (String token : name.split('[./\\-]')) {
            String core = SUFFIX_PATTERN.matcher(token).replaceAll('');
            Boolean namespaced = core.contains('__') && (own == null || !token.toLowerCase().startsWith(own));
            if (namespaced) {
                return MANAGED;
            }
        }
        return null;
    }

    /**
     * @description The components of a list that can't be deleted, with the reason (managed ones included).
     * @param keys Type:Name keys
     * @param orgNamespace the developer org's own namespace, or blank
     * @return the blocked ones
     */
    public static List<Blocked> blockedOf(List<String> keys, String orgNamespace) {
        List<Blocked> out = new List<Blocked>();
        for (String k : keys) {
            String type = k.substringBefore(':');
            String name = k.substringAfter(':');
            String reason = managedReason(name, orgNamespace);
            reason = reason == null ? whyNot(type, name) : reason;
            if (reason != null) {
                Blocked b = new Blocked();
                b.key = k;
                b.reason = reason;
                out.add(b);
            }
        }
        return out;
    }

    // A file name's component name (some are URL-encoded, like Custom%3A Marketing Profile).
    private static String decoded(String name) {
        if (!name.contains('%')) {
            return name;
        }
        try {
            return EncodingUtil.urlDecode(name.replace('+', '%2B'), 'UTF-8');
        } catch (Exception e) {
            return name; // not encoded after all
        }
    }

    // The object's or field's own name: a field's name after the object.
    private static String ownName(String type, String name) {
        return type == 'CustomField' ? name.substringAfter('.') : name;
    }
}
