/**
 * @description The History line for a conflict resolution (build 56, D22): what each file kept.
 */
public with sharing class RlyConflictSummary {

    /**
     * @description One line for History: what each file kept, for example "CustomLabels.labels-meta.xml kept the
     * release's version; Foo.cls kept sit's version".
     * @param resolveJson the resolve file built by resolveFile
     * @param targetBranch the target branch's name
     * @return the line
     */
    public static String of(String resolveJson, String targetBranch) {
        List<String> parts = new List<String>();
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(resolveJson);
        for (Object o : (List<Object>) root.get('resolutions')) {
            Map<String, Object> r = (Map<String, Object>) o;
            parts.add(String.valueOf(r.get('file')).substringAfterLast('/') + ' ' + choiceWords(String.valueOf(r.get('choice')), targetBranch));
        }
        return String.join(parts, '; ');
    }

    private static String choiceWords(String choice, String targetBranch) {
        if (choice == 'mine') {
            return 'kept the release\'s version';
        }
        return choice == 'theirs' ? 'kept ' + targetBranch + '\'s version' : 'edited by hand';
    }
}
