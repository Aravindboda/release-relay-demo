/**
 * @description One file of a pull request for the Changes card (RlyPullRequestFiles): the list row without its patch, and
 * the patch when the file is opened, cut when long.
 */
public with sharing class RlyPullRequestFileRow {

    /**
     * @description A file of the list: no patch, only whether there is one.
     * @param c the changes (provider and files view)
     * @param raw the provider's file
     * @param pageNo the page it's on
     * @return the file
     */
    public static RlyPullRequestFiles.FileChange listed(RlyPullRequestFiles.Changes c, Map<String, Object> raw, Integer pageNo) {
        RlyPullRequestFiles.FileChange f = new RlyPullRequestFiles.FileChange();
        f.filename = RlySyncParse.text(raw.get('filename'));
        f.status = RlySyncParse.text(raw.get('status'));
        f.additions = count(raw.get('additions'));
        f.deletions = count(raw.get('deletions'));
        f.hasPatch = String.isNotBlank(RlySyncParse.text(raw.get('patch')));
        f.pageNo = pageNo;
        f.previousFilename = RlySyncParse.text(raw.get('previous_filename'));
        f.url = c.filesUrl == null || f.filename == null ? c.filesUrl : c.filesUrl + '#diff-' + anchor(f.filename);
        f.note = f.hasPatch ? null : 'No preview: open in ' + c.provider + '.';
        return f;
    }

    /**
     * @description The file with its patch, cut at a line end before RlyPullRequestFiles.MAX_PATCH characters.
     * @param f the file
     * @param patch the provider's patch
     * @param provider the provider's name
     * @return the file
     */
    public static RlyPullRequestFiles.FileChange withPatch(RlyPullRequestFiles.FileChange f, String patch, String provider) {
        if (String.isBlank(patch) || patch.length() <= RlyPullRequestFiles.MAX_PATCH) {
            f.patch = patch;
            return f;
        }
        Integer cut = patch.lastIndexOf('\n', RlyPullRequestFiles.MAX_PATCH);
        f.patch = patch.left(cut > 0 ? cut : RlyPullRequestFiles.MAX_PATCH);
        f.note = 'Only the first ' + RlyPullRequestFiles.MAX_PATCH.format() + ' characters of this file\'s changes are shown: open in ' + provider + ' for the rest.';
        return f;
    }

    // The files view's anchor of a file: the SHA-256 of its path, in hex.
    private static String anchor(String filename) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(filename)));
    }

    /**
     * @description A value as a count.
     * @param value the value
     * @return the count, 0 when absent
     */
    public static Integer count(Object value) {
        return value == null ? 0 : Integer.valueOf(value);
    }
}
