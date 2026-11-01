/**
 * Release Relay guide content (Guide v3).
 *
 * Sections are grouped for the left navigation (Start here, Daily use, Reference). A section has one or more
 * cards; a card has blocks. Text uses two marks only: `code` (monospace) and **bold**.
 * Block types:
 *   text      { paras: [] }
 *   list      { items: [] }
 *   table     { cols: [], rows: [[]] }
 *   note      { text }
 *   progress  { labels: [] }                         numbered strip; a click opens that step
 *   steps     { steps: [{ title, who, where, items | text, providers, shot }] }
 *   seq       { stops: [{ title, text }], shots: [] } a row of stops with arrows, screenshots under it
 *   repo      { providers }                           tree + files table, one tab per Git provider
 *   shots     { shots: [] }
 *   files     {}                                      the pipeline files to download (PIPELINE_FILES), versions from the hub
 * providers: { GitHub: [...], GitLab: [...], Bitbucket: [...], AzureDevOps: [...] } (lists shown in a tab set).
 * shot: { name: 'pipeline', cap } (a jpg in the RLY_Guide_Shots static resource).
 * Names of orgs and branches appear only in clearly marked examples; the screenshots come from a demo hub.
 * adminOnly sections show only to users with the RLY_Admin custom permission.
 * more: cards of other sections shown under a section's own ({ key, only: block type, noAside }).
 * "Release Relay" in the text is replaced with the app's name (Custom Label RLY_App_Name).
 */

export const PROVIDERS = [
    { value: 'GitHub', label: 'GitHub' },
    { value: 'GitLab', label: 'GitLab' },
    { value: 'Bitbucket', label: 'Bitbucket' },
    { value: 'AzureDevOps', label: 'Azure DevOps' }
];

export const GROUPS = [
    { key: 'start', label: 'Start here' },
    { key: 'daily', label: 'Daily use' },
    { key: 'ref', label: 'Reference' }
];

const SHOT_NOTE = 'Screenshots are examples from a demo hub on GitHub.';

const TOKENS = {
    GitHub: [
        'A fine-grained personal access token on the repository: **Contents**, **Pull requests**, **Actions** and **Workflows**, all Read and write.',
        'Named Credential `RLY_GitHub` (Pipeline → Git connection: provider GitHub, repository `owner/repository`).'
    ],
    GitLab: [
        'A project access token (role Maintainer) with the scope `api`. Also Settings → CI/CD → Variables → **Minimum role to use pipeline variables**: Maintainer, so the hub can pass the release.',
        'Named Credential `RLY_GitLab` (Pipeline → Git connection: provider GitLab, repository `group/project`).',
        'Running releases from the hub on this provider is coming in a later version; the pipeline file is ready.'
    ],
    Bitbucket: [
        'A repository access token with **Repositories**, **Pull requests** and **Pipelines**: Read and write.',
        'Named Credential `RLY_Bitbucket` (Pipeline → Git connection: provider Bitbucket, repository `workspace/repository`).',
        'Running releases from the hub on this provider is coming in a later version; the pipeline file is ready.'
    ],
    AzureDevOps: [
        'A personal access token with **Code**: Read and write, and **Build**: Read and execute.',
        'Named Credential `RLY_AzureDevOps` (Pipeline → Git connection: provider Azure DevOps, repository `organization/project/repository`, and the pipeline id).',
        'Create the pipeline from `azure-pipelines.yml` (Pipelines → New pipeline → Azure Repos Git → Existing Azure Pipelines YAML file). Its id is the number after `definitionId=`.',
        'Running releases from the hub on this provider is coming in a later version; the pipeline file is ready.'
    ]
};

