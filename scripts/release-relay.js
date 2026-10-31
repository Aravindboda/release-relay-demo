#!/usr/bin/env node
// Release Relay pipeline files: version 8
/*
 * Release Relay: one script for every pipeline job, on GitHub, GitLab, Bitbucket or Azure DevOps.
 *
 *   STEP=raise     MODE=org: retrieve COMPONENTS from the source org, remove DELETIONS, write a
 *                  destructive manifest, commit to a new BRANCH from TARGET, push, open a PR/MR.
 *                  MODE=branch: open a PR/MR from an existing BRANCH into TARGET.
 *                  MODE=promote: make BRANCH (promote/rel-...) from TARGET, cherry-pick the merge
 *                  commits listed in COMPONENTS (oldest first) from the previous stage, push,
 *                  open a PR/MR into TARGET.
 *                  MODE=hub: the Release Relay hub already retrieved the components from the
 *                  developer org and committed the Metadata API zip to BRANCH as
 *                  .relay-inbox/<REQUEST_ID>.zip. Convert it to source format, replace the zip
 *                  with the files, push, open a PR/MR into TARGET. No org login is needed.
 *                  MODE=resolve: merge TARGET into BRANCH, applying the choices the hub committed in
 *                  .relay-inbox/<REQUEST_ID>-resolve.json for each conflicted file, then push.
 *   STEP=scan      Salesforce Code Analyzer on the files the PR/MR changes.
 *   STEP=validate  Check-only deployment of the PR/MR's changes to the target org.
 *   STEP=merge     Merge the PR/MR approved in Salesforce.
 *   STEP=deploy    Deploy the merged changes (and deletions) to the target org.
 *   STEP=auto      Run the steps MODE needs, in order (GitLab and Bitbucket use one job).
 *   STEP=notify    Tell the Salesforce org that raised the release to read the results now
 *                  (POST /services/apexrest/release-relay/v1/status). Never fails the run.
 *
 * RELAY_PROVIDER: github, gitlab, bitbucket or azure.
 * Each org's login is read as PREFIX_NAME first (DEV_SF_USERNAME, prefix from the org's
 * environment name), then NAME, so one job can hold the logins of both orgs.
 * scan, validate, merge and deploy write results/<REQUEST_ID>/<step>.json to the
 * release-relay-results branch, where Salesforce reads them.
 *
 * OPTIONS (JSON from Salesforce): {"hub":true} means the hub checked the route, so ALLOWED_TARGETS
 * isn't needed; {"tests":["AccountServiceTest"]} runs those tests (RunSpecifiedTests) when
 * validating and deploying, and {"tests":[]} means no Apex, so no tests run (NoTestRun).
 * {"validateMerged":true} validates BRANCH merged with TARGET (conflicts are reported, not guessed);
 * {"syncBranches":["dev1"]} merges TARGET into those branches after a merge, so every developer org's
 * branch starts from the latest stage.
 *
 * Every input arrives as an environment variable and is validated here. Commands run with
 * execFileSync and argument arrays, never through a shell, so input can't inject commands.
 */
'use strict';

const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const env = process.env;
const BRANCH_RE = /^(feature|bugfix|hotfix|promote)\/[a-z0-9._-]{1,100}$/;
const REF_RE = /^[A-Za-z0-9._/-]{1,100}$/;
const ITEM_RE = /^([A-Za-z]{2,80}):([^,:\r\n]{1,255})$/;


// Repo layout per metadata type, relative to SOURCE_PATH.
const FILE_TYPES = {
    ApexClass: ['classes', '.cls'],
    ApexTrigger: ['triggers', '.trigger'],
    ApexPage: ['pages', '.page'],
    ApexComponent: ['components', '.component'],
    Flow: ['flows', '.flow-meta.xml'],
    Layout: ['layouts', '.layout-meta.xml'],
    FlexiPage: ['flexipages', '.flexipage-meta.xml'],
    PermissionSet: ['permissionsets', '.permissionset-meta.xml'],
    CustomMetadata: ['customMetadata', '.md-meta.xml'],
    CustomTab: ['tabs', '.tab-meta.xml'],
    QuickAction: ['quickActions', '.quickAction-meta.xml']
};
const FOLDER_TYPES = { LightningComponentBundle: 'lwc', AuraDefinitionBundle: 'aura', CustomObject: 'objects' };
const CHILD_TYPES = {
    CustomField: ['fields', '.field-meta.xml'],
    ValidationRule: ['validationRules', '.validationRule-meta.xml'],
    RecordType: ['recordTypes', '.recordType-meta.xml'],
    ListView: ['listViews', '.listView-meta.xml']
};

function run(cmd, args, options = {}) {
    const out = execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'], ...options });
    return out == null ? '' : String(out).trim();
}

function summary(markdown) {
    if (env.GITHUB_STEP_SUMMARY) {
        fs.appendFileSync(env.GITHUB_STEP_SUMMARY, markdown + '\n');
    } else {
        console.log(markdown);
    }
}

function fail(message) {
    console.error('::error::' + message);
    summary('**Release Relay failed:** ' + message);
    process.exit(1);
}

function parseList(value, label) {
    return (value || '').split(',').map((s) => s.trim()).filter(Boolean).map((entry) => {
        const m = ITEM_RE.exec(entry);
        if (!m) {
            fail(`${label} entry "${entry}" isn't Type:Name.`);
        }
        return { type: m[1], name: m[2].trim(), entry };
    });
}

/** Repo paths for one component, or [] when the type isn't supported for deletion. */
function pathsFor(sourcePath, type, name) {
    if (FILE_TYPES[type]) {
        const [folder, suffix] = FILE_TYPES[type];
        const main = path.join(sourcePath, folder, name + suffix);
        return suffix.endsWith('-meta.xml') ? [main] : [main, main + '-meta.xml'];
    }
    if (FOLDER_TYPES[type]) {
        return [path.join(sourcePath, FOLDER_TYPES[type], name)];
    }
    if (CHILD_TYPES[type]) {
        const dot = name.indexOf('.');
        if (dot < 1) {
            fail(`${type} "${name}" must be written as Object.Name.`);
        }
        const [folder, suffix] = CHILD_TYPES[type];
        return [path.join(sourcePath, 'objects', name.slice(0, dot), folder, name.slice(dot + 1) + suffix)];
    }
    if (type === 'StaticResource') {
        const dir = path.join(sourcePath, 'staticresources');
        if (!fs.existsSync(dir)) {
            return [];
        }
        return fs.readdirSync(dir).filter((f) => f === name || f.startsWith(name + '.')).map((f) => path.join(dir, f));
    }
    if (type === 'EmailTemplate') {
        const main = path.join(sourcePath, 'email', name + '.email');
        return [main, main + '-meta.xml'];
    }
    return null;
}

