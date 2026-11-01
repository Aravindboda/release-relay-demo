# Release Relay build 7: shared contract (backend ↔ UI)

Working package: /home/claude/hub6 (mdapi format: classes/, lwc/, objects/, permissionsets/, tabs/, applications/, customPermissions/, package.xml).
Deployed baseline (don't edit): /home/claude/hub5.
Design boards (the UI must match these 1:1 in look, layout and wording, using SLDS / lightning base components):
/tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/canvas/project/
  HubSlackConnection.dc.html (Pipeline tab: Slack connection card + per-org "Approval and Slack" section)
  HubSlackCard.dc.html (what the Slack message looks like)
  HubReleasePolish.dc.html (release page)
  HubGuide.dc.html (Guide tab) + shots/*.jpg (real screenshots for the Guide)

Wording rule: use org names (DEV1, SIT, PROD), never "vendor".

## New / changed fields (backend creates in objects/*.object, adds to package.xml, grants FLS in permission sets)
RLY_Org__c:
  Approval_In__c   Picklist: "Release Relay" (default), "GitHub"
  Slack_Channel__c Text(80)  channel name or ID, e.g. #rr-sit
  Slack_Post__c    Checkbox  default false
  Slack_Approve__c Checkbox  default false
RLY_Release__c:
  Check_Token__c   Text(40)  token of the latest pipeline run the hub started (results must echo it)
  Slack_Channel_Id__c Text(40)
  Slack_Ts__c      Text(40)  Slack message timestamp of the release card
  Approved_Via__c  Text(40)  "Release Relay" | "Slack" | "GitHub"
RLY_Notification__c:
  Signing_Secret__c EncryptedText(175, mask lastFour) – Slack signing secret (never sent to the browser)
  (Webhook_URL__c stays, legacy fallback; Events default = all six when Slack is first switched on)
User:
  RLY_Slack_Member_Id__c Text(20)  Slack member ID (U0…), edited by admins only (no FLS edit in RLY_Developer/RLY_Approver)

## Apex methods the UI calls (backend implements exactly these signatures)
RlyReleasesController.Detail – keep all existing fields and ADD:
  @AuraEnabled public String phase;      // label for the header pill: e.g. 'Resolving conflicts' when Status 'Validating' and Pending_Run__c=='resolve'; otherwise Status__c
  @AuraEnabled public String notice;     // info line to show above the timeline (e.g. 'SIT changed after the checks passed, so they are running again.' or 'Waiting for approval in GitHub'), or null
  @AuraEnabled public String slackUrl;   // https://slack.com/app_redirect?channel=<id>&message_ts=<ts>-style permalink, or null
  @AuraEnabled public String approvedIn; // target org's Approval_In__c
  @AuraEnabled public List<String> tests;// test classes of the release
RlyOrgController: getOrgs() returns RLY_Org__c rows including Approval_In__c, Slack_Channel__c, Slack_Post__c, Slack_Approve__c; saveOrg(...) existing method accepts and saves those fields (same JSON shape as today plus the new keys).
RlySlackController (replaces the webhook card API):
  getSlack() -> SlackSettings { Boolean isAdmin; Boolean enabled; List<String> events; List<String> allEvents;
      Boolean connected; String workspace; String status /*'Connected'|'Not set up'|'Error: …'*/;
      String signingSecretHint /*'Saved (ends ••••4f2a)' or null*/; String actionsUrl /*the Site URL path to give Slack, or null*/;
      Integer approversLinked; Integer approversTotal; List<ApproverLink> approvers; Datetime lastSent; String lastResult; }
    ApproverLink { Id userId; String name; String slackMemberId; }
  saveSlack(String settingsJson /* {enabled, events[], signingSecret (blank keeps)} */) -> SlackSettings
  testSlack() -> SlackSettings              // auth.test through Named Credential RLY_Slack; fills workspace/status
  sendSlackTest(String channel) -> SlackSettings  // posts a test message to that channel
  saveSlackMember(Id userId, String memberId) -> SlackSettings  // admins only; blank clears

## Rules for all code (non-negotiable)
- Code Analyzer/PMD 7 all apex categories must report ZERO findings (Low included): run
  bash /tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/pmdscan.sh /home/claude/hub6/classes
  Only allowed suppression: @SuppressWarnings('PMD.ApexSuggestUsingNamedCred') on RlyOrgSession.send (exists).
  Limits: method cyclomatic <10, cognitive <15, NCSS <40; class cyclomatic <40, cognitive <50; ≤3 params; no Boolean params;
  fields declared first; ApexDoc on every public/global thing with @description/@param/@return; no unused vars.
- Top-level classes `with sharing`; elevated SOQL/DML in a private inner `without sharing` class; queries WITH SYSTEM_MODE / AccessLevel.SYSTEM_MODE / `as system` as the existing code does.
- No async Apex at all (no Queueable/@future/Batch/Schedulable). Callouts before DML in a transaction.
- Every test method uses System.runAs; each class ≥ 75% coverage (aim 90%); no SeeAllData.
- Don't use Apex reserved words as identifiers (hint, on, when, first, after, all, inner, list, merge, json, url, …) and don't shadow system classes with local names.
- Names must not contain "New" or "Hub".
- LWC: no setTimeout/setInterval (eslint @lwc/lwc/no-async-operation), no eslint-disable comments, SLDS classes / base components only, no external libraries.

## CHANGE 1 (overrides the above where they differ) – generic, owner-configurable approval and names
This package is installed by other product owners in their own orgs. Nothing may be hard-wired to our demo
(no 'SIT'/'sit'/'PROD'/'prod'/'DEV1', no '#rr-…', no 'GitHub' baked into labels or logic beyond the provider adapter).
- RLY_Org__c.Approval_In__c picklist values (API value → label): Salesforce → "In Salesforce" (default),
  Slack → "In Slack", Git → "In Git provider". REMOVE the Slack_Approve__c field from the design and code: approving
  in Slack = Approval_In__c 'Slack'. Approving in the Git provider = Approval_In__c 'Git' (the old 'GitHub' behaviour:
  auto-start the merge when checks pass; the provider's own reviewers approve; Approved_Via__c = provider name).
- The UI shows Approval_In__c as one choice whose options come from the hub's connections:
  RlyOrgController adds to its getOrgs() result: List<ApprovalOption> approvalOptions, ApprovalOption { String value; String label; }
  built server-side: always {Salesforce, 'In Salesforce'}; {Slack, 'In Slack'} only when the Slack connection is set up
  (Named Credential RLY_Slack works / settings enabled); {Git, 'In ' + <Git connection provider label, e.g. GitHub>} only when a Git
  connection exists. Designed so another option (e.g. Teams) is one more entry later.
- Slack card buttons Approve/Reject show only when the target org's Approval_In__c = 'Slack'.
- User-facing product name in Slack messages/buttons ("Open in Release Relay") comes from Custom Label RLY_App_Name
  (value "Release Relay"), via System.Label.RLY_App_Name; include labels/CustomLabels.labels + package.xml. Notices use the
  org records' Name values, never literal org names.
- UI placeholders are generic: channel input placeholder "#channel-name"; no demo names in code or the Guide's instructions
  (the Guide may show screenshots of the demo, and uses example names only inside clearly marked examples).
