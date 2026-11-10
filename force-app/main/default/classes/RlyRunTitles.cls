/**
 * @description Matches a pipeline run's name to the title the hub looks for (build 44). From pipeline version 25 a run's
 * name keeps the hub's title ("Release Relay REL-1 (hub)") and may add " · <release title>" and " · by <name>", so a run
 * matches when its name is the title or starts with the title and " · ". Build 45: GitLab pipelines' names (the CI file's
 * workflow:name, version 25) have the same shape, without " · by <name>". No SOQL, DML or callouts.
 */
public with sharing class RlyRunTitles {

    /** @description What separates the hub's title from the parts version 25 adds. */
    public static final String SEPARATOR = ' · ';

    /**
     * @description Whether a run's name stands for the title.
     * @param runName the run's display title
     * @param title the title the hub looks for
     * @return true when equal, or when the name starts with the title and the separator
     */
    public static Boolean matches(String runName, String title) {
        if (runName == null || String.isBlank(title)) {
            return false;
        }
        return runName == title || runName.startsWith(title + SEPARATOR);
    }
}