function xmlEscape(value) {
    return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function manifest(apiVersion, items) {
    const byType = {};
    items.forEach((i) => { (byType[i.type] = byType[i.type] || []).push(i.name); });
    const types = Object.keys(byType).sort().map((t) =>
        '    <types>\n'
        + byType[t].sort().map((n) => `        <members>${xmlEscape(n)}</members>\n`).join('')
        + `        <name>${t}</name>\n    </types>\n`).join('');
    return '<?xml version="1.0" encoding="UTF-8"?>\n<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n'
        + types + `    <version>${apiVersion}</version>\n</Package>\n`;
}

/**
 * Writes the JWT signing key. Either SF_JKS (a keystore exported from Salesforce Certificate
 * and Key Management, base64 encoded) with SF_JKS_PASSWORD and SF_JKS_ALIAS, or SF_JWT_KEY
 * (a base64 PEM private key).
 */
function writePrivateKey(keyFile) {
    if (v('SF_JKS')) {
        if (!v('SF_JKS_PASSWORD') || !v('SF_JKS_ALIAS')) {
            fail('SF_JKS is set, so SF_JKS_PASSWORD (secret) and SF_JKS_ALIAS (variable) are needed too.');
        }
        const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-'));
        const jks = path.join(dir, 'store.jks');
        const p12 = path.join(dir, 'store.p12');
        fs.writeFileSync(jks, Buffer.from(v('SF_JKS'), 'base64'), { mode: 0o600 });
        const childEnv = { ...process.env, RELAY_PW: v('SF_JKS_PASSWORD') };
        try {
            run('keytool', ['-importkeystore', '-noprompt', '-srckeystore', jks, '-srcstoretype', 'JKS',
                '-srcstorepass:env', 'RELAY_PW', '-srckeypass:env', 'RELAY_PW', '-srcalias', v('SF_JKS_ALIAS'),
                '-destkeystore', p12, '-deststoretype', 'PKCS12', '-deststorepass:env', 'RELAY_PW',
                '-destkeypass:env', 'RELAY_PW'], { env: childEnv, stdio: ['ignore', 'ignore', 'inherit'] });
            run('openssl', ['pkcs12', '-in', p12, '-nocerts', '-nodes', '-passin', 'env:RELAY_PW', '-out', keyFile],
                { env: childEnv, stdio: ['ignore', 'ignore', 'inherit'] });
            fs.chmodSync(keyFile, 0o600);
        } catch (e) {
            fail('Couldn\'t read the key from SF_JKS. Check SF_JKS_PASSWORD, and that SF_JKS_ALIAS is the certificate\'s Unique Name.');
        } finally {
            fs.rmSync(dir, { recursive: true, force: true });
        }
        return;
    }
    if (!v('SF_JWT_KEY')) {
        fail('Set SF_JKS (keystore from Salesforce) or SF_JWT_KEY (private key) for this org (environment or prefixed variables).');
    }
    fs.writeFileSync(keyFile, Buffer.from(v('SF_JWT_KEY'), 'base64'), { mode: 0o600 });
}


// ---------- inputs and per-org values ----------

const RESULTS_BRANCH = 'release-relay-results';
const SHA_RE = /^[0-9a-f]{40}$/;
const SCAN_EXT = ['.cls', '.trigger', '.page', '.component', '.cmp', '.js', '.html', '.flow-meta.xml'];
const TEST_LEVELS = ['NoTestRun', 'RunLocalTests', 'RunAllTestsInOrg'];
const WORK_DIR = '.relay';
const PROVIDER = (env.RELAY_PROVIDER || 'github').toLowerCase();

/** A plain input: empty for unset, '-' (Azure's empty marker) or an unexpanded $(NAME) macro. */
function input(name) {
    const value = (env[name] || '').trim();
    return value === '-' || /^\$\([A-Za-z0-9_.]+\)$/.test(value) ? '' : value;
}

const step = input('STEP');
const mode = input('MODE');
const requestId = input('REQUEST_ID');
const branch = input('BRANCH');
const target = input('TARGET');
const title = input('TITLE').replace(/[\r\n\t]+/g, ' ').slice(0, 200);
const sourceEnv = input('ENVIRONMENT');
const options = (() => {
    try {
        const o = JSON.parse(input('OPTIONS') || '{}');
        return o && typeof o === 'object' && !Array.isArray(o) ? o : {};
    } catch (e) {
        return {};
    }
})();
const APEX_NAME_RE = /^[A-Za-z][A-Za-z0-9_]{0,39}$/;
// The hub's token for this run: every result file echoes it, so the hub never reads an earlier run's result.
const runToken = typeof options.attempt === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(options.attempt) ? options.attempt : null;
const targetEnv = input('TARGET_ENVIRONMENT');

let orgEnv = sourceEnv; // whose login and settings v() reads

function prefixOf(name) {
    return (name || '').toUpperCase().replace(/[^A-Z0-9]+/g, '_');
}

/** A per-org value: PREFIX_NAME for the current org, else NAME. */
function v(name) {
    const prefixed = orgEnv ? input(prefixOf(orgEnv) + '_' + name) : '';
    return prefixed || input(name);
}

function sourcePath() {
    return (v('SOURCE_PATH') || 'force-app/main/default').replace(/\/+$/, '');
}

function orgLabel() {
    const label = typeof options.label === 'string' && /^[A-Za-z0-9 ._-]{1,40}$/.test(options.label) ? options.label : '';
    return label || v('ORG_LABEL') || sourceEnv || 'the source org';
}

function runUrl() {
    if (env.GITHUB_RUN_ID) {
        return `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`;
    }
    if (env.CI_PIPELINE_URL) {
        return env.CI_PIPELINE_URL;
    }
    if (env.BITBUCKET_BUILD_NUMBER) {
        return `https://bitbucket.org/${env.BITBUCKET_REPO_FULL_NAME}/pipelines/results/${env.BITBUCKET_BUILD_NUMBER}`;
    }
    if (env.BUILD_BUILDID) {
        return `${env.SYSTEM_COLLECTIONURI}${encodeURIComponent(env.SYSTEM_TEAMPROJECT || '')}/_build/results?buildId=${env.BUILD_BUILDID}`;
    }
    return '';
}

function checkCommonInputs() {
    if (!/^REL-\d{5,}$/.test(requestId)) { fail('REQUEST_ID must look like REL-00042.'); }
    if (!['org', 'branch', 'promote', 'hub', 'resolve', 'check', 'merge'].includes(mode)) { fail('MODE must be org, branch, promote, hub, resolve, check or merge.'); }
    if (!BRANCH_RE.test(branch)) { fail(`Branch "${branch}" must look like feature/short-name.`); }
    if (!REF_RE.test(target) || target === branch) { fail(`Target "${target}" isn't a valid target branch.`); }
    if (!/^[A-Za-z0-9_./-]+$/.test(sourcePath()) || sourcePath().includes('..')) { fail('SOURCE_PATH is invalid.'); }
    if (!['github', 'gitlab', 'bitbucket', 'azure'].includes(PROVIDER)) { fail('RELAY_PROVIDER must be github, gitlab, bitbucket or azure.'); }
}

function checkAllowedTarget() {
    if (options.hub === true) {
        return; // the Release Relay hub only raises along its registered route
    }
    const allowed = v('ALLOWED_TARGETS').split(',').map((s) => s.trim()).filter(Boolean);
    if (!allowed.length) { fail(`ALLOWED_TARGETS isn't set for ${sourceEnv || 'this org'}, so it isn't configured for Release Relay.`); }
    if (!allowed.includes(target)) { fail(`${sourceEnv || 'This org'} can only raise into: ${allowed.join(', ')}.`); }
}

// ---------- git ----------

function git(args, options) {
    return run('git', args, options);
}

function gitQuiet(args) {
    try {
        return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
    } catch (e) {
        return null;
    }
}

function remoteBranchExists(name) {
    return git(['ls-remote', '--heads', 'origin', 'refs/heads/' + name]) !== '';
}

function fetchBranch(name) {
    git(['fetch', '--no-tags', 'origin', `+refs/heads/${name}:refs/remotes/origin/${name}`]);
}

/** GitLab jobs can't push with their own token: push with the project access token instead. */
function preparePush() {
    git(['config', 'user.name', 'Release Relay']);
    git(['config', 'user.email', 'release-relay@users.noreply.local']);
    if (PROVIDER === 'gitlab') {
        if (!input('RELAY_TOKEN')) {
            fail('RELAY_TOKEN (a project access token with api and write_repository) is required on GitLab.');
        }
        // RELAY_PUSH_URL overrides the address, for example a self-managed GitLab on another port.
        const url = input('RELAY_PUSH_URL')
            || `https://oauth2:${input('RELAY_TOKEN')}@${env.CI_SERVER_HOST}/${env.CI_PROJECT_PATH}.git`;
        git(['remote', 'set-url', 'origin', url]);
    }
}

/** Checks out the release branch and returns its merge base with the target. */
function checkoutReleaseBranch() {
    fetchBranch(target);
    fetchBranch(branch);
    git(['checkout', '-q', '--detach', `refs/remotes/origin/${branch}`]);
    return git(['merge-base', `refs/remotes/origin/${target}`, 'HEAD']);
}

// ---------- results for Salesforce ----------

/** Saves this step's result on the results branch. Each step has its own file; pushes retry on races. */
function writeResult(name, data) {
    const result = { request: requestId, step: name, ...data, runUrl: runUrl(), finishedAt: new Date().toISOString() };
    if (runToken) {
        result.attempt = runToken;
    }
    const json = JSON.stringify(result, null, 1);
    summary('```json\n' + json.slice(0, 4000) + '\n```');
    if (env.RELAY_LOCAL_RESULTS === 'true') {
        return;
    }
    const file = path.join('results', requestId, name + '.json');
    for (let attempt = 1; attempt <= 4; attempt++) {
        const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-results-'));
        try {
            if (remoteBranchExists(RESULTS_BRANCH)) {
                fetchBranch(RESULTS_BRANCH);
                git(['worktree', 'add', '-q', '--detach', dir, `refs/remotes/origin/${RESULTS_BRANCH}`]);
            } else {
                git(['worktree', 'add', '-q', '--detach', dir]);
                git(['checkout', '-q', '--orphan', 'relay-results-' + Date.now()], { cwd: dir });
                gitQuietIn(dir, ['rm', '-rf', '-q', '--cached', '.']);
                for (const entry of fs.readdirSync(dir)) {
                    if (entry !== '.git') {
                        fs.rmSync(path.join(dir, entry), { recursive: true, force: true });
                    }
                }
            }
            fs.mkdirSync(path.join(dir, path.dirname(file)), { recursive: true });
            fs.writeFileSync(path.join(dir, file), json + '\n');
            git(['add', '--', file], { cwd: dir });
            git(['-c', 'user.name=Release Relay', '-c', 'user.email=release-relay@users.noreply.local',
                'commit', '-q', '-m', `${requestId} ${name}: ${result.status}`], { cwd: dir });
            git(['push', '-q', 'origin', `HEAD:refs/heads/${RESULTS_BRANCH}`], { cwd: dir });
            return;
        } catch (e) {
            console.log(`Saving the ${name} result failed (attempt ${attempt}); retrying.`);
        } finally {
            gitQuiet(['worktree', 'remove', '--force', dir]);
            fs.rmSync(dir, { recursive: true, force: true });
        }
    }
    fail(`Couldn't save the ${name} result to the ${RESULTS_BRANCH} branch. The pipeline needs permission to push a new branch, and the branch must not be protected.`);
}

function gitQuietIn(dir, args) {
    try {
        execFileSync('git', args, { cwd: dir, stdio: ['ignore', 'ignore', 'ignore'] });
    } catch (e) {
        // nothing to remove
    }
}

/** Hands the merge commit to the deploy job. */
function shareMergeSha(sha) {
    fs.writeFileSync('.relay-merge-sha', sha + '\n');
    if (env.GITHUB_OUTPUT) {
        fs.appendFileSync(env.GITHUB_OUTPUT, `sha=${sha}\n`);
    }
    if (env.TF_BUILD) {
        console.log(`##vso[task.setvariable variable=sha;isOutput=true]${sha}`);
    }
}

// ---------- Salesforce login ----------

function login(alias) {
    for (const name of ['SF_USERNAME', 'SF_CLIENT_ID', 'SF_INSTANCE_URL']) {
        if (!v(name)) {
            throw new Error(`${name} isn't set for ${orgEnv || 'this org'} (as ${prefixOf(orgEnv)}_${name} or ${name}).`);
        }
    }
    const keyFile = path.join(os.tmpdir(), 'relay.key');
    writePrivateKey(keyFile);
    try {
        run('sf', ['org', 'login', 'jwt', '--client-id', v('SF_CLIENT_ID'), '--username', v('SF_USERNAME'),
            '--jwt-key-file', keyFile, '--instance-url', v('SF_INSTANCE_URL'), '--alias', alias], { stdio: ['ignore', 'ignore', 'inherit'] });
    } finally {
        fs.rmSync(keyFile, { force: true });
    }
}

function apiVersion() {
    try {
        return JSON.parse(fs.readFileSync('sfdx-project.json', 'utf8')).sourceApiVersion || '62.0';
    } catch (e) {
        return '62.0';
    }
}

/** Files changed between two commits, under SOURCE_PATH. Renames count as delete plus add. */
function changedFiles(base, head) {
    const out = git(['diff', '--name-status', '--no-renames', base, head, '--', sourcePath()]);
    return out.split('\n').filter(Boolean).map((line) => {
        const [status, file] = line.split('\t');
        return { status: status.charAt(0), file };
    });
}

// Folder -> [type, suffix] for one-file components, built from FILE_TYPES.
const FOLDER_FILES = {};
Object.keys(FILE_TYPES).forEach((t) => { FOLDER_FILES[FILE_TYPES[t][0]] = [t, FILE_TYPES[t][1]]; });
const BUNDLES = { lwc: 'LightningComponentBundle', aura: 'AuraDefinitionBundle' };
const CHILD_FOLDERS = {};
Object.keys(CHILD_TYPES).forEach((t) => { CHILD_FOLDERS[CHILD_TYPES[t][0]] = [t, CHILD_TYPES[t][1]]; });

/** The component a repo file belongs to, or null when the script can't tell. */
function componentFor(file) {
    const rel = path.relative(sourcePath(), file).split(path.sep);
    const folder = rel[0];
    const base = rel[rel.length - 1];
    if (BUNDLES[folder]) {
        return rel.length >= 3 ? { type: BUNDLES[folder], name: rel[1], dir: path.join(sourcePath(), folder, rel[1]) } : null;
    }
    if (folder === 'objects' && rel.length === 3 && base === `${rel[1]}.object-meta.xml`) {
        return { type: 'CustomObject', name: rel[1] };
    }
    if (folder === 'objects' && rel.length === 4 && CHILD_FOLDERS[rel[2]]) {
        const [type, suffix] = CHILD_FOLDERS[rel[2]];
        return base.endsWith(suffix) ? { type, name: `${rel[1]}.${base.slice(0, -suffix.length)}` } : null;
    }
    if (FOLDER_FILES[folder] && rel.length === 2) {
        const [type, suffix] = FOLDER_FILES[folder];
        const stem = base.endsWith('-meta.xml') && !suffix.endsWith('-meta.xml') ? base.slice(0, -'-meta.xml'.length) : base;
        return stem.endsWith(suffix) ? { type, name: stem.slice(0, -suffix.length) } : null;
    }
    if (folder === 'staticresources' && rel.length >= 2) {
        return { type: 'StaticResource', name: rel[1].split('.')[0] };
    }
    return null;
}

/**
 * Builds .relay/package.xml (+ destructiveChangesPost.xml) for the changes between two commits,
 * using the files as they are at head. Returns null when nothing deployable changed.
 */
function buildDeployment(base, head) {
    const files = changedFiles(base, head);
    const sourceDirs = new Set();
    const deletions = new Map();
    const unknown = [];
    for (const f of files) {
        if (f.status !== 'D') {
            const c = componentFor(f.file);
            sourceDirs.add(c && c.dir ? c.dir : f.file);
            continue;
        }
        const c = componentFor(f.file);
        if (!c) {
            unknown.push(f.file);
        } else if (c.dir && fs.existsSync(c.dir)) {
            sourceDirs.add(c.dir); // a file removed from a bundle that still exists
        } else if (c.type === 'StaticResource' || !c.dir) {
            const stillThere = c.type === 'StaticResource'
                ? fs.existsSync(path.join(sourcePath(), 'staticresources')) && fs.readdirSync(path.join(sourcePath(), 'staticresources')).some((n) => n.split('.')[0] === c.name)
                : (pathsFor(sourcePath(), c.type, c.name) || []).some((p) => fs.existsSync(p));
            if (!stillThere) {
                deletions.set(`${c.type}:${c.name}`, c);
            }
        } else {
            deletions.set(`${c.type}:${c.name}`, c);
        }
    }
    if (unknown.length) {
        throw new Error(`Can't tell which component these deleted files belong to: ${unknown.slice(0, 10).join(', ')}. Delete it with a manual deployment.`);
    }
    if (!sourceDirs.size && !deletions.size) {
        return null;
    }
    fs.rmSync(WORK_DIR, { recursive: true, force: true });
    fs.mkdirSync(WORK_DIR, { recursive: true });
    const pkg = path.join(WORK_DIR, 'package.xml');
    const existing = [...sourceDirs].filter((d) => fs.existsSync(d));
    if (existing.length) {
        const args = ['project', 'generate', 'manifest', '--name', 'package', '--output-dir', WORK_DIR];
        existing.forEach((d) => args.push('--source-dir', d));
        run('sf', args, { stdio: ['ignore', 'ignore', 'inherit'] });
    } else {
        fs.writeFileSync(pkg, manifest(apiVersion(), []));
    }
    let destructive = null;
    if (deletions.size) {
        destructive = path.join(WORK_DIR, 'destructiveChangesPost.xml');
        fs.writeFileSync(destructive, manifest(apiVersion(), [...deletions.values()]));
    }
    return { pkg, destructive, changed: existing.length, deleted: deletions.size,
        deletedList: [...deletions.keys()] };
}

function asList(value) {
    if (!value) {
        return [];
    }
    return Array.isArray(value) ? value : [value];
}

/** The release's test classes from OPTIONS.tests, or null when the release didn't send any. */
function releaseTests() {
    if (!Array.isArray(options.tests)) {
        return null;
    }
    const bad = options.tests.filter((t) => !APEX_NAME_RE.test(String(t)));
    if (bad.length) {
        fail(`These test class names aren't valid: ${bad.slice(0, 5).join(', ')}.`);
    }
    return [...new Set(options.tests.map(String))];
}

/** Runs a deployment (or a check-only one) and returns a result for Salesforce. */
function deployTo(alias, plan, checkOnly) {
    const tests = releaseTests();
    const testLevel = tests ? (tests.length ? 'RunSpecifiedTests' : 'NoTestRun')
        : TEST_LEVELS.includes(v('DEPLOY_TEST_LEVEL')) ? v('DEPLOY_TEST_LEVEL') : 'RunLocalTests';
    const args = ['project', 'deploy', 'start', '--manifest', plan.pkg, '--target-org', alias,
        '--test-level', testLevel, '--wait', '110', '--json'];
    (tests || []).forEach((t) => args.push('--tests', t));
    if (plan.destructive) {
        args.push('--post-destructive-changes', plan.destructive);
    }
    if (checkOnly) {
        args.push('--dry-run');
    }
    let raw;
    try {
        raw = execFileSync('sf', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 });
    } catch (e) {
        raw = e.stdout ? String(e.stdout) : '';
        if (!raw) {
            return { ok: false, message: String(e.stderr || e.message).slice(0, 1500), testLevel };
        }
    }
    let out;
    try {
        out = JSON.parse(raw);
    } catch (e) {
        return { ok: false, message: 'The Salesforce CLI returned output that isn\'t JSON.', testLevel };
    }
    const r = out.result || {};
    const details = r.details || {};
    const componentErrors = asList(details.componentFailures).slice(0, 100).map((c) => ({
        type: c.componentType, name: c.fullName, problem: c.problem, line: c.lineNumber
    }));
    const testFailures = asList(details.runTestResult && details.runTestResult.failures).slice(0, 100).map((t) => ({
        name: t.name, method: t.methodName, message: t.message
    }));
    const ok = out.status === 0 && r.success !== false && !componentErrors.length && !testFailures.length;
    return {
        ok,
        testLevel,
        deployId: r.id || null,
        testsRun: details.runTestResult ? Number(details.runTestResult.numTestsRun || 0) : 0,
        tests: tests || [],
        coverageWarnings: asList(details.runTestResult && details.runTestResult.codeCoverageWarnings).slice(0, 50).map((w) => ({
            name: w.name, message: w.message
        })),
        componentErrors,
        testFailures,
        message: ok ? '' : (componentErrors.length ? `${componentErrors.length} component error(s)`
            : testFailures.length ? `${testFailures.length} test failure(s)` : (out.message || r.errorMessage || 'Deployment failed')).toString().slice(0, 1500)
    };
}


