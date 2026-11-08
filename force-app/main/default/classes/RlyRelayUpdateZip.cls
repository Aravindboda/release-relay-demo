/**
 * @description Install Release Relay update: what a build's zip holds, read with Compression.ZipReader. The tests are
 * every Apex class in it whose name ends in Test; the components are the members of its package.xml (Type:Name), as
 * the pipeline's COMPONENTS input takes them. Only the entry names and package.xml are read, never the other files.
 */
public with sharing class RlyRelayUpdateZip {

    /** @description The longest components input the hub sends (as RlyPipelineRun does). */
    public static final Integer MAX_COMPONENT_CHARS = 60000;
    private static final Pattern TEST_CLASS_PATTERN = Pattern.compile('^(?:.*/)?classes/([A-Za-z][A-Za-z0-9_]{0,79}Test)\\.cls$');
    private static final String MANIFEST = 'package.xml';
    private static final String WILDCARD = '*';

    /** @description What the zip holds. */
    public class Contents {
        /** @description The test classes, sorted. */
        public List<String> tests = new List<String>();
        /** @description The package.xml members as Type:Name, in package order. */
        public List<String> components = new List<String>();
    }

    /**
     * @description Reads a build's zip.
     * @param zip the zip
     * @return its tests and components
     */
    public static Contents read(Blob zip) {
        Compression.ZipReader reader = new Compression.ZipReader(zip);
        Contents c = new Contents();
        Compression.ZipEntry manifestEntry;
        for (Compression.ZipEntry e : reader.getEntries()) {
            String entryName = e.getName();
            String test = testName(entryName);
            if (test != null) {
                c.tests.add(test);
            }
            if (isManifest(entryName) && (manifestEntry == null || entryName.length() < manifestEntry.getName().length())) {
                manifestEntry = e;
            }
        }
        if (manifestEntry != null) {
            c.components = members(reader.extract(manifestEntry).toString());
        }
        c.tests.sort();
        return c;
    }

    /**
     * @description The test class an entry is, when it is one.
     * @param entryName the entry's path in the zip
     * @return the class name, or null
     */
    public static String testName(String entryName) {
        Matcher m = TEST_CLASS_PATTERN.matcher(entryName == null ? '' : entryName);
        return m.matches() ? m.group(1) : null;
    }

    /**
     * @description The members of a package.xml as Type:Name (wildcards and names the pipeline can't take left out).
     * @param packageXml the package.xml text
     * @return the components, in package order
     */
    public static List<String> members(String packageXml) {
        List<String> out = new List<String>();
        Dom.Document doc = new Dom.Document();
        doc.load(packageXml);
        for (Dom.XmlNode types : doc.getRootElement().getChildElements()) {
            if (types.getName() == 'types') {
                addTypes(types, out);
            }
        }
        return out;
    }

    /**
     * @description A list joined with commas, whole entries only, no longer than a limit.
     * @param items the entries
     * @param maxChars the limit
     * @return the joined text
     */
    public static String joined(List<String> items, Integer maxChars) {
        List<String> kept = new List<String>();
        Integer used = 0;
        for (String item : items == null ? new List<String>() : items) {
            Integer more = item.length() + (kept.isEmpty() ? 0 : 1);
            if (used + more > maxChars) {
                break;
            }
            kept.add(item);
            used += more;
        }
        return String.join(kept, ',');
    }

    /**
     * @description Whether a file name is a zip.
     * @param fileName the name
     * @return true for *.zip
     */
    public static Boolean isZip(String fileName) {
        return fileName != null && fileName.toLowerCase().endsWith('.zip');
    }

    private static void addTypes(Dom.XmlNode types, List<String> out) {
        String typeName;
        List<String> names = new List<String>();
        for (Dom.XmlNode child : types.getChildElements()) {
            if (child.getName() == 'name') {
                typeName = child.getText().trim();
            } else if (child.getName() == 'members') {
                names.add(child.getText().trim());
            }
        }
        if (String.isBlank(typeName)) {
            return;
        }
        for (String n : names) {
            if (usable(n)) {
                out.add(typeName + ':' + n);
            }
        }
    }

    // A member the pipeline's COMPONENTS input can take: a name, not a wildcard, without commas or colons.
    private static Boolean usable(String memberName) {
        return String.isNotBlank(memberName) && memberName != WILDCARD && !memberName.contains(',') && !memberName.contains(':');
    }

    private static Boolean isManifest(String entryName) {
        return entryName == MANIFEST || entryName.endsWith('/' + MANIFEST);
    }
}