const LOGINS = {
    GitHub: [
        'Settings → Environments → one environment per stage org, named as the org\'s **Git environment** on its Pipeline card.',
        'Secrets: `SF_USERNAME`, `SF_CLIENT_ID`, `SF_JKS`, `SF_JKS_PASSWORD`. Variables: `SF_INSTANCE_URL`, `SF_JKS_ALIAS`.',
        'Deployment branches: the pipeline branch only (usually `main`). Add required reviewers to the production environment if you approve there.'
    ],
    GitLab: [
        'Settings → CI/CD → Variables. Add each variable once per stage org, with **Environment scope** set to the org\'s Git environment.',
        'Masked and protected: `SF_USERNAME`, `SF_CLIENT_ID`, `SF_JKS` (type Variable: the .jks base64-encoded on one line), `SF_JKS_PASSWORD`. Plain: `SF_INSTANCE_URL`, `SF_JKS_ALIAS`.',
        'Protect the pipeline branch (usually `main`) so only it can use protected variables.',
        'Add `RELAY_TOKEN` (masked, protected, environment scope `*`): a project access token, role Maintainer, scopes `api` and `write_repository`. The pipeline pushes branches and merges with it.'
    ],
    Bitbucket: [
        'Repository settings → Pipelines → Repository variables. Prefix each org\'s login with its Git environment in upper case (example: `sit` → `SIT_SF_USERNAME`).',
        'Secured: `<ENV>_SF_USERNAME`, `<ENV>_SF_CLIENT_ID`, `<ENV>_SF_JKS` (the .jks base64-encoded), `<ENV>_SF_JKS_PASSWORD`. Plain: `<ENV>_SF_INSTANCE_URL`, `<ENV>_SF_JKS_ALIAS`. Also `RELAY_TOKEN` (Secured): a repository access token with Repositories and Pull requests: Write.',
        'Turn on Pipelines in Repository settings.'
    ],
    AzureDevOps: [
        'Pipelines → Library → one variable group per stage org, named `release-relay-` plus the org\'s Git environment (example: `release-relay-sit`).',
        'Secret variables: `SF_USERNAME`, `SF_CLIENT_ID`, `SF_JKS` (the .jks base64-encoded), `SF_JKS_PASSWORD`. Plain: `SF_INSTANCE_URL`, `SF_JKS_ALIAS`.',
        'Let the pipeline use each variable group and environment (Pipeline permissions). Project Settings → Repositories → Security → `<project> Build Service`: Contribute, Create branch, Contribute to pull requests (and Bypass policies when completing pull requests if stage branches have policies). For approvals: Pipelines → Environments → the org\'s Git environment → Approvals and checks.'
    ]
};

const PIPE_FILE = {
    GitHub: '.github/workflows/release-relay.yml',
    GitLab: '.gitlab-ci.yml',
    Bitbucket: 'bitbucket-pipelines.yml',
    AzureDevOps: 'azure-pipelines.yml'
};

function tree(provider) {
    const file = PIPE_FILE[provider];
    const pipeLine = file.includes('/')
        ? '├─ .github/workflows/\n│  └─ release-relay.yml     ← the pipeline\n'
        : '├─ ' + file.padEnd(25) + '← the pipeline\n';
    return '<repository>/\n'
        + pipeLine
        + '├─ scripts/\n'
        + '│  └─ release-relay.js      ← every step\n'
        + '├─ force-app/main/default/  ← the metadata\n'
        + '├─ .relay-inbox/            ← hub drops zips here\n'
        + '└─ sfdx-project.json\n'
        + '\n'
        + 'branches:  main (pipeline branch)\n'
        + '           one per org (example: dev1 · sit · prod)\n'
        + '           feature/rel-xxxxx · hotfix/rel-xxxxx · promote/rel-xxxxx\n'
        + '           release-relay-results  ← step results';
}

function repoRows(provider) {
    const word = provider === 'GitLab' ? 'merge request' : 'pull request';
    return [
        ['`' + PIPE_FILE[provider].split('/').pop() + '`', 'Starts the jobs: raise, scan, validate, merge, deploy. Modes: hub, check, resolve, merge, promote, sync. Lives at `' + PIPE_FILE[provider] + '` on the pipeline branch.'],
        ['`release-relay.js`', 'The steps themselves: convert the hub\'s zip, open the ' + word + ', merge the target, run tests, deploy, update branches.'],
        ['`.relay-inbox/`', 'Where the hub commits a release\'s zip and your conflict choices. The pipeline removes them after use.'],
        ['`release-relay-results`', 'One folder per release with `scan.json`, `validate.json`, `merge.json`, `deploy.json`. The hub reads these.'],
        ['`feature/rel-xxxxx`', 'One branch per release, from the developer org\'s branch.'],
        ['`hotfix/rel-xxxxx`', 'A hotfix: a release from a developer org marked urgent. Same checks as a feature branch.'],
        ['`promote/rel-xxxxx`', 'A promotion: the merge commits of releases deployed to a stage, into the next stop\'s branch.']
    ];
}

/**
 * The pipeline files packaged with the app (one static resource each). provider All: every provider needs it.
 * The GitHub workflow's name comes from the Git connection when the hub has one.
 */