// ---------- step: scan ----------

const SEVERITY = { 1: 'Critical', 2: 'High', 3: 'Moderate', 4: 'Low', 5: 'Info' };

async function stepScan() {
    orgEnv = '';
    const base = checkoutReleaseBranch();
    const files = changedFiles(base, 'HEAD')
        .filter((f) => f.status !== 'D' && SCAN_EXT.some((ext) => f.file.endsWith(ext)) && fs.existsSync(f.file))
        .map((f) => f.file);
    if (!files.length) {
        writeResult('scan', { status: 'Skipped', total: 0, blocking: 0, files: [], violations: [],
            message: 'No code files in this pull request.' });
        return;
    }
    const threshold = Math.min(5, Math.max(1, parseInt(v('SCAN_BLOCK_SEVERITY'), 10) || 2));
    const rules = /^[A-Za-z0-9:,() _-]{1,200}$/.test(v('SCAN_RULES') || '') ? v('SCAN_RULES') : 'Recommended';
    fs.mkdirSync(WORK_DIR, { recursive: true });
    const outFile = path.join(WORK_DIR, 'scan.json');
    const args = ['code-analyzer', 'run', '--workspace', '.', '--rule-selector', rules, '--output-file', outFile];
    files.forEach((f) => args.push('--target', f));
    try {
        run('sf', args, { stdio: ['ignore', 'inherit', 'inherit'] });
    } catch (e) {
        if (!fs.existsSync(outFile)) {
            writeResult('scan', { status: 'Error', total: 0, blocking: 0, files, violations: [],
                message: 'Code Analyzer didn\'t run. Open the workflow run for the log.' });
            return;
        }
    }
    let report;
    try {
        report = JSON.parse(fs.readFileSync(outFile, 'utf8'));
    } catch (e) {
        writeResult('scan', { status: 'Error', total: 0, blocking: 0, files, violations: [], message: 'The scan report couldn\'t be read.' });
        return;
    }
    const root = process.cwd() + path.sep;
    const violations = asList(report.violations).map((v) => {
        const loc = asList(v.locations)[v.primaryLocationIndex || 0] || {};
        return {
            severity: Number(v.severity) || 5,
            severityLabel: SEVERITY[Number(v.severity)] || String(v.severity),
            rule: v.rule,
            engine: v.engine,
            file: String(loc.file || '').replace(root, ''),
            line: loc.startLine || null,
            message: String(v.message || '').slice(0, 500),
            url: asList(v.resources)[0] || null
        };
    }).sort((a, b) => a.severity - b.severity);
    const counts = {};
    violations.forEach((v) => { counts[v.severityLabel] = (counts[v.severityLabel] || 0) + 1; });
    const blocking = violations.filter((v) => v.severity <= threshold).length;
    writeResult('scan', {
        status: blocking ? 'Failed' : 'Passed',
        total: violations.length,
        blocking,
        threshold,
        thresholdLabel: SEVERITY[threshold],
        rules,
        counts,
        files,
        violations: violations.slice(0, 200),
        message: blocking ? `${blocking} violation(s) at ${SEVERITY[threshold]} or above.` : ''
    });
}

