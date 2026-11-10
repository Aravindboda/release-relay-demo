/**
 * @description Reads a Git tree answer ({sha, tree:[{path, mode, type, sha, size, url}], truncated}) by scanning its
 * text for each entry's path, type and sha (in any order inside the entry). JSON.deserializeUntyped of a tree with
 * thousands of files takes several times the answer's size in heap; scanning keeps the answer and three short strings
 * per entry.
 */
public with sharing class RlyGitTree {

    private static final String PATH_KEY = '"path"';
    private static final String TYPE_KEY = '"type"';
    private static final String SHA_KEY = '"sha"';

    /**
     * @description The entries of a tree answer, and whether it was cut short.
     * @param body the answer
     * @return the tree
     */
    public static Tree read(String body) {
        Tree t = new Tree();
        String text = body == null ? '' : body;
        Integer treeAt = text.indexOf('"tree"');
        t.truncated = Pattern.compile('"truncated"\\s*:\\s*true').matcher(text).find();
        if (treeAt < 0) {
            return t;
        }
        Integer pos = text.indexOf(PATH_KEY, treeAt);
        while (pos >= 0) {
            Value path = stringAt(text, pos + PATH_KEY.length());
            if (path == null) {
                break;
            }
            // The entry's own object: its keys may come in any order.
            Integer objStart = Math.max(text.lastIndexOf('{', pos), treeAt);
            Integer objEnd = text.indexOf('}', path.endPos);
            objEnd = objEnd < 0 ? text.length() : objEnd;
            Entry e = new Entry();
            e.path = path.text;
            String entryText = text.substring(objStart, objEnd);
            e.type = valueIn(entryText, TYPE_KEY);
            e.sha = valueIn(entryText, SHA_KEY);
            t.entries.add(e);
            pos = text.indexOf(PATH_KEY, objEnd);
        }
        return t;
    }

    /**
     * @description The files of a tree under a path.
     * @param t the tree
     * @param path the folder (blank: every file)
     * @return the file paths
     */
    public static List<String> filesUnder(Tree t, String path) {
        String prefix = String.isBlank(path) ? '' : path.trim().removeEnd('/') + '/';
        List<String> out = new List<String>();
        for (Entry e : t.entries) {
            if (e.type == 'blob' && e.path != null && e.path.startsWith(prefix)) {
                out.add(e.path);
            }
        }
        return out;
    }

    /** @description One entry of a Git tree. */
    public class Entry {
        /** @description Its path, relative to the tree read. */
        public String path;
        /** @description blob (a file), tree (a folder) or commit (a submodule). */
        public String type;
        /** @description Its sha. */
        public String sha;
    }

    /** @description A Git tree: its entries, and whether the provider cut the answer short. */
    public class Tree {
        /** @description The entries. */
        public List<Entry> entries = new List<Entry>();
        /** @description The provider left entries out (too many for one answer). */
        public Boolean truncated = false;
    }

    /** @description A string value and where it ends. */
    private class Value {
        /** @description The text, escapes undone. */
        public String text;
        /** @description The position after its closing quote. */
        public Integer endPos;
    }

    // The value of a key in one entry's text, or null.
    private static String valueIn(String text, String key) {
        Integer at = text.indexOf(key);
        if (at < 0) {
            return null;
        }
        Value v = stringAt(text, at + key.length());
        return v == null ? null : v.text;
    }

    // The JSON string after a key's colon (spaces allowed), or null.
    private static Value stringAt(String text, Integer afterKey) {
        Integer colon = text.indexOf(':', afterKey);
        Integer open = colon < 0 ? -1 : text.indexOf('"', colon);
        if (open < 0 || String.isNotBlank(text.substring(colon + 1, open))) {
            return null;
        }
        Integer close = text.indexOf('"', open + 1);
        while (close > 0 && escaped(text, close)) {
            close = text.indexOf('"', close + 1);
        }
        if (close < 0) {
            return null;
        }
        Value v = new Value();
        String raw = text.substring(open + 1, close);
        v.text = raw.contains('\\') ? (String) JSON.deserialize('"' + raw + '"', String.class) : raw;
        v.endPos = close + 1;
        return v;
    }

    // Whether the quote at a position is escaped (an odd number of backslashes before it).
    private static Boolean escaped(String text, Integer quotePos) {
        Integer n = 0;
        Integer i = quotePos - 1;
        while (i >= 0 && text.substring(i, i + 1) == '\\') {
            n++;
            i--;
        }
        return Math.mod(n, 2) == 1;
    }
}
