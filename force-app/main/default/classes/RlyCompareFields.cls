/**
 * @description Compare on Review (build 60): custom fields. A Metadata API retrieve of CustomField:Account.Tier__c brings
 * objects/Account.object with only the asked fields inside it; in source format each field is its own file,
 * objects/Account/fields/Tier__c.field-meta.xml. This turns each fields element of the object file into that file's
 * text (one indent less, wrapped in CustomField), so compare and the Review list of kept lines (D40) can read fields.
 */
public with sharing class RlyCompareFields {

    private static final String OPEN = '<fields>';
    private static final String CLOSE = '</fields>';
    private static final String HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">\n';
    private static final String TAIL = '</CustomField>\n';
    private static final String INDENT = '    ';

    /**
     * @description Whether a zip path is an object file (objects/Account.object).
     * @param zipPath the Metadata API path
     * @return true for an object file
     */
    public static Boolean isObjectFile(String zipPath) {
        return zipPath != null && zipPath.startsWith('objects/') && zipPath.endsWith('.object') && zipPath.countMatches('/') == 1;
    }

    /**
     * @description A custom field's file below the source path.
     * @param key CustomField:Object.Field
     * @return objects/Object/fields/Field.field-meta.xml
     */
    public static List<String> pathsOf(String key) {
        String full = key.substringAfter(':');
        return new List<String>{ 'objects/' + full.substringBefore('.') + '/fields/' + full.substringAfter('.') + '.field-meta.xml' };
    }

    /**
     * @description The fields in an object file, each as its source-format file.
     * @param zipPath objects/Object.object
     * @param objectXml the file's text
     * @return the files by CustomField:Object.Field (path and right side set)
     */
    public static Map<String, RlyCompareFiles.FileDiff> fieldsOf(String zipPath, String objectXml) {
        Map<String, RlyCompareFiles.FileDiff> out = new Map<String, RlyCompareFiles.FileDiff>();
        String objectName = zipPath.substringAfter('/').removeEnd('.object');
        Integer at = objectXml == null ? -1 : objectXml.indexOf(OPEN);
        while (at >= 0) {
            Integer endAt = objectXml.indexOf(CLOSE, at);
            if (endAt < 0) {
                break;
            }
            String inner = objectXml.substring(at + OPEN.length(), endAt);
            String fieldName = inner.substringBetween('<fullName>', '</fullName>');
            if (String.isNotBlank(fieldName)) {
                String key = 'CustomField:' + objectName + '.' + fieldName.trim();
                RlyCompareFiles.FileDiff f = new RlyCompareFiles.FileDiff();
                f.path = pathsOf(key)[0];
                f.right = sourceText(inner);
                out.put(key, f);
            }
            at = objectXml.indexOf(OPEN, endAt);
        }
        return out;
    }

    // The field's lines one indent less, in a CustomField file.
    private static String sourceText(String inner) {
        List<String> lines = new List<String>();
        for (String line : inner.split('\n', -1)) {
            String l = line.removeEnd('\r');
            if (String.isNotBlank(l)) {
                lines.add(l.startsWith(INDENT) ? l.substring(INDENT.length()) : l);
            }
        }
        return HEAD + String.join(lines, '\n') + '\n' + TAIL;
    }
}