// ---------- step: validate ----------

// ---------- pull requests and merge requests, per provider ----------

async function http(method, url, headers, body) {
    const res = await fetch(url, {
        method,
        headers: { Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}), ...headers },
        body: body ? JSON.stringify(body) : undefined
    });
    const text = await res.text();
    let json = null;
    try {
        json = text ? JSON.parse(text) : null;
    } catch (e) {
        json = null;
    }
    return { ok: res.ok, status: res.status, json, text };
}

function apiError(action, res) {
    const detail = res.json ? JSON.stringify(res.json).slice(0, 500) : String(res.text || '').slice(0, 500);
    return new Error(`${action} failed with HTTP ${res.status}: ${detail}`);
}

const providers = {
    github: {
        label: 'pull request',
        async open(head, base, prTitle, body) {
            const existing = run('gh', ['pr', 'list', '--head', head, '--base', base, '--state', 'open', '--json', 'url', '--jq', '.[0].url // ""']);
            if (existing) {
                return existing;
            }
            const bodyFile = path.join(os.tmpdir(), 'relay-pr-body.md');
            fs.writeFileSync(bodyFile, body);
            return run('gh', ['pr', 'create', '--head', head, '--base', base, '--title', prTitle, '--body-file', bodyFile]);
        },
        async find(head, base, state) {
            const n = run('gh', ['pr', 'list', '--head', head, '--base', base, '--state', state, '--json', 'number', '--jq', '.[0].number // ""']);
            return n ? { id: n } : null;
        },
        async merge(pr, method) {
            try {
                execFileSync('gh', ['pr', 'merge', String(pr.id), '--' + method], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
            } catch (e) {
                throw new Error(String(e.stderr || e.message).trim().slice(0, 800));
            }
        },
        async mergeSha(pr) {
            return run('gh', ['pr', 'view', String(pr.id), '--json', 'mergeCommit', '--jq', '.mergeCommit.oid // ""']);
        }
    },

    gitlab: {
        label: 'merge request',
        base() {
            return `${env.CI_API_V4_URL}/projects/${env.CI_PROJECT_ID}`;
        },
        headers() {
            return { 'PRIVATE-TOKEN': input('RELAY_TOKEN') };
        },
        async list(head, base, state) {
            const q = `source_branch=${encodeURIComponent(head)}&target_branch=${encodeURIComponent(base)}&state=${state}`;
            const res = await http('GET', `${this.base()}/merge_requests?${q}`, this.headers());
            if (!res.ok) {
                throw apiError('Merge request lookup', res);
            }
            return res.json || [];
        },
        async open(head, base, prTitle, body) {
            const open = await this.list(head, base, 'opened');
            if (open.length) {
                return open[0].web_url;
            }
            const res = await http('POST', `${this.base()}/merge_requests`, this.headers(),
                { source_branch: head, target_branch: base, title: prTitle, description: body, remove_source_branch: false });
            if (!res.ok) {
                throw apiError('Merge request creation', res);
            }
            return res.json.web_url;
        },
        async find(head, base, state) {
            const rows = await this.list(head, base, state === 'open' ? 'opened' : 'merged');
            return rows.length ? { id: rows[0].iid, raw: rows[0] } : null;
        },
        async merge(pr, method) {
            const res = await http('PUT', `${this.base()}/merge_requests/${pr.id}/merge`, this.headers(), { squash: method === 'squash' });
            if (!res.ok) {
                throw apiError('Merge', res);
            }
            pr.raw = res.json;
        },
        async mergeSha(pr) {
            let mr = pr.raw;
            if (!mr || (!mr.merge_commit_sha && !mr.squash_commit_sha)) {
                const res = await http('GET', `${this.base()}/merge_requests/${pr.id}`, this.headers());
                mr = res.json || {};
            }
            return mr.merge_commit_sha || mr.squash_commit_sha || '';
        }
    },

    bitbucket: {
        label: 'pull request',
        base() {
            return `https://api.bitbucket.org/2.0/repositories/${env.BITBUCKET_REPO_FULL_NAME}`;
        },
        headers() {
            return { Authorization: 'Bearer ' + input('RELAY_TOKEN') };
        },
        async list(head, base, state) {
            const q = encodeURIComponent(`source.branch.name="${head}" AND destination.branch.name="${base}"`);
            const res = await http('GET', `${this.base()}/pullrequests?q=${q}&state=${state}&sort=-created_on`, this.headers());
            if (!res.ok) {
                throw apiError('Pull request lookup', res);
            }
            return (res.json && res.json.values) || [];
        },
        async open(head, base, prTitle, body) {
            const open = await this.list(head, base, 'OPEN');
            if (open.length) {
                return open[0].links.html.href;
            }
            const res = await http('POST', `${this.base()}/pullrequests`, this.headers(), {
                title: prTitle, description: body, close_source_branch: false,
                source: { branch: { name: head } }, destination: { branch: { name: base } }
            });
            if (!res.ok) {
                throw apiError('Pull request creation', res);
            }
            return res.json.links.html.href;
        },
        async find(head, base, state) {
            const rows = await this.list(head, base, state === 'open' ? 'OPEN' : 'MERGED');
            return rows.length ? { id: rows[0].id, raw: rows[0] } : null;
        },
        async merge(pr, method) {
            const res = await http('POST', `${this.base()}/pullrequests/${pr.id}/merge`, this.headers(),
                { merge_strategy: method === 'squash' ? 'squash' : 'merge_commit', close_source_branch: false });
            if (!res.ok) {
                throw apiError('Merge', res);
            }
            pr.raw = res.json;
        },
        async mergeSha(pr) {
            let raw = pr.raw;
            if (!raw || !raw.merge_commit) {
                const res = await http('GET', `${this.base()}/pullrequests/${pr.id}`, this.headers());
                raw = res.json || {};
            }
            return raw.merge_commit ? raw.merge_commit.hash : '';
        }
    },

    azure: {
        label: 'pull request',
        base() {
            return `${env.SYSTEM_COLLECTIONURI}${encodeURIComponent(env.SYSTEM_TEAMPROJECT)}/_apis/git/repositories/${env.BUILD_REPOSITORY_ID}`;
        },
        headers() {
            return { Authorization: 'Bearer ' + input('SYSTEM_ACCESSTOKEN') };
        },
        web(id) {
            return `${env.SYSTEM_COLLECTIONURI}${encodeURIComponent(env.SYSTEM_TEAMPROJECT)}/_git/${encodeURIComponent(env.BUILD_REPOSITORY_NAME)}/pullrequest/${id}`;
        },
        async list(head, base, status) {
            const q = `searchCriteria.sourceRefName=${encodeURIComponent('refs/heads/' + head)}&searchCriteria.targetRefName=${encodeURIComponent('refs/heads/' + base)}&searchCriteria.status=${status}`;
            const res = await http('GET', `${this.base()}/pullrequests?${q}&api-version=7.1`, this.headers());
            if (!res.ok) {
                throw apiError('Pull request lookup', res);
            }
            return (res.json && res.json.value) || [];
        },
        async open(head, base, prTitle, body) {
            const open = await this.list(head, base, 'active');
            if (open.length) {
                return this.web(open[0].pullRequestId);
            }
            const res = await http('POST', `${this.base()}/pullrequests?api-version=7.1`, this.headers(), {
                sourceRefName: 'refs/heads/' + head, targetRefName: 'refs/heads/' + base, title: prTitle, description: body.slice(0, 4000)
            });
            if (!res.ok) {
                throw apiError('Pull request creation', res);
            }
            return this.web(res.json.pullRequestId);
        },
        async find(head, base, state) {
            const rows = await this.list(head, base, state === 'open' ? 'active' : 'completed');
            return rows.length ? { id: rows[0].pullRequestId, raw: rows[0] } : null;
        },
        async merge(pr, method) {
            const res = await http('PATCH', `${this.base()}/pullrequests/${pr.id}?api-version=7.1`, this.headers(), {
                status: 'completed',
                lastMergeSourceCommit: pr.raw.lastMergeSourceCommit,
                completionOptions: { mergeStrategy: method === 'squash' ? 'squash' : 'noFastForward', deleteSourceBranch: false }
            });
            if (!res.ok) {
                throw apiError('Merge', res);
            }
        },
        async mergeSha(pr) {
            for (let i = 0; i < 20; i++) {
                const res = await http('GET', `${this.base()}/pullrequests/${pr.id}?api-version=7.1`, this.headers());
                const raw = res.json || {};
                if (raw.status === 'completed' && raw.lastMergeCommit) {
                    return raw.lastMergeCommit.commitId;
                }
                await new Promise((r) => setTimeout(r, 3000));
            }
            return '';
        }
    }
};

const provider = providers[PROVIDER] || providers.github;

// ---------- step: raise ----------

async function stepRaise() {
    orgEnv = sourceEnv;
    if (!['org', 'branch', 'promote', 'hub', 'resolve'].includes(mode)) { fail('MODE must be org, branch, promote, hub or resolve to raise.'); }
    checkAllowedTarget();
    if (!title) { fail('Title is required.'); }
    preparePush();

    if (mode === 'promote') {
        await raisePromotion();
        return;
    }

    if (mode === 'hub') {
        await raiseFromHub();
        return;
    }

    if (mode === 'resolve') {
        resolveConflicts();
        return;
    }

    if (mode === 'branch') {
        if (!remoteBranchExists(branch)) {
            fail(`Branch ${branch} doesn't exist.`);
        }
        const body = `Raised from Release Relay (${orgLabel()}), release ${requestId}.\n\n**Request type:** Manual PR\n\nOpened from an existing branch; nothing was retrieved from the org. Approve it in Salesforce; Release Relay merges it.`;
        const url = await provider.open(branch, target, title, body);
        summary(`**${provider.label}:** ${url}\n\n${branch} → ${target}, release ${requestId}`);
        return;
    }

    const components = parseList(input('COMPONENTS'), 'COMPONENTS');
    const deletions = parseList(input('DELETIONS'), 'DELETIONS');
    if (!components.length && !deletions.length) { fail('Nothing selected.'); }
    if (remoteBranchExists(branch)) { fail(`Branch ${branch} already exists. Raise again with a new branch name.`); }

    fetchBranch(target);
    git(['checkout', '-q', '-B', branch, `refs/remotes/origin/${target}`]);

    if (components.length) {
        try {
            login('source-org');
        } catch (e) {
            fail(e.message);
        }
        const args = ['project', 'retrieve', 'start', '--target-org', 'source-org', '--ignore-conflicts', '--wait', '30'];
        components.forEach((c) => args.push('--metadata', c.entry));
        run('sf', args, { stdio: ['ignore', 'inherit', 'inherit'] });
    }

    const missing = [];
    for (const d of deletions) {
        const paths = pathsFor(sourcePath(), d.type, d.name);
        if (paths === null) {
            fail(`Deleting ${d.type} isn't supported by the script. Remove it in a normal ${provider.label}.`);
        }
        const found = paths.filter((p) => fs.existsSync(p));
        if (!found.length) {
            missing.push(d.entry);
            continue;
        }
        git(['rm', '-r', '-q', '--', ...found]);
    }
    if (missing.length) {
        fail(`Not found in ${target}, so they can't be deleted: ${missing.join(', ')}.`);
    }

    if (deletions.length && v('WRITE_DESTRUCTIVE_MANIFEST') !== 'false') {
        const dir = path.join('destructive', requestId);
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, 'package.xml'), manifest(apiVersion(), []));
        fs.writeFileSync(path.join(dir, 'destructiveChangesPost.xml'), manifest(apiVersion(), deletions));
        git(['add', '--', dir]);
    }

    git(['add', '-A', '--', sourcePath()]);
    if (git(['diff', '--cached', '--name-only']) === '') {
        fail(`${orgLabel()} already matches ${target} for these components. Nothing to commit.`);
    }
    git(['commit', '-q', '-m', title, '-m', `Release Relay ${requestId} from ${orgLabel()}`]);
    git(['push', '-q', 'origin', `HEAD:refs/heads/${branch}`]);

    const list = (items) => items.map((i) => `- ${i.type}: \`${i.name}\``).join('\n');
    const requestType = deletions.length ? (components.length ? 'Changes and destructive' : 'Destructive') : 'Changes';
    const body = [
        `Raised from Release Relay (${orgLabel()}), release ${requestId}.`,
        `**Request type:** ${requestType}`,
        components.length ? `### Added or updated from ${orgLabel()}\n${list(components)}` : '',
        deletions.length ? `### Deleted\n${list(deletions)}` : '',
        deletions.length && v('WRITE_DESTRUCTIVE_MANIFEST') !== 'false'
            ? `Destructive manifest: \`destructive/${requestId}/destructiveChangesPost.xml\`` : '',
        'Every item was reviewed in Release Relay. Approve it in Salesforce; Release Relay merges it.'
    ].filter(Boolean).join('\n\n');

    const url = await provider.open(branch, target, title, body);
    summary(`**${provider.label}:** ${url}\n\n${branch} → ${target}, release ${requestId}\n\n${body}`);
}