export const PIPELINE_FILES = [
    {
        resource: 'RLY_Pipeline_GitHub', provider: 'GitHub', name: 'release-relay.yml', path: PIPE_FILE.GitHub,
        what: 'The GitHub Actions workflow: starts the jobs (raise, scan, validate, merge, deploy) when the hub asks.'
    },
    {
        resource: 'RLY_Pipeline_GitLab', provider: 'GitLab', name: '.gitlab-ci.yml', path: PIPE_FILE.GitLab,
        what: 'The GitLab CI pipeline: starts the same jobs when the hub asks.'
    },
    {
        resource: 'RLY_Pipeline_Bitbucket', provider: 'Bitbucket', name: 'bitbucket-pipelines.yml', path: PIPE_FILE.Bitbucket,
        what: 'The Bitbucket custom pipeline: starts the same jobs when the hub asks.'
    },
    {
        resource: 'RLY_Pipeline_Azure', provider: 'AzureDevOps', name: 'azure-pipelines.yml', path: PIPE_FILE.AzureDevOps,
        what: 'The Azure Pipeline: starts the same jobs when the hub asks.'
    },
    {
        resource: 'RLY_Pipeline_Script', provider: 'All', name: 'release-relay.js', path: 'scripts/release-relay.js',
        what: 'Every step the pipeline runs, for every provider: converts the hub\'s zip, opens the pull request, merges, tests, deploys.'
    }
];

function byProvider(fn) {
    const out = {};
    PROVIDERS.forEach((p) => {
        out[p.value] = fn(p.value);
    });
    return out;
}

