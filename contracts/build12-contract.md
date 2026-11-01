# Release Relay build 12: hotfix from a developer org, Promote SIT → PROD, back-merge, optional back promote

Working package (mdapi format): /home/claude/hub6 (classes/, lwc/, objects/, permissionsets/, tabs/, applications/, staticresources/, package.xml).
Repo with the pipeline script: /home/claude/release-relay-demo (branch main; scripts/release-relay.js, .github/workflows/release-relay.yml, pipelines/*).
Deployed source of truth for fields not in hub6/objects: `git -C /home/claude/release-relay-demo show origin/prod:force-app/...` (run `git -C /home/claude/release-relay-demo fetch -q origin "+refs/heads/prod:refs/remotes/origin/prod"` first). The SOQL in classes/RlyReleaseStore.cls lists the RLY_Release__c fields that exist today.

Design boards to match 1:1 (look, layout, wording, SLDS / lightning base components):
/tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/canvas/project/
  HubHotfixBackPromote.dc.html  (THE board for this build: hotfix flag, approvals first, promote alone, merged back, back promote)
  HubPromoteProd.dc.html        (older Promote SIT → PROD board: pick releases, bundle, tests carried. Use its layout for the Promote tab; the new board wins where they differ)
  HubSourceEnvironments.dc.html (New Release steps 1–2, already built: don't change its look)

ALL rules from /tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/build7-contract.md ("Rules for all code" + CHANGE 1) still apply:
PMD 0 findings incl. Low (bash /tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/pmdscan.sh /home/claude/hub6/classes → TOTAL 0), no async Apex, callouts before DML, with sharing + private inner without sharing, System.runAs in every test, ≥75% (aim 90%) per class, ApexDoc, ≤3 params, no Boolean params, no reserved words as identifiers (by, on, when, first, after, all, merge, json, url, hint, list…), no case-insensitive name clashes between constants/params/locals (Apex is case-insensitive), no "New"/"Hub" in class/component names, never the word "vendor", no demo org names hard-coded (SIT/PROD/DEV1/TRAINING only in tests and boards), product name via System.Label.RLY_App_Name.
LWC checks: python3 /tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/lwccheck/check.py /home/claude/hub6/lwc/<bundle> and bash /tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/lwccheck/lint.sh /home/claude/hub6/lwc must pass (no setTimeout, no eslint-disable).
Every new class needs its -meta.xml (API 63.0) and a package.xml entry. Nothing is compiled locally: there is no Salesforce CLI here. The lead deploys through GitHub after you finish.

## Definitions (decided with the user)
- HOTFIX = a release raised from a DEVELOPER org (any sandbox type), flagged urgent with a required reason. It goes DEV → first stage (SIT) with the usual scan, check-only deploy, tests, approval. Then it is promoted to PROD on its own (or bundled), approved again, deployed, and merged back down: prod → every stage branch → every developer branch.
- The old "hotfix from a stage org (SIT → PROD)" is RETIRED: stage orgs are no longer offered as sources; raising from a Stage-role org is refused with "Hotfixes are raised from a developer org now. Pick the developer org that has the fix."
- Who may flag a hotfix: custom permission RLY_Hotfix (exists). Approval can never be skipped.
- Two-approver rule (optional, per target org): RLY_Org__c.Hotfix_Two_Approvers__c. When on and the release is a hotfix going into that org: needs 2 different approvers, neither may be the user who raised it. The first approval keeps the release waiting with phase/notice "Approved by <name>. Waiting for a second approver."
- PROMOTE = a release record of Release_Type__c 'Promotion' from a stage org to its next stop, carrying the merge commits of releases already deployed to that stage. Hotfixes are listed first and can be promoted alone.
- BACK-MERGE after a deploy to the hub (PROD): syncBranches = every stage branch in route order (excluding the hub), then every developer branch. Conflicts are reported per branch on the release page ("1 to review"), never forced.
- BACK PROMOTE = optional, OFF by default (RLY_Git_Connection__c.Back_Promote__c). Orgs with Role__c 'Back_Promote' receive PROD's changes: metadata only, never send anything up. Each such org: Back_Promote_When__c 'After_Deploy' (after every PROD deploy) or 'Manual' (admin clicks Sync now, default), Back_Promote_Approval__c (approve before syncing, default off). A sync is a release record of Release_Type__c 'Back_Promote' (source = hub org, target = that org) run with pipeline mode 'sync'.

## Data model (backend owns objects/, permissionsets/, package.xml)
RLY_Release__c (add as CustomField entries in package.xml, like the existing RLY_Release__c.* members; create objects/RLY_Release__c.object entries the same way the existing ones are):
  Release_Type__c   Picklist restricted: Release (default) | Promotion | Back_Promote (labels: Release, Promotion, Back promote)
  Is_Hotfix__c      Checkbox default false
  Hotfix_Reason__c  TextArea (255)
  Promoted_In__c    Lookup(RLY_Release__c) SetNull, relationship name Promoted_Releases_In  (set on each carried release; cleared if the promotion is Rejected, Failed or Closed)
  Carried_Releases__c LongTextArea(32768), 3 visible lines: comma-separated Ids of the releases a promotion carries, oldest deploy first
  Second_Approved_By__c Lookup(User) SetNull, relationship RLY_Second_Approvals
  Second_Approved_On__c DateTime
  Back_Merge_Result__c LongTextArea(32768): JSON array [{branch,status:'Synced'|'Conflict'|'Missing',message}] from the merge/deploy result's sync list
RLY_Org__c (in objects/RLY_Org__c.object):
  Role__c: add value Back_Promote, label "Back promote (after production)"
  Hotfix_Two_Approvers__c  Checkbox default false
  Back_Promote_When__c     Picklist restricted: Manual (default, label "When an admin clicks Sync now") | After_Deploy (label "After every PROD deploy")
  Back_Promote_Approval__c Checkbox default false
  Synced_On__c             DateTime  (last successful back promote)
  Sync_Status__c           Text(40)  (Deployed | Failed | Conflict | Running)
RLY_Git_Connection__c:
  Back_Promote__c Checkbox default false
FLS: RLY_Admin edit on all new fields; RLY_Approver and RLY_Developer read on the RLY_Release__c ones (match how existing release fields are granted). Tab RLY_Promote visible in RLY_Admin and RLY_Approver (the UI agent creates the tab file; backend adds tab settings + package.xml CustomTab member RLY_Promote + LightningComponentBundle member rlyPromote).

## Apex API the UI calls (backend implements exactly)
RlyReleaseStart.Start: keep fields; stageSources stays but is always EMPTY now (hotfix from stage retired). canHotfix = RlyHotfix.allowed() (now means: may flag a hotfix).
RlyRaiseService.RaiseRequest: ADD  public Boolean isHotfix; public String hotfixReason;  (JSON from rlyReleaseBuilder via RlyReleasesController.raiseRelease(requestJson)). Rules: isHotfix needs RLY_Hotfix ("Only users with the Hotfix permission can raise a hotfix.") and a non-blank reason ("Say why this is a hotfix."), reason trimmed, max 255. Branch prefix for hotfix releases: 'hotfix/rel-xxxxx' (pipeline BRANCH_RE already allows hotfix/); others keep 'feature/'.
RlyHotfix.isHotfix(rel) → rel.Is_Hotfix__c == true.
RlyReleasesController.Row (list rows, used by rlyApprovalQueue and rlyReleaseTracker): ADD Boolean isHotfix; String hotfixReason; String releaseType. listReleases('approvals') returns hotfixes first, then oldest first.
RlyReleasesController.Detail: ADD Boolean isHotfix; String hotfixReason; String releaseType; List<CarriedRelease> carried /*{Id id; String name; String title; Boolean isHotfix}*/; String promotedInName; Id promotedInId; List<BranchSync> backMerge /*{String branch; String status; String message}*/; String backPromote /* e.g. 'Off' | 'Sent to TRAINING: Deployed' | 'TRAINING: waiting for Sync now' */; Boolean needsSecondApprover; String firstApprover.
RlyPromoteController (new, @AuraEnabled):
  getPromote() → PromoteBoard { Boolean canPromote /*RlyApprovalService.canApprove() or admin*/; List<PromoteStage> stages; }
    PromoteStage { Id stageId; String stageName; String stageBranch; Id nextId; String nextName; String nextBranch; List<Ready> ready; }
    Ready { Id id; String name; String title; Boolean isHotfix; String hotfixReason; Datetime deployedOn; String raisedBy; List<String> tests; Integer componentCount; }
    ready = releases with Target_Org__c = stage, Status__c 'Deployed', Merge_Commit__c set, Promoted_In__c null, Release_Type__c != 'Back_Promote'; hotfixes first, then oldest deploy first.
  promote(String requestJson /* {stageId, releaseIds:[...], title} */) → Id of the new Promotion release. Validates: all ids ready for that stage; title required (default suggestion by UI: "Promote <n> releases to <next>" or the hotfix title). Creates the record (Source_Org__c stage, Target_Org__c next, Title__c, Test_Classes__c = union, Is_Hotfix__c = any carried hotfix, Hotfix_Reason__c = carried reasons joined "; " left 255, Carried_Releases__c), sets Promoted_In__c on the carried releases, dispatches pipeline mode 'promote' (components = merge SHAs oldest first, branch 'promote/rel-xxxxx', target = next stop's branch, environment = stage's Git env, target_environment = next stop's Git env) exactly the way RlyRaiseService dispatches 'hub' (run token, Check_Token__c, Pending_Run__c…). From there the existing flow (raise result → scan/validate → approval → merge → deploy) must work for it; read RlyStatusReader/RlyCheckReader/RlyDeployReader and make the promote run's raise result understood.
RlyApprovalService: two-approver rule as defined; applies to approveRelease and approveAs (Slack). Reject works as before.
After a deploy whose target is the hub org: options for 'merge' include syncBranches = stage branches (route order, hub excluded) + developer branches (RlyPipelineOptions). Store the returned sync list in Back_Merge_Result__c (RlyDeployReader). The script returns it in the merge result (see pipeline section) under key "sync".
Back promote (new class RlyBackPromote + methods on RlyRouteController, admins only):
  RlyRouteController.getBackPromote() → BackPromoteBoard { Boolean enabled; Boolean isAdmin; List<BackPromoteOrg> orgs; }
    BackPromoteOrg { Id orgId; String name; String branch; String environment /*Environment__c*/; String gitEnvironment; String status /*org Status__c*/; String whenValue; Boolean approval; Integer behind; List<String> behindNames /*REL numbers*/; Datetime syncedOn; String syncStatus; Id lastSyncId; }
    behind = count of releases with Target_Org__c = hub org, Status__c 'Deployed', deploy finished after Synced_On__c (all of them when never synced).
  RlyRouteController.setBackPromote(Boolean enabled) → BackPromoteBoard  (PMD: Boolean params are not allowed: take String 'on'|'off' instead: setBackPromote(String state))
  RlyRouteController.saveBackPromoteOrg(String settingsJson /* {orgId, whenValue, approval} */) → BackPromoteBoard
  RlyRouteController.syncNow(Id orgId) → Id of the Back_Promote release (status 'Ready for approval' when Back_Promote_Approval__c, else dispatched now with mode 'sync').
  Automatic: when the hub records a successful deploy to the hub org and Back_Promote__c is on, each After_Deploy org gets a Back_Promote release (dispatched in the same request if no approval is needed, respecting callouts-before-DML; if that ordering isn't possible in that code path, create the records with Status 'Queued' and dispatch on the next read of the release page / Pipeline tab — no async Apex).
  Sync result: the hub reads results/<REL>/sync.json (see pipeline) like the other steps, sets the release Status (Deployed / Failed), and on success sets the org's Synced_On__c / Sync_Status__c.
RlyOrgController.saveOrg accepts Hotfix_Two_Approvers__c, Back_Promote_When__c, Back_Promote_Approval__c; getOrgs/queries return them.
Slack (RlySlackCard): hotfix → title prefixed "Hotfix: " and a line "Why: <reason>"; promotion → "Promotes REL-…, REL-…"; back promote → events go to the target org's channel as usual.

## UI (UI agent owns lwc/, tabs/RLY_Promote.tab, applications/*.app entry for the tab, lwc/rlyReleaseGuide content)
- rlyReleaseBuilder: Raise step (step 5 of 5 is "Raise"; review step shows the raise form): when start.canHotfix, a lightning-input checkbox "This is a hotfix" + Hotfix pill; when ticked a required lightning-textarea "Why is this a hotfix?" (max 255) and the help line from the board; the raise button label becomes "Raise hotfix". Send isHotfix/hotfixReason in the request JSON. Stage-org hotfix UI (stageCards, hotfix note) can be removed since stageSources is empty; keep the environment tiles / org list exactly as built.
- rlyApprovalQueue: hotfix rows first, red "Hotfix" pill (rr-pill-bad style used elsewhere), the reason under the title; promotions show "Promotion" pill and "Carries REL-…".
- rlyReleaseView (release page): Hotfix pill in the header; Details: "Why it's a hotfix"; for promotions "Carries" list with links; for carried releases "Promoted in REL-…"; Progress steps after deploy to the hub: "Merged back to <stage branches>", "Merged back to developer branches" (status pill Done / "n to review" with per-branch lines), "Back promote" (Off / per org). Second-approver notice when needsSecondApprover.
- rlyPromote (NEW component + tab RLY_Promote "Promote", lightning__Tab target): per PromoteStage a card "<stage> → <next>": table of ready releases with checkboxes (hotfixes first with pill + reason), tests carried summary, title input, button "Promote hotfix to <next>" when only hotfixes are ticked, otherwise "Promote <n> releases to <next>"; empty state "Nothing deployed to <stage> is waiting to be promoted." After promote, navigate to the new release (same navigation the builder uses after raising).
- rlyPipeline: Role option "Back promote (after production)"; on stage/hub cards (approval section) toggle "Hotfixes into <org> need 2 approvers"; route shows Back_Promote orgs dashed after the hub ("⤳") with "Back promote · matches PROD" / "· n releases behind"; a "Back promote" card (Off by default switch "Send PROD's changes to other orgs after a deploy" + help) and on each Back_Promote org card: When segmented control, "Approve before syncing" toggle, behind pill + names, "Sync now" button (admins). Developer-only fields (Slack "Also post here" etc.) unchanged.
- rlyReleaseGuide: update the hotfix section to the new definition, add "Promote to production" and "Back promote (optional)" sections; no demo org names in instructions.

## Pipeline (pipeline agent owns /home/claude/release-relay-demo/{scripts,.github,pipelines} and hub6/staticresources/RLY_Pipeline_*.resource)
- Bump the version stamp in every pipeline file to 9 ("Release Relay pipeline files: version 9") and copy the files into the matching hub6/staticresources/RLY_Pipeline_*.resource (byte-identical; RlyPipelineFiles reads the version from them).
- syncDeveloperBranches: remove the "branch starts with hotfix/ → first branch takes -X theirs" heuristic; only when options.stageWins === true (the hub no longer sends it). Order of options.syncBranches is respected; each branch merges the previous synced one? NO: each listed branch merges TARGET (the branch just merged into) directly. Return the list as today and include it in the merge result JSON under "sync" (check what the hub reads today and keep compatibility).
- mode 'promote' must work for the hub: honours options.hub / attempt (run token in raise.json) / tests / validateMerged like mode 'hub'; writes raise.json with the PR url/number the same shape as hub mode. Read raiseFromHub and raisePromotion and make promote's result identical in shape.
- NEW mode 'sync' (back promote): BRANCH = source branch (the hub's, e.g. prod), TARGET = the back-promote org's branch (create it from BRANCH if missing), ENVIRONMENT = hub env, TARGET_ENVIRONMENT = that org's env. Steps: fetch, checkout TARGET, merge origin/BRANCH (no -X), on conflict → result {status:'Conflict', conflicts:[files]} and stop (no push); else compute the deployable delta (old TARGET head → merged head) under the source path with the same plan builder merge/deploy uses, deploy to TARGET_ENVIRONMENT (test level: env var DEPLOY_TEST_LEVEL, default RunLocalTests when Apex changed, NoTestRun otherwise, same helper as deploy), then push TARGET. Result file results/<REQUEST_ID>/sync.json: {request, step:'sync', status:'Deployed'|'Nothing to deploy'|'Conflict'|'Failed', sha, deployId, testsRun, conflicts:[], message, runUrl, attempt, finishedAt}. Nothing is pushed if the deploy fails.
- Workflow: add 'sync' to the mode choices and a job for it using environment ${{ inputs.target_environment }} (mirror how the deploy job gets the target org's login); allowed-target checks must accept the hub's back-promote branches when options.hub is true (as for other hub modes). Mirror in pipelines/gitlab|bitbucket|azure templates and pipelines/README.md.
- node --check scripts/release-relay.js must pass; commit to a branch feature/pipeline-v9 (NOT main), push it, and report the commit. The lead merges.