/** Copies converted source files into the repo; an object's own file only when the object itself was selected. */
function copyConverted(fromDir, toDir, wholeObjects) {
    const copied = [];
    const walk = (rel) => {
        for (const entry of fs.readdirSync(path.join(fromDir, rel), { withFileTypes: true })) {
            const r = path.join(rel, entry.name);
            if (entry.isDirectory()) {
                walk(r);
                continue;
            }
            const parts = r.split(path.sep);
            const dest = path.join(toDir, r);
            const objectFile = parts[0] === 'objects' && parts.length === 3 && parts[2] === `${parts[1]}.object-meta.xml`;
            if (objectFile && !wholeObjects.has(parts[1]) && fs.existsSync(dest)) {
                continue; // only the object's fields etc. were selected: keep the object's own settings
            }
            fs.mkdirSync(path.dirname(dest), { recursive: true });
            fs.copyFileSync(path.join(fromDir, r), dest);
            copied.push(r);
        }
    };
    walk('');
    return copied;
}

/** MODE=hub: turn the hub's Metadata API zip on BRANCH into source files and open the PR/MR. */
/** Converts the hub's metadata zip to source format. On failure the CLI's own message goes into raise.json, so the hub can show it. */
function convertFromHub(mdapi, out) {
    // Some types (custom labels, for example) are only converted inside a Salesforce DX project, so the output
    // folder is made one: a minimal sfdx-project.json whose package directory receives the files.
    fs.mkdirSync(out, { recursive: true });
    fs.writeFileSync(path.join(out, 'sfdx-project.json'),
        JSON.stringify({ packageDirectories: [{ path: 'force-app', default: true }], sourceApiVersion: '63.0' }));
    try {
        execFileSync('sf', ['project', 'convert', 'mdapi', '--root-dir', mdapi, '--output-dir', path.join(out, 'force-app'), '--json'],
            { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], cwd: out });
    } catch (e) {
        let detail = String(e.stdout || '') + String(e.stderr || '');
        try {
            const parsed = JSON.parse(String(e.stdout || '{}'));
            detail = [parsed.name, parsed.message].concat(parsed.actions || []).filter(Boolean).join(' | ') || detail;
        } catch (ignored) {
            // not JSON: keep the raw output
        }
        const message = 'Converting the files from the hub failed: ' + detail.replace(/\s+/g, ' ').trim().slice(0, 1500);
        writeResult('raise', { status: 'Failed', message });
        fail(message);
    }
}

