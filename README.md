# release-relay-demo
Release Relay demo – Salesforce DEV to SIT releases via GitHub Actions

## Release Relay's own metadata

Release Relay's own components (`Rly*` classes, `rly*` LWCs, `RLY_*` objects and the rest listed in
`.relay/exclude`) are never deployed or deleted by the pipeline's validate, deploy or sync steps; the results list
them as `excluded`. The hub's own updates go to the `release-relay-hub` branch with `{"selfUpdate":true}`, which
ignores the list. The copies already in `prod`, `sit` and the developer branches stay until removed by hand;
removing them from `sit` and the developer branches is safe, because excluded paths are never deleted in the orgs.
See `pipelines/README.md`, "Release Relay's own metadata".
