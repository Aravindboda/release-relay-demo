/**
 * @description Checks the details of the Git connection before it's saved. Each problem is a sentence
 * (without the full stop) the page shows.
 */
public with sharing class RlyGitValidator {

    private static final Pattern NAME_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');
    private static final Pattern REF_PATTERN = Pattern.compile('^[A-Za-z0-9._/-]{1,100}$');
    private static final Pattern PATH_PATTERN = Pattern.compile('^[A-Za-z0-9_./-]{1,200}$');
    private static final Pattern PIPELINE_PATTERN = Pattern.compile('^[A-Za-z0-9_./-]{1,120}$');

    /**
     * @description Every problem with the connection's details; when the fields are fine, also the provider's
     * own check of the repository's shape.
     * @param g the details sent
     * @return the problems (empty when all is well)
     */
    public static List<String> validate(RLY_Git_Connection__c g) {
        List<String> problems = repositoryProblems(g);
        problems.addAll(pipelineProblems(g));
        if (problems.isEmpty()) {
            try {
                RlyGit.forConnection(g);
            } catch (RlyGit.GitException e) {
                problems.add(e.getMessage().removeEnd('.'));
            }
        }
        return problems;
    }

    private static List<String> repositoryProblems(RLY_Git_Connection__c g) {
        List<String> problems = new List<String>();
        if (!RlyGit.PROVIDERS.contains(g.Provider__c)) {
            problems.add('Pick a provider: GitHub, GitLab, Bitbucket or Azure DevOps');
        }
        if (String.isBlank(g.Repository__c) || g.Repository__c.trim().length() > 255) {
            problems.add('Repository is required');
        }
        if (!matches(g.Named_Credential__c, NAME_PATTERN)) {
            problems.add('Named Credential must be the API name of a Named Credential, for example RLY_GitHub');
        }
        return problems;
    }

    private static List<String> pipelineProblems(RLY_Git_Connection__c g) {
        List<String> problems = new List<String>();
        if (g.Provider__c != RlyGit.BITBUCKET && !matches(g.Pipeline__c, PIPELINE_PATTERN)) {
            problems.add('Pipeline is required: the workflow file, CI file or pipeline id');
        }
        if (!matches(g.Pipeline_Branch__c, REF_PATTERN)) {
            problems.add('Pipeline branch is required, for example main');
        }
        if (!matches(g.Source_Path__c, PATH_PATTERN) || g.Source_Path__c.contains('..')) {
            problems.add('Source path must be a folder such as force-app/main/default');
        }
        return problems;
    }

    private static Boolean matches(String value, Pattern p) {
        return String.isNotBlank(value) && p.matcher(value.trim()).matches();
    }
}
