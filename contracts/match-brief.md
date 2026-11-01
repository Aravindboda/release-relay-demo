# Make each tab match its design board exactly (Release Relay, Salesforce LWC)

The user checked the org and says the built tabs don't match the design canvas. Requirement: each tab must look EXACTLY
like its board: same layout, card structure, order of sections, headers, column sets, pills/badges, button placement,
spacing rhythm and wording. Use native SLDS (lightning base components + SLDS classes, SLDS colours/tokens as in the boards).

Boards (HTML mockups, render them with Playwright to see them: Chromium is preinstalled, `require('playwright')`,
`chromium.launch()`; screenshot at 1280px wide). Folder:
/tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/canvas/project/
Built package: /home/claude/hub6 (mdapi). LWC bundles in /home/claude/hub6/lwc/.

Rules that override the boards where they differ (the boards are older in places):
- Generic for any owner's org: no literal demo names (SIT/PROD/DEV1/sit/#rr-…) in code; use the org/branch names from data.
  Never the word "vendor". Product name from Custom Label c.RLY_App_Name (import APP_NAME from '@salesforce/label/c.RLY_App_Name').
- Git-provider neutral wording ("pull request", or "merge request" for GitLab: derive from the provider name the Apex gives).
- Slack is optional: no Slack UI when Slack isn't set up.
- If a board shows a feature that isn't built (e.g. Promote, Bundle, Compare editing), leave it out and list it in your report;
  don't invent Apex. You may NOT edit Apex/objects/permission sets (another person is changing them). If you need data the Apex
  doesn't return, list it in your report; use what exists (read the controller classes in /home/claude/hub6/classes to see
  the DTOs: RlyReleasesController.Row/Detail, RlyChangesController/RlyReleaseStart, RlyOrgController.PipelineOrgs,
  RlySlackController.SlackSettings, RlyRouteController).
- LWC rules: template expressions are plain property access (use getters), for:each needs key, lwc:if only, no
  setTimeout/setInterval/requestAnimationFrame, no eslint-disable, no innerHTML, no global CSS selectors.
  Accessible: labels, aria where the board has icons only.
- Keep existing behaviour working (Apex calls, navigation, events, the 30 s countdown on the release page via CSS animation).

Checks you must run before reporting (both must pass):
  python3 /tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/lwccheck/check.py /home/claude/hub6/lwc/<bundle>
  bash /tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/lwccheck/lint.sh /home/claude/hub6/lwc
Also render a static approximation of your template with Playwright (replace {expressions} with sample data, include
SLDS from https is NOT possible offline — approximate with the board's own CSS values) and compare side by side with the
board screenshot; iterate until the structure matches. Save both screenshots in
/tmp/claude-0/-home-claude/0e958625-02dd-52f2-980b-ad852cca4809/scratchpad/match/<bundle>/ (board.png, built.png).

Report: what you changed per board section, anything from the board you left out and why, data you needed but didn't have.
