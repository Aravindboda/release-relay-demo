/**
 * @description The Data view of the Sync status tab (rlyDataSync): data sets (admins edit them) and their runs, a dry
 * run first and a load after (RlyDataRuns, RlyDataRules, RlyDataResult). Every call needs the production hub.
 */
public with sharing class RlyDataController {

    /** @description A data set as the page sends it. */
    private class SetInput {
        /** @description The record (blank: a new set). */
        public String id;
        /** @description Its title. */
        public String title;
        /** @description What it's for. */
        public String description;
        /** @description The definition JSON. */
        public String definition;
    }

    /**
     * @description The data sets, orgs and latest runs.
     * @return the board
     */
    @AuraEnabled
    public static RlyDataBoard.Board board() {
        try {
            RlyHubGuard.requireHub();
            return RlyDataBoard.read();
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Saves a data set (admins).
     * @param setJson {id, title, description, definition}
     * @return the set's Id
     */
    @AuraEnabled
    public static Id saveSet(String setJson) {
        try {
            RlyHubGuard.requireHub();
            requireAdmin();
            RLY_Data_Set__c row = setOf(setJson);
            return RlyDataStore.saveSet(row);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Deletes a data set (admins); its runs keep their history.
     * @param setId the set
     */
    @AuraEnabled
    public static void removeSet(Id setId) {
        try {
            RlyHubGuard.requireHub();
            requireAdmin();
            RlyDataStore.deleteSet(setId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Starts a run: the dry run, or the export from a developer org first.
     * @param requestJson {dataSetId, sourceOrgId, targetOrgId, direction, mask, releaseName}
     * @return the run
     */
    @AuraEnabled
    public static RlyDataRuns.Started startRun(String requestJson) {
        try {
            RlyHubGuard.requireHub();
            RlyDataRuns.Request req = String.isBlank(requestJson) ? null : (RlyDataRuns.Request) JSON.deserialize(requestJson, RlyDataRuns.Request.class);
            return RlyDataRuns.start(req);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Sends one page of a developer org's records.
     * @param partJson {runId, index, page, cursor}
     * @return the page
     */
    @AuraEnabled
    public static RlyDataExport.Part exportPart(String partJson) {
        try {
            RlyHubGuard.requireHub();
            RlyDataExport.Page p = String.isBlank(partJson) ? null : (RlyDataExport.Page) JSON.deserialize(partJson, RlyDataExport.Page.class);
            return RlyDataExport.send(p);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Starts the dry run once every page is sent.
     * @param runId the run
     * @return the run's title
     */
    @AuraEnabled
    public static String runExported(String runId) {
        try {
            RlyHubGuard.requireHub();
            return RlyDataRuns.runExported(runId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Reads a run (and moves it on when its result is there).
     * @param runId the run
     * @return the run
     */
    @AuraEnabled
    public static RlyDataResult.View readRun(String runId) {
        try {
            RlyHubGuard.requireHub();
            return RlyDataResult.read(runId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Loads a run's records (approver for Up, admin for Down and Refill).
     * @param runId the run
     * @return the run's title
     */
    @AuraEnabled
    public static String loadRun(String runId) {
        try {
            RlyHubGuard.requireHub();
            return RlyDataRuns.load(runId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    // The page's set as a record, checked: a title and a usable definition.
    private static RLY_Data_Set__c setOf(String setJson) {
        SetInput input = String.isBlank(setJson) ? new SetInput() : (SetInput) JSON.deserialize(setJson, SetInput.class);
        String title = String.isBlank(input.title) ? '' : input.title.normalizeSpace();
        if (String.isBlank(title) || title.length() > 80) {
            throw new RlyReleaseException('Give the data set a title (up to 80 characters).');
        }
        RlyDataSet.parse(input.definition);
        return new RLY_Data_Set__c(Id = String.isBlank(input.id) ? null : Id.valueOf(input.id), Title__c = title,
            Definition__c = input.definition, Description__c = input.description == null ? null : input.description.left(4000));
    }

    private static void requireAdmin() {
        if (!RlyOrgController.isAdmin()) {
            throw new RlyReleaseException('Data sets are edited by Release Relay admins.');
        }
    }

    private static AuraHandledException handled(Exception e) {
        String message = e instanceof RlyReleaseException ? e.getMessage() : 'Something went wrong: ' + e.getMessage();
        AuraHandledException a = new AuraHandledException(message);
        a.setMessage(message);
        return a;
    }
}
