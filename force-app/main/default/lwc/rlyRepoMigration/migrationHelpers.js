/** Helpers for rlyRepoMigration: pills and short SHAs (the developer org listing and parts are in c/rlyPartSending). */

/** The pill class of a status. */
export function pillOf(status) {
    const ok = ['In sync', 'Ready', 'Succeeded', 'Connected', 'Done'];
    const bad = ['Failed', 'Not ready', 'Differs'];
    const run = ['Running', 'Started', 'In progress'];
    if (ok.includes(status)) {
        return 'rr-pill rr-pill-ok';
    }
    if (bad.includes(status)) {
        return status === 'Differs' ? 'rr-pill rr-pill-warn' : 'rr-pill rr-pill-bad';
    }
    return run.includes(status) ? 'rr-pill rr-pill-run' : 'rr-pill rr-pill-none';
}

/** The first 7 characters of a commit. */
export function shortSha(sha) {
    return sha ? String(sha).substring(0, 7) : '—';
}

/** The wizard's steps. */
export const STEPS = [
    { n: 1, label: 'Current → New' },
    { n: 2, label: 'How' },
    { n: 3, label: 'Dry run' },
    { n: 4, label: 'Run' },
    { n: 5, label: 'New setup' },
    { n: 6, label: 'Orgs in sync' },
    { n: 7, label: 'Switch now' },
    { n: 8, label: 'Old setup' }
];

/** The providers a new connection can be on, with the grey hints. */
export const PROVIDERS = [
    { value: 'GitHub', label: 'GitHub', repo: 'owner/repository', cred: 'RLY_Git_GitHub', pipe: 'release-relay.yml' },
    { value: 'GitLab', label: 'GitLab', repo: 'group/project', cred: 'RLY_Git_GitLab', pipe: '.gitlab-ci.yml' },
    { value: 'Bitbucket', label: 'Bitbucket', repo: 'workspace/repository', cred: 'RLY_Git_Bitbucket', pipe: 'bitbucket-pipelines.yml' },
    { value: 'AzureDevOps', label: 'Azure DevOps', repo: 'organization/project/repository', cred: 'RLY_Git_AzureDevOps', pipe: 'azure-pipelines.yml' }
];
