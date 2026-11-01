<!-- Release Relay pipeline files: version 14 -->
# Release Relay pipelines for GitLab, Bitbucket and Azure DevOps

These files do what `.github/workflows/release-relay.yml` does on GitHub, with the same modes
(`org`, `branch`, `promote`, `hub`, `resolve`, `check`, `merge`, `sync`, `rollback`), the same jobs (raise, scan,
validate, merge, deploy, sync, rollback, notify) and the same script, `scripts/release-relay.js`. Every job runs the default
branch's copy of the script (`git show <pipeline commit>:scripts/release-relay.js`), never the copy on
the release branch.

| Provider | File here | Put it in the owner's repository at | Hub Git connection, Pipeline field |
|---|---|---|---|
| GitHub | (`.github/workflows/release-relay.yml`) | `.github/workflows/release-relay.yml` | `release-relay.yml` |
| GitLab | `gitlab/.gitlab-ci.yml` | `.gitlab-ci.yml` at the root of the default branch | `.gitlab-ci.yml` (blank means the same) |
| Bitbucket | `bitbucket/bitbucket-pipelines.yml` | `bitbucket-pipelines.yml` at the root of the default branch | (not used: the custom pipeline is `release-relay`) |
| Azure DevOps | `azure/azure-pipelines.yml` | `azure-pipelines.yml` at the root of the default branch (any path works) | the pipeline id (`definitionId=` in its address) |

Every provider also needs `scripts/release-relay.js` on the default branch. `.relay/exclude`, `.relay/values.json`
and `.relay/gates.json` are optional; like the script, they are read from the pipeline's own commit (the default
branch), never from a release branch.

## The same for every provider

**Each stage org's login** (any org the pipeline validates or deploys to, and any org it signs in to):

| Name | Secret | Value |
|---|---|---|
| `SF_USERNAME` | yes | the integration user's username |
| `SF_CLIENT_ID` | yes | the External Client App's consumer key |
| `SF_INSTANCE_URL` | no | the org's My Domain URL, `https://example.my.salesforce.com` |
| `SF_JKS` | yes | the keystore exported from Certificate and Key Management, **base64 on one line** (`base64 -w0 release_relay.jks`, on macOS `base64 -i release_relay.jks`) |
| `SF_JKS_PASSWORD` | yes | the keystore password |
| `SF_JKS_ALIAS` | no | the certificate's Unique Name, `release_relay` |
| `SF_JWT_KEY` | yes | instead of the three `SF_JKS*`: the PEM private key, base64 on one line |

The script reads `SF_JKS` as text, so it can't be a GitLab File variable or an Azure secure file.

**Optional settings** (shared, or per org): `SOURCE_PATH` (default `force-app/main/default`),
`SCAN_RULES` (`Recommended`), `SCAN_BLOCK_SEVERITY` (`2` = High), `DEPLOY_TEST_LEVEL` (`RunLocalTests`; the hub's
test list wins), `MERGE_METHOD` (`merge` or `squash`), and for runs not started by the hub: `ALLOWED_TARGETS`,
`ORG_LABEL`, `WRITE_DESTRUCTIVE_MANIFEST`.

