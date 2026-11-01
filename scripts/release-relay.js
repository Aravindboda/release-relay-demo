#!/usr/bin/env node
// Release Relay pipeline files: version 13
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
 *                  DELETIONS (Type:Name list, and/or .relay-inbox/<REQUEST_ID>.deletions, the hub's
 *                  marker for a release with only deletions) removes those components' files from
 *                  BRANCH in the same commit; validate and deploy then delete them from the org
 *                  (destructiveChangesPost). raise.json lists them under "deleted".
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
    if (!/^REL-\d{5,}$/.test(requestId)) { fail('REQUEST_ID must look like REL-00042.'); }
    if (!['org', 'branch', 'promote', 'hub', 'resolve', 'check', 'merge', 'sync', 'rollback'].includes(mode)) { fail('MODE must be org, branch, promote, hub, resolve, check, merge, sync or rollback.'); }
    if (mode === 'rollback') {
        // A rollback works on an org and the snapshots branch only: BRANCH and TARGET aren't used.
        if (!/^[A-Za-z0-9._-]{1,80}$/.test(targetEnv)) { fail('TARGET_ENVIRONMENT (the org to roll back) must be an environment name.'); }
    } else if (mode === 'sync') {
        // A back promote takes the hub's production branch (any branch name) into a back-promote org's branch.
        if (!REF_RE.test(branch) || branch.includes('..')) { fail(`Branch "${branch}" isn't a valid source branch.`); }
    } else if (!BRANCH_RE.test(branch)) { fail(`Branch "${branch}" must look like feature/short-name.`); }
    if (mode !== 'rollback' && (!REF_RE.test(target) || target.includes('..') || target === branch || target === RESULTS_BRANCH || target === SNAPSHOT_BRANCH)) { fail(`Target "${target}" isn't a valid target branch.`); }
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
    const edits = [];
    const missing = [];
    const used = new Map();
    for (const f of deploymentFiles(plan.sources || [])) {
        const text = readText(f);
        if (text === null || !text.includes('{{relay:')) {
            continue;
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
    if (!relayValues.present || !envName) {
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

/** tests.requireForApex: a deployment with Apex that would run no tests fails before it's sent. */
function evaluateTestsGate(apex, testLevel, gates) {
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
function evaluateCoverageGate(codeCoverage, apex, testLevel, gates) {
    if (!gates.coverage) {
        return { failures: [], coverage: null };
    }
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
    const all = changedFiles(base, head);
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
    return { pkg, destructive, changed: existing.length, deleted: deletions.size,
        deletedList: [...deletions.keys()], sources: existing, apex };
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
 * { status: 'Opened' | 'Failed', mode, branch, target, sha, pr, url, commits, conflicts, deleted, valuesTokenized, message }.
 * deleted: the Type:Name entries mode hub removed from BRANCH (always [] for promote). valuesTokenized: how many
 * occurrences of the source environment's values (.relay/values.json) became {{relay:NAME}} (always 0 for promote).
 */
function raiseResult(status, data) {
    writeResult('raise', { status, mode, branch, target, sha: null, pr: null, url: null,
        commits: [], conflicts: [], deleted: [], valuesTokenized: 0, message: '', ...data });
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
        raiseFailed('Converting the files from the hub failed: ' + detail.replace(/\s+/g, ' ').trim().slice(0, 1500));
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

async function raiseFromHub() {
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
    const hasZip = fs.existsSync(zipFile);
    if (!hasZip && !deletions.length) {
        raiseFailed(`${zipFile} isn't on ${branch} (nor a ${markerFile} listing deletions). Raise the release again from Release Relay.`);
    }
    const clash = addedAndDeleted(components, deletions);
    if (clash) {
        raiseFailed(clash, { deleted });
    }

    // Deletions first, on the branch as the hub left it: each must be there to be removed.
    for (const d of deletions) {
        const paths = deletionPaths(d);
        if (paths === null) {
            raiseFailed(`Deleting ${d.type} isn't supported by the pipeline. Remove ${d.name} in a normal ${provider.label}.`, { deleted });
        }
        const found = paths.filter((p) => fs.existsSync(p));
        if (!found.length) {
            raiseFailed(`${d.type} ${d.name} isn't in ${branch}, so there's nothing to delete.`, { deleted });
        }
        git(['rm', '-r', '-q', '--', ...found]);
    }

    let copied = [];
    if (hasZip) {
        const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-hub-'));
        const mdapi = path.join(tmp, 'mdapi');
        const out = path.join(tmp, 'source');
        let unzipped = true;
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
        git(['rm', '-q', '--', zipFile]);
    }
    // The developer org's own values go into the branch as {{relay:NAME}} placeholders.
    const tokens = tokenizeFiles(copied.map((r) => path.join(sourcePath(), r)), sourceEnv);
    if (tokens.error) {
        raiseFailed(tokens.error, { deleted });
    }
    const valuesTokenized = tokens.count;
    if (fs.existsSync(markerFile)) {
        if (gitQuiet(['ls-files', '--error-unmatch', '--', markerFile]) !== null) {
            git(['rm', '-q', '-f', '--', markerFile]);
        } else {
            fs.rmSync(markerFile, { force: true });
        }
    }
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
    const lines = (picked) => [
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
        await openAndRecord(lines(shas), { sha: head, commits: shas });
        return;
    }

    git(['fetch', '--no-tags', 'origin']); // the commits live on the previous stage's branch
    fetchBranch(target);
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
            execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
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
        const early = gatesResult(relayGates, evaluateTestsGate(plan.apex, testLevelFor(plan).testLevel, relayGates));
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
        coverageCheck = evaluateCoverageGate(r.codeCoverage, plan.apex, r.testLevel, relayGates);
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
    if (!targetEnv) {
        stop({ message: 'No target environment: a back promote needs the org to deploy to.' });
    }
    let oldHead = null;
    let head;
    try {
        fetchBranch(branch);
        if (remoteBranchExists(target)) {
            fetchBranch(target);
            oldHead = git(['rev-parse', `refs/remotes/origin/${target}`]);
            git(['checkout', '-q', '-B', target, oldHead]);
            try {
                run('git', ['merge', '--no-edit', '-m', `Release Relay ${requestId}: back promote ${branch} into ${target}`,
                    `refs/remotes/origin/${branch}`], { stdio: ['ignore', 'pipe', 'pipe'] });
            } catch (e) {
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
        } else {
            git(['checkout', '-q', '-B', target, `refs/remotes/origin/${branch}`]);
        }
        head = git(['rev-parse', 'HEAD']);
    } catch (e) {
        stop({ message: String(e.message || e).slice(0, 1500) });
    }

    const push = () => git(['push', '-q', 'origin', `HEAD:refs/heads/${target}`]);
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
                : oldHead === head ? `${target} already includes ${branch}.`
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

const STEPS = { raise: stepRaise, scan: stepScan, validate: stepValidate, merge: stepMerge, deploy: stepDeploy, sync: stepSync,
    rollback: stepRollback, auto: stepAuto };

async function main() {
    if (step === 'notify') {
        await stepNotify();
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
        fail('STEP must be raise, scan, validate, merge, deploy, sync, rollback or auto.');
    }
    preparePush();
    await STEPS[step]();
}

main().catch((e) => fail(e && e.message ? e.message : String(e)));
