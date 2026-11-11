/**
 * @description Compare on Review: reads a Metadata API retrieve zip (Compression.ZipReader) into the files of each
 * component, in source format, as the developer org's side (right). Files compare doesn't show are left out; a binary
 * file, a file over RlyCompareFiles.MAX_FILE_CHARS, or text beyond RlyCompareRun.TEXT_BUDGET is kept as unsupported
 * with its reason, without its text.
 */
public with sharing class RlyCompareZip {

    /**
     * @description The largest retrieve zip (base64 characters, about 1.1 MB) compare decodes. Build 50: static resources
     * and profiles, the large files, are left out of compare, so a part's zip is small; the heap is checked too.
     */
    public static final Integer MAX_ZIP_CHARS = 1500000;
    /** @description Shown when the zip is larger than MAX_ZIP_CHARS. */
    public static final String TOO_BIG = 'These components are too large to compare together. Compare fewer at a time.';

    private static final String BINARY = 'Binary file: compare isn\'t available for it.';

    /**
     * @description The files of each component in the zip.
     * @param zipBase64 the retrieve zip, base64
     * @param sourceName the developer org's name (for the reasons)
     * @return files by Type:Name in lower case, right side set
     * @throws RlyReleaseException when the zip is larger than MAX_ZIP_CHARS (it isn't decoded)
     */
    public static Map<String, List<RlyCompareFiles.FileDiff>> read(String zipBase64, String sourceName) {
        if (String.isBlank(zipBase64)) {
            return new Map<String, List<RlyCompareFiles.FileDiff>>();
        }
        ZipRead z = new ZipRead(opened(zipBase64), sourceName);
        for (Compression.ZipEntry e : z.reader.getEntries()) {
            z.entry(e);
        }
        return z.out;
    }

    // One pass over the zip: the files by component and the characters read so far.
    private class ZipRead {
        final Map<String, List<RlyCompareFiles.FileDiff>> out = new Map<String, List<RlyCompareFiles.FileDiff>>();
        final Compression.ZipReader reader;
        final String sourceName;
        Integer chars = 0;

        ZipRead(Compression.ZipReader reader, String sourceName) {
            this.reader = reader;
            this.sourceName = sourceName;
        }

        Boolean overBudget() {
            return chars >= RlyCompareRun.TEXT_BUDGET;
        }

        void entry(Compression.ZipEntry e) {
            String entryName = e.getName();
            if (RlyCompareFields.isObjectFile(entryName)) {
                chars += addFields(out, entryName, overBudget() ? null : textOf(reader.extract(e), new RlyCompareFiles.FileDiff(), sourceName)); // build 60
                return;
            }
            String key = entryName.endsWith('/') ? null : RlyCompareFiles.keyOf(entryName);
            if (key == null) {
                return;
            }
            RlyCompareFiles.FileDiff f = fileOf(entryName, overBudget() ? null : reader.extract(e), sourceName);
            chars += f.right == null ? 0 : f.right.length();
            add(out, key, f);
        }
    }

    // One file of a component: its text, or why it has none (over the text budget when content is null).
    private static RlyCompareFiles.FileDiff fileOf(String entryName, Blob content, String sourceName) {
        RlyCompareFiles.FileDiff f = new RlyCompareFiles.FileDiff();
        f.path = RlyCompareFiles.sourcePathOf(entryName);
        f.right = content == null ? overBudget(f) : textOf(content, f, sourceName);
        return f;
    }

    private static void add(Map<String, List<RlyCompareFiles.FileDiff>> out, String key, RlyCompareFiles.FileDiff f) {
        if (!out.containsKey(key.toLowerCase())) {
            out.put(key.toLowerCase(), new List<RlyCompareFiles.FileDiff>());
        }
        out.get(key.toLowerCase()).add(f);
    }

    // An object file's fields, each as its own component and file; the characters they add.
    private static Integer addFields(Map<String, List<RlyCompareFiles.FileDiff>> out, String entryName, String text) {
        if (text == null) {
            return 0;
        }
        Integer added = 0;
        Map<String, RlyCompareFiles.FileDiff> fields = RlyCompareFields.fieldsOf(entryName, text);
        for (String key : fields.keySet()) {
            RlyCompareFiles.FileDiff f = fields.get(key);
            added += f.right.length();
            out.put(key.toLowerCase(), new List<RlyCompareFiles.FileDiff>{ f });
        }
        return added;
    }

    // The zip, decoded only when it is small enough to read within the heap: the decoded zip and the files read from
    // it need about twice its base64 length on top of what the request holds already.
    private static Compression.ZipReader opened(String zipBase64) {
        if (zipBase64.length() > MAX_ZIP_CHARS || Limits.getHeapSize() + 2 * zipBase64.length() > Limits.getLimitHeapSize()) {
            throw new RlyReleaseException(TOO_BIG);
        }
        return new Compression.ZipReader(EncodingUtil.base64Decode(zipBase64));
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
        f.reason = RlyCompareFiles.TOO_LARGE + ' with the rest of this part. ' + RlyCompareParts.PIPELINE_HINT;
        return null;
    }
}
