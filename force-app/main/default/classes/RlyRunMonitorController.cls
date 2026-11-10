/**
 * @description The Pipeline Monitor tab (rlyPipelineMonitor), read only, for every Release Relay user. Both methods are
 * imperative (not cacheable: the page reads again every 10 s while a run is going and every 30 s otherwise) and read
 * only records the hub keeps (RLY_Pipeline_Run__c, posted by the Git pipeline, and the releases and orgs); nothing calls
 * Git from here.
 *   readBoard  the repository picker, the tiles, the route's lanes, the active branches and the first page of runs
 *   readOlder  the next page of older finished runs (Load older runs)
 */
public with sharing class RlyRunMonitorController {

    /**
     * @description The board.
     * @param repository the repository picked (blank: the first Git connection's)
     * @return the board
     */
    @AuraEnabled
    public static RlyRunMonitorViews.Board readBoard(String repository) {
        try {
            return RlyRunMonitorBoard.read(repository);
        } catch (QueryException e) {
            throw new AuraHandledException('The pipeline runs couldn\'t be read: ' + e.getMessage());
        }
    }

    /**
     * @description Finished runs older than the oldest one shown.
     * @param repository the repository picked
     * @param startedBefore the oldest shown run's start (ISO 8601)
     * @param idBefore the oldest shown run's record
     * @return the page
     */
    @AuraEnabled
    public static RlyRunMonitorViews.OlderPage readOlder(String repository, String startedBefore, Id idBefore) {
        Datetime cursor = RlyRunMonitorInput.moment(startedBefore);
        if (cursor == null) {
            throw new AuraHandledException('Pick up from the oldest run shown: its start time is missing.');
        }
        return RlyRunMonitorBoard.older(repository, cursor, idBefore);
    }
}
