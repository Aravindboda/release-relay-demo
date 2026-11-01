# Release Relay pipeline files: version 11
# Release Relay's own metadata (the globs in .relay/exclude) is never validated, deployed or deleted;
# options {"selfUpdate":true} (the hub updating itself, from the release-relay-hub branch) ignores the list.
# Release Relay for GitLab CI/CD. Started only from Salesforce (the Release Relay hub creates a
# pipeline on the default branch through the API, with the release in pipeline variables).
#   MODE=org     retrieve the selected components from the source org, apply deletions, commit to a
#                new branch, open a merge request into the target branch, then scan and validate it.
#   MODE=branch  open a merge request from a branch that already exists, then scan and validate it.
#   MODE=promote make a promote/ branch from the target, cherry-pick the merge commits listed in
#                COMPONENTS (from the previous stage), open a merge request, then scan and validate it.
#   MODE=hub     the hub committed its retrieve (a Metadata API zip) to the branch: convert it to
#                source format (none for a release with only deletions,
#                a .relay-inbox/<id>.deletions marker instead), remove the deleted components' files,
#                open a merge request into the target, scan and validate.
#   MODE=resolve merge the target into the branch with the conflict choices the hub committed, then
#                scan and validate again.
#   MODE=check   scan and validate an open merge request again.
#   MODE=merge   merge the merge request approved in Salesforce, then deploy it to the target org.
#   MODE=sync    back promote: merge BRANCH (the hub's production branch) into TARGET (a back-promote
#                org's branch, made from BRANCH when missing), deploy what changed to the org in
#                TARGET_ENVIRONMENT, and push TARGET only when that deploy worked.
# Validation and deployment run only when TARGET_ENVIRONMENT is set. Each step writes its result as
# JSON to the release-relay-results branch, where Salesforce reads it.
#
# Pipeline variables from the hub: REQUEST_ID, MODE, ENVIRONMENT, TARGET_ENVIRONMENT, BRANCH, TARGET,
# TITLE, COMPONENTS, DELETIONS, OPTIONS (JSON, for example {"hub":true,"tests":[],"scan":"off"}).
# Project CI/CD variables: see pipelines/README.md (RELAY_TOKEN, and each org's SF_* login either
# scoped to its environment or prefixed with it: SIT_SF_USERNAME).
#
# If you already have a .gitlab-ci.yml, save this file as release-relay.gitlab-ci.yml, add
# "include: [{ local: release-relay.gitlab-ci.yml }]" to yours, and add the five relay-* stages to
# your stages: list. Your own jobs also run in the hub's pipelines unless their rules leave them out:
#   rules: [ { if: '$REQUEST_ID', when: never }, { when: on_success } ]

workflow:
  name: '$RELAY_RUN_NAME'
  rules:
    # Result pushes never start pipelines.
    - if: '$CI_COMMIT_BRANCH == "release-relay-results"'
      when: never
    # The hub finds its run by this name: "Release Relay REL-00042 (hub)".
    - if: '$REQUEST_ID && $MODE'
      variables:
        RELAY_RUN_NAME: 'Release Relay $REQUEST_ID ($MODE)'
    - when: always

stages:
  - relay-raise
  - relay-check
  - relay-merge
  - relay-deploy
  - relay-sync

.release-relay:
  image: node:22
  variables:
    RELAY_PROVIDER: gitlab
    GIT_DEPTH: "0"
  # The release branch may hold an older copy of the script: always run the pipeline's own
  # (the default branch's commit this pipeline runs on).
  before_script:
    - git show "$CI_COMMIT_SHA:scripts/release-relay.js" > /tmp/release-relay.js
    # keytool turns an SF_JKS keystore into the key; only needed when a keystore is set.
    - |
      if env | grep -Eq '^([A-Z0-9_]+_)?SF_JKS=.'; then
        apt-get update -qq && apt-get install -y -qq openjdk-17-jre-headless > /dev/null
      fi

release-relay-raise:
  extends: .release-relay
  stage: relay-raise
  timeout: 30m
  environment:
    name: $ENVIRONMENT
    action: prepare
  rules:
    - if: '$CI_PIPELINE_SOURCE =~ /^(api|trigger|web)$/ && $REQUEST_ID && $MODE =~ /^(org|branch|promote|hub|resolve)$/'
  script:
    - |
      if [ "$MODE" = hub ] || { [ "$MODE" = org ] && [ -n "$COMPONENTS" ] && [ "$COMPONENTS" != "-" ]; }; then
        npm install --global @salesforce/cli@2 --silent
      fi
    - STEP=raise node /tmp/release-relay.js

