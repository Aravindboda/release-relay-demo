/**
 * @description A GitLab merge request's diffs as the files the Changes card lists (build 45), with GitHub's keys so
 * RlyPullRequestFileRow reads them as it reads GitHub's: filename, status, additions, deletions, patch and
 * previous_filename. GitLab doesn't count lines: they're counted from each diff. No SOQL, DML or callouts.
 */
public with sharing class RlyGitLabDiffs {

    /**
     * @description A page of diffs as files.
     * @param diffs GitLab's diffs ([{old_path, new_path, diff, new_file, renamed_file, deleted_file}])
     * @return the files
     */
    public static List<Object> toFiles(List<Object> diffs) {
        List<Object> out = new List<Object>();
        for (Object o : diffs == null ? new List<Object>() : diffs) {
            out.add(toFile((Map<String, Object>) o));
        }
        return out;
    }

    private static Map<String, Object> toFile(Map<String, Object> d) {
        String patch = RlySyncParse.text(d.get('diff'));
        Integer[] counted = countLines(patch);
        Map<String, Object> f = new Map<String, Object>{
            'filename' => d.get('new_path'), 'status' => statusOf(d), 'additions' => counted[0], 'deletions' => counted[1]
        };
        if (String.isNotBlank(patch)) {
            f.put('patch', patch);
        }
        if (d.get('renamed_file') == true) {
            f.put('previous_filename', d.get('old_path'));
        }
        return f;
    }

    private static String statusOf(Map<String, Object> d) {
        if (d.get('new_file') == true) {
            return 'added';
        }
        if (d.get('deleted_file') == true) {
            return 'removed';
        }
        return d.get('renamed_file') == true ? 'renamed' : 'modified';
    }

    // Lines added and removed in a unified diff's hunks (GitLab's diff has no file headers).
    private static Integer[] countLines(String patch) {
        Integer added = 0;
        Integer removed = 0;
        for (String line : String.isBlank(patch) ? new List<String>() : patch.split('\n')) {
            if (line.startsWith('+')) {
                added++;
            } else if (line.startsWith('-')) {
                removed++;
            }
        }
        return new Integer[]{ added, removed };
    }

    /**
     * @description A merge request's changes_count as a number ("1000+" when GitLab stopped counting).
     * @param value changes_count
     * @return the number, 0 when absent
     */
    public static Integer changesCount(Object value) {
        String digits = value == null ? '' : String.valueOf(value).replaceAll('[^0-9]', '');
        return String.isBlank(digits) ? 0 : Integer.valueOf(digits.left(9));
    }
}