async function raiseFromHub() {
    const components = parseList(input('COMPONENTS'), 'COMPONENTS');
    const zipFile = path.join('.relay-inbox', requestId + '.zip');
    if (!remoteBranchExists(branch)) {
        fail(`Branch ${branch} doesn't exist. Raise the release again from Release Relay.`);
    }
    fetchBranch(target);
    fetchBranch(branch);
    git(['checkout', '-q', '-B', branch, `refs/remotes/origin/${branch}`]);
    if (!fs.existsSync(zipFile)) {
        fail(`${zipFile} isn't on ${branch}. Raise the release again from Release Relay.`);
    }
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-hub-'));
    const mdapi = path.join(tmp, 'mdapi');
    const out = path.join(tmp, 'source');
    run('unzip', ['-q', '-o', zipFile, '-d', mdapi]);
    convertFromHub(mdapi, out);
    const converted = [path.join(out, 'force-app', 'main', 'default'), path.join(out, 'force-app')]
        .find((p) => fs.existsSync(p));
    const wholeObjects = new Set(components.filter((c) => c.type === 'CustomObject').map((c) => c.name));
    const copied = copyConverted(converted, sourcePath(), wholeObjects);
    git(['rm', '-q', '--', zipFile]);
    git(['add', '-A', '--', sourcePath()]);
    if (git(['diff', '--cached', '--name-only', '--', sourcePath()]) === '') {
        fail(`${orgLabel()} already matches ${target} for these components. Nothing to commit.`);
    }
    git(['commit', '-q', '-m', title, '-m', `Release Relay ${requestId} from ${orgLabel()} (${copied.length} files)`]);
    git(['push', '-q', 'origin', `HEAD:refs/heads/${branch}`]);

    const list = components.map((i) => `- ${i.type}: \`${i.name}\``).join('\n');
    const tests = releaseTests();
    const body = [
        `Raised from the Release Relay hub (${orgLabel()}), release ${requestId}.`,
        '**Request type:** Changes',
        `### Added or updated from ${orgLabel()}\n${list}`,
        tests ? (tests.length ? `**Tests:** ${tests.map((t) => '`' + t + '`').join(', ')} (RunSpecifiedTests)` : '**Tests:** none, no Apex (NoTestRun)') : '',
        'Every item was selected and reviewed in Release Relay. Approve it in Salesforce; Release Relay merges it.'
    ].filter(Boolean).join('\n\n');
    const url = await provider.open(branch, target, title, body);
    summary(`**${provider.label}:** ${url}\n\n${branch} → ${target}, release ${requestId}\n\n${body}`);
}

/**
 * A promotion: a new branch from the next stage, with the carried releases' merge commits
 * cherry-picked onto it in the order Salesforce sent them (oldest merge first).
 */
