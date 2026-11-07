#!/usr/bin/env node
// Release Relay pipeline files: version 25
// Version 25: each step's result also goes to the run's summary page (GITHUB_STEP_SUMMARY; printed when it isn't set)
//   as readable markdown instead of the raw JSON: request id and title, step and status, source → target, raised and
//   approved by (options.by, options.approvedBy), components (count and the first 30), deletions, tests, scan findings,
//   deploy id, message and an "Open in Release Relay" link (options.hubUrl). Values from the values file and
//   secret-like environment variables are replaced by •••. The run's name (workflow file) adds the title and raiser.
// Version 24 (the hub's data sets, request ids DAT-<13 digits>): MODE=data moves records between orgs.
//   STEP=data-export (ENVIRONMENT, the source's environment) queries each object of options.dataSet and saves the
//     records on release-relay-results at data-inbox/<id>/<ii>-<ppp>.json (a developer org's are sent there by the hub).
//   STEP=data-load (TARGET_ENVIRONMENT) masks (options.mask) and swaps per-org values, matches every record with the
//     target by its match key and counts insert / update / unchanged (options.dryRun), or loads parents then children
//     with the data set's trigger bypass on. A key matching two or more target records, a record without a key or a
//     missing parent blocks it. results/<id>/data.json; data runs older than 3 days are pruned.
// Also in version 24: Slack reminders run in the workflow's slack-due job, which calls the hub directly (no script change).
// Version 23 (the hub's Sync status tab, request ids SYN-<13 digits>):
//   MODE=drift (STEP=drift): signs in to an org (ENVIRONMENT, the org's own GitHub environment), builds a manifest of
//     everything in it (sf project generate manifest --from-org: managed packages left out; plus the hub's skipped
//     types and Release Relay's own components left out), retrieves it in chunks, converts it, turns the org's values
//     into {{relay:NAME}} placeholders and compares it with TARGET (that org's branch). Writes results/<id>/drift.json
//     (components only in the org, only on the branch, or different) and results/<id>/f/<n>.json (left = branch,
//     right = org).
//   MODE=compare with options.full = true: the same drift.json for a developer org the hub retrieved in parts
//     (compare-inbox/<id>/<n>.zip): branch components of the types the hub listed (options.folders) that no part
//     holds are only on the branch.
//   MODE=routediff (STEP=routediff): Git only. For each pair of branches down options.route (high to low), what the
//     higher branch changed since their merge base that the lower one doesn't have (same content now is skipped);
//     results/<id>/route.json and f/<n>.json (left = higher, right = lower).
//   MODE=sync with options.paths: back promote picked files only: the paths are taken from BRANCH onto TARGET (a path
//     BRANCH no longer has is removed) instead of a full merge; a path TARGET changed too is a conflict, nothing is
//     overwritten. The validate and deploy that follow are sync's own. With BRANCH = TARGET (Push to the org) the
//     picked components are deployed from the branch as it is and the branch isn't changed.
//   MODE=sync with options.branchOnly and no TARGET_ENVIRONMENT (a developer org, no sign-in in GitHub): the lower
//     branch is updated (merge or picked paths) and nothing is deployed; result Succeeded.
//   MODE=routediff takes options.pairs [[higher, lower], ...] when given (the route as a tree), else options.route.
// Version 22: STEP=compare (MODE=compare, request id CMP-<13 digits>) compares a developer org's copy with a target
// branch for the hub's Compare before raising, without the zip ever being read in Salesforce: the hub commits each
// batch's Metadata API zip to release-relay-results at compare-inbox/<id>/<n>.zip (every zip there is read, in number
// order; options.batches is only a hint), the step converts them to source format on top of TARGET, and writes results/<id>/compare.json (each component and file with its
// status) plus results/<id>/f/<n>.json (a file's two sides, or its unified diff when a side is over 300,000
// characters). The inbox is removed and compares older than 3 days are pruned in the same commit. No org is signed in to.
// Also in version 22: a big release can come from the hub in parts (.relay-inbox/<REQUEST_ID>-part-<k>.zip, mode hub);
// every part is unpacked in number order, like the single zip.
// Version 21: step notify and the monitor send their JSON body inline. "sf api request rest --body <file>" sent the
// file's path as the body, so the hub refused it (runId missing) or ignored it. Runs started from a debug/ or test/
// workflow branch are not posted to the Pipeline Monitor.
// Version 20: STEP=monitor tells the hub about this run for its Pipeline Monitor tab (POST
// /services/apexrest/rly/pipeline-run, signed in with the hub environment's login through "sf api request rest"):
// MONITOR_STATUS=in_progress when the run starts, MONITOR_STATUS=end when it ends (Succeeded, Failed or Cancelled from
// NEEDS_JSON, the finished jobs' outcomes and the first failure read from the GitHub API with GH_TOKEN). It never fails
// the run: any problem is a warning and the step exits 0.
// Version 17: a release whose Apex is only deletions and inactive triggers (<status>Inactive</status> in the trigger's
// -meta.xml), sent with no tests, runs the local tests in production (options.production, set by the hub from its org
// record) and no tests elsewhere; the tests and coverage gates leave inactive triggers (and the tests gate deleted
// Apex) out.
// Version 15: no change to this script; it moves with the GitHub pipeline file (nightly archive job), since the lowest
// version among a hub's files counts.
/*
 * Release Relay: one script for every pipeline job, on GitHub, GitLab, Bitbucket or Azure DevOps.
 *
 *   STEP=raise     MODE=org: retrieve COMPONENTS from the source org, remove DELETIONS, write a
 *                  destructive manifest, commit to a new BRANCH from TARGET, push, open a PR/MR.
 *                  MODE=branch: open a PR/MR from an existing BRANCH into TARGET.
 *                  MODE=promote: make BRANCH (promote/rel-...) from TARGET and open a PR/MR into TARGET.
 *                  With OPTIONS.stageBranch (the previous stage's branch, e.g. "sit"): every file the
 *                  merge commits in COMPONENTS changed (each against its first parent) is taken as it is
 *                  now in that branch (or removed when it's gone there), so older stage releases and
 *                  fixes to the same files come along and nothing has to apply as a patch. A file whose
 *                  TARGET version the stage never had (a hotfix not merged back down) stops it first:
 *                  raise.json "clash". Without stageBranch: cherry-pick the commits (oldest first).
 *                  MODE=hub: the Release Relay hub already retrieved the components from the
 *                  developer org and committed the Metadata API zip to BRANCH as
 *                  .relay-inbox/<REQUEST_ID>.zip. Convert it to source format, replace the zip
 *                  with the files, push, open a PR/MR into TARGET. No org login is needed.
 *                  DELETIONS (Type:Name list, and/or .relay-inbox/<REQUEST_ID>.deletions, the hub's
 *                  marker for a release with only deletions) removes those components' files from
 *                  BRANCH in the same commit; validate and deploy then delete them from the org
 *                  (destructiveChangesPost). raise.json lists them under "deleted".
 *                  With OPTIONS.append (more changes for a release that's already open): BRANCH must
 *                  exist; the hub committed .relay-inbox/<REQUEST_ID>-add-<k>.zip (OPTIONS.appendZip) to
 *                  it, which is converted the same way, DELETIONS removed, and the branch pushed. No new
 *                  PR/MR (the open one updates); raise.json says "appended": true.
 *                  MODE=resolve: merge TARGET into BRANCH, applying the choices the hub committed in
 *                  .relay-inbox/<REQUEST_ID>-resolve.json for each conflicted file, then push.
 *                  Runs started by the hub (OPTIONS.hub) in modes hub and promote write
 *                  results/<REQUEST_ID>/raise.json: the pull request opened, or why none was.
 *   STEP=scan      Salesforce Code Analyzer on the files the PR/MR changes.
 *   STEP=validate  Check-only deployment of the PR/MR's changes to the target org.
 *   STEP=merge     Merge the PR/MR approved in Salesforce.
 *   STEP=deploy    Deploy the merged changes (and deletions) to the target org.
 *   STEP=sync      MODE=sync (back promote): merge BRANCH (the hub's production branch) into TARGET
 *                  (a back-promote org's branch, made from BRANCH when missing), deploy what changed
 *                  to TARGET_ENVIRONMENT's org, and push TARGET only when that deploy worked.
 *                  Writes results/<REQUEST_ID>/sync.json.
 *   STEP=rollback  MODE=rollback: deploy a snapshot taken before an earlier deploy back into
 *                  TARGET_ENVIRONMENT's org (and delete what that deploy added). Git isn't changed.
 *                  Writes results/<REQUEST_ID>/rollback.json.
 *   STEP=auto      Run the steps MODE needs, in order (GitLab and Bitbucket use one job).
 *   STEP=notify    Tell the Salesforce org that raised the release to read the results now
 *                  (POST /services/apexrest/release-relay/v1/status). Never fails the run.
 *   STEP=monitor   Tell the hub about this run for its Pipeline Monitor (POST /services/apexrest/rly/pipeline-run):
 *                  MONITOR_STATUS=in_progress at the start, MONITOR_STATUS=end at the end (status from NEEDS_JSON,
 *                  the jobs and the first failure from the GitHub API with GH_TOKEN). Never fails the run.
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
 * {"syncBranches":["sit","dev1"]} merges TARGET into each of those branches, in that order, after a
 * merge (each branch takes TARGET directly), so every stage and developer branch starts from the latest;
 * the merge result lists them under "sync". {"stageWins":true} lets the first listed branch take
 * TARGET's lines where they conflict (-X theirs); without it a conflict is reported, never forced.
 * The deploy step quick deploys the release's validation (no tests run again) when the merge is exactly
 * what was validated; {"quickDeploy":false} always deploys in full. deploy.json says which: quick, quickNote.
 * {"stageBranch":"sit"} (mode promote) takes each changed file as it is in that branch instead of cherry-picking;
 * {"append":true,"appendZip":".relay-inbox/REL-00042-add-1.zip"} (mode hub) adds changes to the open release's BRANCH.
 *
 * Release Relay's own metadata (its classes, LWCs, objects, tabs, permission sets, ... listed by exact name in
 * BUILT_IN_EXCLUDES, plus any globs in .relay/exclude read from the pipeline's own commit) is never deployed or
 * deleted by validate, deploy (full or quick) or sync. A release whose every changed file is excluded fails. They
 * are left out of every deployment and listed in validate.json, deploy.json and sync.json as "excluded". {"selfUpdate":true} (the hub
 * updating itself, from the release-relay-hub branch) ignores the list.
 *
 * Per-org values (.relay/values.json, read from the pipeline's own commit like .relay/exclude):
 * {"values":{"PAYMENT_URL":{"dev1":"https://dev.pay.example","prod":"https://pay.example"}}}. Branches hold
 * {{relay:PAYMENT_URL}}; validate, deploy and sync replace it with the target environment's value in a temporary
 * copy of the deployment's text files (never committed), and fail when a placeholder has no value for that
 * environment. Raises that write org metadata into a branch (modes org and hub) turn the source environment's
 * values (6 characters or longer, longest first) back into placeholders. Results: "values" (validate, deploy, sync),
 * "valuesTokenized" (raise). Keys starting with "_" are ignored.
 *
 * Quality gates (.relay/gates.json, pipeline commit, all optional):
 * {"scan":{"failAtPriority":2},"coverage":{"minimumPerClass":75,"minimumOrgWide":75},"tests":{"requireForApex":true}}.
 * scan.json and validate.json record "gates": { file, passed, failures }; a failed gate fails that step.
 *
 * Rollback snapshots: before every real deploy (deploy, full or quick, and sync) the current org versions of the
 * deployment's components (and of the components it deletes) are retrieved and committed to the
 * release-relay-snapshots branch at <REQUEST_ID>/<environment>/<attempt or run id>/ (manifest.json + metadata/,
 * Metadata API format). {"snapshot":false} or selfUpdate skips it; a failed snapshot never blocks the deploy.
 * MODE=rollback deploys one back: options {"snapshotPath":"REL-00042/prod/<id>"} (else the latest for that release
 * and environment) and {"tests":[...]}.
 *
 * Every input arrives as an environment variable and is validated here. Commands run with
 * execFileSync and argument arrays, never through a shell, so input can't inject commands.
 */
'use strict';

const { execFileSync } = require('child_process');
const crypto = require('crypto');
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

/** Output buffer for git and Salesforce CLI calls (Node's default, 1 MB, is too small for a whole org). */
const CLI_BUFFER = 512 * 1024 * 1024;

function run(cmd, args, options = {}) {
    // A big buffer: git and the CLI list every file of a whole-org branch, far past Node's 1 MB default.
    const out = execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'], maxBuffer: CLI_BUFFER, ...options });
    return out == null ? '' : String(out).trim();
}

function summary(markdown) {
    if (env.GITHUB_STEP_SUMMARY) {
        fs.appendFileSync(env.GITHUB_STEP_SUMMARY, markdown + '\n');
    } else {
        console.log(markdown);
    }
}

// ---------- run summary (version 25) ----------

const SUMMARY_OK = /^(passed|deployed|merged|succeeded|created|raised|opened|done|ok|up to date|no changes)$/i;
const SUMMARY_BAD = /^(failed|error|conflict|conflicts|cancelled|blocked)$/i;
const SUMMARY_COMPONENTS = 30;
const SECRET_ENV_RE = /(TOKEN|SECRET|PASSWORD|PASSWD|KEY|AUTH|SFDX_URL|JWT|CREDENTIAL|PRIVATE)/i;

