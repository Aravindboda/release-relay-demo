/**
 * @description The secrets and variables to enter again in the new provider (build 46). Values can never be read back
 * out of a provider, so the Migration tab lists the names per environment: the sign-in each org's environment needs, the
 * shared keystore (and GitLab's push token) for all environments, and any other name the new provider's pipeline file
 * reads, as optional. No SOQL, DML or callouts.
 */
public with sharing class RlyMigrationSecrets {

    private static final List<String> ENV_SECRETS = new List<String>{ 'SF_CLIENT_ID', 'SF_USERNAME' };
    private static final List<String> ENV_VARIABLES = new List<String>{ 'SF_INSTANCE_URL', 'SF_JKS_ALIAS', 'ORG_LABEL' };
    private static final List<String> SHARED_SECRETS = new List<String>{ 'SF_JKS', 'SF_JKS_PASSWORD' };
    private static final Pattern NAME_PATTERN = Pattern.compile('(?:secrets\\.|vars\\.|\\$\\{?)([A-Z][A-Z0-9_]{2,})');
    /** @description Names a pipeline reads that nobody enters: the run's inputs and the CI system's own. */
    private static final Set<String> NOT_ENTERED = new Set<String>{ 'MODE', 'REQUEST_ID', 'ENVIRONMENT', 'TARGET_ENVIRONMENT',
        'BRANCH', 'TARGET', 'TITLE', 'OPTIONS', 'COMPONENTS', 'DELETIONS', 'PATH', 'HOME', 'STEP', 'RELAY_RUN_NAME', 'RELAY_NO_ORG',
        'RELAY_PROVIDER', 'GIT_DEPTH', 'NEEDS_JSON', 'MONITOR_STATUS', 'GH_TOKEN', 'RELAY_MIGRATE_TOKEN' };
    private static final List<String> NOT_ENTERED_PREFIXES = new List<String>{ 'CI_', 'GITHUB_', 'RUNNER_', 'BITBUCKET_', 'BUILD_', 'SYSTEM_', 'AGENT_' };

    /** @description One row of the checklist: the names one scope needs. */
    public class Row {
        /** @description The checklist key (sec:dev1, sec:*). */
        public String key;
        /** @description The environment, or All environments. */
        public String scope;
        /** @description The names, in words: secrets … · variables …. */
        public String names;
    }

    /**
     * @description The rows: one per environment, then the names for all environments.
     * @param provider the new provider
     * @param environments the orgs' environments (each once)
     * @return the rows
     */
    public static List<Row> rows(String provider, List<String> environments) {
        List<Row> out = new List<Row>();
        for (String e : environments) {
            out.add(row('sec:' + e, e, 'secrets ' + String.join(ENV_SECRETS, ', ') + ' · variables ' + String.join(ENV_VARIABLES, ', ')));
        }
        out.add(row('sec:*', 'All environments', 'secrets ' + String.join(shared(provider), ', ')));
        return out;
    }

    /**
     * @description The other names the new provider's pipeline file reads (enter them only when the old setup has them).
     * @param provider the new provider
     * @param pipelineText the packaged pipeline file
     * @return the names, comma separated, or blank
     */
    public static String optionalNames(String provider, String pipelineText) {
        Set<String> known = new Set<String>(ENV_SECRETS);
        known.addAll(ENV_VARIABLES);
        known.addAll(shared(provider));
        List<String> out = new List<String>();
        Matcher m = NAME_PATTERN.matcher(pipelineText == null ? '' : pipelineText);
        while (m.find()) {
            String name = m.group(1);
            if (!known.contains(name) && !out.contains(name) && entered(name)) {
                out.add(name);
            }
        }
        out.sort();
        return String.join(out, ', ');
    }

    /**
     * @description The packaged pipeline file of a provider.
     * @param provider GitHub, GitLab, Bitbucket or AzureDevOps
     * @return the static resource's name
     */
    public static String resourceOf(String provider) {
        return new Map<String, String>{ 'GitHub' => 'RLY_Pipeline_GitHub', 'GitLab' => 'RLY_Pipeline_GitLab',
            'Bitbucket' => 'RLY_Pipeline_Bitbucket', 'AzureDevOps' => 'RLY_Pipeline_Azure' }.get(provider);
    }

    // GitLab jobs push with a project access token of their own (RELAY_TOKEN).
    private static List<String> shared(String provider) {
        List<String> out = new List<String>(SHARED_SECRETS);
        if (provider == 'GitLab') {
            out.add('RELAY_TOKEN');
        }
        return out;
    }

    private static Boolean entered(String name) {
        if (NOT_ENTERED.contains(name)) {
            return false;
        }
        for (String prefix : NOT_ENTERED_PREFIXES) {
            if (name.startsWith(prefix)) {
                return false;
            }
        }
        return true;
    }

    private static Row row(String key, String scope, String names) {
        Row r = new Row();
        r.key = key;
        r.scope = scope;
        r.names = names;
        return r;
    }
}