async function raisePromotion() {
    const shas = (input('COMPONENTS') || '').split(',').map((x) => x.trim()).filter(Boolean);
    if (!shas.length || shas.some((x) => !SHA_RE.test(x))) {
        fail('COMPONENTS must list the merge commits to promote, as full 40-character hashes.');
    }
    if (remoteBranchExists(branch)) { fail(`Branch ${branch} already exists. Promote again to get a new branch.`); }

    git(['fetch', '--no-tags', 'origin']); // the commits live on the previous stage's branch
    fetchBranch(target);
    git(['checkout', '-q', '-B', branch, `refs/remotes/origin/${target}`]);

    const picked = [];
    for (const sha of shas) {
        if (gitQuiet(['cat-file', '-t', sha]) !== 'commit') {
            fail(`Commit ${sha.slice(0, 7)} isn't in the repository. Was its branch rewritten?`);
        }
        const parents = (gitQuiet(['rev-list', '--parents', '-n', '1', sha]) || '').split(' ').length - 1;
        // A merge commit is picked against its first parent: the stage branch before the merge.
        const args = ['cherry-pick', '-x', '--allow-empty', '--keep-redundant-commits'];
        if (parents > 1) { args.push('-m', '1'); }
        args.push(sha);
        try {
            execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
        } catch (e) {
            const files = gitQuiet(['diff', '--name-only', '--diff-filter=U']) || '';
            gitQuiet(['cherry-pick', '--abort']);
            fail(`${sha.slice(0, 7)} doesn't apply cleanly on ${target}`
                + (files ? ` (conflicts in ${files.split('\n').slice(0, 5).join(', ')})` : '')
                + '. Promote the releases it depends on first, or resolve it in a branch and raise that branch.');
        }
        picked.push(sha);
    }
    if (git(['diff', '--name-only', `refs/remotes/origin/${target}`, 'HEAD']) === '') {
        fail(`Everything in these commits is already in ${target}. Nothing to promote.`);
    }
    git(['push', '-q', 'origin', `HEAD:refs/heads/${branch}`]);

    const body = [
        `Raised from Release Relay, release ${requestId}.`,
        '**Request type:** Promotion',
        `Promotes into \`${target}\` the changes already deployed to the previous stage, cherry-picked in this order:`,
        picked.map((x) => `- ${x.slice(0, 7)}`).join('\n'),
        'Approve it in Salesforce; Release Relay merges it and deploys it.'
    ].join('\n\n');
    const url = await provider.open(branch, target, title, body);
    summary(`**${provider.label}:** ${url}\n\n${branch} → ${target}, release ${requestId}\n\n${body}`);
}

// ---------- step: validate ----------

async function stepValidate() {
    orgEnv = targetEnv;
    if (!targetEnv) {
        writeResult('validate', { status: 'Skipped', message: 'No target environment: this target is Git only.' });
        return;
    }
    let plan;
    let mergedWith = null;
    try {
        let base;
        if (options.validateMerged === true) {
            const merged = mergeForValidation();
            if (merged.conflicts) {
                writeResult('validate', merged.conflicts);
                return;
            }
            base = merged.base;
            mergedWith = merged.base;
        } else {
            base = checkoutReleaseBranch();
        }
        plan = buildDeployment(base, 'HEAD');
        if (!plan) {
            writeResult('validate', { status: 'Skipped', message: 'Nothing deployable changed under ' + sourcePath() + '.' });
            return;
        }
        login('target-org');
    } catch (e) {
        writeResult('validate', { status: 'Error', message: e.message.slice(0, 1500) });
        return;
    }
    const r = deployTo('target-org', plan, true);
    writeResult('validate', { status: r.ok ? 'Passed' : 'Failed', changed: plan.changed, deleted: plan.deletedList, mergedWith, ...r });
}

const CONFLICT_TEXT_LIMIT = 15000;
const CONFLICT_FILES_LIMIT = 6;

function textAt(ref, file) {
    const out = gitQuiet(['show', `${ref}:${file}`]);
    return out === null ? null : out;
}

function clip(text) {
    if (text === null || text === undefined) {
        return { text: null, truncated: false };
    }
    return { text: text.slice(0, CONFLICT_TEXT_LIMIT), truncated: text.length > CONFLICT_TEXT_LIMIT };
}

function conflictedFiles() {
    const out = gitQuiet(['diff', '--name-only', '--diff-filter=U']);
    return out ? out.split('\n').filter(Boolean) : [];
}

/**
 * Checks out TARGET and merges BRANCH into it locally (nothing is pushed), so validation deploys what
 * the target will really get. Returns { base } (the target commit) or { conflicts } (a result to write).
 */
