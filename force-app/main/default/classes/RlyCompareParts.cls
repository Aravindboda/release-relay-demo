/**
 * @description Compare on Review: the components of a compare and their statuses. Checks the components asked for,
 * builds each component from the retrieve zip's files (what the release brings) or from its paths on the branch
 * (what it deletes), and works out file and component statuses (RlyCompareFiles holds the values).
 */
public with sharing class RlyCompareParts {

    /**
     * @description Checks the components asked for: 1 to RlyCompareFiles.MAX_COMPONENTS, each Type:Name.
     * @param keys the components
     */
    public static void checkKeys(List<String> keys) {
        if (keys == null || keys.isEmpty() || keys.size() > RlyCompareFiles.MAX_COMPONENTS) {
            throw new RlyReleaseException('Compare 1 to ' + RlyCompareFiles.MAX_COMPONENTS + ' components at a time.');
        }
        for (String k : keys) {
            if (!isKey(k)) {
                throw new RlyReleaseException('"' + k + '" isn\'t Type:Name.');
            }
        }
    }

    private static Boolean isKey(String k) {
        return String.isNotBlank(k) && k.contains(':') && String.isNotBlank(k.substringBefore(':')) && String.isNotBlank(k.substringAfter(':'));
    }

    /**
     * @description A component the release brings: its files from the zip (main first), or why it isn't compared.
     * @param key Type:Name
     * @param files its files from the zip, or null when the zip doesn't have it
     * @param result the answer so far (the developer org's name and the retrieve's problems)
     * @return the component
     */
    public static RlyCompareFiles.ComponentDiff brought(String key, List<RlyCompareFiles.FileDiff> files, RlyCompareRun.Result result) {
        RlyCompareFiles.ComponentDiff c = new RlyCompareFiles.ComponentDiff();
        c.key = key;
        String typeName = key.substringBefore(':');
        if (!RlyCompareFiles.isSupported(typeName)) {
            c.status = RlyCompareFiles.UNSUPPORTED;
            c.reason = RlyCompareFiles.reasonFor(typeName);
        } else if (files == null) {
            c.status = RlyCompareFiles.UNSUPPORTED;
            c.reason = missingReason(key, result);
        } else {
            c.files = RlyCompareFiles.mainFirst(key, files);
        }
        return c;
    }

    private static String missingReason(String key, RlyCompareRun.Result result) {
        String name = key.substringAfter(':');
        for (String p : result.problems) {
            if (p.containsIgnoreCase(name)) {
                return result.sourceName + ' didn\'t send it: ' + p;
            }
        }
        return result.sourceName + ' didn\'t send it: it may have been deleted or renamed there.';
    }

    /**
     * @description A component the release deletes: its files on the branch (a bundle's are listed from the branch),
     * still to be read.
     * @param key Type:Name
     * @param branch the branch reader
     * @return the component
     */
    public static RlyCompareFiles.ComponentDiff removed(String key, RlyCompareBranch branch) {
        RlyCompareFiles.ComponentDiff c = new RlyCompareFiles.ComponentDiff();
        c.key = key;
        c.deleted = true;
        String typeName = key.substringBefore(':');
        if (!RlyCompareFiles.isSupported(typeName)) {
            c.status = RlyCompareFiles.UNSUPPORTED;
            c.reason = RlyCompareFiles.reasonFor(typeName);
            return c;
        }
        List<String> paths = RlyCompareFiles.pathsOf(key);
        for (String p : paths == null ? branch.filesUnder(RlyCompareFiles.bundleFolder(key)) : paths) {
            RlyCompareFiles.FileDiff f = new RlyCompareFiles.FileDiff();
            f.path = p;
            c.files.add(f);
        }
        if (c.files.isEmpty()) {
            c.status = RlyCompareFiles.SAME;
            c.reason = branch.notThere();
        }
        c.files = RlyCompareFiles.mainFirst(key, c.files);
        return c;
    }

    /**
     * @description A file's status from its two sides (the comparison is exact: Apex == ignores case).
     * @param left the branch's copy, or null
     * @param right the developer org's copy, or null
     * @return new, deleted, same or changed
     */
    public static String statusOf(String left, String right) {
        if (left == null) {
            return right == null ? RlyCompareFiles.SAME : RlyCompareFiles.ADDED;
        }
        if (right == null) {
            return RlyCompareFiles.REMOVED;
        }
        return left.replace('\r\n', '\n').equals(right.replace('\r\n', '\n')) ? RlyCompareFiles.SAME : RlyCompareFiles.CHANGED;
    }

    /**
     * @description Sets a component's status: its main file's, or unsupported when it has no files.
     * @param c the component, files main first
     */
    public static void settle(RlyCompareFiles.ComponentDiff c) {
        if (c.status == RlyCompareFiles.UNSUPPORTED || (c.status == RlyCompareFiles.SAME && c.files.isEmpty())) {
            return;
        }
        if (c.files.isEmpty()) {
            c.status = RlyCompareFiles.UNSUPPORTED;
            return;
        }
        c.status = c.files[0].status;
        if (c.status == RlyCompareFiles.UNSUPPORTED && String.isBlank(c.reason)) {
            c.reason = c.files[0].reason;
        }
    }

    /**
     * @description The reason for a file too large to compare, with its line count.
     * @param text the file
     * @param whereText for example in DEV1
     * @return for example Too large to compare here (6,240 lines in DEV1).
     */
    public static String tooLarge(String text, String whereText) {
        Integer lines = text == null ? 0 : text.countMatches('\n') + 1;
        return RlyCompareFiles.TOO_LARGE + ' (' + lines.format() + ' lines ' + whereText + ').';
    }
}
