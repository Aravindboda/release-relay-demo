/**
 * @description Build 60 (D40): the file the hub commits on a new release's branch with its components when the developer
 * took lines out on purpose on Review: .relay-inbox/<REL>-keep.json, {"removeOnPurpose": [{component, item}]}. The
 * pipeline (version 34) takes those lines out and puts back every other line the target branch has and the developer
 * org lacks, then takes the upload file off.
 */
public with sharing class RlyKeepFile {

    /**
     * @description The file's path on the release branch.
     * @param rel the release, with Name
     * @return .relay-inbox/<REL>-keep.json
     */
    public static String pathOf(RLY_Release__c rel) {
        return '.relay-inbox/' + rel.Name + '-keep.json';
    }

    /**
     * @description The file to commit.
     * @param rel the release, with Id and Name
     * @param branch the release branch
     * @return the file, or null when nothing is taken out on purpose
     */
    public static RlyGitFile fileFor(RLY_Release__c rel, String branch) {
        List<RlyKeepRules.KeepItem> items = RlyKeepRules.fromField(RlyReleaseStore.removeOnPurpose(rel.Id));
        if (items.isEmpty()) {
            return null;
        }
        String body = JSON.serialize(new Map<String, Object>{ 'removeOnPurpose' => items }, true);
        return new RlyGitFile(pathOf(rel), branch).withContent(EncodingUtil.base64Encode(Blob.valueOf(body)), rel.Name + ': lines taken out on purpose');
    }
}