function mergeForValidation() {
    fetchBranch(target);
    fetchBranch(branch);
    const base = git(['rev-parse', `refs/remotes/origin/${target}`]);
    git(['checkout', '-q', '--detach', base]);
    try {
        run('git', ['merge', '--no-ff', '--no-commit', `refs/remotes/origin/${branch}`], { stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e) {
        const files = conflictedFiles();
        if (!files.length) {
            throw new Error('Merging ' + branch + ' into ' + target + ' failed: ' + String(e.stderr || e.message).slice(0, 500));
        }
        const conflicts = files.slice(0, CONFLICT_FILES_LIMIT).map((file) => {
            const merged = clip(fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null);
            const mine = clip(textAt(`refs/remotes/origin/${branch}`, file));
            const theirs = clip(textAt(`refs/remotes/origin/${target}`, file));
            return { file, merged: merged.text, mine: mine.text, theirs: theirs.text,
                truncated: merged.truncated || mine.truncated || theirs.truncated };
        });
        gitQuiet(['merge', '--abort']);
        return { conflicts: { status: 'Conflict', conflicts, conflictCount: files.length,
            message: `${files.length} file(s) conflict with ${target}. Choose what to keep in Release Relay, then check again.` } };
    }
    // Nothing to merge (already contained) still needs a commit to diff against.
    gitQuiet(['commit', '-q', '--allow-empty', '-m', `${requestId}: ${branch} merged into ${target} for validation`]);
    return { base };
}

const MARKER_RE = /^(<{7}|>{7})( |$)/m;

/** MODE=resolve: merge TARGET into BRANCH with the hub's per-file choices, then push. */
function resolveConflicts() {
    if (!remoteBranchExists(branch)) {
        fail(`Branch ${branch} doesn't exist.`);
    }
    fetchBranch(target);
    fetchBranch(branch);
    git(['checkout', '-q', '-B', branch, `refs/remotes/origin/${branch}`]);
    const inbox = path.join('.relay-inbox', requestId + '-resolve.json');
    if (!fs.existsSync(inbox)) {
        fail(`${inbox} isn't on ${branch}. Resolve the conflicts again in Release Relay.`);
    }
    let resolutions;
    try {
        resolutions = JSON.parse(fs.readFileSync(inbox, 'utf8')).resolutions || [];
    } catch (e) {
        fail(`${inbox} isn't valid JSON.`);
    }
    git(['rm', '-q', '--', inbox]);
    git(['commit', '-q', '-m', `${requestId}: conflict choices received`]);
    try {
        run('git', ['merge', '--no-ff', '--no-commit', `refs/remotes/origin/${target}`], { stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e) {
        // conflicts expected: resolved below
    }
    const conflicted = new Set(conflictedFiles());
    const byFile = new Map(resolutions.map((r) => [String(r.file), r]));
    const missing = [...conflicted].filter((f) => !byFile.has(f));
    if (missing.length) {
        gitQuiet(['merge', '--abort']);
        fail(`No choice was sent for: ${missing.join(', ')}. Resolve every file in Release Relay.`);
    }
    for (const file of conflicted) {
        const r = byFile.get(file);
        if (r.choice === 'mine' || r.choice === 'theirs') {
            const ref = r.choice === 'mine' ? 'HEAD' : 'MERGE_HEAD';
            if (gitQuiet(['cat-file', '-e', `${ref}:${file}`]) === null) {
                git(['rm', '-q', '--', file]);
                continue;
            }
            git(['checkout', `--${r.choice === 'mine' ? 'ours' : 'theirs'}`, '--', file]);
        } else if (r.choice === 'edit' && typeof r.content === 'string' && !MARKER_RE.test(r.content)) {
            fs.writeFileSync(file, r.content);
        } else {
            gitQuiet(['merge', '--abort']);
            fail(`The choice for ${file} isn't valid (mine, theirs, or edited text without conflict markers).`);
        }
        git(['add', '--', file]);
    }
    if (conflictedFiles().length) {
        gitQuiet(['merge', '--abort']);
        fail('Some conflicts are still open after applying the choices.');
    }
    git(['commit', '-q', '--no-edit', '-m', `${requestId}: merge ${target} into ${branch} (conflicts resolved in Release Relay)`]);
    git(['push', '-q', 'origin', `HEAD:refs/heads/${branch}`]);
    summary(`Resolved ${conflicted.size} conflicted file(s) on ${branch}: ${[...conflicted].join(', ')}`);
}

/** After a merge: brings TARGET into each developer branch listed in OPTIONS.syncBranches. */
function syncDeveloperBranches() {
    const branches = Array.isArray(options.syncBranches) ? options.syncBranches.map(String) : [];
    const out = [];
    if (!branches.length) {
        return out;
    }
    fetchBranch(target);
    // A hotfix lists its source stage first: that org already runs the hotfix, so the stage branch takes the
    // hotfix's lines where they differ, and the developer branches then take the stage branch.
    const hotfix = branch.startsWith('hotfix/');
    let from = target;
    for (const b of branches) {
        if (!REF_RE.test(b) || b === target) {
            out.push({ branch: b, status: 'Missing', message: 'Not a valid branch name.' });
            continue;
        }
        if (!remoteBranchExists(b)) {
            out.push({ branch: b, status: 'Missing', message: `${b} doesn't exist in the repository.` });
            continue;
        }
        try {
            fetchBranch(b);
            const stage = hotfix && from === target && b === branches[0];
            git(['checkout', '-q', '-B', b, `refs/remotes/origin/${b}`]);
            run('git', ['merge', '--no-edit', ...(stage ? ['-X', 'theirs'] : []),
                '-m', `Release Relay ${requestId}: bring ${from} into ${b}`, `refs/remotes/origin/${from}`],
                { stdio: ['ignore', 'pipe', 'pipe'] });
            git(['push', '-q', 'origin', `HEAD:refs/heads/${b}`]);
            out.push({ branch: b, status: 'Synced', message: stage
                ? `${b} now includes the hotfix (its lines win, as the ${b} org already runs them).` : `${b} now includes ${from}.` });
            if (stage) {
                gitQuiet(['update-ref', `refs/remotes/origin/${b}`, 'HEAD']);
                from = b;
            }
        } catch (e) {
            gitQuiet(['merge', '--abort']);
            out.push({ branch: b, status: 'Conflict', message: `${b} couldn't take ${from} automatically: ${String(e.stderr || e.message).slice(0, 300)}` });
        }
    }
    return out;
}

// ---------- step: merge ----------

async function stepMerge() {
    orgEnv = sourceEnv;
    checkAllowedTarget();
    const method = ['merge', 'squash'].includes(v('MERGE_METHOD')) ? v('MERGE_METHOD') : 'merge';
    let pr = await provider.find(branch, target, 'open');
    let alreadyMerged = false;
    if (!pr) {
        pr = await provider.find(branch, target, 'merged');
        alreadyMerged = !!pr;
    }
    if (!pr) {
        writeResult('merge', { status: 'Failed', message: `No open ${provider.label} from ${branch} into ${target}.` });
        process.exit(1);
    }
    if (!alreadyMerged) {
        try {
            await provider.merge(pr, method);
        } catch (e) {
            writeResult('merge', { status: 'Failed', pr: Number(pr.id),
                message: `The merge was refused: ${e.message} (conflicts, or a branch rule that needs a bypass for this pipeline).` });
            process.exit(1);
        }
    }
    let sha = '';
    for (let i = 0; i < 5 && !SHA_RE.test(sha); i++) {
        sha = String((await provider.mergeSha(pr)) || '');
        if (sha && !SHA_RE.test(sha)) {
            fetchBranch(target);
            sha = gitQuiet(['rev-parse', sha]) || sha; // a short hash from the provider
        }
        if (!SHA_RE.test(sha)) {
            await new Promise((r) => setTimeout(r, 3000));
        }
    }
    if (!SHA_RE.test(sha)) {
        writeResult('merge', { status: 'Failed', pr: Number(pr.id), message: 'Merged, but the merge commit couldn\'t be read.' });
        process.exit(1);
    }
    let sync = [];
    try {
        sync = syncDeveloperBranches();
    } catch (e) {
        sync = [{ branch: '*', status: 'Conflict', message: 'Updating the developer branches failed: ' + e.message.slice(0, 300) }];
    }
    writeResult('merge', { status: 'Merged', pr: Number(pr.id), sha, method, sync });
    shareMergeSha(sha);
}

// ---------- step: deploy ----------

async function stepDeploy() {
    orgEnv = targetEnv;
    let sha = input('MERGE_SHA');
    if (!SHA_RE.test(sha) && fs.existsSync('.relay-merge-sha')) {
        sha = fs.readFileSync('.relay-merge-sha', 'utf8').trim();
    }
    if (!SHA_RE.test(sha)) {
        writeResult('deploy', { status: 'Failed', message: 'The merge commit is missing.' });
        process.exit(1);
    }
    if (!targetEnv) {
        writeResult('deploy', { status: 'Deployed', sha, message: 'Git only: nothing to deploy for this target.' });
        return;
    }
    let plan;
    try {
        fetchBranch(target);
        git(['checkout', '-q', '--detach', sha]);
        plan = buildDeployment(`${sha}^1`, sha);
        if (!plan) {
            writeResult('deploy', { status: 'Deployed', sha, message: 'Nothing deployable changed under ' + sourcePath() + '.' });
            return;
        }
        login('target-org');
    } catch (e) {
        writeResult('deploy', { status: 'Failed', sha, message: e.message.slice(0, 1500) });
        process.exit(1);
    }
    const r = deployTo('target-org', plan, false);
    writeResult('deploy', { status: r.ok ? 'Deployed' : 'Failed', sha, changed: plan.changed, deleted: plan.deletedList, ...r });
    if (!r.ok) {
        process.exit(1);
    }
}

// ---------- step: auto (one job runs everything MODE needs) ----------

async function stepAuto() {
    if (mode === 'org' || mode === 'branch' || mode === 'promote') {
        await stepRaise();
        await stepScan();
        await stepValidate();
    } else if (mode === 'check') {
        await stepScan();
        await stepValidate();
    } else {
        await stepMerge();
        await stepDeploy();
    }
}

// ---------- step: notify ----------

/** Signs in to the org in this job's environment and asks it to read this release's results. */
async function stepNotify() {
    orgEnv = ''; // this job's environment holds the login of the org to tell
    if (!/^REL-\d{5,}$/.test(requestId)) {
        fail('REQUEST_ID must look like REL-00042.');
    }
    try {
        login('relay-notify');
        const org = JSON.parse(run('sf', ['org', 'display', '--target-org', 'relay-notify', '--json'])).result;
        const res = await http('POST', org.instanceUrl.replace(/\/+$/, '') + '/services/apexrest/release-relay/v1/status',
            { Authorization: 'Bearer ' + org.accessToken }, { request: requestId });
        if (!res.ok) {
            throw apiError('Status update', res);
        }
        summary(`Salesforce updated ${requestId}: ${res.json && res.json.status ? res.json.status : 'done'}.`);
    } catch (e) {
        // The scheduled sync or an open release page picks the result up anyway.
        summary(`Couldn't tell Salesforce about ${requestId} (${e.message}). It catches up on its next sync.`);
    }
}

// ---------- main ----------

const STEPS = { raise: stepRaise, scan: stepScan, validate: stepValidate, merge: stepMerge, deploy: stepDeploy, auto: stepAuto };

async function main() {
    if (step === 'notify') {
        await stepNotify();
        return;
    }
    checkCommonInputs();
    if (!STEPS[step]) {
        fail('STEP must be raise, scan, validate, merge, deploy or auto.');
    }
    preparePush();
    await STEPS[step]();
}

main().catch((e) => fail(e && e.message ? e.message : String(e)));
