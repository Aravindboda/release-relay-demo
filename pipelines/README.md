<!-- Release Relay pipeline files: version 9 -->
# Release Relay pipelines for GitLab, Bitbucket and Azure DevOps

These files do what `.github/workflows/release-relay.yml` does on GitHub, with the same modes
(`org`, `branch`, `promote`, `hub`, `resolve`, `check`, `merge`, `sync`), the same jobs (raise, scan, validate,
merge, deploy, sync, notify) and the same script, `scripts/release-relay.js`. Every job runs the default
branch's copy of the script (`git show <pipeline commit>:scripts/release-relay.js`), never the copy on
the release branch.

| Provider | File here | Put it in the owner's repository at | Hub Git connection, Pipeline field |
|---|---|---|---|
| GitHub | (`.github/workflows/release-relay.yml`) | `.github/workflows/release-relay.yml` | `release-relay.yml` |
| GitLab | `gitlab/.gitlab-ci.yml` | `.gitlab-ci.yml` at the root of the default branch | `.gitlab-ci.yml` (blank means the same) |
| Bitbucket | `bitbucket/bitbucket-pipelines.yml` | `bitbucket-pipelines.yml` at the root of the default branch | (not used: the custom pipeline is `release-relay`) |
| Azure DevOps | `azure/azure-pipelines.yml` | `azure-pipelines.yml` at the root of the default branch (any path works) | the pipeline id (`definitionId=` in its address) |

Every provider also needs `scripts/release-relay.js` on the default branch.

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
branches it updates after a merge (`syncBranches`), the back-promote orgs' branches (mode `sync`), and
`release-relay-results`. `release-relay-results` must not be protected.

## What the hub sends and reads

**Options** (`OPTIONS`, JSON): `hub` (true: the hub checked the route, so `ALLOWED_TARGETS` isn't needed),
`label`, `tests` (the release's test classes; `[]` = NoTestRun), `scan` (`off`), `validateMerged` (validate the
branch merged with the target), `attempt` (the run's token, echoed in every result file), `notify`, and for
`merge`: `syncBranches` (the branches to bring the target into after the merge, in order; after a deploy to
production every stage branch, then every developer branch) and `stageWins` (true: the first listed branch takes
the target's lines where they conflict; otherwise a conflict is reported for that branch, never forced).

**Result files** on `release-relay-results`, `results/<REQUEST_ID>/<step>.json`, each with `request`, `step`,
`status`, `runUrl`, `finishedAt` and `attempt`:

- `raise.json` (modes `hub` and `promote` started by the hub): `status` `Opened` or `Failed`, `mode`, `branch`,
  `target`, `sha` (the branch head pushed), `pr` (number), `url`, `commits` (promote: the merge commits picked),
  `conflicts` (promote: files a commit conflicted on), `message`.
- `scan.json`, `validate.json`, `deploy.json`: as before.
- `merge.json`: `status` `Merged` or `Failed`, `pr`, `sha`, `method`, and `sync`: one entry per `syncBranches`
  branch, `{ "branch", "status": "Synced" | "Conflict" | "Missing", "message" }`.
- `sync.json` (mode `sync`): `status` `Deployed`, `Nothing to deploy`, `Conflict` or `Failed`, `sha` (the
  back-promote branch's new head; for a conflict the production head that couldn't be merged), `deployId`,
  `testsRun`, `conflicts` (files), `message`.

**Mode `sync` (back promote).** `branch` = the hub's production branch, `target` = the back-promote org's branch,
`environment` = the production org's environment, `target_environment` = the back-promote org's environment
(its login is used, as for deploy). The job merges `branch` into `target` (no conflict strategy: a conflict stops
it, nothing is pushed), deploys what that changed under `SOURCE_PATH` (test level `DEPLOY_TEST_LEVEL`, else
RunLocalTests when Apex changed and NoTestRun otherwise; the release's `tests` aren't used), and pushes `target`
only when the deploy worked. A missing `target` branch is made from `branch` and nothing is deployed that time:
the org is taken to match production already (a sandbox made from it).

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

**Stages.** Add `relay-sync` (after `relay-deploy`) if you include this file in your own `.gitlab-ci.yml`.

**Approvals: protected environments** (Premium/Ultimate). Settings → CI/CD → Protected environments → protect
`prod` (and any stage): **Allowed to deploy** must include the `RELAY_TOKEN`/hub token's bot user, since the hub
starts the pipelines; **Approvals** sets who approves and how many. The deploy job records a deployment, so it
waits there until approved; validate uses `action: prepare`, so it isn't held.

**How the hub starts it.** `POST /projects/:id/pipeline` with `{"ref": "<default branch>", "variables": [{"key":
"REQUEST_ID", "value": "REL-00042"}, …]}`: keys `REQUEST_ID`, `MODE`, `ENVIRONMENT`, `TARGET_ENVIRONMENT`, `BRANCH`,
`TARGET`, `TITLE`, `COMPONENTS`, `DELETIONS`, `OPTIONS` (upper case). The run is named
`Release Relay REL-00042 (hub)` (`GET /projects/:id/pipelines?name=…`, or keep the `id` from the create call).

## Bitbucket

**File.** `bitbucket/bitbucket-pipelines.yml` → `bitbucket-pipelines.yml`. If you already have one, copy the
`release-relay` entry under `pipelines: custom:` into it and set `clone: depth: full`. Bitbucket can't skip a step
by variable, so every step starts and a step the mode doesn't need ends at once (a few seconds of build minutes).
Scan and validate run in parallel, like GitHub's jobs.

**Hub Named Credential** (`RLY_Bitbucket`, URL `https://api.bitbucket.org/2.0`): a repository access token with
**Repositories: Write**, **Pull requests: Write** and **Pipelines: Write** (Write includes Read).

**Pipeline token.** Repository variable `RELAY_TOKEN` (Secured): a repository access token with
**Repositories: Write** and **Pull requests: Write**. The script opens and merges pull requests with it; git
pushes use the pipeline's own access. Branch restrictions must let pipelines push to the developer branches, the
back-promote branches and the results branch, and merge into the stage branches. The last step, "Back promote to
the target org", runs only in mode `sync` and reads the back-promote org's prefixed login.

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
back-promote org's environment with its group `release-relay-<target_environment>`, like deploy.

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
