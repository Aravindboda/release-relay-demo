/**
 * @description The Migration tab's checklists (build 46), each item with where to click in that provider and a Done
 * toggle chip whose mark (who, when) is kept on the migration: "Do in the new setup" for the new provider (pipeline
 * files, environments, the secrets and variables per environment, protected branches, the provider's own settings, the
 * Named Credential, Check) and "Do in the old setup" for the current one (the copy's token, the old pipeline, archive,
 * the old token). No SOQL, DML or callouts.
 */
public with sharing class RlyMigrationChecklist {

    /** @description The item that runs Update pipeline files. */
    public static final String ACTION_FILES = 'pipelineFiles';
    /** @description The item that runs Check on the new connection. */
    public static final String ACTION_CHECK = 'check';

    private static final Map<String, String> VARIABLES_AT = new Map<String, String>{
        'GitHub' => 'Settings → Secrets and variables → Actions (each environment\'s own, or Repository)',
        'GitLab' => 'Settings → CI/CD → Variables (Environment scope)',
        'Bitbucket' => 'Repository settings → Deployments (each environment) or Repository variables',
        'AzureDevOps' => 'Pipelines → Library → a variable group per environment' };
    private static final Map<String, String> ENVIRONMENTS_AT = new Map<String, String>{
        'GitHub' => 'Settings → Environments → New environment', 'GitLab' => 'Operate → Environments → New environment',
        'Bitbucket' => 'Repository settings → Deployments', 'AzureDevOps' => 'Pipelines → Environments → New environment' };
    private static final Map<String, String> PROTECT_AT = new Map<String, String>{
        'GitHub' => 'Settings → Rules → Rulesets (or Branches) → New branch ruleset',
        'GitLab' => 'Settings → Repository → Protected branches', 'Bitbucket' => 'Repository settings → Branch restrictions',
        'AzureDevOps' => 'Repos → Branches → ··· → Branch policies' };
    private static final Map<String, String> PIPELINE_OFF_AT = new Map<String, String>{
        'GitHub' => 'Actions → Release Relay → ··· → Disable workflow',
        'GitLab' => 'Settings → General → Visibility, project features, permissions → CI/CD off',
        'Bitbucket' => 'Repository settings → Pipelines → Settings → Enable Pipelines off',
        'AzureDevOps' => 'Pipelines → the pipeline → ··· → Settings → Disabled' };
    private static final Map<String, String> ARCHIVE_AT = new Map<String, String>{
        'GitHub' => 'Settings → General → Danger Zone → Archive this repository',
        'GitLab' => 'Settings → General → Advanced → Archive project',
        'Bitbucket' => 'Repository settings → User and group access: everyone Read',
        'AzureDevOps' => 'Project settings → Repositories → the repository → Disable repository' };
    private static final Map<String, String> TOKENS_AT = new Map<String, String>{
        'GitHub' => 'Settings → Developer settings → Personal access tokens (or the GitHub App)',
        'GitLab' => 'Settings → Access tokens', 'Bitbucket' => 'Repository settings → Access tokens',
        'AzureDevOps' => 'User settings → Personal access tokens' };

    /** @description One checklist item. */
    public class Item {
        /** @description Its key (kept on the migration). */
        @AuraEnabled public String key;
        /** @description What to do. */
        @AuraEnabled public String label;
        /** @description Where to click. */
        @AuraEnabled public String place;
        /** @description pipelineFiles or check: the hub does it from here. */
        @AuraEnabled public String action;
        /** @description Done. */
        @AuraEnabled public Boolean done = false;
        /** @description Who marked it. */
        @AuraEnabled public String who;
        /** @description When. */
        @AuraEnabled public Datetime stamp;
    }

    /** @description What the new setup list needs. */
    public class NewSetup {
        /** @description The new connection. */
        public RLY_Git_Connection__c target;
        /** @description The orgs' environments, each once. */
        public List<String> environments = new List<String>();
        /** @description The hub's (prod) branch. */
        public String prodBranch;
    }

    /**
     * @description Do in the new setup.
     * @param n the new connection, environments and prod branch
     * @param state the marks
     * @return the items
     */
    public static List<Item> newSetup(NewSetup n, RlyMigrationState state) {
        String p = n.target.Provider__c;
        String label = RlyMigrationMethods.labelOf(p);
        List<Item> out = new List<Item>{
            withAction(item('new.files', 'Update pipeline files (' + (String.isBlank(n.target.Pipeline__c) ? 'the pipeline file' : n.target.Pipeline__c.trim())
                + ' and scripts/release-relay.js) on ' + n.target.Pipeline_Branch__c, 'From here, after the copy'), ACTION_FILES),
            item('new.envs', 'Environments: ' + String.join(n.environments, ' · '), ENVIRONMENTS_AT.get(p))
        };
        for (RlyMigrationSecrets.Row r : RlyMigrationSecrets.rows(p, n.environments)) {
            out.add(item(r.key, r.scope + ': ' + r.names, VARIABLES_AT.get(p)));
        }
        out.add(item('new.protect', 'Protect ' + n.target.Pipeline_Branch__c + (String.isBlank(n.prodBranch) ? '' : ' and ' + n.prodBranch),
            PROTECT_AT.get(p)));
        out.addAll(providerItems(p));
        out.add(item('new.credential', 'The ' + label + ' token in Named Credential ' + n.target.Named_Credential__c
            + ', and principal access on your profile', 'Setup → Named Credentials → External Credentials → Principals · '
            + 'Setup → Profiles → External Credential Principal Access'));
        out.add(withAction(item('new.check', 'Check the new connection (repository, pipeline files, every org\'s branch)', 'From here'), ACTION_CHECK));
        return withMarks(out, state);
    }

    /**
     * @description Do in the old setup.
     * @param current the current connection
     * @param state the marks
     * @return the items
     */
    public static List<Item> oldSetup(RLY_Git_Connection__c current, RlyMigrationState state) {
        String p = current.Provider__c;
        return withMarks(new List<Item>{
            item('old.migrateToken', 'Delete RELAY_MIGRATE_TOKEN', VARIABLES_AT.get(p)),
            item('old.pipeline', 'Turn off the old pipeline so nobody runs it', PIPELINE_OFF_AT.get(p)),
            item('old.archive', 'After a waiting period, make the repository read-only (old releases keep linking to it: history and audit)',
                ARCHIVE_AT.get(p)),
            item('old.token', 'Revoke the old token once nothing uses it', TOKENS_AT.get(p))
        }, state);
    }

    /**
     * @description Where the copy's token goes in the current pipeline, and what the token needs in the new provider.
     * @param current the current connection
     * @param target the new connection
     * @return the hint
     */
    public static String tokenHint(RLY_Git_Connection__c current, RLY_Git_Connection__c target) {
        String needs = new Map<String, String>{
            'GitHub' => 'a fine-grained token with Contents and Workflows read and write on the new repository',
            'GitLab' => 'a project access token (Maintainer) with write_repository',
            'Bitbucket' => 'a repository access token with Repositories write',
            'AzureDevOps' => 'a personal access token with Code read and write' }.get(target == null ? '' : target.Provider__c);
        return 'Add RELAY_MIGRATE_TOKEN to the ' + RlyMigrationMethods.labelOf(current.Provider__c) + ' pipeline ('
            + VARIABLES_AT.get(current.Provider__c) + ', for all environments): ' + (needs == null ? 'a token that can push to the new repository' : needs)
            + '. Delete it after the move.';
    }

    // What only one provider needs.
    private static List<Item> providerItems(String p) {
        if (p == 'GitLab') {
            return new List<Item>{
                item('new.varRole', 'Minimum role to use pipeline variables: Maintainer', 'Settings → CI/CD → Variables'),
                item('new.runners', 'Instance runners on (on gitlab.com the account must be verified)', 'Settings → CI/CD → Runners'),
                item('new.schedules', 'Schedules: the nightly archive (MODE archive, 0 8 * * *) and Slack reminders (MODE slack, 17 * * * *), if used',
                    'Build → Pipeline schedules → New schedule, variable MODE') };
        }
        if (p == 'GitHub') {
            return new List<Item>{ item('new.actions', 'Actions allowed, workflow permissions Read and write',
                'Settings → Actions → General') };
        }
        if (p == 'Bitbucket') {
            return new List<Item>{ item('new.pipelines', 'Pipelines on', 'Repository settings → Pipelines → Settings') };
        }
        return new List<Item>{ item('new.pipelineDef', 'A pipeline from azure-pipelines.yml', 'Pipelines → New pipeline → Azure Repos Git') };
    }

    private static List<Item> withMarks(List<Item> items, RlyMigrationState state) {
        for (Item i : items) {
            RlyMigrationState.Mark m = state.marks.get(i.key);
            if (m != null) {
                i.done = m.done == true;
                i.who = m.who;
                i.stamp = m.stamp;
            }
        }
        return items;
    }

    private static Item item(String key, String label, String place) {
        Item i = new Item();
        i.key = key;
        i.label = label;
        i.place = place;
        return i;
    }

    private static Item withAction(Item i, String action) {
        i.action = action;
        return i;
    }
}