/** Text for the summary: one line, no HTML, at most max characters. */
function summaryText(value, max = 300) {
    const text = String(value === null || value === undefined ? '' : value).replace(/[\r\n\t]+/g, ' ').trim();
    const clipped = text.length > max ? text.slice(0, max - 1) + '…' : text;
    return clipped.replace(/[<>]/g, (c) => (c === '<' ? '&lt;' : '&gt;')).replace(/\|/g, '\\|').replace(/`/g, "'");
}

/** Every value the summary must never show: the values file's values and secret-like environment variables. */
function summarySecrets() {
    const out = new Set();
    for (const perEnv of Object.values((relayValues && relayValues.values) || {})) {
        for (const value of Object.values(perEnv || {})) {
            if (typeof value === 'string' && value.trim().length >= 3) {
                out.add(value.trim());
            }
        }
    }
    for (const [name, value] of Object.entries(env)) {
        if (SECRET_ENV_RE.test(name) && typeof value === 'string' && value.trim().length >= 6) {
            out.add(value.trim());
        }
    }
    return [...out].sort((a, b) => b.length - a.length);
}

/** The markdown with every secret and value-file value replaced by •••. */
function redactSummary(markdown) {
    let out = markdown;
    for (const secret of summarySecrets()) {
        out = out.split(secret).join('•••');
    }
    return out;
}

/** Type:Name entries the run was given (not a promotion's merge commits). */
function summaryList(name) {
    if (name === 'COMPONENTS' && mode === 'promote') {
        return [];
    }
    return (input(name) || '').split(',').map((x) => x.trim()).filter((x) => /^[A-Za-z]+:.+/.test(x));
}

/** The readable summary of one step's result (markdown). Never shows secrets or values from the values file. */
function resultSummary(result) {
    const status = String(result.status || 'Unknown');
    const emoji = SUMMARY_OK.test(status) ? '✅' : SUMMARY_BAD.test(status) ? '❌' : /^skipped$/i.test(status) ? '⏭️' : 'ℹ️';
    const id = String(result.request || requestId);
    const shortTitle = title.startsWith(id + ':') ? title.slice(id.length + 1).trim() : title; // the hub's titles start with the id
    const lines = [`### ${emoji} Release Relay ${summaryText(id, 80)}` + (shortTitle ? ` · ${summaryText(shortTitle, 200)}` : ''), ''];
    const row = (label, value) => {
        if (value !== null && value !== undefined && String(value).trim() !== '') {
            lines.push(`| ${label} | ${summaryText(value)} |`);
        }
    };
    lines.push('| | |', '|---|---|');
    row('Step', `${result.step}${mode ? ' (' + mode + ')' : ''}: ${emoji} ${status}`);
    const from = [sourceEnv, branch].filter(Boolean).join(' · ');
    const to = [options.label || '', targetEnv, target].filter(Boolean).join(' · ');
    if (from || to) {
        row('Source → target', `${from || '—'} → ${to || '—'}`);
    }
    row('Raised by', typeof options.by === 'string' ? options.by : '');
    row('Approved by', typeof options.approvedBy === 'string' ? options.approvedBy : '');
    const components = summaryList('COMPONENTS');
    const deletions = Array.isArray(result.deleted) ? result.deleted
        : Array.isArray(result.deletedList) ? result.deletedList : summaryList('DELETIONS');
    if (components.length) {
        row('Components', String(components.length));
    } else if (typeof result.changed === 'number') {
        row('Files sent', String(result.changed));
    }
    row('Deletions', deletions.length || (typeof result.deleted === 'number' ? result.deleted : '') || '');
    if (result.testLevel || result.testsRun) {
        row('Tests', `${Number(result.testsRun || 0)} run` + (result.testLevel ? ` · ${result.testLevel}` : ''));
    }
    if (result.step === 'scan' || typeof result.blocking === 'number') {
        row('Scan findings', `${Number(result.total || 0)} found, ${Number(result.blocking || 0)} blocking`
            + (result.thresholdLabel ? ` (${result.thresholdLabel} or above)` : ''));
    }
    row('Deploy id', result.deployId || result.validationId || '');
    row('Message', result.message ? summaryText(result.message, 600) : '');
    if (typeof options.hubUrl === 'string' && /^https:\/\/[^\s"'<>]+$/.test(options.hubUrl)) {
        lines.push('', `[Open in Release Relay](${options.hubUrl})`);
    }
    if (components.length) {
        lines.push('', `<details><summary>Components (${components.length})</summary>`, '');
        components.slice(0, SUMMARY_COMPONENTS).forEach((c) => lines.push(`- ${summaryText(c, 200)}`));
        if (components.length > SUMMARY_COMPONENTS) {
            lines.push(`- … and ${components.length - SUMMARY_COMPONENTS} more`);
        }
        lines.push('', '</details>');
    }
    return lines.join('\n') + '\n';
}

/** Adds a step's result to the run's summary page; a problem here never fails the step. */
function summarizeResult(result) {
    try {
        summary(redactSummary(resultSummary(result)));
    } catch (e) {
        console.log(`The run summary couldn't be written (${String(e.message).slice(0, 200)}).`);
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
const SNAPSHOT_BRANCH = 'release-relay-snapshots';
const SHA_RE = /^[0-9a-f]{40}$/;
const SCAN_EXT = ['.cls', '.trigger', '.page', '.component', '.cmp', '.js', '.html', '.flow-meta.xml'];
const TEST_LEVELS = ['NoTestRun', 'RunLocalTests', 'RunAllTestsInOrg'];
const WORK_DIR = '.relay';
const EXCLUDE_FILE = '.relay/exclude';
const VALUES_FILE = '.relay/values.json';
const GATES_FILE = '.relay/gates.json';
// Release Relay's own components, by exact name (never a prefix: your own Rly* class is deployed as usual). Globs
// relative to SOURCE_PATH; a glob matching a folder covers everything in it. "only-labels:<names>" excludes a labels
// file only when every label in it matches. Lines in .relay/exclude are added to this list.
const BUILT_IN_EXCLUDES = [ // RLY-EXCLUDES: generated from the hub package.xml, exact names only
    'objects/RLY_Git_Connection__c', 'objects/RLY_Notification__c', 'objects/RLY_Manual_Step__c',
    'objects/RLY_Manual_Step_Run__c', 'objects/RLY_Org__c', 'objects/RLY_Release_Event__c',
    'objects/User/fields/RLY_Slack_Member_Id__c.field-meta.xml', 'classes/RlyApprovalService.cls*',
    'classes/RlyApprovalServiceTest.cls*', 'classes/RlyAzureRepos.cls*', 'classes/RlyBitbucket.cls*',
    'classes/RlyChangeFinder.cls*', 'classes/RlyChangesController.cls*', 'classes/RlyChangesControllerTest.cls*',
    'classes/RlyCheckReader.cls*', 'classes/RlyCheckReaderTest.cls*', 'classes/RlyConflictResult.cls*',
    'classes/RlyConflictRules.cls*', 'classes/RlyConflictService.cls*', 'classes/RlyConflictServiceTest.cls*',
    'classes/RlyConsumerKeyTest.cls*', 'classes/RlyDeployReader.cls*', 'classes/RlyDeployReaderTest.cls*',
    'classes/RlyFlowScenario.cls*', 'classes/RlyGit.cls*', 'classes/RlyGitAdvice.cls*',
    'classes/RlyGitAdviceTest.cls*', 'classes/RlyPullRequestCloseTest.cls*', 'classes/RlyGitCheck.cls*',
    'classes/RlyGitFile.cls*', 'classes/RlyGitHub.cls*', 'classes/RlyGitLab.cls*', 'classes/RlyGitProvidersTest.cls*',
    'classes/RlyGitRequest.cls*', 'classes/RlyGitValidator.cls*', 'classes/RlyHotfix.cls*',
    'classes/RlyHotfixTest.cls*', 'classes/RlyHttpMock.cls*', 'classes/RlyMetadata.cls*',
    'classes/RlyMetadataMock.cls*', 'classes/RlyOrgCheck.cls*', 'classes/RlyOrgCheckMock.cls*',
    'classes/RlyOrgController.cls*', 'classes/RlyOrgControllerTest.cls*', 'classes/RlyOrgSession.cls*',
    'classes/RlyOrgSessionTest.cls*', 'classes/RlyOrgValidator.cls*', 'classes/RlyPipelineFiles.cls*',
    'classes/RlyPipelineFilesTest.cls*', 'classes/RlyPipelineOptions.cls*', 'classes/RlyPipelineRun.cls*',
    'classes/RlyPipelineUpdate.cls*', 'classes/RlyPullRequestClose.cls*', 'classes/RlyRaiseRoute.cls*',
    'classes/RlyRaiseRules.cls*', 'classes/RlyRaiseService.cls*', 'classes/RlyRaiseServiceTest.cls*',
    'classes/RlyReleaseException.cls*', 'classes/RlyReleaseStart.cls*', 'classes/RlyReleaseStore.cls*',
    'classes/RlyReleaseTestData.cls*', 'classes/RlyReleasesController.cls*', 'classes/RlyReleasesFilterTest.cls*',
    'classes/RlyReleaseQuery.cls*', 'classes/RlyReleaseRows.cls*', 'classes/RlyRetrieve.cls*',
    'classes/RlyRouteController.cls*', 'classes/RlyRouteControllerTest.cls*', 'classes/RlyRouteRules.cls*',
    'classes/RlySignInAdvice.cls*', 'classes/RlySlack.cls*', 'classes/RlySlackController.cls*',
    'classes/RlySlackMessage.cls*', 'classes/RlySlackRules.cls*', 'classes/RlySlackTest.cls*',
    'classes/RlySoapClient.cls*', 'classes/RlyStatusReader.cls*', 'classes/RlyStatusReaderTest.cls*',
    'classes/RlyTestData.cls*', 'classes/RlyTestRule.cls*', 'classes/RlyApprover.cls*',
    'classes/RlyApprovalRuns.cls*', 'classes/RlySlackApi.cls*', 'classes/RlySlackCard.cls*',
    'classes/RlyReleasePhase.cls*', 'classes/RlySlackDelivery.cls*', 'classes/RlySlackDirectory.cls*',
    'classes/RlySlackSignature.cls*', 'classes/RlySlackAction.cls*', 'classes/RlySlackActions.cls*',
    'classes/RlySlackPayload.cls*', 'classes/RlySlackReply.cls*', 'classes/RlyGitName.cls*',
    'classes/RlySlackActionsTest.cls*', 'classes/RlyApprovalRunsTest.cls*', 'classes/RlyBackPromote.cls*',
    'classes/RlyBackPromoteQueue.cls*', 'classes/RlyBackPromoteRun.cls*', 'classes/RlyBackPromoteSummary.cls*',
    'classes/RlyCarried.cls*', 'classes/RlyDeletionFinder.cls*', 'classes/RlyDeletionFinderTest.cls*',
    'classes/RlyDeletionPaths.cls*', 'classes/RlyDeletionRules.cls*', 'classes/RlyDeletions.cls*',
    'classes/RlyOrgSettings.cls*', 'classes/RlyPromoteController.cls*', 'classes/RlyPromoteStore.cls*',
    'classes/RlyPromotion.cls*', 'classes/RlyReleaseEffects.cls*', 'classes/RlyReleaseLinks.cls*',
    'classes/RlySlackCardText.cls*', 'classes/RlyTwoApprovers.cls*', 'classes/RlyPromoteTest.cls*',
    'classes/RlyBackPromoteTest.cls*', 'classes/RlyTwoApproversTest.cls*', 'classes/RlyManualSteps.cls*',
    'classes/RlyManualStepStore.cls*', 'classes/RlyManualStepRules.cls*', 'classes/RlyManualStepRuns.cls*',
    'classes/RlyManualStepGate.cls*', 'classes/RlyManualStepCheck.cls*', 'classes/RlyManualStepBoard.cls*',
    'classes/RlyManualStepEdit.cls*', 'classes/RlyManualStepController.cls*', 'classes/RlyManualStepsTest.cls*',
    'classes/RlyManualStepGateTest.cls*', 'classes/RlyManualStepScope.cls*', 'classes/RlyManualStepText.cls*',
    'classes/RlyBackPromoteSteps.cls*', 'classes/RlyApprovalRuleOrg.cls*', 'classes/RlyApprovalRules.cls*',
    'classes/RlyApprovalRulesTest.cls*', 'classes/RlyApprovalWords.cls*', 'classes/RlyAutoApproval.cls*',
    'classes/RlyEvidenceController.cls*', 'classes/RlyEvidenceHtml.cls*', 'classes/RlyEvidenceTables.cls*',
    'classes/RlyEvidenceTest.cls*', 'classes/RlyEvidenceText.cls*', 'classes/RlyFlowActivation.cls*',
    'classes/RlyFlowActivationTest.cls*', 'classes/RlyFlowChoices.cls*', 'classes/RlyFlowResults.cls*',
    'classes/RlyFlowVersions.cls*', 'classes/RlyHubGuard.cls*', 'classes/RlyHubGuardTest.cls*',
    'classes/RlyReleaseHistory.cls*', 'classes/RlyReleaseLog.cls*', 'classes/RlyReleaseOutcomes.cls*',
    'classes/RlyReleaseTransitions.cls*', 'classes/RlySandboxCopy.cls*', 'classes/RlyBotToken.cls*',
    'classes/RlySetupStatus.cls*', 'classes/RlySetupStatusTest.cls*', 'classes/RlyManualOnly.cls*',
    'classes/RlyManualOnlyTest.cls*', 'lwc/rlyApprovalQueue', 'lwc/rlyManualSteps', 'lwc/rlySetupWizard',
    'lwc/rlyChoiceChips', 'lwc/rlyMergeConflicts', 'lwc/rlyPipeline', 'lwc/rlyPromote', 'lwc/rlyReleaseBuilder',
    'lwc/rlyReleaseGuide', 'lwc/rlyReleaseTracker', 'lwc/rlyReleaseView', 'tabs/RLY_Approvals.tab-meta.xml',
    'tabs/RLY_My_Releases.tab-meta.xml', 'tabs/RLY_New_Release.tab-meta.xml', 'tabs/RLY_Pipeline.tab-meta.xml',
    'tabs/RLY_Promote.tab-meta.xml', 'tabs/RLY_Relay_Guide.tab-meta.xml', 'applications/Release_Relay.app-meta.xml',
    'customPermissions/RLY_Admin.customPermission-meta.xml',
    'customPermissions/RLY_Deploy_Team.customPermission-meta.xml',
    'customPermissions/RLY_Hotfix.customPermission-meta.xml', 'permissionsets/RLY_Admin.permissionset-meta.xml',
    'permissionsets/RLY_Approver.permissionset-meta.xml', 'permissionsets/RLY_Deploy_Team.permissionset-meta.xml',
    'permissionsets/RLY_Developer.permissionset-meta.xml', 'permissionsets/RLY_Slack_Site.permissionset-meta.xml',
    'staticresources/RLY_Guide_Setup.*', 'staticresources/RLY_Guide_Setup', 'staticresources/RLY_Guide_Shots.*',
    'staticresources/RLY_Guide_Shots', 'staticresources/RLY_Pipeline_Azure.*', 'staticresources/RLY_Pipeline_Azure',
    'staticresources/RLY_Pipeline_Bitbucket.*', 'staticresources/RLY_Pipeline_Bitbucket',
    'staticresources/RLY_Pipeline_GitHub.*', 'staticresources/RLY_Pipeline_GitHub',
    'staticresources/RLY_Pipeline_GitLab.*', 'staticresources/RLY_Pipeline_GitLab',
    'staticresources/RLY_Pipeline_Script.*', 'staticresources/RLY_Pipeline_Script',
    'externalCredentials/RLY_Slack.externalCredential-meta.xml',
    'namedCredentials/RLY_Slack.namedCredential-meta.xml',
    'labels/CustomLabels.labels-meta.xml only-labels:RLY_App_Name', 'objects/RLY_Release__c',
    'objects/RLY_Release_Item__c'
];
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
    if (mode === 'data') {
        // Data sets (version 24): id DAT-<13 digits>; the load needs TARGET_ENVIRONMENT.
        if (!DATA_ID_RE.test(requestId)) { fail('REQUEST_ID must look like DAT-1762400000000 for data.'); }
        if (!/^[A-Za-z0-9._-]{1,80}$/.test(targetEnv)) { fail('TARGET_ENVIRONMENT (the org to load) must be an environment name.'); }
        if (sourceEnv && !/^[A-Za-z0-9._-]{1,80}$/.test(sourceEnv)) { fail('ENVIRONMENT (the org to read) must be an environment name.'); }
        if (!['github', 'gitlab', 'bitbucket', 'azure'].includes(PROVIDER)) { fail('RELAY_PROVIDER must be github, gitlab, bitbucket or azure.'); }
        return;
    }
    if (mode === 'drift' || mode === 'routediff') {
        // Sync status (version 23): id SYN-<13 digits>; drift reads TARGET, routediff the branches in options.route.
        if (!SYNC_ID_RE.test(requestId)) { fail(`REQUEST_ID must look like SYN-1762400000000 for ${mode}.`); }
        if (mode === 'drift' && (!REF_RE.test(target) || target.includes('..') || target === RESULTS_BRANCH || target === SNAPSHOT_BRANCH)) { fail(`Target "${target}" isn't a valid branch.`); }
        if (!/^[A-Za-z0-9_./-]+$/.test(sourcePath()) || sourcePath().includes('..')) { fail('SOURCE_PATH is invalid.'); }
        if (!['github', 'gitlab', 'bitbucket', 'azure'].includes(PROVIDER)) { fail('RELAY_PROVIDER must be github, gitlab, bitbucket or azure.'); }
        return;
    }
    if (mode === 'compare') {
        // A compare (version 22) has no release: its id is CMP-<13 digits> (SYN-<13 digits> for a full compare from the
        // Sync status tab, version 23), and it reads TARGET only (BRANCH isn't used).
        const idOk = COMPARE_ID_RE.test(requestId) || (options.full === true && SYNC_ID_RE.test(requestId));
        if (!idOk) { fail('REQUEST_ID must look like CMP-1762400000000 for a compare.'); }
        if (options.syncId !== undefined && !SYNC_ID_RE.test(String(options.syncId))) { fail('options.syncId must look like SYN-1762400000000.'); }
        if (!REF_RE.test(target) || target.includes('..') || target === RESULTS_BRANCH || target === SNAPSHOT_BRANCH) { fail(`Target "${target}" isn't a valid target branch.`); }
        if (!/^[A-Za-z0-9_./-]+$/.test(sourcePath()) || sourcePath().includes('..')) { fail('SOURCE_PATH is invalid.'); }
        if (!['github', 'gitlab', 'bitbucket', 'azure'].includes(PROVIDER)) { fail('RELAY_PROVIDER must be github, gitlab, bitbucket or azure.'); }
        return;
    }
    if (!/^REL-\d{5,}$/.test(requestId)) { fail('REQUEST_ID must look like REL-00042.'); }
    if (!['org', 'branch', 'promote', 'hub', 'resolve', 'check', 'merge', 'sync', 'rollback'].includes(mode)) { fail('MODE must be org, branch, promote, hub, resolve, check, merge, sync, rollback or compare.'); }
    if (mode === 'rollback') {
        // A rollback works on an org and the snapshots branch only: BRANCH and TARGET aren't used.
        if (!/^[A-Za-z0-9._-]{1,80}$/.test(targetEnv)) { fail('TARGET_ENVIRONMENT (the org to roll back) must be an environment name.'); }
    } else if (mode === 'sync') {
        // A back promote takes the hub's production branch (any branch name) into a back-promote org's branch.
        if (!REF_RE.test(branch) || branch.includes('..')) { fail(`Branch "${branch}" isn't a valid source branch.`); }
    } else if (!BRANCH_RE.test(branch)) { fail(`Branch "${branch}" must look like feature/short-name.`); }
    // Push to the org (version 23): sync with picked paths from an org's own branch to that org (BRANCH = TARGET).
    const pushToOrg = mode === 'sync' && Array.isArray(options.paths) && options.paths.length > 0 && target === branch;
    if (mode !== 'rollback' && (!REF_RE.test(target) || target.includes('..') || (target === branch && !pushToOrg) || target === RESULTS_BRANCH || target === SNAPSHOT_BRANCH)) { fail(`Target "${target}" isn't a valid target branch.`); }
    if (!/^[A-Za-z0-9_./-]+$/.test(sourcePath()) || sourcePath().includes('..')) { fail('SOURCE_PATH is invalid.'); }
    if (!['github', 'gitlab', 'bitbucket', 'azure'].includes(PROVIDER)) { fail('RELAY_PROVIDER must be github, gitlab, bitbucket or azure.'); }
}

function checkAllowedTarget() {
    if (options.hub === true) {
        return; // the Release Relay hub only raises (and back promotes) along its registered route
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
        return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: CLI_BUFFER }).trim();
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
    if (['validate', 'deploy', 'sync'].includes(name)) {
        result.excluded = deployExcluded.slice(0, 1000);
        result.selfUpdate = selfUpdate();
        if (!result.values) {
            result.values = deployValues || { replaced: 0, files: [], hash: '' };
        }
    }
    if (['validate', 'scan'].includes(name) && !result.gates) {
        result.gates = gatesResult(relayGates, []);
    }
    const json = JSON.stringify(result, null, 1);
    summarizeResult(result);
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

/** git with text on stdin and extra environment variables (a private index), returning stdout. */
function gitWith(args, extraEnv, inputText) {
    const out = execFileSync('git', args, { encoding: 'utf8', input: inputText === undefined ? '' : inputText,
        env: { ...process.env, ...extraEnv }, stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 });
    return String(out || '').trim();
}

/** Fetches only the tip of a branch (an orphan branch such as the snapshots, whose history isn't needed). */
function fetchTip(name) {
    git(['fetch', '--no-tags', '--depth=1', 'origin', `+refs/heads/${name}:refs/remotes/origin/${name}`]);
}

/**
 * Commits files to a branch without checking it out: a private index starts from the branch's tip, drops
 * everything under prefix, adds the files ({ rel: path in the branch, abs: local file }), and the commit is
 * pushed. Another run pushing first is retried on the new tip. Used for the snapshots, where checking out
 * every earlier snapshot would cost time.
 */
function commitFilesToBranch(branchName, prefix, files, message) {
    const who = { GIT_AUTHOR_NAME: 'Release Relay', GIT_AUTHOR_EMAIL: 'release-relay@users.noreply.local',
        GIT_COMMITTER_NAME: 'Release Relay', GIT_COMMITTER_EMAIL: 'release-relay@users.noreply.local' };
    let lastError = null;
    for (let attempt = 1; attempt <= 5; attempt++) {
        const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-index-'));
        const genv = { ...who, GIT_INDEX_FILE: path.join(dir, 'index') };
        try {
            let parent = null;
            if (remoteBranchExists(branchName)) {
                fetchTip(branchName);
                parent = git(['rev-parse', `refs/remotes/origin/${branchName}`]);
                gitWith(['read-tree', parent], genv);
                const old = gitWith(['ls-files', '-z', '--', prefix], genv).replace(/\0+$/, '');
                if (old) {
                    gitWith(['update-index', '--force-remove', '-z', '--stdin'], genv, old + '\0');
                }
            } else {
                gitWith(['read-tree', '--empty'], genv);
            }
            if (files.length) {
                const shas = gitWith(['hash-object', '-w', '--stdin-paths'], genv, files.map((f) => f.abs).join('\n') + '\n').split('\n');
                if (shas.length !== files.length) {
                    throw new Error('git hash-object returned an unexpected number of objects.');
                }
                gitWith(['update-index', '--add', '--index-info'], genv,
                    files.map((f, i) => `100644 ${shas[i]}\t${f.rel}`).join('\n') + '\n');
            }
            const tree = gitWith(['write-tree'], genv);
            const commit = gitWith(['commit-tree', tree, ...(parent ? ['-p', parent] : []), '-m', message], genv);
            gitWith(['push', '-q', 'origin', `${commit}:refs/heads/${branchName}`], {});
            return commit;
        } catch (e) {
            lastError = e;
            console.log(`Saving to ${branchName} failed (attempt ${attempt}); retrying.`);
        } finally {
            fs.rmSync(dir, { recursive: true, force: true });
        }
    }
    throw new Error(`Couldn't push to ${branchName}: ${String((lastError && (lastError.stderr || lastError.message)) || lastError).trim().slice(0, 300)}`);
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
        return JSON.parse(fs.readFileSync('sfdx-project.json', 'utf8')).sourceApiVersion || '65.0';
    } catch (e) {
        return '65.0';
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

// ---------- Release Relay's own metadata: the exclude list ----------

let excludeRules = [];
let excludeSource = '';
let deployExcluded = []; // the files the last buildDeployment left out, for the result
const selfUpdate = () => options.selfUpdate === true;

function globRegex(glob) {
    let re = '';
    for (let i = 0; i < glob.length; i++) {
        const c = glob[i];
        if (c === '*' && glob[i + 1] === '*') {
            re += '.*';
            i++;
        } else if (c === '*') {
            re += '[^/]*';
        } else if (c === '?') {
            re += '[^/]';
        } else {
            re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
        }
    }
    return new RegExp('^' + re + '$');
}

/** Reads .relay/exclude from the pipeline's commit, else the defaults. */
function loadExcludes() {
    let lines = BUILT_IN_EXCLUDES.slice();
    excludeSource = "Release Relay's built-in list";
    try {
        const text = pipelineFile(EXCLUDE_FILE);
        if (text !== null) {
            lines = lines.concat(text.split(/\r?\n/));
            excludeSource = "Release Relay's built-in list and " + EXCLUDE_FILE;
        }
    } catch (e) {
        // unreadable: the built-in list alone
    }
    excludeRules = [];
    for (const raw of lines) {
        const line = raw.replace(/(^|\s)#.*$/, '').trim();
        if (!line) {
            continue;
        }
        const [glob, ...mods] = line.split(/\s+/);
        const rule = { glob: glob.replace(/^\/+/, '').replace(/\/+$/, ''), labels: null };
        for (const m of mods) {
            if (m.startsWith('only-labels:') && m.length > 12) {
                rule.labels = globRegex(m.slice(12));
            } else {
                console.log(`::warning::${excludeSource}: "${m}" isn't understood; "${rule.glob}" is excluded without it.`);
            }
        }
        if (rule.glob) {
            rule.re = globRegex(rule.glob);
            excludeRules.push(rule);
        }
    }
}

/** True when every label in a labels file (at head, or at base when deleted) matches the rule's name glob. */
function labelsAllMatch(file, base, nameRe) {
    const text = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : gitQuiet(['show', `${base}:${file}`]);
    const names = [...String(text || '').matchAll(/<fullName>\s*([^<]*?)\s*<\/fullName>/g)].map((m) => m[1]);
    return names.length > 0 && names.every((n) => nameRe.test(n));
}

/** Whether a changed repo file is Release Relay's own metadata, which normal releases never deploy or delete. */
function isExcluded(file, base) {
    if (selfUpdate()) {
        return false;
    }
    const rel = path.relative(sourcePath(), file).split(path.sep).join('/');
    if (!rel || rel.startsWith('..')) {
        return false;
    }
    return excludeHit(rel, (nameRe) => labelsAllMatch(file, base, nameRe));
}

/** Whether a path relative to SOURCE_PATH (or a folder above it) matches the exclude list; labelsCheck decides only-labels rules. */
function excludeHit(rel, labelsCheck) {
    const parts = rel.split('/');
    return excludeRules.some((rule) => {
        let hit = false;
        for (let i = parts.length; i >= 1 && !hit; i--) {
            hit = rule.re.test(parts.slice(0, i).join('/'));
        }
        return hit && (!rule.labels || labelsCheck(rule.labels));
    });
}

/** Source paths (relative to SOURCE_PATH) a Type:Name component would have, for matching the exclude list. */
function componentRelPaths(type, name) {
    if (FILE_TYPES[type]) {
        return [`${FILE_TYPES[type][0]}/${name}${FILE_TYPES[type][1]}`];
    }
    if (FOLDER_TYPES[type]) {
        return [`${FOLDER_TYPES[type]}/${name}`];
    }
    if (CHILD_TYPES[type]) {
        const dot = name.indexOf('.');
        return dot < 1 ? [] : [`objects/${name.slice(0, dot)}/${CHILD_TYPES[type][0]}/${name.slice(dot + 1)}${CHILD_TYPES[type][1]}`];
    }
    const other = {
        StaticResource: [`staticresources/${name}.resource`, `staticresources/${name}`],
        CustomPermission: [`customPermissions/${name}.customPermission-meta.xml`],
        CustomApplication: [`applications/${name}.app-meta.xml`],
        NamedCredential: [`namedCredentials/${name}.namedCredential-meta.xml`],
        ExternalCredential: [`externalCredentials/${name}.externalCredential-meta.xml`]
    };
    return other[type] || [];
}

/** Whether a Type:Name component is Release Relay's own (a rollback never touches those, even for selfUpdate). */
function componentExcluded(type, name) {
    if (type === 'CustomLabel') {
        return excludeRules.some((rule) => rule.labels && rule.labels.test(name));
    }
    return componentRelPaths(type, name).some((rel) => excludeHit(rel, () => false));
}

// The exclude list also goes into .forceignore for the run (restored on exit), so the CLI never picks an excluded
// file up as part of another component (an RLY_ field when the User object itself is deployed).
let forceIgnoreOriginal;
function applyForceIgnore() {
    const globs = excludeRules.filter((r) => !r.labels).map((r) => `${sourcePath()}/${r.glob}`);
    if (selfUpdate() || !globs.length || forceIgnoreOriginal !== undefined) {
        return;
    }
    forceIgnoreOriginal = fs.existsSync('.forceignore') ? fs.readFileSync('.forceignore', 'utf8') : null;
    fs.writeFileSync('.forceignore', (forceIgnoreOriginal ? forceIgnoreOriginal.replace(/\n?$/, '\n') : '')
        + '# Release Relay exclude list (this run only)\n' + globs.join('\n') + '\n');
    process.on('exit', () => {
        try {
            if (forceIgnoreOriginal === null) {
                fs.rmSync('.forceignore', { force: true });
            } else {
                fs.writeFileSync('.forceignore', forceIgnoreOriginal);
            }
        } catch (e) {
            // the job ends anyway
        }
    });
}

/** A sentence for result messages when files were left out, or ''. */
/** Why a release whose every changed file is on the exclude list deploys nothing: it fails instead of passing. */
function nothingLeftMessage() {
    const names = deployExcluded.slice(0, 5).map((f) => path.basename(f)).join(', ');
    return `Nothing was deployed: all ${deployExcluded.length} changed file(s) are on Release Relay's exclude list (${names}`
        + `${deployExcluded.length > 5 ? ', ...' : ''}). Release Relay's own components are only deployed by a hub update.`;
}

function excludedNote() {
    return deployExcluded.length ? ` ${deployExcluded.length} Release Relay file(s) were left out (exclude list).` : '';
}

// ---------- files read from the pipeline's own commit ----------

/** The commit this run started on (the default branch): its .relay files count, never a release branch's. */
function pipelineSha() {
    for (const name of ['RELAY_PIPELINE_SHA', 'GITHUB_SHA', 'CI_COMMIT_SHA', 'BITBUCKET_COMMIT', 'BUILD_SOURCEVERSION']) {
        const value = (env[name] || '').trim();
        if (SHA_RE.test(value)) {
            return value;
        }
    }
    return '';
}

let pipelineCommitReady;

/**
 * A file's text at the pipeline's commit, or null when it isn't there. Read with git show, because some jobs check
 * out the release branch or the merge commit; when the commit can't be read, the job's own checkout (which starts
 * on the pipeline's commit) is used.
 */
function pipelineFile(rel) {
    const sha = pipelineSha();
    if (sha) {
        if (pipelineCommitReady === undefined) {
            const has = () => gitQuiet(['cat-file', '-e', sha + '^{commit}']) !== null;
            pipelineCommitReady = has() || (gitQuiet(['fetch', '--no-tags', '--depth=1', 'origin', sha]) !== null && has());
        }
        if (pipelineCommitReady) {
            return gitQuiet(['show', `${sha}:${rel}`]);
        }
    }
    return fs.existsSync(rel) ? fs.readFileSync(rel, 'utf8') : null;
}

// ---------- per-org values (.relay/values.json) ----------

const PLACEHOLDER_RE = /\{\{relay:([A-Z0-9_]{1,60})\}\}/g;
const VALUE_NAME_RE = /^[A-Z0-9_]{1,60}$/;
const MIN_REVERSE_LENGTH = 6;

let relayValues = { values: {}, warnings: [], error: '', present: false };
let deployValues = null; // the last deployment's substitutions, for the result

/**
 * Parses .relay/values.json: { "values": { "NAME": { "<environment>": "value" } } }. Keys starting with "_" are
 * ignored at every level. Returns { values, warnings, error, present }.
 */
function parseValues(text) {
    const out = { values: {}, warnings: [], error: '', present: false };
    if (text === null || text === undefined || !String(text).trim()) {
        return out;
    }
    out.present = true;
    let json;
    try {
        json = JSON.parse(text);
    } catch (e) {
        out.error = `${VALUES_FILE} isn't valid JSON (${String(e.message).slice(0, 200)}).`;
        return out;
    }
    if (!json || typeof json !== 'object' || Array.isArray(json)) {
        out.error = `${VALUES_FILE} must hold a JSON object.`;
        return out;
    }
    const values = json.values;
    if (values === undefined || values === null) {
        return out;
    }
    if (typeof values !== 'object' || Array.isArray(values)) {
        out.error = `"values" in ${VALUES_FILE} must be an object.`;
        return out;
    }
    for (const [name, perEnv] of Object.entries(values)) {
        if (name.startsWith('_')) {
            continue;
        }
        if (!VALUE_NAME_RE.test(name)) {
            out.warnings.push(`"${name.slice(0, 80)}" in ${VALUES_FILE} isn't a valid name (A-Z, 0-9 and _, up to 60 characters), so it's ignored.`);
            continue;
        }
        if (!perEnv || typeof perEnv !== 'object' || Array.isArray(perEnv)) {
            out.warnings.push(`${name} in ${VALUES_FILE} must map environment names to values, so it's ignored.`);
            continue;
        }
        const envs = {};
        for (const [envName, value] of Object.entries(perEnv)) {
            if (envName.startsWith('_')) {
                continue;
            }
            if (typeof value !== 'string') {
                out.warnings.push(`${name} for ${envName.slice(0, 80)} in ${VALUES_FILE} isn't text, so it's ignored.`);
                continue;
            }
            envs[envName] = value;
        }
        out.values[name] = envs;
    }
    return out;
}

/**
 * Replaces {{relay:NAME}} with NAME's value for envName. Returns { text, count, missing: [names], used: [names] };
 * a placeholder without a value stays as it is and is listed in missing.
 */
function substituteText(text, values, envName) {
    let count = 0;
    const missing = new Set();
    const used = new Set();
    const out = text.replace(PLACEHOLDER_RE, (whole, name) => {
        const perEnv = values[name];
        if (!perEnv || !Object.prototype.hasOwnProperty.call(perEnv, envName)) {
            missing.add(name);
            return whole;
        }
        count++;
        used.add(name);
        return perEnv[envName];
    });
    return { text: out, count, missing: [...missing], used: [...used] };
}

/**
 * The values to turn back into placeholders for envName, longest first. Values shorter than 6 characters are
 * never reverse-replaced (they could match unrelated text), and a value two names share goes to the first name.
 * Returns { pairs: [{ name, value }], warnings }.
 */
function reversePairs(values, envName) {
    const warnings = [];
    const byValue = new Map();
    for (const name of Object.keys(values).sort()) {
        const value = values[name][envName];
        if (typeof value !== 'string' || !value) {
            continue;
        }
        if (value.length < MIN_REVERSE_LENGTH) {
            warnings.push(`${name}'s value for ${envName} is shorter than ${MIN_REVERSE_LENGTH} characters, so it isn't turned back into {{relay:${name}}} in retrieved files.`);
            continue;
        }
        if (byValue.has(value)) {
            warnings.push(`${name} and ${byValue.get(value)} have the same value for ${envName}; retrieved files get {{relay:${byValue.get(value)}}}.`);
            continue;
        }
        byValue.set(value, name);
    }
    const pairs = [...byValue.entries()].map(([value, name]) => ({ name, value }))
        .sort((a, b) => b.value.length - a.value.length || (a.name < b.name ? -1 : 1));
    return { pairs, warnings };
}

function escapeRegex(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Replaces exact occurrences of the pairs' values with {{relay:NAME}}, in one pass (longest value first at each
 * position), leaving existing placeholders alone. Returns { text, count }.
 */
function tokenizeText(text, pairs) {
    if (!pairs.length) {
        return { text, count: 0 };
    }
    const byValue = new Map(pairs.map((p) => [p.value, p.name]));
    const re = new RegExp('(\\{\\{relay:[A-Z0-9_]{1,60}\\}\\})|' + pairs.map((p) => escapeRegex(p.value)).join('|'), 'g');
    let count = 0;
    const out = text.replace(re, (m, placeholder) => {
        if (placeholder) {
            return m;
        }
        count++;
        return `{{relay:${byValue.get(m)}}}`;
    });
    return { text: out, count };
}

/** A file's text, or null for binary files, files that aren't UTF-8 and files over 20 MB (left as they are). */
function readText(file) {
    try {
        const buf = fs.readFileSync(file);
        if (buf.length > 20 * 1024 * 1024 || buf.subarray(0, 8000).includes(0)) {
            return null;
        }
        const text = buf.toString('utf8');
        return Buffer.from(text, 'utf8').equals(buf) ? text : null;
    } catch (e) {
        return null;
    }
}

function relToSource(file) {
    return path.relative(sourcePath(), file).split(path.sep).join('/');
}

/** Every file a deployment of these source entries (files or bundle folders) sends, excluded files left out. */
function deploymentFiles(sources) {
    const files = new Set();
    const addTree = (p) => {
        if (!fs.existsSync(p)) {
            return;
        }
        if (fs.statSync(p).isDirectory()) {
            for (const entry of fs.readdirSync(p, { recursive: true })) {
                const f = path.join(p, String(entry));
                if (fs.statSync(f).isFile()) {
                    files.add(f);
                }
            }
        } else {
            files.add(p);
        }
    };
    for (const s of sources) {
        addTree(s);
        if (!fs.existsSync(s) || fs.statSync(s).isDirectory()) {
            continue;
        }
        addTree(s.endsWith('-meta.xml') ? s.slice(0, -'-meta.xml'.length) : s + '-meta.xml');
        const rel = relToSource(s).split('/');
        if (rel[0] === 'objects' && rel.length === 3 && rel[2] === `${rel[1]}.object-meta.xml`) {
            addTree(path.join(sourcePath(), 'objects', rel[1])); // the object's children go with it
        }
        if (rel[0] === 'staticresources' && rel.length >= 2) {
            const dir = path.join(sourcePath(), 'staticresources');
            const name = rel[1].split('.')[0];
            fs.readdirSync(dir).filter((n) => n.split('.')[0] === name).forEach((n) => addTree(path.join(dir, n)));
        }
    }
    return [...files].filter((f) => !isExcluded(f, null)).sort();
}

/** A copy of the project (sfdx-project.json, .forceignore, package directories) to fill values into. */
function makeDeployCopy() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-deploy-'));
    process.on('exit', () => {
        try {
            fs.rmSync(dir, { recursive: true, force: true });
        } catch (e) {
            // the job ends anyway
        }
    });
    let dirs = [];
    try {
        dirs = asList(JSON.parse(fs.readFileSync('sfdx-project.json', 'utf8')).packageDirectories)
            .map((p) => String((p && p.path) || '').replace(/\/+$/, '')).filter(Boolean);
    } catch (e) {
        dirs = [];
    }
    if (!dirs.some((d) => sourcePath() === d || sourcePath().startsWith(d + '/'))) {
        dirs.push(sourcePath());
    }
    for (const f of ['sfdx-project.json', '.forceignore']) {
        if (fs.existsSync(f)) {
            fs.copyFileSync(f, path.join(dir, f));
        }
    }
    for (const d of dirs) {
        if (/^[A-Za-z0-9_./-]+$/.test(d) && !d.includes('..') && !path.isAbsolute(d) && fs.existsSync(d)) {
            fs.cpSync(d, path.join(dir, d), { recursive: true });
        }
    }
    return dir;
}

/** Why a placeholder can't be filled, one sentence per name. */
function missingValuesMessage(missing, envName) {
    const byName = new Map();
    missing.forEach((m) => byName.set(m.name, (byName.get(m.name) || []).concat(m.file)));
    return [...byName.entries()].slice(0, 5).map(([name, files]) =>
        `${name} has no value for ${envName} in ${VALUES_FILE} (used in ${files.slice(0, 3).join(', ')}${files.length > 3 ? ', ...' : ''}).`)
        .join(' ') + (byName.size > 5 ? ` ${byName.size - 5} more name(s) have no value.` : '');
}

/** A short fingerprint of the values a deployment used, so a quick deploy never sends a validation's older values. */
function valuesHash(used) {
    if (!used.size) {
        return '';
    }
    const list = [...used.entries()].sort((a, b) => (a[0] < b[0] ? -1 : 1));
    return crypto.createHash('sha256').update(JSON.stringify(list)).digest('hex').slice(0, 16);
}

/**
 * Fills {{relay:NAME}} in the deployment's text files with envName's values, in a temporary copy of the project
 * that the deploy then runs from (plan.cwd); the checkout itself is never changed. Sets deployValues
 * ({ replaced, files, hash }) for the result. Returns '' or why the deployment can't go ahead.
 */
function prepareDeployValues(plan, envName) {
    deployValues = { replaced: 0, files: [], hash: '' };
    if (selfUpdate()) {
        return ''; // the hub updating itself: Release Relay's own files hold placeholder examples, never values
    }
    const edits = [];
    const missing = [];
    const used = new Map();
    for (const f of deploymentFiles(plan.sources || [])) {
        const text = readText(f);
        if (text === null || !text.includes('{{relay:') || isExcluded(f, 'HEAD')) {
            continue; // Release Relay's own files (the exclude list) are never filled
        }
        if (relayValues.error) {
            return `${relayValues.error} It's needed for ${relToSource(f)}.`;
        }
        const r = substituteText(text, relayValues.values, envName);
        r.missing.forEach((name) => missing.push({ name, file: relToSource(f) }));
        if (r.count) {
            edits.push({ file: f, text: r.text, count: r.count });
            r.used.forEach((name) => used.set(name, relayValues.values[name][envName]));
        }
    }
    if (missing.length) {
        return missingValuesMessage(missing, envName);
    }
    if (!edits.length) {
        return '';
    }
    const copy = makeDeployCopy();
    for (const e of edits) {
        fs.writeFileSync(path.join(copy, e.file), e.text);
    }
    plan.cwd = copy;
    deployValues = { replaced: edits.reduce((n, e) => n + e.count, 0), files: edits.slice(0, 50).map((e) => relToSource(e.file)),
        hash: valuesHash(used) };
    summary(`**Per-org values:** ${deployValues.replaced} placeholder(s) in ${edits.length} file(s) filled with ${envName}'s values `
        + `from ${VALUES_FILE} (${[...used.keys()].join(', ')}), in a temporary copy that isn't committed.`);
    return '';
}

/**
 * Turns the source environment's values back into {{relay:NAME}} in files just written from an org, so branches
 * always hold placeholders. Returns { count, error }.
 */
function tokenizeFiles(files, envName) {
    if (!relayValues.present || !envName || selfUpdate()) {
        return { count: 0, error: '' };
    }
    if (relayValues.error) {
        return { count: 0, error: relayValues.error };
    }
    const { pairs, warnings } = reversePairs(relayValues.values, envName);
    warnings.forEach((w) => console.log('::warning::' + w));
    let count = 0;
    let changed = 0;
    for (const f of files) {
        const text = readText(f);
        if (text === null) {
            continue;
        }
        const r = tokenizeText(text, pairs);
        if (r.count) {
            fs.writeFileSync(f, r.text);
            count += r.count;
            changed++;
        }
    }
    if (count || warnings.length) {
        summary(`**Per-org values:** ${count} occurrence(s) of ${envName}'s values in ${changed} retrieved file(s) turned into `
            + `{{relay:NAME}} placeholders (${VALUES_FILE}).` + (warnings.length ? '\n' + warnings.map((w) => `- ${w}`).join('\n') : ''));
    }
    return { count, error: '' };
}

// ---------- quality gates (.relay/gates.json) ----------

let relayGates = { present: false, scan: null, coverage: null, tests: null, errors: [] };

/** Parses .relay/gates.json: { scan: { failAtPriority }, coverage: { minimumPerClass, minimumOrgWide }, tests: { requireForApex } }. */
function parseGates(text) {
    const out = { present: false, scan: null, coverage: null, tests: null, errors: [] };
    if (text === null || text === undefined || !String(text).trim()) {
        return out;
    }
    out.present = true;
    let json;
    try {
        json = JSON.parse(text);
    } catch (e) {
        out.errors.push(`${GATES_FILE} isn't valid JSON (${String(e.message).slice(0, 200)}).`);
        return out;
    }
    if (!json || typeof json !== 'object' || Array.isArray(json)) {
        out.errors.push(`${GATES_FILE} must hold a JSON object.`);
        return out;
    }
    const section = (key) => (json[key] && typeof json[key] === 'object' && !Array.isArray(json[key]) ? json[key] : null);
    const percent = (obj, key) => {
        if (!obj || obj[key] === undefined || obj[key] === null) {
            return null;
        }
        if (typeof obj[key] !== 'number' || obj[key] < 0 || obj[key] > 100) {
            out.errors.push(`${key} in ${GATES_FILE} must be a number from 0 to 100.`);
            return null;
        }
        return obj[key];
    };
    const scan = section('scan');
    if (scan && scan.failAtPriority !== undefined && scan.failAtPriority !== null) {
        if (Number.isInteger(scan.failAtPriority) && scan.failAtPriority >= 1 && scan.failAtPriority <= 5) {
            out.scan = { failAtPriority: scan.failAtPriority };
        } else {
            out.errors.push(`scan.failAtPriority in ${GATES_FILE} must be a whole number from 1 (highest) to 5.`);
        }
    }
    const coverage = section('coverage');
    const perClass = percent(coverage, 'minimumPerClass');
    const orgWide = percent(coverage, 'minimumOrgWide');
    if (perClass !== null || orgWide !== null) {
        out.coverage = { minimumPerClass: perClass, minimumOrgWide: orgWide };
    }
    const tests = section('tests');
    if (tests && tests.requireForApex === true) {
        out.tests = { requireForApex: true };
    }
    return out;
}

/** The "gates" entry of scan.json and validate.json. file is null when there's no .relay/gates.json. */
function gatesResult(gates, failures) {
    const all = gates.errors.concat(failures);
    return { file: gates.present ? GATES_FILE : null, passed: all.length === 0, failures: all.slice(0, 50) };
}

/** The scan gate: findings at failAtPriority or higher (1 is highest). Returns { failures, gate }. */
function evaluateScanGate(violations, gates) {
    if (!gates.scan) {
        return { failures: [], gate: null };
    }
    const p = gates.scan.failAtPriority;
    const hits = violations.filter((x) => Number(x.severity) <= p);
    const gate = { failAtPriority: p, findings: hits.length };
    if (!hits.length) {
        return { failures: [], gate };
    }
    const list = hits.slice(0, 5).map((x) => `${x.rule} (${x.file}${x.line ? ':' + x.line : ''})`).join(', ') + (hits.length > 5 ? ', ...' : '');
    return { failures: [`${hits.length} finding${hits.length === 1 ? '' : 's'} at priority ${p} or higher: ${list}`], gate };
}

/**
 * tests.requireForApex: a deployment with Apex that would run no tests fails before it's sent. skip: Apex that needs
 * no tests (deleted classes and triggers, triggers sent inactive), left out.
 */
function evaluateTestsGate(apexAll, testLevel, gates, skip = []) {
    const skipped = new Set(skip.map((n) => String(n).toLowerCase()));
    const apex = apexAll.filter((n) => !skipped.has(String(n).toLowerCase()));
    if (!gates.tests || !gates.tests.requireForApex || !apex.length || testLevel !== 'NoTestRun') {
        return [];
    }
    return [`This release deploys Apex (${apex.slice(0, 5).join(', ')}${apex.length > 5 ? ', ...' : ''}) but names no tests. `
        + `Add its test classes to the release in Release Relay (${GATES_FILE}: tests.requireForApex).`];
}

/**
 * The coverage gate, from the validation's per-class coverage (runTestResult.codeCoverage). minimumPerClass applies
 * to the Apex classes and triggers the release deploys; minimumOrgWide only when the validation ran every local
 * test (RunLocalTests, RunAllTestsInOrg), the only case where the coverage covers the org. Returns
 * { failures, coverage: { minimumPerClass, minimumOrgWide, perClass: [{ name, percent }], orgWide } }.
 */
function evaluateCoverageGate(codeCoverage, apexAll, testLevel, gates, inactive = []) {
    if (!gates.coverage) {
        return { failures: [], coverage: null };
    }
    // Inactive triggers get no coverage and Salesforce doesn't hold them to it: no 0% failure for them.
    const off = new Set(inactive.map((n) => String(n).toLowerCase()));
    const apex = apexAll.filter((n) => !off.has(String(n).toLowerCase()));
    const { minimumPerClass, minimumOrgWide } = gates.coverage;
    const rows = asList(codeCoverage).map((c) => {
        const total = Number(c && c.numLocations) || 0;
        const notCovered = Number(c && c.numLocationsNotCovered) || 0;
        return { name: String((c && c.name) || ''), total, covered: Math.max(0, total - notCovered) };
    }).filter((r) => r.name);
    const pct = (covered, total) => (covered / total) * 100;
    const shown = (x) => Math.floor(x * 10) / 10;
    const wanted = new Set(apex.map((n) => n.toLowerCase()));
    const failures = [];
    const perClass = [];
    const seen = new Set();
    for (const r of rows) {
        const key = r.name.toLowerCase();
        if (!wanted.has(key) || seen.has(key) || r.total === 0) {
            continue;
        }
        seen.add(key);
        const p = pct(r.covered, r.total);
        perClass.push({ name: r.name, percent: shown(p) });
        if (minimumPerClass !== null && p < minimumPerClass) {
            failures.push(`${r.name} ${shown(p)}% < ${minimumPerClass}%`);
        }
    }
    let orgWide = null;
    if (['RunLocalTests', 'RunAllTestsInOrg'].includes(testLevel) && rows.length) {
        const total = rows.reduce((n, r) => n + r.total, 0);
        if (total > 0) {
            orgWide = shown(pct(rows.reduce((n, r) => n + r.covered, 0), total));
            if (minimumOrgWide !== null && orgWide < minimumOrgWide) {
                failures.push(`Org-wide coverage ${orgWide}% < ${minimumOrgWide}%`);
            }
        }
    }
    return { failures, coverage: { minimumPerClass, minimumOrgWide, perClass: perClass.slice(0, 200), orgWide } };
}

function gatesSummary(step, result) {
    if (!result.file && result.passed) {
        return;
    }
    summary(`**Quality gates (${GATES_FILE}), ${step}:** ${result.passed ? 'passed' : 'failed'}`
        + (result.failures.length ? '\n' + result.failures.map((f) => `- ${f}`).join('\n') : ''));
}

/**
 * Builds .relay/package.xml (+ destructiveChangesPost.xml) for the changes between two commits,
 * using the files as they are at head. Returns null when nothing deployable changed.
 */
function buildDeployment(base, head) {
    return buildFromFiles(changedFiles(base, head), base);
}

/** The deployment for picked repo paths as the checked-out branch has them (a path it hasn't got is a deletion). */
function buildForPaths(paths, ref) {
    return buildFromFiles(paths.map((f) => ({ status: fs.existsSync(f) ? 'M' : 'D', file: f })), ref);
}

/** The deployment (manifests, counts, Apex) for changed files [{status A|M|D, file}]; base is used for the exclude list's label checks. */
function buildFromFiles(all, base) {
    const skipped = new Set(all.filter((f) => isExcluded(f.file, base)).map((f) => f.file));
    const files = all.filter((f) => !skipped.has(f.file));
    deployExcluded = [...skipped].sort();
    if (selfUpdate()) {
        summary('**Self-update:** the exclude list is ignored; Release Relay\'s own files are deployed.');
    } else if (deployExcluded.length) {
        summary(`**Excluded:** ${deployExcluded.length} Release Relay file(s) matching ${excludeSource} were not deployed or deleted:\n`
            + deployExcluded.slice(0, 30).map((f) => `- \`${f}\``).join('\n') + (deployExcluded.length > 30 ? '\n- ...' : ''));
    }
    const sourceDirs = new Set();
    const deletions = new Map();
    const unknown = [];
    // A custom object deleted as a whole takes its fields, list views, compact layouts etc. with it.
    const goneObjects = new Set(files.filter((f) => f.status === 'D').map((f) => componentFor(f.file))
        .filter((c) => c && c.type === 'CustomObject' && !fs.existsSync(path.join(sourcePath(), 'objects', c.name)))
        .map((c) => c.name));
    for (const f of files) {
        const rel = path.relative(sourcePath(), f.file).split(path.sep);
        if (f.status === 'D' && rel[0] === 'objects' && goneObjects.has(rel[1])) {
            if (rel.length === 3 && rel[2] === `${rel[1]}.object-meta.xml`) {
                deletions.set(`CustomObject:${rel[1]}`, { type: 'CustomObject', name: rel[1] });
            }
            continue;
        }
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
    // Only the generated manifests: .relay/exclude lives in the same folder.
    fs.mkdirSync(WORK_DIR, { recursive: true });
    ['package.xml', 'destructiveChangesPost.xml'].forEach((f) => fs.rmSync(path.join(WORK_DIR, f), { force: true }));
    applyForceIgnore();
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
    // The Apex classes and triggers the deployment sends or deletes, for the quality gates.
    const apex = [...new Set(existing.map((d) => componentFor(d)).concat([...deletions.values()])
        .filter((c) => c && APEX_TYPES.has(c.type)).map((c) => c.name))].sort();
    // Deleted Apex, and triggers sent switched off (<status>Inactive</status>): neither needs a test class.
    const apexDeleted = [...deletions.values()].filter((c) => APEX_TYPES.has(c.type)).map((c) => c.name).sort();
    const sentTriggers = [...new Set(existing.map((d) => componentFor(d)).filter((c) => c && c.type === 'ApexTrigger').map((c) => c.name))];
    const inactiveTriggers = sentTriggers.filter((n) => triggerIsInactive(n)).sort();
    return { pkg, destructive, changed: existing.length, deleted: deletions.size,
        deletedList: [...deletions.keys()], sources: existing, apex, apexDeleted, inactiveTriggers };
}

/** Whether a trigger's -meta.xml in the release files says <status>Inactive</status>. */
function triggerIsInactive(name) {
    const meta = path.join(sourcePath(), 'triggers', `${name}.trigger-meta.xml`);
    try {
        return /<status>\s*Inactive\s*<\/status>/i.test(fs.readFileSync(meta, 'utf8'));
    } catch (e) {
        return false;
    }
}

/**
 * Whether the release's Apex is only deletions and triggers sent inactive (nothing that runs and needs coverage).
 * Such a release without tests runs the org's local tests in production (Salesforce refuses NoTestRun there for
 * Apex, deleted or inactive included) and no tests elsewhere.
 */
function apexNeedsNoTests(plan) {
    const apex = plan.apex || [];
    const skip = new Set([...(plan.apexDeleted || []), ...(plan.inactiveTriggers || [])].map((n) => n.toLowerCase()));
    return apex.length > 0 && skip.size > 0 && apex.every((n) => skip.has(n.toLowerCase()));
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

/**
 * Runs a deployment (or a check-only one) and returns a result for Salesforce. The release's tests win;
 * without them DEPLOY_TEST_LEVEL, else plan.defaultTestLevel (a back promote: by whether Apex changed),
 * else RunLocalTests. plan.ownTests false ignores the release's tests (a back promote has none).
 */
function deployTo(alias, plan, checkOnly) {
    const { tests, testLevel } = testLevelFor(plan);
    // plan.cwd: the temporary copy with per-org values filled in (manifests then go by absolute path).
    const abs = (p) => (plan.cwd ? path.resolve(p) : p);
    const args = ['project', 'deploy', 'start', '--manifest', abs(plan.pkg), '--target-org', alias,
        '--test-level', testLevel, '--wait', DEPLOY_WAIT, '--json'];
    (tests || []).forEach((t) => args.push('--tests', t));
    if (plan.destructive) {
        args.push('--post-destructive-changes', abs(plan.destructive));
    }
    if (checkOnly) {
        args.push('--dry-run');
    }
    return runDeploy(args, testLevel, tests, plan.cwd);
}

/** The test level a deployment of plan uses, and the release's tests (null when it sent none). */
function testLevelFor(plan) {
    const tests = plan.ownTests === false ? null : releaseTests();
    if (tests && !tests.length && apexNeedsNoTests(plan)) {
        // Only deleted Apex and inactive triggers, no tests: production (the hub says so: options.production) runs
        // the local tests, sandboxes and other orgs none.
        return { tests: [], testLevel: options.production === true ? 'RunLocalTests' : 'NoTestRun' };
    }
    const testLevel = tests ? (tests.length ? 'RunSpecifiedTests' : 'NoTestRun')
        : TEST_LEVELS.includes(v('DEPLOY_TEST_LEVEL')) ? v('DEPLOY_TEST_LEVEL') : (plan.defaultTestLevel || 'RunLocalTests');
    return { tests, testLevel };
}

/** WAIT for every deploy command: the deploy and validate jobs' time limits leave room for it. */
const DEPLOY_WAIT = '110';

/**
 * Runs an sf project deploy command (--json) and turns its output into a result for Salesforce. The per-class
 * code coverage is attached as a hidden property (codeCoverage), for the coverage gate, and isn't written out.
 */
function runDeploy(args, testLevel, tests, cwd) {
    let raw;
    try {
        raw = execFileSync('sf', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024,
            ...(cwd ? { cwd } : {}) });
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
    const result = {
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
    Object.defineProperty(result, 'codeCoverage', {
        value: asList(details.runTestResult && details.runTestResult.codeCoverage), enumerable: false
    });
    return result;
}


// ---------- step: scan ----------

const SEVERITY = { 1: 'Critical', 2: 'High', 3: 'Moderate', 4: 'Low', 5: 'Info' };

async function stepScan() {
    orgEnv = '';
    const base = checkoutReleaseBranch();
    const files = changedFiles(base, 'HEAD')
        .filter((f) => f.status !== 'D' && SCAN_EXT.some((ext) => f.file.endsWith(ext)) && fs.existsSync(f.file))
        .map((f) => f.file);
    // The gates file itself being unreadable fails the scan whatever it finds; the scan gate needs findings.
    const gatesOnly = gatesResult(relayGates, []);
    const scanGate = relayGates.scan ? { failAtPriority: relayGates.scan.failAtPriority, findings: 0 } : null;
    if (!files.length) {
        gatesSummary('scan', gatesOnly);
        writeResult('scan', { status: gatesOnly.passed ? 'Skipped' : 'Failed', total: 0, blocking: 0, files: [], violations: [],
            message: gatesOnly.passed ? 'No code files in this pull request.' : gatesOnly.failures.join(' '),
            gate: scanGate, gates: gatesOnly });
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
                message: 'Code Analyzer didn\'t run. Open the workflow run for the log.', gate: scanGate,
                gates: gatesResult(relayGates, relayGates.scan ? ['The scan didn\'t run, so the scan gate couldn\'t be checked.'] : []) });
            return;
        }
    }
    let report;
    try {
        report = JSON.parse(fs.readFileSync(outFile, 'utf8'));
    } catch (e) {
        writeResult('scan', { status: 'Error', total: 0, blocking: 0, files, violations: [], message: 'The scan report couldn\'t be read.',
            gate: scanGate, gates: gatesResult(relayGates, relayGates.scan ? ['The scan report couldn\'t be read, so the scan gate couldn\'t be checked.'] : []) });
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
    const evaluated = evaluateScanGate(violations, relayGates);
    const gates = gatesResult(relayGates, evaluated.failures);
    gatesSummary('scan', gates);
    const messages = [blocking ? `${blocking} violation(s) at ${SEVERITY[threshold]} or above.` : ''].concat(gates.failures).filter(Boolean);
    writeResult('scan', {
        status: blocking || !gates.passed ? 'Failed' : 'Passed',
        total: violations.length,
        blocking,
        threshold,
        thresholdLabel: SEVERITY[threshold],
        rules,
        counts,
        files,
        violations: violations.slice(0, 200),
        message: messages.join(' ').slice(0, 1500),
        gate: evaluated.gate,
        gates
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

/** Modes hub and promote started by the hub write raise.json: the hub reads the pull request, or why there's none. */
function writesRaiseResult() {
    return mode === 'hub' || (mode === 'promote' && options.hub === true);
}

/**
 * results/<REQUEST_ID>/raise.json, the same shape for modes hub and promote:
 * { status: 'Opened' | 'Failed', mode, branch, target, sha, pr, url, commits, conflicts, deleted, valuesTokenized,
 *   appended, message }.
 * deleted: the Type:Name entries mode hub removed from BRANCH (always [] for promote). valuesTokenized: how many
 * occurrences of the source environment's values (.relay/values.json) became {{relay:NAME}} (always 0 for promote).
 * appended: true for changes added to an open release (mode hub, OPTIONS.append; also files, appendZip).
 * A promotion from the stage's state adds files (how many files the releases changed) and fromStage, and on a
 * clash conflicts (the files) and clash: [{ file, targetBlob, stageBlob }].
 */
function raiseResult(status, data) {
    writeResult('raise', { status, mode, branch, target, sha: null, pr: null, url: null,
        commits: [], conflicts: [], deleted: [], valuesTokenized: 0, appended: false, message: '', ...data });
}

/** Ends the raise; a hub run first says why in raise.json. */
function raiseFailed(message, data) {
    if (writesRaiseResult()) {
        raiseResult('Failed', { ...data, message: String(message).slice(0, 1500) });
    }
    fail(message);
}

/** The pull/merge request number at the end of its web address. */
function prNumber(url) {
    const m = /(\d+)\/?$/.exec(String(url || ''));
    return m ? Number(m[1]) : null;
}

/** Opens (or finds) the PR/MR for a hub or promote raise and records it in raise.json. */
async function openAndRecord(body, data) {
    let url;
    try {
        url = await provider.open(branch, target, title, body);
    } catch (e) {
        raiseFailed(`Opening the ${provider.label} failed: ${e && e.message ? e.message : e}`, data);
    }
    if (writesRaiseResult()) {
        raiseResult('Opened', { ...data, pr: prNumber(url), url });
    }
    summary(`**${provider.label}:** ${url}\n\n${branch} → ${target}, release ${requestId}\n\n${body}`);
}

async function stepRaise() {
    orgEnv = sourceEnv;
    if (!['org', 'branch', 'promote', 'hub', 'resolve'].includes(mode)) { fail('MODE must be org, branch, promote, hub or resolve to raise.'); }
    checkAllowedTarget();
    if (!title) { raiseFailed('Title is required.'); }
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
        // The org's own values (its URLs, ids, ...) go into the branch as {{relay:NAME}} placeholders.
        const retrieved = [...new Set(git(['ls-files', '-z', '-m', '-o', '--exclude-standard', '--', sourcePath()]).split('\0').filter(Boolean))];
        const tokens = tokenizeFiles(retrieved, sourceEnv);
        if (tokens.error) {
            fail(tokens.error);
        }
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
function convertFromHub(mdapi, out, failWith = raiseFailed) {
    // Some types (custom labels, for example) are only converted inside a Salesforce DX project, so the output
    // folder is made one: a minimal sfdx-project.json whose package directory receives the files.
    fs.mkdirSync(out, { recursive: true });
    fs.writeFileSync(path.join(out, 'sfdx-project.json'),
        JSON.stringify({ packageDirectories: [{ path: 'force-app', default: true }], sourceApiVersion: '63.0' }));
    try {
        // The JSON lists every converted file (megabytes for a whole org): a big buffer, or Node stops the command midway.
        execFileSync('sf', ['project', 'convert', 'mdapi', '--root-dir', mdapi, '--output-dir', path.join(out, 'force-app'), '--json'],
            { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], cwd: out, maxBuffer: CLI_BUFFER,
                env: { ...process.env, SF_SKIP_NEW_VERSION_CHECK: 'true', NO_COLOR: '1', FORCE_COLOR: '0' } });
    } catch (e) {
        if (e.code === 'ENOBUFS') {
            failWith('Converting the files from the hub printed more output than the pipeline can hold; nothing was changed.');
        }
        let detail = String(e.stdout || '') + String(e.stderr || '');
        try {
            const parsed = JSON.parse(String(e.stdout || '{}'));
            detail = [parsed.name, parsed.message].concat(parsed.actions || []).filter(Boolean).join(' | ') || detail;
        } catch (ignored) {
            // not JSON: keep the raw output
        }
        failWith('Converting the files from the hub failed: ' + detail.replace(/\s+/g, ' ').trim().slice(0, 1500));
    }
}

/** The pull request's line about the tests the release runs (OPTIONS.tests), or '' when it sent none. */
function testsLine() {
    const tests = releaseTests();
    if (!tests) {
        return '';
    }
    return tests.length ? `**Tests:** ${tests.map((t) => '`' + t + '`').join(', ')} (RunSpecifiedTests)` : '**Tests:** none, no Apex (NoTestRun)';
}

/** Reverse of componentFor: the files (or folder) of one component on the checked-out branch, or null when unsupported. */
function deletionPaths(d) {
    if (d.type === 'StaticResource') {
        return pathsFor(sourcePath(), d.type, d.name).filter((p) => p.split(path.sep).pop().split('.')[0] === d.name);
    }
    return pathsFor(sourcePath(), d.type, d.name);
}

/** The hub's deletions: DELETIONS plus any Type:Name entries in .relay-inbox/<REQUEST_ID>.deletions (commas or new lines). */
function hubDeletions(markerFile) {
    const raw = [input('DELETIONS'), fs.existsSync(markerFile) ? fs.readFileSync(markerFile, 'utf8') : '']
        .join(',').split(/[,\r\n]+/).map((x) => x.trim()).filter(Boolean);
    const seen = new Map();
    for (const entry of raw) {
        const m = ITEM_RE.exec(entry);
        if (!m) {
            raiseFailed(`The deletion "${entry.slice(0, 100)}" isn't Type:Name.`);
        }
        const d = { type: m[1], name: m[2].trim() };
        if (CHILD_TYPES[d.type] && d.name.indexOf('.') < 1) {
            raiseFailed(`${d.type} "${d.name}" must be written as Object.Name.`);
        }
        d.entry = `${d.type}:${d.name}`;
        seen.set(d.entry, d);
    }
    return [...seen.values()];
}

/** Why a release can't both add and delete these, or ''. */
function addedAndDeleted(components, deletions) {
    const added = new Set(components.map((c) => `${c.type}:${c.name}`));
    for (const d of deletions) {
        if (added.has(d.entry)) {
            return `${d.type} ${d.name} is both added and deleted.`;
        }
        if (d.type === 'CustomObject') {
            const child = components.find((c) => CHILD_TYPES[c.type] && c.name.startsWith(d.name + '.'));
            if (child) {
                return `${child.type} ${child.name} is added, but its object ${d.name} is deleted.`;
            }
        }
    }
    return '';
}

/** Removes each deletion's files from the checked-out branch. In append mode, files already gone are skipped. */
function removeDeletions(deletions, deleted, lenient) {
    const skipped = [];
    for (const d of deletions) {
        const paths = deletionPaths(d);
        if (paths === null) {
            raiseFailed(`Deleting ${d.type} isn't supported by the pipeline. Remove ${d.name} in a normal ${provider.label}.`, { deleted });
        }
        const found = paths.filter((p) => fs.existsSync(p));
        if (!found.length) {
            if (lenient) {
                skipped.push(d.entry); // deleted earlier in this release
                continue;
            }
            raiseFailed(`${d.type} ${d.name} isn't in ${branch}, so there's nothing to delete.`, { deleted });
        }
        git(['--literal-pathspecs', 'rm', '-r', '-q', '--', ...found]);
    }
    return skipped;
}

/**
 * Unzips the hub's Metadata API zip, converts it to source format and copies the files into SOURCE_PATH, then
 * removes the zip from the branch. Returns the copied paths (relative to SOURCE_PATH). The same code path for a
 * new hub raise and for changes added to an open release.
 */
function unpackHubZip(zipFile, components, deleted) {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-hub-'));
    const mdapi = path.join(tmp, 'mdapi');
    const out = path.join(tmp, 'source');
    let copied = [];
    let unzipped = true;
    try {
        try {
            execFileSync('unzip', ['-q', '-o', zipFile, '-d', mdapi], { stdio: ['ignore', 'pipe', 'pipe'] });
        } catch (e) {
            unzipped = false; // an empty zip (a release with only deletions) makes unzip complain
            if (components.length) {
                raiseFailed(`${zipFile} couldn't be unzipped: ${String(e.stderr || e.message).trim().slice(0, 500)}`, { deleted });
            }
        }
        const hasFiles = unzipped && fs.existsSync(mdapi)
            && fs.readdirSync(mdapi, { recursive: true }).some((f) => !/(^|\/)package\.xml$/.test(String(f))
                && fs.statSync(path.join(mdapi, String(f))).isFile());
        if (components.length || hasFiles) {
            convertFromHub(mdapi, out);
            const converted = [path.join(out, 'force-app', 'main', 'default'), path.join(out, 'force-app')]
                .find((p) => fs.existsSync(p));
            const wholeObjects = new Set(components.filter((c) => c.type === 'CustomObject').map((c) => c.name));
            copied = converted ? copyConverted(converted, sourcePath(), wholeObjects) : [];
        }
    } finally {
        fs.rmSync(tmp, { recursive: true, force: true });
    }
    git(['rm', '-q', '--', zipFile]);
    return copied;
}

/** Removes the hub's deletions marker, committed or not. */
function removeMarker(markerFile) {
    if (fs.existsSync(markerFile)) {
        if (gitQuiet(['ls-files', '--error-unmatch', '--', markerFile]) !== null) {
            git(['rm', '-q', '-f', '--', markerFile]);
        } else {
            fs.rmSync(markerFile, { force: true });
        }
    }
}

async function raiseFromHub() {
    if (options.append === true) {
        await appendToRelease();
        return;
    }
    const components = parseList(input('COMPONENTS'), 'COMPONENTS');
    const zipFile = path.join('.relay-inbox', requestId + '.zip');
    const markerFile = path.join('.relay-inbox', requestId + '.deletions');
    if (!remoteBranchExists(branch)) {
        raiseFailed(`Branch ${branch} doesn't exist. Raise the release again from Release Relay.`);
    }
    fetchBranch(target);
    fetchBranch(branch);
    git(['checkout', '-q', '-B', branch, `refs/remotes/origin/${branch}`]);
    const deletions = hubDeletions(markerFile);
    const deleted = deletions.map((d) => d.entry);
    // A big release comes in parts (version 22): .relay-inbox/<REQUEST_ID>-part-<k>.zip, unpacked in order.
    const zips = (fs.existsSync(zipFile) ? [zipFile] : []).concat(hubPartZips());
    const hasZip = zips.length > 0;
    if (!hasZip && !deletions.length) {
        raiseFailed(`${zipFile} isn't on ${branch} (nor a ${markerFile} listing deletions). Raise the release again from Release Relay.`);
    }
    const clash = addedAndDeleted(components, deletions);
    if (clash) {
        raiseFailed(clash, { deleted });
    }

    // Deletions first, on the branch as the hub left it: each must be there to be removed.
    removeDeletions(deletions, deleted, false);

    const copied = [];
    zips.forEach((z) => unpackHubZip(z, components, deleted).forEach((f) => copied.push(f)));
    // The developer org's own values go into the branch as {{relay:NAME}} placeholders.
    const tokens = tokenizeFiles(copied.map((r) => path.join(sourcePath(), r)), sourceEnv);
    if (tokens.error) {
        raiseFailed(tokens.error, { deleted });
    }
    const valuesTokenized = tokens.count;
    removeMarker(markerFile);
    git(['add', '-A', '--', sourcePath()]);
    if (git(['diff', '--cached', '--name-only', '--', sourcePath()]) === '') {
        raiseFailed(`${orgLabel()} already matches ${target} for these components. Nothing to commit.`, { deleted });
    }
    const counts = [copied.length ? `${copied.length} files` : '', deletions.length ? `${deletions.length} deletion(s)` : '']
        .filter(Boolean).join(', ');
    git(['commit', '-q', '-m', title, '-m', `Release Relay ${requestId} from ${orgLabel()} (${counts || 'no files'})`]);
    git(['push', '-q', 'origin', `HEAD:refs/heads/${branch}`]);
    const sha = git(['rev-parse', 'HEAD']);

    const list = (items) => items.map((i) => `- ${i.type}: \`${i.name}\``).join('\n');
    const requestType = deletions.length ? (components.length ? 'Changes and deletions' : 'Deletions') : 'Changes';
    const body = [
        `Raised from the Release Relay hub (${orgLabel()}), release ${requestId}.`,
        `**Request type:** ${requestType}`,
        components.length ? `### Added or updated from ${orgLabel()}\n${list(components)}` : '',
        deletions.length ? `### Deleted from ${orgLabel()}\n${list(deletions)}\n\nTheir files are removed from this branch; `
            + `validating and deploying delete them from ${targetEnv ? `the ${targetEnv} org` : `${target}'s org`} too (destructiveChangesPost).` : '',
        testsLine(),
        'Every item was selected and reviewed in Release Relay. Approve it in Salesforce; Release Relay merges it.'
    ].filter(Boolean).join('\n\n');
    await openAndRecord(body, { sha, deleted, valuesTokenized });
}

/** The parts of a big release the hub committed (.relay-inbox/<REQUEST_ID>-part-<k>.zip), in number order. */
function hubPartZips() {
    const dir = '.relay-inbox';
    if (!fs.existsSync(dir)) {
        return [];
    }
    const re = new RegExp('^' + requestId.replace(/[^A-Za-z0-9-]/g, '') + '-part-(\\d{1,4})\\.zip$');
    return fs.readdirSync(dir).map((f) => [f, re.exec(f)]).filter((x) => x[1])
        .sort((a, b) => Number(a[1][1]) - Number(b[1][1])).map((x) => path.join(dir, x[0]));
}

/** The zip the hub committed for changes added to an open release: .relay-inbox/<REQUEST_ID>-add-<k>.zip, or ''. */
function appendZipPath(value, request) {
    const zip = typeof value === 'string' ? value : '';
    const m = /^\.relay-inbox\/(REL-\d+)-add-\d{1,6}\.zip$/.exec(zip);
    return m && m[1] === request ? zip : '';
}

/** The web address of a pull/merge request found by provider.find, or null. */
function foundPrUrl(found) {
    const raw = (found && found.raw) || {};
    if (raw.web_url) { return raw.web_url; }                                   // GitLab
    if (raw.links && raw.links.html && raw.links.html.href) { return raw.links.html.href; } // Bitbucket
    if (PROVIDER === 'azure' && found && found.id && provider.web) { return provider.web(found.id); }
    if (PROVIDER === 'github' && found && found.id && env.GITHUB_REPOSITORY) {
        return `${env.GITHUB_SERVER_URL || 'https://github.com'}/${env.GITHUB_REPOSITORY}/pull/${found.id}`;
    }
    return null;
}

/**
 * MODE=hub with OPTIONS.append: more changes from the developer org for a release that's already open. The hub
 * committed a new zip (OPTIONS.appendZip, .relay-inbox/<REQUEST_ID>-add-<k>.zip) to the release branch; it's
 * converted into SOURCE_PATH exactly like a new hub raise, DELETIONS are removed, and the branch is pushed. The
 * open pull request updates itself, so none is opened; scan and validate then run again.
 */
async function appendToRelease() {
    const components = parseList(input('COMPONENTS'), 'COMPONENTS');
    const zipFile = appendZipPath(options.appendZip, requestId);
    if (!zipFile) {
        raiseFailed(`options.appendZip must be .relay-inbox/${requestId}-add-<number>.zip (the file the hub committed to ${branch}).`,
            { appended: true });
    }
    if (!remoteBranchExists(branch)) {
        raiseFailed(`Branch ${branch} doesn't exist, so ${requestId} has no open release branch to add changes to.`, { appended: true });
    }
    fetchBranch(target);
    fetchBranch(branch);
    git(['checkout', '-q', '-B', branch, `refs/remotes/origin/${branch}`]);
    const markerFile = zipFile.replace(/\.zip$/, '.deletions');
    const deletions = hubDeletions(markerFile);
    const deleted = deletions.map((d) => d.entry);
    const hasZip = fs.existsSync(zipFile) && gitQuiet(['ls-files', '--error-unmatch', '--', zipFile]) !== null;
    if (!hasZip && (components.length || !deletions.length)) {
        raiseFailed(`${zipFile} isn't on ${branch}. Add the changes again from Release Relay.`, { appended: true, deleted });
    }
    const clash = addedAndDeleted(components, deletions);
    if (clash) {
        raiseFailed(clash, { appended: true, deleted });
    }
    const skipped = removeDeletions(deletions, deleted, true);
    const copied = [];
    zips.forEach((z) => unpackHubZip(z, components, deleted).forEach((f) => copied.push(f)));
    const tokens = tokenizeFiles(copied.map((r) => path.join(sourcePath(), r)), sourceEnv);
    if (tokens.error) {
        raiseFailed(tokens.error, { appended: true, deleted });
    }
    removeMarker(markerFile);
    git(['add', '-A', '--', sourcePath()]);
    if (git(['diff', '--cached', '--name-only', '--', sourcePath()]) === '') {
        // Nothing new, but the consumed zip must not stay on the branch (it would be merged into the target).
        if (git(['diff', '--cached', '--name-only']) !== '') {
            git(['commit', '-q', '-m', `${requestId}: remove ${zipFile} (nothing new from ${orgLabel()})`]);
            git(['push', '-q', 'origin', `HEAD:refs/heads/${branch}`]);
        }
        raiseFailed(`${orgLabel()} already matches ${branch} for these components. Nothing to add.`,
            { appended: true, deleted, sha: git(['rev-parse', 'HEAD']) });
    }
    const counts = [copied.length ? `${copied.length} files` : '', deletions.length - skipped.length ? `${deletions.length - skipped.length} deletion(s)` : '']
        .filter(Boolean).join(', ');
    git(['commit', '-q', '-m', `${requestId}: more changes from ${orgLabel()}`, '-m', `Release Relay ${requestId} (${counts || 'no files'})`
        + (components.length ? '\n\n' + components.map((c) => `- ${c.entry}`).join('\n') : '')
        + (deletions.length ? '\n\nDeleted:\n' + deletions.map((d) => `- ${d.entry}`).join('\n') : '')]);
    git(['push', '-q', 'origin', `HEAD:refs/heads/${branch}`]);
    const sha = git(['rev-parse', 'HEAD']);

    let found = null;
    try {
        found = await provider.find(branch, target, 'open');
    } catch (e) {
        console.log(`::warning::Couldn't look up the open ${provider.label}: ${e && e.message ? e.message : e}`);
    }
    const url = foundPrUrl(found);
    const pr = found && found.id ? (Number(found.id) || prNumber(url)) : null;
    const message = found ? '' : `No open ${provider.label} from ${branch} into ${target} was found; the branch was updated anyway.`;
    raiseResult('Opened', { sha, pr, url, appended: true, deleted, valuesTokenized: tokens.count, files: copied.length,
        appendZip: zipFile, message });
    summary(`**Added to ${requestId}:** ${copied.length} files${deletions.length ? `, ${deletions.length - skipped.length} deletion(s)` : ''}`
        + ` from ${orgLabel()} on ${branch}${skipped.length ? ` (already deleted: ${skipped.join(', ')})` : ''}.`
        + (url ? ` The ${provider.label} updates itself: ${url}` : ` ${message}`));
}

/**
 * A promotion: a new branch from the next stage, with the carried releases' merge commits
 * cherry-picked onto it in the order Salesforce sent them (oldest merge first). Started by the hub
 * (OPTIONS.hub), it behaves like mode hub: raise.json, the release's tests, validateMerged and the
 * run token; a re-run for the same release opens the pull request for the branch it already pushed.
 */
async function raisePromotion() {
    const shas = (input('COMPONENTS') || '').split(',').map((x) => x.trim()).filter(Boolean);
    if (!shas.length || shas.some((x) => !SHA_RE.test(x))) {
        raiseFailed('COMPONENTS must list the merge commits to promote, as full 40-character hashes.');
    }
    const stageBranch = promoteStageBranch();
    const stageLines = (picked) => [
        `Raised from Release Relay${options.hub === true ? ' hub' : ''}, release ${requestId}.`,
        '**Request type:** Promotion',
        `Takes each file these releases changed as it is in \`${stageBranch}\` (the previous stage), into \`${target}\`:`,
        picked.map((x) => `- ${x.slice(0, 7)}`).join('\n'),
        testsLine(),
        'Approve it in Salesforce; Release Relay merges it and deploys it.'
    ].filter(Boolean).join('\n\n');
    const lines = (picked) => stageBranch ? stageLines(picked) : [
        `Raised from Release Relay${options.hub === true ? ' hub' : ''}, release ${requestId}.`,
        '**Request type:** Promotion',
        `Promotes into \`${target}\` the changes already deployed to the previous stage, cherry-picked in this order:`,
        picked.map((x) => `- ${x.slice(0, 7)}`).join('\n'),
        testsLine(),
        'Approve it in Salesforce; Release Relay merges it and deploys it.'
    ].filter(Boolean).join('\n\n');

    if (remoteBranchExists(branch)) {
        if (options.hub !== true) {
            fail(`Branch ${branch} already exists. Promote again to get a new branch.`);
        }
        fetchBranch(target);
        fetchBranch(branch);
        const head = git(['rev-parse', `refs/remotes/origin/${branch}`]);
        if (git(['diff', '--name-only', `refs/remotes/origin/${target}`, head]) === '') {
            raiseFailed(`Branch ${branch} already exists and matches ${target}. Nothing to promote.`, { sha: head });
        }
        await openAndRecord(lines(shas), { sha: head, commits: shas, ...(stageBranch ? { fromStage: stageBranch } : {}) });
        return;
    }

    git(['fetch', '--no-tags', 'origin']); // the commits live on the previous stage's branch
    fetchBranch(target);
    if (stageBranch) {
        await promoteFromStage(shas, stageBranch, lines);
        return;
    }
    git(['checkout', '-q', '-B', branch, `refs/remotes/origin/${target}`]);

    const picked = [];
    for (const sha of shas) {
        if (gitQuiet(['cat-file', '-t', sha]) !== 'commit') {
            raiseFailed(`Commit ${sha.slice(0, 7)} isn't in the repository. Was its branch rewritten?`, { commits: picked });
        }
        const parents = (gitQuiet(['rev-list', '--parents', '-n', '1', sha]) || '').split(' ').length - 1;
        // A merge commit is picked against its first parent: the stage branch before the merge.
        const args = ['cherry-pick', '-x', '--allow-empty', '--keep-redundant-commits'];
        if (parents > 1) { args.push('-m', '1'); }
        args.push(sha);
        try {
            execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: CLI_BUFFER });
        } catch (e) {
            const files = conflictedFiles();
            gitQuiet(['cherry-pick', '--abort']);
            raiseFailed(`${sha.slice(0, 7)} doesn't apply cleanly on ${target}`
                + (files.length ? ` (conflicts in ${files.slice(0, 5).join(', ')})` : '')
                + '. Promote the releases it depends on first, or resolve it in a branch and raise that branch.',
            { commits: picked, conflicts: files.slice(0, 50) });
        }
        picked.push(sha);
    }
    if (git(['diff', '--name-only', `refs/remotes/origin/${target}`, 'HEAD']) === '') {
        raiseFailed(`Everything in these commits is already in ${target}. Nothing to promote.`, { commits: picked });
    }
    git(['push', '-q', 'origin', `HEAD:refs/heads/${branch}`]);
    await openAndRecord(lines(picked), { sha: git(['rev-parse', 'HEAD']), commits: picked });
}

/** OPTIONS.stageBranch: the previous stage's branch a promotion takes its files from, or '' (cherry-pick as before). */
function promoteStageBranch() {
    const value = options.stageBranch;
    if (value === undefined || value === null || value === '') {
        return '';
    }
    const name = typeof value === 'string' ? value.trim() : '';
    if (!REF_RE.test(name) || name.includes('..') || name.startsWith('-') || name === target || name === branch
        || name === RESULTS_BRANCH || name === SNAPSHOT_BRANCH) {
        raiseFailed(`options.stageBranch "${String(value).slice(0, 100)}" isn't a valid stage branch.`);
    }
    return name;
}

/** Blob ids of many "<commit>:<path>" objects in one git call: a Map of spec to blob id (missing specs left out). */
function blobsOf(specs) {
    const result = new Map();
    if (!specs.length) {
        return result;
    }
    const out = gitWith(['cat-file', '--batch-check=%(objectname) %(objecttype)'], {}, specs.join('\n') + '\n').split('\n');
    specs.forEach((spec, i) => {
        const m = /^([0-9a-f]{40,64}) blob$/.exec(out[i] || '');
        if (m) {
            result.set(spec, m[1]);
        }
    });
    return result;
}

/** The files each merge commit changed against its first parent (the stage before the merge), in order, once each. */
function promotedFiles(shas) {
    const files = new Set();
    for (const sha of shas) {
        const parents = (gitQuiet(['rev-list', '--parents', '-n', '1', sha]) || '').split(' ').filter(Boolean).length - 1;
        const out = parents >= 1
            ? git(['diff', '--name-only', '--no-renames', '-z', `${sha}^1`, sha])
            : git(['diff-tree', '--root', '--no-commit-id', '--name-only', '--no-renames', '-r', '-z', sha]);
        out.split('\0').filter(Boolean).forEach((f) => files.add(f));
    }
    return [...files];
}

const CLASH_HISTORY_LIMIT = 200;

/**
 * Files whose target version the stage never had: { file, targetBlob, stageBlob } each. A target version is fine
 * when it's the stage's current version or appears in the stage's history of that file (the last 200 commits that
 * changed it, on every path: --full-history, so a hotfix merged back into the stage counts even when the merge kept
 * the stage's lines), so taking the stage's version can't drop a change made only in the target.
 */
function promotionClashes(files, targetRef, stageRef) {
    const targetBlobs = blobsOf(files.map((f) => `${targetRef}:${f}`));
    const stageBlobs = blobsOf(files.map((f) => `${stageRef}:${f}`));
    const clashes = [];
    for (const file of files) {
        const targetBlob = targetBlobs.get(`${targetRef}:${file}`);
        const stageBlob = stageBlobs.get(`${stageRef}:${file}`) || null;
        if (!targetBlob || targetBlob === stageBlob) {
            continue;
        }
        const commits = git(['--literal-pathspecs', 'log', '--full-history', '--format=%H', '-n', String(CLASH_HISTORY_LIMIT), stageRef, '--', file])
            .split('\n').filter(Boolean);
        const seen = new Set(blobsOf(commits.map((c) => `${c}:${file}`)).values());
        if (!seen.has(targetBlob)) {
            clashes.push({ file, targetBlob, stageBlob });
        }
    }
    return clashes;
}

/** Why the promotion clashes, for raise.json and the hub. */
function clashMessage(clashes, stageBranch) {
    const first = clashes[0].file;
    const more = clashes.length > 1 ? ` (and ${clashes.length - 1} more file${clashes.length > 2 ? 's' : ''})` : '';
    return `${target} has a change to ${first}${more} that ${stageBranch} doesn't have (a hotfix not merged back down?). `
        + `Merge ${target} into ${stageBranch} first, then promote again.`;
}

/** Runs git with a long list of paths in chunks, so the command line never gets too long. */
function gitPaths(args, files) {
    for (let i = 0; i < files.length; i += 200) {
        git(['--literal-pathspecs', ...args, '--', ...files.slice(i, i + 200)]);
    }
}

/**
 * A promotion from the stage's state (OPTIONS.stageBranch): a new branch from TARGET where every file the releases'
 * merge commits changed is taken as it is now in the stage branch (or removed when the stage no longer has it).
 * Older stage releases and later fixes to the same files come along, so nothing has to apply as a patch. Before
 * writing, a file whose target version the stage never had (a hotfix only in the target) stops the promotion.
 */
async function promoteFromStage(shas, stageBranch, lines) {
    if (!remoteBranchExists(stageBranch)) {
        raiseFailed(`The stage branch ${stageBranch} doesn't exist, so there's nothing to promote from.`, { fromStage: stageBranch });
    }
    fetchBranch(stageBranch);
    for (const sha of shas) {
        if (gitQuiet(['cat-file', '-t', sha]) !== 'commit') {
            raiseFailed(`Commit ${sha.slice(0, 7)} isn't in the repository. Was its branch rewritten?`, { fromStage: stageBranch });
        }
    }
    const targetRef = `refs/remotes/origin/${target}`;
    const stageRef = `refs/remotes/origin/${stageBranch}`;
    const files = promotedFiles(shas);
    if (!files.length) {
        raiseFailed(`These commits change no files. Nothing to promote.`, { commits: shas, files: 0, fromStage: stageBranch });
    }
    const clashes = promotionClashes(files, targetRef, stageRef);
    if (clashes.length) {
        raiseFailed(clashMessage(clashes, stageBranch), { commits: shas, files: files.length, fromStage: stageBranch,
            conflicts: clashes.map((c) => c.file).slice(0, 50), clash: clashes.slice(0, 50) });
    }
    git(['checkout', '-q', '-B', branch, targetRef]);
    const stageBlobs = blobsOf(files.map((f) => `${stageRef}:${f}`));
    const targetBlobs = blobsOf(files.map((f) => `${targetRef}:${f}`));
    const take = files.filter((f) => stageBlobs.has(`${stageRef}:${f}`));
    const drop = files.filter((f) => !stageBlobs.has(`${stageRef}:${f}`) && targetBlobs.has(`${targetRef}:${f}`));
    if (take.length) {
        gitPaths(['checkout', stageRef], take);
    }
    if (drop.length) {
        gitPaths(['rm', '-q'], drop);
    }
    if (git(['diff', '--cached', '--name-only']) === '') {
        raiseFailed(`${target} already has ${stageBranch}'s version of every file these releases changed. Nothing to promote.`,
            { commits: shas, files: files.length, fromStage: stageBranch });
    }
    const n = shas.length;
    git(['commit', '-q', '-m', `${requestId}: promote ${n} release(s) from ${stageBranch}`, '-m',
        `Takes each file these releases changed as it is in ${stageBranch}:\n${shas.map((x) => '- ' + x).join('\n')}`]);
    git(['push', '-q', 'origin', `HEAD:refs/heads/${branch}`]);
    summary(`**Promotion from ${stageBranch}:** ${files.length} file(s) from ${n} release(s); ${take.length} taken from ${stageBranch}, `
        + `${drop.length} removed.`);
    await openAndRecord(lines(shas), { sha: git(['rev-parse', 'HEAD']), commits: shas, files: files.length, fromStage: stageBranch });
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
    let validatedTree = null;
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
        validatedTree = git(['rev-parse', 'HEAD^{tree}']); // a quick deploy needs exactly this tree
        if (!plan) {
            writeResult('validate', deployExcluded.length
                ? { status: 'Failed', message: nothingLeftMessage(), excluded: deployExcluded.slice(0, 1000), gates: gatesResult(relayGates, []) }
                : { status: 'Skipped', message: 'Nothing deployable changed under ' + sourcePath() + '.', gates: gatesResult(relayGates, []) });
            return;
        }
        // Per-org values are filled for the TARGET org, so a quick deploy of this validation sends them too.
        const valuesProblem = prepareDeployValues(plan, targetEnv);
        if (valuesProblem) {
            writeResult('validate', { status: 'Failed', changed: plan.changed, deleted: plan.deletedList, mergedWith, validatedTree,
                environment: targetEnv, ok: false, message: valuesProblem.slice(0, 1500), gates: gatesResult(relayGates, []) });
            return;
        }
        // Gates that need no org: a broken gates file, Apex without tests. They fail before anything is sent.
        const early = gatesResult(relayGates, evaluateTestsGate(plan.apex, testLevelFor(plan).testLevel, relayGates,
            [...plan.apexDeleted, ...plan.inactiveTriggers]));
        if (!early.passed) {
            gatesSummary('validate', early);
            writeResult('validate', { status: 'Failed', changed: plan.changed, deleted: plan.deletedList, mergedWith, validatedTree,
                environment: targetEnv, ok: false, testLevel: testLevelFor(plan).testLevel, message: early.failures.join(' ').slice(0, 1500),
                gates: early });
            return;
        }
        login('target-org');
    } catch (e) {
        writeResult('validate', { status: 'Error', message: e.message.slice(0, 1500), gates: gatesResult(relayGates, []) });
        return;
    }
    const r = deployTo('target-org', plan, true);
    // The coverage gate reads the coverage of a validation that passed and ran tests.
    let coverageCheck = { failures: [], coverage: null };
    if (r.ok && TESTED_LEVELS.includes(r.testLevel) && r.testsRun > 0) {
        coverageCheck = evaluateCoverageGate(r.codeCoverage, plan.apex, r.testLevel, relayGates, plan.inactiveTriggers);
    }
    const gates = gatesResult(relayGates, coverageCheck.failures);
    gatesSummary('validate', gates);
    const passed = r.ok && gates.passed;
    writeResult('validate', { status: passed ? 'Passed' : 'Failed', changed: plan.changed, deleted: plan.deletedList,
        mergedWith, validatedTree, environment: targetEnv, ...r, ok: passed,
        message: r.ok && !gates.passed ? gates.failures.join(' ').slice(0, 1500) : r.message,
        gates, ...(coverageCheck.coverage ? { coverage: coverageCheck.coverage } : {}) });
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
 * After a failed merge: files that are new on one side only (not in the merge base, missing on the other side) are not
 * real conflicts. Git can still flag them when it pairs a new file with one the other side deleted (a "rename"
 * guessed from identical -meta.xml files). Takes the side that has the file. Returns true when no conflict is left.
 */
function resolveAddedFiles() {
    const files = conflictedFiles();
    if (!files.length) {
        return false;
    }
    const mergeBase = gitQuiet(['merge-base', 'HEAD', 'MERGE_HEAD']);
    for (const file of files) {
        const inBase = mergeBase && gitQuiet(['cat-file', '-e', `${mergeBase.trim()}:${file}`]) !== null;
        const ours = gitQuiet(['cat-file', '-e', `HEAD:${file}`]) !== null;
        const theirs = gitQuiet(['cat-file', '-e', `MERGE_HEAD:${file}`]) !== null;
        if (inBase || (ours && theirs)) {
            return false;
        }
    }
    for (const file of files) {
        const ours = gitQuiet(['cat-file', '-e', `HEAD:${file}`]) !== null;
        git(['checkout', ours ? '--ours' : '--theirs', '--', file]);
        git(['add', '--', file]);
    }
    return conflictedFiles().length === 0;
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
        const files = resolveAddedFiles() ? [] : conflictedFiles();
        if (!files.length && !gitQuiet(['rev-parse', '-q', '--verify', 'MERGE_HEAD'])) {
            throw new Error('Merging ' + branch + ' into ' + target + ' failed: ' + String(e.stderr || e.message).slice(0, 500));
        }
    }
    if (conflictedFiles().length) {
        const files = conflictedFiles();
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
    if (conflictedFiles().length) {
        resolveAddedFiles();
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

/**
 * After a merge: brings TARGET into each branch listed in OPTIONS.syncBranches, in the order given (after a
 * deploy to production: every stage branch, then every developer branch). Each branch merges TARGET directly.
 * A conflict is reported for that branch and left alone, never forced, unless OPTIONS.stageWins is true: then
 * the first listed branch takes TARGET's lines where they differ (-X theirs).
 * Returns [{ branch, status: 'Synced' | 'Conflict' | 'Missing', message }], the merge result's "sync".
 */
function syncDeveloperBranches() {
    const branches = Array.isArray(options.syncBranches) ? options.syncBranches.map(String) : [];
    const out = [];
    if (!branches.length) {
        return out;
    }
    fetchBranch(target);
    const stageWins = options.stageWins === true;
    for (const b of branches) {
        if (b === target) {
            out.push({ branch: b, status: 'Missing', message: `${b} is the branch just merged into.` });
            continue;
        }
        if (!REF_RE.test(b) || b.includes('..') || b === RESULTS_BRANCH) {
            out.push({ branch: b, status: 'Missing', message: 'Not a valid branch name.' });
            continue;
        }
        if (!remoteBranchExists(b)) {
            out.push({ branch: b, status: 'Missing', message: `${b} doesn't exist in the repository.` });
            continue;
        }
        const wins = stageWins && b === branches[0];
        try {
            fetchBranch(b);
            git(['checkout', '-q', '-B', b, `refs/remotes/origin/${b}`]);
            run('git', ['merge', '--no-edit', ...(wins ? ['-X', 'theirs'] : []),
                '-m', `Release Relay ${requestId}: bring ${target} into ${b}`, `refs/remotes/origin/${target}`],
                { stdio: ['ignore', 'pipe', 'pipe'] });
            git(['push', '-q', 'origin', `HEAD:refs/heads/${b}`]);
            out.push({ branch: b, status: 'Synced', message: wins
                ? `${b} now includes ${target} (${target}'s lines win where they differ).` : `${b} now includes ${target}.` });
        } catch (e) {
            if (resolveAddedFiles()) {
                git(['commit', '-q', '--no-edit']);
                git(['push', '-q', 'origin', `HEAD:refs/heads/${b}`]);
                out.push({ branch: b, status: 'Synced', message: `${b} now includes ${target}.` });
                continue;
            }
            const files = conflictedFiles();
            gitQuiet(['merge', '--abort']);
            out.push({ branch: b, status: 'Conflict', message: files.length
                ? `${b} couldn't take ${target} automatically: ${files.length} file(s) conflict (${files.slice(0, 5).join(', ')}).`
                : `${b} couldn't take ${target} automatically: ${String(e.stderr || e.message).slice(0, 300)}` });
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
        sync = [{ branch: '*', status: 'Conflict', message: 'Updating the branches after the merge failed: ' + e.message.slice(0, 300) }];
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
            writeResult('deploy', deployExcluded.length
                ? { status: 'Failed', sha, message: nothingLeftMessage(), excluded: deployExcluded.slice(0, 1000) }
                : { status: 'Deployed', sha, message: 'Nothing deployable changed under ' + sourcePath() + '.' });
            return;
        }
        const valuesProblem = prepareDeployValues(plan, targetEnv);
        if (valuesProblem) {
            writeResult('deploy', { status: 'Failed', sha, changed: plan.changed, deleted: plan.deletedList, message: valuesProblem.slice(0, 1500) });
            process.exit(1);
        }
        login('target-org');
    } catch (e) {
        writeResult('deploy', { status: 'Failed', sha, message: e.message.slice(0, 1500) });
        process.exit(1);
    }
    // The org's current versions of what this deploy changes, for a rollback. Never blocks the deploy.
    const snapshot = takeSnapshot(plan, sha);
    const check = quickDeployCheck(sha);
    let r = null;
    let quickNote = check.note;
    if (check.validation) {
        const val = check.validation;
        console.log(`Quick deploying validation ${val.deployId} (${val.testLevel}, ${val.testsRun || 0} tests run).`);
        const q = runDeploy(['project', 'deploy', 'quick', '--job-id', val.deployId, '--target-org', 'target-org',
            '--wait', DEPLOY_WAIT, '--json'], val.testLevel, Array.isArray(val.tests) ? val.tests : []);
        if (q.ok) {
            r = { ...q, deployId: q.deployId || val.deployId, testsRun: Number(val.testsRun || 0), validationId: val.deployId };
            quickNote = `Quick deployed validation ${val.deployId}: ` + (TESTED_LEVELS.includes(val.testLevel)
                ? 'its tests already passed, so none ran again.' : 'a sandbox validation that ran no tests.');
            r.message = quickNote;
        } else {
            quickNote = `Quick deploy of validation ${val.deployId} was refused (${String(q.message || 'no reason given').slice(0, 500)}), so the release was deployed in full.`;
        }
    }
    const quick = r !== null;
    if (!quick) {
        r = deployTo('target-org', plan, false);
        if (check.validation && r.ok) {
            r.message = quickNote; // the fallback worked: say why it wasn't a quick deploy
        }
    }
    writeResult('deploy', { status: r.ok ? 'Deployed' : 'Failed', sha, changed: plan.changed, deleted: plan.deletedList,
        ...r, quick, quickNote: quickNote || '', snapshot });
    if (!r.ok) {
        process.exit(1);
    }
}

const QUICK_DEPLOY_DAYS = 10;
const TESTED_LEVELS = ['RunSpecifiedTests', 'RunLocalTests', 'RunAllTestsInOrg'];

/** This release's validate.json from the results branch, or null. */
function validationResult() {
    try {
        if (!remoteBranchExists(RESULTS_BRANCH)) {
            return null;
        }
        fetchBranch(RESULTS_BRANCH);
        const raw = gitQuiet(['show', `refs/remotes/origin/${RESULTS_BRANCH}:results/${requestId}/validate.json`]);
        return raw ? JSON.parse(raw) : null;
    } catch (e) {
        return null;
    }
}

/** Whether the target org is a sandbox (null when it can't be told). */
function targetIsSandbox() {
    try {
        const out = JSON.parse(run('sf', ['data', 'query', '--query', 'SELECT IsSandbox FROM Organization',
            '--target-org', 'target-org', '--json']));
        const rows = (out.result && out.result.records) || [];
        return rows.length ? rows[0].IsSandbox === true : null;
    } catch (e) {
        return null;
    }
}

/**
 * Can this merge be deployed as a quick deploy of the release's validation? Only when OPTIONS.quickDeploy
 * isn't false, the validation passed in this target's org less than 10 days ago with a deploy id, it ran
 * tests (a NoTestRun validation only in a sandbox: production never quick deploys one), and the merge is
 * exactly what was validated: the merge's target-side parent is the target commit the validation merged
 * with, and the merged tree is the validated tree. Returns { validation } or { note } (why not).
 */
function quickDeployCheck(sha) {
    if (options.quickDeploy === false) {
        return { note: 'Quick deploy is off for this release.' };
    }
    const val = validationResult();
    if (!val) {
        return { note: 'No validation result for this release, so it was deployed in full.' };
    }
    if (val.status !== 'Passed' || val.ok !== true || typeof val.deployId !== 'string' || !/^[A-Za-z0-9]{15,18}$/.test(val.deployId)) {
        return { note: `The validation didn't pass with a deployment id (${val.status || 'no status'}), so it was deployed in full.` };
    }
    // The validation must have used the same exclude setting: an older pipeline's validation included every file.
    if ((val.selfUpdate === true) !== selfUpdate() || (!selfUpdate() && !Array.isArray(val.excluded) && deployExcluded.length)) {
        return { note: 'The validation used a different exclude list setting (selfUpdate, or a pipeline before version 11), so it was deployed in full.' };
    }
    // The validation sent the per-org values of its time: a change to .relay/values.json since then needs a full deploy.
    const validatedValues = val.values && typeof val.values.hash === 'string' ? val.values.hash : '';
    if (validatedValues !== ((deployValues && deployValues.hash) || '')) {
        return { note: `The per-org values (${VALUES_FILE}) aren't the ones the validation used, so it was deployed in full.` };
    }
    if (val.environment && val.environment !== targetEnv) {
        return { note: `The validation ran against ${val.environment}, not ${targetEnv}, so it was deployed in full.` };
    }
    const finished = Date.parse(val.finishedAt || '');
    if (!finished || Date.now() - finished > QUICK_DEPLOY_DAYS * 24 * 3600 * 1000) {
        return { note: `The validation is older than ${QUICK_DEPLOY_DAYS} days (Salesforce keeps one for quick deploy that long), so it was deployed in full.` };
    }
    if (!SHA_RE.test(val.mergedWith || '') || !val.validatedTree) {
        return { note: 'The validation didn\'t record the target commit and files it checked (validated without the target merged in, or by an older pipeline), so it was deployed in full.' };
    }
    const parent = gitQuiet(['rev-parse', `${sha}^1`]);
    if (parent !== val.mergedWith) {
        return { note: `${target} moved after the validation (validated against ${val.mergedWith.slice(0, 7)}, merged onto ${String(parent || '?').slice(0, 7)}), so it was deployed in full.` };
    }
    if (gitQuiet(['rev-parse', `${sha}^{tree}`]) !== val.validatedTree) {
        return { note: 'The merged files differ from the validated ones (the branch changed after the validation), so it was deployed in full.' };
    }
    if (!TESTED_LEVELS.includes(val.testLevel)) {
        const sandbox = targetIsSandbox();
        if (sandbox !== true) {
            return { note: sandbox === false
                ? 'The validation ran no tests (NoTestRun), and production quick deploys only validations that ran tests, so it was deployed in full.'
                : 'The validation ran no tests (NoTestRun) and the org couldn\'t be confirmed as a sandbox, so it was deployed in full.' };
        }
    }
    return { validation: val };
}

// ---------- step: sync (back promote) ----------

const APEX_TYPES = new Set(['ApexClass', 'ApexTrigger']);

/** The first few component errors of a failed deploy, for the result's message. */
function deployFailureText(r) {
    const errors = (r.componentErrors || []).slice(0, 5).map((c) => `${c.type || ''} ${c.name || ''}: ${c.problem || ''}`.trim());
    const tests = (r.testFailures || []).slice(0, 5).map((t) => `${t.name || ''}.${t.method || ''}: ${t.message || ''}`);
    return [r.message || 'Deployment failed'].concat(errors, tests).join(' | ').slice(0, 1500);
}

/**
 * MODE=sync: brings BRANCH (the hub's production branch) into TARGET (a back-promote org's branch) and
 * deploys what that changed to TARGET_ENVIRONMENT's org. TARGET is pushed only after the deploy worked, so
 * it always matches what the org received. A missing TARGET is made from BRANCH: the org is taken to match
 * production already (a sandbox made from it), so that first sync deploys nothing.
 * Writes results/<REQUEST_ID>/sync.json:
 * { status: 'Deployed' | 'Nothing to deploy' | 'Conflict' | 'Failed', sha, deployId, testsRun, conflicts, message }.
 */
/** options.paths (version 23): the picked repo paths of a back promote, checked; null for a full back promote. */
function pickedPaths() {
    if (!Array.isArray(options.paths) || !options.paths.length) {
        return null;
    }
    if (options.paths.length > 2000) {
        fail('A back promote takes at most 2,000 picked paths.');
    }
    const root = sourcePath().replace(/\/+$/, '') + '/';
    return options.paths.map((p) => {
        const f = String(p).trim();
        if (!f.startsWith(root) || f.includes('..') || !/^[A-Za-z0-9 _.,@()+'%&$#~=\[\]/-]{1,400}$/.test(f)) {
            fail(`Picked path "${f.slice(0, 120)}" isn't a file under ${root}.`);
        }
        return f;
    });
}

/** A file's blob id at a commit, or null when it isn't there. */
function blobAt(ref, file) {
    return gitQuiet(['rev-parse', '--verify', '-q', `${ref}:${file}`]) || null;
}

/**
 * Takes the picked paths from BRANCH onto the checked-out TARGET (a path BRANCH no longer has is removed) and commits.
 * A path TARGET changed since the merge base, to something else than BRANCH has, is a conflict: then nothing is taken.
 * Returns the conflicting paths.
 */
function takePickedPaths(paths, lowerHead) {
    const higher = `refs/remotes/origin/${branch}`;
    const base = gitQuiet(['merge-base', higher, lowerHead]) || null;
    const take = [];
    const remove = [];
    const conflicts = [];
    for (const f of paths) {
        const hi = blobAt(higher, f);
        const lo = blobAt(lowerHead, f);
        if (hi === lo) {
            continue; // already the same
        }
        const was = base ? blobAt(base, f) : null;
        if (lo !== was && base) {
            conflicts.push(f); // changed below too: never overwritten
            continue;
        }
        (hi ? take : remove).push(f);
    }
    if (conflicts.length) {
        return conflicts;
    }
    for (let i = 0; i < take.length; i += 200) {
        git(['checkout', higher, '--', ...take.slice(i, i + 200)]);
    }
    for (let i = 0; i < remove.length; i += 200) {
        git(['rm', '-q', '--ignore-unmatch', '--', ...remove.slice(i, i + 200)]);
    }
    if (take.length || remove.length) {
        const keys = Array.isArray(options.keys) ? options.keys.map(String).slice(0, 20).join(', ') : '';
        git(['-c', 'user.name=Release Relay', '-c', 'user.email=release-relay@users.noreply.local', 'commit', '-q', '-m',
            `Release Relay ${requestId}: back promote ${take.length + remove.length} file(s) from ${branch}`
                + (keys ? `\n\nPicked: ${keys}${options.keys.length > 20 ? ', …' : ''}` : '')]);
    }
    return [];
}

/**
 * Push to the org (version 23): BRANCH = TARGET, options.paths picked. Deploys just those components from the branch as
 * it is (a picked path the branch hasn't got is deleted from the org); the branch isn't changed.
 */
async function pushPickedToOrg(result, stop, branchOnly) {
    const paths = pickedPaths();
    if (!paths) {
        stop({ message: 'Pushing to the org needs picked paths.' });
    }
    if (branchOnly || !targetEnv) {
        stop({ message: `Pushing to the org needs its environment: ${target}'s org has no sign-in in GitHub.` });
    }
    let head;
    let plan;
    try {
        if (!remoteBranchExists(target)) {
            throw new Error(`Branch ${target} doesn't exist.`);
        }
        fetchBranch(target);
        head = git(['rev-parse', `refs/remotes/origin/${target}`]);
        git(['checkout', '-q', '--force', '--detach', head]);
        plan = buildForPaths(paths, head);
        if (!plan) {
            result('Nothing to deploy', { sha: head, message: `Nothing deployable among the picked files.${excludedNote()}` });
            return;
        }
        const valuesProblem = prepareDeployValues(plan, targetEnv);
        if (valuesProblem) {
            stop({ sha: head, message: `${valuesProblem} Nothing was deployed.`.slice(0, 1500) });
        }
        login('target-org');
    } catch (e) {
        stop({ sha: head || null, message: String(e.message || e).slice(0, 1500) });
    }
    plan.ownTests = false;
    plan.defaultTestLevel = plan.apex.length ? 'RunLocalTests' : 'NoTestRun';
    const snapshot = takeSnapshot(plan, head);
    const r = deployTo('target-org', plan, false);
    if (!r.ok) {
        stop({ sha: head, deployId: r.deployId || null, testsRun: r.testsRun || 0, snapshot,
            message: `Deploying the picked components to ${targetEnv} failed: ${deployFailureText(r)}` });
    }
    result('Deployed', { sha: head, deployId: r.deployId || null, testsRun: r.testsRun || 0, snapshot,
        message: `Deployed ${pickedCount(plan.sources)} picked component(s)${plan.deleted ? ` and deleted ${plan.deleted}` : ''} from ${target} to ${targetEnv} (${r.testLevel}). The branch wasn't changed.${excludedNote()}` });
}

/** How many components some deployed files are (a class and its -meta.xml are one). */
function pickedCount(files) {
    return new Set(files.map((f) => {
        const c = componentFor(f);
        return c ? `${c.type}:${c.name}` : f;
    })).size;
}

async function stepSync() {
    orgEnv = sourceEnv;
    if (mode !== 'sync') {
        fail('STEP=sync needs MODE=sync.');
    }
    const result = (status, data) => writeResult('sync', { status, sha: null, deployId: null, testsRun: 0,
        conflicts: [], message: '', ...data });
    const stop = (data) => {
        result('Failed', data);
        process.exit(1);
    };
    checkAllowedTarget(); // runs not started by the hub: TARGET must be in the source's ALLOWED_TARGETS
    orgEnv = targetEnv;
    const branchOnly = options.branchOnly === true; // version 23: a developer org's branch only (no GitHub sign-in)
    if (!targetEnv && !branchOnly) {
        stop({ message: 'No target environment: a back promote needs the org to deploy to.' });
    }
    if (branch === target) {
        await pushPickedToOrg(result, stop, branchOnly);
        return;
    }
    let oldHead = null;
    let head;
    try {
        fetchBranch(branch);
        if (remoteBranchExists(target)) {
            fetchBranch(target);
            oldHead = git(['rev-parse', `refs/remotes/origin/${target}`]);
            git(['checkout', '-q', '-B', target, oldHead]);
            if (pickedPaths()) {
                // Version 23: back promote picked files only (the Sync status tab), never a full merge.
                const conflicts = takePickedPaths(pickedPaths(), oldHead);
                if (conflicts.length) {
                    result('Conflict', { sha: git(['rev-parse', `refs/remotes/origin/${branch}`]), conflicts: conflicts.slice(0, 200),
                        message: `${conflicts.length} picked file(s) were changed in ${target} too. Nothing was deployed or pushed. `
                            + `Bring them into ${target} by hand (or pick without them), then back promote again.` });
                    process.exit(1);
                }
            } else {
                try {
                    run('git', ['merge', '--no-edit', '-m', `Release Relay ${requestId}: back promote ${branch} into ${target}`,
                        `refs/remotes/origin/${branch}`], { stdio: ['ignore', 'pipe', 'pipe'] });
                } catch (e) {
                    if (resolveAddedFiles()) {
                        git(['commit', '-q', '--no-edit']);
                    } else {
                        const files = conflictedFiles();
                        gitQuiet(['merge', '--abort']);
                        if (!files.length) {
                            throw new Error(`Merging ${branch} into ${target} failed: ${String(e.stderr || e.message).slice(0, 500)}`);
                        }
                        result('Conflict', { sha: git(['rev-parse', `refs/remotes/origin/${branch}`]), conflicts: files.slice(0, 200),
                            message: `${files.length} file(s) in ${target} conflict with ${branch}. Nothing was deployed or pushed. `
                                + `Bring ${branch} into ${target} by hand (keep ${branch}'s lines), then sync again.` });
                        process.exit(1);
                    }
                }
            }
        } else if (pickedPaths()) {
            throw new Error(`Back promoting picked components needs ${target} to exist.`);
        } else {
            git(['checkout', '-q', '-B', target, `refs/remotes/origin/${branch}`]);
        }
        head = git(['rev-parse', 'HEAD']);
    } catch (e) {
        stop({ message: String(e.message || e).slice(0, 1500) });
    }

    const push = () => git(['push', '-q', 'origin', `HEAD:refs/heads/${target}`]);
    if (branchOnly) {
        // A developer org has no sign-in in GitHub: only its branch is brought up to date.
        try {
            push();
        } catch (e) {
            stop({ sha: head, message: `Pushing ${target} failed (branch rules?): ${String(e.message || e).slice(0, 500)}` });
        }
        const what = pickedPaths() ? `${pickedPaths().length} picked file(s)` : `everything from ${branch}`;
        result('Succeeded', { sha: head, message: oldHead === head ? `${target} already had ${what}; nothing changed.`
            : `${target} was updated with ${what}. The org itself wasn't deployed to (a developer org has no sign-in in GitHub): `
                + 'deploy to it from the branch, or raise from it again.' });
        return;
    }
    let plan = null;
    let apexChanged = false;
    try {
        if (oldHead && oldHead !== head) {
            plan = buildDeployment(oldHead, head);
            apexChanged = changedFiles(oldHead, head).some((f) => {
                const c = componentFor(f.file);
                return c && APEX_TYPES.has(c.type);
            });
        }
        if (!plan) {
            push();
            result('Nothing to deploy', { sha: head, message: !oldHead
                ? `Made ${target} from ${branch}. The org is taken to match ${branch} already, so nothing was deployed; later syncs deploy what changes.`
                : oldHead === head ? (pickedPaths() ? `The picked files are already the same in ${target}.` : `${target} already includes ${branch}.`)
                    : `Nothing deployable changed under ${sourcePath()}. ${target} now includes ${branch}.${excludedNote()}` });
            return;
        }
        const valuesProblem = prepareDeployValues(plan, targetEnv);
        if (valuesProblem) {
            stop({ sha: head, message: `${valuesProblem} Nothing was deployed or pushed.`.slice(0, 1500) });
        }
        login('target-org');
    } catch (e) {
        stop({ sha: head, message: String(e.message || e).slice(0, 1500) });
    }
    plan.ownTests = false;
    plan.defaultTestLevel = apexChanged ? 'RunLocalTests' : 'NoTestRun';
    const snapshot = takeSnapshot(plan, head);
    const r = deployTo('target-org', plan, false);
    if (!r.ok) {
        stop({ sha: head, deployId: r.deployId || null, testsRun: r.testsRun || 0, snapshot,
            message: `Deploying to ${targetEnv} failed, so ${target} wasn't updated: ${deployFailureText(r)}` });
    }
    try {
        push();
    } catch (e) {
        stop({ sha: head, deployId: r.deployId || null, testsRun: r.testsRun || 0, snapshot,
            message: `Deployed to ${targetEnv}, but pushing ${target} failed (branch rules?). The next sync deploys these changes again: ${String(e.message || e).slice(0, 500)}` });
    }
    result('Deployed', { sha: head, deployId: r.deployId || null, testsRun: r.testsRun || 0, snapshot,
        message: `Deployed ${plan.changed} change(s)${plan.deleted ? ` and ${plan.deleted} deletion(s)` : ''} from ${branch} (${r.testLevel}).${excludedNote()}` });
}

// ---------- rollback snapshots ----------

const SNAPSHOT_PATH_RE = /^REL-\d{5,}\/[A-Za-z0-9._-]{1,80}\/[A-Za-z0-9._-]{1,80}$/;

/** A path segment from a name: letters, digits, . _ - only. */
function safeSegment(value) {
    const s = String(value || '').replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 80);
    return !s || /^\.+$/.test(s) ? '_' : s;
}

/** This run's id for the snapshot folder: the hub's attempt token, else the provider's run id. */
function snapshotRunId() {
    if (runToken) {
        return runToken;
    }
    if (env.GITHUB_RUN_ID) {
        return `${env.GITHUB_RUN_ID}-${env.GITHUB_RUN_ATTEMPT || '1'}`;
    }
    return env.CI_JOB_ID || env.BITBUCKET_BUILD_NUMBER || env.BUILD_BUILDID || String(Date.now());
}

function xmlUnescape(value) {
    return value.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
}

/** The Type:Name members of a package.xml (or destructiveChanges*.xml). */
function parsePackageXml(xml) {
    const items = [];
    for (const block of String(xml || '').matchAll(/<types>([\s\S]*?)<\/types>/g)) {
        const type = (/<name>\s*([^<]+?)\s*<\/name>/.exec(block[1]) || [])[1];
        if (!type) {
            continue;
        }
        for (const m of block[1].matchAll(/<members>\s*([^<]+?)\s*<\/members>/g)) {
            items.push({ type, name: xmlUnescape(m[1]) });
        }
    }
    return items;
}

/**
 * Sorts the components a snapshot asked for by what the retrieve said: found (in fileProperties), absent (a
 * "cannot be found" message: the deploy adds them) or unresolved (neither; never restored or deleted by a rollback).
 */
function classifyRetrieved(requested, fileProperties, messages) {
    const have = new Set();
    for (const fp of asList(fileProperties)) {
        if (fp && fp.type && fp.fullName) {
            have.add(`${fp.type}:${fp.fullName}`.toLowerCase());
        }
    }
    const missing = new Set();
    for (const m of asList(messages)) {
        const text = typeof m === 'string' ? m : String((m && (m.problem || m.message)) || '');
        const hit = /Entity of type '([^']+)' named '([^']+)' cannot be found/i.exec(text);
        if (hit) {
            missing.add(`${hit[1]}:${hit[2]}`.toLowerCase());
        }
    }
    const haveList = [...have];
    const found = [];
    const absent = [];
    const unresolved = [];
    for (const c of requested) {
        const key = `${c.type}:${c.name}`.toLowerCase();
        if (have.has(key) || haveList.some((h) => h.startsWith(key + '/'))) {
            found.push(c);
        } else if (missing.has(key)) {
            absent.push(c);
        } else {
            unresolved.push(c);
        }
    }
    return { found, absent, unresolved };
}

/**
 * manifest.json of a snapshot: { request, environment, takenAt, sha, existing, added, deleted, unresolved }, each list
 * Type:Name. existing: deployed components the org already had (restored by a rollback); added: deployed components
 * the org didn't have (deleted by a rollback); deleted: components the release deletes that the org had (restored);
 * unresolved: components the retrieve said nothing about (left alone).
 */
function buildSnapshotManifest(meta, deployItems, deletedItems, classified) {
    const key = (c) => `${c.type}:${c.name}`;
    const found = new Set(classified.found.map(key));
    const absent = new Set(classified.absent.map(key));
    const deployKeys = [...new Set(deployItems.map(key))];
    const deletedKeys = [...new Set(deletedItems.map(key))].filter((k) => !deployKeys.includes(k));
    return {
        request: meta.request,
        environment: meta.environment,
        takenAt: meta.takenAt,
        sha: meta.sha,
        existing: deployKeys.filter((k) => found.has(k)).sort(),
        added: deployKeys.filter((k) => absent.has(k)).sort(),
        deleted: deletedKeys.filter((k) => found.has(k)).sort(),
        unresolved: [...new Set(classified.unresolved.map(key))].sort()
    };
}

/** Removes Release Relay's own fields (exclude list) from Metadata API object files, so a rollback never sends them. */
function stripExcludedFields(objectName, xml) {
    return xml.replace(/[ \t]*<fields>\s*<fullName>([^<]+)<\/fullName>[\s\S]*?<\/fields>\s*\n?/g, (block, fullName) =>
        (excludeHit(`objects/${objectName}/fields/${fullName.trim()}.field-meta.xml`, () => false) ? '' : block));
}

function walkFiles(root) {
    if (!fs.existsSync(root)) {
        return [];
    }
    return fs.readdirSync(root, { recursive: true }).map(String).filter((f) => fs.statSync(path.join(root, f)).isFile())
        .map((f) => f.split(path.sep).join('/')).sort();
}

/**
 * Before a real deploy: retrieves the org's current versions of the deployment's components and of the components it
 * deletes (Metadata API format), and commits them with manifest.json to release-relay-snapshots at
 * <REQUEST_ID>/<environment>/<run id>/. Returns deploy.json's "snapshot": { branch, path, existing, added },
 * { skipped } or { error } (a failed snapshot is a warning; the deploy goes ahead).
 */
function takeSnapshot(plan, sha) {
    if (options.snapshot === false) {
        return { skipped: 'Snapshots are off for this release (options.snapshot is false).' };
    }
    if (selfUpdate()) {
        return { skipped: 'The hub updating itself (selfUpdate) takes no snapshot.' };
    }
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-snapshot-'));
    try {
        const deployItems = parsePackageXml(fs.readFileSync(plan.pkg, 'utf8')).filter((c) => !c.name.includes('*'));
        const deletedItems = plan.destructive ? parsePackageXml(fs.readFileSync(plan.destructive, 'utf8')) : [];
        const requested = [...new Map(deployItems.concat(deletedItems).map((c) => [`${c.type}:${c.name}`, c])).values()];
        if (!requested.length) {
            return { skipped: 'Nothing to snapshot.' };
        }
        const requestPkg = path.join(tmp, 'package.xml');
        fs.writeFileSync(requestPkg, manifest(apiVersion(), requested));
        const retrieveDir = path.join(tmp, 'retrieve');
        fs.mkdirSync(retrieveDir);
        let raw;
        try {
            raw = execFileSync('sf', ['project', 'retrieve', 'start', '--manifest', requestPkg, '--target-metadata-dir', retrieveDir,
                '--target-org', 'target-org', '--wait', '30', '--json'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 });
        } catch (e) {
            raw = e.stdout ? String(e.stdout) : '';
            if (!raw) {
                throw new Error('The retrieve failed: ' + String(e.stderr || e.message).replace(/\s+/g, ' ').slice(0, 400));
            }
        }
        let out;
        try {
            out = JSON.parse(raw);
        } catch (e) {
            throw new Error('The Salesforce CLI returned output that isn\'t JSON.');
        }
        const r = out.result || {};
        if (out.status !== 0 && !r.fileProperties) {
            throw new Error('The retrieve failed: ' + String(out.message || r.errorMessage || 'no reason given').slice(0, 400));
        }
        const zip = walkFiles(retrieveDir).find((f) => f.endsWith('.zip'));
        const extracted = path.join(tmp, 'extracted');
        fs.mkdirSync(extracted);
        if (zip) {
            execFileSync('unzip', ['-q', '-o', path.join(retrieveDir, zip), '-d', extracted], { stdio: ['ignore', 'pipe', 'pipe'] });
        }
        const pkgFile = walkFiles(extracted).filter((f) => f.split('/').pop() === 'package.xml').sort((a, b) => a.length - b.length)[0];
        const root = pkgFile ? path.join(extracted, path.dirname(pkgFile)) : extracted;
        const messages = asList(r.messages).concat(asList(r.response && r.response.messages), asList(out.warnings));
        const classified = classifyRetrieved(requested, r.fileProperties, messages);
        if (classified.found.length && !zip) {
            throw new Error('The retrieve returned no files.');
        }
        const snap = buildSnapshotManifest({ request: requestId, environment: targetEnv, takenAt: new Date().toISOString(), sha },
            deployItems, deletedItems, classified);
        const keep = snap.existing.concat(snap.deleted).map((k) => {
            const m = /^([^:]+):(.+)$/.exec(k);
            return { type: m[1], name: m[2] };
        });
        // The snapshot's package.xml names exactly what it holds, so a rollback can deploy the folder as it is.
        fs.writeFileSync(path.join(root, 'package.xml'), manifest(apiVersion(), keep));
        for (const f of walkFiles(root).filter((x) => /^objects\/[^/]+\.object$/.test(x))) {
            const file = path.join(root, f);
            fs.writeFileSync(file, stripExcludedFields(path.basename(f, '.object'), fs.readFileSync(file, 'utf8')));
        }
        const snapPath = `${requestId}/${safeSegment(targetEnv)}/${safeSegment(snapshotRunId())}`;
        const manifestFile = path.join(tmp, 'manifest.json');
        fs.writeFileSync(manifestFile, JSON.stringify(snap, null, 1) + '\n');
        const files = [{ rel: `${snapPath}/manifest.json`, abs: manifestFile }].concat(walkFiles(root)
            .filter((f) => !/[\t\n\r]/.test(f)).map((f) => ({ rel: `${snapPath}/metadata/${f}`, abs: path.join(root, f) })));
        commitFilesToBranch(SNAPSHOT_BRANCH, snapPath, files, `${requestId} ${targetEnv}: snapshot before deploying ${String(sha).slice(0, 7)}`);
        summary(`**Snapshot:** ${snap.existing.length} component(s) as they were in ${targetEnv}, ${snap.added.length} new, `
            + `${snap.deleted.length} to be deleted, saved to ${SNAPSHOT_BRANCH} at \`${snapPath}\` (MODE=rollback restores it).`
            + (snap.unresolved.length ? ` ${snap.unresolved.length} component(s) couldn't be told apart (not rolled back): ${snap.unresolved.slice(0, 5).join(', ')}.` : ''));
        return { branch: SNAPSHOT_BRANCH, path: snapPath, existing: snap.existing.length, added: snap.added.length };
    } catch (e) {
        const message = String((e && e.message) || e).slice(0, 500);
        console.log(`::warning::No rollback snapshot was taken: ${message}`);
        summary(`**Snapshot:** not taken (${message}). The deploy goes ahead; this deploy can't be rolled back by Release Relay.`);
        return { error: message };
    } finally {
        fs.rmSync(tmp, { recursive: true, force: true });
    }
}

// ---------- step: rollback ----------

/** The snapshot to roll back to: options.snapshotPath, else the latest for this release and environment. */
function findSnapshot() {
    if (!remoteBranchExists(SNAPSHOT_BRANCH)) {
        throw new Error(`There are no snapshots yet (no ${SNAPSHOT_BRANCH} branch): nothing was deployed by pipeline version 13 or later.`);
    }
    fetchTip(SNAPSHOT_BRANCH);
    const tip = `refs/remotes/origin/${SNAPSHOT_BRANCH}`;
    const envDir = `${requestId}/${safeSegment(targetEnv)}`;
    let snapPath = typeof options.snapshotPath === 'string' ? options.snapshotPath.trim().replace(/\/+$/, '') : '';
    if (snapPath) {
        if (!SNAPSHOT_PATH_RE.test(snapPath) || !snapPath.startsWith(envDir + '/') || snapPath.split('/').some((s) => /^\.+$/.test(s))) {
            throw new Error(`snapshotPath "${snapPath.slice(0, 200)}" must look like ${envDir}/<id>: a snapshot of this release in this environment.`);
        }
    } else {
        const ids = (gitQuiet(['ls-tree', '--name-only', `${tip}:${envDir}`]) || '').split('\n').filter(Boolean);
        if (!ids.length) {
            throw new Error(`No snapshot of ${targetEnv} for ${requestId}: Release Relay (version 13 or later) hasn't deployed it there, or snapshots were off.`);
        }
        const dated = ids.map((id) => {
            let takenAt = '';
            try {
                takenAt = String(JSON.parse(gitQuiet(['show', `${tip}:${envDir}/${id}/manifest.json`]) || '{}').takenAt || '');
            } catch (e) {
                takenAt = '';
            }
            return { id, takenAt };
        }).sort((a, b) => (a.takenAt < b.takenAt ? 1 : a.takenAt > b.takenAt ? -1 : (a.id < b.id ? 1 : -1)));
        snapPath = `${envDir}/${dated[0].id}`;
    }
    const raw = gitQuiet(['show', `${tip}:${snapPath}/manifest.json`]);
    if (!raw) {
        throw new Error(`Snapshot ${snapPath} isn't on ${SNAPSHOT_BRANCH}.`);
    }
    let snap;
    try {
        snap = JSON.parse(raw);
    } catch (e) {
        throw new Error(`${snapPath}/manifest.json on ${SNAPSHOT_BRANCH} isn't valid JSON.`);
    }
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-rollback-'));
    process.on('exit', () => fs.rmSync(tmp, { recursive: true, force: true }));
    const dir = path.join(tmp, 'x', snapPath, 'metadata');
    if (gitQuiet(['cat-file', '-e', `${tip}:${snapPath}/metadata`]) !== null) {
        const tar = path.join(tmp, 'snapshot.tar');
        git(['archive', '--format=tar', '-o', tar, tip, '--', `${snapPath}/metadata`]);
        fs.mkdirSync(path.join(tmp, 'x'));
        execFileSync('tar', ['-xf', tar, '-C', path.join(tmp, 'x')], { stdio: ['ignore', 'pipe', 'pipe'] });
    }
    fs.mkdirSync(dir, { recursive: true });
    return { path: snapPath, manifest: snap, dir };
}

/** Type:Name strings to items, Release Relay's own components left out. Returns { keep, skipped }. */
function rollbackItems(list) {
    const keep = [];
    const skipped = [];
    for (const entry of asList(list).map(String)) {
        const m = /^([A-Za-z]{2,80}):(.+)$/.exec(entry);
        if (!m) {
            continue;
        }
        (componentExcluded(m[1], m[2]) ? skipped : keep).push({ type: m[1], name: m[2], entry });
    }
    return { keep, skipped };
}

/**
 * MODE=rollback: deploys a snapshot back into TARGET_ENVIRONMENT's org: the components it holds (existing and deleted)
 * as they were, and destructiveChangesPost for the ones the deploy added. Release branches aren't touched.
 * Writes results/<REQUEST_ID>/rollback.json:
 * { status: 'Rolled back' | 'Failed', environment, deployId, restored, removed, snapshot, message, testLevel, testsRun,
 *   componentErrors, testFailures }.
 */
async function stepRollback() {
    orgEnv = targetEnv;
    const result = (status, data) => writeResult('rollback', { status, environment: targetEnv || null, deployId: null,
        restored: 0, removed: 0, snapshot: null, message: '', ...data });
    const stop = (data) => {
        result('Failed', data);
        process.exit(1);
    };
    if (mode !== 'rollback') {
        fail('STEP=rollback needs MODE=rollback.');
    }
    let snap;
    try {
        snap = findSnapshot();
    } catch (e) {
        stop({ message: String(e.message || e).slice(0, 1500) });
    }
    const restore = rollbackItems(asList(snap.manifest.existing).concat(asList(snap.manifest.deleted)));
    const remove = rollbackItems(snap.manifest.added);
    const skipped = restore.skipped.concat(remove.skipped).map((c) => c.entry);
    if (!restore.keep.length && !remove.keep.length) {
        stop({ snapshot: snap.path, message: `Snapshot ${snap.path} holds nothing to roll back`
            + (skipped.length ? ` (only Release Relay's own components: ${skipped.slice(0, 5).join(', ')}).` : '.') });
    }
    fs.writeFileSync(path.join(snap.dir, 'package.xml'), manifest(apiVersion(), restore.keep));
    const destructive = path.join(snap.dir, 'destructiveChangesPost.xml');
    fs.rmSync(destructive, { force: true });
    if (remove.keep.length) {
        fs.writeFileSync(destructive, manifest(apiVersion(), remove.keep));
    }
    try {
        login('target-org');
    } catch (e) {
        stop({ snapshot: snap.path, message: String(e.message || e).slice(0, 1500) });
    }
    const tests = releaseTests();
    const apex = restore.keep.concat(remove.keep).some((c) => APEX_TYPES.has(c.type));
    // Tests given: those. Apex in production (or an org not confirmed as a sandbox): every local test. Else none.
    const testLevel = tests && tests.length ? 'RunSpecifiedTests' : (apex && targetIsSandbox() !== true ? 'RunLocalTests' : 'NoTestRun');
    const args = ['project', 'deploy', 'start', '--metadata-dir', snap.dir, '--target-org', 'target-org',
        '--test-level', testLevel, '--wait', DEPLOY_WAIT, '--json'];
    if (testLevel === 'RunSpecifiedTests') {
        tests.forEach((t) => args.push('--tests', t));
    }
    const r = runDeploy(args, testLevel, testLevel === 'RunSpecifiedTests' ? tests : []);
    const details = { deployId: r.deployId || null, snapshot: snap.path, testLevel, testsRun: r.testsRun || 0,
        componentErrors: r.componentErrors || [], testFailures: r.testFailures || [] };
    const skippedNote = skipped.length ? ` ${skipped.length} Release Relay component(s) were left alone (exclude list).` : '';
    if (!r.ok) {
        stop({ ...details, message: `Rolling ${targetEnv} back to snapshot ${snap.path} failed, so the org is unchanged: ${deployFailureText(r)}` });
    }
    const taken = snap.manifest.takenAt ? ` (taken ${snap.manifest.takenAt}` + (snap.manifest.sha ? `, before deploying ${String(snap.manifest.sha).slice(0, 7)})` : ')') : '';
    const message = `Rolled ${targetEnv} back to snapshot ${snap.path}${taken}: restored ${restore.keep.length} component(s), `
        + `removed ${remove.keep.length} the release had added (${testLevel}).${skippedNote} Git wasn't changed: a follow-up release brings the branches in line.`;
    summary(`**Rollback:** ${message}`);
    result('Rolled back', { ...details, restored: restore.keep.length, removed: remove.keep.length, message });
}

// ---------- step: auto (one job runs everything MODE needs) ----------

async function stepAuto() {
    if (mode === 'sync') {
        await stepSync();
    } else if (mode === 'rollback') {
        await stepRollback();
    } else if (['org', 'branch', 'promote', 'hub', 'resolve'].includes(mode)) {
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
        // The CLI signs the call itself: newer CLIs hide the access token in "sf org display".

        const out = run('sf', ['api', 'request', 'rest', '/services/apexrest/release-relay/v1/status', '--method', 'POST',
            '--body', JSON.stringify({ request: requestId }), '--target-org', 'relay-notify']);
        let json = null;
        try { json = JSON.parse(out); } catch (ignore) { json = null; }
        summary(`Salesforce updated ${requestId}: ${json && json.status ? json.status : 'done'}.`);
    } catch (e) {
        // The scheduled sync or an open release page picks the result up anyway.
        summary(`Couldn't tell Salesforce about ${requestId} (${e.message}). It catches up on its next sync.`);
    }
}

// ---------- step: compare (version 22) ----------

/** A compare's id: CMP- and the hub's clock in milliseconds. */
const COMPARE_ID_RE = /^CMP-(\d{13})$/;
/** Sync status runs (version 23): SYN-<13 digits>. */
const SYNC_ID_RE = /^SYN-(\d{13})$/;
/** Where the hub leaves a compare's zips on the results branch: compare-inbox/<id>/<n>.zip. */
const COMPARE_INBOX = 'compare-inbox';
/** The most characters a side (or a unified diff) can have to be shown by the hub. */
const COMPARE_TEXT_LIMIT = 300000;
/** Compares (results and inboxes) older than this are removed when a new compare saves its result. */
const COMPARE_KEEP_DAYS = 3;

/** The compare's result: results/<id>/compare.json (and the files' JSON), then the run fails with the message. */
function compareFailed(message) {
    if (options.full === true) {
        writeCompareResults({ status: 'Failed', message: String(message).slice(0, 1500), org: orgLabel(), branch: target,
            components: [], counts: {} }, [], 'drift.json', 'drift');
    } else {
        writeCompareResults({ status: 'Failed', message: String(message).slice(0, 1500), targetBranch: target,
            source: orgLabel(), components: [], counts: {} }, []);
    }
    fail(message);
}

/** Where this run's results go: results/<id>/ (a full compare can name its Sync status id in options.syncId). */
function resultsId() {
    return mode === 'compare' && options.full === true && SYNC_ID_RE.test(String(options.syncId || '')) ? String(options.syncId) : requestId;
}

/** A file's bytes at HEAD, or null when HEAD hasn't got it. */
function headBytes(file) {
    try {
        return execFileSync('git', ['show', `HEAD:${file.split(path.sep).join('/')}`],
            { stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 256 * 1024 * 1024 });
    } catch (e) {
        return null;
    }
}

/** Text from bytes, or null for a binary file (a NUL byte, or not UTF-8). */
function compareText(buf) {
    if (buf === null) {
        return null;
    }
    if (buf.subarray(0, 8000).includes(0)) {
        return undefined;
    }
    const text = buf.toString('utf8');
    return Buffer.from(text, 'utf8').equals(buf) ? text : undefined;
}

/** The unified diff of one file between HEAD and the working tree (a new file against /dev/null). */
function comparePatch(file, isNew) {
    const args = isNew ? ['diff', '--no-color', '--no-index', '-U3', '--', '/dev/null', file]
        : ['diff', '--no-color', '-U3', 'HEAD', '--', file];
    try {
        return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 256 * 1024 * 1024 });
    } catch (e) {
        return String(e.stdout || ''); // git diff --no-index exits 1 when the files differ
    }
}

/** The part numbers the hub left in compare-inbox/<id>/ (<n>.zip), in numeric order; numbers can have gaps. */
function compareParts() {
    const out = gitQuiet(['ls-tree', '--name-only', `refs/remotes/origin/${RESULTS_BRANCH}:${COMPARE_INBOX}/${requestId}`]);
    return (out || '').split('\n').map((f) => /^(\d{1,6})\.zip$/.exec(f.trim())).filter(Boolean)
        .map((m) => Number(m[1])).sort((a, b) => a - b);
}

/** Unzips one of the hub's parts, converts it to source format and copies it into SOURCE_PATH; the copied repo paths. */
function unpackComparePart(n, tmp) {
    const spec = `refs/remotes/origin/${RESULTS_BRANCH}:${COMPARE_INBOX}/${requestId}/${n}.zip`;
    let bytes;
    try {
        bytes = execFileSync('git', ['show', spec], { stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 512 * 1024 * 1024 });
    } catch (e) {
        compareFailed(`Part ${n} of the compare (${COMPARE_INBOX}/${requestId}/${n}.zip) couldn't be read from ${RESULTS_BRANCH}. Compare again from Release Relay.`);
    }
    const zip = path.join(tmp, `${n}.zip`);
    const mdapi = path.join(tmp, `mdapi-${n}`);
    const out = path.join(tmp, `source-${n}`);
    fs.writeFileSync(zip, bytes);
    try {
        execFileSync('unzip', ['-q', '-o', zip, '-d', mdapi], { stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e) {
        compareFailed(`Part ${n} of the compare couldn't be unzipped: ${String(e.stderr || e.message).trim().slice(0, 500)}`);
    }
    convertFromHub(mdapi, out, compareFailed);
    const converted = [path.join(out, 'force-app', 'main', 'default'), path.join(out, 'force-app')].find((p) => fs.existsSync(p));
    // A whole object is compared as the org has it (its own file too, not only its fields).
    return converted ? copyConverted(converted, sourcePath(), ALL_OBJECTS).map((r) => path.join(sourcePath(), r)) : [];
}

/** Whether a repo file belongs to a component (a bundle or object: anything in its folder). */
function belongsTo(file, c) {
    if (FOLDER_TYPES[c.type]) {
        const dir = path.join(sourcePath(), FOLDER_TYPES[c.type], c.name) + path.sep;
        return file.startsWith(dir);
    }
    const owner = componentFor(file);
    return !!owner && owner.type === c.type && owner.name.toLowerCase() === c.name.toLowerCase();
}

/** The files at HEAD of a component the release deletes, or null when its type can't be found by path. */
function deletedFiles(c) {
    const paths = pathsFor(sourcePath(), c.type, c.name);
    if (paths === null) {
        return null;
    }
    const out = paths.length ? git(['ls-tree', '-r', '--name-only', 'HEAD', '--', ...paths]) : '';
    return out.split('\n').filter(Boolean);
}

/** One file: its status, and its content for the hub (two sides, or a diff) when it can be shown. */
function compareFile(file, deleted, files) {
    const leftBuf = headBytes(file);
    const rightBuf = deleted ? null : fs.readFileSync(file);
    const left = compareText(leftBuf);
    const right = compareText(rightBuf);
    const rel = file.split(path.sep).join('/');
    let status;
    if (deleted) {
        status = 'deleted';
    } else if (leftBuf === null) {
        status = 'new';
    } else if (left !== undefined && right !== undefined) {
        status = left.replace(/\r\n/g, '\n') === right.replace(/\r\n/g, '\n') ? 'same' : 'changed';
    } else {
        status = leftBuf.equals(rightBuf) ? 'same' : 'changed';
    }
    const chars = Math.max(left ? left.length : 0, right ? right.length : 0);
    const entry = { path: rel, status, chars };
    if (left === undefined || right === undefined) {
        entry.reason = 'Binary file: open it in GitHub.';
        return entry;
    }
    if (chars <= COMPARE_TEXT_LIMIT) {
        files.push({ path: rel, left, right });
        return { ...entry, n: files.length, kind: 'text' };
    }
    const patch = status === 'same' ? '' : (deleted ? '' : comparePatch(file, status === 'new'));
    if (patch && patch.length <= COMPARE_TEXT_LIMIT) {
        files.push({ path: rel, patch });
        return { ...entry, n: files.length, kind: 'patch' };
    }
    entry.reason = `Too large to show here (over ${COMPARE_TEXT_LIMIT.toLocaleString('en-US')} characters): open it in GitHub.`;
    return entry;
}

/** A component's status from its files: new when all are new, same when all are the same, otherwise changed. */
function componentStatus(files) {
    if (files.every((f) => f.status === 'new')) {
        return 'new';
    }
    return files.every((f) => f.status === 'same') ? 'same' : 'changed';
}

/** Main files first (a class before its -meta.xml), then by path. */
function compareOrder(a, b) {
    const ma = a.endsWith('-meta.xml') ? 1 : 0;
    const mb = b.endsWith('-meta.xml') ? 1 : 0;
    return ma - mb || a.localeCompare(b);
}

/**
 * STEP=compare: the developer org's copy (the hub's zips) against TARGET, for the hub's Compare before raising.
 * Nothing is committed to TARGET; only results go to the results branch.
 */
async function stepCompare() {
    orgEnv = sourceEnv;
    if (mode !== 'compare') { fail('STEP=compare needs MODE=compare.'); }
    const components = parseList(input('COMPONENTS'), 'COMPONENTS');
    const deletions = parseList(input('DELETIONS'), 'DELETIONS');
    const full = options.full === true;
    if (!full && !components.length && !deletions.length) { compareFailed('Nothing to compare.'); }
    if (!remoteBranchExists(target)) { compareFailed(`Branch ${target} doesn't exist.`); }
    fetchBranch(target);
    // Every <n>.zip in the inbox is read (options.batches is only a hint: a part the hub split gets new numbers).
    let parts = [];
    if (remoteBranchExists(RESULTS_BRANCH)) {
        fetchBranch(RESULTS_BRANCH);
        parts = compareParts();
    }
    if ((components.length || full) && !parts.length) {
        compareFailed(`The parts of this compare weren't found on ${RESULTS_BRANCH} (${COMPARE_INBOX}/${requestId}/). Compare again from Release Relay.`);
    }
    git(['checkout', '-q', '--force', '--detach', `refs/remotes/origin/${target}`]);

    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-compare-'));
    let copied = [];
    try {
        for (const n of parts) {
            copied = copied.concat(unpackComparePart(n, tmp));
        }
    } finally {
        fs.rmSync(tmp, { recursive: true, force: true });
    }
    copied = [...new Set(copied)].sort(compareOrder);
    // The developer org's own values become {{relay:NAME}} placeholders, as a raise writes them.
    const tokens = tokenizeFiles(copied, sourceEnv);
    if (tokens.error) {
        compareFailed(tokens.error);
    }
    if (full) {
        // Sync status (version 23): the developer org's whole copy against its branch.
        const folders = folderOption();
        const drift = driftOf(copied, pathRules(folders), typesFrom(folders), {});
        git(['checkout', '-q', '--force', '--detach', `refs/remotes/origin/${target}`]);
        gitQuiet(['clean', '-fdq', '--', sourcePath()]);
        saveDrift(drift);
        return;
    }

    const files = [];
    const out = [];
    for (const c of components) {
        const mine = copied.filter((f) => belongsTo(f, c));
        if (!mine.length) {
            out.push({ key: c.entry, status: 'missing', reason: `Not in ${orgLabel()}'s copy (it may have been deleted or renamed).`, files: [] });
            continue;
        }
        const entries = mine.map((f) => compareFile(f, false, files));
        out.push({ key: c.entry, status: componentStatus(entries), files: entries });
    }
    for (const d of deletions) {
        const at = deletedFiles(d);
        if (at === null) {
            out.push({ key: d.entry, status: 'missing', reason: `Deleting ${d.type} isn't compared.`, files: [] });
        } else if (!at.length) {
            out.push({ key: d.entry, status: 'missing', reason: `Not on ${target}, so there's nothing to delete.`, files: [] });
        } else {
            out.push({ key: d.entry, status: 'deleted', files: at.sort(compareOrder).map((f) => compareFile(f, true, files)) });
        }
    }
    const counts = { changed: 0, new: 0, same: 0, deleted: 0, missing: 0 };
    out.forEach((c) => { counts[c.status] = (counts[c.status] || 0) + 1; });
    git(['checkout', '-q', '--force', '--detach', `refs/remotes/origin/${target}`]);
    gitQuiet(['clean', '-fdq', '--', sourcePath()]);
    writeCompareResults({ status: 'Succeeded', message: '', targetBranch: target, source: orgLabel(), components: out, counts }, files);
    summary(`**Compare:** ${orgLabel()} with ${target}: ${counts.changed} changed, ${counts.new} new, ${counts.same} same, `
        + `${counts.deleted} deleted, ${counts.missing} not found; ${files.length} file(s) for the hub.`);
}

/** The compare folders (results/CMP-… and compare-inbox/CMP-…) older than COMPARE_KEEP_DAYS in a results checkout. */
function staleCompares(dir) {
    const cutoff = Date.now() - COMPARE_KEEP_DAYS * 24 * 3600 * 1000;
    const stale = [];
    for (const parent of ['results', COMPARE_INBOX]) {
        const full = path.join(dir, parent);
        if (!fs.existsSync(full)) {
            continue;
        }
        for (const name of fs.readdirSync(full)) {
            const m = COMPARE_ID_RE.exec(name) || SYNC_ID_RE.exec(name);
            if (m && name !== requestId && name !== resultsId() && Number(m[1]) < cutoff) {
                stale.push(`${parent}/${name}`);
            }
        }
    }
    return stale;
}

/**
 * Saves a compare's result in one commit on the results branch: results/<id>/compare.json and results/<id>/f/<n>.json,
 * removes compare-inbox/<id> and prunes old compares. Pushes retry on races, as writeResult does.
 */
function writeCompareResults(data, files, fileName = 'compare.json', stepName = 'compare') {
    const result = { request: resultsId(), step: stepName, ...data, runUrl: runUrl(), finishedAt: new Date().toISOString() };
    if (runToken) {
        result.attempt = runToken;
    }
    const json = JSON.stringify(result, null, 1);
    summarizeResult({ ...result, components: undefined, changed: undefined, deleted: undefined });
    if (env.RELAY_LOCAL_RESULTS === 'true') {
        return;
    }
    const base = path.join('results', resultsId());
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
            fs.rmSync(path.join(dir, base), { recursive: true, force: true });
            fs.mkdirSync(path.join(dir, base, 'f'), { recursive: true });
            fs.writeFileSync(path.join(dir, base, fileName), json + '\n');
            files.forEach((f, i) => fs.writeFileSync(path.join(dir, base, 'f', `${i + 1}.json`), JSON.stringify(f) + '\n'));
            git(['add', '-A', '--', base], { cwd: dir });
            const remove = [`${COMPARE_INBOX}/${requestId}`, ...staleCompares(dir)];
            gitQuietIn(dir, ['rm', '-r', '-q', '--ignore-unmatch', '--', ...remove]);
            git(['-c', 'user.name=Release Relay', '-c', 'user.email=release-relay@users.noreply.local',
                'commit', '-q', '-m', `${resultsId()} ${stepName}: ${result.status}`], { cwd: dir });
            git(['push', '-q', 'origin', `HEAD:refs/heads/${RESULTS_BRANCH}`], { cwd: dir });
            return;
        } catch (e) {
            console.log(`Saving the ${stepName} result failed (attempt ${attempt}); retrying.`);
        } finally {
            gitQuiet(['worktree', 'remove', '--force', dir]);
            fs.rmSync(dir, { recursive: true, force: true });
        }
    }
    fail(`Couldn't save the ${stepName} result to the ${RESULTS_BRANCH} branch. The pipeline needs permission to push to it, and it must not be protected.`);
}

// ---------- version 23: Sync status (drift, full compare, routediff) ----------

/** Child folders of an object folder in source format: folder -> [type, suffix]. */
const OBJECT_CHILDREN = {
    fields: ['CustomField', '.field-meta.xml'], validationRules: ['ValidationRule', '.validationRule-meta.xml'],
    recordTypes: ['RecordType', '.recordType-meta.xml'], listViews: ['ListView', '.listView-meta.xml'],
    compactLayouts: ['CompactLayout', '.compactLayout-meta.xml'], webLinks: ['WebLink', '.webLink-meta.xml'],
    fieldSets: ['FieldSet', '.fieldSet-meta.xml'], businessProcesses: ['BusinessProcess', '.businessProcess-meta.xml'],
    sharingReasons: ['SharingReason', '.sharingReason-meta.xml'], indexes: ['Index', '.index-meta.xml']
};
/** Folders whose components are a folder each (a bundle): folder -> type. */
const BUNDLE_FOLDERS = { lwc: 'LightningComponentBundle', aura: 'AuraDefinitionBundle', experiences: 'ExperienceBundle',
    waveTemplates: 'WaveTemplateBundle', staticresources: 'StaticResource' };
/** Types listed in folders (reports/<Folder>/<Name>.report-meta.xml): folder -> [type, suffix, folder type]. */
const IN_FOLDER = { reports: ['Report', '.report-meta.xml', 'ReportFolder'], dashboards: ['Dashboard', '.dashboard-meta.xml', 'DashboardFolder'],
    email: ['EmailTemplate', '.email', 'EmailFolder'], documents: ['Document', '', 'DocumentFolder'] };
/** Types the hub doesn't list (RlyMetadata.SKIP): never compared. */
const DRIFT_SKIP = new Set(['ApexTestSuite', 'Certificate', 'ConnectedApp', 'ExternalClientApplication', 'ExtlClntAppOauthSettings',
    'ExtlClntAppGlobalOauthSettings', 'ExtlClntAppOauthConfigurablePolicies', 'Index', 'InstalledPackage', 'ManagedTopics',
    'Package', 'Portal', 'SiteDotCom', 'Territory', 'Scontrol']);
/** For copyConverted: every object is taken whole (its own -object-meta.xml too). */
const ALL_OBJECTS = { has: () => true };
/** Custom suffixes that aren't a namespace. */
const CUSTOM_SUFFIX_RE = /__(c|mdt|e|b|x|r|kav|pc|history|share|feed|s)$/i;

/** Whether a component name belongs to a managed package (a token that still has __ after its custom suffix). */
function isManagedName(name) {
    return String(name).split(/[./-]/).some((t) => t.replace(CUSTOM_SUFFIX_RE, '').includes('__'));
}

/** The most components a drift lists (then truncated). */
const DRIFT_MAX = 5000;
/** Members per retrieve when an org is read whole. */
const DRIFT_CHUNK = 2500;

/** options.folders from the hub ({"classes":"ApexClass", ...}): only plain folder and type names are kept. */
function folderOption() {
    const out = {};
    const f = options.folders && typeof options.folders === 'object' && !Array.isArray(options.folders) ? options.folders : {};
    Object.keys(f).slice(0, 800).forEach((k) => {
        const t = String(f[k]);
        if (/^[A-Za-z0-9]{1,80}$/.test(k) && /^[A-Za-z0-9]{2,80}$/.test(t)) {
            out[k] = { type: t, suffix: null };
        }
    });
    return out;
}

/**
 * Folder -> {type, suffix} rules: the built-in layout (FILE_TYPES, bundles, objects, folders, territory models,
 * settings) plus those given (a describe, or the hub's options.folders) for folders the built-in layout doesn't know.
 */
function pathRules(extra) {
    const rules = {};
    Object.keys(extra || {}).forEach((k) => { rules[k] = extra[k]; });
    Object.keys(FILE_TYPES).forEach((t) => { rules[FILE_TYPES[t][0]] = { type: t, suffix: FILE_TYPES[t][1] }; });
    return rules;
}

/**
 * The types an org was read for, from the folders its describe (or the hub's options.folders) names: only these can be
 * "only on the branch". Nested layouts come with their folder (objects: the object's children too).
 */
function typesFrom(folders) {
    const types = new Set();
    Object.keys(folders).forEach((k) => {
        types.add(folders[k].type);
        if (k === 'objects') {
            Object.keys(OBJECT_CHILDREN).forEach((c) => types.add(OBJECT_CHILDREN[c][0]));
        }
        if (k === 'territory2Models') {
            ['Territory2Model', 'Territory2', 'Territory2Rule'].forEach((t) => types.add(t));
        }
        if (BUNDLE_FOLDERS[k]) {
            types.add(BUNDLE_FOLDERS[k]);
        }
        if (IN_FOLDER[k]) {
            types.add(IN_FOLDER[k][0]);
            types.add(IN_FOLDER[k][2]);
        }
        if (k === 'settings') {
            types.add('Settings');
        }
    });
    return types;
}

/** A file name without its suffix: the given one, else -meta.xml and the last extension. */
function stemOf(base, suffix) {
    if (suffix && base.endsWith(suffix)) {
        return base.slice(0, -suffix.length);
    }
    if (suffix && base.endsWith(suffix + '-meta.xml')) {
        return base.slice(0, -(suffix.length + '-meta.xml'.length));
    }
    const noMeta = base.endsWith('-meta.xml') ? base.slice(0, -'-meta.xml'.length) : base;
    const dot = noMeta.indexOf('.');
    return dot > 0 ? noMeta.slice(0, dot) : noMeta;
}

/** The component (type, name, key) a repo file under SOURCE_PATH belongs to, or null. */
function componentOf(file, rules) {
    const rel = path.relative(sourcePath(), file).split(path.sep);
    if (rel[0] === '..' || rel.length < 2) {
        return null;
    }
    const folder = rel[0];
    const base = rel[rel.length - 1];
    const make = (type, name) => (type && name ? { type, name, key: `${type}:${name}` } : null);
    if (folder === 'objects') {
        if (rel.length === 3 && base === `${rel[1]}.object-meta.xml`) { return make('CustomObject', rel[1]); }
        if (rel.length === 4 && OBJECT_CHILDREN[rel[2]]) {
            const [type, suffix] = OBJECT_CHILDREN[rel[2]];
            return base.endsWith(suffix) ? make(type, `${rel[1]}.${base.slice(0, -suffix.length)}`) : null;
        }
        return rel.length >= 3 ? make('CustomObject', rel[1]) : null;
    }
    if (folder === 'territory2Models' && rel.length >= 3) {
        if (rel.length === 3) { return make('Territory2Model', rel[1]); }
        if (rel[2] === 'territories') { return make('Territory2', `${rel[1]}.${stemOf(base, '.territory2-meta.xml')}`); }
        if (rel[2] === 'rules') { return make('Territory2Rule', `${rel[1]}.${stemOf(base, '.territory2Rule-meta.xml')}`); }
        return make('Territory2Model', rel[1]);
    }
    if (BUNDLE_FOLDERS[folder]) {
        return make(BUNDLE_FOLDERS[folder], rel.length >= 3 ? rel[1] : stemOf(rel[1], null));
    }
    if (IN_FOLDER[folder]) {
        const [type, suffix, folderType] = IN_FOLDER[folder];
        const folderMeta = new RegExp(`\\.${folderType.charAt(0).toLowerCase() + folderType.slice(1)}-meta\\.xml$`);
        if (folderMeta.test(base)) {
            return make(folderType, rel.slice(1, -1).concat([base.replace(folderMeta, '')]).join('/'));
        }
        return make(type, rel.slice(1, -1).concat([stemOf(base, suffix || null)]).join('/'));
    }
    if (folder === 'settings' && rel.length === 2) {
        const name = stemOf(base, '.settings-meta.xml');
        return make(`${name}Settings`, name);
    }
    const rule = rules[folder];
    if (!rule || rel.length !== 2) {
        return null;
    }
    return make(rule.type, stemOf(base, rule.suffix));
}

/** Files at HEAD under SOURCE_PATH. */
function branchFiles() {
    const out = git(['ls-tree', '-r', '--name-only', 'HEAD', '--', sourcePath()]);
    return out.split('\n').filter(Boolean).map((f) => f.split('/').join(path.sep));
}

/**
 * The drift of an org's copy (orgFiles, already written over a checkout of TARGET) against TARGET's files:
 * components only in the org, only on the branch (of the types the org was read for) and different. Same ones left out.
 */
function driftOf(orgFiles, rules, types, lastChanged) {
    const byKey = new Map();
    const add = (file, side) => {
        const c = componentOf(file, rules);
        if (!c || DRIFT_SKIP.has(c.type) || componentExcluded(c.type, c.name) || isManagedName(c.name)) {
            return; // skipped types, Release Relay's own components and managed packages are never compared
        }
        if (!byKey.has(c.key)) {
            byKey.set(c.key, { c, org: new Set(), branch: new Set() });
        }
        byKey.get(c.key)[side].add(file);
    };
    orgFiles.forEach((f) => add(f, 'org'));
    branchFiles().forEach((f) => add(f, 'branch'));
    const files = [];
    const components = [];
    const counts = { onlyInOrg: 0, onlyOnBranch: 0, different: 0, same: 0 };
    let truncated = false;
    for (const key of [...byKey.keys()].sort()) {
        const { c, org, branch: onBranch } = byKey.get(key);
        if (!org.size && !types.has(c.type) && !(c.type.endsWith('Settings') && types.has('Settings'))) {
            continue; // the org wasn't read for this type: no claim either way
        }
        let status;
        if (!onBranch.size) {
            status = 'onlyInOrg';
        } else if (!org.size) {
            status = 'onlyOnBranch';
        } else {
            status = null;
        }
        const all = [...new Set([...org, ...onBranch])].sort(compareOrder);
        if (status === null) {
            const quick = all.map((f) => fileStatus(f, !org.has(f)));
            if (quick.every((x) => x === 'same')) {
                counts.same++;
                continue;
            }
            status = 'different';
        }
        counts[status]++;
        if (components.length >= DRIFT_MAX) {
            truncated = true;
            continue;
        }
        const shown = status === 'different' ? all.filter((f) => fileStatus(f, !org.has(f)) !== 'same') : all;
        const entries = shown.map((f) => compareFile(f, !org.has(f), files));
        const entry = { key, type: c.type, status, files: entries };
        const lc = lastChanged[key];
        if (lc) {
            entry.lastChangedBy = lc.by || null;
            entry.lastChangedAt = lc.at || null;
        }
        components.push(entry);
    }
    return { components, counts, files, truncated };
}

/** A file's status without reading it for the hub: same / changed / new / deleted. */
function fileStatus(file, deleted) {
    const leftBuf = headBytes(file);
    if (deleted) {
        return leftBuf === null ? 'same' : 'deleted';
    }
    if (leftBuf === null) {
        return 'new';
    }
    const rightBuf = fs.readFileSync(file);
    const left = compareText(leftBuf);
    const right = compareText(rightBuf);
    if (left !== undefined && right !== undefined && left !== null && right !== null) {
        return left.replace(/\r\n/g, '\n') === right.replace(/\r\n/g, '\n') ? 'same' : 'changed';
    }
    return leftBuf.equals(rightBuf) ? 'same' : 'changed';
}

/** Saves a drift as results/<id>/drift.json (+ f/<n>.json). */
function saveDrift(drift) {
    writeCompareResults({ status: 'Succeeded', message: '', org: orgLabel(), branch: target, checkedAt: new Date().toISOString(),
        counts: drift.counts, truncated: drift.truncated, components: drift.components }, drift.files, 'drift.json', 'drift');
    summary(`**Org vs branch:** ${orgLabel()} against ${target}: ${drift.counts.onlyInOrg} only in the org, `
        + `${drift.counts.onlyOnBranch} only on the branch, ${drift.counts.different} different, ${drift.counts.same} the same`
        + `${drift.truncated ? ` (the first ${DRIFT_MAX} listed)` : ''}; ${drift.files.length} file(s) for the hub.`);
}

/** A drift run's failure: drift.json with the message, then the run fails. */
function driftFailed(message) {
    writeCompareResults({ status: 'Failed', message: String(message).slice(0, 1500), org: orgLabel(), branch: target,
        components: [], counts: {} }, [], 'drift.json', 'drift');
    fail(message);
}

/** The org's metadata types as the CLI describes them: folder -> {type, suffix}. */
function describedRules(alias) {
    let out;
    try {
        out = JSON.parse(execFileSync('sf', ['org', 'list', 'metadata-types', '--target-org', alias, '--json'],
            { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 }));
    } catch (e) {
        return {};
    }
    const rules = {};
    const objects = (out.result && out.result.metadataObjects) || [];
    objects.forEach((o) => {
        if (o && o.directoryName && o.xmlName && !rules[o.directoryName]) {
            rules[o.directoryName] = { type: o.xmlName, suffix: o.suffix ? `.${o.suffix}` : null };
        }
    });
    return rules;
}

/** CLI output as one plain line: colour codes and the "update available" warning removed, the JSON's message kept. */
function plainCliText(raw) {
    let text = String(raw || '').replace(/\u001b\[[0-9;]*m/g, '');
    try {
        const j = JSON.parse(text);
        text = (j.name ? j.name + ': ' : '') + (j.message || text);
    } catch (e) {
        text = text.replace(/›?\s*Warning: @salesforce\/cli update available[^\n]*\n?/g, '');
    }
    return text.replace(/\s+/g, ' ').trim();
}

/** sf project generate manifest --from-org: the org's components (managed packages left out), skipped types removed. */
function orgManifest(alias, dir) {
    // The command only runs inside a Salesforce project: the temporary folder gets a minimal sfdx-project.json.
    fs.mkdirSync(path.join(dir, 'force-app'), { recursive: true });
    fs.writeFileSync(path.join(dir, 'sfdx-project.json'), JSON.stringify({
        packageDirectories: [{ path: 'force-app', default: true }], sourceApiVersion: apiVersion() }, null, 2));
    try {
        execFileSync('sf', ['project', 'generate', 'manifest', '--from-org', alias, '--output-dir', dir, '--name', 'package.xml', '--json'],
            { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], cwd: dir, maxBuffer: 64 * 1024 * 1024,
                env: { ...process.env, SF_SKIP_NEW_VERSION_CHECK: 'true', NO_COLOR: '1', FORCE_COLOR: '0' } });
    } catch (e) {
        driftFailed(`Listing ${orgLabel()}'s components failed: ${plainCliText(e.stdout || e.stderr || e.message).slice(0, 500)}`);
    }
    const file = path.join(dir, 'package.xml');
    if (!fs.existsSync(file)) {
        driftFailed(`Listing ${orgLabel()}'s components gave no manifest.`);
    }
    return parsePackageXml(fs.readFileSync(file, 'utf8'))
        .filter((c) => !c.name.includes('*') && !DRIFT_SKIP.has(c.type) && !componentExcluded(c.type, c.name));
}

/** Retrieves components into Metadata API folders, DRIFT_CHUNK at a time; the extracted folders and last-changed data. */
function retrieveAll(alias, items, tmp) {
    const folders = [];
    const lastChanged = {};
    for (let i = 0; i < items.length; i += DRIFT_CHUNK) {
        const n = folders.length + 1;
        const pkg = path.join(tmp, `package-${n}.xml`);
        fs.writeFileSync(pkg, manifest(apiVersion(), items.slice(i, i + DRIFT_CHUNK)));
        const dir = path.join(tmp, `retrieve-${n}`);
        fs.mkdirSync(dir);
        let raw;
        try {
            raw = execFileSync('sf', ['project', 'retrieve', 'start', '--manifest', pkg, '--target-metadata-dir', dir,
                '--target-org', alias, '--wait', '60', '--json'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 256 * 1024 * 1024 });
        } catch (e) {
            raw = e.stdout ? String(e.stdout) : '';
            if (!raw) {
                driftFailed(`Retrieving part ${n} from ${orgLabel()} failed: ${String(e.stderr || e.message).replace(/\s+/g, ' ').slice(0, 400)}`);
            }
        }
        let out = {};
        try { out = JSON.parse(raw); } catch (e) { driftFailed('The Salesforce CLI returned output that isn\'t JSON.'); }
        const r = out.result || {};
        asList(r.fileProperties).forEach((p) => {
            if (p && p.type && p.fullName) {
                lastChanged[`${p.type}:${p.fullName}`] = { by: p.lastModifiedByName || null, at: p.lastModifiedDate || null };
            }
        });
        const zip = walkFiles(dir).find((f) => f.endsWith('.zip'));
        const extracted = path.join(tmp, `mdapi-${n}`);
        fs.mkdirSync(extracted);
        if (zip) {
            execFileSync('unzip', ['-q', '-o', path.join(dir, zip), '-d', extracted], { stdio: ['ignore', 'pipe', 'pipe'] });
        }
        // The zip holds an unpackaged/ folder (or the files at its root).
        const root = fs.existsSync(path.join(extracted, 'unpackaged')) ? path.join(extracted, 'unpackaged') : extracted;
        folders.push(root);
    }
    return { folders, lastChanged };
}

/**
 * STEP=drift (MODE=drift, version 23): ENVIRONMENT's org read whole against TARGET (its branch). Nothing is committed to
 * TARGET; only results go to the results branch.
 */
async function stepDrift() {
    orgEnv = sourceEnv;
    if (mode !== 'drift') { fail('STEP=drift needs MODE=drift.'); }
    if (!remoteBranchExists(target)) { driftFailed(`Branch ${target} doesn't exist.`); }
    fetchBranch(target);
    if (remoteBranchExists(RESULTS_BRANCH)) {
        fetchBranch(RESULTS_BRANCH);
    }
    git(['checkout', '-q', '--force', '--detach', `refs/remotes/origin/${target}`]);
    try {
        login('drift-org');
    } catch (e) {
        driftFailed(e.message);
    }
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-drift-'));
    let copied = [];
    let rules;
    let described = {};
    let lastChanged = {};
    try {
        described = describedRules('drift-org');
        rules = pathRules(described);
        const items = orgManifest('drift-org', tmp);
        if (!items.length) {
            driftFailed(`${orgLabel()} has no components to compare.`);
        }
        const got = retrieveAll('drift-org', items, tmp);
        lastChanged = got.lastChanged;
        got.folders.forEach((mdapi, i) => {
            const out = path.join(tmp, `source-${i + 1}`);
            convertFromHub(mdapi, out, driftFailed);
            const converted = [path.join(out, 'force-app', 'main', 'default'), path.join(out, 'force-app')].find((p) => fs.existsSync(p));
            if (converted) {
                copied = copied.concat(copyConverted(converted, sourcePath(), ALL_OBJECTS).map((r) => path.join(sourcePath(), r)));
            }
        });
    } finally {
        fs.rmSync(tmp, { recursive: true, force: true });
    }
    copied = [...new Set(copied)].sort(compareOrder);
    const tokens = tokenizeFiles(copied, sourceEnv);
    if (tokens.error) {
        driftFailed(tokens.error);
    }
    const drift = driftOf(copied, rules, typesFrom(described), lastChanged);
    git(['checkout', '-q', '--force', '--detach', `refs/remotes/origin/${target}`]);
    gitQuiet(['clean', '-fdq', '--', sourcePath()]);
    saveDrift(drift);
}

/** A file's text at a commit, or null when it isn't there (undefined for a binary file). */
function textAtRef(ref, file) {
    let buf;
    try {
        buf = execFileSync('git', ['show', `${ref}:${file}`], { stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 256 * 1024 * 1024 });
    } catch (e) {
        return null;
    }
    return compareText(buf);
}

/** One file of a route pair: left = higher, right = lower; its text for the hub when it can be shown. */
function routeFile(file, higher, lower, lowerChanged, files) {
    const left = textAtRef(higher, file);
    const right = textAtRef(lower, file);
    let status;
    if (left === null) {
        status = 'deleted';
    } else if (right === null) {
        status = 'new';
    } else {
        status = 'changed';
    }
    const entry = { path: file, status, lowerChangedToo: lowerChanged };
    if (left === undefined || right === undefined) {
        entry.reason = 'Binary file: open it in GitHub.';
        return entry;
    }
    const chars = Math.max(left ? left.length : 0, right ? right.length : 0);
    if (chars <= COMPARE_TEXT_LIMIT) {
        files.push({ path: file, left, right });
        return { ...entry, n: files.length, kind: 'text' };
    }
    let patch = '';
    try {
        patch = execFileSync('git', ['diff', '--no-color', '-U3', lower, higher, '--', file], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 256 * 1024 * 1024 });
    } catch (e) {
        patch = String(e.stdout || '');
    }
    if (patch && patch.length <= COMPARE_TEXT_LIMIT) {
        files.push({ path: file, patch });
        return { ...entry, n: files.length, kind: 'patch' };
    }
    entry.reason = `Too large to show here (over ${COMPARE_TEXT_LIMIT.toLocaleString('en-US')} characters): open it in GitHub.`;
    return entry;
}

/** Where a file's latest change on a branch came from: the release named in the commit, or the commit itself. */
function cameFrom(ref, file) {
    const line = gitQuiet(['log', '-1', '--format=%s%x09%h%x09%cs', ref, '--', file]) || '';
    const [subject, sha, day] = line.split('\t');
    const m = /\b(REL-\d{5,})\b/.exec(subject || '');
    return m ? m[1] : (sha ? `commit ${sha} ${day || ''}`.trim() : null);
}

/** One pair down the route: what the higher branch changed since the merge base that the lower one doesn't have. */
function routePair(higher, lower, rules, files) {
    const hi = `refs/remotes/origin/${higher}`;
    const lo = `refs/remotes/origin/${lower}`;
    const base = gitQuiet(['merge-base', hi, lo]);
    const changedHigh = (base ? git(['diff', '--name-only', '--no-renames', base, hi, '--', sourcePath()])
        : git(['ls-tree', '-r', '--name-only', hi, '--', sourcePath()])).split('\n').filter(Boolean);
    const changedLow = new Set(base ? git(['diff', '--name-only', '--no-renames', base, lo, '--', sourcePath()]).split('\n').filter(Boolean) : []);
    const byKey = new Map();
    for (const f of changedHigh) {
        const a = textAtRef(hi, f);
        const b = textAtRef(lo, f);
        if (a === b || (typeof a === 'string' && typeof b === 'string' && a.replace(/\r\n/g, '\n') === b.replace(/\r\n/g, '\n'))) {
            continue; // the same now in both (the change came down another way)
        }
        const c = componentOf(f.split('/').join(path.sep), rules) || { type: 'File', name: f, key: `File:${f}` };
        if (!byKey.has(c.key)) {
            byKey.set(c.key, { c, files: [] });
        }
        byKey.get(c.key).files.push(f);
    }
    const components = [...byKey.keys()].sort().map((key) => {
        const { c, files: paths } = byKey.get(key);
        const lowerChangedToo = paths.some((f) => changedLow.has(f));
        const entries = paths.sort(compareOrder).map((f) => routeFile(f, hi, lo, changedLow.has(f), files));
        const status = entries.every((e) => e.status === 'new') ? 'onlyInHigher' : 'different';
        return { key, type: c.type, status, lowerChangedToo, files: entries, cameFrom: cameFrom(hi, paths[0]) };
    });
    return { higher, lower, count: components.length, components };
}

/** STEP=routediff (MODE=routediff, version 23): each pair down options.route, Git only; results/<id>/route.json. */
async function stepRouteDiff() {
    if (mode !== 'routediff') { fail('STEP=routediff needs MODE=routediff.'); }
    const route = Array.isArray(options.route) ? options.route.map(String) : [];
    const routeFailed = (message) => {
        writeCompareResults({ status: 'Failed', message: String(message).slice(0, 1500), pairs: [] }, [], 'route.json', 'routediff');
        fail(message);
    };
    // options.pairs [[higher, lower], ...] (several developer orgs make the route a tree) wins over options.route.
    let wanted;
    if (Array.isArray(options.pairs) && options.pairs.length) {
        if (options.pairs.length > 30 || !options.pairs.every((p) => Array.isArray(p) && p.length === 2)) {
            routeFailed('options.pairs must list 1 to 30 [higher, lower] pairs of branches.');
        }
        wanted = options.pairs.map((p) => [String(p[0]), String(p[1])]);
    } else {
        if (route.length < 2 || route.length > 12) {
            routeFailed('options.route must list 2 to 12 branches, highest first.');
        }
        wanted = route.slice(0, -1).map((b, i) => [b, route[i + 1]]);
    }
    for (const b of [...new Set([].concat(...wanted))]) {
        if (!REF_RE.test(b) || b.includes('..') || b === RESULTS_BRANCH || b === SNAPSHOT_BRANCH) { routeFailed(`"${b}" isn't a valid branch.`); }
        if (!remoteBranchExists(b)) { routeFailed(`Branch ${b} doesn't exist.`); }
        fetchBranch(b);
    }
    if (wanted.some(([h, l]) => h === l)) {
        routeFailed('A pair compares a branch with itself.');
    }
    const rules = pathRules(folderOption());
    const files = [];
    const pairs = wanted.map(([h, l]) => routePair(h, l, rules, files));
    writeCompareResults({ status: 'Succeeded', message: '', checkedAt: new Date().toISOString(), pairs }, files, 'route.json', 'routediff');
    summary('**Down the route:** ' + pairs.map((p) => `${p.higher} → ${p.lower}: ${p.count}`).join(' · ') + `; ${files.length} file(s) for the hub.`);
}

// ---------- version 24: data sets (MODE=data, request ids DAT-<13 digits>) ----------
//
// The hub's Sync status tab, Data. A data set is options.dataSet: { title, objects: [{ objectName, fields, filter,
// matchKey, parents: { field: parentObject }, masks: { field: rule } }], bypass: { kind, name, field } } (checked again
// here). STEP=data-export (the source's environment) queries each object and saves the records to the results branch as
// data-inbox/<id>/<ii>-<ppp>.json; a developer org's records are sent there by the hub instead (no export job).
// STEP=data-load (the target's environment) reads them, masks (options.mask) and swaps per-org values (the source's
// value of a name becomes the target's), matches each record with the target by its match key (a parent lookup in a
// key stands for the parent's own key, so a child a trigger created is matched, not duplicated), and:
//   options.dryRun = true   counts insert / update / unchanged per object, duplicate keys and records without a key
//   options.dryRun = false  loads parents first, then children (Bulk API: import for new records, update for changed
//                           ones), with the data set's trigger bypass switched on for this user and back after
// A key that matches two or more target records, or a record without a key, blocks the run (nothing is loaded).
// results/<id>/data.json: { status, dryRun, blocked, message, objects: [{ objectName, insert, update, unchanged, failed,
// duplicates, missingKeys, triggers, errors }], counts }.

const DATA_ID_RE = /^DAT-(\d{13})$/;
const DATA_INBOX = 'data-inbox';
const DATA_MAX_RECORDS = 10000;
const DATA_MAX_TARGET = 50000;
const DATA_PAGE = 2000;
const DATA_NAME_RE = /^[A-Za-z][A-Za-z0-9_]{0,79}$/;
const DATA_MASK_RULES = ['email', 'phone', 'name', 'blank'];
let dataLabelSource = false;

/** The org a data step talks about: the source (options.sourceLabel) in the export, else the target (options.label). */
function dataOrgLabel() {
    const label = String(options.sourceLabel || '');
    return dataLabelSource && /^[A-Za-z0-9 ._-]{1,40}$/.test(label) ? label : orgLabel();
}

/** The data set from the options, checked like the hub checks it; fails the run when it isn't usable. */
function dataSetOf() {
    const d = options.dataSet;
    const bad = (why) => { throw new Error(`The data set isn't usable: ${why}`); };
    if (!d || !Array.isArray(d.objects) || !d.objects.length || d.objects.length > 20) { bad('it needs 1 to 20 objects.'); }
    const seen = new Set();
    const objects = d.objects.map((o) => {
        const name = String((o && o.objectName) || '');
        if (!DATA_NAME_RE.test(name) || seen.has(name.toLowerCase())) { bad(`"${name}" isn't an object API name, or is there twice.`); }
        const fields = (Array.isArray(o.fields) ? o.fields : []).map(String);
        const key = (Array.isArray(o.matchKey) ? o.matchKey : []).map(String);
        const lower = new Set(fields.map((f) => f.toLowerCase()));
        if (!fields.length || fields.some((f) => !DATA_NAME_RE.test(f))) { bad(`${name} needs field API names.`); }
        if (!key.length || key.some((k) => !lower.has(k.toLowerCase()))) { bad(`${name} needs a match key made of its fields.`); }
        const filter = String(o.filter || '').replace(/\s+/g, ' ').trim();
        if (filter.length > 2000 || filter.includes(';') || /\s(limit|order\s+by)\s/i.test(' ' + filter + ' ')) { bad(`${name}'s record filter must be one condition.`); }
        const parents = o.parents && typeof o.parents === 'object' ? o.parents : {};
        for (const [f, p] of Object.entries(parents)) {
            if (!lower.has(String(f).toLowerCase()) || !seen.has(String(p).toLowerCase())) { bad(`${name}.${f} must point at an earlier object.`); }
        }
        const masks = o.masks && typeof o.masks === 'object' ? o.masks : {};
        for (const [f, r] of Object.entries(masks)) {
            const rule = String(r);
            if (!lower.has(String(f).toLowerCase()) || !(DATA_MASK_RULES.includes(rule) || rule.startsWith('fixed:'))) { bad(`${name}: mask ${f} isn't valid.`); }
        }
        seen.add(name.toLowerCase());
        return { objectName: name, fields, matchKey: key, filter, parents, masks };
    });
    const b = d.bypass && typeof d.bypass === 'object' && d.bypass.kind ? d.bypass : null;
    if (b && (!['setting', 'permissionSet'].includes(b.kind) || !DATA_NAME_RE.test(String(b.name || '')) || (b.kind === 'setting' && !DATA_NAME_RE.test(String(b.field || ''))))) {
        bad('the trigger bypass needs a kind and API names.');
    }
    return { title: String(d.title || 'Data set').slice(0, 80), objects, bypass: b };
}

/** One object's export query (Id and its fields). */
function dataQuery(o, withFilter = true) {
    const fields = new Map([['id', 'Id']]);
    o.fields.forEach((f) => fields.set(f.toLowerCase(), f));
    return `SELECT ${[...fields.values()].join(', ')} FROM ${o.objectName}` + (withFilter && o.filter ? ` WHERE ${o.filter}` : '');
}

/** sf with --json: the result, or an error with the CLI's own message. */
function sfJson(args) {
    let out;
    try {
        out = execFileSync('sf', [...args, '--json'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 512 * 1024 * 1024 });
    } catch (e) {
        out = e.stdout ? String(e.stdout) : '';
        let parsed = null;
        try {
            parsed = JSON.parse(out);
        } catch (x) {
            parsed = null;
        }
        throw new Error((parsed && (parsed.message || parsed.name)) || String(e.stderr || e.message).trim().slice(0, 500));
    }
    const parsed = JSON.parse(out);
    return parsed.result === undefined ? parsed : parsed.result;
}

/** A query's records (without "attributes"); fails when the CLI returned fewer than the query found. */
function sfRecords(alias, soql, tooling = false) {
    const res = sfJson(['data', 'query', '--query', soql, '--target-org', alias, ...(tooling ? ['--use-tooling-api'] : [])]);
    const records = res.records || [];
    if (typeof res.totalSize === 'number' && res.totalSize > records.length) {
        throw new Error(`the query found ${res.totalSize} records but only ${records.length} came back.`);
    }
    return records.map((r) => {
        const copy = { ...r };
        delete copy.attributes;
        return copy;
    });
}

/** Writes data.json (and adds or removes inbox files) on the results branch in one commit, retried like the others. */
function saveDataFiles(files, removals, message) {
    if (env.RELAY_LOCAL_RESULTS === 'true') {
        return;
    }
    for (let attempt = 1; attempt <= 4; attempt++) {
        const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-data-'));
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
            for (const [rel, text] of Object.entries(files)) {
                fs.mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true });
                fs.writeFileSync(path.join(dir, rel), text);
                git(['add', '--', rel], { cwd: dir });
            }
            const stale = staleData(dir);
            if (removals.length || stale.length) {
                gitQuietIn(dir, ['rm', '-r', '-q', '--ignore-unmatch', '--', ...removals, ...stale]);
            }
            git(['-c', 'user.name=Release Relay', '-c', 'user.email=release-relay@users.noreply.local',
                'commit', '-q', '--allow-empty', '-m', message], { cwd: dir });
            git(['push', '-q', 'origin', `HEAD:refs/heads/${RESULTS_BRANCH}`], { cwd: dir });
            return;
        } catch (e) {
            console.log(`Saving the data run's files failed (attempt ${attempt}); retrying.`);
        } finally {
            gitQuiet(['worktree', 'remove', '--force', dir]);
            fs.rmSync(dir, { recursive: true, force: true });
        }
    }
    fail(`Couldn't save the data run's files to the ${RESULTS_BRANCH} branch.`);
}

/** Data runs older than the compare keep days (results and inbox folders), never this run's. */
function staleData(dir) {
    const cutoff = Date.now() - COMPARE_KEEP_DAYS * 24 * 3600 * 1000;
    const stale = [];
    for (const parent of ['results', DATA_INBOX]) {
        const full = path.join(dir, parent);
        if (!fs.existsSync(full)) {
            continue;
        }
        for (const name of fs.readdirSync(full)) {
            const m = DATA_ID_RE.exec(name);
            if (m && name !== requestId && Number(m[1]) < cutoff) {
                stale.push(`${parent}/${name}`);
            }
        }
    }
    return stale;
}

/** Saves data.json (and, after a load or a failed export, removes this run's records). */
function saveDataResult(data, removeInbox) {
    const result = { request: requestId, step: 'data', ...data, runUrl: runUrl(), finishedAt: new Date().toISOString() };
    if (runToken) {
        result.attempt = runToken;
    }
    summary('```json\n' + JSON.stringify(result, null, 1).slice(0, 3000) + '\n```');
    saveDataFiles({ [`results/${requestId}/data.json`]: JSON.stringify(result, null, 1) + '\n' },
        removeInbox ? [`${DATA_INBOX}/${requestId}`] : [], `${requestId} data: ${result.status}`);
}

function dataFailed(message, objects = []) {
    saveDataResult({ status: 'Failed', dryRun: options.dryRun !== false, blocked: false, message: String(message).slice(0, 1500), objects }, options.dryRun === false);
    fail(message);
}

/** STEP=data-export: the source's records to data-inbox/<id>/. */
async function stepDataExport() {
    orgEnv = sourceEnv;
    dataLabelSource = true;
    if (mode !== 'data') { fail('STEP=data-export needs MODE=data.'); }
    let set;
    try {
        set = dataSetOf();
        login('data-src');
    } catch (e) {
        dataFailed(e.message);
    }
    const files = {};
    let total = 0;
    set.objects.forEach((o, i) => {
        let records;
        try {
            records = sfRecords('data-src', dataQuery(o));
        } catch (e) {
            dataFailed(`Reading ${o.objectName} in ${dataOrgLabel()} failed: ${e.message}`);
        }
        if (records.length > DATA_MAX_RECORDS) {
            dataFailed(`${o.objectName} has ${records.length} records in ${dataOrgLabel()}; a data set moves at most ${DATA_MAX_RECORDS} per object. Narrow its filter.`);
        }
        total += records.length;
        for (let p = 0; p * DATA_PAGE < Math.max(records.length, 1); p++) {
            const name = `${DATA_INBOX}/${requestId}/${String(i).padStart(2, '0')}-${String(p + 1).padStart(3, '0')}.json`;
            files[name] = JSON.stringify({ objectName: o.objectName, index: i, records: records.slice(p * DATA_PAGE, (p + 1) * DATA_PAGE) });
        }
    });
    saveDataFiles(files, [], `${requestId} data: ${total} records from ${dataOrgLabel()}`);
    console.log(`Exported ${total} records of ${set.objects.length} objects from ${dataOrgLabel()}.`);
}

/** The saved records per object index, from the results branch. */
function dataInboxRecords(count) {
    if (!remoteBranchExists(RESULTS_BRANCH)) {
        return null;
    }
    fetchBranch(RESULTS_BRANCH);
    const ref = `refs/remotes/origin/${RESULTS_BRANCH}`;
    const names = (gitQuiet(['ls-tree', '-r', '--name-only', ref, '--', `${DATA_INBOX}/${requestId}/`]) || '')
        .split('\n').filter((n) => /\/\d{2}-\d{3}\.json$/.test(n)).sort();
    if (!names.length) {
        return null;
    }
    const byIndex = Array.from({ length: count }, () => []);
    for (const n of names) {
        const part = JSON.parse(gitQuiet(['show', `${ref}:${n}`]) || '{}');
        const i = Number(part.index);
        if (Number.isInteger(i) && i >= 0 && i < count && Array.isArray(part.records)) {
            byIndex[i].push(...part.records);
        }
    }
    return byIndex;
}

/** A masked value: the same shape, no personal data. */
function maskValue(value, rule, n) {
    if (value === null || value === undefined || value === '') {
        return value;
    }
    if (rule === 'email') { return `masked.${n}@example.invalid`; }
    if (rule === 'phone') { return `+1 555 01${String(n % 100).padStart(2, '0')}`; }
    if (rule === 'name') { return `Masked ${n}`; }
    if (rule === 'blank') { return null; }
    return rule.startsWith('fixed:') ? rule.slice(6) : value;
}

/** The source's per-org values swapped for the target's in text values (names with a value in both). */
function dataValueSwaps() {
    const from = String(options.sourceValuesEnv || sourceEnv || '');
    const swaps = [];
    for (const [name, byEnv] of Object.entries(relayValues.values || {})) {
        const s = byEnv && byEnv[from];
        const t = byEnv && byEnv[targetEnv];
        if (typeof s === 'string' && typeof t === 'string' && s.length >= MIN_REVERSE_LENGTH && s !== t) {
            swaps.push([s, t, name]);
        }
    }
    return swaps;
}

/** Masks and per-org values applied to one object's records (a copy). */
function dataTransform(o, records, swaps) {
    let n = 0;
    return records.map((r) => {
        n += 1;
        const copy = { ...r };
        if (options.mask === true) {
            for (const [f, rule] of Object.entries(o.masks)) {
                const key = Object.keys(copy).find((k) => k.toLowerCase() === f.toLowerCase());
                if (key) {
                    copy[key] = maskValue(copy[key], String(rule), n);
                }
            }
        }
        for (const [k, val] of Object.entries(copy)) {
            if (typeof val === 'string') {
                copy[k] = swaps.reduce((acc, [s, t]) => acc.split(s).join(t), val);
            }
        }
        return copy;
    });
}

/** A record's field value, case-insensitively. */
function fieldOf(record, field) {
    const key = Object.keys(record).find((k) => k.toLowerCase() === field.toLowerCase());
    return key === undefined ? undefined : record[key];
}

/** A record's match key: its key fields, with a parent lookup standing for the parent's own key; '' when blank. */
function keyOf(o, record, parentKeys) {
    const parts = o.matchKey.map((f) => {
        const value = fieldOf(record, f);
        const parentObject = Object.keys(o.parents).find((p) => p.toLowerCase() === f.toLowerCase());
        if (parentObject && value) {
            const pk = (parentKeys[o.parents[parentObject].toLowerCase()] || new Map()).get(String(value));
            return pk === undefined ? '#' + value : '[' + pk + ']';
        }
        return value === null || value === undefined ? '' : String(value).trim().toLowerCase();
    });
    return parts.every((p) => p === '') ? '' : parts.join('|');
}

/** Fields a load never writes: Id, system fields and the owner (users differ between orgs). */
const DATA_SKIP_FIELDS = ['id', 'ownerid', 'createddate', 'createdbyid', 'lastmodifieddate', 'lastmodifiedbyid', 'systemmodstamp',
    'isdeleted', 'lastvieweddate', 'lastreferenceddate'];
/** A lookup whose parent is in the data set's records but not (yet) in the target: it's inserted first. */
const DATA_PENDING = '(a new parent)';

/** The fields the load writes. */
function writableFields(o) {
    return o.fields.filter((f) => !DATA_SKIP_FIELDS.includes(f.toLowerCase()));
}

/** The parent object a lookup field points at in the data set, or undefined. */
function parentOf(o, field) {
    const key = Object.keys(o.parents).find((p) => p.toLowerCase() === field.toLowerCase());
    return key === undefined ? undefined : String(o.parents[key]);
}

/**
 * One object's plan against the target: the records to insert, to update (all their written fields) and unchanged ones,
 * with the problems that block a load: keys matching more than one target record, records without a key, and lookups to
 * a parent that is neither in the data set's records nor in the target (orphans).
 */
function dataPlan(o, source, target, keys, idOf) {
    const byKey = new Map();
    for (const t of target) {
        const k = keyOf(o, t, keys.tgt);
        if (k) {
            byKey.set(k, (byKey.get(k) || []).concat([t]));
        }
    }
    const plan = { inserts: [], updates: [], unchanged: 0, duplicates: [], missingKeys: 0, orphans: 0 };
    const fields = writableFields(o);
    for (const r of source) {
        const k = keyOf(o, r, keys.src);
        if (!k) {
            plan.missingKeys += 1;
            continue;
        }
        const matches = byKey.get(k) || [];
        if (matches.length > 1) {
            plan.duplicates.push(k);
            continue;
        }
        const values = {};
        let orphan = false;
        for (const f of fields) {
            let val = fieldOf(r, f);
            const parent = parentOf(o, f);
            if (parent && val) {
                val = idOf(parent, String(val));
                orphan = orphan || val === null;
            }
            values[f] = val === undefined ? null : val;
        }
        if (orphan) {
            plan.orphans += 1;
        } else if (!matches.length) {
            plan.inserts.push(values);
        } else if (fields.some((f) => String(dataText(fieldOf(matches[0], f))) !== String(dataText(values[f])))) {
            plan.updates.push({ Id: matches[0].Id, ...values });
        } else {
            plan.unchanged += 1;
        }
    }
    return plan;
}

function dataText(value) {
    return value === null || value === undefined ? '' : value;
}

/** Objects whose triggers are active in the target (empty when the org won't say). */
function activeTriggerObjects(alias) {
    for (const soql of ["SELECT EntityDefinition.QualifiedApiName FROM ApexTrigger WHERE Status = 'Active'",
        "SELECT TableEnumOrId FROM ApexTrigger WHERE Status = 'Active'"]) {
        try {
            return new Set(sfRecords(alias, soql, true).map((r) => String((r.EntityDefinition && r.EntityDefinition.QualifiedApiName) || r.TableEnumOrId || '').toLowerCase()));
        } catch (e) {
            continue;
        }
    }
    return new Set();
}

/** CSV for the Bulk API: a header and the rows; an empty value clears the field (#N/A). */
function toCsv(rows, fields) {
    const cell = (v) => {
        if (v === null || v === undefined || v === '') {
            return '#N/A';
        }
        const s = typeof v === 'object' ? JSON.stringify(v) : String(v);
        return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
    };
    return [fields.join(','), ...rows.map((r) => fields.map((f) => cell(r[f])).join(','))].join('\n') + '\n';
}

/** A Bulk API load (import for new records, update for changed ones): the failed count and a note. */
function bulkLoad(alias, o, kind, rows) {
    if (!rows.length) {
        return { failed: 0, errors: [] };
    }
    const fields = kind === 'update' ? ['Id', ...writableFields(o)] : writableFields(o);
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-load-'));
    const file = path.join(dir, `${o.objectName}-${kind}.csv`);
    fs.writeFileSync(file, toCsv(rows, fields));
    try {
        const res = sfJson(['data', kind, 'bulk', '--sobject', o.objectName, '--file', file, '--wait', '30', '--target-org', alias]);
        const failed = Number(res.failedRecords || res.numberRecordsFailed || 0);
        return { failed, errors: failed ? [`${failed} ${kind === 'update' ? 'updates' : 'inserts'} failed (Bulk API job ${res.jobId || res.id || ''}).`] : [] };
    } catch (e) {
        return { failed: rows.length, errors: [`${kind === 'update' ? 'Updating' : 'Inserting'} failed: ${String(e.message).slice(0, 300)}`] };
    } finally {
        fs.rmSync(dir, { recursive: true, force: true });
    }
}

/** The pipeline user's Id in the target. */
function dataUserId(alias) {
    const info = sfJson(['org', 'display', '--target-org', alias]);
    const username = String(info.username || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
    const rows = sfRecords(alias, `SELECT Id FROM User WHERE Username = '${username}'`);
    if (!rows.length) {
        throw new Error(`the pipeline's user wasn't found in ${dataOrgLabel()}.`);
    }
    return rows[0].Id;
}

/** Switches the data set's trigger bypass on for the pipeline's user; returns what to undo. */
function bypassOn(alias, b) {
    const userId = dataUserId(alias);
    if (b.kind === 'permissionSet') {
        const had = sfRecords(alias, `SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = '${userId}' AND PermissionSet.Name = '${b.name}'`);
        if (had.length) {
            return { kind: 'permissionSet', id: null };
        }
        const sets = sfRecords(alias, `SELECT Id FROM PermissionSet WHERE Name = '${b.name}'`);
        if (!sets.length) {
            throw new Error(`the trigger bypass permission set ${b.name} isn't in ${dataOrgLabel()}.`);
        }
        const made = sfJson(['data', 'create', 'record', '--sobject', 'PermissionSetAssignment', '--values',
            `AssigneeId=${userId} PermissionSetId=${sets[0].Id}`, '--target-org', alias]);
        return { kind: 'permissionSet', id: made.id };
    }
    const rows = sfRecords(alias, `SELECT Id, ${b.field} FROM ${b.name} WHERE SetupOwnerId = '${userId}'`);
    if (rows.length) {
        const was = fieldOf(rows[0], b.field) === true;
        if (!was) {
            sfJson(['data', 'update', 'record', '--sobject', b.name, '--record-id', rows[0].Id, '--values', `${b.field}=true`, '--target-org', alias]);
        }
        return { kind: 'setting', id: rows[0].Id, was, created: false };
    }
    const made = sfJson(['data', 'create', 'record', '--sobject', b.name, '--values', `SetupOwnerId=${userId} ${b.field}=true`, '--target-org', alias]);
    return { kind: 'setting', id: made.id, was: false, created: true };
}

/** Puts the bypass back as it was; a warning when it can't. */
function bypassOff(alias, b, state) {
    try {
        if (state.kind === 'permissionSet' && state.id) {
            sfJson(['data', 'delete', 'record', '--sobject', 'PermissionSetAssignment', '--record-id', state.id, '--target-org', alias]);
        } else if (state.kind === 'setting' && state.created) {
            sfJson(['data', 'delete', 'record', '--sobject', b.name, '--record-id', state.id, '--target-org', alias]);
        } else if (state.kind === 'setting' && !state.was) {
            sfJson(['data', 'update', 'record', '--sobject', b.name, '--record-id', state.id, '--values', `${b.field}=false`, '--target-org', alias]);
        }
        console.log(`Trigger bypass (${b.name}) switched back off in ${dataOrgLabel()}.`);
    } catch (e) {
        console.log(`::warning::The trigger bypass (${b.name}) couldn't be switched back off in ${dataOrgLabel()}: ${e.message}`);
        summary(`**Check ${dataOrgLabel()}:** the trigger bypass ${b.name} may still be on for the pipeline's user.`);
    }
}

/** The target's records of one object (all of them: the match must see records outside the filter too). */
function dataTarget(o) {
    const records = sfRecords('data-tgt', dataQuery(o, false));
    if (records.length > DATA_MAX_TARGET) {
        throw new Error(`${o.objectName} has more than ${DATA_MAX_TARGET} records in ${dataOrgLabel()}: too many to match safely.`);
    }
    return records;
}

/**
 * One pass over the objects in order (parents first). Without load it only counts; with load it inserts and updates
 * each object, then reads its records again so the children's lookups find the new parents.
 */
function dataPass(set, saved, swaps, load, triggers) {
    const keys = { src: {}, tgt: {}, ids: {} };
    const rows = [];
    for (let i = 0; i < set.objects.length; i++) {
        const o = set.objects[i];
        const name = o.objectName.toLowerCase();
        const source = dataTransform(o, saved[i] || [], swaps);
        let target = dataTarget(o);
        const idOf = (parentObject, sourceId) => {
            const p = parentObject.toLowerCase();
            const key = (keys.src[p] || new Map()).get(sourceId);
            const id = key ? (keys.ids[p] || new Map()).get(key) : undefined;
            if (id) {
                return id;
            }
            // Not in the target: a parent in the data set's records is inserted first (dry run); after the load it's missing.
            return key && !load ? DATA_PENDING : null;
        };
        const plan = dataPlan(o, source, target, keys, idOf);
        const row = { objectName: o.objectName, insert: plan.inserts.length, update: plan.updates.length, unchanged: plan.unchanged,
            failed: 0, duplicates: plan.duplicates.slice(0, 50), missingKeys: plan.missingKeys,
            triggers: triggers.has(name), errors: [] };
        if (plan.orphans) {
            row.errors.push(`${plan.orphans} records point at a parent that is neither in the data set's records nor in ${dataOrgLabel()}.`);
        }
        if (load) {
            const a = bulkLoad('data-tgt', o, 'import', plan.inserts);
            const b = bulkLoad('data-tgt', o, 'update', plan.updates);
            row.failed = a.failed + b.failed + plan.orphans;
            row.errors = row.errors.concat(a.errors, b.errors);
            if (plan.inserts.length) {
                target = dataTarget(o);
            }
        }
        keys.src[name] = new Map(source.map((r) => [String(r.Id), keyOf(o, r, keys.src)]));
        keys.tgt[name] = new Map(target.map((r) => [String(r.Id), keyOf(o, r, keys.tgt)]));
        keys.ids[name] = new Map(target.map((r) => [keys.tgt[name].get(String(r.Id)), String(r.Id)]).filter(([k]) => k));
        row.orphans = plan.orphans;
        rows.push(row);
    }
    return rows;
}

/** What blocks a load: keys matching two or more target records, records without a key, orphans. */
function dataBlockMessage(rows) {
    const bad = rows.filter((r) => r.duplicates.length || r.missingKeys || r.orphans);
    if (!bad.length) {
        return '';
    }
    return 'Blocked: ' + bad.map((r) => r.objectName + ' (' + [
        r.duplicates.length ? `${r.duplicates.length} keys match more than one record in ${dataOrgLabel()}: ${r.duplicates.slice(0, 5).join(', ')}` : '',
        r.missingKeys ? `${r.missingKeys} records without a key` : '',
        r.orphans ? `${r.orphans} records whose parent isn't there` : ''].filter(Boolean).join('; ') + ')').join(' · ') + '. Nothing was loaded.';
}

/** STEP=data-load: the dry run, or the load of the saved records into the target. */
async function stepDataLoad() {
    orgEnv = targetEnv;
    if (mode !== 'data') {
        fail('STEP=data-load needs MODE=data.');
    }
    let set;
    try {
        set = dataSetOf();
    } catch (e) {
        dataFailed(e.message);
    }
    const saved = dataInboxRecords(set.objects.length);
    if (!saved) {
        dataFailed(`The data set's records weren't found on ${RESULTS_BRANCH} (${DATA_INBOX}/${requestId}/). Start the run again from Release Relay.`);
    }
    const dryRun = options.dryRun !== false;
    const swaps = dataValueSwaps();
    let rows = [];
    let blockMessage = '';
    try {
        login('data-tgt');
        const triggers = set.bypass ? new Set() : activeTriggerObjects('data-tgt');
        rows = dataPass(set, saved, swaps, false, triggers);
        blockMessage = dataBlockMessage(rows);
        if (!dryRun && !blockMessage) {
            // The counts are checked again just before the load: the target may have changed since the dry run.
            const state = set.bypass ? bypassOn('data-tgt', set.bypass) : null;
            try {
                rows = dataPass(set, saved, swaps, true, triggers);
            } finally {
                if (state) {
                    bypassOff('data-tgt', set.bypass, state);
                }
            }
        }
    } catch (e) {
        dataFailed(e.message, rows);
    }
    const failed = rows.filter((r) => r.failed);
    let message = blockMessage;
    if (!message && failed.length) {
        message = 'Some records weren\'t saved: ' + failed.map((r) => `${r.objectName} ${r.failed}`).join(', ') + '.';
    }
    const status = message ? 'Failed' : 'Succeeded';
    const counts = rows.reduce((c, r) => ({ insert: c.insert + r.insert, update: c.update + r.update, unchanged: c.unchanged + r.unchanged,
        failed: c.failed + r.failed, duplicates: c.duplicates + r.duplicates.length }), { insert: 0, update: 0, unchanged: 0, failed: 0, duplicates: 0 });
    saveDataResult({ status, dryRun, blocked: Boolean(blockMessage), message, objects: rows, counts }, !dryRun);
    console.log(`${dryRun ? 'Dry run' : 'Load'} into ${dataOrgLabel()}: ${counts.insert} insert, ${counts.update} update, ${counts.unchanged} unchanged, ${counts.failed} failed.`);
    if (status !== 'Succeeded' && !(dryRun && blockMessage)) {
        fail(message); // a blocked dry run has done its job: the hub shows what blocks it
    }
}

// ---------- step: monitor (version 20) ----------

/** What a run does, by mode, as the hub's Pipeline Monitor shows it. */
const MONITOR_STEPS = { org: 'Raise', branch: 'Raise', promote: 'Raise', hub: 'Raise', resolve: 'Resolve conflicts',
    check: 'Check-only deploy', merge: 'Merge', sync: 'Back promote', rollback: 'Rollback', archive: 'Archive', compare: 'Compare',
    drift: 'Org vs branch', routediff: 'Down the route', data: 'Data' };
/** The pipeline's jobs whose outcomes make the run's status, with the names the hub shows. */
const MONITOR_JOBS = { raise: 'Raise pull request', scan: 'Code scan', validate: 'Check-only deploy', merge: 'Merge',
    deploy: 'Deploy', sync: 'Back promote', 'sync-branch': 'Back promote (branch only)', rollback: 'Rollback', archive: 'Archive',
    compare: 'Compare', drift: 'Org vs branch', routediff: 'Down the route', 'data-export': 'Data export', 'data-load': 'Data load' };

function monitorWarn(message) {
    console.log('::warning::Pipeline Monitor: ' + message);
}

/** The run's GitHub numbers and address, or null outside GitHub Actions. */
function monitorRun() {
    const runId = String(env.GITHUB_RUN_ID || '');
    if (!/^\d+$/.test(runId) || !env.GITHUB_REPOSITORY) {
        return null;
    }
    const attempt = /^\d+$/.test(String(env.GITHUB_RUN_ATTEMPT || '')) ? Number(env.GITHUB_RUN_ATTEMPT) : 1;
    const server = env.GITHUB_SERVER_URL || 'https://github.com';
    const api = env.GITHUB_API_URL || 'https://api.github.com';
    return { runId, attempt, url: `${server}/${env.GITHUB_REPOSITORY}/actions/runs/${runId}`,
        api: `${api}/repos/${env.GITHUB_REPOSITORY}` };
}

/** GET from the GitHub API with this job's token; null when it can't be read (the monitor goes on without it). */
async function monitorApi(url) {
    if (!env.GH_TOKEN) {
        return null;
    }
    try {
        const res = await http('GET', url, { Authorization: `Bearer ${env.GH_TOKEN}`, 'X-GitHub-Api-Version': '2022-11-28' });
        return res.ok ? res.json : null;
    } catch (e) {
        return null;
    }
}

/** The run's status from the main jobs' results in NEEDS_JSON: Failed, Cancelled or Succeeded. */
function monitorEndStatus() {
    let needs = {};
    try {
        needs = JSON.parse(input('NEEDS_JSON') || '{}') || {};
    } catch (e) {
        needs = {};
    }
    const results = Object.keys(MONITOR_JOBS).map((j) => needs[j] && needs[j].result).filter(Boolean);
    if (results.includes('failure')) {
        return 'Failed';
    }
    return results.includes('cancelled') ? 'Cancelled' : 'Succeeded';
}

function monitorSeconds(from, to) {
    const a = Date.parse(from || '');
    const b = Date.parse(to || '');
    return isNaN(a) || isNaN(b) ? null : Math.max(0, Math.round((b - a) / 1000));
}

/** The finished main jobs as [{name, outcome, seconds}], and the first failures as text (job › step: message). */
async function monitorJobs(gh) {
    const data = await monitorApi(`${gh.api}/actions/runs/${gh.runId}/attempts/${gh.attempt}/jobs?per_page=100`);
    const jobs = (data && Array.isArray(data.jobs) ? data.jobs : []).filter((j) => MONITOR_JOBS[j.name] && j.conclusion);
    const steps = jobs.map((j) => ({ name: MONITOR_JOBS[j.name], outcome: j.conclusion, seconds: monitorSeconds(j.started_at, j.completed_at) }));
    const failed = jobs.filter((j) => j.conclusion === 'failure').slice(0, 3);
    const notes = await Promise.all(failed.map((j) => monitorApi(`${gh.api}/check-runs/${j.id}/annotations?per_page=20`)));
    const lines = failed.map((j, i) => {
        const step = (j.steps || []).find((st) => st.conclusion === 'failure');
        const errors = (Array.isArray(notes[i]) ? notes[i] : []).filter((a) => a.annotation_level === 'failure')
            .map((a) => String(a.message || '').trim()).filter((m) => m && !/^Process completed with exit code/.test(m));
        return `${MONITOR_JOBS[j.name]}${step ? ' › ' + step.name : ''} failed` + (errors.length ? ': ' + errors.slice(0, 3).join(' | ') : '');
    });
    return { steps, failure: lines.join('\n').slice(0, 30000) };
}

/** Signs in to the hub and posts this run's start or end. Never fails the run. */
async function stepMonitor() {
    orgEnv = ''; // this job's environment holds the hub's login
    const gh = monitorRun();
    if (!gh) {
        monitorWarn('not a GitHub Actions run; nothing to post.');
        return;
    }
    if (/^(debug|test)\//.test(env.GITHUB_REF_NAME || '')) {
        console.log('Pipeline Monitor: a debug or test run (' + env.GITHUB_REF_NAME + '); not shown on the monitor.');
        return;
    }
    const hasKey = (v('SF_JKS') && v('SF_JKS_PASSWORD') && v('SF_JKS_ALIAS')) || v('SF_JWT_KEY');
    if (!v('SF_USERNAME') || !v('SF_CLIENT_ID') || !v('SF_INSTANCE_URL') || !hasKey) {
        monitorWarn('the hub environment\'s login (SF_USERNAME, SF_CLIENT_ID, SF_INSTANCE_URL and SF_JKS or SF_JWT_KEY) isn\'t set; nothing posted.');
        return;
    }
    const scheduled = env.GITHUB_EVENT_NAME === 'schedule';
    const runMode = scheduled ? 'archive' : mode;
    const ending = input('MONITOR_STATUS') === 'end';
    const now = new Date().toISOString();
    const runInfo = await monitorApi(`${gh.api}/actions/runs/${gh.runId}/attempts/${gh.attempt}`);
    const startedAt = runInfo && runInfo.run_started_at ? runInfo.run_started_at : (ending ? null : now);
    let step = MONITOR_STEPS[runMode] || runMode || 'Run';
    if (runMode === 'merge' && targetEnv) {
        step = 'Merge and deploy';
    }
    const body = {
        runId: gh.runId, attempt: gh.attempt, mode: runMode, step,
        branch: runMode === 'sync' || runMode === 'compare' || runMode === 'drift' ? target
            : (runMode === 'routediff' ? (target || (Array.isArray(options.route) ? options.route.map(String).join(' → ').slice(0, 255) : null))
                : (runMode === 'archive' ? env.GITHUB_REF_NAME : branch)) || null,
        targetOrg: targetEnv || sourceEnv || (runMode === 'archive' ? input('RELAY_HUB_ENVIRONMENT') || 'prod' : null),
        status: ending ? monitorEndStatus() : 'In progress',
        started: startedAt, actor: scheduled ? 'Schedule' : (env.GITHUB_TRIGGERING_ACTOR || env.GITHUB_ACTOR || null),
        runUrl: gh.url, requestId: /^REL-\d{5,}$/.test(requestId) ? requestId : null
    };
    if (ending) {
        const jobs = await monitorJobs(gh);
        body.finished = now;
        body.durationSeconds = monitorSeconds(startedAt, now);
        if (jobs.steps.length) {
            body.steps = jobs.steps;
        }
        body.failureMessage = body.status === 'Failed' ? jobs.failure || 'A job failed; the run log has the details.' : null;
    }
    login('relay-hub');
    // The CLI signs the call itself: newer CLIs hide the access token in "sf org display".
    const out = run('sf', ['api', 'request', 'rest', '/services/apexrest/rly/pipeline-run', '--method', 'POST',
        '--body', JSON.stringify(body), '--target-org', 'relay-hub']);
    let json = null;
    try { json = JSON.parse(out); } catch (ignore) { json = null; }
    if (json && json.ok === true) {
        console.log(`Pipeline Monitor: run ${gh.runId} (attempt ${gh.attempt}) is ${json.status} in the hub.`);
        (json.warnings || []).forEach((w) => monitorWarn(w));
    } else {
        monitorWarn(`the hub didn't save the run: ${json && json.error ? json.error : String(out).slice(0, 300)}`);
    }
}

// ---------- main ----------

const STEPS = { raise: stepRaise, scan: stepScan, validate: stepValidate, merge: stepMerge, deploy: stepDeploy, sync: stepSync,
    rollback: stepRollback, auto: stepAuto, compare: stepCompare, drift: stepDrift, routediff: stepRouteDiff,
    'data-export': stepDataExport, 'data-load': stepDataLoad };

async function main() {
    if (step === 'notify') {
        await stepNotify();
        return;
    }
    if (step === 'monitor') {
        // The monitor never fails the run: any problem is a warning.
        try {
            await stepMonitor();
        } catch (e) {
            monitorWarn(`couldn't post this run to the hub (${String((e && (e.stderr || e.message)) || e).trim().slice(0, 300)}).`);
        }
        return;
    }
    checkCommonInputs();
    // The pipeline's own settings, read before any step checks out another commit.
    loadExcludes();
    relayValues = parseValues(pipelineFile(VALUES_FILE));
    relayValues.warnings.forEach((w) => console.log('::warning::' + w));
    relayGates = parseGates(pipelineFile(GATES_FILE));
    if (selfUpdate() && target !== 'release-relay-hub' && mode !== 'rollback') {
        summary(`**Note:** selfUpdate is set but the target is ${target}; the hub's own updates belong on release-relay-hub.`);
    }
    if (!STEPS[step]) {
        fail('STEP must be raise, scan, validate, merge, deploy, sync, rollback, auto, compare, drift, routediff, data-export or data-load.');
    }
    preparePush();
    await STEPS[step]();
}

main().catch((e) => fail(e && e.message ? e.message : String(e)));
