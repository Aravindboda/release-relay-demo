/** Helpers for rlyRepoMigration: the developer org listing and parts (as Sync status sends them), pills and short SHAs. */

/** Types listed (and sent) on their own: big lists or big files. */
const HEAVY_TYPES = ['CustomField', 'ListView', 'RecordType', 'CompactLayout', 'WebLink', 'ValidationRule', 'FieldSet', 'BusinessProcess',
    'CustomLabel', 'StaticResource', 'Profile', 'ContentAsset', 'Document', 'ExperienceBundle', 'ApexClass', 'Flow', 'Layout'];
const TYPES_PER_CALL = 10;
const KEYS_PER_PART = 25;
const ALONE = ['StaticResource', 'Profile', 'ContentAsset', 'Document', 'ExperienceBundle'];

/** The types in listing calls: heavy types alone, the rest TYPES_PER_CALL at a time. */
export function listTypeChunks(types) {
    const out = [];
    const light = [];
    (types || []).forEach((t) => {
        if (HEAVY_TYPES.includes(t)) {
            out.push([t]);
        } else {
            light.push(t);
        }
    });
    for (let i = 0; i < light.length; i += TYPES_PER_CALL) {
        out.push(light.slice(i, i + TYPES_PER_CALL));
    }
    return out;
}

/** The keys in parts to retrieve: static resources, profiles and documents alone, the rest KEYS_PER_PART at a time. */
export function partsOf(keys) {
    const out = [];
    let current = [];
    (keys || []).slice().sort().forEach((k) => {
        if (ALONE.includes(k.substring(0, k.indexOf(':')))) {
            out.push([k]);
            return;
        }
        if (current.length === KEYS_PER_PART) {
            out.push(current);
            current = [];
        }
        current.push(k);
    });
    if (current.length) {
        out.push(current);
    }
    return out;
}

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