**Prefixes.** The script reads `<PREFIX>_NAME` before `NAME`, where `<PREFIX>` is the org's environment name
in upper case with anything that isn't a letter or digit turned into `_`: `sit` → `SIT_SF_USERNAME`,
`sit-uat` → `SIT_UAT_SF_USERNAME`. That's how one job holds several orgs' logins on Bitbucket (and on
GitLab, if you don't use environment scopes).

**Branches.** The pipeline pushes `feature/…`, `hotfix/…` and `promote/…` branches, the stage and developer
branches it updates after a merge (`syncBranches`), the back-promote orgs' branches (mode `sync`),
`release-relay-results` and `release-relay-snapshots` (rollback snapshots). Neither of the last two may be
protected.

## What the hub sends and reads

**Options** (`OPTIONS`, JSON): `hub` (true: the hub checked the route, so `ALLOWED_TARGETS` isn't needed),
`label`, `tests` (the release's test classes; `[]` = NoTestRun), `scan` (`off`), `validateMerged` (validate the
branch merged with the target), `attempt` (the run's token, echoed in every result file), `notify`, and for
`merge`: `syncBranches` (the branches to bring the target into after the merge, in order; after a deploy to
production every stage branch, then every developer branch) and `stageWins` (true: the first listed branch takes
the target's lines where they conflict; otherwise a conflict is reported for that branch, never forced), and
`quickDeploy` (false: always deploy in full; see Quick deploy), and `selfUpdate` (true: the hub updating itself;
the exclude list is ignored, see Release Relay's own metadata), `snapshot` (false: no rollback snapshot before the
deploy), and for `rollback`: `snapshotPath` (`REL-00042/prod/<id>`; blank = the latest snapshot of that release in
that environment) and `tests`. Version 14 adds `stageBranch` (mode `promote`: the previous stage's branch; see
Promotion from the stage) and `append` with `appendZip` (mode `hub`: see Adding changes to an open release).

**Result files** on `release-relay-results`, `results/<REQUEST_ID>/<step>.json`, each with `request`, `step`,
`status`, `runUrl`, `finishedAt` and `attempt`:

- `raise.json` (modes `hub` and `promote` started by the hub): `status` `Opened` or `Failed`, `mode`, `branch`,
  `target`, `sha` (the branch head pushed), `pr` (number), `url`, `commits` (promote: the merge commits picked),
  `conflicts` (promote: files a commit conflicted on), `deleted` (mode `hub`: the `Type:Name` deletions removed
  from the branch; `[]` otherwise), `valuesTokenized` (mode `hub`: occurrences of the source org's values turned
  into `{{relay:NAME}}`; `0` otherwise), `appended` (true for changes added to an open release), `message`. A
  promotion from the stage adds `files` (how many files the releases changed) and `fromStage` (the stage branch),
  and when it stops on a hotfix, `conflicts` (the files) and `clash` (`[{ "file", "targetBlob", "stageBlob" }]`).
  Changes added to an open release add `files` (files written) and `appendZip`; `pr` and `url` are the open pull
  request's (null when none is found).
- `validate.json` and `deploy.json` list `deleted` (`Type:Name`): the components deployed as
  `destructiveChangesPost.xml` because their files were removed.
- `validate.json`, `deploy.json` and `sync.json` list `excluded` (repo paths): changed or deleted files that match
  `.relay/exclude` and were neither deployed nor deleted, and `selfUpdate` (true when the list was ignored).
- `scan.json`: as before, plus `gate` (`{ "failAtPriority", "findings" }`, or null without a scan gate) and
  `gates`. `validate.json` also records `mergedWith` (the target commit validated against), `validatedTree` (the
  merged files' tree), `environment`, `gates` and, when the coverage gate ran, `coverage`
  (`{ "minimumPerClass", "minimumOrgWide", "perClass": [{ "name", "percent" }], "orgWide" }`).
- `gates` (scan.json, validate.json): `{ "file": ".relay/gates.json" | null, "passed": true | false, "failures": [ … ] }`.
  A failed gate makes the step `Failed` (validate.json also `ok: false`), with the failures in `message`.
- `values` (validate.json, deploy.json, sync.json): `{ "replaced": n, "files": [ up to 50, relative to SOURCE_PATH ],
  "hash": "…" }`: placeholders filled with the target org's values, and a fingerprint of the values used ("" when
  none), so a quick deploy never sends a validation's outdated values.
- `deploy.json`: as before, plus `quick` (true when the validation was quick deployed) and `quickNote` (why it
  wasn't, or which validation was used), and `snapshot`: `{ "branch": "release-relay-snapshots", "path":
  "REL-00042/prod/<id>", "existing": n, "added": n }`, or `{ "skipped": "…" }` (options `snapshot: false`,
  `selfUpdate`), or `{ "error": "…" }` (the snapshot failed; the deploy went ahead). `sync.json` has the same
  `snapshot` when it deployed.
- `merge.json`: `status` `Merged` or `Failed`, `pr`, `sha`, `method`, and `sync`: one entry per `syncBranches`
  branch, `{ "branch", "status": "Synced" | "Conflict" | "Missing", "message" }`.
- `sync.json` (mode `sync`): `status` `Deployed`, `Nothing to deploy`, `Conflict` or `Failed`, `sha` (the
  back-promote branch's new head; for a conflict the production head that couldn't be merged), `deployId`,
  `testsRun`, `conflicts` (files), `message`.
- `rollback.json` (mode `rollback`): `status` `Rolled back` or `Failed`, `environment`, `deployId`, `restored`
  (components put back as they were), `removed` (components the release had added, deleted), `snapshot` (its
  path), `message`, `testLevel`, `testsRun`, `componentErrors`, `testFailures`.

**Deletions (mode `hub`).** `deletions` is a comma-separated `Type:Name` list. The hub commits either
`.relay-inbox/<REQUEST_ID>.zip` (the retrieve), `.relay-inbox/<REQUEST_ID>.deletions` (a marker, empty or holding the
same list, when the release has only deletions), or both; the pipeline accepts any of these and removes both files.
Each deletion's files must be on the branch (`ApexClass:X` = `classes/X.cls` + `-meta.xml`, bundles and
`CustomObject` = their folder, `CustomField:Object.Field` etc. = the child file, `StaticResource` = the resource and
its `-meta.xml`), else `raise.json` is `Failed` with "<Type> <Name> isn't in <branch>, so there's nothing to
delete." A component both added and deleted fails the raise. The files are removed in the same commit as the
converted components; validate (check-only) and deploy then send the removed components as
`destructiveChangesPost.xml`, and a quick deploy of that validation includes them. A custom object deleted as a whole
is sent as the object alone (its fields and other children go with it).

**Quick deploy.** After a merge, the deploy step quick deploys the release's validation
(`sf project deploy quick --job-id <validate.json deployId>`, no tests run again) when all of these hold:
`quickDeploy` isn't false; the validation passed with a deploy id, against the same environment, less than 10 days
ago; it ran tests (RunSpecifiedTests, RunLocalTests or RunAllTestsInOrg; a NoTestRun validation only when the org
is a sandbox, since production quick deploys only validations that ran tests); and the merge is exactly what was
validated (the merge commit's target-side parent is `mergedWith` and its tree is `validatedTree`, so the target
didn't move and the branch didn't change). If Salesforce refuses the quick deploy (expired, or another deploy
since), the step deploys in full and says so in `message` and `quickNote`.

**Release Relay's own metadata.** The hub's own components (`Rly*` Apex classes, `rly*` LWCs, `RLY_*` objects,
tabs, permission sets, custom permissions, static resources, named and external credentials, the `RLY_Slack_Member_Id__c`
User field, the `Release_Relay` app and the `RLY_App_Name` label) must never reach the route's orgs through a normal
release. `.relay/exclude` (repo root, one glob per line relative to `SOURCE_PATH`, `#` comments) lists them;
validate, deploy (full and quick) and sync leave every matching file out of `package.xml` and
`destructiveChangesPost.xml` (and out of the CLI's view, through `.forceignore` for the run), list them as
`excluded` in the result and in the step summary. A labels file is excluded only when every label in it matches
(`only-labels:RLY_*`); a file that also holds your own labels is deployed as usual. The list is read from the
pipeline's own commit (the default branch), like the script; without the file the script uses the same defaults.
A deploy quick deploys a validation only when it used the same setting (a version 10 validation of a change with
excluded files is deployed in full).

**The hub's own updates go to `release-relay-hub`.** Until version 10 the hub's own metadata was deployed through
`prod`, so merging `prod` back (`syncBranches`) copied it into the stage and developer branches. From version 11 the
hub deploys its own updates from a dedicated branch, `release-relay-hub` (not `prod`, and never in `syncBranches`),
with `{"selfUpdate":true}` in the options: those runs ignore the exclude list. Merge-back then never carries new
Release Relay files.

**Existing Release Relay files in `prod`, the stage and developer branches** are not removed by the pipeline:
removing them in a release would become destructive changes. With the exclude list in place they are harmless (never
deployed), and removing them by hand from the stage and developer branches is safe, because excluded paths are
never deleted in the orgs:

```sh
git checkout sit
git rm -r -q force-app/main/default/classes/Rly* force-app/main/default/lwc/rly* \
  force-app/main/default/objects/RLY_* force-app/main/default/objects/User/fields/RLY_* \
  force-app/main/default/tabs/RLY_* force-app/main/default/permissionsets/RLY_* \
  force-app/main/default/customPermissions/RLY_* force-app/main/default/staticresources/RLY_* \
  force-app/main/default/applications/Release_Relay.app-meta.xml \
  force-app/main/default/namedCredentials/RLY_* force-app/main/default/externalCredentials/RLY_*
# and labels/CustomLabels.labels-meta.xml if it holds only RLY_ labels
git commit -m "Remove Release Relay's own files (excluded from deployments)" && git push origin sit
```

Repeat for each developer branch. Remove them from `prod` only after the hub's updates come from
`release-relay-hub`; otherwise the next merge-back from `prod` would bring the deletions to the other branches
(still harmless to the orgs, since they are excluded).

**Promotion from the stage (mode `promote`, `stageBranch`).** `components` lists the releases' merge commits;
`stageBranch` names the previous stage's branch (`sit`). The job lists every file each commit changed against its
first parent, makes `branch` from `target`, and takes each file as it is now in `stageBranch` (a file the stage no
longer has is removed from `target`). Older releases still waiting in the stage and later fixes to the same file
come along, so nothing has to apply as a patch. Before writing, each file `target` has must be a version the stage
has had (its current version, or one in its last 200 commits that changed the file); otherwise `target` holds a
change the stage never got, usually a hotfix not merged back down, and the job stops with `clash` in `raise.json`:
merge `target` into `stageBranch`, then promote again. One commit, `REL-00042: promote 2 release(s) from sit`,
lists the commits. Without `stageBranch` the commits are cherry-picked as before.

**Adding changes to an open release (mode `hub`, `append`).** The hub retrieves the new components, commits the zip
to the release's existing `branch` as `.relay-inbox/<REQUEST_ID>-add-<k>.zip`, and dispatches mode `hub` with
`{"append":true,"appendZip":".relay-inbox/REL-00042-add-1.zip"}` (and the release's `tests`, old and new). The job
converts it exactly like a new hub raise (per-org values become placeholders), removes `deletions` (any already
removed from the branch are skipped), removes the zip, commits `REL-00042: more changes from DEV1`, and pushes. It
opens no pull request: the open one updates. `raise.json` says `Opened` with `appended: true`; scan and validate
run again. A missing branch or zip fails the raise.

**Mode `sync` (back promote).** `branch` = the hub's production branch, `target` = the back-promote org's branch,
`environment` = the production org's environment, `target_environment` = the back-promote org's environment
(its login is used, as for deploy). The job merges `branch` into `target` (no conflict strategy: a conflict stops
it, nothing is pushed), deploys what that changed under `SOURCE_PATH` (test level `DEPLOY_TEST_LEVEL`, else
RunLocalTests when Apex changed and NoTestRun otherwise; the release's `tests` aren't used), and pushes `target`
only when the deploy worked. A missing `target` branch is made from `branch` and nothing is deployed that time:
the org is taken to match production already (a sandbox made from it).

**Per-org values (`.relay/values.json`).** Values that differ per org (endpoints, ids, emails) are kept out of the
branches as placeholders, `{{relay:PAYMENT_URL}}`, with one value per Git environment:

```json
{ "values": { "PAYMENT_URL": { "dev1": "https://dev.pay.example", "sit": "https://sit.pay.example", "prod": "https://pay.example" } } }
```

Names are `A-Z`, `0-9` and `_` (up to 60); environment names are the ones the hub sends (`environment`,
`target_environment`); keys starting with `_` are ignored. Validate, deploy and sync replace each placeholder in the
deployment's text files with the **target** org's value, in a temporary copy of the project (the branch and the
checkout are never changed), and fail when a placeholder has no value for that org ("PAYMENT_URL has no value for
prod in .relay/values.json (used in classes/PayClient.cls)."). A quick deploy sends what its validation filled in,
so the validation fills the target's values; if the values changed since, the deploy runs in full. Modes `org` and
`hub` (org metadata written to a branch) turn the **source** org's values back into placeholders in the retrieved
files, longest value first; values shorter than 6 characters are never turned back (a warning says so), since they
could match unrelated text. Snapshots and rollbacks hold the org's own copies, so nothing is filled in there.

**Quality gates (`.relay/gates.json`).** All optional:

```json
{ "scan": { "failAtPriority": 2 }, "coverage": { "minimumPerClass": 75, "minimumOrgWide": 75 }, "tests": { "requireForApex": true } }
```

`scan.failAtPriority`: the scan fails when a finding has that priority or higher (1 is the highest), on top of
`SCAN_BLOCK_SEVERITY`. `coverage`: after a validation that passed and ran tests, it fails when an Apex class or
trigger the release deploys is below `minimumPerClass` ("PayClient 61% < 75%"); `minimumOrgWide` is checked only
when the validation ran `RunLocalTests` or `RunAllTestsInOrg`, the only runs whose coverage covers the org.
`tests.requireForApex`: a release that deploys or deletes Apex and would run no tests (`tests: []`, or
`NoTestRun`) fails before anything is sent. An unreadable gates file fails the scan and the validation. A
validation that failed a gate is never quick deployed.

**Rollback snapshots and mode `rollback`.** Before every real deploy (deploy, full or quick, and sync) the pipeline
retrieves the target org's current versions of the components it is about to deploy and delete (Metadata API
format) and commits them, with `manifest.json`, to `release-relay-snapshots` at
`<REQUEST_ID>/<environment>/<attempt, or the run id>/`:

```json
{ "request": "REL-00042", "environment": "prod", "takenAt": "2026-11-01T10:00:00.000Z", "sha": "<merge commit>",
  "existing": ["ApexClass:PayClient"], "added": ["ApexClass:PayClientV2"], "deleted": ["ApexClass:OldPay"],
  "unresolved": [] }
```

`existing`: deployed components the org already had; `added`: ones it didn't have ("cannot be found"); `deleted`:
components the release deletes that the org had; `unresolved`: ones the retrieve said nothing about (left alone by
a rollback). Release Relay's own components (and their fields on standard objects) never go into a snapshot.
`{"snapshot":false}` or `selfUpdate` skips it; a failed snapshot is a warning and the deploy goes ahead
(`deploy.json` `snapshot.error`).

Mode `rollback` deploys a snapshot back: start it like a deploy, with `mode` `rollback`, `request_id`,
`target_environment` (the org; its login is used, as for deploy), `environment` (any, the hub sends the same),
`branch` and `target` (not used: send the target org's branch) and `title`, and options `snapshotPath` (blank = the
latest snapshot of that release in that environment) and `tests`. It deploys the snapshot's components as they were
and deletes the `added` ones (`destructiveChangesPost.xml`). Test level: the given tests (`RunSpecifiedTests`);
otherwise `RunLocalTests` when Apex is involved and the org isn't a confirmed sandbox; otherwise `NoTestRun`.
Release branches aren't changed: Git still holds the release, so a follow-up release brings the branches in line.
The exclude list always applies: Release Relay's own components are never rolled back.

**Faster runs.** The jobs cache the Salesforce CLI (major version 2): GitHub per runner OS and month
(`actions/cache`, `~/.relay-sf`; the scan job also caches the Code Analyzer plugin), GitLab in the job cache
(`.relay-sf/`, installed again after 30 days), Bitbucket in the caches `relay-sf` and `relay-sf-plugins` (refreshed
weekly by Bitbucket), Azure with `Cache@2` per agent OS and month. GitHub's deploy job fetches only the merge commit
and its parents, and the rollback and notify jobs only the pipeline's commit; jobs that merge or diff against the
target keep the full history.

## GitLab

**File.** `gitlab/.gitlab-ci.yml` → `.gitlab-ci.yml`. If you already have one, save this file as
`release-relay.gitlab-ci.yml`, add `include: [{ local: release-relay.gitlab-ci.yml }]` to yours, add the stages
`relay-raise`, `relay-check`, `relay-merge`, `relay-deploy` to your `stages:`, and merge its `workflow:` block into
yours (it names the run, which the hub looks for, and stops result pushes from starting pipelines). Your own jobs
also run in the hub's pipelines unless their rules leave them out:
`rules: [ { if: '$REQUEST_ID', when: never }, { when: on_success } ]`.

**Hub Named Credential** (`RLY_GitLab`, URL `https://gitlab.com/api/v4` or your own): a project access token,
role **Maintainer**, scope **`api`**. Maintainer, because the hub starts pipelines on the protected default
branch.

**Settings → CI/CD → Variables → Minimum role to use pipeline variables:** Maintainer or lower. Newer projects
default to "no one", which stops the hub from passing the release.

**Pipeline token.** CI/CD variable `RELAY_TOKEN` (masked, protected, environment scope `*`): a project access
token, role **Maintainer**, scopes **`api`** and **`write_repository`**. GitLab's job token can't push, so the
script pushes and merges with this one. It must be allowed to merge into every stage branch and push to the
developer branches and the back-promote branches. It can be the hub's token if that has both scopes.

**Each org's login**, one of:

- **Environment scope** (matches the GitHub environments): add `SF_USERNAME`, `SF_CLIENT_ID`, `SF_JKS`,
  `SF_JKS_PASSWORD` (masked, protected) and `SF_INSTANCE_URL`, `SF_JKS_ALIAS` once per stage org, with
  **Environment scope** = the org's Git environment (`sit`). The validate, deploy and sync jobs run in the
  target's environment, raise and merge in the source's.
- **Prefixed**: `SIT_SF_USERNAME`, `SIT_SF_CLIENT_ID`, and so on, scope `*`.

The notify job (only when the options carry `notify`) reads prefixed variables only.

**Stages.** Add `relay-sync` (after `relay-deploy`) if you include this file in your own `.gitlab-ci.yml`. The
rollback job runs in `relay-deploy`. Jobs that use the Salesforce CLI share the cache key `relay-sf-cli2-node22`
(`.relay-sf/` in the project folder; add it to your `.gitignore` if you run other jobs that commit).

**Approvals: protected environments** (Premium/Ultimate). Settings → CI/CD → Protected environments → protect
`prod` (and any stage): **Allowed to deploy** must include the `RELAY_TOKEN`/hub token's bot user, since the hub
starts the pipelines; **Approvals** sets who approves and how many. The deploy job records a deployment, so it
waits there until approved; validate uses `action: prepare`, so it isn't held.

**How the hub starts it.** `POST /projects/:id/pipeline` with `{"ref": "<default branch>", "variables": [{"key":
"REQUEST_ID", "value": "REL-00042"}, …]}`: keys `REQUEST_ID`, `MODE`, `ENVIRONMENT`, `TARGET_ENVIRONMENT`, `BRANCH`,
`TARGET`, `TITLE`, `COMPONENTS`, `DELETIONS`, `OPTIONS` (upper case). The run is named
`Release Relay REL-00042 (hub)` (`GET /projects/:id/pipelines?name=…`, or keep the `id` from the create call).
A rollback is `MODE` `rollback` with `TARGET_ENVIRONMENT` and `OPTIONS` (`{"snapshotPath": …, "tests": […]}`).

## Bitbucket

**File.** `bitbucket/bitbucket-pipelines.yml` → `bitbucket-pipelines.yml`. If you already have one, copy the
`release-relay` entry under `pipelines: custom:` into it, add the `relay-sf` and `relay-sf-plugins` caches under
`definitions: caches:`, and set `clone: depth: full`. Bitbucket can't skip a step
by variable, so every step starts and a step the mode doesn't need ends at once (a few seconds of build minutes).
Scan and validate run in parallel, like GitHub's jobs.

**Hub Named Credential** (`RLY_Bitbucket`, URL `https://api.bitbucket.org/2.0`): a repository access token with
**Repositories: Write**, **Pull requests: Write** and **Pipelines: Write** (Write includes Read).

**Pipeline token.** Repository variable `RELAY_TOKEN` (Secured): a repository access token with
**Repositories: Write** and **Pull requests: Write**. The script opens and merges pull requests with it; git
pushes use the pipeline's own access. Branch restrictions must let pipelines push to the developer branches, the
back-promote branches, the results branch and the snapshots branch, and merge into the stage branches. The step
"Back promote to the target org" runs only in mode `sync` and reads the back-promote org's prefixed login; the last
step, "Roll back the target org", runs only in mode `rollback` and reads the target org's prefixed login.

**Each org's login: prefixed repository variables** (Repository settings → Pipelines → Repository variables).
Secured: `SIT_SF_USERNAME`, `SIT_SF_CLIENT_ID`, `SIT_SF_JKS`, `SIT_SF_JKS_PASSWORD`; plain: `SIT_SF_INSTANCE_URL`,
`SIT_SF_JKS_ALIAS`. Deployment variables don't fit here: a step's `deployment:` must be a fixed name, and each
deployment environment can appear only once in a pipeline.

**Approvals: deployment permissions** (Premium). Add a second custom pipeline per protected target, used for
mode `merge` into that target, with the deployment on its deploy step:

```yaml
    release-relay-prod:
      - variables: [ ... the same list as release-relay ... ]
      - step: { ... the "Merge the approved pull request" step ... }
      - step:
          name: Deploy to prod
          deployment: prod        # Repository settings > Deployments > prod
          trigger: manual         # optional: someone presses Run
          max-time: 120
          script: [ ... the deploy step's script ... ]
```

Then Repository settings → Deployments → `prod`: **Only allow admins to deploy** and/or **Only allow deployments
from** the default branch; deployment variables may then hold that org's unprefixed `SF_*`. The hub has to start
`release-relay-<target_environment>` for merges when that pipeline exists (not built yet; see the gaps).

**How the hub starts it.** `POST /repositories/{workspace}/{repo}/pipelines/` with
`{"target": {"type": "pipeline_ref_target", "ref_type": "branch", "ref_name": "<default branch>", "selector":
{"type": "custom", "pattern": "release-relay"}}, "variables": [{"key": "REQUEST_ID", "value": "REL-00042"}, …]}`,
the same upper-case keys as GitLab, `-` for empty values. Bitbucket runs have no name: keep the `uuid` the call
returns to find the run.

## Azure DevOps

**File.** `azure/azure-pipelines.yml` → `azure-pipelines.yml` (any path). Pipelines → New pipeline → Azure Repos
Git → Existing Azure Pipelines YAML file; its id goes in the hub's Pipeline field.

**Hub Named Credential** (`RLY_AzureDevOps`, URL `https://dev.azure.com`): a personal access token with
**Code: Read & write** and **Build: Read & execute**.

**Pipeline identity.** The jobs use `System.AccessToken`. Project Settings → Repositories → the repository →
Security → **`<project> Build Service (<organization>)`** (or **Project Collection Build Service** when "Limit job
authorization scope" is off): **Contribute**, **Create branch**, **Contribute to pull requests** = Allow. Add
**Bypass policies when completing pull requests** if stage branches have policies (required reviewers, build
validation) that would stop the merge, since approval happens in Salesforce; **Bypass policies when pushing** if
developer branches have policies.

**Each org's login: a variable group per org**, Pipelines → Library, named **`release-relay-<environment>`**
(`release-relay-sit`). Secret: `SF_USERNAME`, `SF_CLIENT_ID`, `SF_JKS`, `SF_JKS_PASSWORD`; plain:
`SF_INSTANCE_URL`, `SF_JKS_ALIAS`. Optional settings go in the same group or as pipeline variables. Under the
group's **Pipeline permissions**, allow this pipeline; otherwise the first run waits for someone to press Permit.
Runs started by the hub (`"hub":true`) use only the target's group. Mode `sync` is a deployment job in the
back-promote org's environment with its group `release-relay-<target_environment>`, like deploy, and so is mode
`rollback` (the environment's approvals and checks hold a rollback too).

**Approvals: environments with approvals and checks.** The deploy job is a deployment job in the Azure DevOps
environment named as the target (`sit`, `prod`; created on first use). Pipelines → Environments → `prod` →
**Approvals and checks**: Approvals, Branch control (`refs/heads/main`), Business hours, Exclusive lock (one deploy
at a time); allow the pipeline under its Security/Pipeline permissions. Deploy is its own stage, so the checks
hold only the deploy. Checks on a variable group would also hold validation.

**How the hub starts it.** `POST {organization}/{project}/_apis/pipelines/{id}/runs?api-version=7.1` with
`{"resources": {"repositories": {"self": {"refName": "refs/heads/<default branch>"}}}, "templateParameters":
{"request_id": "REL-00042", "mode": "hub", …}}`: the same lower-case keys as GitHub's inputs, `-` for every empty
value (an empty string isn't accepted). The run's `name` is `Release Relay REL-00042 (hub)`.

## Differences from GitHub

- **One run at a time per branch.** GitHub's `concurrency` group has no equivalent here; the hub starts one run
  per release at a time. On Azure, an Exclusive lock check on the environment serializes deploys.
- **Notify** (`{"notify": "<env>"}` in the options) works on GitLab and Bitbucket with prefixed variables; on Azure
  only when `notify` is the source environment (variable groups are chosen when the run starts). On Bitbucket it
  runs after the validate step (it can be ahead of the parallel scan) or after the deploy step, so a failed merge
  sends none. The hub's scheduled sync reads the results either way.
- **Result pushes** start your other pipelines on Bitbucket and Azure (GitLab's `workflow:` rule stops them):
  leave `release-relay-results` out of your own pipelines' triggers.
- **Job images.** GitLab and Bitbucket use `node:22` (git, unzip, openssl included) and install Java 17 for the
  scan and for `SF_JKS` logins.
