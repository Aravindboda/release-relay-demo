/**
 * @description Files on manual steps (RlyStepFiles) in the evidence: the PDF's Files table (evidenceRows: step files of
 * the release's own and carried steps first, then proof by org, then files removed, from History) and the Releases
 * CSV's Files column (csvFiles). Files are listed, not embedded; html is the PDF's section (after Manual steps).
 */
public with sharing class RlyStepFileEvidence {

    private static final String NO_ORG = '–';

    /**
     * @description The evidence document's Files table rows.
     * @param rel the release, with Id and Carried_Releases__c
     * @param events its History
     * @return rows of Step, File, Size, Attached by, When, Org for proof
     */
    public static List<List<String>> evidenceRows(RLY_Release__c rel, List<RLY_Release_Event__c> events) {
        List<RLY_Manual_Step__c> steps = RlyManualStepStore.stepsOf(new Set<Id>(RlyManualStepRuns.definersOf(rel)));
        List<RLY_Manual_Step_Run__c> runs = RlyStepFileStore.runsOfReleases(new Set<Id>{ rel.Id });
        Set<Id> ids = new Set<Id>(new Map<Id, RLY_Manual_Step__c>(steps).keySet());
        ids.addAll(new Map<Id, RLY_Manual_Step_Run__c>(runs).keySet());
        Map<Id, List<RlyStepFiles.FileRow>> files = RlyStepFileStore.rowsByRecord(ids);
        List<List<String>> rows = new List<List<String>>();
        for (RLY_Manual_Step__c s : steps) {
            rows.addAll(rowsOf(RlyStepFileStore.rowsOf(files, s.Id), s.Title__c, NO_ORG));
        }
        for (RLY_Manual_Step_Run__c r : runs) {
            rows.addAll(rowsOf(RlyStepFileStore.rowsOf(files, r.Id), r.Step__r.Title__c, r.Org__r.Name));
        }
        for (RLY_Release_Event__c e : events) {
            if (e.Event_Type__c == RlyStepFiles.EVENT_REMOVED) {
                rows.add(removedRow(e));
            }
        }
        return rows;
    }

    /**
     * @description The Files section of the evidence document (empty without files).
     * @param rows evidenceRows
     * @return the HTML
     */
    public static String html(List<List<String>> rows) {
        if (rows == null || rows.isEmpty()) {
            return '';
        }
        return RlyEvidenceTables.section('Files', new List<String>{ 'Step', 'File', 'Size', 'Attached by', 'When', 'Org for proof' }, rows);
    }

    private static List<List<String>> rowsOf(List<RlyStepFiles.FileRow> files, String stepTitle, String orgName) {
        List<List<String>> out = new List<List<String>>();
        for (RlyStepFiles.FileRow f : files) {
            out.add(new List<String>{ stepTitle, f.title, f.sizeText, f.createdBy, RlyEvidenceTables.stamp(f.createdOn), orgName });
        }
        return out;
    }

    // A file removed: its History line, "Removed", who and when.
    private static List<String> removedRow(RLY_Release_Event__c e) {
        return new List<String>{ '', e.Detail__c, 'Removed', e.Actor__r?.Name, RlyEvidenceTables.stamp(e.Occurred_On__c),
            e.Org__r == null ? NO_ORG : e.Org__r.Name };
    }

    /**
     * @description The Releases CSV's Files column per release: "usa-contacts.csv (48 KB, Load 240 USA contacts);
     * success-sit.csv (31 KB, proof in SIT)".
     * @param releases the releases, with Id and Carried_Releases__c
     * @return the text by release (missing means no files)
     */
    public static Map<Id, String> csvFiles(List<RLY_Release__c> releases) {
        Map<Id, List<Id>> definers = new Map<Id, List<Id>>();
        Set<Id> definerIds = new Set<Id>();
        for (RLY_Release__c r : releases) {
            definers.put(r.Id, RlyManualStepRuns.definersOf(r));
            definerIds.addAll(definers.get(r.Id));
        }
        Map<Id, List<RLY_Manual_Step__c>> stepsBy = stepsByRelease(definerIds.isEmpty() ? new List<RLY_Manual_Step__c>() : RlyManualStepStore.stepsOf(definerIds));
        List<RLY_Manual_Step_Run__c> runs = RlyStepFileStore.runsOfReleases(definers.keySet());
        Set<Id> ids = new Set<Id>(new Map<Id, RLY_Manual_Step_Run__c>(runs).keySet());
        for (List<RLY_Manual_Step__c> steps : stepsBy.values()) {
            ids.addAll(new Map<Id, RLY_Manual_Step__c>(steps).keySet());
        }
        Map<Id, List<RlyStepFiles.FileRow>> files = RlyStepFileStore.rowsByRecord(ids);
        Map<Id, List<String>> parts = new Map<Id, List<String>>();
        for (Id relId : definers.keySet()) {
            parts.put(relId, stepParts(definers.get(relId), stepsBy, files));
        }
        for (RLY_Manual_Step_Run__c r : runs) {
            parts.get(r.Release__c).addAll(csvParts(RlyStepFileStore.rowsOf(files, r.Id), 'proof in ' + r.Org__r.Name));
        }
        Map<Id, String> out = new Map<Id, String>();
        for (Id relId : parts.keySet()) {
            if (!parts.get(relId).isEmpty()) {
                out.put(relId, String.join(parts.get(relId), '; '));
            }
        }
        return out;
    }

    private static Map<Id, List<RLY_Manual_Step__c>> stepsByRelease(List<RLY_Manual_Step__c> steps) {
        Map<Id, List<RLY_Manual_Step__c>> out = new Map<Id, List<RLY_Manual_Step__c>>();
        for (RLY_Manual_Step__c s : steps) {
            if (!out.containsKey(s.Release__c)) {
                out.put(s.Release__c, new List<RLY_Manual_Step__c>());
            }
            out.get(s.Release__c).add(s);
        }
        return out;
    }

    // The step files of a release's definers, in order.
    private static List<String> stepParts(List<Id> definerIds, Map<Id, List<RLY_Manual_Step__c>> stepsBy, Map<Id, List<RlyStepFiles.FileRow>> files) {
        List<String> out = new List<String>();
        for (Id definer : definerIds) {
            for (RLY_Manual_Step__c s : stepsBy.containsKey(definer) ? stepsBy.get(definer) : new List<RLY_Manual_Step__c>()) {
                out.addAll(csvParts(RlyStepFileStore.rowsOf(files, s.Id), s.Title__c));
            }
        }
        return out;
    }

    private static List<String> csvParts(List<RlyStepFiles.FileRow> files, String place) {
        List<String> out = new List<String>();
        for (RlyStepFiles.FileRow f : files) {
            out.add(f.title + ' (' + f.sizeText + ', ' + place + ')');
        }
        return out;
    }
}