release-relay-scan:
  extends: .release-relay
  stage: relay-check
  timeout: 30m
  needs:
    - job: release-relay-raise
      optional: true
  rules:
    - if: '$CI_PIPELINE_SOURCE =~ /^(api|trigger|web)$/ && $REQUEST_ID && $MODE =~ /^(org|branch|promote|hub|resolve|check)$/ && $OPTIONS !~ /"scan"\s*:\s*"off"/'
  script:
    - apt-get update -qq && apt-get install -y -qq openjdk-17-jre-headless > /dev/null
    - npm install --global @salesforce/cli@2 --silent
    - sf plugins install code-analyzer
    - STEP=scan node /tmp/release-relay.js

release-relay-validate:
  extends: .release-relay
  stage: relay-check
  timeout: 2h
  needs:
    - job: release-relay-raise
      optional: true
  # prepare: uses the environment's variables and protection without recording a deployment,
  # so deployment approvals gate the deploy job only.
  environment:
    name: $TARGET_ENVIRONMENT
    action: prepare
  rules:
    - if: '$CI_PIPELINE_SOURCE =~ /^(api|trigger|web)$/ && $REQUEST_ID && $MODE =~ /^(org|branch|promote|hub|resolve|check)$/ && $TARGET_ENVIRONMENT && $TARGET_ENVIRONMENT != "-"'
  script:
    - npm install --global @salesforce/cli@2 --silent
    - STEP=validate node /tmp/release-relay.js

release-relay-merge:
  extends: .release-relay
  stage: relay-merge
  timeout: 15m
  environment:
    name: $ENVIRONMENT
    action: prepare
  rules:
    - if: '$CI_PIPELINE_SOURCE =~ /^(api|trigger|web)$/ && $REQUEST_ID && $MODE == "merge"'
  script:
    - STEP=merge node /tmp/release-relay.js
    # Hands the merge commit to the deploy job.
    - echo "MERGE_SHA=$(cat .relay-merge-sha)" > relay-merge.env
  artifacts:
    reports:
      dotenv: relay-merge.env

release-relay-deploy:
  extends: .release-relay
  stage: relay-deploy
  timeout: 2h
  needs:
    - job: release-relay-merge
      artifacts: true
  # A real deployment: protected environments and deployment approvals apply here.
  environment:
    name: $TARGET_ENVIRONMENT
  rules:
    - if: '$CI_PIPELINE_SOURCE =~ /^(api|trigger|web)$/ && $REQUEST_ID && $MODE == "merge" && $TARGET_ENVIRONMENT && $TARGET_ENVIRONMENT != "-"'
  script:
    - npm install --global @salesforce/cli@2 --silent
    - STEP=deploy node /tmp/release-relay.js

# Back promote: production's changes into a back-promote org. A real deployment to the target org's
# environment, like the deploy job, so its login, protection and approvals apply.
release-relay-sync:
  extends: .release-relay
  stage: relay-sync
  timeout: 2h
  needs: []
  environment:
    name: $TARGET_ENVIRONMENT
  rules:
    - if: '$CI_PIPELINE_SOURCE =~ /^(api|trigger|web)$/ && $REQUEST_ID && $MODE == "sync" && $TARGET_ENVIRONMENT && $TARGET_ENVIRONMENT != "-"'
  script:
    - npm install --global @salesforce/cli@2 --silent
    - STEP=sync node /tmp/release-relay.js

# Tells the Salesforce org named in OPTIONS.notify to read the results now. Its login is read as
# <NOTIFY>_SF_USERNAME etc. (prefixed variables). A failure here never fails the pipeline.
release-relay-notify:
  extends: .release-relay
  stage: .post
  timeout: 10m
  allow_failure: true
  rules:
    - if: '$CI_PIPELINE_SOURCE =~ /^(api|trigger|web)$/ && $REQUEST_ID && $OPTIONS =~ /"notify"\s*:\s*"[^"]+"/'
      when: always
  script:
    - npm install --global @salesforce/cli@2 --silent
    - |
      node -e '
        let o = {};
        try { o = JSON.parse(process.env.OPTIONS || "{}"); } catch (e) { o = {}; }
        const p = String(o.notify || "").toUpperCase().replace(/[^A-Z0-9]+/g, "_") + "_";
        const e = { ...process.env, STEP: "notify" };
        for (const k of ["SF_USERNAME", "SF_CLIENT_ID", "SF_INSTANCE_URL", "SF_JWT_KEY", "SF_JKS", "SF_JKS_PASSWORD", "SF_JKS_ALIAS"]) {
          if (e[p + k]) { e[k] = e[p + k]; }
        }
        require("child_process").execFileSync("node", ["/tmp/release-relay.js"], { stdio: "inherit", env: e });
      '
