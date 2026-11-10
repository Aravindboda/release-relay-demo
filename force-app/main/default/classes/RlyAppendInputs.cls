/**
 * @description What the hub commits and sends while changes are added to an open release (RlyAppendRun): the zip
 * .relay-inbox/<REL>-add-<k>.zip (an empty zip when only deletions are added), the hub run's options append and
 * appendZip, and only the new components and deletions as the run's inputs.
 */
public with sharing class RlyAppendInputs {

    /** @description An empty zip: the file committed when only deletions are added. */
    public static final String EMPTY_ZIP = 'UEsFBgAAAAAAAAAAAAAAAAAAAAAAAA==';

    /**
     * @description The zip the hub commits for the release: .relay-inbox/<REL>-add-<k>.zip while an add is pending,
     * otherwise .relay-inbox/<REL>.zip.
     * @param rel the release
     * @return the path
     */
    public static String zipPath(RLY_Release__c rel) {
        RlyAppendRun.State st = RlyAppendRun.stateOf(rel);
        return '.relay-inbox/' + rel.Name + (st.pending ? '-add-' + st.adds : '') + '.zip';
    }

    /**
     * @description The file committed for an add with only deletions: an empty zip at zipPath.
     * @param rel the release
     * @param branch the release branch
     * @return the file
     */
    public static RlyGitFile emptyZip(RLY_Release__c rel, String branch) {
        return new RlyGitFile(zipPath(rel), branch).withContent(EMPTY_ZIP, rel.Name + ': deletions from ' + RlyAppendRun.stateOf(rel).fromOrg);
    }

    /**
     * @description Adds append and appendZip to a hub run's options while an add is pending.
     * @param rel the release
     * @param options the options
     */
    public static void addOptions(RLY_Release__c rel, Map<String, Object> options) {
        if (RlyAppendRun.isPending(rel)) {
            options.put('append', true);
            options.put('appendZip', zipPath(rel));
        }
    }

    /**
     * @description The components a hub run carries while an add is pending: only the new ones.
     * @param rel the release
     * @return Type:Name, comma separated, or null when no add is pending
     */
    public static String componentsInput(RLY_Release__c rel) {
        RlyAppendRun.State st = RlyAppendRun.stateOf(rel);
        return st.pending ? String.join(st.components, ',') : null;
    }

    /**
     * @description The deletions a hub run carries while an add is pending: only the new ones.
     * @param rel the release
     * @return Type:Name, comma separated, or null when no add is pending
     */
    public static String deletionsInput(RLY_Release__c rel) {
        RlyAppendRun.State st = RlyAppendRun.stateOf(rel);
        return st.pending ? String.join(st.deletions, ',') : null;
    }
}
