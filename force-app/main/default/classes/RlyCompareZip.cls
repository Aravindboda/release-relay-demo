/**
 * @description Compare on Review: reads a Metadata API retrieve zip (Compression.ZipReader) into the files of each
 * component, in source format, as the developer org's side (right). Files compare doesn't show are left out; a binary
 * file, a file over RlyCompareFiles.MAX_FILE_CHARS, or text beyond RlyCompareRun.TEXT_BUDGET is kept as unsupported
 * with its reason, without its text.
 */
public with sharing class RlyCompareZip {

    private static final String BINARY = 'Binary file: compare isn\'t available for it.';

    /**
     * @description The files of each component in the zip.
     * @param zipBase64 the retrieve zip, base64
     * @param sourceName the developer org's name (for the reasons)
     * @return files by Type:Name in lower case, right side set
     */
    public static Map<String, List<RlyCompareFiles.FileDiff>> read(String zipBase64, String sourceName) {
        Map<String, List<RlyCompareFiles.FileDiff>> out = new Map<String, List<RlyCompareFiles.FileDiff>>();
        if (String.isBlank(zipBase64)) {
            return out;
        }
        Compression.ZipReader reader = new Compression.ZipReader(EncodingUtil.base64Decode(zipBase64));
        Integer chars = 0;
        for (Compression.ZipEntry e : reader.getEntries()) {
            String entryName = e.getName();
            String key = entryName.endsWith('/') ? null : RlyCompareFiles.keyOf(entryName);
            if (key == null) {
                continue;
            }
            RlyCompareFiles.FileDiff f = new RlyCompareFiles.FileDiff();
            f.path = RlyCompareFiles.sourcePathOf(entryName);
            f.right = chars >= RlyCompareRun.TEXT_BUDGET ? overBudget(f) : textOf(reader.extract(e), f, sourceName);
            chars += f.right == null ? 0 : f.right.length();
            if (!out.containsKey(key.toLowerCase())) {
                out.put(key.toLowerCase(), new List<RlyCompareFiles.FileDiff>());
            }
            out.get(key.toLowerCase()).add(f);
        }
        return out;
    }

    // The file's text, or null with the file marked unsupported (binary, too large).
    private static String textOf(Blob content, RlyCompareFiles.FileDiff f, String sourceName) {
        String text;
        try {
            text = content.toString();
        } catch (Exception ex) {
            f.status = RlyCompareFiles.UNSUPPORTED;
            f.reason = BINARY;
            return null;
        }
        if (text.length() > RlyCompareFiles.MAX_FILE_CHARS) {
            f.status = RlyCompareFiles.UNSUPPORTED;
            f.reason = RlyCompareParts.tooLarge(text, 'in ' + sourceName);
            return null;
        }
        return text;
    }

    private static String overBudget(RlyCompareFiles.FileDiff f) {
        f.status = RlyCompareFiles.UNSUPPORTED;
        f.reason = RlyCompareFiles.TOO_LARGE + ': compare fewer components at a time.';
        return null;
    }
}
