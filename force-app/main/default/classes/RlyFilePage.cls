/**
 * @description One file of a compare or a sync check as the pipeline saved it (results/<id>/f/<n>.json), read into a
 * FileDiff (build 57: shared by RlyComparePipelineResult and RlySyncResult).
 */
public with sharing class RlyFilePage {

    /**
     * @description The file's two sides, its patch and its status.
     * @param f the page as read (path, left, right, patch)
     * @param n the page number
     * @return the diff
     */
    public static RlyCompareFiles.FileDiff diffOf(Map<String, Object> f, Integer n) {
        RlyCompareFiles.FileDiff d = new RlyCompareFiles.FileDiff();
        d.n = n;
        d.path = RlySyncParse.text(f.get('path'));
        d.left = RlySyncParse.text(f.get('left'));
        d.right = RlySyncParse.text(f.get('right'));
        d.patch = RlySyncParse.text(f.get('patch'));
        d.status = d.patch != null ? RlyCompareFiles.CHANGED : RlyCompareParts.statusOf(d.left, d.right);
        return d;
    }
}
