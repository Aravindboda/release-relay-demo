/**
 * @description How a repository moves to another provider (build 46), only what works for the pair:
 *   lift      lift and shift: the migrate job copies every branch, tag and commit into an EMPTY new repository;
 *   importer  the new provider's own importer (GitLab, Azure Repos, Bitbucket), done by hand with the clicks shown,
 *             then verified by the migrate job (heads match on every branch and tag); also a copy made another way;
 *   fresh     fresh start: each Release Relay branch seeded with the current latest files, one commit, no history.
 * The migrate job runs in the current pipeline, which needs the pipeline files v26 on GitHub or GitLab. No SOQL, DML or
 * callouts.
 */
public with sharing class RlyMigrationMethods {

    /** @description Lift and shift. */
    public static final String LIFT = 'lift';
    /** @description The provider's own importer, then verify. */
    public static final String IMPORTER = 'importer';
    /** @description Fresh start. */
    public static final String FRESH = 'fresh';

    private static final Set<String> RUNS_MIGRATE = new Set<String>{ 'GitHub', 'GitLab' };

    /** @description One method as the page shows it. */
    public class Method {
        /** @description lift, importer or fresh. */
        @AuraEnabled public String key;
        /** @description Its name. */
        @AuraEnabled public String label;
        /** @description What it does. */
        @AuraEnabled public String summary;
        /** @description What's good about it. */
        @AuraEnabled public String pros;
        /** @description What it costs. */
        @AuraEnabled public String cons;
        /** @description It works for this pair now. */
        @AuraEnabled public Boolean possible = true;
        /** @description Why not, or what it needs. */
        @AuraEnabled public String why;
        /** @description The clicks in the new provider (importer). */
        @AuraEnabled public List<String> clicks = new List<String>();
    }

    /**
     * @description The methods for a pair.
     * @param current the current connection
     * @param target the new connection
     * @param targetBranches how many branches the new repository holds (null: not checked yet)
     * @return lift, importer and fresh, each possible or not
     */
    public static List<Method> forPair(RLY_Git_Connection__c current, RLY_Git_Connection__c target, Integer targetBranches) {
        String fromProvider = current == null ? '' : current.Provider__c;
        String to = target == null ? '' : target.Provider__c;
        String noJob = RUNS_MIGRATE.contains(fromProvider) ? null
            : 'The copy runs in the current pipeline, and ' + labelOf(fromProvider) + ' pipeline files have no migrate job yet.';
        String notEmpty = targetBranches != null && targetBranches > 0
            ? 'The new repository already holds ' + targetBranches + ' branch(es): this needs an empty one.' : null;
        List<Method> out = new List<Method>{ lift(noJob, notEmpty), importer(current, target, noJob), fresh(noJob, notEmpty) };
        if (String.isBlank(to)) {
            for (Method m : out) {
                m.possible = false;
                m.why = 'Configure the new connection first.';
            }
        }
        return out;
    }

    /**
     * @description The migrate job's method for a picked one.
     * @param method lift, importer or fresh
     * @return lift, verify or fresh
     */
    public static String jobMethod(String method) {
        return method == IMPORTER ? 'verify' : (method == FRESH ? FRESH : LIFT);
    }

    private static Method lift(String noJob, String notEmpty) {
        Method m = method(LIFT, 'Lift and shift', new List<String>{
            'The migrate job in the current pipeline copies every branch, tag and commit into the new repository.',
            'All history, one click, checked ref by ref afterwards.',
            'The new repository must be empty; a big repository takes longer.' });
        return blocked(m, noJob == null ? notEmpty : noJob);
    }

    private static Method fresh(String noJob, String notEmpty) {
        Method m = method(FRESH, 'Fresh start', new List<String>{
            'Each Release Relay branch (the pipeline branch, each org\'s branch, prod, results and snapshots) gets the current '
            + 'repository\'s latest files only: one commit per branch.',
            'A clean, small repository.',
            'No history in the new repository: it stays in the old one, where old releases keep linking.' });
        return blocked(m, noJob == null ? notEmpty : noJob);
    }

    private static Method importer(RLY_Git_Connection__c current, RLY_Git_Connection__c target, String noJob) {
        String to = target == null ? '' : target.Provider__c;
        String fromLabel = current == null ? '' : labelOf(current.Provider__c);
        String source = current == null ? '' : current.Repository__c;
        Method m = method(IMPORTER, labelOf(to) + '\'s own importer', new List<String>{
            'You import the repository in ' + labelOf(to) + ' with the clicks below; then the hub verifies that every '
            + 'branch and tag matches (nothing is pushed).',
            'The provider does the copy; it also fits a repository that already holds the content.',
            'Done by hand in ' + labelOf(to) + '; anything changed in ' + fromLabel + ' since the import shows as a difference.' });
        m.clicks = clicks(current, to, source);
        if (m.clicks.isEmpty()) {
            m.label = 'Verify a copy you made';
            m.summary = labelOf(to) + ' has no importer the hub can guide for ' + fromLabel + '. If you copied the '
                + 'repository another way (for example git clone --mirror, then git push --mirror), the hub verifies it.';
        }
        return blocked(m, noJob);
    }

    private static List<String> clicks(RLY_Git_Connection__c current, String to, String source) {
        String fromProvider = current == null ? '' : current.Provider__c;
        String cloneUrl = current == null ? '' : RlyMigrationRepo.pushUrl(RlyGit.forConnection(current));
        if (to == 'GitLab') {
            return gitLabClicks(fromProvider, source, cloneUrl);
        }
        if (to == 'AzureDevOps') {
            return new List<String>{ 'In Azure DevOps: Repos → the repository list → Import repository.',
                'Clone URL: ' + cloneUrl + '. Tick Requires authentication and give a user name and a token that can read it.',
                'Name the repository as in the new connection, then Import.' };
        }
        if (to == RlyGit.BITBUCKET) {
            return new List<String>{ 'In Bitbucket: Create → Import repository.',
                'URL: ' + cloneUrl + '. Tick Requires authorization and give a user name and a token that can read it.',
                'Pick the workspace, project and repository name as in the new connection, then Import repository.' };
        }
        return new List<String>();
    }

    // GitLab's importers: GitHub and Bitbucket Cloud have their own; any other repository by its URL.
    private static List<String> gitLabClicks(String fromProvider, String source, String cloneUrl) {
        if (fromProvider == 'GitHub') {
            return new List<String>{ 'In GitLab: New project → Import project → GitHub.',
                'Authorize with GitHub (or paste a GitHub token that can read ' + source + ').',
                'Find ' + source + ', pick the target group and project name, then Import.',
                'Wait until the status says Complete, then come back and run the verify.' };
        }
        if (fromProvider == RlyGit.BITBUCKET) {
            return new List<String>{ 'In GitLab: New project → Import project → Bitbucket Cloud.',
                'Authorize with Bitbucket, find ' + source + ', pick the target group, then Import.' };
        }
        return new List<String>{ 'In GitLab: New project → Import project → Repository by URL.',
            'Git repository URL: ' + cloneUrl + ', with a user name and a token that can read it.',
            'Pick the group and project name, then Create project.' };
    }

    // texts: summary, pros, cons
    private static Method method(String key, String label, List<String> texts) {
        Method m = new Method();
        m.key = key;
        m.label = label;
        m.summary = texts[0];
        m.pros = texts[1];
        m.cons = texts[2];
        return m;
    }

    /**
     * @description A provider's name for people.
     * @param provider GitHub, GitLab, Bitbucket or AzureDevOps
     * @return for example Azure DevOps
     */
    public static String labelOf(String provider) {
        return provider == 'AzureDevOps' ? 'Azure DevOps' : (provider == null ? '' : provider);
    }

    private static Method blocked(Method m, String why) {
        if (why != null) {
            m.possible = false;
            m.why = why;
        }
        return m;
    }
}
