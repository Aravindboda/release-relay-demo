# Build 9 contract: pipeline files (download + update from the hub) + Slack toggle visibility

Package: /home/claude/hub6 (mdapi). Same code rules as /tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/build7-contract.md
(PMD zero incl. Low: bash /tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/pmdscan.sh /home/claude/hub6/classes;
with sharing + inner without sharing; no async; System.runAs in tests; ≥75% each class (aim 90); ApexDoc; no reserved words —
NOTE Apex is case-insensitive, so a local/param must not share a name with a constant (e.g. `secret` vs `SECRET`); `by` is reserved;
no protected static methods; generic names (no demo org names, never "vendor"); provider-neutral).

## Packaged files (already created, plain-text static resources, all stamped with a line containing
## "Release Relay pipeline files: version 8")
- RLY_Pipeline_GitHub  → repo path `.github/workflows/<Git connection Pipeline__c, default release-relay.yml>`  (provider GitHub)
- RLY_Pipeline_GitLab  → `.gitlab-ci.yml` (GitLab)
- RLY_Pipeline_Bitbucket → `bitbucket-pipelines.yml` (Bitbucket)
- RLY_Pipeline_Azure   → `azure-pipelines.yml` (AzureDevOps)
- RLY_Pipeline_Script  → `scripts/release-relay.js` (every provider)
The version is read from the text with the pattern `Release Relay pipeline files: version (\d+)`.

## Apex (backend agent): new class RlyPipelineFiles + controller methods on RlyRouteController (admin only for update)
@AuraEnabled(cacheable=false) public static RlyPipelineFiles.Status getPipelineFiles()
  Status { Integer packagedVersion; Integer repoVersion /* null when not found */; String provider; String branch /* Pipeline_Branch__c */;
           Boolean isAdmin; Boolean upToDate; List<FileInfo> files; String message; }
  FileInfo { String name /* e.g. release-relay.yml */; String repoPath; String provider /* GitHub|GitLab|Bitbucket|AzureDevOps|All */;
             String resourceName /* static resource API name */; Boolean forThisHub /* provider matches the hub's connection or All */;
             Integer repoVersion /* that file's version in the repo, or null */; }
  repoVersion = lowest version found among this hub's files in the repo (read with RlyGit.getFileRaw on the pipeline branch); files missing → null.
@AuraEnabled public static RlyPipelineFiles.UpdateResult updatePipelineFiles(String how /* 'pullRequest' (default) | 'commit' */)
  Admin only. Writes this hub's provider file + the script to the repo with RlyGit.putFile:
  - pullRequest: new branch `release-relay/pipeline-files-v<N>` from the pipeline branch (create it with the existing branch-creation
    method on RlyGit; if it exists, reuse it), commit the files there, then open a pull request into the pipeline branch titled
    "Release Relay pipeline files v<N>" (add RlyGit `openPullRequest(String head, String base, String title, String body)` returning the
    PR URL; implement for GitHub; other providers throw the existing "not available for this provider yet" GitException — keep it
    declared on RlyGit like the other release calls).
  - commit: commit straight to the pipeline branch.
  UpdateResult { Boolean ok; String url /* PR or commit URL */; String message; }
  Errors in words (e.g. GitHub 403 on .github/workflows → "The token needs Workflows: Read and write to change files in .github/workflows.").
Read static resources with [SELECT Name, Body FROM StaticResource WHERE Name IN :names] (system mode inner class).
Tests with RlyHttpMock: up to date, older in repo, missing in repo, update via PR, update via commit, 403 on workflows, non-admin refused.
Also: RlyOrgController.PipelineOrgs.slackAvailable must be true only when Slack is on AND connected (RlySlackController/RlySlack auth.test
result recorded); simplest: Slack on AND the last Slack test/auth result was OK — store nothing new if a cheap existing signal exists;
otherwise slackAvailable = RlySlack.isOn() && RlySlackApi has a working token (one auth.test callout is acceptable in getOrgs).

## UI (UI agent)
- Guide (rlyReleaseGuide) → "Repository files" section: a "Download" list: each file (name, repo path, what it's for, version),
  this hub's provider first, "Show other providers" for the rest; download link = '/resource/' + resourceName? NO — use
  @salesforce/resourceUrl imports for the five resources and an <a href={url} download={fileName}> link (SLDS button style).
  Admins also see the status line + Update button (same as Pipeline tab below) or a link to the Pipeline tab.
- Pipeline (rlyPipeline) → Git connection card: a line "Pipeline files: version {repoVersion} in your repository · version {packagedVersion} available"
  (or "up to date (version N)", or "not found in your repository"), and for admins an "Update pipeline files" button opening a small
  SLDS modal: choose "Open a pull request (recommended)" or "Commit directly to {branch}", list of files that will change, Update button;
  result shows a link to the PR/commit. Calls getPipelineFiles / updatePipelineFiles on RlyRouteController.
- Pipeline org cards: show the "Approve in Slack" toggle only when slackAvailable is true (already wired to slackAvailable — just make sure).
- Canvas: add a board /tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/canvas/project/HubPipelineFiles.dc.html
  (same HTML board format as the others there, e.g. copy the <head>/<helmet>/script structure of HubSlackConnection.dc.html) showing the
  Guide download list and the Pipeline "Pipeline files" line + update modal; add it to canvas.json boards/order at x 1360, y 8660,
  w 1280, h 900, title "Pipeline files: download in the Guide, update from the Pipeline tab".
