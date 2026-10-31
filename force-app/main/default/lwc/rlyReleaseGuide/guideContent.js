/**
 * Release Relay guide content. Each section has steps; a step can have paragraphs (text),
 * a list (items), a table (cols + rows), a "where" hint and a note. adminOnly sections show
 * only to users with the Release Relay Admin permission.
 */
const SECTIONS = [
    {
        key: 'how',
        label: 'How it works',
        intro: 'Release Relay runs in one hub org. It reads changes from your developer org, turns them into a pull request in Git, checks them, and deploys them along the route after approval.',
        route: ['DEV1, DEV2… (developer orgs)', 'SIT', 'PROD (this hub)'],
        steps: [
            {
                key: 'how-pieces',
                title: 'The pieces',
                items: [
                    'Hub: this org. It holds the releases, approvals and history, and signs in to every registered org itself.',
                    'Git: one repository. Each org has a branch (dev1, sit, prod). Every release is a pull request.',
                    'Pipeline: GitHub Actions. It opens the pull request, runs the code scan and a check-only deploy with your tests, and later merges and deploys.'
                ]
            },
            {
                key: 'how-life',
                title: 'A release, start to finish',
                table: {
                    cols: ['Step', 'What happens', 'Who'],
                    rows: [
                        ['Raise', 'The hub reads your components from your developer org and commits them to a release branch that starts from your org\'s own branch.', 'Developer'],
                        ['Pull request', 'The pipeline turns the files into source format and opens a pull request into the next stage.', 'Automatic'],
                        ['Code scan', 'Salesforce Code Analyzer checks the changed code. High or Critical findings block; lower ones are shown but don\'t block.', 'Automatic'],
                        ['Validation', 'A check-only deploy of the release merged with the target, running the release\'s test classes.', 'Automatic'],
                        ['Approval', 'An approver approves (or rejects with a reason). A blocking code scan can be bypassed with a reason; a failed validation can\'t.', 'Approver'],
                        ['Merge and deploy', 'The pipeline merges the pull request and deploys to the target org with the same tests. Every developer branch then takes the change.', 'Automatic']
                    ]
                }
            },
            {
                key: 'how-tests',
                title: 'The test rule',
                text: [
                    'A release with an Apex class or trigger must include the test classes that cover it. Release Relay detects test classes (@IsTest) and won\'t let you continue without one. There is no bypass.',
                    'Those tests run (RunSpecifiedTests) in every org the release deploys to, and each class needs 75% coverage. A release without Apex deploys without tests (NoTestRun).'
                ]
            },
            {
                key: 'how-parallel',
                title: 'Several vendors at once',
                text: [
                    'Each developer org has its own branch, so Git knows what each vendor started from. When two releases change the same class, Git combines them line by line; nothing is overwritten.',
                    'If two releases change the same lines, the release shows "Conflict with SIT" and you choose what to keep. After every deploy to SIT, all developer branches are brought up to date.'
                ]
            }
        ]
    },
    {
        key: 'dev',
        label: 'Developer',
        intro: 'You build in your developer org and raise releases from it. Assign: Release Relay Developer and Release Relay User.',
        steps: [
            {
                key: 'dev-source',
                title: 'Pick where the changes are',
                where: 'New Release > Source',
                text: ['Pick your developer org. The page shows where the release goes (the first stage, usually SIT). Choose how far back to look and whether to show only your changes.']
            },
            {
                key: 'dev-select',
                title: 'Select the components',
                where: 'New Release > Select',
                items: [
                    'Types are on the left with counts; changes on the right. Filter custom, standard or both, and search by name.',
                    'Standard items count too: Account.Industry, standard picklists, layouts of standard objects.',
                    'Not in the list? Add it by type and API name at the bottom.',
                    'The bar at the bottom counts your Apex and test classes. Red means Apex without a test class: tick the suggested test or add it.'
                ]
            },
            {
                key: 'dev-review',
                title: 'Review and raise',
                where: 'New Release > Review',
                text: ['Check the list (remove anything that shouldn\'t go), give the release a title, and press Raise pull request. The release page opens and follows the release step by step.']
            },
            {
                key: 'dev-follow',
                title: 'Follow your release',
                where: 'Releases tab',
                text: [
                    'The release page checks the status every 30 seconds while something is running ("Next check at …"); Check now checks at once.',
                    'Code scan findings and deployment errors are listed under the timeline. Fix them in your org and raise again, or ask an approver to bypass a blocking code scan.'
                ]
            },
            {
                key: 'dev-conflict',
                title: 'When the release conflicts with SIT',
                text: ['Another release changed the same lines first. For each file choose Keep mine, Keep SIT\'s, or edit the merged text (remove the <<<<<<< and >>>>>>> markers), then Resolve and check again. The checks run on the merged result.']
            }
        ]
    },
    {
        key: 'approver',
        label: 'Approver',
        intro: 'You decide what goes into each stage. Assign: Release Relay Approver, Release Relay Developer and Release Relay User.',
        steps: [
            {
                key: 'ap-queue',
                title: 'See what\'s waiting',
                where: 'Approvals tab',
                text: ['The list shows releases whose checks finished: Ready for approval, or Checks failed. Open one to see its timeline, code scan findings, deployment errors and components.']
            },
            {
                key: 'ap-approve',
                title: 'Approve and deploy',
                text: ['Approve and deploy merges the pull request and deploys to the target org with the release\'s tests. The release shows Deployed, or Deploy failed with the reason (for example a merge conflict).']
            },
            {
                key: 'ap-bypass',
                title: 'Bypass a blocking code scan',
                text: ['If only the code scan blocks, you can accept the findings with a reason (at least 10 characters). Your name and the reason are kept on the release and shown in the next stage. A failed validation can\'t be bypassed.']
            },
            {
                key: 'ap-reject',
                title: 'Reject',
                text: ['Reject needs a comment. The pull request is closed with your comment, so the developer sees why.']
            },
            {
                key: 'ap-slack',
                title: 'Slack',
                text: ['When Slack is on, the approvers\' channel gets a message for the events the admin chose (for example Ready for approval, Checks failed, Deployed). Open in Release Relay takes you to the release.']
            }
        ]
    },
    {
        key: 'hotfix',
        label: 'Hotfix',
        intro: 'For a fix made directly in SIT that must reach PROD now. Needs the Release Relay Hotfix permission.',
        steps: [
            {
                key: 'hf-raise',
                title: 'Raise from SIT',
                where: 'New Release > Source > Stage orgs',
                text: ['Pick SIT under Stage orgs. The release goes to the next stop (PROD) and its branch starts from prod, so it carries only the hotfix, none of SIT\'s releases that aren\'t promoted yet.']
            },
            {
                key: 'hf-after',
                title: 'After it\'s deployed',
                text: ['The fix flows back into sit and every developer branch, so the next vendor release doesn\'t overwrite it.']
            }
        ]
    },
    {
        key: 'statuses',
        label: 'Statuses',
        intro: 'What each status means and what to do.',
        steps: [
            {
                key: 'st-table',
                title: 'Release statuses',
                table: {
                    cols: ['Status', 'Meaning', 'What to do'],
                    rows: [
                        ['Retrieving', 'The hub is reading the components from the source org.', 'Wait. Usually under a minute.'],
                        ['Workflow running', 'The pipeline is converting the files and opening the pull request.', 'Wait.'],
                        ['Validating', 'Code scan and check-only deploy are running.', 'Wait, or Check now.'],
                        ['Checks failed', 'The code scan blocked it, the validation failed, or it conflicts with the target.', 'Fix and raise again, resolve the conflict, or ask an approver to bypass the scan.'],
                        ['Ready for approval', 'All checks passed (or the scan was bypassed).', 'An approver approves or rejects.'],
                        ['Deploying', 'Merging the pull request and deploying.', 'Wait.'],
                        ['Deployed', 'In the target org; developer branches updated.', 'Nothing.'],
                        ['Deploy failed', 'The merge or the deploy failed.', 'Read the reason; raise a new release.'],
                        ['Rejected', 'An approver rejected it; the pull request was closed.', 'Read the comment; raise again.'],
                        ['Closed', 'The pull request was closed in Git.', 'Raise again if still needed.'],
                        ['Failed', 'The release couldn\'t be raised (for example a component wasn\'t found).', 'Read the reason; raise again.']
                    ]
                }
            },
            {
                key: 'st-help',
                title: 'Common problems',
                table: {
                    cols: ['You see', 'Do this'],
                    rows: [
                        ['"No COMPONENT named …" after an update', 'Reload the page without cache (Ctrl+Shift+R), or log out and in.'],
                        ['A sign-in error on an org', 'The message names the fix (Remote Site, certificate, consumer key, pre-authorized user). An admin uses Test sign-in on the Pipeline tab.'],
                        ['"couldn\'t close the pull request"', 'The Git token needs Pull requests: Read and write.'],
                        ['A test class doesn\'t show as a test', 'It must contain @IsTest. Add it by name if it isn\'t in the list.']
                    ]
                }
            }
        ]
    },
    {
        key: 'admin',
        label: 'Admin setup',
        adminOnly: true,
        intro: 'Set up once, in this order. Assign yourself Release Relay Admin and Release Relay User.',
        steps: [
            {
                key: 'ad-cert',
                title: 'Hub certificate',
                where: 'Setup > Certificate and Key Management',
                text: ['Use the self-signed certificate release_relay (create it if missing) and download its .crt. Every registered org trusts it.']
            },
            {
                key: 'ad-git',
                title: 'Git connection',
                where: 'Pipeline tab > Git connection',
                items: [
                    'A Named Credential (for example RLY_GitHub) holds the Git token. GitHub fine-grained token on the repository: Contents, Pull requests, Actions and Workflows, all Read and write.',
                    'The repository holds .github/workflows/release-relay.yml and scripts/release-relay.js on its pipeline branch (main).',
                    'Grant the credential\'s principal in Release Relay User (External Credential Principal Access). Save and check.'
                ]
            },
            {
                key: 'ad-org',
                title: 'Register each org',
                where: 'In the org, then Pipeline tab > Register an org',
                items: [
                    'In the org: External Client App Manager > New. OAuth on, scopes api and refresh_token, JWT bearer flow on with the hub\'s .crt. Policies: admin-approved users are pre-authorized; add the integration user\'s profile or permission set. Copy the consumer key.',
                    'In this hub: Remote Site Settings > New, with the org\'s My Domain URL.',
                    'Register the org: role (Developer, Stage or Hub), My Domain, login type, integration username, consumer key (stored encrypted, shown masked), certificate release_relay, branch (dev1, sit, prod) and Git environment.',
                    'Test sign-in. The card shows Connected and whether the org has source tracking.'
                ]
            },
            {
                key: 'ad-route',
                title: 'Route and branches',
                where: 'Pipeline tab > Route',
                text: ['Order the stages (SIT before PROD), save the route, and Create missing branches. Each developer org needs its own branch.']
            },
            {
                key: 'ad-env',
                title: 'GitHub environments for stage orgs',
                where: 'GitHub > Settings > Environments',
                text: ['One environment per stage org (sit, prod) with the secrets SF_USERNAME, SF_CLIENT_ID and SF_JWT_KEY and the variable SF_INSTANCE_URL. Protect prod with required reviewers. Developer orgs need no environment: the hub reads them itself.']
            },
            {
                key: 'ad-perms',
                title: 'Permission sets',
                table: {
                    cols: ['Permission set', 'Gives'],
                    rows: [
                        ['Release Relay User', 'The Git credential (needed by everyone who raises or approves).'],
                        ['Release Relay Developer', 'New Release and Releases tabs.'],
                        ['Release Relay Approver', 'Approvals tab: approve, reject, bypass a code scan.'],
                        ['Release Relay Admin', 'Pipeline tab: Git connection, orgs, route, Slack. Includes Hotfix.']
                    ]
                }
            },
            {
                key: 'ad-slack',
                title: 'Slack (optional)',
                where: 'Pipeline tab > Slack',
                items: [
                    'In Slack: create an app (or use one) > Incoming Webhooks > On > Add New Webhook to Workspace > pick the approvers\' channel > copy the URL.',
                    'In this hub: Remote Site Settings > New: https://hooks.slack.com.',
                    'Paste the webhook (stored encrypted), pick the events, switch it On and Send test message. Switch Off at any time.'
                ]
            }
        ]
    }
];

export default SECTIONS;
