# release-relay-demo
Release Relay demo – Salesforce DEV to SIT releases via GitHub Actions

## Release Relay's own metadata

Release Relay's own components (`Rly*` classes, `rly*` LWCs, `RLY_*` objects and the rest listed in
`.relay/exclude`) are never deployed or deleted by the pipeline's validate, deploy or sync steps; the results list
them as `excluded`. The hub's own updates go to the `release-relay-hub` branch with `{"selfUpdate":true}`, which
ignores the list. The copies already in `prod`, `sit` and the developer branches stay until removed by hand;
removing them from `sit` and the developer branches is safe, because excluded paths are never deleted in the orgs.
See `pipelines/README.md`, "Release Relay's own metadata".

## Pipeline version 14: promotion from the stage, adding to an open release

- **Promotion from the stage** (`options.stageBranch`): a promotion takes each file its releases changed as it is in
  the previous stage's branch, so older stage releases and fixes to the same file come along without conflicts. A
  hotfix in the target that the stage doesn't have stops it (`raise.json` `clash`): merge the target into the stage.
- **Adding to an open release** (mode `hub`, `options.append`, `options.appendZip`): more changes from the developer
  org go onto the release's branch; the open pull request updates and the checks run again.

## Pipeline version 13: per-org values, quality gates, rollback

- **Per-org values** (`.relay/values.json`): branches hold `{{relay:NAME}}` placeholders; validate, deploy and sync
  fill in the target org's value in a temporary copy (never committed) and fail when a value is missing; raises that
  write org metadata into a branch turn the source org's values back into placeholders.
- **Quality gates** (`.relay/gates.json`): fail the scan at a finding priority, fail a validation below a per-class
  (and org-wide) Apex coverage, require tests when a release has Apex. Results record `gates`.
- **Rollback**: before every deploy the org's current versions are saved to the `release-relay-snapshots` branch;
  `mode=rollback` deploys a snapshot back into the org without changing Git.
- **Faster runs**: the Salesforce CLI is cached, and the deploy job fetches only the commits it needs.

Both `.relay` files are read from the pipeline's own commit (the default branch). See `pipelines/README.md`.