const SECTIONS = [
    // ---------------- Start here ----------------
    {
        key: 'how',
        group: 'start',
        label: 'How it works',
        cards: [
            {
                key: 'how-main',
                title: 'How it works',
                blocks: [
                    { type: 'text', paras: ['Release Relay runs in one hub org. It reads changes from a developer org, turns them into a pull request (a merge request in GitLab) in your Git provider, checks them, and deploys them along the route after approval.'] },
                    {
                        type: 'list',
                        items: [
                            '**Hub**: this org. It holds the releases, approvals and history, and signs in to every registered org itself.',
                            '**Git provider**: one repository (GitHub, GitLab, Bitbucket or Azure DevOps). Each org has a branch; every release is a pull request into the next stage\'s branch.',
                            '**Pipeline**: your provider\'s pipeline runs the code scan and a check-only deploy with your tests, and later merges and deploys.',
                            '**Route**: developer orgs → stages in order → production (the hub). Pipeline → Route shows yours.',
                            '**Promote**: what is deployed to a stage moves on to the next stop from the Promote tab, hotfixes first.'
                        ]
                    }
                ]
            },
            {
                key: 'how-order',
                title: 'A release, in order',
                aside: SHOT_NOTE,
                blocks: [
                    {
                        type: 'seq',
                        stops: [
                            { title: 'Raise', text: 'Hub retrieves from the developer org' },
                            { title: 'Pull request', text: 'Pipeline converts and opens it' },
                            { title: 'Checks', text: 'Scan + check-only deploy, merged with the target' },
                            { title: 'Conflict?', text: 'Choose per file, checks run again' },
                            { title: 'Approve', text: 'In Salesforce, Slack or the Git provider' },
                            { title: 'Deploy', text: 'Merge, deploy, update dev branches' }
                        ],
                        shots: [
                            { name: 'review', cap: 'Review: what goes in, and which tests run.' },
                            { name: 'conflict', cap: 'Conflict: your version and the target\'s side by side.' },
                            { name: 'approval', cap: 'Approval: scan findings and the decision.' }
                        ]
                    },
                    { type: 'text', paras: ['**The test rule.** A release with an Apex class or trigger must include the test classes that cover it; Release Relay won\'t let you continue without one. Those tests run (RunSpecifiedTests) in every org the release deploys to. A release without Apex deploys without tests.'] }
                ]
            }
        ]
    },
    {
        key: 'setup',
        group: 'start',
        label: 'Set up, step by step',
        adminOnly: true,
        more: [{ key: 'repo-main' }, { key: 'repo-files' }, { key: 'how-order', only: 'seq', noAside: true }],
        cards: [
            {
                key: 'setup-main',
                title: 'Set up, step by step',
                aside: 'About 45 minutes for a hub with 2 orgs',
                blocks: [
                    { type: 'progress', labels: ['Git repository', 'Hub certificate', 'Register orgs', 'Pipeline logins', 'Route', 'Slack', 'People', 'First release'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Prepare the Git repository',
                                who: 'Git admin',
                                items: [
                                    'Create the repository and a branch per org (example: `dev1`, `sit`, `prod`; the hub can create missing ones).',
                                    'Copy the two pipeline files to the pipeline branch, usually `main` (see Repository files).',
                                    'Create a token for the hub and put it in a Named Credential in the hub. Pick your provider:'
                                ],
                                providers: byProvider((p) => TOKENS[p]),
                                where: 'Your Git provider · Salesforce Setup → Named Credentials · Release Relay → Pipeline → Git connection',
                                shot: { name: 'pipeline', cap: 'Example: Git connection shows Connected and lists what it checked.' }
                            },
                            {
                                title: 'Create the hub certificate',
                                who: 'Salesforce admin',
                                items: [
                                    'Setup → Certificate and Key Management → Create Self-Signed: `release_relay`, exportable key.',
                                    'Download the certificate (.crt) for step 3; Export to Keystore (.jks) for step 4.'
                                ]
                            },
                            {
                                title: 'Register each org',
                                who: 'Salesforce admin',
                                items: [
                                    'In the org: External Client App, JWT bearer flow with the hub .crt, admins pre-authorized, integration user\'s profile.',
                                    'In the hub: Remote Site for the org\'s My Domain.',
                                    'Pipeline → Register an org: role, My Domain, username, consumer key, branch → **Save and test sign-in**.'
                                ],
                                where: 'The org: Setup → External Client App Manager · Hub: Release Relay → Pipeline',
                                shot: { name: 'register', cap: 'Example: Register an org. The consumer key is saved encrypted and shown as ••••.' }
                            },
                            {
                                title: 'Give the pipeline a login per stage',
                                who: 'Git admin',
                                items: ['Each stage org (and production) needs its login where the pipeline can read it. Developer orgs need none: the hub reads them itself. Pick your provider:'],
                                providers: byProvider((p) => LOGINS[p])
                            },
                            {
                                title: 'Check the route',
                                text: ['Pipeline → Route shows developer orgs → stages → production. Use the arrows to reorder stages; **Create missing branches** makes any branch your Git provider doesn\'t have yet.']
                            },
                            {
                                title: 'Slack (optional)',
                                items: [
                                    'Skip this if you don\'t use Slack: everything works without it.',
                                    'Slack app with `chat:write`; bot token in Named Credential `RLY_Slack`. Pipeline → Slack connection: switch Slack on and press Test.',
                                    'On each org card: Slack channel and Post to Slack. To approve in Slack, set Approved in to **In Slack**.',
                                    '`/invite @<your Slack app>` in each channel.'
                                ]
                            },
                            {
                                title: 'Give people access',
                                text: ['Developer → `RLY_Developer` · Approver → `RLY_Approver` · Admin → `RLY_Admin` (includes Hotfix).']
                            },
                            {
                                title: 'Raise a first release',
                                text: ['New Release → pick a developer org → select a class and its test → Review → Raise. Watch it on the release page.'],
                                shot: { name: 'select', cap: 'Example: Select. The bar shows the test rule before you can go on.' }
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'repo',
        group: 'start',
        label: 'Repository files',
        adminOnly: true,
        cards: [
            {
                key: 'repo-main',
                title: 'Repository files',
                asideFromRepo: true,
                blocks: [
                    {
                        type: 'repo',
                        providers: byProvider((p) => ({ tree: tree(p), rows: repoRows(p) }))
                    }
                ]
            },
            {
                key: 'repo-files',
                title: 'Download the pipeline files',
                blocks: [
                    {
                        type: 'text',
                        paras: ['Put each file at its path on the pipeline branch (usually `main`). Your provider\'s file and `release-relay.js` are all you need. When a new version of Release Relay brings new files, update them from the Pipeline tab: it opens a pull request with them.']
                    },
                    { type: 'files' }
                ]
            }
        ]
    },

    // ---------------- Daily use ----------------
    {
        key: 'raise',
        group: 'daily',
        label: 'Raise a release (developer)',
        cards: [
            {
                key: 'raise-main',
                title: 'Raise a release',
                aside: SHOT_NOTE,
                blocks: [
                    { type: 'text', paras: ['You build in your developer org and raise releases from it. You need the `RLY_Developer` permission set.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Pick where the changes are',
                                where: 'New Release → Source',
                                text: ['Pick your developer org. The page shows where the release goes (the first stage of the route). Choose how far back to look and whether to show only your changes.'],
                                shot: { name: 'source', cap: 'Example: Source, with Goes to under the org cards.' }
                            },
                            {
                                title: 'Select the components',
                                where: 'New Release → Select',
                                items: [
                                    'Types are on the left with counts; changes on the right. Filter custom, standard or both, and search by name.',
                                    'Not in the list? Add it by type and API name at the bottom.',
                                    'Components to remove show a red **Delete** pill (see Deleting components).',
                                    'The bar at the bottom counts your Apex and test classes. Red means Apex without a test class: tick the suggested test or add it.'
                                ],
                                shot: { name: 'select', cap: 'Example: Select, with the test rule in the bar.' }
                            },
                            {
                                title: 'Review and raise',
                                where: 'New Release → Review',
                                text: [
                                    'Check the list (remove anything that shouldn\'t go), give the release a title, and raise it. The release page opens and follows the release step by step.',
                                    'With the Hotfix permission you also see **This is a hotfix**. Tick it for an urgent fix and say why: the button becomes **Raise hotfix** (see Hotfix).'
                                ],
                                shot: { name: 'review', cap: 'Example: Review, what goes in and which tests run.' }
                            },
                            {
                                title: 'Follow your release',
                                where: 'Releases tab',
                                text: [
                                    'The path at the top shows Raised → Pull request → Checks → Approval → Deploy. While something runs the page checks every 30 seconds; **Check now** checks at once.',
                                    'Code scan findings and deployment errors are listed under the progress. Fix them in your org and raise again, or ask an approver to bypass a blocking code scan.'
                                ]
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'deletions',
        group: 'daily',
        label: 'Deleting components',
        cards: [
            {
                key: 'del-main',
                title: 'Deleting components',
                blocks: [
                    { type: 'text', paras: ['A release can remove components as well as bring them. Deletions are removed from the target branch, and on deploy from the target org (as `destructiveChangesPost.xml`). They travel with the release: promoted to production and merged back down like any change.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Orgs with source tracking',
                                where: 'New Release → Select',
                                text: ['Components you deleted in the org are listed with the changes, with a red **Delete** pill and **Delete from** the target. The **Deleted** type on the left counts them.']
                            },
                            {
                                title: 'Orgs without source tracking',
                                where: 'New Release → Select',
                                text: [
                                    'Press **Find deleted components**. The hub compares the files in your org\'s own branch with what is in the org and lists what is in the branch but not in the org.',
                                    'They may have been deleted in your org, or came from another org through the branch and were never deployed to yours. Nothing is ticked for you: **tick only what you deleted**.'
                                ]
                            },
                            {
                                title: 'Delete by name',
                                where: 'New Release → Select',
                                text: ['Not in the list? At the bottom choose **Delete**, the type and the API name, for example Apex Class and `OldHelper`.']
                            },
                            {
                                title: 'Review',
                                where: 'New Release → Review',
                                text: [
                                    'Deletions are listed in red under **Deleted from** the target. A component can\'t be both added and deleted in one release.',
                                    'Deleting Apex needs no test class unless Apex is also added. Into production, Salesforce runs the local tests when Apex is deleted.'
                                ]
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'approve',
        group: 'daily',
        label: 'Approve (approver)',
        cards: [
            {
                key: 'approve-main',
                title: 'Approve',
                aside: SHOT_NOTE,
                blocks: [
                    { type: 'text', paras: ['You decide what goes into each stage. You need the `RLY_Approver` permission set. Each org card on the Pipeline tab sets where releases into that org are approved: **In Salesforce**, **In Slack** or **In** your Git provider.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'See what\'s waiting',
                                where: 'Approvals tab',
                                text: ['The list shows releases whose checks finished: Ready for approval, or Checks failed. Hotfixes come first, with a red **Hotfix** pill and the reason under the title; promotions show a **Promotion** pill. Open one to see its progress, code scan findings, deployment errors and components.'],
                                shot: { name: 'approvals', cap: 'Example: the Approvals tab.' }
                            },
                            {
                                title: 'Approve and deploy',
                                text: ['**Approve and deploy** merges the pull request and deploys to the target org with the release\'s tests. If the target\'s branch changed after the checks passed, Approve first checks again against the newest branch. The release then shows Deployed, or Deploy failed with the reason.'],
                                shot: { name: 'approval', cap: 'Example: a release ready for approval.' }
                            },
                            {
                                title: 'Bypass a blocking code scan',
                                text: ['If only the code scan blocks, you can accept the findings with a reason. Your name and the reason are kept on the release. A failed validation can\'t be bypassed.']
                            },
                            {
                                title: 'Reject',
                                text: ['Reject needs a comment. The pull request is closed with your comment, so the developer sees why.']
                            },
                            {
                                title: 'Hotfixes that need 2 approvers',
                                text: ['An org card on the Pipeline tab can say **Hotfixes into <org> need 2 approvers**. Then a hotfix into that org needs two different approvers, and the person who raised it can\'t approve it. After the first approval the release page shows who approved and waits for the second. Approval is never skipped.']
                            },
                            {
                                title: 'Approve in Slack or in the Git provider',
                                items: [
                                    '**In Slack**: the release card in the org\'s channel shows Approve and Reject, for approvers whose Slack account is linked (see Slack).',
                                    '**In the Git provider**: when the checks pass the hub starts the merge, and your provider\'s own reviewers and branch rules approve it.'
                                ]
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'conflicts',
        group: 'daily',
        label: 'Conflicts between orgs',
        cards: [
            {
                key: 'conf-main',
                title: 'Conflicts between orgs',
                aside: SHOT_NOTE,
                blocks: [
                    {
                        type: 'list',
                        items: [
                            'Each developer org has its own branch. A release branch starts from it, so Git knows what that org started from.',
                            'Into a stage, Git combines releases line by line. Different lines in the same class: both kept. Nothing is overwritten.',
                            'Same lines changed by two releases: a conflict. The release stops before approval and shows **Conflict** with the files.',
                            'Validation deploys the merged result (what the stage will really get), not only your copy.',
                            'After each deploy to a stage, its branch is merged back into every developer branch.'
                        ]
                    },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Resolve it',
                                where: 'The release page',
                                text: [
                                    'For each file choose **Keep mine**, **Keep the target\'s**, or edit the merged lines, then resolve. Your choice is committed to the release branch.',
                                    'The page then shows Conflicts · Resolving while the pipeline merges the target and runs the checks again.'
                                ],
                                shot: { name: 'conflict', cap: 'Example: your version and the target\'s side by side.' }
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'hotfix',
        group: 'daily',
        label: 'Hotfix',
        cards: [
            {
                key: 'hf-main',
                title: 'Hotfix',
                blocks: [
                    { type: 'text', paras: ['A hotfix is a release from a **developer org**, marked urgent with a reason. It goes through the first stage like any release, is promoted to production on its own, and is then merged back down so no org overwrites it. Only users with the Hotfix permission (included in `RLY_Admin`) can mark a release as a hotfix. Approval is never skipped.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Raise it from the developer org that has the fix',
                                where: 'New Release → Review',
                                text: ['Pick your developer org and the components as usual. On the review step tick **This is a hotfix**, say why (required, up to 255 characters) and press **Raise hotfix**. Its branch is `hotfix/rel-xxxxx`. It gets the same scan, check-only deploy, tests and approval into the first stage as any release. Stage orgs aren\'t offered as sources: fix it in a developer org.']
                            },
                            {
                                title: 'Approve it first',
                                where: 'Approvals tab and Slack',
                                text: ['Hotfixes are listed first, with the reason. The Slack card starts with **Hotfix:** and shows **Why:**.']
                            },
                            {
                                title: 'Promote it on its own',
                                where: 'Promote tab',
                                text: ['When the hotfix is deployed to the stage, it waits on the Promote tab, ticked on its own: **Promote hotfix to** the next stop sends only its changes. Other work waiting in the stage stays there. Into production it is approved again (2 approvers if the production org card asks for it).']
                            },
                            {
                                title: 'Merged back down',
                                where: 'The release page',
                                text: ['After the deploy to production the hub merges production\'s branch into every stage branch and then every developer branch. The release page shows each one: **Done**, or **n to review** when a branch conflicts with work in progress. Nothing is forced: merge that branch by hand.']
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'promote',
        group: 'daily',
        label: 'Promote to production',
        cards: [
            {
                key: 'pr-main',
                title: 'Promote to production',
                blocks: [
                    { type: 'text', paras: ['Releases deployed to a stage move on to the next stop (the next stage, or production) from the **Promote** tab. You need `RLY_Approver` or `RLY_Admin`.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Pick what goes',
                                where: 'Promote tab',
                                items: [
                                    'One block per stage: the releases deployed there and not promoted yet. Hotfixes are first, then the oldest deploy first.',
                                    'Tick the releases to promote. Unticked ones stay in the stage for a later promotion.',
                                    'The panel on the right counts the releases and components and lists the test classes that run in the next stop (RunSpecifiedTests).'
                                ]
                            },
                            {
                                title: 'Promote',
                                text: ['Give the promotion a title and press **Promote <n> releases to** the next stop (or **Promote hotfix to** it). Release Relay raises one release of type Promotion on the branch `promote/rel-xxxxx` with the releases\' merge commits, oldest first. It runs the code scan, a check-only deploy and the tests into the next stop, then waits for approval like any release.']
                            },
                            {
                                title: 'Follow it',
                                where: 'The release page',
                                text: ['The promotion lists what it **Carries**; each carried release shows **Promoted in** with a link. If the promotion is rejected or fails, the releases it carried are ready to promote again.']
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'manual',
        group: 'daily',
        label: 'Manual steps',
        cards: [
            {
                key: 'ms-main',
                title: 'Manual steps',
                blocks: [
                    { type: 'text', paras: ['Some changes can\'t be deployed as metadata: profile or permission access, data loads, setup settings, a connected app setting, a scheduled job to start. Add them to the release as **manual steps**. They travel with the release through every org on the route and to back promote orgs, in order, and the **deployment team** checks each one off per org.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Add them when you raise',
                                where: 'New Release → Review → Manual steps',
                                items: [
                                    'Press **Add a manual step**: a title, the category (Profile or permission access, Data, Setup configuration, Other), **When** (Before deploy or After deploy) and the exact instructions, for example `Profile Sales User: Account.Region__c read/edit`.',
                                    '**Also in back promote orgs** is on by default. **Orgs**: all orgs on the route, or pick the orgs it applies to.',
                                    'Order them with the up and down arrows: the deployment team does them in that order. Up to 50 steps.',
                                    'Until the release is first deployed, the person who raised it (or an admin) can add, edit, reorder and delete steps on the release page.'
                                ]
                            },
                            {
                                title: 'Before deploy and after deploy',
                                where: 'The release page → Manual steps',
                                items: [
                                    '**Before deploy**: the deploy into an org doesn\'t start until that org\'s before deploy steps are done. An approved release waits with **Approved. Deploys when the deployment team finishes n manual steps before deploy.** The last tick starts the deploy.',
                                    '**After deploy**: shown as open work in that org after the deploy. The release and the Approvals tab show **n manual steps** while any are open.'
                                ]
                            },
                            {
                                title: 'The deployment team checks them off',
                                where: 'The release page → Manual steps → one tab per org',
                                items: [
                                    'Only users with the `RLY_Deploy_Team` permission set (Release Relay Deployment Team) or `RLY_Admin` tick steps.',
                                    'Tick a step when it is done: the page records who did it and when. **Not needed** asks for a note (for example: already set in this org). **Reopen** puts it back to do.',
                                    '**Show instructions** opens what exactly to do.'
                                ]
                            },
                            {
                                title: 'They follow promote and back promote',
                                where: 'Promote tab and back promote orgs',
                                items: [
                                    'A promotion carries the manual steps of every release it carries, in deploy order (the releases in the order they are promoted, then each step\'s order). The Promote tab lists them under the bundle.',
                                    'A back promote sync carries the steps with **Also in back promote orgs** of every release the org is behind, in deploy order.',
                                    'Steps scoped to some orgs only show up in those orgs.'
                                ]
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'backpromote',
        group: 'daily',
        label: 'Back promote (optional)',
        cards: [
            {
                key: 'bp-main',
                title: 'Back promote (optional)',
                blocks: [
                    { type: 'text', paras: ['Back promote keeps other orgs (for example a training or demo sandbox) in line with production. It is **off by default** and set up by an admin on the Pipeline tab. Metadata only: users and records in those orgs stay as they are, and they never send changes up the route.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Register the org',
                                where: 'Pipeline → Register an org',
                                text: ['Use the role **Back promote (after production)**, with its own branch and Git environment. On the route it shows dashed after production, with how many releases it is behind.']
                            },
                            {
                                title: 'Switch it on',
                                where: 'Pipeline → Back promote',
                                text: ['Turn on **Send production\'s changes to other orgs after a deploy**.']
                            },
                            {
                                title: 'Choose when, and whether to approve',
                                where: 'Pipeline → the org\'s card',
                                items: [
                                    '**When**: After every production deploy, or When an admin clicks Sync now (the default).',
                                    '**Approve before syncing**: off by default, so production\'s approval is enough. On: each sync waits for an approver.',
                                    '**Sync now** brings the org up to date with production at once. The card shows the releases it is behind and the last sync.'
                                ]
                            },
                            {
                                title: 'What a sync does',
                                text: ['A sync is a release of type Back promote from the hub to that org. The pipeline merges production\'s branch into the org\'s branch, deploys what changed, and only then pushes the branch. A conflict or a failed deploy stops it, and nothing is pushed.']
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'slack',
        group: 'daily',
        label: 'Slack (optional)',
        cards: [
            {
                key: 'slack-main',
                title: 'Slack (optional)',
                blocks: [
                    { type: 'note', text: 'Slack is optional. Without it, everything works in Salesforce and the org cards show only Approved in.' },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Bot token',
                                who: 'Admin',
                                items: [
                                    'Create a Slack app with the bot scope `chat:write`, install it to the workspace and copy the bot token.',
                                    'In the hub: Named Credential `RLY_Slack` holds the token; Salesforce keeps it, the page never shows it.',
                                    'Pipeline → Slack connection: switch Slack on, choose the events, Save, then **Test**. The card shows the workspace.'
                                ]
                            },
                            {
                                title: 'A channel per org',
                                who: 'Admin',
                                items: [
                                    'On each org card: **Slack channel** (`#channel-name` or its ID) and **Post to Slack**. A release posts one card in the target org\'s channel and updates it as it moves; every step goes into its thread.',
                                    'A developer org can also get a copy (**Also post here**), so its people see their own releases.',
                                    '**Send test message** checks the channel. Invite the app to each channel first.'
                                ]
                            },
                            {
                                title: 'Approve in Slack',
                                who: 'Admin',
                                items: [
                                    'Set Approved in to **In Slack** on the org card. The card then shows Approve and Reject; otherwise it shows Open in Release Relay.',
                                    'Slack must reach the hub: a Salesforce Site with the `RLY_Slack_Site` permission set for its guest user. Give Slack the Site address shown on the Slack connection card (Interactivity request URL).',
                                    'Paste the app\'s **Signing secret** in the Slack settings. It is saved encrypted; leave it blank to keep the saved one.'
                                ]
                            },
                            {
                                title: 'Link approvers',
                                who: 'Admin',
                                items: [
                                    'Slack connection → Approvers linked → **Show**. For each approver paste their Slack member ID (Slack: profile → More → Copy member ID) and Save.',
                                    'Only linked approvers can press Approve or Reject. Anyone else gets a private message to ask an admin to link them.'
                                ]
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'statuses',
        group: 'daily',
        label: 'Statuses',
        cards: [
            {
                key: 'st-main',
                title: 'Statuses',
                blocks: [
                    {
                        type: 'table',
                        cols: ['Status', 'Meaning', 'What to do'],
                        rows: [
                            ['Retrieving', 'The hub is reading the components from the source org.', 'Wait. Usually under a minute.'],
                            ['Workflow running', 'The pipeline is converting the files and opening the pull request.', 'Wait.'],
                            ['Validating', 'Code scan and check-only deploy are running.', 'Wait, or Check now.'],
                            ['Resolving conflicts', 'Your conflict choices were committed; the pipeline merges the target and checks again.', 'Wait.'],
                            ['Checks failed', 'The code scan blocked it, the validation failed, or it conflicts with the target.', 'Fix and raise again, resolve the conflict, or ask an approver to bypass the scan.'],
                            ['Ready for approval', 'All checks passed (or the scan was bypassed).', 'An approver approves or rejects, where the target org says (Salesforce, Slack or the Git provider).'],
                            ['Deploying', 'Merging the pull request and deploying.', 'Wait.'],
                            ['Deployed', 'In the target org; developer branches updated.', 'Nothing.'],
                            ['Deploy failed', 'The merge or the deploy failed.', 'Read the reason; raise a new release.'],
                            ['Rejected', 'An approver rejected it; the pull request was closed.', 'Read the comment; raise again.'],
                            ['Closed', 'The pull request was closed in the Git provider.', 'Raise again if still needed.'],
                            ['Failed', 'The release couldn\'t be raised (for example a component wasn\'t found).', 'Read the reason; raise again.']
                        ]
                    }
                ]
            }
        ]
    },

    // ---------------- Reference ----------------
    {
        key: 'perms',
        group: 'ref',
        label: 'Permission sets',
        cards: [
            {
                key: 'perm-main',
                title: 'Permission sets',
                blocks: [
                    {
                        type: 'table',
                        cols: ['Permission set', 'Gives'],
                        rows: [
                            ['`RLY_Developer`', 'New Release, Releases and Guide tabs: raise and follow releases.'],
                            ['`RLY_Approver`', 'Approvals and Promote tabs: approve, reject, bypass a code scan, promote what is deployed to a stage.'],
                            ['`RLY_Admin`', 'Pipeline tab: Git connection, orgs, route, Slack, linked approvers, back promote. Promote tab. Includes Hotfix. Shows the admin sections of this Guide.'],
                            ['`RLY_Slack_Site`', 'For the Site guest user only, so Approve in Slack can reach the hub. Needed only when an org is approved in Slack.']
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'trouble',
        group: 'ref',
        label: 'Troubleshooting',
        cards: [
            {
                key: 'tr-main',
                title: 'Troubleshooting',
                blocks: [
                    {
                        type: 'table',
                        cols: ['You see', 'Do this'],
                        rows: [
                            ['"No COMPONENT named …" after an update', 'Reload the page without cache (Ctrl+Shift+R), or log out and in.'],
                            ['A sign-in error on an org', 'The message names the fix (Remote Site, certificate, consumer key, pre-authorized user). An admin uses Test sign-in on the Pipeline tab.'],
                            ['Git connection: check failed', 'The token is missing a permission (see Set up, step 1) or the pipeline files aren\'t on the pipeline branch.'],
                            ['"couldn\'t close the pull request"', 'The Git token needs pull request (merge request) write access.'],
                            ['A test class doesn\'t show as a test', 'It must contain @IsTest. Add it by name if it isn\'t in the list.'],
                            ['Slack: Not set up or Error', 'Check the Named Credential `RLY_Slack` holds the bot token, then Test on the Slack connection card.'],
                            ['Slack test message fails with not_in_channel', 'Invite the Slack app to that channel.'],
                            ['Approve in Slack says you can\'t approve', 'An admin links your Slack member ID (Slack connection → Approvers linked), and you need `RLY_Approver`.'],
                            ['Waiting for approval in the Git provider', 'The target org is set to approve in Git: approve the pull request there, or change Approved in on its org card.']
                        ]
                    }
                ]
            }
        ]
    }
];

export default SECTIONS;
