/**
 * @description The rules for resolving a release's conflicts with its target: the release is 'Checks failed' with a
 * Conflict validation result and an open pull request; every conflicting file gets one choice (mine, theirs or
 * edit); an edit has the whole file and no conflict markers left; a file too long to show in full can't be edited
 * here. Builds the resolve file the hub commits for the pipeline.
 */
public with sharing class RlyConflictRules {

    private static final Set<String> CHOICES = new Set<String>{ 'mine', 'theirs', 'edit' };
    private static final List<String> MARKERS = new List<String>{ '<<<<<<<', '>>>>>>>' };

    /** @description One file's resolution, as the page sends it. */
    public class Resolution {
        /** @description Path of the conflicting file. */
        public String file;
        /** @description mine, theirs or edit. */
        public String choice;
        /** @description The full file text, for edit only. */
        public String content;
    }

    /** @description What the page sends: one resolution per conflicting file. */
    public class ResolveRequest {
        /** @description The resolutions. */
        public List<Resolution> resolutions;
    }

    /**
     * @description Checks the release can be resolved and the resolutions are complete and valid.
     * @param rel the release, with its status, validation result and pull request
     * @param requestJson a ResolveRequest as JSON
     * @return the resolve file's JSON, {"resolutions":[{"file","choice","content" (edit only)}]}
     */
    public static String resolveFile(RLY_Release__c rel, String requestJson) {
        Map<String, Map<String, Object>> files = conflictingFiles(rel);
        Map<String, Resolution> byFile = byFile(read(requestJson), files);
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (String path : files.keySet()) {
            if (!byFile.containsKey(path)) {
                throw new RlyReleaseException('Choose how to resolve ' + path + ': every conflicting file needs a choice.');
            }
            out.add(entry(byFile.get(path)));
        }
        return JSON.serialize(new Map<String, Object>{ 'resolutions' => out });
    }

    private static Map<String, Map<String, Object>> conflictingFiles(RLY_Release__c rel) {
        Map<String, Map<String, Object>> files = RlyConflictResult.filesOf(rel.Validation_Result__c);
        if (rel.Status__c != 'Checks failed' || rel.PR_Number__c == null || files.isEmpty()) {
            throw new RlyReleaseException('Only a release whose validation found conflicts, with its pull request open, can resolve them.');
        }
        return files;
    }

    private static List<Resolution> read(String requestJson) {
        ResolveRequest req;
        try {
            req = (ResolveRequest) JSON.deserialize(requestJson, ResolveRequest.class);
        } catch (Exception e) {
            throw new RlyReleaseException('The resolutions couldn\'t be read.');
        }
        return req == null || req.resolutions == null ? new List<Resolution>() : req.resolutions;
    }

    // Each resolution checked, by file; a file that isn't conflicting, or comes twice, is refused.
    private static Map<String, Resolution> byFile(List<Resolution> resolutions, Map<String, Map<String, Object>> files) {
        Map<String, Resolution> out = new Map<String, Resolution>();
        for (Resolution r : resolutions) {
            if (r == null || r.file == null || !files.containsKey(r.file) || out.containsKey(r.file)) {
                throw new RlyReleaseException((r == null ? 'A file' : String.valueOf(r.file)) + ' isn\'t one of the conflicting files, or comes twice.');
            }
            checkChoice(r, files.get(r.file));
            out.put(r.file, r);
        }
        return out;
    }

    private static void checkChoice(Resolution r, Map<String, Object> conflict) {
        if (!CHOICES.contains(r.choice)) {
            throw new RlyReleaseException('Choose Keep mine, Keep the target\'s or Edit for ' + r.file + '.');
        }
        if (r.choice == 'edit') {
            checkEdit(r, conflict);
        }
    }

    private static void checkEdit(Resolution r, Map<String, Object> conflict) {
        if (conflict.get('truncated') == true) {
            throw new RlyReleaseException(r.file + ' is too long to edit here: keep yours or the target\'s, or fix it on the release branch.');
        }
        if (String.isBlank(r.content)) {
            throw new RlyReleaseException('The edited ' + r.file + ' is empty.');
        }
        for (String marker : MARKERS) {
            if (r.content.contains(marker)) {
                throw new RlyReleaseException('The edited ' + r.file + ' still has conflict markers (' + marker
                    + '): remove them and keep the lines you want.');
            }
        }
    }

    private static Map<String, Object> entry(Resolution r) {
        Map<String, Object> e = new Map<String, Object>{ 'file' => r.file, 'choice' => r.choice };
        if (r.choice == 'edit') {
            e.put('content', r.content);
        }
        return e;
    }
}
