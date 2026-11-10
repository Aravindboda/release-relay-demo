/**
 * Release Relay guide content (Guide v3).
 *
 * Sections are grouped for the left navigation (Start here, Set up, How to use, Reference). A section has one or more
 * cards; a card has blocks. Text uses two marks only: `code` (monospace) and **bold**.
 * Block types (a step can also carry badge: a pill beside its title, and code: a monospace block under its items):
 *   text      { paras: [] }
 *   list      { items: [] }
 *   table     { cols: [], rows: [[]] }
 *   note      { text }
 *   progress  { labels: [] }                         numbered strip; a click opens that step
 *   steps     { steps: [{ title, who, where, goal, items | text, check, problems, links, providers, shot }], start }
 *             start: the first step's number (default 1), to carry the numbering on after a table between two steps blocks.
 *             goal: why the step is needed (one line); check: what you should see when it worked;
 *             problems: [['You see', 'Do this']]; links: [{ label, to: section key }] (buttons that open that section).
 *             In a step with an illustration, the numbered items match the numbered callouts in the picture.
 *   checklist { stages: [{ to, label, who, time }] }  the setup stages with a tick each and a progress bar (per browser)
 *   links     { links: [{ label, to }] }               to: a section key; or tab: a tab's API name (opens that tab, state optional); kind 'neutral' for a plain button
 *   seq       { stops: [{ title, text }], shots: [] } a row of stops with arrows, screenshots under it
 *   repo      { providers }                           tree + files table, one tab per Git provider
 *   shots     { shots: [] }
 *   files     {}                                      the pipeline files to download (PIPELINE_FILES), versions from the hub
 *   route     { label, stops: [{ name, branch, role, kind, approval: [label, value, text] | text }],
 *               hops: [{ where, what, who }], every: [] }   stops with hops between (horizontal, one column on narrow
 *               screens); kind 'dev' or 'hub'; every: the steps at every hop, shown as a strip under it
 *   hotfixpath { label, stops: [{ name, branch, kind, text }], hops: [{ where, what }], back }   the same drawing in
 *               hotfix colours, with the merge back down (back) under it
 *   rules     { stageName, nextName }                 the four promotion rules, drawn (c-rly-promote-rules variant rules)
 *   promotecard { stageName, nextName }               the Promote card as an annotated example (c-rly-promote-rules variant card)
 * table also takes stack: true (at 480px and narrower each row becomes a card with the column names as labels).
 * providers: { GitHub: [...], GitLab: [...], Bitbucket: [...], AzureDevOps: [...] } (lists shown in a tab set).
 * shot: { name: 'pipeline', cap } (a jpg in the RLY_Guide_Shots static resource), or
 *       { ill: 'cert-create', cap, alt } (an annotated drawing, an svg in the RLY_Guide_Setup static resource).
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
    { key: 'setup', label: 'Set up' },
    { key: 'daily', label: 'How to use' },
    { key: 'ref', label: 'Reference' }
];

const SHOT_NOTE = 'Screenshots are examples from a demo hub on GitHub, some from an earlier layout of the pages.';

const TOKENS = {
    GitHub: [
        'A fine-grained personal access token on the repository, with the permissions in Set up → M. Secure your repository, step 1.',
        'Named Credential `RLY_Git_GitHub` (Pipeline → Connection & route → Git connection: provider GitHub, repository `owner/repository`).'
    ],
    GitLab: [
        'A project access token (role Maintainer) with the scope `api`. Also Settings → CI/CD → Variables → **Minimum role to use pipeline variables**: Maintainer, so the hub can pass the release.',
        'Named Credential `RLY_Git_GitLab` (Pipeline → Connection & route → Git connection: provider GitLab, repository `group/project`). Paste the token into its principal `RLY_Git_GitLab` (Setup → Named Credentials → External Credentials → RLY_Git_GitLab → Principals → Edit). Access comes with `RLY_Access`, part of every Release Relay group: no profile step is needed.',
        'CI/CD variables per GitLab environment (one per org\'s Git environment, for example dev, qa, prod): `SF_CLIENT_ID`, `SF_USERNAME`, `SF_INSTANCE_URL`, `SF_JKS_ALIAS`, `ORG_LABEL`; for all environments `SF_JKS`, `SF_JKS_PASSWORD` and `RELAY_TOKEN` (the project access token, for the jobs\' pushes).'
    ],
    Bitbucket: [
        'A repository access token with **Repositories**, **Pull requests** and **Pipelines**: Read and write.',
        'Named Credential `RLY_Git_Bitbucket`, which you create yourself (Release Relay ships only the GitHub and GitLab credentials). Pipeline → Connection & route → Git connection: provider Bitbucket, repository `workspace/repository`.',
        'Running releases from the hub on this provider is coming in a later version; the pipeline file is ready.'
    ],
    AzureDevOps: [
        'A personal access token with **Code**: Read and write, and **Build**: Read and execute.',
        'Named Credential `RLY_Git_AzureDevOps`, which you create yourself (Release Relay ships only the GitHub and GitLab credentials). Pipeline → Connection & route → Git connection: provider Azure DevOps, repository `organization/project/repository`, and the pipeline id.',
        'Create the pipeline from `azure-pipelines.yml` (Pipelines → New pipeline → Azure Repos Git → Existing Azure Pipelines YAML file). Its id is the number after `definitionId=`.',
        'Running releases from the hub on this provider is coming in a later version; the pipeline file is ready.'
    ]
};

const LOGINS = {
    GitHub: [
        'Settings → Environments → one environment per stage org, named as the org\'s **Git environment** (Pipeline → Orgs → the org).',
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
        'Repository settings → Pipelines → Repository variables. Prefix each org\'s login with its Git environment in upper case (example: `qa` → `QA_SF_USERNAME`).',
        'Secured: `<ENV>_SF_USERNAME`, `<ENV>_SF_CLIENT_ID`, `<ENV>_SF_JKS` (the .jks base64-encoded), `<ENV>_SF_JKS_PASSWORD`. Plain: `<ENV>_SF_INSTANCE_URL`, `<ENV>_SF_JKS_ALIAS`. Also `RELAY_TOKEN` (Secured): a repository access token with Repositories and Pull requests: Write.',
        'Turn on Pipelines in Repository settings.'
    ],
    AzureDevOps: [
        'Pipelines → Library → one variable group per stage org, named `release-relay-` plus the org\'s Git environment (example: `release-relay-qa`).',
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
        + '           one per org (example: dev · qa · prod)\n'
        + '           feature/rel-xxxxx · hotfix/rel-xxxxx · promote/rel-xxxxx\n'
        + '           release-relay-results  ← step results\n'
        + '           release-relay-snapshots  ← rollback snapshots';
}

function repoRows(provider) {
    const word = provider === 'GitLab' ? 'merge request' : 'pull request';
    return [
        ['`' + PIPE_FILE[provider].split('/').pop() + '`', 'Starts the jobs: raise, scan, validate, merge, deploy. Modes include hub, check, resolve, merge, promote, sync, rollback, compare, drift, data, migrate, archive and slack. Lives at `' + PIPE_FILE[provider] + '` on the pipeline branch.'],
        ['`release-relay.js`', 'The steps themselves: convert the hub\'s zip, open the ' + word + ', merge the target, run tests, deploy, update branches.'],
        ['`.relay-inbox/`', 'Where the hub commits a release\'s zip and your conflict choices. The pipeline removes them after use, and from version 28 also when a raise or an add fails; a release branch that still holds them can\'t be validated or merged.'],
        ['`release-relay-results`', 'One folder per release with `scan.json`, `validate.json`, `merge.json`, `deploy.json`. The hub reads these (from pipeline files version 27 each one is signed, and the hub trusts only signed ones once it has a run-signing key).'],
        ['`feature/rel-xxxxx`', 'One branch per release. The hub makes it from the developer org\'s branch; from pipeline files version 28 the pipeline restarts it where that branch and the target meet, so only the components you selected are in the ' + word + '.'],
        ['`hotfix/rel-xxxxx`', 'A hotfix: a release from a developer org marked urgent. Same checks as a feature branch.'],
        ['`promote/rel-xxxxx`', 'A promotion: each file the releases it carries changed, as it is in the stage\'s branch, into the next stop\'s branch.']
    ];
}

/**
 * The pipeline files packaged with the app (one static resource each). provider All: every provider needs it.
 * The GitHub workflow's name comes from the Git connection when the hub has one.
 */
export const PIPELINE_FILES = [
    {
        resource: 'RLY_Pipeline_GitHub', provider: 'GitHub', name: 'release-relay.yml', path: PIPE_FILE.GitHub,
        what: 'The GitHub Actions workflow: starts the jobs (raise, scan, validate, merge, deploy) when the hub asks, and tells the hub about each run for the Pipeline Monitor.'
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

const SETUP_NOTE = 'Pictures are simple drawings of each settings screen. The numbers in a picture match the numbered actions next to it. Menu names can differ slightly between releases.';
const EXAMPLE_NOTE = 'Org and branch names such as Dev, QA, Production, `dev`, `qa` and `prod` are examples only: use your own.';

/** Which setup stage each section is, for the "Next" buttons. */
const NEXT = {
    setup: { label: 'Next: B. Hub org', to: 'setup-hub' },
    'setup-hub': { label: 'Next: C. Git provider', to: 'setup-git' },
    'setup-git': { label: 'Next: D. Each org', to: 'setup-orgs' },
    'setup-orgs': { label: 'Next: E. Slack (optional)', to: 'setup-slack' },
    'setup-slack': { label: 'Next: F. Settings worth knowing', to: 'setup-settings' },
    'setup-settings': { label: 'Next: G. Nightly archive (optional)', to: 'setup-archive' },
    'setup-archive': { label: 'Next: H. Checklist', to: 'setup-checklist' }
};

function next(key) {
    return { type: 'links', links: [NEXT[key]] };
}

const SIGN_IN_PROBLEMS = [
    ['"Add … as a Remote Site Setting in the hub"', 'Setup → Remote Site Settings → New, with the org\'s My Domain URL exactly as in the org\'s Sign-in section (see B. Hub org, step 6).'],
    ['"Check Hub certificate: … must be the API name of a certificate in this hub"', 'Hub certificate on the org must be `release_relay`, the Unique Name of the certificate (B. Hub org, step 2).'],
    ['"Check Consumer key: it must be the consumer key of the External Client App in …"', 'Copy the Consumer Key again from that org\'s External Client App (D. Each org, step 3). Click the org\'s card under Connected orgs, press **Edit**, paste it into **Consumer key** and press **Save**.'],
    ['"Pre-authorize the integration user in …\'s External Client App"', 'Permitted Users = Admin approved users are pre-authorized, then add the integration user\'s profile or permission set (D. Each org, step 3).'],
    ['"Check the My Domain URL: the Login type is read from it…" or "This org is a sandbox: open it, press Edit and save…"', 'Login type is read from the My Domain URL and can\'t be picked. Check the URL: a sandbox\'s has `.sandbox.` in it (Setup → My Domain in that org). Fix the URL under **Edit**, then **Save**.'],
    ['"Check Integration username: it must be an active user in …"', 'Type the username exactly, and check the user is active in that org.'],
    ['"The org refused the login. Check that its External Client App has the JWT bearer flow on, the hub certificate uploaded, and the user pre-authorized."', 'Check the three things in the External Client App (D. Each org, steps 2 and 3). A new app can take a few minutes before it works.'],
    ['"Saved, but the sign-in didn\'t work yet: … Fix the details, then Check connection and next."', 'The org is saved but not signed in, and the window stays on Sign-in. Fix what the message names, then press **Check connection and next** again. Cancel keeps the org as saved, with the status Failed.'],
    ['"… is already the hub. There is only one hub: edit … instead." or "The hub keeps its role: there must always be one hub."', 'There is one hub only. Register this org with another role, or open the hub\'s card and edit it there.'],
    ['"Release Relay supports up to 10 orgs per hub."', 'The hub has 10 registered orgs. Remove one you no longer use before registering another.'],
    ['"The Org Id changed since the last check, so this sandbox was refreshed. The new Org Id is saved."', 'Nothing to fix: a note after a sandbox refresh. Check the sandbox still has the integration user and the External Client App (see After a sandbox refresh).']
];

/** Provider tabs for the steps that differ outside GitHub (GitHub's own steps are the numbered ones). */
const ON_GITHUB = ['Nothing more: the steps above are written for GitHub.'];
const OTHER_TOKENS = byProvider((p) => (p === 'GitHub' ? ON_GITHUB : TOKENS[p]));
const OTHER_LOGINS = byProvider((p) => (p === 'GitHub' ? ON_GITHUB : LOGINS[p]));

const SETUP_SECTIONS = [
    // ---------------- A. Before you start ----------------
    {
        key: 'setup',
        group: 'setup',
        label: 'A. Before you start',
        adminOnly: true,
        cards: [
            {
                key: 'setup-main',
                title: 'Set up Release Relay',
                aside: 'About 2 hours the first time, for a hub with 2 orgs',
                blocks: [
                    { type: 'text', paras: ['Release Relay runs in one org, the **hub** (your production org). The hub signs in to every other org itself, keeps its code in one Git repository, and runs a pipeline there to check and deploy. Setting it up means: a certificate and a few settings in the hub, a repository with the pipeline files, a sign-in app in each org, and (if you want) Slack.', 'Do the stages in order. Tick a stage when it is done: the ticks are kept in this browser only.'] },
                    {
                        type: 'checklist',
                        stages: [
                            { to: 'setup', label: 'A. Before you start', who: 'You', time: '10 min' },
                            { to: 'setup-hub', label: 'B. Hub org: permissions, certificate, remote sites, Git token', who: 'Salesforce admin + Git admin', time: '30 min' },
                            { to: 'setup-git', label: 'C. Git provider: repository, pipeline files, actions, environments', who: 'Git admin', time: '30 min' },
                            { to: 'setup-orgs', label: 'D. Each org: sign-in app, register on the Pipeline tab', who: 'Salesforce admin of each org', time: '15 min per org' },
                            { to: 'setup-slack', label: 'E. Slack (optional): app, channels, and Approve in Slack with a Site', who: 'Slack admin + Salesforce admin', time: '20 min, 45 with Approve in Slack' },
                            { to: 'setup-settings', label: 'F. Settings worth knowing', who: 'Salesforce admin', time: '10 min' },
                            { to: 'setup-archive', label: 'G. Nightly archive (optional): the scheduled job that keeps storage free', who: 'Git admin + Release Relay admin', time: '10 min' },
                            { to: 'setup-checklist', label: 'H. Check everything', who: 'Salesforce admin', time: '10 min' },
                            { to: 'secure', label: 'M. Secure your repository: token, environments, branches, run signing (once the first release works)', who: 'Release Relay admin + Git admin', time: '30 min' }
                        ]
                    },
                    {
                        type: 'table',
                        cols: ['Who you need', 'For'],
                        rows: [
                            ['A **Salesforce admin of the hub** (System Administrator)', 'Certificate, Remote Site Settings, Named Credentials, permission set groups, the Pipeline tab.'],
                            ['A **Salesforce admin of each other org** (developer orgs, test stages)', 'The sign-in app (External Client App) and an integration user in that org.'],
                            ['A **Git repository admin**', 'The repository, its branches, Actions settings, environments with secrets, and a token for the hub.'],
                            ['A **Slack workspace admin** (only if you use Slack)', 'Creating and installing the Slack app, and the channels.']
                        ]
                    },
                    {
                        type: 'list',
                        items: [
                            '**Have ready:** the My Domain URL of each org (Setup → My Domain, for example `https://your-domain.my.salesforce.com`, or `https://your-domain--qa.sandbox.my.salesforce.com` for a sandbox), and a list of the orgs on your route: developer orgs → test stages → production. A hub takes **at most 10 orgs**, the hub included.',
                            '**Never paste real secrets into tickets or chat.** Tokens, keystore passwords and consumer keys go only where these steps say. In this guide they are shown as placeholders such as `xoxb-…` or `github_pat_…`.',
                            'Release Relay runs releases on **GitHub** and **GitLab**. Bitbucket and Azure DevOps have pipeline files too (see Repository files), but running releases from the hub there comes in a later version; the differences are listed on the provider tabs in C. Git provider.',
                            'A hub has **one active Git connection** at a time. To move to another provider later, use the Migration tab (I. Move to another provider).'
                        ]
                    },
                    { type: 'note', text: SETUP_NOTE + ' ' + EXAMPLE_NOTE },
                    next('setup')
                ]
            }
        ]
    },

    // ---------------- B. Hub org ----------------
    {
        key: 'setup-hub',
        group: 'setup',
        label: 'B. Hub org',
        adminOnly: true,
        cards: [
            {
                key: 'sh-main',
                title: 'B. Hub org',
                aside: 'In the hub (your production org), as a Salesforce admin',
                blocks: [
                    { type: 'text', paras: ['Everything in this stage happens in the hub, except creating the Git token (in your Git provider).'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Give people their permission set group',
                                who: 'Salesforce admin',
                                where: 'Setup → Users → Permission Set Groups → (group) → Manage Assignments → Add Assignment',
                                goal: 'The tabs and buttons show only to people with the right group. One group per person, for their role.',
                                items: [
                                    'Admins of Release Relay: **Release Relay Admin** (it includes the deployment team, not Hotfix).',
                                    'Approvers: **Release Relay Approver**.',
                                    'Developers who raise releases: **Release Relay Developer**.',
                                    'People who do the manual steps, roll back and move data: **Release Relay Deployment Team**.',
                                    'People who only look (audit): **Release Relay Auditor**.',
                                    'A few people need more: add an **add-on** permission set on top of their group: **Release Relay Hotfix**, **Release Relay Production Approver**, **Release Relay Release Window Bypass**. Owners get **Release Relay Full Access** (every set and add-on).',
                                    'Give yourself **Release Relay Full Access** (or Admin) first, then reload the page.'
                                ],
                                check: 'The Release Relay app shows the Pipeline tab, and this Guide shows the Set up group.',
                                links: [{ label: 'Roles and access', to: 'access' }, { label: 'What each permission set gives', to: 'perms', kind: 'neutral' }]
                            },
                            {
                                title: 'Create the hub certificate',
                                who: 'Salesforce admin',
                                where: 'Setup → Certificate and Key Management → Create Self-Signed Certificate',
                                goal: 'The hub signs its logins to every org with this certificate. No passwords are stored.',
                                items: [
                                    'Label: `release_relay`.',
                                    'Unique Name: `release_relay` (exactly this, lower case).',
                                    'Tick **Exportable Private Key** (the pipeline needs the key too).',
                                    'Key Size: **2048**.',
                                    'Press **Save**.'
                                ],
                                check: 'The certificate page shows release_relay with Exportable Private Key: Yes.',
                                problems: [['"Check Hub certificate: … must be the API name of a certificate in this hub"', 'The Unique Name isn\'t `release_relay`, or the org card names another certificate.']],
                                shot: { ill: 'cert-create', cap: 'Create Self-Signed Certificate: label, unique name, exportable key, key size, Save.', alt: 'Drawing of the Create Self-Signed Certificate form with callouts 1 Label release_relay, 2 Unique Name release_relay, 3 Exportable Private Key ticked, 4 Key Size 2048, 5 Save.' }
                            },
                            {
                                title: 'Download the certificate (.crt)',
                                who: 'Salesforce admin',
                                where: 'Setup → Certificate and Key Management → release_relay',
                                goal: 'Each org you register trusts the hub by having this file uploaded in its sign-in app.',
                                items: ['Press **Download Certificate**. Keep the file `release_relay.crt`: you upload it in D. Each org.'],
                                check: 'A file release_relay.crt is in your downloads.',
                                shot: { ill: 'cert-download', cap: 'The certificate page: Download Certificate.', alt: 'Drawing of the release_relay certificate page with callout 1 on the Download Certificate button.' }
                            },
                            {
                                title: 'Export the keystore for the pipeline (.jks)',
                                who: 'Salesforce admin',
                                where: 'Setup → Certificate and Key Management → Export to Keystore',
                                goal: 'The pipeline signs in to the stage orgs with the same key. It reads it from the keystore file.',
                                items: [
                                    'Press **Export to Keystore**.',
                                    'Keystore Password: choose a strong password.',
                                    'Type it again in Confirm Keystore Password.',
                                    'Press **Export**. You get a `.jks` file; rename it `release_relay.jks` if you like.'
                                ],
                                text: ['The password becomes the secret `SF_JKS_PASSWORD`, the file (as base64 text) becomes `SF_JKS`, and the certificate\'s Unique Name `release_relay` becomes the variable `SF_JKS_ALIAS` (C. Git provider, steps 7 and 8). Store the file and password in your password manager, not in email.'],
                                check: 'A .jks file is in your downloads.',
                                shot: { ill: 'keystore-export', cap: 'Export to Keystore: password twice, then Export.', alt: 'Drawing of the Certificate and Key Management page with callouts 1 Export to Keystore, 2 Keystore Password, 3 Confirm Keystore Password, 4 Export.' }
                            },
                            {
                                title: 'Find each org\'s My Domain URL',
                                who: 'Salesforce admin of each org',
                                where: 'Each org: Setup → My Domain',
                                goal: 'The hub calls each org at this address.',
                                items: [
                                    'Copy the **Current My Domain URL** of every org on your route, the hub included.',
                                    'Write it with `https://` in front, for example `https://your-domain.my.salesforce.com` or `https://your-domain--qa.sandbox.my.salesforce.com` (examples).'
                                ]
                            },
                            {
                                title: 'Add a Remote Site Setting per org',
                                who: 'Salesforce admin',
                                where: 'Setup → Security → Remote Site Settings → New Remote Site',
                                goal: 'Salesforce blocks calls to other addresses unless they are listed here.',
                                items: [
                                    'Remote Site Name: a name you recognize, for example `RLY_Org_QA` (example).',
                                    'Remote Site URL: the org\'s My Domain URL.',
                                    'Leave **Active** ticked.',
                                    'Press **Save**. Repeat for every org you will register, **the hub\'s own My Domain included**.'
                                ],
                                text: ['Git and Slack need no Remote Site: the hub reaches them through Named Credentials (`RLY_Git_GitHub`, `RLY_Git_GitLab`, `RLY_Slack`).'],
                                check: 'Remote Site Settings lists one active row per org.',
                                problems: [['"Add https://… as a Remote Site Setting in the hub"', 'The URL is missing or different (http vs https, a typo, the old instance URL instead of My Domain). It must match the org card\'s My Domain URL.']],
                                shot: { ill: 'remote-site', cap: 'Remote Site Edit: name, URL, Active, Save.', alt: 'Drawing of the Remote Site Edit form with callouts 1 Remote Site Name, 2 Remote Site URL, 3 Active, 4 Save.' }
                            },
                            {
                                title: 'Create the Git token for the hub',
                                who: 'Git admin',
                                where: 'Your Git provider → your profile picture → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token',
                                goal: 'The hub reads branches, commits releases, starts the pipeline and opens pull requests with this token.',
                                items: [
                                    'Create it on a dedicated bot account (or use a GitHub App), not a person\'s own account, so it keeps working when people leave (see Roles and access).',
                                    'Token name: for example `Release Relay hub` (example).',
                                    'Expiration: as your company allows. To renew it later, see M. Secure your repository, step 2.',
                                    'Resource owner: the account or organization that owns the repository.',
                                    'Repository access: **Only select repositories** → your repository.',
                                    'Repository permissions: each one in the table in **M. Secure your repository**, step 1 (the button under this step opens it), with what each is for.',
                                    'Press **Generate token** and copy it (`github_pat_…`). It is shown once.'
                                ],
                                text: ['If an organization owns the repository, an owner may have to approve the token.'],
                                check: 'The token shows under Fine-grained tokens with access to one repository.',
                                problems: [
                                    ['"… failed with HTTP 401. The token in Named Credential RLY_Git_GitHub was refused"', 'The token expired, was revoked or was pasted wrongly. Regenerate it and paste it again (M. Secure your repository, step 2).'],
                                    ['"… failed with HTTP 403. The token lacks permission for this"', 'Add the missing permission to the token (M. Secure your repository, step 1). Organization-owned repositories may also need the token approved.'],
                                    ['"… failed with HTTP 404. Not found: check the repository name and that the token can see it"', 'Repository on the Git connection must be `owner/repository`, and the token must include that repository.'],
                                    ['"The token needs Workflows: Read and write to change files in .github/workflows."', 'Edit the token: Workflows → Read and write.']
                                ],
                                shot: { ill: 'gh-token', cap: 'New fine-grained token: name, expiry, owner, one repository, its permissions, Generate. The full list of permissions is in M. Secure your repository, step 1.', alt: 'Drawing of the new fine-grained token form with callouts 1 Token name, 2 Expiration, 3 Resource owner, 4 Only select repositories, 5 the permission table Actions, Contents, Pull requests, Workflows read and write and Metadata read-only, 6 Generate token.' },
                                links: [{ label: 'M. Secure your repository: token permissions', to: 'secure', kind: 'neutral' }]
                            },
                            {
                                title: 'Not on GitHub? Your provider\'s token',
                                who: 'Git admin',
                                goal: 'The other providers use their own kind of token and Named Credential.',
                                items: ['Only if your repository isn\'t on GitHub. Pick your provider:'],
                                providers: OTHER_TOKENS
                            },
                            {
                                title: 'Paste the token into its Named Credential\'s principal',
                                who: 'Salesforce admin',
                                where: 'Setup → Named Credentials → External Credentials → RLY_Git_GitHub → Principals → Edit',
                                goal: 'Release Relay comes with the External Credential and the Named Credential RLY_Git_GitHub. Salesforce stores the token encrypted; no page or person can read it back.',
                                items: [
                                    'Open External Credential `RLY_Git_GitHub` (it comes with Release Relay).',
                                    'Under **Principals**, on `RLY_Git_GitHub` press Edit.',
                                    'Under Authentication Parameters: Name `Token`, Value: the token (`github_pat_…`).',
                                    'Press **Save**.'
                                ],
                                text: ['On GitLab, paste the project access token into `RLY_Git_GitLab` the same way. Access to both comes with `RLY_Access`, part of every Release Relay group.'],
                                check: 'External Credential RLY_Git_GitHub has the principal RLY_Git_GitHub with the parameter Token.',
                                shot: { ill: 'gh-extcred', cap: 'External Credential RLY_Git_GitHub: principal RLY_Git_GitHub, parameter Token.', alt: 'Drawing of an External Credential form with callouts 1 the credential\'s name, 2 Authentication Protocol Custom, 3 the principal, 4 authentication parameter Token with the token value, 5 Save.' }
                            },
                            {
                                title: 'Look at the Named Credential RLY_Git_GitHub',
                                who: 'Salesforce admin',
                                where: 'Setup → Named Credentials → Named Credentials tab → RLY_Git_GitHub',
                                goal: 'Release Relay calls `callout:RLY_Git_GitHub`. It comes with Release Relay: nothing to create.',
                                items: [
                                    'Label and Name: `RLY_Git_GitHub`.',
                                    'URL: `https://api.github.com`, **Enabled for Callouts** on.',
                                    'External Credential: `RLY_Git_GitHub`.',
                                    '**Generate Authorization Header** off, **Allow Formulas in HTTP Header** on.',
                                    'Custom Header `Authorization`: `Bearer {!$Credential.RLY_Git_GitHub.Token}`.',
                                    'Nothing to change: press Cancel.'
                                ],
                                check: 'The Named Credential shows URL https://api.github.com and one custom header, Authorization.',
                                shot: { ill: 'gh-namedcred', cap: 'Named Credential RLY_Git_GitHub with its Authorization header.', alt: 'Drawing of a Named Credential form with callouts 1 the credential\'s name, 2 URL https://api.github.com, 3 its External Credential, 4 Generate Authorization Header unticked, 5 Allow Formulas in HTTP Header ticked, 6 custom header Authorization, 7 Save.' }
                            },
                            {
                                title: 'Let Release Relay users use the token',
                                who: 'Salesforce admin',
                                where: 'Setup → Permission Sets → (a permission set) → External Credential Principal Access → Edit',
                                goal: 'Raising, approving and promoting call Git as the person who presses the button, so each of them needs access to the principal.',
                                items: [
                                    'Nothing to do: `RLY_Git_GitHub - RLY_Git_GitHub`, `RLY_Git_GitLab - RLY_Git_GitLab` and `RLY_Slack - Bot` are already Enabled in `RLY_Access`, which is in every Release Relay group. The role permission sets (`RLY_Admin`, `RLY_Deploy_Team`, `RLY_Developer`, `RLY_Approver`) hold them too.',
                                    'Only if people use Release Relay through another permission set: add the same principals there. Don\'t add your own principals (such as `RLY_Org_Self`) to `RLY_Access`: deploying Release Relay replaces that set\'s principal list.'
                                ],
                                check: 'Pipeline → Connection & route → 1 · Where the code lives → Check connection shows Connected (after step 12).',
                                problems: [['"Named Credential RLY_Git_GitHub wasn\'t found or you can\'t use it. Check it exists, and that your permission set has its principal under External Credential Principal Access."', 'Do this step for the user who saw it, and check the Named Credential\'s name.']],
                                shot: { ill: 'perm-principal', cap: 'External Credential Principal Access: RLY_Git_GitHub - RLY_Git_GitHub is Enabled in the Release Relay permission sets.', alt: 'Drawing of the External Credential Principal Access edit page with callouts 1 the Git principal in Enabled, 2 Save.' }
                            },
                            {
                                title: 'Connect the repository on the Pipeline tab',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Connection & route → 1 · Where the code lives → Edit',
                                goal: 'One active Git connection for the whole pipeline.',
                                items: [
                                    'Provider: **GitHub** or **GitLab** (Bitbucket and Azure DevOps: pipeline files only, for now).',
                                    'Repository: `owner/repository`.',
                                    'Workflow file: `release-relay.yml`.',
                                    'Pipeline branch: `main` (where the pipeline files live).',
                                    'Named Credential (token): `RLY_Git_GitHub`.',
                                    'Source path: `force-app/main/default`.',
                                    '**Code scan on every pull request**: on (the default) or off. Each org can follow it or set its own (D. Each org).',
                                    'Press **Save**: it tests the connection. **Check connection** on the card tests it again later.',
                                    'A new hub\'s first Git connection also turns on **Production approval needs the add-on** (F. Settings worth knowing).',
                                    'To change provider later, don\'t edit the connection: **Move to another provider…** under the card opens the Migration tab (I. Move to another provider).'
                                ],
                                text: ['First time in a new hub? The Pipeline tab opens **Set up Release Relay**, a short walk-through: 1 This org is the hub, 2 Git connection, 3 Pipeline files, 4 Add orgs, 5 Slack (optional). Each step is checked before **Check and continue** goes on; **Do this later** hides it, and the header button **Set up Release Relay** opens it again. It fills in the same records as this step and the next one.'],
                                check: 'The card shows Connected and lists what it checked.',
                                problems: [
                                    ['Git connection: check failed', 'Read the list on the card: a token permission, the repository name, or the pipeline files missing on the pipeline branch (C. Git provider, step 2).'],
                                    ['"No Git connection yet. Press Edit to choose the provider and repository."', 'Nothing is saved yet: press **Edit**.']
                                ],
                                shot: { ill: 'pipeline-git', cap: 'Edit Git connection: provider, repository, workflow file, branch, credential, path, Save.', alt: 'Drawing of the Edit Git connection window with callouts 1 Provider, 2 Repository, 3 Workflow file, 4 Pipeline branch, 5 Named Credential, 6 Source path, 7 Save.' }
                            },
                            {
                                title: 'Register the hub as production',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Register org (page header)',
                                goal: 'Releases deploy to production through the hub\'s own record, and the hub knows which org is the real hub (sandbox copies are refused).',
                                items: [
                                    'Org name: for example `Production` (an example).',
                                    'Role: **Hub (this org, production)**. There is one hub only: once it is registered, Hub is no longer offered for other orgs, and the hub\'s own Role box is grey (it keeps its role).',
                                    'My Domain URL: the hub\'s own. **Login type** and **Salesforce environment** then turn grey: the hub signs in as production, and its environment is Production.',
                                    'Branch and Git environment: for example `prod`. The pipeline\'s hub jobs (nightly archive, Pipeline Monitor, Slack reminders) use the environment `prod` unless the repository variable `RELAY_HUB_ENVIRONMENT` names another. Fill the sign-in fields as in D. Each org: the hub needs its own External Client App too.',
                                    'Press **Check connection and next**, then set the hub\'s Approval (Never isn\'t offered for production).'
                                ],
                                text: ['In Set up Release Relay, step 1 does the same: it reads the hub\'s My Domain and Org Id itself, and asks for the org name, integration username, consumer key, certificate, branch and Git environment.'],
                                check: 'Pipeline → Orgs → the Production tab: the hub\'s card shows Connected with the role Hub, and the tab says "Production holds one org: the hub. Register other orgs on their sandbox tab."',
                                links: [{ label: 'D. Each org: the sign-in app', to: 'setup-orgs' }],
                                shot: { ill: 'hub-register', cap: 'Register the hub: role Hub, its own My Domain, its branch.', alt: 'Drawing of Register an org for the hub with callouts 1 Org name, 2 Role Hub, 3 My Domain URL, 4 Branch and Git environment.' }
                            },
                            {
                                title: 'Give sign-ins room in Platform Cache',
                                who: 'Salesforce admin',
                                where: 'Setup → Platform Cache → RlyTokens → Edit',
                                goal: 'The hub keeps each org\'s sign-in for 15 minutes and shares it between everyone using Release Relay, instead of signing in again on every page. With many users this keeps the hub well under Salesforce\'s sign-in limits.',
                                items: [
                                    'The partition `RlyTokens` comes with Release Relay, with no space yet.',
                                    'Under **Org Cache Allocation**, give it **1 MB** (plenty: a sign-in takes well under 1 KB). Session cache: 0.',
                                    'Press **Save**.'
                                ],
                                text: ['No free Platform Cache in your org (some editions have none)? Release Relay still works: it signs in once per request, as before. With 50 or more people using it daily, ask Salesforce for Platform Cache capacity.'],
                                check: 'Platform Cache lists RlyTokens with 1 MB of org cache.'
                            }
                        ]
                    },
                    next('setup-hub')
                ]
            }
        ]
    },

    // ---------------- C. Git provider ----------------
    {
        key: 'setup-git',
        group: 'setup',
        label: 'C. Git provider',
        adminOnly: true,
        cards: [
            {
                key: 'sg-main',
                title: 'C. Git provider',
                aside: 'In your Git provider, as a repository admin',
                blocks: [
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Create the repository and its pipeline branch',
                                who: 'Git admin',
                                where: 'Your Git provider → New repository',
                                goal: 'One private repository holds every org\'s metadata and the pipeline.',
                                items: [
                                    'Create a **private** repository.',
                                    'Its default branch, usually `main`, is the **pipeline branch**: it holds the pipeline files and is never deployed.',
                                    'Add `sfdx-project.json` and the folder `force-app/main/default` (your metadata goes there).'
                                ],
                                check: 'The repository opens on main with sfdx-project.json in it.'
                            },
                            {
                                title: 'Put the pipeline files on the pipeline branch',
                                who: 'Git admin',
                                where: 'Guide → Repository files → Download, or Pipeline → Connection & route → Update pipeline files',
                                goal: 'The pipeline does the work: convert, open the pull request, scan, check-only deploy, merge, deploy.',
                                items: [
                                    'Download the workflow (`release-relay.yml`) and the script (`release-relay.js`) from Repository files.',
                                    'Commit them to `main` at `.github/workflows/release-relay.yml` and `scripts/release-relay.js`.',
                                    'Or, once the Git connection works: Pipeline → Connection & route → **Update pipeline files** opens a pull request with them (it needs the token\'s Workflows permission).'
                                ],
                                check: 'The repository\'s Actions tab lists the workflow Release Relay.',
                                links: [{ label: 'Repository files: download', to: 'repo' }]
                            },
                            {
                                title: 'Let workflows push and open pull requests',
                                who: 'Git admin',
                                where: 'Repository → Settings → Actions → General → Workflow permissions',
                                goal: 'The pipeline pushes the release branch and the results with the workflow\'s own token.',
                                items: [
                                    'Choose **Read and write permissions**.',
                                    'Tick **Allow GitHub Actions to create and approve pull requests**.',
                                    'Press **Save**.'
                                ],
                                check: 'Both settings stay selected after a reload.',
                                problems: [['"Couldn\'t save the … result to the release-relay-results branch. The pipeline needs permission to push a new branch, and the branch must not be protected."', 'Do this step, and remove any branch protection rule that matches `release-relay-results`.']],
                                shot: { ill: 'gh-actions', cap: 'Workflow permissions: read and write, allow pull requests, Save.', alt: 'Drawing of the Actions general settings with callouts 1 Read and write permissions, 2 Allow GitHub Actions to create and approve pull requests, 3 Save.' }
                            },
                            {
                                title: 'Create the org branches',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Connection & route → 2 · Route → Create missing branches',
                                goal: 'Each org has its own branch: stages (for example `qa`, `prod`) and each developer org (for example `dev`).',
                                items: [
                                    'Register the orgs first (D. Each org), each with its branch.',
                                    'Open **Connection & route** and, under **2 · Route**, press **Create missing branches**: every route branch your repository doesn\'t have yet is made from the pipeline branch. The button shows once the Git connection is saved.',
                                    '`release-relay-results` (the step results) is created by the pipeline on its first run, and `release-relay-snapshots` (rollback snapshots) on the first deploy. Don\'t protect them.',
                                    'Only if you update Release Relay itself through the pipeline: a branch `release-relay-hub`, made from `main`, for the hub\'s own updates.'
                                ],
                                check: 'The route shows no missing branches ("Every route branch already exists").'
                            },
                            {
                                title: 'Create an environment per org',
                                who: 'Git admin',
                                where: 'Repository → Settings → Environments → New environment',
                                goal: 'An environment holds one org\'s login for the pipeline. The pipeline picks it by the org\'s Git environment name.',
                                items: [
                                    'Name: the org\'s **Git environment** (Pipeline → Orgs → the org), for example `qa` or `prod`. Press Configure environment.',
                                    'Required reviewers: optional. **Recommended on production\'s environment for real use**: GitHub then waits for a reviewer before each job there (the check-only deploy too).',
                                    'Deployment branches and tags: **Selected branches** → add `main`.',
                                    'Add the four secrets (step 7), and later the run-signing key `RELAY_RUN_KEY` (K. Security).',
                                    'Add the variables (step 8).'
                                ],
                                text: ['Create one for every stage and production, and for back promote orgs. Developer orgs need none: the hub reads them itself. Pipeline files version 27 also use an environment `relay-signing` for the jobs that have no org (L. Pipeline security).'],
                                check: 'Settings → Environments lists one environment per stage org.',
                                shot: { ill: 'gh-env', cap: 'An environment: name, reviewers, branches, secrets and variables.', alt: 'Drawing of a repository environment with callouts 1 name, 2 Required reviewers, 3 Selected branches main, 4 Add environment secret with SF_USERNAME, SF_CLIENT_ID, SF_JKS, SF_JKS_PASSWORD, 5 Add environment variable with SF_INSTANCE_URL and SF_JKS_ALIAS.' }
                            },
                            {
                                title: 'Not on GitHub? Where the logins go',
                                who: 'Git admin',
                                goal: 'Same names and values, kept the way your provider keeps secrets.',
                                items: ['Only if your repository isn\'t on GitHub. Pick your provider:'],
                                providers: OTHER_LOGINS
                            },
                            {
                                title: 'Add the secrets to each environment',
                                who: 'Git admin',
                                where: 'Settings → Environments → (environment) → Environment secrets → Add environment secret',
                                goal: 'How the pipeline signs in to that org. Secrets can\'t be read back.',
                                items: [
                                    '`SF_USERNAME`: the org\'s integration user\'s username.',
                                    '`SF_CLIENT_ID`: the Consumer Key of that org\'s External Client App (D. Each org, step 3).',
                                    '`SF_JKS`: the keystore from B. Hub org, step 4, as base64 on one line. Mac: `base64 -i release_relay.jks`; Linux: `base64 -w0 release_relay.jks`; Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("release_relay.jks"))`.',
                                    '`SF_JKS_PASSWORD`: the keystore password.'
                                ],
                                text: ['Instead of the three `SF_JKS*` you may use `SF_JWT_KEY` (the PEM private key, base64 on one line).'],
                                check: 'Environment secrets lists the four names. Names are exact, in capitals.',
                                problems: [['"SF_JKS is set, so SF_JKS_PASSWORD (secret) and SF_JKS_ALIAS (variable) are needed too."', 'Add the missing one to that environment.'], ['"Couldn\'t read the key from SF_JKS. Check SF_JKS_PASSWORD, and that SF_JKS_ALIAS is the certificate\'s Unique Name."', 'Encode the file again on one line, check the password, and set SF_JKS_ALIAS to `release_relay`.']]
                            },
                            {
                                title: 'Add the variables to each environment',
                                who: 'Git admin',
                                where: 'Settings → Environments → (environment) → Environment variables → Add environment variable',
                                goal: 'Plain settings the pipeline reads for that org.',
                                items: [
                                    '`SF_INSTANCE_URL`: the org\'s My Domain URL, for example `https://your-domain.my.salesforce.com`.',
                                    '`SF_JKS_ALIAS`: `release_relay` (the certificate\'s Unique Name).'
                                ],
                                text: ['Optional: `DEPLOY_TEST_LEVEL` (default `RunLocalTests`; the release\'s own test list wins), `ORG_LABEL` and `ALLOWED_TARGETS` (only for runs not started by the hub), `SOURCE_PATH` (default `force-app/main/default`).'],
                                check: 'Environment variables lists SF_INSTANCE_URL and SF_JKS_ALIAS.'
                            },
                            {
                                title: 'The exclude list (nothing to do)',
                                who: 'Git admin',
                                where: 'Repository → main → .relay/exclude',
                                goal: 'Release Relay\'s own components never travel to your orgs through a normal release.',
                                items: [
                                    'The pipeline knows Release Relay\'s own components by exact name, so your own classes are deployed even when their names start with "Rly".',
                                    'To keep other files out of every release, add one line each to `.relay/exclude` (optional).',
                                    'A release whose every file is on the list fails with "Nothing was deployed" instead of showing Deployed.'
                                ]
                            }
                        ]
                    },
                    next('setup-git')
                ]
            }
        ]
    },

    // ---------------- D. Each org ----------------
    {
        key: 'setup-orgs',
        group: 'setup',
        label: 'D. Each org',
        adminOnly: true,
        cards: [
            {
                key: 'so-main',
                title: 'D. Each org you deploy to or read from',
                aside: 'Repeat for every org: developer orgs, stages, and the hub itself',
                blocks: [
                    { type: 'text', paras: ['The hub signs in to each org with a JWT signed by its certificate. Each org needs an integration user and a sign-in app (an External Client App; an older Connected App works the same way) that trusts the hub certificate.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Create an integration user',
                                who: 'Salesforce admin of the org',
                                where: 'The org: Setup → Users → New User',
                                goal: 'The hub and the pipeline act in the org as this user.',
                                items: [
                                    'A user (often a Salesforce Integration license, or a spare admin user) with a profile or permission set that has **API Enabled**, **View Setup and Configuration** and **Modify Metadata Through Metadata API Functions**.',
                                    'Add **Manage Flow** if releases should activate flows in this org.',
                                    'Note its username, for example `relay@yourorg.dev` (example).'
                                ],
                                check: 'The user is active.'
                            },
                            {
                                title: 'Create the sign-in app (External Client App)',
                                who: 'Salesforce admin of the org',
                                where: 'The org: Setup → External Client App Manager → New External Client App',
                                goal: 'The app lets the hub sign in without a password, using the hub certificate.',
                                items: [
                                    'External Client App Name: for example `Release Relay Hub`.',
                                    'Contact Email: yours. Distribution State: Local.',
                                    'Under API (Enable OAuth Settings) tick **Enable OAuth**.',
                                    'Callback URL: `https://login.salesforce.com/services/oauth2/success` (required by the form, not used by the hub).',
                                    'OAuth scopes: **Manage user data via APIs (api)** and **Perform requests at any time (refresh_token, offline_access)**.',
                                    'Under Flow Enablement tick **Enable JWT Bearer Flow**.',
                                    'Upload the hub certificate `release_relay.crt` (B. Hub org, step 3).',
                                    'Press **Create**.'
                                ],
                                check: 'The app opens with OAuth and JWT Bearer Flow on.',
                                shot: { ill: 'eca-oauth', cap: 'New External Client App: OAuth on, two scopes, JWT bearer flow with the hub certificate.', alt: 'Drawing of the New External Client App form with callouts 1 app name, 2 contact email, 3 Enable OAuth, 4 Callback URL, 5 scopes api and refresh_token offline_access, 6 Enable JWT Bearer Flow, 7 upload release_relay.crt, 8 Create.' }
                            },
                            {
                                title: 'Pre-authorize the integration user',
                                who: 'Salesforce admin of the org',
                                where: 'The org: External Client App Manager → Release Relay Hub → Policies → Edit',
                                goal: 'With the JWT flow nobody clicks Allow, so the org must already trust the user.',
                                items: [
                                    'OAuth Policies → Permitted Users: **Admin approved users are pre-authorized**.',
                                    'App Policies: add the integration user\'s **profile** or a **permission set** it has.',
                                    'Press **Save**.',
                                    'Settings tab → OAuth Settings → **Consumer Key and Secret** → copy the **Consumer Key** (Salesforce may ask for a verification code).'
                                ],
                                text: ['A new app can take a few minutes before sign-in works.'],
                                check: 'Policies show Admin approved users are pre-authorized and the profile or permission set.',
                                shot: { ill: 'eca-policies', cap: 'Policies: admin-approved users, the user\'s profile, then copy the consumer key.', alt: 'Drawing of the External Client App policies with callouts 1 Permitted Users admin approved users are pre-authorized, 2 profile or permission set, 3 Save, 4 Consumer Key and Secret.' }
                            },
                            {
                                title: 'Check the Remote Site in the hub',
                                who: 'Salesforce admin of the hub',
                                where: 'Hub: Setup → Remote Site Settings',
                                goal: 'The hub can only call orgs listed there.',
                                items: ['Make sure the org\'s My Domain URL is listed and active (B. Hub org, step 6).'],
                                links: [{ label: 'B. Hub org: Remote Site Settings', to: 'setup-hub' }]
                            },
                            {
                                title: 'Register the org on the Pipeline tab',
                                who: 'Release Relay admin',
                                where: 'Hub: Release Relay → Pipeline → Register org (page header), or + Register an org on an environment tab under Orgs (opens a window)',
                                goal: 'The hub saves how to reach the org and where it sits on the route.',
                                items: [
                                    'Org name: a short name people know, for example `QA` or `Dev` (examples).',
                                    'A hub has at most 10 registered orgs, the hub included: the eleventh is refused with "Release Relay supports up to 10 orgs per hub."',
                                    'Role: **Developer org** (people build here; the label says which branch it raises into), **Stage (an org on the route)** or **Back promote (after production)**. **Hub (this org, production)** is offered only until the hub is registered (B. Hub org).',
                                    'My Domain URL: the org\'s, with `https://`.',
                                    'Login type: read from the My Domain URL and grey. A URL with `.sandbox.` is **Sandbox**; any other is **Production or Developer Edition**.',
                                    'Salesforce environment: follows the login type. A sandbox login: pick the sandbox type (**Developer sandbox or Developer Edition**, **Developer Pro sandbox**, **Partial Copy sandbox**, **Full Copy sandbox**). A production login that isn\'t the hub is a Developer Edition org, so it is set to **Developer sandbox or Developer Edition** and grey. Production belongs to the hub alone. New Release and Connected orgs group the orgs by it.',
                                    'Integration username: from step 1.',
                                    'Consumer key: from step 3. It is saved encrypted and never shown again.',
                                    'Hub certificate: `release_relay`.',
                                    'Branch: the org\'s branch, for example `qa` or `dev` (examples).',
                                    'Git environment: the environment holding its login (C. Git provider, step 5), usually the same as the branch.',
                                    'The fields start empty: the grey text in each is an example only. Press **Check connection and next**: it saves, signs in and reads the Org Id, sandbox name and Metadata API version.',
                                    'The window then shows the org\'s next steps one at a time: **Approval** (stages and the hub), **Back promote** (back promote orgs) and **Slack** (once Slack is set up), each with **Save and next** or **Save and finish**. **Skip** goes on without changing that step (approval Always, approved in Salesforce, no Slack channel).'
                                ],
                                check: 'The window closes, and Pipeline → Orgs shows the org\'s environment tab with its card lit up, Connected.',
                                problems: SIGN_IN_PROBLEMS,
                                shot: { ill: 'register-org', cap: 'Register an org: the things to fill in, then Check connection and next.', alt: 'Drawing of the Register an org window with callouts 1 Org name, 2 Role, 3 Salesforce environment, 4 My Domain URL, 5 Login type, 6 Integration username, 7 Consumer key, 8 Hub certificate, 9 Branch, 10 Git environment, 11 Check connection and next.' }
                            },
                            {
                                title: 'Choose its code scan',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Orgs → click the org → Edit → Approval',
                                goal: 'Stages and the hub can scan more, or less, than the Git connection does.',
                                items: [
                                    '**Code scan for releases into** the org: **Follow the Git connection** (the default; it says whether that is on or off now), **Always scan**, or **Don\'t scan** (to move faster).',
                                    'Press **Save**. The org\'s card shows it, for example **Always · Code scan: Follows Git (on)**.'
                                ],
                                text: ['Developer orgs and back promote orgs have no Approval step, so no code scan choice: releases are scanned on the way into a stage.']
                            },
                            {
                                title: 'Check connection any time',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Orgs → click the org → Check connection',
                                goal: 'Proves the hub can still sign in (after a sandbox refresh, a new certificate or a changed user).',
                                items: ['Click the org\'s card and press **Check connection** in its window. On a failure the Sign-in section names the fix (table above).'],
                                check: 'Connected, with the time it was checked.'
                            },
                            {
                                title: 'After a sandbox refresh',
                                who: 'Salesforce admin of the sandbox',
                                where: 'The refreshed sandbox',
                                goal: 'A refresh copies production\'s setup, so the sandbox\'s app and user may change.',
                                items: [
                                    'Check the integration user is active in the sandbox, and the External Client App is there with the hub certificate.',
                                    'If the consumer key changed: Pipeline → Orgs → click the org → **Edit** → paste it into **Consumer key** → **Save** (a changed sign-in is checked again). The next check notes the new Org Id by itself.'
                                ]
                            }
                        ]
                    },
                    next('setup-orgs')
                ]
            }
        ]
    },

    // ---------------- E. Slack ----------------
    {
        key: 'setup-slack',
        group: 'setup',
        label: 'E. Slack (optional)',
        adminOnly: true,
        cards: [
            {
                key: 'ss-main',
                title: 'E. Slack (optional)',
                aside: 'Skip this if you don\'t use Slack: everything works without it',
                blocks: [
                    { type: 'text', paras: [
                        'With Slack each release posts **one card** in its target org\'s channel: a header with the release number and title, the card, and a divider under it, so each release stands on its own. The card is edited as the release moves, and each step (pull request, checks, approval, deploy) is a reply in the card\'s **thread**. Steps 1 to 6 set this up; step 7 adds reminders and alerts.',
                        'Approving from the card is a further, optional part (steps 8 to 16). Slack sends each Approve or Reject press to a public **Salesforce Site** in the hub, so it needs a Site, its guest user\'s access, and Slack\'s Interactivity pointed at it. Do those steps in order.',
                        'The card always shows the release\'s current state (approved, waiting for manual steps, deploying, deployed, failed, rejected); the events you tick only choose the extra messages (thread replies and new posts). There is no background job: the hub notices a deploy finishing when someone has Release Relay open (its pages keep checking), and then updates the card.'
                    ] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Create the Slack app',
                                who: 'Slack admin',
                                where: 'Slack app settings (api.slack.com/apps) → Create New App → From scratch',
                                goal: 'One app for the whole hub; it posts as itself.',
                                items: ['App Name: for example `Release Relay`. Pick your workspace. Press **Create App**.']
                            },
                            {
                                title: 'Give it the bot scopes and install it',
                                who: 'Slack admin',
                                where: 'Your app → OAuth & Permissions',
                                goal: 'The app may post and update messages, and look people up by email so approvers are linked to Slack by their SSO sign-in. Nothing more.',
                                items: [
                                    'Scopes → Bot Token Scopes → Add an OAuth Scope → `chat:write`, then `users:read` and `users:read.email`.',
                                    'OAuth Tokens → **Install to Workspace** → Allow.',
                                    'Copy the **Bot User OAuth Token** (`xoxb-…`).',
                                    'App installed before? Add `users:read` and `users:read.email` the same way, then **Reinstall to Workspace** (Slack shows a yellow banner asking for it) → Allow. If Slack shows a new bot token, paste it on the Pipeline tab (Slack connection → Edit → Bot token).'
                                ],
                                text: ['A Slack workspace admin may have to approve the reinstall. Without `users:read.email` nobody can be matched by SSO or email; links already saved keep working.'],
                                check: 'The page shows a Bot User OAuth Token starting xoxb-, and Bot Token Scopes lists chat:write, users:read and users:read.email. Later, Pipeline → Approvals & Slack → Slack connection → Edit → Approvers shows ✓ for all three.',
                                problems: [['"Slack app is missing users:read.email — add it and reinstall."', 'Add the scope here, press **Reinstall to Workspace**, and paste the bot token again if Slack shows a new one. The same message for `users:read`: add that one too.']],
                                shot: { ill: 'slack-scopes', cap: 'OAuth & Permissions: the bot token scopes, install, copy the bot token.', alt: 'Drawing of the Slack app OAuth and Permissions page with callouts 1 bot token scope chat:write, 2 Install to Workspace, 3 copy Bot User OAuth Token.' }
                            },
                            {
                                title: 'Switch Slack on and save the bot token',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Approvals & Slack → Slack connection → Edit',
                                goal: 'The hub posts through the Named Credential `RLY_Slack` (installed with Release Relay); the token goes into its credential store.',
                                items: [
                                    'Open **Approvals & Slack** and press **Edit** on the Slack connection.',
                                    'Switch **Slack** on. Off stops every message; nothing else changes.',
                                    '**Bot token (starts with xoxb-)**: paste the bot token. It is never shown again.',
                                    'Under **Send a message when a release is**, tick the events: Ready for approval, Checks failed, Deployed, Deploy failed, Rejected, Raised.',
                                    'Press **Save and test**: it saves, then checks the token and shows your workspace name. It also records the workspace, so button presses from any other Slack workspace are refused.'
                                ],
                                text: ['Until Slack answers, the card shows a checklist: Slack app created, Bot token saved, Check connection, Pick a channel per org. **Check connection** on the card checks again at any time.'],
                                check: 'The Slack connection shows Connected and the workspace name.',
                                problems: [
                                    ['"A bot token starts with xoxb- and has no spaces: copy the Bot User OAuth Token again (Slack app → OAuth & Permissions)."', 'Copy the Bot User OAuth Token again, not the signing secret or the client secret.'],
                                    ['"Slack settings saved. The bot token goes in Setup: see the Slack connection card."', 'This org doesn\'t let the page keep the token: do the next step.'],
                                    ['Slack: Not set up or Error', 'The token is missing or wrong: paste it again (or do the next step).']
                                ]
                            },
                            {
                                title: 'Only if asked: put the bot token in Setup',
                                who: 'Salesforce admin',
                                where: 'Setup → Named Credentials → External Credentials tab → RLY Slack → Principals',
                                goal: 'The same token, saved by hand when the Slack connection card says "Put the bot token in Setup → Named Credentials → External Credentials → RLY_Slack → Principals → Bot → Token."',
                                items: [
                                    'Press **Open Named Credentials** on the card, or go there in Setup.',
                                    'On the principal **Bot** open Actions ▾ → **Edit**.',
                                    'Authentication Parameters → Add: Name `Token` (exactly), Value: the bot token `xoxb-…`.',
                                    'Press **Save**. Then on the Pipeline tab press **Check connection** on the Slack connection.'
                                ],
                                text: ['Access to this principal is already in `RLY_Access` (in every Release Relay group), the role permission sets and `RLY_Slack_Site`. If people use other permission sets, add `RLY_Slack - Bot` under External Credential Principal Access there.'],
                                check: 'The Bot principal lists the parameter Token, and the Slack connection shows Connected.',
                                shot: { ill: 'ext-cred-slack', cap: 'RLY_Slack: principal Bot → parameter Token = the bot token.', alt: 'Drawing of the RLY Slack external credential with callouts 1 Edit on principal Bot, 2 parameter name Token, 3 value xoxb placeholder, 4 Save.' }
                            },
                            {
                                title: 'Create a channel per org and invite the app',
                                who: 'Slack admin',
                                where: 'Slack → the channel',
                                goal: 'The app can only post in channels it has joined.',
                                items: [
                                    'Create one channel per org, for example `#rr-qa` and `#rr-prod` (examples). In each, type `/invite @Release Relay` (your app\'s name) and press Enter.',
                                    'Slack confirms the app was added.'
                                ],
                                problems: [['Send test message fails with not_in_channel', 'Invite the app to that channel.']],
                                shot: { ill: 'slack-invite', cap: 'In each channel: /invite @your app.', alt: 'Drawing of a Slack channel with callouts 1 the message box with /invite @Release Relay, 2 the confirmation that the app was added.' }
                            },
                            {
                                title: 'Set the channel on each org',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Orgs → click the org → Edit → Slack',
                                goal: 'Releases into each org post in that org\'s own channel.',
                                items: [
                                    '**Channel**: `#channel-name` or the channel ID.',
                                    'Turn on **Post to Slack** (on a developer org the switch is **Also post here**: its people get a one-line copy of their own releases).',
                                    'Press **Save**. Back in the org\'s window (read mode), press **Send test message** in its Slack section. The button is grey until the org has a channel.'
                                ],
                                text: ['The Slack section shows only once Slack is set up. An org approved in Salesforce only gets the card with **Open in Release Relay** instead of Approve and Reject.'],
                                check: 'The test message appears in the channel.',
                                problems: [['"Slack channel must be a channel name such as #channel-name, or a channel ID"', 'Type the channel with `#`, or paste its ID (channel details → bottom of the About tab).']],
                                links: [{ label: 'How to use: Pipeline tab', to: 'pipelinetab' }]
                            },
                            {
                                title: 'Reminders, daily digest, mentions and hotfix alerts (optional, per org)',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Orgs → click the org → Slack → Reminders and alerts → Edit',
                                goal: 'Nudge people when a release waits, send one summary a day, tag the right person, and always flag a hotfix.',
                                items: [
                                    '**Reminders**: a nudge in the release\'s Slack thread when it has waited for approval (approvers) or still has manual steps to do after a deploy (deploy team) longer than the hours you set (4 when blank), then again every that many hours. Quiet between 8 PM and 7 AM.',
                                    '**Daily digest**: one message in the org\'s channel from the hour you pick: deployed yesterday, waiting for approval, manual steps to do, failed. Nothing to say, no message.',
                                    '**Mentions**: tags the developer when checks fail and the approvers when a release is ready (and in reminders). Only people linked to Slack (Approvers window) are tagged.',
                                    '**Hotfix alerts** (on by default): "Hotfix in progress" in the org\'s channel when a hotfix into it is raised, even with reminders off.',
                                    'With reminders and the digest off, nothing is checked or sent for that org.'
                                ],
                                text: ['Reminders and digests go out from the pipeline\'s hourly schedule (pipeline files version 24, job **slack-due**), which calls the production hub; times use the hub\'s time zone. Repository variable `RELAY_SLACK_DUE=off` stops it. Slack being busy (rate limited) just moves the rest to the next hour.'],
                                check: 'With reminders on and a short wait (1 hour), a release waiting for approval gets a nudge in its thread within the next hour.',
                                problems: [['Nothing arrives', 'The org needs a channel and Slack on; the pipeline files must be version 24 or later (Pipeline → Connection & route, the pipeline files line); the run "Release Relay Slack reminders" in GitHub Actions logs what the hub answered.']]
                            },
                            {
                                title: 'Approve in Slack: save the signing secret',
                                who: 'Slack admin + Release Relay admin',
                                where: 'Slack app settings → your app → Basic Information → App Credentials; then Release Relay → Pipeline → Approvals & Slack → Slack connection → Edit',
                                goal: 'Proves that an Approve or Reject press really comes from your Slack app. Without it the hub refuses every press.',
                                items: [
                                    'In Slack: under **App Credentials** find **Signing Secret** and press **Show**. Copy it (not the Client Secret, not the token).',
                                    'In Release Relay: Pipeline → **Approvals & Slack** → Slack connection → **Edit** → open **Approve in Slack (optional, advanced)**.',
                                    'Paste it into **Signing secret**.',
                                    'Press **Save and test**. It is saved encrypted and never shown again; later, leave the box blank to keep it.'
                                ],
                                check: 'The Slack connection shows "Signing secret saved" under Approve in Slack.',
                                problems: [['"The signing secret has no spaces: copy it again from the Slack app (Basic Information)."', 'Copy the Signing Secret again from Basic Information → App Credentials, not the Client Secret or the bot token.']]
                            },
                            {
                                title: 'Approve in Slack: create a Site',
                                who: 'Salesforce admin',
                                where: 'Hub: Setup → Quick Find: Sites → Sites',
                                goal: 'Slack sends each press to the hub through this public Site. It answers only requests signed with your signing secret, from linked approvers.',
                                items: [
                                    'No Sites yet? The page first asks for a Site domain: type a domain name, press **Check Availability**, tick the terms, press **Register My Salesforce Site Domain**.',
                                    'Press **New**. Site Label: for example `Release Relay Slack` (Site Name fills in by itself).',
                                    'Tick **Active**.',
                                    'Active Site Home Page: press the lookup and pick any page, for example `InMaintenance`.',
                                    'Press **Save**.'
                                ],
                                check: 'Setup → Sites lists the Site as Active.',
                                shot: { ill: 'slack-site', cap: 'A Site, active, with RLY_Slack_Site on its guest user.', alt: 'Drawing of the Site Edit page with callouts 1 Site Label, 2 Active, 3 Active Site Home Page, 4 RLY_Slack_Site permission set on the guest user.' }
                            },
                            {
                                title: 'Approve in Slack: give the guest user RLY_Slack_Site',
                                who: 'Salesforce admin',
                                where: 'Setup → Sites → your Site → Public Access Settings → Assigned Users',
                                goal: 'The Slack callback runs as the Site\'s guest user. This permission set lets it run Release Relay\'s Slack class, answer through the Slack credential and start the deploy through the Git credential (build 53), nothing else.',
                                items: [
                                    'On the Site\'s page press **Public Access Settings** → **Assigned Users** → open the site guest user (for example "Release Relay Slack Site Guest User").',
                                    '**Permission Set Assignments** → **Edit Assignments** → add **Release Relay Slack Site** (`RLY_Slack_Site`) → **Save**.'
                                ],
                                text: ['Release Relay finds the Site by this assignment: the first active Site whose guest user has `RLY_Slack_Site`. Give it to one Site only.'],
                                check: 'The guest user\'s Permission Set Assignments list RLY_Slack_Site.'
                            },
                            {
                                title: 'Approve in Slack: let the guest user start the deploy',
                                who: 'Salesforce admin',
                                where: 'Setup → Sites → your Site → Public Access Settings (the Site\'s guest profile)',
                                goal: 'Approve starts the deploy through your Git credential as the guest user, so it needs that credential too. Without it pressing Approve does nothing at all. Apex checks Slack\'s signature and the linked approver before either credential is used.',
                                items: [
                                    'On the Site press **Public Access Settings**: this opens the Site\'s **guest profile**. **Edit** → Standard Object Permissions → **User External Credentials** → tick **Read** → **Save**.',
                                    'The credential principals (`RLY_Slack - Bot` and your Git credential\'s) go on the **Release Relay Slack Site** permission set: follow **M. Secure your repository**, step 7 (the button under this step).',
                                    'A Git principal you added on the guest profile before build 53 can stay there.'
                                ],
                                check: 'The guest profile has Read on User External Credentials, and M. Secure your repository, step 7 is done.',
                                problems: [['Approve in Slack stopped working after you renamed or added a Git credential', 'Add the new credential\'s principal as in M. Secure your repository, step 7.']],
                                links: [{ label: 'M. Secure your repository: Approve in Slack', to: 'secure', kind: 'neutral' }]
                            },
                            {
                                title: 'Approve in Slack: copy the Interactivity URL',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Approvals & Slack → Slack connection → Edit → Approve in Slack (optional, advanced)',
                                goal: 'The address Slack sends the presses to: the Site\'s URL followed by `/services/apexrest/rly/slack/actions`.',
                                items: [
                                    '**Interactivity URL to paste in Slack** shows the full URL. Press **Copy**.',
                                    'Press **Cancel** (nothing changed) or **Save and test**.'
                                ],
                                text: ['The URL shows only once an active Site\'s guest user has `RLY_Slack_Site`. Until then the window says "Interactivity URL: set up a Salesforce Site first (Guide → Set up → Slack)": check steps 9 and 10, and that the Site is Active.'],
                                check: 'The URL starts with your Site\'s address (for example `https://your-domain.my.salesforce-sites.com`, an example) and ends with /services/apexrest/rly/slack/actions.',
                                problems: [['"Select the URL and copy it."', 'The browser blocked copying: select the URL in the box and copy it yourself.']]
                            },
                            {
                                title: 'Approve in Slack: set the Request URL in the App Manifest',
                                who: 'Slack admin',
                                where: 'Slack app settings (api.slack.com/apps) → your app → App Manifest',
                                goal: 'Tells Slack where to send Approve and Reject. Socket Mode must stay off: while it is on, Slack sends presses over its own connection and never to Salesforce.',
                                items: [
                                    'Open **App Manifest** (left menu, under Features).',
                                    'Inside `"settings"` set `"interactivity": { "is_enabled": true, "request_url": "<the URL you copied>" }` and `"socket_mode_enabled": false`.',
                                    'Press **Save Changes**. If Slack asks to verify the URL or shows a yellow banner, press **reinstall your app** → Allow.',
                                    'Check **Interactivity & Shortcuts** (left menu): Interactivity is On with your Request URL. Check **Socket Mode**: Enable Socket Mode is Off.'
                                ],
                                text: ['You can also switch Interactivity on and paste the Request URL on the Interactivity & Shortcuts page; the App Manifest works even when that page\'s Save Changes stays grey. If the Request URL box is missing there, Socket Mode is on: switch it off.'],
                                check: 'Socket Mode is Off; Interactivity shows On with your Request URL.',
                                shot: { ill: 'slack-interactivity', cap: 'Interactivity on, Request URL = Site URL + /services/apexrest/rly/slack/actions, Save Changes.', alt: 'Drawing of Slack app settings with callouts 1 Interactivity on, 2 Request URL ending in services/apexrest/rly/slack/actions, 3 Save Changes, 4 Signing Secret Show.' }
                            },
                            {
                                title: 'Approve in Slack: link the approvers',
                                who: 'Release Relay admin (approvers can link themselves)',
                                where: 'Release Relay → Pipeline → Approvals & Slack → Slack connection → Edit → Approvers; then Slack connection → Approvers ›',
                                goal: 'Only approvers linked to a Slack member may press Approve or Reject. With SSO, Release Relay finds each approver in Slack by their Federation ID, so nobody copies member IDs.',
                                items: [
                                    'Slack connection → **Edit** → **Approvers** → **Match approvers by**: **SSO Federation ID** (recommended: each approver\'s SSO sign-in, usually their work email, is looked up in Slack), **Email** (their Salesforce email) or **Manual only**. Check that the scopes show ✓ `chat:write`, ✓ `users:read`, ✓ `users:read.email` (step 2) → **Save**.',
                                    'On the Slack connection line press **Approvers ›**: the **Slack approvers** window lists everyone with `RLY_Approver` or `RLY_Admin` and the Slack account each one approves from.',
                                    '**Add approvers**: search active users (at least 2 letters), tick them, press **Add**. They get `RLY_Approver` and are looked up in Slack right away.',
                                    '**Match now** looks every approver up again, in passes of up to 50. Links set by an admin or by the approver (**Self**) are never overwritten.',
                                    '**Needs attention** lists who couldn\'t be matched, with the fix on each row: Not found in Slack, Federation ID empty or Federation ID isn\'t an email → **Set ID by hand** (the member ID from Slack → their profile → ⋮ → **Copy member ID**, `U0…`); Slack ID already used → **Move link here**.',
                                    'An approver whose Slack email or SSO matches their Salesforce user can link themselves: the first time they press **Approve** in Slack they get a private reply with **Link my account**. It opens Release Relay (signed in as themselves) to confirm; the link works for 15 minutes. Anyone else is told "You\'re not linked to Release Relay yet, so this wasn\'t counted. Ask an admin to link you.": set their ID in the window.',
                                    'With production approval on (F. Settings worth knowing), the window marks who holds the Production Approver add-on.'
                                ],
                                check: 'The Approvers window shows each approver Linked (by SSO, Email, Self or Admin), and Needs attention is empty or only lists people who will link themselves.',
                                problems: [
                                    ['"Slack app is missing users:read.email — add it and reinstall."', 'Step 2: add the scope, reinstall the app, paste the bot token again if it changed. Adding approvers still works; press **Match now** afterwards.'],
                                    ['Not found in Slack', 'The approver\'s Slack account uses another email than their Federation ID (or it is a guest or deactivated account): **Set ID by hand**, or let them use **Link my account**.'],
                                    ['Slack replies "You\'re not linked to Release Relay yet, so your Approve wasn\'t counted."', 'That approver presses **Link my account** in the reply and confirms in Release Relay, then presses Approve again. Or an admin sets their ID in the Approvers window (the only way when the reply says "Ask an admin to link you.").'],
                                    ['Slack replies "You can\'t approve releases. Ask a Release Relay admin."', 'They aren\'t an approver: an admin adds them with **Add approvers**. Also check the release\'s target org has Approve in Slack on.']
                                ]
                            },
                            {
                                title: 'Approve in Slack: turn it on per org',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Orgs → click the org → Edit → Approval',
                                goal: 'Each org decides where its releases are approved.',
                                items: [
                                    'Under **Where releases into** the org **are approved**, switch on **Approve in Slack**. **Approve in Salesforce** may stay on too: either is enough, and at least one stays on.',
                                    'Press **Save**. Do this on every stage (and the hub, if you want) whose releases should be approved from Slack.'
                                ],
                                text: ['The **Approve in Slack** switch shows only while Slack is on and Check connection answers. With Approve in Salesforce off, the release page has no Approve and deploy button: it says "Approved from the Slack card."'],
                                links: [{ label: 'Approval rules', to: 'approvalrules' }]
                            },
                            {
                                title: 'Approve in Slack: check it',
                                who: 'Release Relay admin',
                                where: 'Slack → the org\'s channel',
                                goal: 'See the buttons work before you rely on them.',
                                items: [
                                    'The Slack connection shows **Approve in Slack: Set up** (signing secret saved, the Site found, and its guest user has Read on User External Credentials and the Git principal). **Not ready** names what the guest user still needs.',
                                    'Raise a small release (or use one already waiting) so that it is **Ready for approval** in an org with Approve in Slack on.',
                                    'Its card in that org\'s channel shows **Approve** and **Reject**. A linked approver presses **Approve**: the card updates to Deploying, and the release page says it was approved in Slack. **Reject** opens a form, **Why are you rejecting?**, then **Reject release**.'
                                ],
                                check: 'The card shows Approve and Reject, and pressing Approve moves the release on.',
                                problems: [
                                    ['Slack shows "This app responded with status code 404" or similar', 'The Request URL is wrong or the Site isn\'t Active: copy it again from Pipeline → Approvals & Slack → Slack connection (step 12).'],
                                    ['Slack shows an error after a few seconds and the card doesn\'t change', 'The signing secret is missing or wrong (step 8), Slack is off on the Slack connection, or the press came from another Slack workspace than the one recorded. The hub refuses unsigned presses.'],
                                    ['Pressing Approve does nothing and the release stays Ready for approval', 'The guest user can\'t read User External Credentials (step 11, on the Site\'s guest profile) or can\'t use the Git credential (M. Secure your repository, step 7). To see it for yourself, add a debug log for the Site guest user (Setup → Debug Logs) and press Approve again.'],
                                    ['The card shows Open in Release Relay instead of Approve', 'The org has Approve in Slack off (step 15), or the release isn\'t waiting for an approver.'],
                                    ['Slack replies "Approving production needs the Production Approver add-on."', 'Production approval is on and that approver lacks the add-on: assign it (Roles and access), or ask someone who holds it.']
                                ]
                            }
                        ]
                    },
                    next('setup-slack')
                ]
            }
        ]
    },

    // ---------------- F. Settings worth knowing ----------------
    {
        key: 'setup-settings',
        group: 'setup',
        label: 'F. Settings worth knowing',
        adminOnly: true,
        cards: [
            {
                key: 'sx-main',
                title: 'F. Settings worth knowing',
                blocks: [
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Choose each org\'s approval rule',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Orgs → click the org → Edit → Approval',
                                goal: 'Decide when a release into the org waits for a person.',
                                items: [
                                    'Always (the default), Only when it contains…, or Never (not offered for production). Optionally: hotfixes need 2 approvers.',
                                    'In the same section: the org\'s code scan (Follow the Git connection, Always scan or Don\'t scan) and where it is approved (Approve in Salesforce, Approve in Slack).'
                                ],
                                links: [{ label: 'Approval rules', to: 'approvalrules' }]
                            },
                            {
                                title: 'Choose who approves production',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Approvals & Slack → Approvals',
                                goal: 'Production can need someone with the Production Approver add-on, not just any approver.',
                                items: [
                                    '**Production approval needs the add-on**: on, only holders of the **Release Relay Production Approver** add-on approve releases into production, in Salesforce and in Slack; the Approver group alone approves the other orgs. Off: any approver approves production.',
                                    'A new hub starts with it on (saving its first Git connection turns it on). A hub that existed before the add-on starts with it off, so nobody is locked out: assign the add-on first (the card says who holds it), then turn it on.',
                                    'Both approvers of a two-approver hotfix into production need the add-on.'
                                ],
                                links: [{ label: 'Roles and access', to: 'access' }]
                            },
                            {
                                title: 'Name the deployment team',
                                who: 'Salesforce admin',
                                where: 'Setup → Users → Permission Set Groups → Release Relay Deployment Team → Manage Assignments',
                                goal: 'Only they (and admins) tick manual steps off per org, roll back, load data and copy data down.',
                                items: ['Assign the **Release Relay Deployment Team** group to the people who do manual steps.'],
                                links: [{ label: 'Manual steps', to: 'manual' }]
                            },
                            {
                                title: 'Decide how flows arrive in production',
                                who: 'Salesforce admin of production',
                                where: 'Production: Setup → Process Automation Settings',
                                goal: 'Decides whether an active flow version is deployed active.',
                                items: [
                                    '**Deploy processes and flows as active**: on means active versions deploy active, and the Apex tests in the deploy must cover those flows (flow test coverage). Off means flows arrive inactive and the release\'s **Activate in each org** choice activates them.',
                                    'Press **Save**.'
                                ],
                                shot: { ill: 'flow-setting', cap: 'Process Automation Settings: Deploy processes and flows as active.', alt: 'Drawing of Process Automation Settings with callouts 1 Deploy processes and flows as active, 2 Save.' },
                                links: [{ label: 'Flows', to: 'flows' }]
                            },
                            {
                                title: 'Browser caching: off while building, on for go-live',
                                who: 'Salesforce admin of the hub',
                                where: 'Hub: Setup → Session Settings → Caching',
                                goal: 'With caching on, people can see an old version of a page after Release Relay is updated.',
                                items: [
                                    'Untick **Enable secure and persistent browser caching to improve performance** while you install or update Release Relay. Tick it again for go-live.',
                                    'Press **Save**.'
                                ],
                                problems: [['"No COMPONENT named …" after an update', 'Reload without cache (Ctrl+Shift+R), or log out and in.']],
                                shot: { ill: 'session-cache', cap: 'Session Settings: the browser caching box.', alt: 'Drawing of Session Settings with callouts 1 Enable secure and persistent browser caching unticked, 2 Save.' }
                            },
                            {
                                title: 'Sandbox copies of the hub',
                                who: 'Salesforce admin',
                                where: 'Setup → Sandboxes → New Sandbox (or Refresh) → Apex Class',
                                goal: 'A sandbox made from production copies Release Relay; it must not act as the hub.',
                                items: ['Pick `RlySandboxCopy` as the Apex Class. When the copy is ready it switches Slack off, marks the Git connection Not checked and removes everyone\'s assignments of Release Relay\'s own groups and permission sets (Developer, Approver, Deployment Team and Auditor groups; `RLY_Developer`, `RLY_Approver`, `RLY_Deploy_Team`, `RLY_Auditor`, `RLY_Slack_Site` and the three add-ons). The Admin and Full Access groups and `RLY_Admin` stay, and your own sets are left alone. Release Relay detects the sandbox by itself and refuses actions there anyway.'],
                                links: [{ label: 'Sandbox copies of the hub', to: 'sandboxcopy' }]
                            },
                            {
                                title: 'Keep production reviewers on',
                                who: 'Git admin',
                                where: 'Repository → Settings → Environments → production\'s environment → Required reviewers',
                                goal: 'A second safety net for production in your Git provider.',
                                items: ['If you turned required reviewers off while trying things out, turn them on again before real users start.']
                            }
                        ]
                    },
                    next('setup-settings')
                ]
            }
        ]
    },

    // ---------------- G. Nightly archive (optional) ----------------
    {
        key: 'setup-archive',
        group: 'setup',
        label: 'G. Nightly archive (optional)',
        adminOnly: true,
        cards: [
            {
                key: 'sa-main',
                title: 'G. Schedule the nightly archive (optional)',
                aside: 'Optional · production hub only',
                blocks: [
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Schedule the nightly archive (optional)',
                                badge: 'Recommended',
                                who: 'Git admin',
                                where: 'Release Relay → Pipeline → Connection & route → 1 · Where the code lives → Update pipeline files',
                                goal: 'Lets the Git pipeline ask the hub every night to remove finished releases older than the Retention days, so storage stays free without anyone pressing Run now. The same call refreshes the Credentials check and clears settings changes older than 90 days. It needs Retention days set and “Archive every night” on (Pipeline → Retention & archive).',
                                items: ['Update the pipeline files to the latest version: the schedule has been in them since version 15, so there is nothing to write by hand. In `.github/workflows/release-relay.yml` these are the lines that do it:'],
                                code: 'on:\n'
                                    + '  schedule:\n'
                                    + '    - cron: "0 8 * * *"    # the nightly archive: 08:00 UTC = 2:00 AM Central (CST)\n'
                                    + '    - cron: "17 * * * *"   # Slack reminders and digests (version 24 and later)\n'
                                    + '  workflow_dispatch:       # how the hub starts every other run\n'
                                    + '\n'
                                    + 'jobs:\n'
                                    + '  archive:\n'
                                    + '    if: ... github.event.schedule == \'0 8 * * *\' ... || inputs.mode == \'archive\'\n'
                                    + '    environment: ${{ vars.RELAY_HUB_ENVIRONMENT || \'prod\' }}\n'
                                    + '    # signs in to the hub with that environment\'s login and calls\n'
                                    + '    # POST /services/apexrest/rly/archive once per pass until the hub says done',
                                text: ['**Cron is UTC.** Pick the UTC hour for your quiet time: 2:00 AM Central is `0 8 * * *` in winter (CST) and `0 7 * * *` in summer (CDT); with one fixed line it runs an hour later in summer. GitHub may start scheduled jobs a few minutes late, and pauses schedules in public repositories after 60 days without activity.'],
                                problems: [
                                    ['The Archive tab says "Missed the last 2 nights"', 'Check the schedule in `release-relay.yml` on the pipeline branch, and that the workflow is enabled in GitHub → Actions. The job signs in to the hub like the other jobs, so the hub\'s environment (`prod`, or the one the repository variable `RELAY_HUB_ENVIRONMENT` names) needs its secrets and variables.'],
                                    ['"Last call skipped: nightly is off"', 'Turn on **Archive every night** in Pipeline → Retention & archive → Retention → Edit (it needs the days set first).']
                                ]
                            },
                            {
                                title: 'Check it ran',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Archive → Nightly job, the morning after',
                                goal: 'See that the hub received last night\'s call.',
                                items: [
                                    'Archive tab → **Nightly job** → “Last nightly call received” shows last night\'s time.',
                                    'Or GitHub → Actions → Release Relay → filter Event: `schedule`; the run log lists each pass.',
                                    'No call for 2 nights: the Archive tab warns “Missed the last 2 nights”.'
                                ],
                                check: 'Done when the Archive tab shows a nightly call. Skipping is fine: Run now still works.'
                            }
                        ]
                    },
                    {
                        type: 'links',
                        links: [
                            { label: 'Skip', to: 'setup-checklist', kind: 'neutral' },
                            { label: 'Open Archive tab', tab: 'RLY_Archive' }
                        ]
                    }
                ]
            }
        ]
    },

    // ---------------- H. Checklist ----------------
    {
        key: 'setup-checklist',
        group: 'setup',
        label: 'H. Checklist',
        adminOnly: true,
        cards: [
            {
                key: 'sc-list',
                title: 'H. Setup checklist',
                aside: 'One line per item: where it is, and how to tell it is done',
                blocks: [
                    {
                        type: 'table',
                        cols: ['Item', 'Where', 'Done when'],
                        rows: [
                            ['Permission set groups assigned (and add-ons)', 'Hub: Setup → Permission Set Groups', 'People see their tabs; admins see Pipeline'],
                            ['Certificate `release_relay`', 'Hub: Setup → Certificate and Key Management', 'Listed, exportable key'],
                            ['`release_relay.crt` and the `.jks` + password', 'Your computer / password manager', 'Both files kept safe'],
                            ['Remote Site per org (the hub too)', 'Hub: Setup → Remote Site Settings', 'One active row per org'],
                            ['Git token', 'Git provider → Fine-grained tokens', 'The permissions in M. Secure your repository, step 1'],
                            ['External Credential + Named Credential `RLY_Git_GitHub`', 'Hub: Setup → Named Credentials', 'Principal RLY_Git_GitHub with Token; header Authorization'],
                            ['Principal access `RLY_Git_GitHub - RLY_Git_GitHub`', 'Hub: comes with `RLY_Access`, in every Release Relay group', 'No "can\'t use it" errors'],
                            ['Git connection (one active)', 'Pipeline → Connection & route → 1 · Where the code lives', 'Connected'],
                            ['Pipeline files on `main`', 'Repository / Guide → Repository files', 'Pipeline files: up to date'],
                            ['Workflow permissions', 'Repository → Settings → Actions → General', 'Read and write; may create pull requests'],
                            ['Environment per stage org and production', 'Repository → Settings → Environments', '4 secrets + 2 variables each'],
                            ['Integration user + External Client App per org', 'Each org: Setup', 'JWT on, hub .crt, user pre-authorized'],
                            ['Each org registered (the hub as Hub), 10 at most', 'Pipeline → Orgs', 'Every card Connected'],
                            ['Route branches', 'Pipeline → Connection & route → 2 · Route → Create missing branches', 'Every route branch already exists'],
                            ['Slack (optional): token, channels, test', 'Pipeline → Approvals & Slack → Slack connection · each org → Edit → Slack', 'Connected; test message arrives'],
                            ['Approve in Slack (optional)', 'Slack scopes users:read and users:read.email · Signing secret · Site with RLY_Slack_Site on its guest user · guest profile: Read on User External Credentials · the Git principal on Release Relay Slack Site (M. Secure your repository, step 7) · Request URL in the App Manifest, Socket Mode off · approvers linked (Match approvers by SSO) · Approve in Slack per org', 'Slack connection says Approve in Slack: Set up; Approve works from the card'],
                            ['Approval rules, deployment team', 'Pipeline → Orgs · the Release Relay Deployment Team group', 'Set as your process needs'],
                            ['Production approval', 'Pipeline → Approvals & Slack → Approvals', 'On, once the Production Approver add-on is assigned'],
                            ['Caching on, production reviewers on', 'Session Settings · Environments → production\'s environment', 'Before real users start'],
                            ['Retention and the nightly archive (optional)', 'Pipeline → Retention & archive · pipeline files version 15 or later (scheduled job)', 'Archive tab shows a nightly call'],
                            ['Secure your repository: token permissions, protected environments and branches, run signing, hub access to itself, Slack principals', 'M. Secure your repository · Pipeline → Security & credentials', 'Repository security all green; Credentials no Failed or Unknown rows; Run signing Required'],
                            ['Credentials', 'Pipeline → Security & credentials → Credentials → Check now', 'All OK (the hub\'s own certificates need `RLY_Org_Self`, optional)'],
                            ['First release', 'New Release', 'Deployed to the first stage']
                        ]
                    },
                    { type: 'links', links: [{ label: 'Next: raise a first release', to: 'raise' }] }
                ]
            }
        ]
    }
];

const START_SECTIONS = [
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
                            '**Git provider**: one repository, through one active Git connection (releases run on GitHub and GitLab; Bitbucket and Azure DevOps have pipeline files for later). Each org has a branch; every release is a pull request into the next stage\'s branch.',
                            '**Pipeline**: your provider\'s pipeline runs the code scan and a check-only deploy with your tests, and later merges and deploys.',
                            '**Route**: developer orgs → stages in order → production (the hub), at most 10 orgs. Pipeline → Connection & route shows yours. Releases, hotfixes too, are raised from developer orgs only.',
                            '**Promote**: what is deployed to a stage moves on to the next stop from the Promote tab, hotfixes first.'
                        ]
                    },
                    { type: 'links', links: [{ label: 'Admins: set it up', to: 'setup' }, { label: 'Raise a release', to: 'raise' }, { label: 'Approve', to: 'approve' }, { label: 'How a change moves', to: 'moves', kind: 'neutral' }] }
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
                            { title: 'Approve', text: 'In Salesforce, Slack or Git, or by the org\'s rule' },
                            { title: 'Deploy', text: 'Merge, deploy, update dev branches' }
                        ],
                        shots: [
                            { name: 'review', cap: 'Review: what goes in, and which tests run.' },
                            { name: 'conflict', cap: 'Conflict: your version and the target\'s side by side.' }
                        ]
                    },
                    { type: 'text', paras: ['**The test rule.** A release with an Apex class or trigger must include the test classes that cover it; Release Relay won\'t let you continue without one. Those tests run (RunSpecifiedTests) in every org the release deploys to. A release without Apex deploys without tests. When its only Apex is deleted classes or triggers switched off, production runs its local tests (RunLocalTests) and sandboxes none.'] }
                ]
            }
        ]
    },
    // ---------------- How a change moves (board HubPromoteRules) ----------------
    {
        key: 'moves',
        group: 'start',
        label: 'How a change moves',
        cards: [
            {
                key: 'mv-route',
                title: 'How a change moves (for example Dev → QA → Staging → Production)',
                aside: 'Example route · Pipeline → Connection & route shows yours',
                blocks: [
                    { type: 'text', paras: ['A change starts in a developer org and stops at every stage on the route before production. The first hop is a release raised on **New Release**; every later hop is a **promotion** from the **Promote** tab. Each stop applies its own checks and its own approval rule.'] },
                    {
                        type: 'route',
                        label: 'Example route Dev, QA, Staging, Production',
                        stops: [
                            { name: 'Dev', branch: 'dev', role: 'Developer org', kind: 'dev', text: 'People build here. Releases, hotfixes too, are raised from a developer org.' },
                            { name: 'QA', branch: 'qa', role: 'Stage 1', approval: ['Approval into QA', 'Your org\'s setting', 'Always, Only when it contains… or Never; in Salesforce, Slack or both.'] },
                            { name: 'Staging', branch: 'staging', role: 'Stage 2', approval: ['Approval into Staging', 'Your org\'s setting', 'Always, Only when it contains… or Never; in Salesforce, Slack or both.'] },
                            { name: 'Production', branch: 'prod', role: 'Production · the hub', kind: 'hub', approval: ['Approval into Production', 'Your org\'s setting', 'Always or Only when it contains… (production can\'t be Never). Can need the Production Approver add-on; hotfixes can need 2 approvers.'] }
                        ],
                        hops: [
                            { where: 'New Release tab', what: 'Raise a release', who: 'anyone who raises' },
                            { where: 'Promote tab', what: 'Card QA → Staging', who: 'approvers and admins' },
                            { where: 'Promote tab', what: 'Card Staging → Production', who: 'approvers and admins' }
                        ],
                        every: ['One release or promotion', 'Code scan', 'Check-only deploy + tests', 'Approval: the next stop\'s rule', 'Deploy']
                    },
                    { type: 'note', text: 'Each org\'s approval rule is set on Pipeline → Orgs → the org → Edit → Approval. See Approval rules.' }
                ]
            },
            {
                key: 'mv-rules',
                title: 'The four rules on a Promote card',
                blocks: [
                    { type: 'text', paras: ['**The next stop gets each file as it is in the stage.** So when two releases in a stage change the same component, they can\'t be split: the older one goes too, and a newer one must be added. (Releases, components and dates below are examples.)'] },
                    { type: 'rules', stageName: 'QA', nextName: 'Staging' }
                ]
            },
            {
                key: 'mv-card',
                title: 'What the Promote card shows',
                aside: 'Example',
                blocks: [
                    { type: 'promotecard', stageName: 'QA', nextName: 'Staging' },
                    { type: 'text', paras: ['What you tick, plus what goes too, leaves as one promotion. The card lists releases in the order their changes are promoted. **How promoting works** on each card opens these rules beside the list, and each row label (Goes with …, Changed … after …, Stays in …) says why when you hover over it or tab to it.'] }
                ]
            },
            {
                key: 'mv-hotfix',
                title: 'The hotfix path',
                blocks: [
                    { type: 'text', paras: ['A hotfix takes the same route, with the same checks and approvals, but goes **on its own** at each Promote hop. Approval is never skipped; the person who raised it can\'t approve it.'] },
                    {
                        type: 'hotfixpath',
                        label: 'Hotfix path, example Dev, QA, Staging, Production',
                        stops: [
                            { name: 'Dev', branch: 'dev', kind: 'dev', text: 'The fix is built here · branch `hotfix/rel-xxxxx`' },
                            { name: 'QA', branch: 'qa', text: 'Approval by QA\'s rule' },
                            { name: 'Staging', branch: 'staging', text: 'Approval by Staging\'s rule' },
                            { name: 'Production', branch: 'prod', kind: 'hub', text: 'Can need a 2nd approver' }
                        ],
                        hops: [
                            { where: 'New Release', what: 'Turn on **This is a hotfix** and say why' },
                            { where: 'Promote tab', what: 'Tick it alone: **Promote hotfix to Staging**' },
                            { where: 'Promote tab', what: 'Tick it alone: **Promote hotfix to Production**' }
                        ],
                        back: '**Merged back down** after the deploy to production: `prod` into `staging` and `qa`, then into `dev`. The release page shows each one: **Done**, or **n to review** when a branch conflicts with work in progress.'
                    }
                ]
            },
            {
                key: 'mv-rollback',
                title: 'What rollback means at each stop',
                aside: 'Admins and deployment team',
                blocks: [
                    { type: 'text', paras: ['Before every deploy into an org the pipeline saves a snapshot of what the deploy changes. **Roll back** puts one org back to that snapshot. The other stops are not touched.'] },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['Stop', 'Roll back in this org', 'Tests', 'Not changed'],
                        rows: [
                            ['**Dev**', 'Nothing to roll back: releases are raised from here, not deployed to it.', '—', '—'],
                            ['**QA**', 'QA goes back to its snapshot from just before the release was deployed to QA.', 'None (sandbox)', 'Staging, Production and Git'],
                            ['**Staging**', 'Staging goes back to its snapshot from just before the promotion that carried the release deployed.', 'None (sandbox)', 'QA, Production and Git'],
                            ['**Production**', 'Production goes back to its snapshot from just before the promotion into production deployed.', 'This release\'s tests (default) or all local tests', 'QA, Staging and Git']
                        ]
                    },
                    {
                        type: 'list',
                        items: [
                            'The Admin and Deployment Team groups: **Releases** tab → the release → **Roll back**, pick the org, say why.',
                            'A later release that deployed the same component to that org is undone too: the dialog warns first.',
                            'Git is not changed and the release keeps its status. Fix the branch with a new release from a developer org.',
                            'Rolled back in a stage it still waits in? Its row on the Promote tab shows **Rolled back in** and the stage (for example **Rolled back in QA**). It can still be ticked, and promoting it sends the change on, because Git still has it.'
                        ]
                    },
                    { type: 'links', links: [{ label: 'Promote to the next stop', to: 'promote', kind: 'neutral' }, { label: 'Hotfix', to: 'hotfix', kind: 'neutral' }, { label: 'Roll back a release', to: 'rollback', kind: 'neutral' }, { label: 'Approval rules', to: 'approvalrules', kind: 'neutral' }] }
                ]
            }
        ]
    }
];

const USE_SECTIONS = [
    {
        key: 'home',
        group: 'daily',
        label: 'Home',
        cards: [
            {
                key: 'home-main',
                title: 'Home: what needs you today',
                blocks: [
                    { type: 'text', paras: [
                        '**Home** is the first tab of Release Relay and opens when you start the app. It reads only what is already saved in the hub (no calls to Git, Slack or your orgs), so it opens fast. Press **Refresh** to read it again, **New release** to raise one.',
                        'The greeting says how many things need you. The **Health** line shows the last saved checks: Git connection, pipeline files, Slack, approving in Slack and the code scan. When all is fine it shows one line, **All connections OK**; admins open **Pipeline ›** to check again.',
                        'Under it, **Credentials** shows any certificate, token or sign-in that is expiring, critical, expired or failed, from the nightly check (or **All credentials OK**). A freeze starting within 7 days shows as a warning at the top.'
                    ] },
                    { type: 'table', cols: ['Part', 'What it shows', 'Click it to'], rows: [
                        ['Tiles', 'Open releases, Waiting for approval, Checks failed, Deployed this week, Rollbacks · 30 days, and Raise → deployed · 30 days (the average days from raising a release to its first deploy).', 'Open Releases or Approvals with the matching chip picked.'],
                        ['Needs you', 'One group per role you have: **Waiting for your approval** (approvers), **Manual steps to do** (deployment team), **Your releases with a problem** (failed checks or deploys, conflicts to review).', 'Open the release with **Open** or its number.'],
                        ['Deploys · last 8 weeks', 'Deployed and failed deploys per week, the success rate, and this week per org.', '**Releases ›** lists deployed releases.'],
                        ['Route', 'Each stop of the route with its connection, the last release raised or deployed there, and what waits: open releases, releases ready to promote, approvals.', '**Releases**, **Promote** or **Approvals**.'],
                        ['Recent activity', 'The last 50 events of every release, newest first.', 'Open the release from its number.']
                    ] },
                    { type: 'list', items: [
                        'The lists keep their header in view and scroll inside their card. Type in the search box to filter them as you type (release, title or event, org, person); matches are highlighted and the box shows how many are left, for example **7 of 50**. **Esc** or **×** clears it.',
                        'Recent activity has chips: **All**, **Deploys**, **Approvals**, **Failures**, **Rollbacks**. Search works within the chip you picked.',
                        'On a phone or a narrow window the page shows one column and the lists show two lines per row.'
                    ] },
                    { type: 'note', text: 'In a sandbox, or a production org before setup, Home shows the same notice as the other tabs instead of the page.' }
                ]
            }
        ]
    },
    {
        key: 'monitor',
        group: 'daily',
        label: 'Pipeline Monitor',
        cards: [
            {
                key: 'monitor-main',
                title: 'Pipeline Monitor: what the pipeline is doing now',
                blocks: [
                    { type: 'text', paras: [
                        '**Pipeline Monitor** shows every run of the Git pipeline in one place: what is running, where, for which release, and what failed. Everyone in a Release Relay group (Auditor too) can open it; nobody can change anything there.',
                        'The pipeline tells the hub when each run starts and when it ends (pipeline files version 20 or later). The tab reads only what the hub has saved, never Git itself. It reads again every **10 seconds** while a run is queued or running and every **30 seconds** otherwise; the header says when it last read and counts down to the next read. It pauses while the browser tab is hidden and reads at once when you come back. **Refresh** reads now.'
                    ] },
                    { type: 'table', cols: ['Part', 'What it shows', 'Click it to'], rows: [
                        ['Tiles', '**Running now**, **Branches in progress**, **Succeeded today** and **Failed today** (your day).', '**Failed today** shows only the failed runs below.'],
                        ['Route', 'One lane per org, grouped as on the Pipeline tab: developer orgs, the route in order with production last, then back promote orgs. Each lane shows the org\'s latest run: status, branch, release, how long it took, who started it and a four-part progress bar. **No runs today** when it had none (with its last run).', 'Open that run\'s details.'],
                        ['Active branches', 'The branches of open releases and of runs in the last 24 hours: pull request number and state (from the release), last activity, where it ran last and a status dot. Running and failed first.', 'Open the branch\'s latest run.'],
                        ['Runs', 'Every run, running first, then newest: status, workflow step, branch, target org, release, started, duration, who started it and **View in GitHub**. **All**, **Running**, **Failed**, **Succeeded** filter it; **Load older runs** reads 50 more.', 'Open the run\'s details; the release number opens the release.']
                    ] },
                    { type: 'list', items: [
                        'Each section has its own search box and scrolls on its own; the count shows how many match, for example **3 of 12**.',
                        'A developer org\'s lane shows the raise of its releases: a pull request that opened is green there even when the code scan or the check-only deploy failed later. That failure shows on the lane of the stage org it validated in.',
                        '**Run details** (on the right, or over the page on a smaller screen): status, release, step and org, branch, start and duration, who started it, the GitHub run number and attempt, each job with its outcome, the failure message, and links to the release and to the run log in GitHub.',
                        'After a move to another provider the old connection\'s runs stay: pick the repository at the top (it lists the hub\'s Git connections).',
                        'Old runs leave with the nightly archive, after the same Retention days as releases (Pipeline → Retention & archive).'
                    ] },
                    { type: 'note', text: 'Nothing shows? Update the pipeline files to version 20 or later (Pipeline → Connection & route → Update pipeline files). Only the GitHub pipeline file reports runs. The two monitor jobs sign in to the hub with the hub environment\'s login, like the nightly archive, and its user needs the Release Relay Admin group (`RLY_Admin`). If that environment asks for a reviewer, set the repository variable `RELAY_MONITOR` to `off` to skip them. A failed monitor call never fails a run.' },
                    { type: 'links', links: [{ label: 'Open Pipeline Monitor', tab: 'RLY_Pipeline_Monitor' }, { label: 'Pipeline files', to: 'pipelinetab', kind: 'neutral' }] }
                ]
            }
        ]
    },
    {
        key: 'metrics',
        group: 'daily',
        label: 'Metrics',
        cards: [
            {
                key: 'metrics-main',
                title: 'Metrics: how releases are going',
                blocks: [
                    { type: 'text', paras: [
                        '**Metrics** turns Release Relay\'s own history into numbers: the four **DORA** measures and two day-to-day ones. Everyone in a Release Relay group (Auditor too) can open it; nothing is set up and nothing can be changed there.',
                        'Pick the **Org** deploys go to (production first; **All orgs** adds them up), a **Developer org** (or all) and the period: **30 days**, **90 days**, **6 months** or **12 months**. Each tile compares the period with the one before it, in green when it got better and red when it got worse. Charts go by week up to 90 days and by month beyond; hover a bar for its number.'
                    ] },
                    { type: 'table', cols: ['Tile', 'What it measures'], rows: [
                        ['Deploys (DORA)', 'Successful deploys to the org, and how many a week.'],
                        ['Lead time (DORA)', 'From raising a release to it running in the org (median). A promotion counts each release it carries from the day that release was raised.'],
                        ['Change failure rate (DORA)', 'Failed deploys, rollbacks and hotfixes deployed, over deploys tried.'],
                        ['Time to restore (DORA)', 'From a failed deploy or a rollback to the next successful deploy in that org (median).'],
                        ['Approval wait', 'From the check that made a release ready for approval to its approval (median).'],
                        ['Checks failing', 'Check-only deploys and code scans that failed, over those run.']
                    ] },
                    { type: 'list', items: [
                        '**Why checks fail** sorts the failed checks into test failures, deploy errors, conflicts with the branch, quality gates, code coverage and code scan, from each release\'s latest result (read ten releases at a time, so it fills in after the tiles). A release fixed since shows **Fixed since**. **Files that conflict most** lists the files in those conflicts.',
                        'The **Developer org** filter applies to lead time, approvals and checks; deploys, failures and restores are per org.',
                        '**Download CSV** saves every tile (this period and the one before), every chart point and the reasons.',
                        'Numbers go back as far as the history does: the nightly archive removes releases older than the Retention days (Pipeline → Retention & archive).'
                    ] },
                    { type: 'links', links: [{ label: 'Open Metrics', tab: 'RLY_Metrics' }] }
                ]
            }
        ]
    },
    {
        key: 'sync',
        group: 'daily',
        label: 'Sync status',
        cards: [
            {
                key: 'sync-main',
                title: 'Sync status: are the orgs and branches in step?',
                blocks: [
                    { type: 'text', paras: [
                        '**Sync status** answers three questions: is each org the same as its own branch, has everything a higher stage has come back down the route, and which managed packages are installed where. Developers, approvers, the deployment team and admins can open it and start a check (the Auditor group has no Sync status tab); back promote and push need the **Release Relay Admin** group, like back promote on the Pipeline tab.',
                        'Checks run in the Git pipeline (pipeline files version 23 or later) and can take a few minutes on a big org; the tab reads again every few seconds while one runs and keeps the latest result of each, with when it was checked.'
                    ] },
                    { type: 'table', cols: ['View', 'What it shows', 'What you can do'], rows: [
                        ['Org vs branch', 'One card per org on the route: **In sync**, or **Out of sync** with how many differ. Pick a card to list the differences by type: **Only in org** (changed in the org directly), **Only on branch** (in Git but not in the org) and **Different**. Open one for the side-by-side compare (branch left, org right).', '**Check now**. Pick components, then **Bring into the branch** (a New Release from that org with them selected; only-on-branch ones as deletions) or **Push to the org** (deploys the branch\'s files to a stage or the hub).'],
                        ['Down the route', 'Each branch against the one below it (production over the last stage, … the first stage over each developer org): how many components the higher branch has that the lower one doesn\'t, such as hotfixes. **Different in <org> too** means the lower branch changed the same file.', '**Check the route**. Pick components and **Back promote N picked**, or **Back promote all**: a back promote release with the usual checks, approval rule and conflict screen. A developer org gets the files on its branch only.'],
                        ['Installed packages', 'Each managed package with its version in every route org, and whether they match.', '**Add upgrade step** (a New Release with a Managed package manual step, before deploy) or **Uninstall…**: lists your own components that still use the package (where Salesforce reports it) and starts a release that deletes them first, with an uninstall manual step after deploy.']
                    ] },
                    { type: 'list', items: [
                        'Stages and the hub are read by the pipeline with their own login. A developer org is read by the hub: the tab lists its components and sends them to Git a few at a time first, so keep the page open until the run starts (a grey line says so while the parts are sent). If a part fails, the first error shows and the rest stop; **Check now** starts again. A card\'s result and the list under the cards always agree: the list is read when you pick the card.',
                        'Release Relay\'s own components, managed-package components and org values on the Pipeline tab (per-org values) don\'t count as differences.',
                        'Old checks leave with the nightly archive, after the Retention days.'
                    ] },
                    { type: 'note', text: 'Release Relay never installs or uninstalls a package: Salesforce allows that only in Setup → Installed Packages, so it is a manual step with proof per org.' },
                    { type: 'links', links: [{ label: 'Open Sync status', tab: 'RLY_Sync_Status' }, { label: 'Pipeline files', to: 'pipelinetab', kind: 'neutral' }] }
                ]
            },
            {
                key: 'sync-data',
                title: 'Data sets: send up, copy down, refill',
                blocks: [
                    { type: 'text', paras: [
                        '**Sync status → Data** moves configuration records between orgs: claim types and their rules, price lists, settings kept as records. An admin defines each **data set**: its objects in load order (parents first), which records (a filter), the **match key** that finds the same record in the other org (an external ID field, or a combination of fields such as Claim type and Name), the parent lookups, and the fields to mask.',
                        'Every run is a **dry run** first: the pipeline reads both orgs and counts what would be inserted, updated or left unchanged, per object. Nothing changes until someone presses **Load**. It needs pipeline files version 24 or later.'
                    ] },
                    { type: 'table', cols: ['Direction', 'Who', 'How'], rows: [
                        ['Send up', 'Anyone starts it; an approver, the deployment team or an admin who didn\'t start it loads it', 'From a developer org or a stage to a higher org. Optionally linked to a release (REL-…). Masking is off unless you turn it on.'],
                        ['Copy down', 'Admins and the deployment team', 'From production or a stage to a lower org. Personal data (emails, phones, names) is masked unless you turn **Mask personal data** off.'],
                        ['Refill', 'Admins and the deployment team', 'Shown on an org whose Org Id changed since its last load (a sandbox refresh): repeats that load with the same data set.']
                    ] },
                    { type: 'list', items: [
                        'No match key, no object: a data set can\'t include an object without one.',
                        'A key that matches two or more records in the target, a record without a key, or a child whose parent isn\'t in either org **blocks** the run, with the keys listed. Fix the data (or the key) and start again.',
                        'Parents load first, then children: a child\'s lookup is matched by its parent\'s key, so a child that a trigger already created is updated, not duplicated.',
                        'Give the data set a **trigger bypass** (a custom setting checkbox or a permission set): it is switched on for the pipeline\'s user during the load and back off after. Without one, the dry run flags **Triggers fire** on objects with active triggers in the target.',
                        'Per-org values (`{{relay:NAME}}` on the Pipeline tab) are swapped: the source org\'s value becomes the target\'s, for example a callback URL.',
                        'The pipeline loads stage orgs and the hub (they have a login in your Git provider\'s environments). A developer org can be a source: the page sends its records first, so keep it open until the dry run starts. At most 10,000 records per object.',
                        'The owner field, Id and system fields are never written. Old runs leave with the nightly archive, after the Retention days.'
                    ] },
                    { type: 'note', text: 'OmniStudio DataPacks (OmniScripts, FlexCards, Integration Procedures and Data Mappers as DataPacks) are not moved by data sets yet: they need the OmniStudio migration tool and its own matching. Deploy their metadata form with a release, or move them with the OmniStudio tools.' }
                ]
            }
        ]
    },
    {
        key: 'built',
        group: 'daily',
        label: 'What\'s built',
        cards: [
            {
                key: 'built-main',
                title: 'What\'s built and its lock',
                blocks: [
                    { type: 'text', paras: [
                        '**What\'s built** is Release Relay\'s technical document: objects and fields, security and access, Apex by area, components, pipeline files, limits and tests to run. Its counts are read live and count only Release Relay\'s own components (the build\'s package list); other Rly classes in the org are listed apart as demo classes or leftovers.',
                        'An admin can lock the tab with a password (Pipeline → Advanced → What\'s built lock). While it is locked the tab shows only a password field: type it and press **Unlock**. It stays open for you for up to 8 hours; **Lock again** in the header locks it at once.'
                    ] },
                    { type: 'list', items: [
                        'Five wrong tries lock you out for 15 minutes ("Too many tries. Try again at …"), in any browser.',
                        'Forgot the password? Ask a Release Relay admin to set a new one. Admins can see the stored hash, never the password.'
                    ] }
                ]
            }
        ]
    },
    {
        key: 'raise',
        group: 'daily',
        label: 'Raise a release',
        cards: [
            {
                key: 'raise-main',
                title: 'Raise a release',
                aside: SHOT_NOTE,
                blocks: [
                    { type: 'text', paras: [
                        'You build in your developer org and raise releases from it. You need the Release Relay Developer group (or Full Access). New Release has five steps: **Where**, **Org**, **Select**, **Review**, **Raise**.',
                        'Releases always come from a **developer org**. Stage orgs (for example QA) and production are never offered as sources: a hotfix is raised from the developer org that has the fix, and what is in a stage moves on with **Promote** (for example QA → Production).'
                    ] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Choose where the changes come from',
                                who: 'Developer',
                                where: 'New Release → Where should the changes come from?',
                                goal: 'Orgs are grouped by their Salesforce environment, so you find yours fast.',
                                items: [
                                    'Press the tile of your org\'s type: **Developer sandbox or Developer Edition**, **Developer Pro sandbox**, **Partial Copy sandbox** or **Full Copy sandbox**. **Other orgs** shows when an org has no sandbox type yet.',
                                    'Each tile counts the developer orgs in it. A stage of that type is named with "releases arrive here" and can\'t be picked; a tile with no developer org is grey ("None registered").',
                                    'When only one tile has orgs it is chosen for you. Press **Next: pick the org**.'
                                ],
                                check: 'The next step lists the orgs of that type.',
                                problems: [
                                    ['A red line such as "The Git connection isn\'t set up and checked yet (Pipeline tab).", "No stage to release into yet: register the first stage org with its branch (Pipeline tab)." or "No developer org registered yet (Pipeline tab)."', 'An admin fixes it on the Pipeline tab. Until then Next: pick the org stays grey.'],
                                    ['"No developer org yet. An admin registers it on the Pipeline tab with the role Developer."', 'Ask an admin to register your org.']
                                ]
                            },
                            {
                                title: 'Pick your org and how far back to look',
                                who: 'Developer',
                                where: 'New Release → Which … org?',
                                goal: 'The release is read from this org and goes to the first stage of its route.',
                                items: [
                                    'Pick your developer org (with more than 6 there is a search by name or branch). Each org shows its branch and how changes are listed: **Fast: source tracking** or **Metadata API**.',
                                    'Under the list, **Goes to →** names the first stage and its branch.',
                                    '**Changed**: **Last 7 days** (the default), **Last 30 days**, **Any time** or **Since a date…** (pick today or an earlier date). **Changed by**: **Me** (the default) or **Anyone**.',
                                    'Not finding something later? Come back here with **Any time** and **Anyone**: that lists every component in the org, including ones you didn\'t change but the release needs.',
                                    'Press **Next: find changes**. **Back** returns to the tiles.'
                                ],
                                problems: [
                                    ['Your org isn\'t listed', 'An admin registers it on the Pipeline tab (role Developer org) with its sandbox type.'],
                                    ['Your org is grey: "Not connected: check it on the Pipeline tab"', 'An admin presses Check connection on its card; the message names the fix.'],
                                    ['Next: find changes stays grey', 'Pick an org, and with Since a date… pick a date that isn\'t in the future.']
                                ]
                            },
                            {
                                title: 'Select the components',
                                who: 'Developer',
                                where: 'New Release → Select',
                                goal: 'Pick exactly what goes, and the tests that cover your Apex.',
                                items: [
                                    'Types are on the left with counts (Code, Automation, Data model, Access and UI, Other); changes on the right. **Show** custom, standard or both, and search by name or type. The ↻ button reads the org again.',
                                    'Deleted something? Orgs with source tracking list it with a red **Delete** pill. Otherwise pick it with **Delete from <branch> branch…** (see Deleting components).',
                                    'The bar at the bottom counts what you picked. Red means Apex without a test class: "Apex selected without a test class." Press the suggested **+ test class**, or tick it.',
                                    '**Show selection** lists what you picked, with × to remove one; **Clear all** empties it.',
                                    'Press **Next: review**. It stays grey while nothing is picked, while the org is read, or while Apex has no test.'
                                ],
                                check: 'The bar is not red.',
                                problems: [
                                    ['"No changes found in … for this period. Try Any time, or add a component by name."', 'Press **Back**, set **Changed** to **Any time**, and press Next: find changes again.'],
                                    ['"Nothing here changed by you. Switch Changed by to Anyone."', 'Press **Back** and set **Changed by** to **Anyone**.'],
                                    ['A test class doesn\'t show as a test', 'It must contain @IsTest. If it isn\'t in the list, go Back and use Any time and Anyone.'],
                                    ['"<Type> <Name> is both added and deleted."', 'Untick one of the two.']
                                ],
                                links: [{ label: 'Deleting components', to: 'deletions' }],
                                shot: { name: 'select', cap: 'Example from a demo hub (an earlier layout of the page): picked components, with the test rule in the bar.' }
                            },
                            {
                                title: 'Review: title, hotfix, flows, manual steps',
                                who: 'Developer',
                                where: 'New Release → Review before raising',
                                goal: 'Check what goes and tell the people after you what they need to know.',
                                items: [
                                    '**In this release** lists each component with **Compare** and × (remove it). **Compare all** compares them all (see Compare and changes).',
                                    'The box under Source → Target says which tests run, for example "Runs … (RunSpecifiedTests) in every org it deploys to", or "No Apex in this release: deploys run without tests (NoTestRun)."',
                                    'Give the release a **Title** (required) and a **Description (optional)**.',
                                    '**Work items**: the tickets this release delivers. Type one and press Enter or a comma; each chip names the tracker it goes to. Required when the admin made tickets required (see Work items).',
                                    'Urgent fix? With the **Release Relay Hotfix** add-on turn on the **This is a hotfix** chip and answer **Why is this a hotfix?** (see Hotfix).',
                                    'Flows: each shows its version in your org; choose **After deploy** per flow (see Flows).',
                                    'Anything that can\'t be deployed (access, data, setup)? **Add a manual step** (see Manual steps).',
                                    'A blue box says whether the first stage asks for approval, for example "Approval in QA: Always needs approval in QA." (an example).'
                                ],
                                links: [{ label: 'Compare and changes', to: 'compare' }, { label: 'Flows', to: 'flows' }, { label: 'Manual steps', to: 'manual' }, { label: 'Hotfix', to: 'hotfix' }, { label: 'Work items', to: 'workitems' }],
                                shot: { name: 'review', cap: 'Example from a demo hub (an earlier layout of the page): what goes in and which tests run.' }
                            },
                            {
                                title: 'Raise it',
                                who: 'Developer',
                                where: 'New Release → Review → Raise pull request (or Raise hotfix)',
                                goal: 'The hub retrieves the components and the pipeline opens the pull request into the first stage\'s branch.',
                                items: [
                                    'Press **Raise pull request** (**Raise hotfix** for a hotfix). It is grey until there is a title (and a reason for a hotfix) and the test rule is met.',
                                    'The release then shows on the same page and follows itself step by step. **Raise another release** starts again. (Only manual steps? See the next step.)'
                                ],
                                check: 'The release shows Retrieving, then Workflow running, then Validating.',
                                problems: [
                                    ['Failed: "… already matches … for these components. Nothing to commit."', 'The target branch already has these components exactly as your org has them, so there is nothing to release (often: already promoted or merged in). Check the selection, or raise only what differs.'],
                                    ['Failed: "Some components couldn\'t be retrieved from …"', 'Read the reason (a component wasn\'t found or was renamed), fix the selection and raise again.'],
                                    ['"Hotfixes are raised from a developer org now. Pick the developer org that has the fix."', 'Pick the developer org that has the fix.']
                                ],
                                links: [{ label: 'Follow a release', to: 'follow' }]
                            },
                            {
                                title: 'Raise manual steps only (no metadata)',
                                who: 'Developer',
                                where: 'New Release → Select → No metadata — only manual steps',
                                goal: 'A change done by hand (for example profile access) is still tracked, approved, done in order in every org and promoted, without any components.',
                                items: [
                                    'Pick your org as usual. On **Select**, switch on **No metadata — only manual steps** in the bar at the bottom (it clears any ticked components), then press **Next: review**.',
                                    'On Review give it a **Title** and **Add a manual step** for each thing to do (at least one: until then the page says "Manual steps only: add at least one manual step below to raise it."), in order, with Before deploy or After deploy.',
                                    'Press **Raise manual steps**.',
                                    'There is no retrieve, Git branch, pull request, pipeline run, code scan or validation: the release page shows them as "Not needed: manual steps only".',
                                    'It goes straight to approval in the first stage (that org\'s approval rule decides; production always needs an approver). After approval the deployment team checks the steps off; when all of them are Done or Not needed it shows **Deployed** in that org.',
                                    'Promote it like any release: it is listed on the Promote tab with a **Manual steps only** pill. A promotion of only such releases has no pipeline run either; mixed with other releases, only their changes are picked and every manual step goes along in order.'
                                ],
                                check: 'The release shows the Manual steps only pill and goes to Ready for approval.',
                                links: [{ label: 'Manual steps', to: 'manual' }, { label: 'Promote', to: 'promote' }]
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'follow',
        group: 'daily',
        label: 'Follow a release',
        cards: [
            {
                key: 'fo-main',
                title: 'Follow a release',
                blocks: [
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Find it on the Releases tab',
                                where: 'Releases tab',
                                goal: 'See your releases and where each one is.',
                                items: [
                                    '**Raised by**: leave it blank for everyone, or pick a person. Pick yourself and the title reads **My Releases**.',
                                    'Status: **Open** (running, checks failed or waiting for approval; the default), **Checks failed**, **Waiting for the window**, **Deployed**, **Rolled back**, **Failed**, **Rejected** (rejected, cancelled or closed) or **All**. Each shows a count.',
                                    '**Search releases** by number or title, then press Enter.',
                                    '**Export CSV** exports what matches the filters (see History and evidence). **New release** opens New Release.',
                                    '**Live status**: while something runs the list checks every 30 seconds, with a bar counting down; **Check now** checks at once.',
                                    'Each card shows pills (Hotfix, Promotion, Back promote, Manual steps only), the status, the progress bar and the route; a failed one says which step failed and why. Click it to open it on the right; the link button copies a link to it, the arrows widen it.'
                                ],
                                problems: [['"No open releases." (or another chip\'s empty line)', 'Nothing matches: try another status chip, clear Raised by, or clear the search.']],
                                shot: { ill: 'releases-filters', cap: 'Releases tab: Raised by, status, search, Export CSV, live status.', alt: 'Drawing of the Releases tab with callouts 1 Raised by user picker, 2 status filters Open Deployed Failed Rejected All, 3 search, 4 Export CSV, 5 Live status with Check now.' }
                            },
                            {
                                title: 'Read the release page',
                                where: 'Releases tab → a release',
                                goal: 'Everything about one release on one page.',
                                items: [
                                    'The path at the top shows **Raised → Pull request → Checks → Approval → Deploy** (Raised → Approval → Deploy for manual steps only). Under it: Route, Raised by, Raised, Tests and Approved in.',
                                    'Header buttons, when they apply: **Open in Slack** (its card), **Pull request #n**, **Pipeline run**, **Open org ▾**, **Add changes from** the developer org, **Copy summary**, **Roll back**, **Download evidence (PDF)**.',
                                    '**Progress** lists each step with its state and refreshes itself while something runs (Last checked … · next check in, and **Check now**). A red or amber box above the steps gives the reason when something stopped.',
                                    'Under the steps: **Quality gates failed**, **Code scan findings** (priority, rule, where, finding) and **Deployment errors**. Fix them in your org and add the fix (Add changes), or raise again, or ask an approver to bypass a blocking code scan. While **Check again** or **Add changes** runs the checks again, the previous findings and errors are hidden (History keeps them).',
                                    '**Details**: status, code scan, validation, branch, why it is a hotfix, what a promotion carries, deletions, manual steps, Promoted in and the Slack card. Then **Components** and **Changes** (see Compare and changes), **Flows**, **History** (newest first), **Work items** (its tickets, see Work items) and **Manual steps**.',
                                    'Admins and the deployment team see **Open org ▾**: each **Log in to <org>** opens that org\'s login page (its My Domain, or single sign-on) in a new window. It lists the orgs on the release\'s route except production (the hub), where you already are.'
                                ],
                                check: 'A Deployed release shows the deploy id and how each branch was updated.'
                            },
                            {
                                title: 'The buttons at the bottom',
                                where: 'The release page → the bar at the bottom',
                                goal: 'What you can do now, and why a button is grey.',
                                items: [
                                    'While the checks run the buttons are grey: "Actions show when the checks finish."',
                                    '**Check again** runs the code scan and check-only deploy again on the open pull request (Checks failed or Ready for approval), for example after a quality gate or the target changed.',
                                    '**Reject** and **Approve and deploy** are for approvers (see Approve or reject). Others read "An approver approves or rejects it on the Approvals tab."',
                                    'An org approved in Slack only has no Approve button here: "Approved from the Slack card."',
                                    'Into production, with production approval on, only holders of the Production Approver add-on can approve; others read "Approving production needs the Production Approver add-on."'
                                ],
                                problems: [['"Checks can run again on an open pull request that isn\'t approved yet."', 'The release is approved, deploying or closed: nothing to check again.']]
                            },
                            // Build 54: Cancel release.
                            {
                                title: 'Cancel a release (withdraw it)',
                                who: 'The person who raised it, or an admin',
                                where: 'The release page → the bar at the bottom → Cancel release',
                                goal: 'Withdraw a release you no longer want while it is open (any status but Deployed, Rejected, Cancelled or Closed). Reject is different: an approver turns a release down.',
                                items: [
                                    'Press **Cancel release**. The box names the release ("Cancel REL-…?"); write **Why it\'s cancelled** (required) and press **Cancel REL-…**, or **Keep it**.',
                                    'The release becomes **Cancelled** with "Cancelled by <you>: <reason>"; History adds a **Cancelled** entry; its pull request gets the comment "Cancelled in Release Relay by <you>: <reason>" and is closed; its Slack card says Cancelled and loses Approve and Reject. A cancelled promotion frees the releases it carried, so they can be promoted again.',
                                    'While a pipeline run is going the box warns "A pipeline run is going: it may still deploy." Cancelling doesn\'t stop the run: check it in the pipeline. A pull request already merged is left as it is.',
                                    'It can\'t be undone: raise the change again if you need it. Cancelled releases are listed under **Rejected** on the Releases tab.'
                                ],
                                check: 'The release shows Cancelled and the reason; the pull request is closed with your comment.',
                                problems: [
                                    ['No Cancel release button', 'You didn\'t raise it and aren\'t an admin, or it is already Deployed, Rejected, Cancelled or Closed.'],
                                    ['"But the pull request couldn\'t be closed: …" on the release', 'The release is cancelled anyway. Close the pull request in the Git provider; the Git token needs Pull requests: Read and write (Set up → M. Secure your repository).']
                                ]
                            },
                            {
                                title: 'Resolve a conflict',
                                where: 'The release page → Progress → Conflict with <target>',
                                goal: 'Two releases changed the same lines; you decide which lines stay.',
                                items: [
                                    'Press **Resolve conflicts**. The window shows your version and the target\'s side by side.',
                                    'For each file choose **Keep mine**, **Keep <target>\'s** (for example Keep QA\'s) or **Edit** (keep the lines you want and remove the conflict markers). **Next file** goes on.',
                                    'When every file has a choice, press **Resolve and check again**. The page shows Conflicts · Resolving while the pipeline merges and runs the checks again.',
                                    'Only the developer who raised it, or an approver, resolves; everyone else sees **Review the conflicts** (read only).'
                                ],
                                problems: [['"Remove the conflict markers (…) and keep the lines you want." or "The edited file is empty."', 'Finish editing that file, or choose Keep mine or Keep <target>\'s.']],
                                links: [{ label: 'Conflicts between orgs', to: 'conflicts' }],
                                shot: { name: 'conflict', cap: 'Example: your version and the target\'s side by side.' }
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'compare',
        group: 'daily',
        label: 'Compare and changes',
        cards: [
            {
                key: 'cmp-main',
                title: 'Compare and changes',
                blocks: [
                    { type: 'text', paras: ['See what a release changes, line by line: before you raise it (**Compare**, your developer org against the target branch) and after (**Changes**, the pull request\'s files). Looking changes nothing.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Compare before raising',
                                where: 'New Release → Review',
                                goal: 'What your developer org has now against what the target branch has.',
                                items: [
                                    'Press **Compare** on a component under **In this release** (or on a flow), or **Compare all** above the list. The window is called **Compare with** the target.',
                                    'The hub gets your org\'s copy and reads the target branch (usually under a minute), then marks each component **Changed**, **New in this release**, **Same**, **Deleted** or **Not available** (**Checking…** while it reads).',
                                    'Left is the target branch (Target, what is there now), right is your org (Source, what the release brings). Switch **Split** / **Unified**; click **⋯ unchanged lines** to open them. A component with several files has a file picker.',
                                    'Compared: Apex classes and triggers, Visualforce pages and components, flows, layouts, permission sets, Lightning web components and Aura components. Objects, fields, record types and other types show **Not available** ("Compare isn\'t available for … yet"): see them under **Changes** after raising.',
                                    'Static resources and profiles are never compared, in the hub or in the pipeline: their files are large. They show **Not compared: open it in Git.** with a link to the file on the target\'s branch.',
                                    'The hub reads the components a few at a time (5 per part, 3 parts at once), so each row shows **Waiting**, **Comparing**, then its result, and the first one ready opens by itself. A part that can\'t be read shows **Couldn\'t read** on its rows with **Try again**; the other components carry on.',
                                    'Up to 50 components in the hub. With more, or when a file is **Too large** for the hub, press **Compare all in the pipeline**: the hub sends your org\'s copy to Git in parts and the pipeline compares every component there (usually 1–2 minutes; the run shows on the Pipeline Monitor as **Compare**). The pipeline also compares types the hub can\'t, such as objects and fields, and shows a very large file as its changed lines only. It needs a GitHub connection with pipeline files version 22 or later.',
                                    'A flow shows its versions on both sides, for example Version 8 · Draft against Version 7 · Active (an example). When your org has an active version and a newer draft, the copy compared is the active one, and the window says the newer version isn\'t compared.'
                                ],
                                check: 'Close and press Compare again to read a fresh copy.'
                            },
                            {
                                title: 'See the changes after raising',
                                where: 'The release page → Details → Changes',
                                goal: 'The pull request\'s files as your Git provider shows them, for releases and promotions.',
                                items: [
                                    'The **Changes** tab is next to **Components** once the release has a pull request. Its files load the first time you open it ("Reading the pull request\'s files…"), each with its lines added and removed.',
                                    'Click a file to see its diff in a wide window; ↑ and ↓ (or the file list) step through the files. **Open in GitHub ↗** (or GitLab) opens the pull request\'s files.',
                                    'A binary or very large file says **No preview: open in GitHub.** Up to 300 files are listed ("Showing 300 of … files"); the pull request has the rest.',
                                    'GitLab merge requests are read the same way. With Bitbucket or Azure DevOps the tab says "Changes are shown for GitHub and GitLab only; open the pull request." If reading fails, the tab says why and has **Try again**.'
                                ]
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'append',
        group: 'daily',
        label: 'Add changes to an open release',
        cards: [
            {
                key: 'ap-main',
                title: 'Add changes to an open release',
                blocks: [
                    { type: 'text', paras: ['When the checks of a release fail (or it waits for approval) and the fix is in the same developer org, add the fix to the same release instead of raising a new one. Its branch and pull request stay; the checks run again.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Open Add changes',
                                who: 'Who raised it, or an admin',
                                where: 'The release page',
                                goal: 'A release raised from a developer org, with an open pull request, whose checks failed or that waits for approval, not approved yet, with nothing running.',
                                items: [
                                    'Press **Add changes from** the release\'s developer org (header of the release page). The button shows only when all of the above is true; it is grey while a step runs.',
                                    'New Release opens at **Select**, titled **Add changes to** the release, for that org and the release\'s target: Where and Org are skipped.'
                                ],
                                problems: [
                                    ['"Changes can be added to an open release whose checks failed or that waits for approval, before it\'s approved."', 'The release is approved, deploying or closed: raise a new release instead.'],
                                    ['"Only the person who raised … or an admin can add changes to it."', 'Ask them, or raise your own release.'],
                                    ['"Changes can be added only to a release raised from a developer org."', 'Promotions and back promote syncs take no added changes.']
                                ]
                            },
                            {
                                title: 'Pick what to add',
                                where: 'New Release → Select',
                                items: [
                                    '**Changed**: Last 7 days, Last 30 days or Any time, above the list. The route is fixed to the release\'s.',
                                    'What is in the release already shows ticked and greyed, with **In** and the release number: it can\'t be unticked.',
                                    'Tick the new components (or deletions). Apex needs a test class: one you tick now, or one the release runs already.',
                                    '**Show selection** lists what is **Already in** the release and what you are **Adding**. The bar says "Nothing added yet" until you tick something. **Cancel** goes back to the release.'
                                ]
                            },
                            {
                                title: 'Review and add',
                                where: 'New Release → Review',
                                items: [
                                    'Review says what is added, for example **Adds 1 component to** the release **· the checks run again**. Compare works as for a new release.',
                                    'Press **Add to** the release. You are back on the release page (Release · the number): the changes are committed to its branch, its pull request updates, then the code scan and check-only deploy run again (with the release\'s tests and the new ones).',
                                    'Until the pipeline confirms the add, Components says **Adding … changes from** the org. If the pipeline fails to add them, they leave the release again (counts, tests and deletions as before) and the release says **Not added: the pipeline failed**: press **Add changes** to try again.'
                                ],
                                problems: [
                                    ['"… already matches … for these components. Nothing to add."', 'The release\'s branch already has these components as your org has them: pick what actually changed.'],
                                    ['"Not added: the pipeline failed to add the changes from …"', 'The run\'s reason is in brackets (open the run for the log). Fix it, then press **Add changes** again.']
                                ],
                                check: 'The History shows **Changes added**: Added 1 component from the developer org, and any approval given before is cleared.'
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
                                    'Pick what you deleted with **Delete from <branch> branch…** (below). There is no **Find deleted components** scan any more (it was retired): you choose each deletion from the branch, and the branch is read one folder per request.',
                                    'Picklist values aren\'t components: remove a value in the field (Salesforce makes it inactive in the target, it can\'t delete it through a deploy) or add a manual step to delete it in Setup.'
                                ]
                            },
                            {
                                title: 'Delete from the branch',
                                where: 'New Release → Select → Delete from <branch> branch…',
                                text: [
                                    'Pick what to delete straight from the target\'s branch (the first stage\'s, for example **qa**), without deleting it in your org first. Useful after a refresh, or for something that never was in your org.',
                                    'The window reads the branch a folder at a time: types on the left with their counts, components on the right with search, **All** / **Chosen**. Press **Delete** on a component to choose it (press again to drop it); **Add N to the release** puts them in the release\'s deletions.',
                                    'Each component says whether your org still has it: **Still in** your org (amber: delete it there too, or a later release from it can bring it back) or **Not in** your org. Components already in the release say **In release**.',
                                    'Greyed with the reason, and not selectable: Salesforce\'s own objects and fields, org settings, standard value sets, standard profiles, files that hold every rule of an object (workflow, sharing, assignment, auto-response, escalation and matching rules), labels and translations, and managed package components (install or upgrade the package instead).',
                                    'The rest is as for any deletion: checks in the first stage catch anything still using it, then approval, deploy and promotion. Records a queue owns stay where they are: add a manual step to move them first.'
                                ]
                            },
                            {
                                title: 'Review',
                                where: 'New Release → Review',
                                text: [
                                    'Deletions are listed in red under **Deleted from** the target. A component can\'t be both added and deleted in one release.',
                                    'Deleting Apex needs no test class unless Apex is also added. Delete its test class too (Review warns when `<Name>Test` still refers to it). Into production the org\'s local tests run (RunLocalTests), as Salesforce requires, unless you pick test classes; sandboxes skip tests.'
                                ],
                                problems: [['"<Type> <Name> isn\'t in <branch>, so there\'s nothing to delete."', 'The component isn\'t in the target\'s branch: untick it.'],
                                    ['"A release takes at most 2,000 components (…): split the release." (or 500 deletions)', 'Raise it as two or more releases. An add to an open release takes up to 100 components.']]
                            }
                        ]
                    },
                    { type: 'note', text: 'An org whose approval rule is **Only when the release contains…** with **Deletions** ticked always asks for approval when a release deletes something. The evidence PDF lists the deletions per release.' }
                ]
            }
        ]
    },
    {
        key: 'approve',
        group: 'daily',
        label: 'Approve or reject',
        cards: [
            {
                key: 'approve-main',
                title: 'Approve or reject',
                blocks: [
                    { type: 'text', paras: ['You decide what goes into each stage. You need the Release Relay Approver group; releases into production can also need the Production Approver add-on (below). Each org card on the Pipeline tab sets **whether** a release into that org needs you (its approval rule) and **where** it is approved: **Approve in Salesforce**, **Approve in Slack**, and optionally your Git provider\'s reviewers too.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'See what\'s waiting',
                                who: 'Approver',
                                where: 'Approvals tab',
                                goal: 'Only releases whose checks finished are listed.',
                                items: [
                                    '**Ready for approval**, or **Checks failed**. Hotfixes come first, with a red **Hotfix** pill and the reason, then the oldest first. Other pills: **Promotion**, **Manual steps only**, **Deletes n**, **n manual steps** (open manual steps).',
                                    '**All** or **Mine** (raised by you), each with a count. Search by release number, title or org.',
                                    'Open one to see its progress, code scan findings, deployment errors and components on the right.'
                                ],
                                problems: [['"Nothing waiting for approval."', 'Nothing has finished its checks. Running releases are on the Releases tab.']]
                            },
                            {
                                title: 'Approve and deploy',
                                who: 'Approver',
                                where: 'The release page → Approval',
                                goal: 'Merges the pull request and deploys to the target org with the release\'s tests.',
                                items: [
                                    'Add an **Approval comment** if useful and press **Approve and deploy** in the bar at the bottom.',
                                    'If the target\'s branch changed after the checks passed, the checks run again first: "… changed after the checks passed, so they are running again." Approve again when they pass.',
                                    'The button shows only when the target org is approved in Salesforce. With Approve in Salesforce off the page says "Approved from the Slack card." and the Approval step "Waiting for approval in Slack."'
                                ],
                                check: 'The release shows Deploying, then Deployed (or Deploy failed with the reason).',
                                problems: [
                                    ['Approve and deploy is grey', 'The checks are still running, or another action is in progress.'],
                                    ['"Only approvers can do this (permission set Release Relay Approver)."', 'Ask an admin for the Release Relay Approver group.']
                                ]
                            },
                            {
                                title: 'Releases into production: the Production Approver add-on',
                                who: 'Approver',
                                where: 'The release page → Approval',
                                items: [
                                    'When an admin has turned on **Production approval needs the add-on** (Pipeline → Approvals & Slack → Approvals), only holders of the **Release Relay Production Approver** add-on approve releases into production, here and in Slack. Every other org is approved by the Approver group as before.',
                                    'Without the add-on the page says "Approving production needs the Production Approver add-on." instead of Approve and deploy; Slack answers privately with the same sentence and nothing changes.',
                                    'A two-approver hotfix into production needs the add-on for both approvers.'
                                ],
                                links: [{ label: 'Roles and access', to: 'access' }]
                            },
                            {
                                title: 'Bypass a blocking code scan',
                                who: 'Approver',
                                where: 'The release page → Bypass code scan',
                                items: [
                                    'On a release with **Checks failed** because of the code scan, the page says **Code scan blocked this release.** Write **Why the findings are accepted** (at least 10 characters) and press **Bypass code scan**.',
                                    'Your name and the reason are kept on the release, which then waits for approval as usual.',
                                    'A failed validation, a conflict, coverage or missing tests can\'t be bypassed: "The validation failed too, and that can\'t be bypassed: fix it and raise again."'
                                ],
                                problems: [['"Say why the findings are accepted (at least 10 characters)."', 'Write a longer reason.']]
                            },
                            {
                                title: 'Reject',
                                who: 'Approver',
                                where: 'The release page → Reject',
                                items: ['Write the **Approval comment** (required to reject) and press **Reject**. It works on Ready for approval and Checks failed. The pull request is closed with your comment, so the developer sees why.'],
                                problems: [['"couldn\'t close the pull request"', 'The Git token needs the permissions in Set up → M. Secure your repository, step 1 (Pull requests and Issues: Read and write).']]
                            },
                            // Build 54: Reject versus Cancel release.
                            {
                                title: 'Reject or cancel?',
                                where: 'The release page',
                                items: [
                                    '**Reject**: an approver turns the release down (Ready for approval or Checks failed), with an approval comment.',
                                    '**Cancel release**: the person who raised it, or an admin, withdraws it while it is open, with a reason. Approvers who didn\'t raise it reject instead. Both close the pull request with the comment and edit the Slack card; a cancelled release says Cancelled, not Rejected.'
                                ],
                                links: [{ label: 'Follow a release', to: 'follow' }]
                            },
                            {
                                title: 'Hotfixes that need 2 approvers',
                                who: 'Approver',
                                where: 'The release page',
                                items: [
                                    'If the org\'s Approval section has **Hotfixes into <org> need 2 approvers** on, a hotfix needs two different approvers, and the person who raised it can\'t approve it.',
                                    'After the first approval the page says "Approved by … Waiting for a second approver: someone else, not the person who raised it."'
                                ],
                                problems: [
                                    ['"You raised this hotfix, so two other people approve it."', 'Ask two other approvers.'],
                                    ['"You already approved it. A second approver is needed."', 'Ask another approver.']
                                ]
                            },
                            {
                                title: 'Approved automatically: why',
                                where: 'The release page and Slack',
                                items: ['When the org\'s rule needs no approver the release is **Approved automatically** (Approved via Rule) and the Approval step says why, for example **Approved automatically: only reports and list views**.'],
                                links: [{ label: 'Approval rules', to: 'approvalrules' }]
                            },
                            {
                                title: 'Approve in Slack or in Git',
                                where: 'The org\'s Slack channel · your Git provider',
                                items: [
                                    '**In Slack**: the release card shows Approve and Reject to linked approvers (see Slack in daily use).',
                                    '**Git reviewers**: with **Also require <provider> reviewers before deploying**, the provider\'s own reviewers approve the deploy there as well. Until they do the release says "Waiting for <provider> reviewers before deploying."'
                                ],
                                links: [{ label: 'Slack in daily use', to: 'slack' }]
                            },
                            {
                                title: 'Manual steps hold the deploy',
                                who: 'Deployment team',
                                where: 'The release page → Manual steps',
                                items: ['An approved release with open **Before deploy** steps waits: **Approved. Deploys when the deployment team finishes n manual steps before deploy.** The last tick starts the deploy.'],
                                links: [{ label: 'Manual steps', to: 'manual' }]
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'approvalrules',
        group: 'daily',
        label: 'Approval rules',
        cards: [
            {
                key: 'ar-main',
                title: 'Approval rules per org',
                blocks: [
                    { type: 'text', paras: ['Each org on the route decides when a release into it needs a person to approve it. The scan, the check-only deploy and the tests always have to pass first: a rule only decides what happens after that.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Set the rule',
                                who: 'Admin',
                                where: 'Pipeline → Orgs → click the org → Edit → Approval',
                                goal: 'Decide per org when a person must look.',
                                items: [
                                    '**Approval rule for releases into** the org: **Always**, **Only when it contains…** or **Never** (deploy when the scan, check-only deploy and tests pass). Never is grey for production: "Production always needs approval."',
                                    'With Only when it contains…: tick the **Kinds of change that need approval** (table below). At least one: "Pick at least one kind of change."',
                                    '**Code scan for releases into** the org: Follow the Git connection, Always scan or Don\'t scan.',
                                    'Where it is approved: **Approve in Salesforce** and/or **Approve in Slack** (Slack only once it is set up). Either is enough; the last one on can\'t be switched off.',
                                    'Optional: **Also require <provider> reviewers before deploying** and **Hotfixes into <org> need 2 approvers**. Then **Save**.'
                                ],
                                text: ['Only stages and the hub have an Approval section. Developer orgs raise releases and back promote orgs have their own Back promote section.'],
                                check: 'The org\'s card shows the rule, for example Always · Code scan: Follows Git (on); its window spells it out, for example "Only when the release contains: Flows, Deletions".',
                                shot: { ill: 'approval-rule', cap: 'The Approval part of an org\'s Edit window.', alt: 'Drawing of the Approval section with callouts 1 approval rule Always, Only when, Never, 2 kinds of change, 3 hotfixes need 2 approvers, 4 Approve in Salesforce and Approve in Slack, 5 also require Git reviewers.' }
                            }
                        ]
                    },
                    {
                        type: 'table',
                        cols: ['Approval rule', 'What happens when the checks pass'],
                        rows: [
                            ['**Always** (the default)', 'The release waits for an approver.'],
                            ['**Only when it contains…**', 'It waits for an approver only if it has one of the ticked kinds of change. Otherwise it is approved automatically and deploys.'],
                            ['**Never**', 'Approved automatically and deployed. Not allowed for production (the hub org): pick Always or Only when it contains….']
                        ]
                    },
                    {
                        type: 'table',
                        cols: ['Kind of change', 'Counts'],
                        rows: [
                            ['Apex classes and triggers', 'Apex classes, Apex triggers'],
                            ['Flows', 'Flows and flow definitions'],
                            ['Profiles and permission sets', 'Profiles, permission sets, permission set groups, custom permissions, muting permission sets'],
                            ['Objects and fields', 'Objects, fields, record types, validation rules'],
                            ['Deletions', 'The release deletes something'],
                            ['Manual steps', 'The release has manual steps (including Leave inactive on a flow)'],
                            ['Hotfixes', 'The release is a hotfix'],
                            ['Anything else', 'Everything not in another box: layouts, reports, list views, static resources, Lightning components…']
                        ]
                    },
                    {
                        type: 'list',
                        items: [
                            '**Approved automatically**: Approved via **Rule**, no approver, with the comment **Approved automatically:** and the reason; it then deploys exactly as after an approval. Manual steps before deploy still hold the deploy.',
                            'The Approval step and the Slack card show why, for example **Needs approval: contains a Flow and a Profile**.',
                            'Each stop decides for itself: a release into the first stage follows that org\'s rule; a promotion into production follows production\'s. For example (an example only): a test stage set to Never, and production set to Always.',
                            'Who may approve is separate from the rule: with **Production approval needs the add-on** on, a release into production waits for someone with the Production Approver add-on (see Approve or reject).'
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
                    { type: 'text', paras: ['Some changes can\'t be deployed as metadata: profile or permission access, data loads, setup settings, a connected app setting, a scheduled job to start. Add them to the release as **manual steps**. They travel with the release through every org on the route and to back promote orgs, in order, and the **deployment team** marks each one **To do**, **Done** or **Not needed** per org. A step can carry **files** (the instructions: a CSV to load, a PDF of steps) and each org\'s run can carry **proof** (a success file, a screenshot). They are standard Salesforce Files: nothing is copied.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Add them when you raise',
                                who: 'Developer',
                                where: 'New Release → Review → Manual steps',
                                items: [
                                    'Press **Add a manual step**: a **Title**, the **Category** (Profile or permission access, Data, Setup configuration, Managed package, Other), **When** (Before deploy or After deploy) and the exact **Instructions**, for example `Profile Sales User: Account.Region__c read/edit`.',
                                    'Installing or upgrading a **managed package** is a manual step (category **Managed package**), usually **Before deploy**: the package, version and install link, who it is installed for and any licences. Release Relay never moves managed-package components: they come with the package.',
                                    '**Also in back promote orgs** is on by default. **Orgs**: all orgs on the route, or pick the orgs it applies to.',
                                    'Order them with the up and down arrows: the deployment team does them in that order. Up to 50 steps.',
                                    'A flow set to **Leave inactive** adds the step **Activate flow <name>** (Setup, After deploy, every org) for you.',
                                    '**Attach files** is part of the Add a manual step form (and of Edit step): press **Upload Files** or drop files on it while you fill in the step. Any type, up to the Salesforce file size limit. They upload straight to Salesforce Files and belong to the step once you press **Add step** or **Save step**; **Cancel** deletes the files you uploaded in that form. Until you raise they wait in your own files; **Raise pull request** links them to the saved steps. The step then lists its files; **×** removes one.',
                                    'Until the release is first deployed, the person who raised it (or an admin) can add, edit, reorder and delete steps on the release page, and attach or remove step files until it is approved.',
                                    'Nothing to deploy, only steps? On Select switch on **No metadata — only manual steps** and raise **manual steps only**: no Git or pipeline, approval then the steps (see Raise a release, step 6). Such a release keeps at least one step.'
                                ],
                                links: [{ label: 'Raise a release', to: 'raise' }]
                            },
                            {
                                title: 'The deployment team checks them off',
                                who: 'Deployment team',
                                where: 'The release page → Manual steps → one tab per org',
                                goal: 'A record of who did what, where and when.',
                                items: [
                                    'Pick the org\'s tab: each shows how many steps are open there.',
                                    'Press **Log in to <org> ↗** on the tab to open that org\'s login page in a new window and do the step there (not on the production tab: you are already in it).',
                                    'Under each step, **Step files** lists its files: **Download** for every file, **Preview** for PDFs and images (the standard Salesforce preview).',
                                    'Do the step, then press **Done** in the **In <org>** row (To do | Done | Not needed): the page records who did it and when.',
                                    '**Not needed** asks why (for example: already set in this org). **To do** puts a step back to do.',
                                    '**Proof in <org>** → **Add proof**: upload the evidence for that org, for example the Data Loader success file. Proof belongs to that org\'s run only: each org has its own, and it stays open after approval. Whoever added it (or an admin) can remove it.',
                                    '**Show instructions** opens what exactly to do.',
                                    '**Add a manual step** adds one (until the first deploy).'
                                ],
                                text: ['Only the Release Relay Deployment Team and Admin groups (custom permission `RLY_Deploy_Team`, which `RLY_Admin` includes) mark steps, add proof and see **Log in to <org> ↗** and **Open org ▾**. Everyone else, developers included, reads the steps and their runs. Only the login address is shown, never a password or other sign-in detail. On a phone (480px and narrower) Download and Preview become icon buttons and Not needed reads **N/A**.'],
                                check: 'The tab shows no open steps; the release no longer shows "n manual steps".',
                                shot: { ill: 'manual-steps', cap: 'Manual steps: a tab per org, tick, Not needed, instructions.', alt: 'Drawing of the Manual steps card with callouts 1 one tab per org with open counts, 2 tick a done step, 3 Not needed, 4 Show instructions, 5 Add a manual step.' }
                            },
                            {
                                title: 'Before deploy and after deploy',
                                where: 'The release page → Manual steps',
                                items: [
                                    '**Before deploy**: the deploy into an org doesn\'t start until that org\'s before deploy steps are done. The last tick starts the deploy.',
                                    '**After deploy**: shown as open work in that org after the deploy. The release and the Approvals tab show **n manual steps** while any are open.',
                                    'An org whose approval rule ticks **Manual steps** always asks for approval when a release has any.'
                                ]
                            },
                            {
                                title: 'They follow promote and back promote',
                                where: 'Promote tab and back promote orgs',
                                items: [
                                    'A promotion carries the manual steps of every release it carries, in deploy order. The Promote tab lists them under the bundle.',
                                    'A back promote sync carries the steps with **Also in back promote orgs** of every release the org is behind.',
                                    'Steps scoped to some orgs only show up in those orgs.',
                                    'Carried steps show the original step\'s files (from REL-…), not copies; each org gets its own proof. A file that should stay out of an org: mark the step **Not needed** there.'
                                ]
                            },
                            {
                                title: 'Files lock when the release is approved',
                                where: 'The release page → Manual steps → Step files',
                                goal: 'Approvers see exactly the files they approve, and those files can\'t change afterwards.',
                                items: [
                                    'From approval on, step files show **🔒 Locked: approved files** (hover it: who approved them and when). No upload, no **×**. To change them, reject the release or raise a new one.',
                                    'The lock is a server check, not only the screen: adding or removing a file on the step, or uploading a new version of a locked file, is refused with **Files on this step are locked: the release is approved.** A step with locked files can\'t be deleted either.',
                                    'Proof on the runs stays open after approval.',
                                    'Deleting the whole file from Files home (its owner can) is not stopped by the lock: History still shows it was attached, but the card and the evidence no longer list it.'
                                ]
                            },
                            {
                                title: 'Files in History and evidence',
                                where: 'The release page → History; Download evidence (PDF); Releases → CSV',
                                items: [
                                    'History records **Attached**, **Removed**, **Proof added** and **Downloaded** (the card\'s Download button only, not Files home). The **Files** chip shows only these.',
                                    'The evidence PDF has a **Files** table after Manual steps: step, file, size, attached by, when, org for proof; files removed show **Removed**. The Releases CSV has a **Files** column. Files are listed, not embedded.'
                                ]
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'flows',
        group: 'daily',
        label: 'Flows',
        cards: [
            {
                key: 'fl-main',
                title: 'Flows: versions and activation',
                blocks: [
                    { type: 'text', paras: ['A flow is deployed as the version that is newest in your developer org. Whether that version is then **active** in each org is your choice on the review step.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Choose what happens after deploy',
                                who: 'Developer',
                                where: 'New Release → Review → Flows → After deploy',
                                goal: 'Each flow shows its newest version in your org, for example **Version 4 · Draft · active: 3**.',
                                items: [
                                    'Per flow pick: **Keep as in** your org (the default: deployed with the status it has in your org), **Activate in each org** (after each successful deploy the hub makes it active), or **Leave inactive: add a manual step to activate**.',
                                    'After the deploy, the release page → Flows shows one line per flow and org, for example `QA v9 active · Production v9 active` (an example only), or why activation failed.'
                                ],
                                text: ['A draft deploys inactive: the orgs keep running their current version unless you choose Activate. A promotion carries the choices of the releases it carries: Activate wins over Keep.'],
                                problems: [['A flow: activation failed', 'The org\'s integration user needs **Manage Flow**, or the version has errors in that org. Activate it in Setup → Flows, or raise again.']],
                                shot: { ill: 'flows-block', cap: 'Review → Flows: After deploy per flow; the result per org on the release page.', alt: 'Drawing of the Flows block with callouts 1 the After deploy choice per flow, 2 the result per org on the release page.' }
                            }
                        ]
                    },
                    {
                        type: 'note',
                        text: 'Production: with **Deploy processes and flows as active** on (Setup → Process Automation Settings), an active flow version deploys active, and Salesforce then requires the Apex tests that run in the deploy to cover it (flow test coverage). With it off, flows arrive in production inactive and Activate in each org activates them after the deploy.'
                    },
                    { type: 'links', links: [{ label: 'Set up: Process Automation Settings', to: 'setup-settings' }] }
                ]
            }
        ]
    },
    {
        key: 'triggers',
        group: 'daily',
        label: 'Switch a trigger off or on',
        cards: [
            {
                key: 'trg-main',
                title: 'Switch a trigger off or on',
                blocks: [
                    { type: 'text', paras: ['A trigger deploys with the status it has in your developer org. Switched off (inactive), it needs no test class and no coverage.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Untick Is Active in your developer org',
                                who: 'Developer',
                                where: 'Developer org → Setup → Apex Triggers → Edit',
                                text: ['To switch it on again later, tick **Is Active** and raise it the same way (it then needs its test class).']
                            },
                            {
                                title: 'Raise the trigger',
                                where: 'New Release → Select → Review',
                                text: [
                                    'Tick the trigger. Review shows its status, for example `OrderTrigger · Inactive: deploys switched off in QA and Production` (an example only). No test class is needed for it.',
                                    'The release page and the Slack card say **Switches off: OrderTrigger**.'
                                ]
                            },
                            {
                                title: 'It deploys inactive',
                                text: ['Sandboxes deploy it without tests. Production runs the org\'s local tests (RunLocalTests), as Salesforce requires for any Apex, unless the release has test classes. The coverage gate leaves inactive triggers out.']
                            }
                        ]
                    },
                    { type: 'links', links: [{ label: 'Deleting components', to: 'deletions' }] }
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
                    { type: 'text', paras: ['A hotfix is a release from a **developer org**, marked urgent with a reason. It goes through the first stage like any release, is promoted to production on its own, and is then merged back down so no org overwrites it. Only users with the **Release Relay Hotfix** add-on (`RLY_Hotfix_Addon`, also in Full Access) can mark a release as a hotfix; the Admin group alone doesn\'t. Approval is never skipped.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Raise it from the developer org that has the fix',
                                where: 'New Release → Review',
                                text: ['Pick your developer org and the components as usual. On the review step turn on the **This is a hotfix** chip, say why (required, up to 255 characters) and press **Raise hotfix**. Its branch is `hotfix/rel-xxxxx`. It gets the same scan, check-only deploy, tests and approval into the first stage as any release. Stage orgs aren\'t offered as sources: fix it in a developer org.']
                            },
                            {
                                title: 'Approve it first',
                                where: 'Approvals tab and Slack',
                                text: ['Hotfixes are listed first, with the reason. The Slack card starts with **Hotfix:** and shows **Why:**. Whether an approver is needed follows the org\'s approval rule: give the org **Always**, or tick **Hotfixes**, so every hotfix waits for one. Into production it can need two approvers, and with production approval on both need the Production Approver add-on.']
                            },
                            {
                                title: 'Promote it on its own',
                                where: 'Promote tab',
                                text: ['When the hotfix is deployed to the stage, it waits on the Promote tab, hotfixes first. Tick it on its own: **Promote hotfix to** the next stop. The next stop gets each file the hotfix changed as it is in the stage, so an older release that changed the same file goes with it; other work waiting in the stage stays there.'],
                                links: [{ label: 'Promote', to: 'promote' }]
                            },
                            {
                                title: 'Merged back down',
                                where: 'The release page',
                                text: ['After the deploy to production the hub merges production\'s branch into every stage branch and then every developer branch. The release page shows each one: **Done**, or **n to review** when a branch conflicts with work in progress. Nothing is forced: merge that branch by hand.']
                            }
                        ]
                    },
                    { type: 'links', links: [{ label: 'The hotfix path, drawn', to: 'moves', kind: 'neutral' }] }
                ]
            }
        ]
    },
    {
        key: 'rollback',
        group: 'daily',
        label: 'Roll back a release',
        cards: [
            {
                key: 'rb-main',
                title: 'Roll back a release',
                aside: 'Admins and deployment team',
                blocks: [
                    { type: 'text', paras: ['Before every deploy into an org, the pipeline saves a **snapshot** of the components the deploy changes, as they are in that org (branch `release-relay-snapshots`). **Roll back** deploys that snapshot back: the org returns to how it was before the release. Git is not changed, and the release keeps its status.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Open the release and press Roll back',
                                who: 'The Release Relay Admin or Deployment Team group',
                                where: 'Releases tab → the release → Roll back',
                                items: ['The button shows only to admins and the deployment team, on a deployed release. It is grey while a deploy or rollback runs ("A deploy or rollback is running").']
                            },
                            {
                                title: 'Pick the org, read what will be restored and removed, and write why',
                                where: 'Roll back dialog',
                                items: [
                                    '**Org to roll back**: one chip per org the release (or the promotion that carried it) was deployed to, with when. An org without a snapshot shows **No snapshot** (or **No Git environment**) and can\'t be picked.',
                                    '**What will happen**: the components restored to how they were, the components the release added that are removed, and a warning when a later release deployed the same component to the same org (rolling back undoes that change too).',
                                    '**Tests in production**: this release\'s tests (the default) or all local tests. No tests run in a sandbox rollback.',
                                    '**Why roll back** is required; it goes into the history, the evidence PDF and the Slack card. **Roll back** stays grey until an org and a reason are given; **Cancel** changes nothing.'
                                ],
                                problems: [
                                    ['"This release hasn\'t been deployed to an org that can be rolled back."', 'No org has a snapshot of this release: fix it with a new release instead.'],
                                    ['"A rollback of this release is running. Wait for it to finish."', 'Wait for the page to show Rolled back or Rollback failed.']
                                ]
                            },
                            {
                                title: 'Press Roll back',
                                where: 'The release page',
                                text: ['The page shows **Rolling back in <org>**, then **Rolled back in <org>** (or **Rollback failed in <org>** with Salesforce\'s errors; the org is then unchanged and you can try again).']
                            },
                            {
                                title: 'Fix Git with a new release',
                                where: 'New Release',
                                text: ['Git still has the change. Raise a new release that fixes the branch (revert or correct the code).']
                            }
                        ]
                    },
                    { type: 'note', text: 'A snapshot is taken before every deploy by pipeline version 13 or later. Release Relay\'s own components are never rolled back. The Releases tab lists rolled back releases under their own chip, and Export CSV has **Rolled back in** and **Rolled back on** columns. On the Promote tab a release rolled back in the stage it waits in shows **Rolled back in** that stage: it can still be ticked, and promoting it sends the change on, because Git still has it.' },
                    { type: 'links', links: [{ label: 'What rollback means at each stop', to: 'moves', kind: 'neutral' }] }
                ]
            }
        ]
    },
    {
        key: 'values',
        group: 'daily',
        label: 'Per-org values',
        cards: [
            {
                key: 'val-main',
                title: 'Per-org values',
                aside: 'Developers and Git admins',
                blocks: [
                    { type: 'text', paras: ['Some values differ per org: an endpoint URL, an email address, a username in a named credential or a custom metadata record, a record id. Keep one placeholder in Git and let the pipeline put each org\'s value in when it deploys: in a release the value is a placeholder, and each deploy fills in that org\'s value.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Add the value per org',
                                who: 'Developer or Git admin',
                                where: 'Pipeline → Advanced → Per-org values → Edit .relay/values.json ↗ (or Create .relay/values.json ↗)',
                                items: [
                                    'Open **Advanced** on the Pipeline tab and press the link beside the **Per-org values** title. It opens your Git provider\'s editor for `.relay/values.json` on the pipeline branch. When the file isn\'t there yet the link reads **Create .relay/values.json ↗** and opens a new file with a starter: one example value with a column per org\'s Git environment.',
                                    'Add a name with a value per org, keyed by each org\'s **Git environment**. Example: `{ "values": { "PAYMENT_URL": { "dev": "https://dev.pay.example", "qa": "https://qa.pay.example", "prod": "https://pay.example" } } }`.',
                                    'Names use capital letters, digits and `_` (up to 60). Keys starting with `_` (such as the starter\'s `_help`) are ignored.',
                                    'Commit the change in your Git provider, then reload the Pipeline tab: the table shows the names, a column per org in route order, and "— no value" where one is missing.'
                                ],
                                text: ['No Pipeline tab (it is for admins)? Open `.relay/values.json` on the pipeline branch in your Git provider and edit it there.']
                            },
                            {
                                title: 'Write the placeholder where the value goes',
                                who: 'Developer',
                                where: 'Your code or metadata',
                                text: ['Write `{{relay:PAYMENT_URL}}` (your name in place of the example) where the value goes.']
                            },
                            {
                                title: 'Raise as usual',
                                where: 'New Release',
                                text: ['Each org gets its own value when the pipeline validates and deploys. When it retrieves from an org it turns that org\'s values back into placeholders, so Git keeps the placeholder.']
                            }
                        ]
                    },
                    { type: 'note', text: 'Every org on the route needs a value, or the check fails and says which (for example "PAYMENT_URL has no value for qa in .relay/values.json"); folded, the Per-org values card shows a pill such as **1 missing value**. Values shorter than 6 characters aren\'t turned back into placeholders on retrieve. Values are in Git, so never put passwords there. The Pipeline tab only shows them: you change them in Git. If the file isn\'t valid JSON the section says ".relay/values.json isn\'t a valid JSON object, so the values can\'t be shown."' }
                ]
            }
        ]
    },
    {
        key: 'gates',
        group: 'daily',
        label: 'Quality gates',
        cards: [
            {
                key: 'gate-main',
                title: 'Quality gates',
                aside: 'Git admins',
                blocks: [
                    { type: 'text', paras: [
                        'Quality gates are rules every release must pass before it can be approved. They live in the repository in `.relay/gates.json` on main (the pipeline branch); all of them are optional.',
                        'The Pipeline tab shows them under **Advanced → Quality gates**, one line each, set or not. The link beside the title opens your Git provider\'s editor: **Edit .relay/gates.json ↗**, or **Create .relay/gates.json ↗** when the file isn\'t there yet (a new file with a starter: scan at priority 2, 75% per class, tests for Apex). Commit it in your Git provider; the next release uses it.'
                    ] },
                    {
                        type: 'table',
                        cols: ['Gate', 'In .relay/gates.json', 'What it does'],
                        rows: [
                            ['Code scan', '`"scan": { "failAtPriority": 2 }`', 'The code scan fails when a finding is at that priority or higher (1 = most serious).'],
                            ['Coverage per class', '`"coverage": { "minimumPerClass": 75 }`', 'The validation fails when a deployed Apex class is below it.'],
                            ['Coverage org-wide', '`"coverage": { "minimumOrgWide": 75 }`', 'The validation fails when the org-wide coverage is below it (when Salesforce reports it).'],
                            ['Tests for Apex', '`"tests": { "requireForApex": true }`', 'A release with Apex and no tests fails before anything is sent to the org.']
                        ]
                    },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'When a gate fails',
                                where: 'The release page → Progress',
                                items: [
                                    'The release shows **Checks failed**, and a red box **Quality gates failed** lists each reason as the pipeline wrote it. In the scan findings, the findings that broke the gate have a red priority.',
                                    'An approver can still accept the code scan\'s findings with a reason (as today). Coverage and missing tests can\'t be bypassed: fix it and press **Check again**.'
                                ]
                            }
                        ]
                    },
                    { type: 'note', text: 'Without `.relay/gates.json` Salesforce\'s own rules still apply (for example 75% coverage in production): the section says "No quality gates yet — add them in .relay/gates.json." A file that isn\'t valid JSON shows ".relay/gates.json isn\'t a valid JSON object, so the gates can\'t be shown."' }
                ]
            }
        ]
    },
    {
        key: 'promote',
        group: 'daily',
        label: 'Promote to the next stop',
        cards: [
            {
                key: 'pr-main',
                title: 'Promote to the next stop (for example QA → Production)',
                blocks: [
                    { type: 'text', paras: ['Releases deployed to a stage move on to the next stop (the next stage, or production) from the **Promote** tab. You need the Approver or Admin group.', '**The next stop gets each file as it is in the stage** (for example Production gets each file as it is in QA). So older releases that changed the same file go too, and a newer one must be added: a file can\'t go without the changes the stage already has in it.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Pick what goes',
                                who: 'Approver or admin',
                                where: 'Promote tab',
                                goal: 'One block per stage, for example QA → Production · prod: the releases deployed there and not yet in the next stop.',
                                items: [
                                    '**How promoting works** beside each card\'s heading opens a panel with the four rules (Hotfix first, Goes too, Must add, Stays) and **Full guide ›**. Hover over a row label (**Goes with …**, **Changed … after …**, **Stays in …**), **Also goes** or **+ Add** (or tab to it) to see why.',
                                    'Tick the releases to promote: nothing is ticked when the tab opens. Hotfixes are first, then the oldest deploy first ("Changes are promoted in that order"). Unticked ones show **Stays in** the stage, for later. A hotfix can go on its own.',
                                    'An older release that changed the same component as one you ticked goes too: it shows a dashed box and **Goes with** the release, and the panel lists it under **Also goes**. It is marked promoted with the others and leaves the list.',
                                    'A newer release that changed the same component blocks the promotion, in red: "… changed … after …: add it, or wait and promote them together." Press **+ Add** and its number to tick it. The Promote button stays grey until then.',
                                    'The panel on the right (**Bundle into one** next stop **release**, or **Promote the hotfix alone**) counts the releases, components and deletions, lists the test classes that run in the next stop (RunSpecifiedTests, 75% each) and the manual steps it carries, in order.',
                                    '**Title**: suggested for you ("Promote 2 releases to Production", or the hotfix\'s own title; an example); change it if you like. It is required.',
                                    'Press **Promote <n> releases to** the next stop (or **Promote hotfix to** it).'
                                ],
                                check: 'The new release of type Promotion shows on the tab, on the branch `promote/rel-xxxxx`, and runs the scan, check-only deploy and tests. **Promote more** goes back to the list.',
                                problems: [
                                    ['"Only approvers and admins can promote. You can see what\'s waiting."', 'You can see the cards but not promote (for example in the Deployment Team group only): ask for the Approver group.'],
                                    ['A row shows **Rolled back in** the stage', 'Its rollback put the stage back the way it was before it, but the release keeps its status and Git still has the change: promoting it sends the change on. Leave it unticked and fix it with a new release if it shouldn\'t go.'],
                                    ['"No stage on the route yet. An admin sets up the route on the Pipeline tab."', 'An admin registers the stages (Pipeline tab).'],
                                    ['"Nothing deployed to … is waiting to be promoted."', 'Nothing to do for that stage: everything deployed there is already in the next stop.'],
                                    ['"Some of these releases aren\'t waiting in … any more. Reload the list."', 'Someone promoted them meanwhile: press ↻ (Read again) and pick again.'],
                                    ['"The Git connection isn\'t set up and checked yet (Pipeline tab)."', 'An admin presses Check connection on 1 · Where the code lives (Pipeline → Connection & route).']
                                ],
                                shot: { ill: 'promote', cap: 'Promote: tick the releases, check the tests, title, Promote.', alt: 'Drawing of the Promote tab with callouts 1 the releases to tick with the hotfix first, 2 the count and the tests that run, 3 Title, 4 the Promote button.' }
                            },
                            {
                                title: 'Approve and follow it',
                                where: 'The release page',
                                text: [
                                    'The promotion lists what it **Carries**; each carried release shows **Promoted in** with a link. It carries their manual steps and flow choices too. Whether it waits for an approver follows the next stop\'s approval rule (a hotfix may need 2 approvers there).',
                                    'Only releases with manual steps only? No pipeline run: it goes straight to approval in the next stop. Mixed with other releases, only their changes are picked and every manual step goes along in order.',
                                    'If it is rejected or fails, the releases it carried are ready to promote again.'
                                ],
                                links: [{ label: 'How a change moves', to: 'moves' }]
                            },
                            {
                                title: 'If it fails with files that clash',
                                where: 'The promotion\'s page → Progress',
                                goal: 'The next stop has a change to a file that the stage doesn\'t have, for example a hotfix that wasn\'t merged back down.',
                                items: [
                                    'The page says, for example, "prod has a change to … that qa doesn\'t have (a hotfix not merged back down?). Merge prod into qa first, then promote again." (branch names are examples) and lists the **Files that clash**.',
                                    'Merge the next stop\'s branch into the stage\'s branch first (in your Git provider), then promote again.'
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
                                who: 'Admin',
                                where: 'Pipeline → Register org',
                                text: ['Use the role **Back promote (after production)**, with its own branch and Git environment (and that environment\'s login, as for a stage). On the route it shows dashed after production, with how many releases it is behind.']
                            },
                            {
                                title: 'Switch it on',
                                who: 'Admin',
                                where: 'Pipeline → Connection & route → Back promote (beside 1 · Where the code lives) → Edit',
                                text: ['Press **Edit** on the small Back promote card beside the Git connection, turn on **Send <hub>\'s changes to other orgs after a deploy** (with your hub\'s name), and press **Save**. The card then shows **On**; while it is off it shows **Off by default**.']
                            },
                            {
                                title: 'Choose when, and whether to approve',
                                who: 'Admin',
                                where: 'Pipeline → Orgs → click the org → Edit → Back promote',
                                items: [
                                    '**When** the org gets the hub\'s changes: **After every <hub> deploy**, or **When an admin clicks Sync now** (the default).',
                                    '**Approve before syncing**: off by default, so production\'s approval is enough. On: each sync waits for an approver.',
                                    'Press **Save**.'
                                ]
                            },
                            {
                                title: 'Sync now',
                                who: 'Admin',
                                where: 'Pipeline → Orgs → click the org → Back promote → Sync now',
                                items: [
                                    'Brings the org up to date with production at once. The section shows how many releases it is behind (or **Matches** the hub), which ones, and the last sync with its result.',
                                    '**Sync now** is grey while back promote is off: "Back promote is off. Switch it on under Back promote, next to the Git connection, to sync this org."'
                                ],
                                text: ['A sync merges production\'s branch into the org\'s branch, deploys what changed, and only then pushes the branch. A conflict or a failed deploy stops it, and nothing is pushed.',
                                    'Several syncs wait in a queue: each refresh of an open hub release or of the Pipeline tab starts or reads one of them, the one read longest ago, so a big sync never shares a request with another.']
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'evidence',
        group: 'daily',
        label: 'History and evidence',
        cards: [
            {
                key: 'ev-main',
                title: 'History and evidence',
                blocks: [
                    { type: 'text', paras: ['Release Relay records every step of a release as it happens: raised, pull request, scan, check-only deploy, approvals (or approved automatically), manual steps, deploys, flow activation, merged back, promoted and back promoted. Nobody can edit or delete these records.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Evidence for a change request',
                                where: 'The release page → header',
                                goal: 'Everything an auditor or change board asks for, in one file.',
                                items: [
                                    '**Download evidence (PDF)**: the release and its route, components and deletions, the pull request, scan and validation, approvals, manual steps, flows, deploys, rollbacks, merge back and the full history (oldest first). It downloads and is saved to the release\'s **Files** ("Evidence saved to the release\'s Files").',
                                    '**Copy summary**: copies a short plain-text summary to paste into a change request, and shows it on the page in a **Copy summary** card (the button then reads **Hide summary**). If the browser blocks copying: "Select the summary below and copy it."',
                                    '**History**: a vertical path, newest first, read top down as "this happened after that": a coloured dot per event (green done, red failed, amber rolled back or waiting, blue other) with who did what, when, and how (Salesforce, Slack, Git, Rule or Pipeline), with deploy ids and links. The PDF lists the full history oldest first, as an audit document reads.',
                                    '**Files**: each PDF is kept (for example `REL-00042 evidence 2026-10-31 16:05.pdf`, an example only). Press it again later for a newer copy; the older ones stay.'
                                ],
                                problems: [['Download evidence (PDF) fails', 'The message says why. Try again later; Copy summary and History still work meanwhile.']],
                                shot: { ill: 'evidence', cap: 'Release page: Download evidence (PDF), Copy summary, History, Files.', alt: 'Drawing of a release page header with callouts 1 Download evidence PDF, 2 Copy summary, 3 the History timeline, 4 the saved PDF under Files.' }
                            },
                            {
                                title: 'Export CSV',
                                where: 'Releases tab → Export CSV',
                                text: ['Exports the releases that match the filters (Raised by, status, search) to `releases-<date>.csv`: release, title, tickets, route, raised by and on, status, approved by and on, approved via, comment, second approver, deployed to, deploy ids, pull request link, rolled back in and on, and files.']
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
                            'Each developer org has its own branch. A release branch starts where that branch and the stage meet (pipeline files version 28), so Git knows what that org started from and only the components you selected are in it.',
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
                                    'Press **Resolve conflicts**. For each file choose **Keep mine**, **Keep <target>\'s** or **Edit**, then **Resolve and check again**. Your choices are committed to the release branch.',
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
        key: 'slack',
        group: 'daily',
        label: 'Slack in daily use',
        cards: [
            {
                key: 'slack-main',
                title: 'Slack in daily use',
                blocks: [
                    { type: 'note', text: 'Slack is optional. Without it, everything works in Salesforce. Admins set it up in Set up → E. Slack.' },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'One card per release',
                                where: 'The target org\'s Slack channel',
                                goal: 'Everyone sees a release move without opening Salesforce.',
                                items: [
                                    'Each release is one card: a header with its number and title, its steps (pull request, checks, approval, deploy) with their state, the buttons, and a divider under it.',
                                    'While it waits for an approver in an org approved in Slack: **Approve** and **Reject**. Reject opens a form, **Why are you rejecting?**, then **Reject release**. Only linked approvers can use them; anyone else gets a private message.',
                                    '**Open in Release Relay** opens the release page.',
                                    'The card is edited as the release moves; each event you chose (Raised, Checks failed, Ready for approval, Deployed, Deploy failed, Rejected, and every approval) is a reply in its **thread**, so the channel keeps one card per release.'
                                ],
                                text: ['A developer org with **Also post here** gets a one-line copy, so its people see their own releases. Hotfix cards start with **Hotfix:** and show **Why:**; promotion cards say what they promote. The release page has **Open in Slack** to jump to the card.'],
                                problems: [
                                    ['A private message "You\'re not linked to Release Relay yet, so your Approve wasn\'t counted."', 'Press **Link my account** in that message, confirm in Release Relay, then press Approve again. If the message says "Ask an admin to link you." instead, your Slack email doesn\'t match your Salesforce user: an admin links you (Pipeline → Approvals & Slack → Slack connection → Approvers ›).'],
                                    ['A private message "You can\'t approve releases. Ask a Release Relay admin."', 'You need to be an approver: an admin adds you in the Approvers window. The release\'s org must have Approve in Slack on.'],
                                    ['A private message "Approving production needs the Production Approver add-on."', 'Production approval is on: someone with the add-on approves it.'],
                                    ['No Approve button, only Open in Release Relay', 'The org is approved in Salesforce only, or the release isn\'t waiting for an approver.']
                                ],
                                links: [{ label: 'Set up: E. Slack', to: 'setup-slack' }],
                                shot: { ill: 'slack-card', cap: 'A release card: Approve and Reject, Open in Release Relay, the thread.', alt: 'Drawing of a Slack channel with a release card, callouts 1 Approve and Reject, 2 Open in Release Relay, 3 the thread of updates.' }
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'workitems',
        group: 'daily',
        label: 'Work items',
        cards: [
            {
                key: 'wi-main',
                title: 'Work items: tickets on every release',
                blocks: [
                    { type: 'text', paras: [
                        'Every release can carry the tickets it delivers (Jira issues, Azure Boards work items, ServiceNow records, or your own numbers). Add them on **New release** under **Work items**: type a ticket and press Enter or a comma. Each ticket goes to its own tracker by its pattern (for example `CLAIMS-412` to Jira and `CHG0012345` to ServiceNow), and its chip names that tracker. When the admin made tickets required, a release can\'t be raised without one; a ticket no tracker takes is refused with the patterns shown: "No tracker matches …".',
                        'A **promotion** carries the tickets of the releases it carries. A release\'s tickets can be added or removed on its page until it is deployed, rejected or closed (see **Add tickets after raising**). The tickets show as links to their own tracker on the release page, in Approvals, in Releases search (search by ticket), in the CSV and evidence PDF, and in Slack messages.'
                    ] },
                    { type: 'table', cols: ['Moment (with your own org names; these are examples)', 'When'], rows: [
                        ['Raised from Dev / Promoted to QA', 'The release or promotion was raised.'],
                        ['Ready for approval in QA', 'Its checks passed; it waits for an approver.'],
                        ['Waiting to deploy to Production', 'Approved, waiting for its deploy to start (for example for an approved change).'],
                        ['Deployed to QA', 'Deployed.'],
                        ['Checks failed / Deploy failed in QA', 'Blocked until the release is fixed.'],
                        ['Rolled back in QA', 'The deploy was rolled back.'],
                        ['Rejected / Closed', 'The release stopped.']
                    ] },
                    { type: 'list', items: [
                        '**Without an integration** Release Relay keeps each ticket\'s status itself: the **Work items** tab shows one row per ticket with a dot per org of the route, its status (**In** <org>, **Waiting for** <org>, **In** <org> **approval**, **Blocked**, **In progress**) and the releases that carry it.',
                        '**With an integration** each moment is also posted to the ticket, once: a Jira comment (and the mapped transition), an Azure Boards history entry (and state), a ServiceNow work note (and state), or a JSON POST to your own address. Each ticket shows its last sync: **Synced**, **Couldn\'t post** (with what the tracker said) or **Tracked here**. **Try again** on the release page posts it again.',
                        'Posting happens while someone has the release page or the Work items tab open (**Sync now**), never in the background.',
                        'The Work items tab has a search box (ticket, release, title, person, tracker), chips (**All**, **In progress**, **In production**, **Blocked**), a **Tracker** column (the ticket\'s own tracker) and a **Tracker** filter (every tracker by name, or **Untracked**).'
                    ] }
                ]
            },
            {
                key: 'wi-admin',
                title: 'Work trackers (admin)',
                blocks: [
                    { type: 'text', paras: [
                        'A hub can use several trackers at once, for example Jira for stories and ServiceNow for change requests, or two Jira projects. **Pipeline → Work tracking** (admins edit, everyone else reads) lists them in routing order; each has **Edit**, **Test**, **Active** and the up and down arrows.',
                        'A ticket goes to the first active tracker whose ticket pattern matches; a tracker with no pattern takes every ticket the others don\'t (a **No integration** tracker without a pattern keeps those as tracked in Release Relay). With no match the ticket is refused: "No tracker matches AB#123. Expected one of: CLAIMS-\\d+ (Claims stories), CHG\\d{7} (Change requests)". With no active tracker at all, any ticket is taken and tracked in Release Relay. **Try a ticket** under the list shows where a ticket would go.',
                        'Each ticket keeps the tracker it went to: posting, Sync now, its link and the change gate use that tracker. A tracker turned off takes no new tickets and gets no posts; its tickets keep their links.',
                        'Hubs set up before build 47 had one tracker in the Work tracking settings: the first time the Pipeline tab, New Release or the Work items tab is opened, it becomes the first tracker in the list, with the same pattern, link, Named Credential and state map, so nothing changes until you add a second one.'
                    ] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Add a tracker',
                                who: 'Admin',
                                where: 'Pipeline → Work tracking → Add tracker',
                                goal: 'Say where one kind of ticket lives and how it looks.',
                                items: [
                                    'Pick the tile: **Jira**, **Azure Boards**, **ServiceNow**, **No integration** or **Other (link)**.',
                                    '**Name**: what people see on tickets and in the Tracker column, for example Claims stories.',
                                    '**Ticket pattern**: one or more regular expressions, separated by spaces, for example `CLAIMS-\\d+` or `CHG\\d{7}`. Two active trackers can\'t have the same pattern, and only one can have none.',
                                    '**Link**: the ticket\'s address with `{id}` where the number goes, for example `https://yourcompany.atlassian.net/browse/{id}`.',
                                    'The grey text in each field is an example for the tile you picked; nothing is filled in for you.'
                                ]
                            },
                            {
                                title: 'Post updates to the tracker',
                                who: 'Admin',
                                where: 'Setup → Named Credentials, then Pipeline → Work tracking → Edit',
                                goal: 'Let Release Relay post each moment to the ticket without storing a password.',
                                items: [
                                    'In Setup create a **Named Credential** (with its External Credential) per tracker, named `RLY_Work_<Tracker>`: `RLY_Work_Jira` for `https://yourcompany.atlassian.net`, `RLY_Work_AzureBoards` for `https://dev.azure.com/<org>/<project>`, `RLY_Work_ServiceNow` for `https://<instance>.service-now.com`, or your own address for Other. A second tracker of the same kind gets its own, for example `RLY_Work_Billing` for a second Jira site. Give its principal to the people who use Release Relay, on a permission set of your own (not `RLY_Access`: deploying Release Relay replaces that set\'s principal list).',
                                    'In the tracker enter the Named Credential\'s API name and turn on the **Post each moment to the ticket** chip.',
                                    'Optional **State map**: JSON from a moment to the tracker\'s state, for example `{"Deployed to QA":"In QA","Deployed to Production":"Done"}`. For Jira it is the transition\'s name.',
                                    'ServiceNow: the table for work notes is `change_request` unless you enter another (for example `incident`).',
                                    '**Test** signs in through the Named Credential (Jira: who you are; Azure Boards: the work item types; ServiceNow: one row of the table) and says what came back.'
                                ]
                            },
                            {
                                title: 'Switches for every tracker',
                                who: 'Admin',
                                where: 'Pipeline → Work tracking → For every tracker',
                                goal: 'Require tickets, and deploy to production only inside an approved change window.',
                                items: [
                                    '**Tickets required to raise** makes every release carry at least one ticket.',
                                    '**Approved ServiceNow change before production** needs an active ServiceNow tracker with its Named Credential. A deploy into the hub org then starts only when the release carries a ticket that went to that ServiceNow tracker, in the change format (`CHG\\d{7}` unless you set another), and ServiceNow shows it **approved** with now inside its planned start and end. Tickets in other trackers never count.',
                                    'Otherwise the release stays approved and says what it waits for. Opening the release page checks again and starts the deploy once the change allows it.'
                                ]
                            }
                        ]
                    },
                    { type: 'note', text: 'Release Relay never stores a tracker\'s password or token: the calls go through each tracker\'s Named Credential.' }
                ]
            },
            {
                key: 'wi-add',
                title: 'Add tickets after raising',
                blocks: [
                    { type: 'text', paras: [
                        'The release page has a **Work items** card: each ticket with its tracker, what was last posted to it, and **Try again** when a post failed.',
                        'Until the release is deployed, rejected or closed, the release\'s raiser or an admin can press **Add tickets** (others see the list read-only): it opens the same ticket input as New Release: each ticket is matched to its tracker as you type. **Add** saves them; the release\'s **History** records, for example, "Tickets added: BILL-81 (Billing stories), at Ready for approval in QA", and the new tickets start at the release\'s current stage (their first post is that moment, not Raised). **Remove** takes a ticket off, also recorded in History.'
                    ] }
                ]
            }
        ]
    },
    {
        key: 'pipelinetab',
        group: 'daily',
        label: 'Pipeline tab (admin)',
        adminOnly: true,
        cards: [
            {
                key: 'pt-main',
                title: 'Pipeline tab',
                blocks: [
                    { type: 'text', paras: [
                        'The Pipeline tab fits the screen: a header, a **status strip** of five tiles, and the settings in seven sections down the left. The list and the open section scroll on their own.',
                        'The tiles answer "is the pipeline healthy?" at a glance: **Git** (provider, status, the pipeline files\' version and an **update to vN** chip when newer files are available), **Route** (the lane, and "N orgs · all signed in" or the problem), **Approvals & Slack** (Slack, approvers linked), **Security** (the last Repository security check: "N to fix", OK, or Not checked) and **Credentials** (the nightly credential check: "N expiring", "N critical" or OK). They read what the hub has stored, so the tab opens without calling Git or Slack. Press a tile to open its section.',
                        'The sections: **Connection & route** (Where the code lives, Back promote, the route, what to fix in security and credentials, and **Recent changes to settings**), **Orgs** (the connected orgs by Salesforce environment, and the setup steps for a new org), **Approvals & Slack** (the Slack connection, Approve in Slack, approvers, production approval), **Work tracking**, **Security & credentials** (run signing, repository security, credentials), **Retention & archive** and **Advanced** (per-org values, quality gates, the What\'s built lock). Each has a dot: green fine, amber needs a look, red needs fixing, grey not set up. The section you open is remembered in this browser. On a narrow screen the list becomes a menu above the section, and the tiles wrap.',
                        'Read first, edit second: each section shows its settings read-only with **Edit**; Edit opens the same form in place, and nothing changes until you press Save. One thing is edited at a time: the other Edit buttons and Register org are grey meanwhile, and the list marks the section being edited.',
                        '**Recent changes to settings** lists the last 10 changes made on this tab: who, what, when, and the old and new value (a token, key or password shows only as set, changed or removed). Changes are kept 90 days; the nightly archive call removes older ones.',
                        'In the header: **Guide: set-up steps** opens the Set up part of this Guide, **Register org** registers an org, and admins have **Set up Release Relay** for the first-run walk-through (B. Hub org). **Setup steps for a new org** is under Orgs.'
                    ] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Register an org',
                                who: 'Admin',
                                where: 'Pipeline → Register org (page header, or the + Register an org card on an environment tab under Orgs)',
                                goal: 'Add a developer org, a stage, a back promote org, or (once) the hub.',
                                items: [
                                    '**Register an org** opens a window. From a tab\'s **+ Register an org** card, that tab\'s Salesforce environment comes chosen ("Opens with … chosen").',
                                    'Step 1 Sign-in: fill in the fields (they start empty; the grey text shows examples). Login type is read from the My Domain URL; the Salesforce environment follows it (see D. Each org). Press **Check connection and next**. If the sign-in fails, the window says why and stays on Sign-in.',
                                    'Next steps: Approval (stages and the hub), Back promote (back promote orgs), Slack (once Slack is set up), each with **Save and next** or **Save and finish**. **Skip** goes on without changing that step.',
                                    'When it is done, the window closes and Connected orgs shows the new org\'s tab, with its card lit up.'
                                ],
                                problems: SIGN_IN_PROBLEMS
                            },
                            {
                                title: 'See and change an org',
                                who: 'Admin',
                                where: 'Pipeline → Orgs → the org\'s environment tab → its card',
                                goal: 'Keep each org\'s sign-in, approval and Slack settings right.',
                                items: [
                                    'Connected orgs has one tab per Salesforce environment (Developer sandbox or Developer Edition, Developer Pro sandbox, Partial Copy sandbox, Full Copy sandbox, Production), each with how many orgs it has. An org with no environment is under **Not set**. Arrow keys move between the tabs; the tab you pick is remembered.',
                                    '**Production** holds one org: the hub. Once the hub is registered that tab has no + Register an org card: "Production holds one org: the hub. Register other orgs on their sandbox tab." An empty tab says "No orgs in … yet."',
                                    'Each card shows the org\'s name, role (Developer, Stage 1, Hub, Back promote), sign-in status, branch, a line about approval (for example **Always · Code scan: Follows Git (on)**, or **Raises into qa** for a developer org), and when it was last checked.',
                                    'Click a card (or press Enter on it) to open the org\'s window: Sign-in, Approval (with code scan, where it is approved, Git reviewers and the two-approver rule), Back promote for those orgs, Slack with **Reminders and alerts** (once Slack is set up), and **Release window** (see Release windows and freezes). The line under the name says its environment, branch and last check.',
                                    '**Check connection** (window header) checks the hub can still sign in. **Send test message** posts to the org\'s Slack channel (grey without a channel).',
                                    '**Edit** turns every section of the window into a form at once (**Edit** and the org\'s name, "saved values shown"). Consumer key: leave it blank to keep the saved key. The hub\'s Role, Login type and Salesforce environment stay grey.',
                                    'Press **Save** ("Saves all sections together. Changing Sign-in tests it again.") or **Cancel** (drops the changes). Escape or × with changes asks **Discard changes?** first. **Close** goes back to the cards.'
                                ],
                                problems: SIGN_IN_PROBLEMS,
                                shot: { ill: 'org-edit', cap: 'An org\'s window (read-only) and the same window after Edit.', alt: 'Drawing of an org card and its Edit window with callouts 1 Check connection, 2 Edit, 3 consumer key left blank, 4 Slack channel, 5 Post to Slack, 6 Save.' }
                            },
                            {
                                title: 'Where the code lives',
                                who: 'Admin',
                                where: 'Pipeline → Connection & route → 1 · Where the code lives',
                                items: [
                                    'Shows the provider, repository, Named Credential (token), workflow file, pipeline branch, source path and **Code scan** (on or off for every pull request; each org can follow it or set its own).',
                                    '**Check connection** tests it again; **Edit** changes it ("Save tests the connection.").',
                                    'A line under it says whether the pipeline files are up to date (see Update the pipeline files).',
                                    'One Git connection is active at a time. **Move to another provider…** (admins) opens the Migration tab.'
                                ],
                                problems: [['Git connection: check failed', 'Read the list on the card: a token permission, the repository name, or the pipeline files missing on the pipeline branch (Set up → B and C).']]
                            },
                            {
                                title: 'Back promote',
                                who: 'Admin',
                                where: 'Pipeline → Connection & route → Back promote (beside 1 · Where the code lives)',
                                items: ['The small Back promote card beside the Git connection shows whether it is on (**On**, or **Off by default**), when the back promote orgs get the hub\'s changes and how many there are. **Edit** switches it on or off in place. Each back promote org\'s own When and Sync now are in its window under Connected orgs. Folding section 1 folds this card too.'],
                                links: [{ label: 'Back promote', to: 'backpromote' }]
                            },
                            {
                                title: 'Check the route',
                                who: 'Admin',
                                where: 'Pipeline → Connection & route → 2 · Route',
                                items: [
                                    'Developer orgs → stages in order → production, with each stop\'s branch and status. Back promote orgs show dashed after production, with how many releases they are behind.',
                                    'Reorder stages: press **Edit** (shown when there are two or more stages besides the hub), move them with the arrows, then **Save** (or **Cancel**).',
                                    '**Create missing branches** makes any route branch your Git provider doesn\'t have yet ("Every route branch already exists." when there is none).',
                                    'Warnings under the route name what is missing, for example "Register at least one developer org to raise releases from." or "Register this hub with the role Hub, so releases can be promoted to production."'
                                ]
                            },
                            {
                                title: 'Per-org values and Quality gates',
                                who: 'Admin',
                                where: 'Pipeline → Advanced → Per-org values · Quality gates',
                                items: [
                                    '**Per-org values** (`.relay/values.json`): values that differ per org, such as endpoint URLs, email addresses, or usernames in named credentials or custom metadata. In a release they are placeholders (`{{relay:NAME}}`), and each deploy fills in that org\'s value, so one branch serves every org.',
                                    '**Quality gates** (`.relay/gates.json`): extra rules a release must pass before it can be approved, for example a minimum code coverage, no code scan findings at or above a priority, or Apex that must come with its test classes.',
                                    'Both are read from the pipeline branch (the line beside the title says from which branch and when) and only shown here. You change them in Git.',
                                    'The link beside each title, **Edit .relay/values.json ↗** or **Edit .relay/gates.json ↗**, opens the file in your Git provider\'s editor. When the file isn\'t there yet it reads **Create … ↗** and opens a new file with a starter.'
                                ],
                                links: [{ label: 'Per-org values', to: 'values' }, { label: 'Quality gates', to: 'gates' }]
                            },
                            {
                                title: 'Slack connection and production approval',
                                who: 'Admin',
                                where: 'Pipeline → Approvals & Slack',
                                items: [
                                    'Until Slack answers it shows a checklist: Slack app created, Bot token saved, Check connection, Pick a channel per org.',
                                    'Once connected: workspace, bot token (saved, never shown), the events, Approve in Slack (Set up, Not ready with what the Site\'s guest user still needs, or Not set up (optional)) and **Approvers** (for example 57 of 60 linked (SSO) · 3 need attention). **Approvers ›** opens the Slack approvers window: Add approvers, Match now, Needs attention, and a fix per row (admins; others see it read only). **Check connection** checks Slack again; the last message and its result are under it.',
                                    '**Edit**: Slack on or off, bot token, events, **Approve in Slack (optional, advanced)** with the signing secret and the Interactivity URL to paste in Slack, and **Approvers**: **Match approvers by** (SSO Federation ID, Email or Manual only) with the Slack app\'s scopes checked. **Save and test** saves and checks.',
                                    'Under it, **Approvals** holds **Production approval needs the add-on** and says who holds the Production Approver add-on (see F. Settings worth knowing).'
                                ],
                                links: [{ label: 'Set up: E. Slack', to: 'setup-slack' }, { label: 'F. Settings worth knowing', to: 'setup-settings', kind: 'neutral' }]
                            },
                            {
                                title: 'Update the pipeline files',
                                who: 'Admin',
                                where: 'Pipeline → Connection & route → 1 · Where the code lives → Update pipeline files',
                                items: [
                                    'The **Git** tile shows the version in your repository, with an **update to vN** chip when newer files are packaged. The line under the Git connection says **Pipeline files: up to date**, an older version in your repository, or **not found in your repository**, with a pill (Update available, Not found).',
                                    '**Update pipeline files** opens **Update pipeline files to version** n: **Files that will change**, and **How**: **Open a pull request (recommended)** or **Commit directly to** the pipeline branch. Press **Update**; then open the pull request (or the commit) from the link.'
                                ],
                                problems: [['"The token needs Workflows: Read and write to change files in .github/workflows."', 'Edit the Git token: Workflows → Read and write.']]
                            },
                            {
                                title: 'Work tracking',
                                who: 'Admin',
                                where: 'Pipeline → Work tracking',
                                items: ['The trackers in routing order, **Add tracker**, **Try a ticket** and the switches **For every tracker**. Everyone else reads it.'],
                                links: [{ label: 'Work items', to: 'workitems' }]
                            },
                            {
                                title: 'Security & credentials',
                                who: 'Admin',
                                where: 'Pipeline → Security & credentials',
                                items: [
                                    '**Run signing**: the hub\'s run-signing key (**Generate key**, then **Replace key**), and whether runs and results are signed.',
                                    '**Repository security**: **Check** reads the repository\'s protections (read only) and says how to fix what is missing.',
                                    '**Credentials**: every certificate, Git token, Slack app, integration user and org sign-in, with its expiry; checked nightly, or **Check now**.',
                                    'The **Security** and **Credentials** tiles, and the box under Connection & route, show what to fix from the last checks.'
                                ],
                                links: [{ label: 'M. Secure your repository', to: 'secure' }, { label: 'K. Security', to: 'security', kind: 'neutral' }, { label: 'Credentials', to: 'access', kind: 'neutral' }]
                            },
                            {
                                title: 'Retention & archive',
                                who: 'Admin',
                                where: 'Pipeline → Retention & archive → Retention → Edit',
                                items: [
                                    '**Keep finished releases for** a number of days, and **Archive every night** (production hub only). Read mode shows the next nightly run, how many releases are eligible now and when it last changed; **Archive tab ›** opens the Archive tab.',
                                    'Removed: finished releases (Deployed, Rejected, Failed, Rolled back, Closed) older than the days, with their items, history, evidence PDFs, manual steps and back promote syncs. It can\'t be undone.'
                                ],
                                links: [{ label: 'G. Nightly archive', to: 'setup-archive' }]
                            },
                            {
                                title: 'What\'s built lock',
                                who: 'Admin',
                                where: 'Pipeline → Advanced → What\'s built lock → Edit',
                                goal: 'Put a password in front of the What\'s built tab (optional; off until an admin turns it on).',
                                items: [
                                    'Read mode shows **Locked** or **Off**, when it was last changed and by whom; admins also see whether a password is set and who is locked out now. Others see "Only Release Relay admins can change this."',
                                    '**Edit**: turn **Lock What\'s built** on, type the **New password** (at least 8 characters) and **Confirm** it; Save stays off until both match. With a password already set, leave both blank to keep it. Turning the lock off removes the password.',
                                    'Everyone, admins too, then types the password once on What\'s built; it stays open for that user for up to 8 hours or until **Lock again**. Every Save ends everyone\'s current unlock.',
                                    'Forgotten password: an admin sets a new one here. Only a salted hash is kept (custom setting RLY_Lock__c): admins can see the hash in Setup, never the password.'
                                ]
                            },
                            {
                                title: 'Install Release Relay update',
                                who: 'Admin',
                                where: 'Pipeline → Advanced → Install Release Relay update',
                                goal: 'Install a new Release Relay build: checked and installed in a test org first, then in production. Only admins see this card.',
                                items: [
                                    'Commit the build\'s zip into `.relay-inbox/` on a branch of the Git connection (one zip only). Fill in **Update branch**, a **Title** and **Test it in** (a stage on the route; its install branch is rly-(its Git environment)-install).',
                                    'Run the four steps in order with the step chips: the chosen stage\'s **check** and **install**, then production\'s **check** and **install**. Each chip carries its org\'s name (for example **QA check**, then **Production install**); it says Test org only until a stage is chosen. Each step opens once the one before it has passed. A check runs every test class in the zip (or, when the zip is too large to read in Salesforce, this org\'s Release Relay test classes); an install merges the check\'s pull request and quick deploys that check.',
                                    'The hub starts every run itself, signed like every other run, so it keeps working once the pipeline requires the run-signing key. Each check gets its own request id; production\'s check copies the very same zip the test org checked.',
                                    'While a step runs the card checks every 30 seconds (or press **Refresh**). It shows each step\'s status, request id, run link, tests run and failures, read from the signed result files. A failed step can run again: fix the zip on the update branch first for the first step.',
                                    'Each start is listed in **Recent changes to settings** (Advanced · Install update). Works with GitHub and GitLab.'
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
                            ['Submitted', 'A promotion or back promote sync is queued: "Starting the pipeline run." (manual steps only: "Going to approval.").', 'Wait.'],
                            ['Retrieving', 'The hub is reading the components from the source org. A big release (more than 25 components, or static resources and profiles) is read and sent to Git one part at a time while the release page is open.', 'Wait. Usually under a minute; a big release a little longer.'],
                            ['Workflow running', 'The pipeline is converting the files and opening the pull request.', 'Wait.'],
                            ['Validating', 'Code scan and check-only deploy are running.', 'Wait, or Check now.'],
                            ['Resolving conflicts', 'Your conflict choices were committed; the pipeline merges the target and checks again.', 'Wait.'],
                            ['Checks failed', 'The code scan blocked it, the validation failed, a quality gate failed, or it conflicts with the target.', 'Add the fix (Add changes from …), resolve the conflict, ask an approver to bypass the scan, or Check again.'],
                            ['Ready for approval', 'All checks passed (or the scan was bypassed) and the target org\'s approval rule asks for an approver.', 'An approver approves or rejects, in Salesforce or Slack. When the rule needs no approver, the release is approved automatically and deploys.'],
                            ['Waiting for the window', 'Approved, but the target org\'s release window is closed or it is frozen. The release says when it will deploy.', 'Wait; it deploys when the release is opened inside the window. Someone with the Release Window Bypass add-on can Deploy now anyway, with a reason.'],
                            ['Deploying', 'Merging the pull request and deploying.', 'Wait.'],
                            ['Deployed', 'In the target org; developer branches updated; flows set to Activate activated.', 'Nothing. Download evidence (PDF) if the change request needs it.'],
                            ['Deploy failed', 'The merge or the deploy failed.', 'Read the reason; raise a new release.'],
                            ['Rejected', 'An approver rejected it; the pull request was closed.', 'Read the comment; raise again.'],
                            ['Cancelled', 'The person who raised it or an admin withdrew it (Cancel release), or the hub moved to another Git provider; the pull request was closed with the reason.', 'Raise again if still needed.'],
                            ['Closed', 'The pull request was closed in the Git provider.', 'Raise again if still needed.'],
                            ['Failed', 'The release couldn\'t be raised (for example a component wasn\'t found, or "Nothing to commit": the target branch already matches).', 'Read the reason; raise again.']
                        ]
                    },
                    {
                        type: 'table',
                        cols: ['Rollback', 'Meaning', 'What to do'],
                        rows: [
                            ['Rolling back in <org>', 'The pipeline deploys the snapshot taken before the release deployed there.', 'Wait, or Check now.'],
                            ['Rolled back in <org>', 'The org is back to how it was before the release. Git still has the change; the release keeps its status. The Releases tab lists it under Rolled back.', 'Raise a release that fixes the branch.'],
                            ['Rollback failed in <org>', 'Salesforce refused the snapshot; the org is unchanged. The errors are under Deployment errors.', 'Read the errors; Roll back again or fix with a new release.']
                        ]
                    },
                    { type: 'note', text: '**Manual steps only** releases skip Retrieving, Workflow running and Validating: Submitted → Ready for approval → Deploying while the deployment team does the manual steps in that org → Deployed when all of them are Done or Not needed.' },
                    { type: 'note', text: '**Package notes** (build 55) don\'t change a status: "package references kept", "left out in <org>" and **Whole component left out** say what happened to a managed package\'s references; History adds **Package references** per run and **File edited** for each edit. See Package-aware releases.' },
                    { type: 'links', links: [{ label: 'Package-aware releases', to: 'packages' }, { label: 'Edit a file in a release', to: 'editfile' }] }
                ]
            }
        ]
    }
];

// Build 39: release windows and freezes.
const WINDOW_SECTIONS = [
    {
        key: 'windows',
        group: 'daily',
        label: 'Release windows and freezes',
        cards: [
            {
                key: 'win-main',
                title: 'Release windows and freezes',
                blocks: [
                    { type: 'text', paras: ['An org can have a **release window**: the days and hours deploys into it may run, in its own time zone. It can also have **freezes**: whole days (start and end included) when nothing deploys, each with a reason. An org without a window or freezes deploys any time, as before.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Set an org\'s window',
                                who: 'Admin',
                                where: 'Pipeline → Orgs → click the org → Release window',
                                items: [
                                    'Open the org\'s card. Its **Release window** section shows the window in a few words (for example "Mon–Thu 6:00 PM–10:00 PM CST · next freeze 16 Nov 2026") and whether it is open now.',
                                    'Press **Edit**. Pick the days, then From and To (leave both blank for the whole day; a To earlier than From runs past midnight), and the time zone.',
                                    'Under **Freezes**, press **Add a freeze** for each period: start, end and why (for example Year-end close).',
                                    'Press **Save**. Clearing every day and freeze removes the window.'
                                ]
                            }
                        ]
                    },
                    {
                        type: 'table',
                        cols: ['When', 'What happens'],
                        rows: [
                            ['A release is approved outside the window', 'Checks and approval run as usual. It shows **Waiting for the window** with when it will deploy, and History says so. It deploys the first time anyone opens the release, the Releases list or Home inside the window.'],
                            ['A release is approved during a freeze', 'It waits the same way: "Frozen until 2 Jan 2027 in Production: Year-end close." (an example) It deploys when a window opens after the freeze.'],
                            ['It can\'t wait', 'Someone with the **Release Window Bypass** add-on presses **Deploy now anyway** on the release and says why. History, the evidence PDF and the Slack card record it.'],
                            ['A freeze starts within 7 days', 'Home shows a warning.'],
                            ['Rollbacks and branch-only back promotes', 'Never held.']
                        ]
                    },
                    { type: 'note', text: 'The Releases tab\'s **Waiting for the window** filter lists the releases that are waiting. A release deploys inside the window only when a page reads it, so open it (or the Releases list) once the window opens.' }
                ]
            }
        ]
    }
];

// Build 55: package-aware releases.
const PACKAGE_SECTIONS = [
    {
        key: 'packages',
        group: 'daily',
        label: 'Package-aware releases',
        cards: [
            {
                key: 'pk-main',
                title: 'Package-aware releases',
                blocks: [
                    { type: 'text', paras: ['**Package references belong to the orgs that have the package.** An org without a managed package never adds, changes or removes that package\'s references, and never receives them. It works in any direction on the route: a lower or a higher org may lack a package. Every installed managed package counts, found by its namespace (`ns__Field__c`, `ns__Object__c`, `ns.Class`, its tabs, apps, record types and layouts); there is no list to keep. Git always keeps the full files.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'See which org has which package',
                                who: 'Anyone; admins change it',
                                where: 'Pipeline → Orgs → Installed packages',
                                items: [
                                    'Packages down, orgs across (developer orgs, then the route). Each cell shows the version installed, **Not installed**, or **Not read yet**. Different versions are shown in amber, never blocked.',
                                    'An amber note says where a package is missing, for example "<package> isn\'t in Dev: its references are kept on the branch when you raise from it, and left out when deploying to it." (example)',
                                    'Admins press **Check now** to read every org again (one query each). The nightly pass reads them too, and so does Sync status → Packages.'
                                ],
                                check: 'The footer says when the packages were read and how many there are.'
                            },
                            {
                                title: 'Treat a package as not installed',
                                who: 'Admin',
                                where: 'Pipeline → Orgs → Installed packages',
                                goal: 'A package is installed in an org but not licensed or used there, so its references must not be deployed to it.',
                                items: [
                                    'Press the version in that org\'s cell. It turns grey and reads **treated as not installed**: releases now leave that package\'s references out of the org, and keep them when raised from it.',
                                    'Press it again to count it as installed.'
                                ]
                            },
                            {
                                title: 'Raise from a higher org',
                                who: 'Admin switches it on; then anyone who raises releases',
                                where: 'Pipeline → Orgs → Installed packages → Can raise releases; then New release',
                                goal: 'A change needs a package the developer orgs don\'t have (for example a layout with the package\'s fields).',
                                items: [
                                    'An admin presses **Can raise releases** under a stage. Developer orgs always can; the hub can\'t (it is the last stop).',
                                    'New release then offers that stage in its environment. Its release goes to the next stop on the route, as any release goes to the next stage, and the lower orgs get the rest of it through back promote.'
                                ]
                            }
                        ]
                    },
                    {
                        type: 'table',
                        cols: ['Step', 'Org without the package', 'Org with the package'],
                        rows: [
                            ['Raise or Add changes from the org', 'The org\'s file has no lines of the package. Release Relay **keeps** them: the branch\'s package lines are put back in the same place, so the merge can\'t remove them. Review and History say how many were kept.', 'As always: the org\'s file is the source, package lines included (adding or removing them is allowed).'],
                            ['Merge', 'Unchanged: only the selected files, both sides\' edits kept; a real clash on the same lines is a conflict.', 'The same.'],
                            ['Check-only deploy and deploy to the org', 'A temporary copy **leaves out** the package\'s references (as per-org values are filled in). Whole components of the package\'s own objects are not deployed to that org. Git keeps the full files.', 'Deployed as in Git.'],
                            ['The package is installed later', 'The next check notes it; the next deploy to that org includes the references (or an admin pushes the branch from Sync status).', '–']
                        ]
                    },
                    {
                        type: 'table',
                        cols: ['Where', 'What it says', 'What to do'],
                        rows: [
                            ['Review → Package references', 'Each file that references a package, and per org: **Sent**, **Left out**, **Kept · left out** (the source lacks it: kept on the branch, left out of its deploys) or **Not read**. Names of a package\'s own components count at once; references inside files count once Compare has read them.', 'Open Compare to read the files. "Kept 3 references to package ns1 … To remove one, raise from an org that has the package" (example): raise from an org that has it.'],
                            ['Release page → Validation and Deploy lines', '"3 package references kept (ns1)", "left out in Dev: 2 references to package ns2 (not installed) · Git keeps the full files" (examples).', 'Nothing: this is what should happen.'],
                            ['Release page → Whole component left out', 'A component that belongs to a package the target org lacks was not deployed there, for example a layout of the package\'s own object.', 'Nothing, unless the org should have the package: install it, then check again.'],
                            ['History → Package references', 'One entry per run: "Kept 3 (ns1) from qa · Left out in Dev: 2 (ns2), 1 component" (example).', 'Nothing.']
                        ]
                    },
                    { type: 'links', links: [{ label: 'Edit a file', to: 'editfile' }, { label: 'Compare before raising', to: 'compare' }, { label: 'Pipeline tab', to: 'pipelinetab' }] }
                ]
            }
        ]
    },
    {
        key: 'editfile',
        group: 'daily',
        label: 'Edit a file in a release',
        cards: [
            {
                key: 'ef-main',
                title: 'Edit a file in a release',
                blocks: [
                    { type: 'text', paras: ['Any file of an open release can be opened and edited, conflict or not: to take out a line, fix a value, or change what a package line says, without raising again.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Open the file',
                                who: 'Who raised it, or an admin',
                                where: 'The release page → Edit a file…',
                                goal: 'The release is open with its pull request and nothing is running: Checks failed or Ready for approval.',
                                items: [
                                    'Pick a component on the left; a component with several files (a Lightning component) shows them as tabs.',
                                    '**Side by side** shows three copies: the source org\'s (read the way Compare reads it), the target branch\'s, and **Will be deployed** (the release branch\'s). Lines that reference a package are marked, with whether the target org gets them. **Only differences** compares the target branch with what will be deployed.'
                                ],
                                problems: [
                                    ['No Edit a file… button', 'You didn\'t raise it and aren\'t an admin, a run is going, or the release is approved, deployed or closed.'],
                                    ['"Not read here: the release comes from a branch, not an org."', 'A promotion or back promote: its files come from a branch. The other two copies are there.']
                                ]
                            },
                            {
                                title: 'Edit and save',
                                where: 'Will be deployed',
                                items: [
                                    'Press **Edit text**, change the file, then **Save edit**. **Discard** puts the release branch\'s copy back.',
                                    'Saving commits the file to the release branch (GitHub or GitLab), adds **File edited**: "Edited by <you>: <file>" to History, and runs the code scan and check-only deploy again, as Check again does.'
                                ],
                                problems: [
                                    ['"… changed on … since you opened it."', 'The branch moved (the pipeline or someone else committed). Open the file again and redo the edit.'],
                                    ['"Nothing changed in …"', 'The text is the same as on the branch.']
                                ],
                                check: 'The release is Validating, and History shows File edited with a link to the commit.'
                            }
                        ]
                    },
                    { type: 'note', text: 'Objects and fields, profiles, layouts, permission sets, flows, code and Lightning components can be edited here; static resources can\'t (open them in Git). Editing on Review, before raising, isn\'t available yet: raise, then edit on the release page.' }
                ]
            }
        ]
    }
];

const REF_SECTIONS = [
    {
        key: 'repo',
        group: 'setup',
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
                        paras: ['Put each file at its path on the pipeline branch (usually `main`). Your provider\'s file and `release-relay.js` are all you need. When a new version of Release Relay brings new files, update them from the Pipeline tab (Connection & route → Update pipeline files): it opens a pull request with them, or commits them.']
                    },
                    { type: 'files' }
                ]
            }
        ]
    },
    {
        key: 'perms',
        group: 'ref',
        label: 'Permission sets',
        cards: [
            {
                key: 'perm-main',
                title: 'Permission sets',
                blocks: [
                    { type: 'text', paras: ['Assign the **groups** (see Roles and access), not these sets one by one: each group holds its role\'s set and `RLY_Access`. The role sets are labelled **Release Relay Developer Permissions**, **… Approver Permissions** and so on.'] },
                    {
                        type: 'table',
                        cols: ['Permission set', 'Gives'],
                        rows: [
                            ['`RLY_Developer`', 'Home, New Release, Releases, Pipeline Monitor, Metrics, Work items, Sync status, Guide and What\'s built tabs: raise and follow releases, read their history, download evidence and export CSV.'],
                            ['`RLY_Approver`', 'Home, Approvals, Releases, Promote, Pipeline Monitor, Metrics, Work items, Sync status, Archive, Guide and What\'s built tabs: approve (production too, unless production approval needs the add-on), reject, bypass a code scan, resolve conflicts, promote what is deployed to a stage, load data sent up. Linked to a Slack member ID, approve from the Slack card.'],
                            ['`RLY_Deploy_Team`', 'Home, Approvals, Releases, Promote (read-only: what waits in each stage), Pipeline Monitor, Metrics, Work items, Sync status, Guide and What\'s built tabs; tick manual steps done or not needed in each org, **Open org ▾** / **Log in to <org>**, roll a deployed release back, load data and copy it down.'],
                            ['`RLY_Admin`', 'Every tab, with Pipeline and Migration: Git connection, orgs, route, approval rules, Slack, linked approvers, back promote, retention, the moves to another provider. The pipeline\'s hub user needs it to post runs to the Pipeline Monitor. Includes the deployment team (so admins can roll back too), not Hotfix or Deploy now anyway: those are add-ons. Shows the Set up sections of this Guide.'],
                            ['`RLY_Slack_Site`', 'For the Site guest user only, so Approve in Slack can reach the hub. Holds the principals of `RLY_Slack` and of both packaged Git credentials (build 53); Read on User External Credentials goes on the Site\'s guest profile. Set up → E and M. Secure your repository, step 7. Needed only when an org is approved in Slack.'],
                            ['`RLY_Access`', 'Credential access only: the principals of `RLY_Git_GitHub`, `RLY_Git_GitLab` and `RLY_Slack`. In every group. The role sets hold them too, so nobody loses access.'],
                            ['`RLY_Auditor`', 'Build 49: read only. Home, Releases, Pipeline Monitor, Metrics, Work items, Archive and Guide; evidence PDFs. No custom permission.'],
                            ['`RLY_Hotfix_Addon`, `RLY_Prod_Approver_Addon`, `RLY_Window_Bypass_Addon`', 'Build 49 add-ons: raise a hotfix; approve releases into production; Deploy now anyway. See Roles and access.'],
                            ['`RLY_Org_Self_Access` (yours, optional)', 'Not packaged: you create it with the principal of your own `RLY_Org_Self` credential and add it to the groups, so the Credentials check can read the hub\'s own certificates.']
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'access',
        group: 'ref',
        label: 'Roles and access',
        cards: [
            {
                key: 'access-groups',
                title: 'Roles and access: one group per person',
                aside: 'Build 49',
                blocks: [
                    { type: 'text', paras: ['Give each person **one permission set group** for their role. Give an **add-on** to the few who need more. Owners get **Full Access**; people who only look get **Auditor**. Setup → Users → Permission Set Groups → (group) → Manage Assignments.'] },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['Group', 'For', 'Holds'],
                        rows: [
                            ['Release Relay Developer', 'Raise and track releases', '`RLY_Developer` + `RLY_Access`'],
                            ['Release Relay Approver', 'Approve releases into every org except production', '`RLY_Approver` + `RLY_Access`'],
                            ['Release Relay Deployment Team', 'Deploy, roll back, manual steps, data loads and copy down', '`RLY_Deploy_Team` + `RLY_Access`'],
                            ['Release Relay Admin', 'Settings, migration, archive; the pipeline\'s hub user', '`RLY_Admin` + `RLY_Access`'],
                            ['Release Relay Auditor', 'Read only: releases, history, metrics, archive, evidence PDFs. No action buttons', '`RLY_Auditor` + `RLY_Access` (the release pages read their changes from Git)'],
                            ['Release Relay Full Access', 'Owners', 'Every Release Relay permission set and add-on, except `RLY_Slack_Site`']
                        ]
                    },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['Add-on (a permission set)', 'Lets them'],
                        rows: [
                            ['Release Relay Hotfix (`RLY_Hotfix_Addon`)', 'Raise a hotfix from a developer org, with a reason.'],
                            ['Release Relay Production Approver (`RLY_Prod_Approver_Addon`)', 'Approve releases into production (in Salesforce and Slack), once **Pipeline → Approvals & Slack → Approvals → Production approval needs the add-on** is on. Both approvers of a two-approver hotfix need it.'],
                            ['Release Relay Release Window Bypass (`RLY_Window_Bypass_Addon`)', '**Deploy now anyway** on a release waiting for its release window or a freeze, with a reason.']
                        ]
                    },
                    { type: 'list', items: [
                        '**What changed for people assigned before build 49:** the role permission sets still hold the Git and Slack principals, so nobody loses access. Admins no longer raise hotfixes or Deploy now anyway: give them the Hotfix and Release Window Bypass add-ons, or Full Access. The deployment team now loads data and copies data down too.',
                        'The role permission sets are now labelled **Release Relay Admin Permissions**, **… Approver Permissions** and so on: the groups carry the role names. Their API names (`RLY_Admin`, `RLY_Approver`…) don\'t change.',
                        '**Production approval** is off after the upgrade, so existing approvers aren\'t locked out. Admins see "Turn on once you\'ve assigned the Production Approver add-on" on the Pipeline tab (Approvals & Slack) until they turn it on. A new hub starts with it on.',
                        '**`RLY_Org_Self`** (the hub reading itself) isn\'t packaged, so `RLY_Access` can\'t hold it. Create your own permission set **`RLY_Org_Self_Access`** with its principal and add it to the groups by hand (at least Release Relay Admin: the nightly check runs as the pipeline\'s hub user, and **Check now** as the admin who presses it). Don\'t add it to `RLY_Access`: deploying Release Relay replaces that set\'s principal list. The steps: Set up → M. Secure your repository, step 6.'
                    ] }
                ]
            },
            {
                key: 'access-signins',
                title: 'Who signs in to what',
                blocks: [
                    {
                        type: 'table',
                        stack: true,
                        cols: ['Sign-in', 'How', 'Use'],
                        rows: [
                            ['Hub → each org', 'Server to server: a certificate (JWT bearer flow) and **one integration user per org**', 'A dedicated integration user in each org, never a person\'s login.'],
                            ['Hub and pipeline → Git', '**One shared token** on the Git credential (and the pipeline\'s own token)', 'A dedicated GitHub **bot account** or a **GitHub App**, not a person\'s account: it keeps working when people leave. GitLab project access tokens are already bots.'],
                            ['Hub → Slack', 'The Slack app\'s bot token', 'Installed once for the hub.'],
                            ['Hub → itself', '`RLY_Org_Self` (optional, made by hand): a Named Credential whose URL is the hub\'s own My Domain, signed in as a user who can view Setup', 'Lets the Credentials card read the hub\'s own certificates. Without it that row says **Unknown** and asks you to add it.']
                        ]
                    }
                ]
            },
            {
                key: 'access-credentials',
                title: 'Credentials: what expires, and when',
                aside: 'Pipeline → Security & credentials · Home',
                blocks: [
                    { type: 'text', paras: ['The **Credentials** card on the Pipeline tab (Security & credentials) lists every certificate, Git token, Slack app, integration user and org sign-in the hub depends on, with its status, expiry, days left and how to renew it. The Home tab shows what needs attention, or "All credentials OK". It is checked **nightly** with the pipeline\'s archive call, and an admin can press **Check now**.'] },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['Kind', 'Checked by', 'Renew'],
                        rows: [
                            ['Git token', 'GitHub: the token\'s expiry header on one call; GitLab: the token\'s own expiry (`/personal_access_tokens/self`)', 'Regenerate the token and paste it into the `RLY_Git_GitHub` (or `RLY_Git_GitLab`) credential\'s principal.'],
                            ['Certificate', 'A Tooling query of certificates: the hub\'s own through `RLY_Org_Self`, each org\'s through its sign-in', 'Setup → Certificate and Key Management → create, upload it to each org\'s connected app, update `SF_JKS` in GitHub / GitLab and the org\'s certificate on the Pipeline tab.'],
                            ['Org sign-in', 'Signing in to the org; expires with the hub certificate it signs in with', 'Check the org on the Pipeline tab; see the sign-in problems in Set up → D.'],
                            ['Integration user', 'The user is active in its org, with the org\'s last sign-in check', 'Activate the user, or register a new one on the org.'],
                            ['Slack', '`auth.test`; bot tokens don\'t expire', 'Reinstall the app or paste its bot token into `RLY_Slack`.']
                        ]
                    },
                    { type: 'list', items: [
                        '**Renew the Git token** (GitHub): M. Secure your repository, step 2. Only the permissions changed? Press **Edit** on the token instead, change them and press **Update**: the value stays the same and nothing is pasted in Salesforce.',
                        '**GitLab**: Settings → Access tokens → the project token → **Rotate** (or create a new one), then paste it into the principal of `RLY_Git_GitLab` the same way.',
                        '**Hub certificates** read through `RLY_Org_Self`: M. Secure your repository, step 6.'
                    ] },
                    { type: 'links', links: [{ label: 'M. Secure your repository', to: 'secure' }] },
                    { type: 'list', items: [
                        '**Expiring**: 30 days or less. **Critical**: 7 days or less. **Expired**. **Failed**: the check failed. **Unknown**: it can\'t be read (no sign-in, or no `RLY_Org_Self`).',
                        'A pass makes at most about 40 calls; a hub with more orgs carries on the next night, oldest checked first. Nothing runs in the background.',
                        'With Slack on and a Slack channel on the hub org, one message goes out when an item turns Critical, Expired or Failed. It isn\'t repeated while it stays that way.'
                    ] },
                    { type: 'list', items: [
                        '**Unknown, not a failure** (build 52): **Hub certificates** when you can\'t use `RLY_Org_Self` (add the `RLY_Org_Self_Access` permission set, with the `RLY_Org_Self` principal, to your group), and any row of an org that **has used its daily API calls (REQUEST_LIMIT_EXCEEDED)**: it is checked again on the next pass. Unknown rows show no "How to renew".',
                        '**Git token**: when GitHub refuses to close or comment on a rejected release\'s pull request (HTTP 403), the row turns Failed: **give it the permissions in M. Secure your repository, step 1** (Pull requests and Issues: Read and write; GitLab: the `api` scope). It stays until a later reject closes a pull request again; the nightly pass makes no extra call for it.'
                    ] }
                ]
            }
        ]
    },
    {
        key: 'sandboxcopy',
        group: 'ref',
        label: 'Sandbox copies of the hub',
        cards: [
            {
                key: 'sc-main',
                title: 'Sandbox copies of the hub',
                blocks: [
                    { type: 'text', paras: ['A sandbox refreshed from production copies Release Relay with everything in it: the orgs, the route, the Git connection, Slack and the approval rules. Left alone, that copy could raise, approve and deploy releases into the real orgs as if it were production. So Release Relay runs only in production, the org registered as the hub: in any sandbox it detects the sandbox by itself and shows only the Guide\'s Set up.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'What happens in a sandbox',
                                where: 'Every Release Relay tab',
                                items: [
                                    'In a copy of the hub (refreshed from production) each tab shows only the notice **This is a sandbox copy of the Release Relay hub**; in any other sandbox **This org is a sandbox** ("Release Relay runs only in production, which becomes the hub…"). Each has **Open the Guide**. The Guide shows only Set up and this page.',
                                    'Raise, approve, reject, check again, resolve conflicts, promote, sync now, manual step check-offs and the Pipeline tab\'s edits and tests are refused (also from Slack).',
                                    'If the post-copy class wasn\'t picked during the refresh, nothing runs anyway: Release Relay detects the sandbox by itself. Turning it on in the sandbox switches Slack and Git off first.'
                                ]
                            },
                            {
                                title: 'Turn it on in a sandbox on purpose',
                                who: 'Admin',
                                where: 'Pipeline tab in the sandbox',
                                items: [
                                    'To try Release Relay in a sandbox (for example a new route), an admin switches on **Turn Release Relay on in this sandbox** on the Pipeline tab\'s notice, types **Days (1 to 90)** (30 if left blank) and presses **Turn on**. It first switches Slack off and sets the Git connection to Not checked; they stay off until an admin reconnects them. Every tab then says "Release Relay is on in this sandbox until …, turned on by …", and Pipeline has **Turn off**.',
                                    'A refresh resets it: the sandbox gets a new Org Id, so the setting stops counting.',
                                    'Reconnect Git and Slack to the sandbox\'s own repository or branches and channels. Never point a sandbox at production\'s repository or orgs.'
                                ]
                            },
                            {
                                title: 'In production, before Set up is done',
                                where: 'Every Release Relay tab',
                                items: [
                                    'Until the hub is registered and the Git connection saved, each tab shows **Release Relay isn\'t set up yet** ("An admin finishes Set up on the Pipeline tab first: this org as the hub, the Git connection, pipeline files, orgs, Slack (optional).") with **Open setup** and **Open the Guide**.',
                                    'The Pipeline tab opens **Set up Release Relay** for admins, and the Guide opens at Set up.'
                                ],
                                links: [{ label: 'B. Hub org', to: 'setup-hub' }]
                            },
                            {
                                title: 'Optional: switch things off at refresh',
                                who: 'Admin',
                                where: 'Setup → Sandboxes → New Sandbox (or Refresh)',
                                items: [
                                    'In **Apex Class**, pick `RlySandboxCopy`. When the copy is ready it switches Slack off, marks the Git connection Not checked and removes everyone\'s assignments of Release Relay\'s own groups and permission sets (the Developer, Approver, Deployment Team and Auditor groups; `RLY_Developer`, `RLY_Approver`, `RLY_Deploy_Team`, `RLY_Auditor`, `RLY_Slack_Site` and the three add-ons). The Admin and Full Access groups and `RLY_Admin` stay, and your own sets are left alone, so only admins see the copy. If Salesforce refuses to remove them in the same step, the Git connection\'s note says so: remove them in Setup → Permission Set Groups and Permission Sets.'
                                ]
                            }
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
                            ['"No COMPONENT named …" after an update', 'Reload the page without cache (Ctrl+Shift+R), or log out and in. While building, turn browser caching off (Set up → F).'],
                            ['A sign-in error on an org', 'The message names the fix (Remote Site, certificate, consumer key, pre-authorized user, login type, username). See Set up → D. Each org; an admin uses Check connection on the Pipeline tab.'],
                            ['Git connection: check failed', 'The token is missing a permission or expired (Set up → M. Secure your repository, steps 1 and 2), the repository name is wrong, or the pipeline files aren\'t on the pipeline branch (Set up → B and C).'],
                            ['"Named Credential … wasn\'t found or you can\'t use it"', 'Give the user a Release Relay group (its `RLY_Access` holds the principal), or add the credential\'s principal to their own permission set under External Credential Principal Access (Set up → B).'],
                            ['"couldn\'t close the pull request"', 'The Git token needs pull request (merge request) write access.'],
                            ['The pipeline can\'t save a result to release-relay-results', 'Settings → Actions → General: Read and write permissions, and no branch protection on release-relay-results (Set up → C).'],
                            ['A test class doesn\'t show as a test', 'It must contain @IsTest. If it isn\'t in the list, set Changed to Any time and Changed by to Anyone.'],
                            ['Slack: Not set up or Error', 'Paste the bot token again (Pipeline → Approvals & Slack → Slack connection → Edit), or check the External Credential `RLY_Slack` → principal Bot → parameter Token, then **Check connection** on the Slack connection.'],
                            ['Send test message fails with not_in_channel', 'Invite the Slack app to that channel.'],
                            ['Slack: "You\'re not linked to Release Relay yet…" or "You can\'t approve releases…"', 'Press **Link my account** in the reply when it offers one; otherwise an admin links you or adds you as an approver (Pipeline → Approvals & Slack → Slack connection → Approvers ›). The org needs Approve in Slack on.'],
                            ['Slack approvers: "Slack app is missing users:read.email — add it and reinstall."', 'Add `users:read` and `users:read.email` to the Slack app\'s Bot Token Scopes and reinstall it (Set up → E, step 2), then **Match now**.'],
                            ['"Interactivity URL: set up a Salesforce Site first (Guide → Set up → Slack)."', 'No active Site\'s guest user has `RLY_Slack_Site` yet: Set up → E, steps 9 and 10.'],
                            ['Approve in Slack does nothing, or Slack shows an error', 'Check the signing secret, the Request URL (App Manifest, Socket Mode off), and the Site guest user\'s access, with the Git principal on the Site\'s guest profile (not the permission set): Set up → E, steps 8 to 13 and the last step\'s table.'],
                            ['Raise fails: "… already matches … for these components. Nothing to commit."', 'The target branch already has these components as your org has them. Check the selection.'],
                            ['Every tab says "Release Relay isn\'t set up yet"', 'An admin finishes Set up on the Pipeline tab: the hub registered and the Git connection saved (Set up → B).'],
                            ['A flow: activation failed', 'The org\'s integration user needs the **Manage Flow** permission, or the flow version has errors in that org. Activate it in Setup → Flows, or raise again.'],
                            ['Approved automatically, but you expected an approver', 'Check the target org\'s approval rule on the Pipeline tab: Always, or tick the kind of change under Only when the release contains….'],
                            ['Download evidence (PDF) fails', 'The message says why. Try again later; Copy summary and the History card still work meanwhile.'],
                            ['A notice: this is a sandbox copy of the hub, or this org is a sandbox', 'Release Relay runs only in production. Do Set up there; see Sandbox copies of the hub.'],
                            ['Waiting for reviewers in the Git provider', 'The org requires the provider\'s reviewers too, or its environment has required reviewers: approve there, or change the org card / environment.'],
                            ['"Release Relay supports up to 10 orgs per hub."', 'A hub takes 10 orgs, the hub included. Remove one you no longer use before registering another.'],
                            ['"Approving production needs the Production Approver add-on."', 'Production approval is on (Pipeline → Approvals & Slack → Approvals). Assign the add-on to the approver, or ask someone who holds it.'],
                            ['"This run wasn\'t started by the Release Relay hub" in a pipeline run, or "Result rejected: not signed by the pipeline" on a release', 'The run-signing key in the repository and the one saved in the hub differ, or someone started the run by hand: see K. Security.'],
                            ['Compare shows "Not compared: open it in Git." for a static resource or profile', 'By design: their files are too large to compare. Open the file on the target\'s branch from the link.']
                        ]
                    },
                    { type: 'links', links: [{ label: 'Set up: H. Checklist', to: 'setup-checklist' }] }
                ]
            }
        ]
    }
];

// ---------------- Build 46: move to another Git provider (Migration tab) ----------------
const MIGRATION_SECTIONS = [
    {
        key: 'migration',
        group: 'setup',
        label: 'I. Move to another provider',
        adminOnly: true,
        cards: [
            {
                key: 'mig-main',
                title: 'I. Move the hub to another Git provider',
                aside: 'Admins · Migration tab · one provider at a time',
                blocks: [
                    {
                        type: 'text',
                        paras: [
                            'A hub has **one active Git connection**: every new release starts in its repository. The Migration tab moves everything to GitHub, GitLab, Bitbucket or Azure DevOps, checks every org against the new repository, then switches the whole hub at once. Open it from Pipeline → Connection & route → 1 · Where the code lives → **Move to another provider…**.',
                            'The copy runs in the **current** pipeline (the `migrate` job, pipeline files version 26 or later on GitHub or GitLab): the new repository is empty and has no pipeline yet. Releases raised before the switch keep their own repository, so their links, files and history still work.'
                        ]
                    },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['Method', 'What it does', 'Good', 'Costs'],
                        rows: [
                            ['Lift and shift', 'The migrate job copies every branch, tag and commit into an **empty** new repository.', 'All history, checked ref by ref.', 'The new repository must be empty.'],
                            ['The provider\'s importer', 'You import with GitLab, Azure Repos or Bitbucket (the tab shows the clicks); the hub **verifies** every branch and tag.', 'The provider does the copy; fits a repository that already holds the content.', 'Done by hand; anything changed since the import shows as a difference.'],
                            ['Fresh start', 'Each Release Relay branch (the pipeline branch, each org\'s branch, results and snapshots) gets the latest files, one commit each.', 'A clean, small repository.', 'No history in the new one; it stays in the old one.']
                        ]
                    },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Current → New',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Migration → Start',
                                goal: 'See what the current connection holds (branches, orgs and their branches, open releases) and configure the new connection.',
                                items: ['Press **Start**: the current (active) connection is picked for you.', 'Pick the new provider and fill the repository, Named Credential, pipeline file and branch (grey hints show the usual values), then **Save** and **Check**.'],
                                check: 'The check says Reachable, and whether the new repository is empty.'
                            },
                            {
                                title: 'Choose how, then the dry run',
                                who: 'Release Relay admin + Git admin',
                                where: 'Migration → 2 · How, 3 · Dry run',
                                goal: 'Only the methods that work for the pair are offered. The dry run reads both sides and pushes nothing.',
                                items: ['Add the secret `RELAY_MIGRATE_TOKEN` to the **current** pipeline (the tab says where): a token that can push to the new repository.', 'Pick a method (the page stays on How: press **Next**), then **Start the dry run** (for the importer: **Verify the imported copy**).', 'A step\'s number turns green only when that step is done (for example the dry run says Ready), not because you moved past it.'],
                                check: 'The dry run says Ready: what would move, read ✓ push ✓, empty (or every ref matches for the importer), the Release Relay branches found.',
                                problems: [['Not ready: the new repository isn\'t empty', 'Use an empty repository, or pick the importer to verify a copy already made.'], ['push ✗', 'The token can\'t push: give it write access (GitHub: Contents and Workflows; GitLab: write_repository).']]
                            },
                            {
                                title: 'Run, then What moved',
                                who: 'Release Relay admin',
                                where: 'Migration → 4 · Run',
                                goal: 'The copy itself (not for the importer, whose dry run is the verify).',
                                items: ['Press **Start the run**; progress shows while it goes.', 'What moved lists every branch and tag with its commit in both repositories and a ✓ when they match; What didn\'t move lists open pull or merge requests (with links), run history, comments, secrets, protected branches, environments and webhooks.'],
                                check: 'Every ref matches.'
                            },
                            {
                                title: 'Do in the new setup',
                                who: 'Git admin + Salesforce admin',
                                where: 'Migration → 5 · New setup',
                                goal: 'Make the new pipeline able to run releases. Values of secrets can never be read back out of a provider: the tab lists the names per environment.',
                                items: ['Update pipeline files and Check run from the tab; the rest says where to click.', 'Mark each item with its **Done** chip: who and when go in the report.', 'Paste each token into its Named Credential\'s principal (Setup → Named Credentials → External Credentials → <name> → Principals → Edit). Access comes with `RLY_Access`, in every Release Relay group.', 'Add the run-signing key `RELAY_RUN_KEY` in the new provider too (K. Security).'],
                                check: 'Check on the new connection says Connected.'
                            },
                            {
                                title: 'Check every org is in sync',
                                who: 'Release Relay admin',
                                where: 'Migration → 6 · Orgs in sync',
                                goal: 'Each org against its branch in the NEW repository (Org vs branch, run in the new pipeline; developer orgs are read by the hub in parts).',
                                items: ['Press **Check every org**, or Check / Try again per org.', 'Differences you expect (for example a hotfix in flight)? Write why and **Accept the differences**.'],
                                check: 'Every org In sync, or the differences accepted with a reason.'
                            },
                            {
                                title: 'Switch now, then the old setup and the report',
                                who: 'Release Relay admin',
                                where: 'Migration → 7 · Switch now, 8 · Old setup',
                                goal: 'One click switches the whole hub. It needs: the dry run passed, every ref matches, the new connection checked, every org in sync (or accepted), and no open releases on the current connection, or your choice to cancel them (below).',
                                items: ['Finish or close the open releases first (the tab lists them), or turn on **Cancel the N open releases and switch**.', 'Press **Switch to <provider> now**. New releases start in the new repository.', 'Do the old setup: delete `RELAY_MIGRATE_TOKEN`, turn off the old pipeline, archive the repository after a waiting period, revoke the old token.', 'Press **Finish and save the Migration report**: the report (PDF) is saved in the migration\'s Files: every step, who did it and when.'],
                                check: 'The Pipeline tab shows the new connection; the report downloads.'
                            }
                        ]
                    },
                    // Build 54: what happens to the releases still open at the switch.
                    {
                        type: 'table',
                        stack: true,
                        cols: ['Open releases at the switch', 'What happens', 'What you do'],
                        rows: [
                            ['Before: step 1 and Start', 'Open means any status but Deployed, Rejected, Cancelled or Closed. The tab lists each open release with its status, a link to it and its pull request, and says "You still have N open releases. Close them, or Release Relay cancels them when you switch." The copy can go on while they are open.', 'Deploy, reject or close them, or leave them to the switch.'],
                            ['At step 7 · Switch now', 'The condition No open releases shows **!** and names them. Switch now stays off until you turn on the toggle chip **Cancel the N open releases and switch**; the box above it lists the releases (a release with a pipeline run going says so).', 'Turn on the chip, then **Switch to <provider> now** and confirm.'],
                            ['Each release, at the switch', 'Status **Cancelled** with the reason "Cancelled by the move to <provider> (MIG-…)" on the release page; a **Cancelled** entry in History ("Cancelled by the move from <old> to <new> by <you>"); on the old provider its pull or merge request gets the comment "Cancelled in Release Relay: the hub moved to <provider>." and is closed; its Slack card says Cancelled and loses Approve and Reject.', 'Raise the change again in the new repository if it is still needed.'],
                            ['Something couldn\'t be done', 'A pull request that can\'t be commented on or closed never stops the switch: the release says why, and 7 · Switch now lists it under Cancelled by the switch. A pipeline run still going is not stopped (Release Relay can\'t stop a run): check it on the old provider. With very many open releases, the ones beyond what one click can call out for are cancelled with their pull request left open, and say so.', 'Close the listed pull requests on the old provider by hand.'],
                            ['A release opened after you chose', 'The switch stops: "REL-… was opened after you chose".', 'Read the list again and choose again.'],
                            ['Afterwards', 'Who did what and the Migration report list the cancelled releases (the report has a table: status before, pull request closed or not, notes). On the Releases tab they are under **Rejected** (rejected, cancelled or closed).', 'Nothing.']
                        ]
                    },
                    { type: 'links', links: [{ label: 'Open the Migration tab', tab: 'RLY_Migration' }] }
                ]
            }
        ]
    },
    {
        key: 'git-credentials',
        group: 'setup',
        label: 'J. Git credentials (after the update)',
        adminOnly: true,
        cards: [
            {
                key: 'gc-main',
                title: 'J. Paste the Git tokens into the packaged credentials',
                aside: 'Once, after the update that brings RLY_Git_GitHub and RLY_Git_GitLab',
                blocks: [
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Paste each token into its Named Credential\'s principal',
                                who: 'Salesforce admin',
                                where: 'Setup → Named Credentials → External Credentials → <name> → Principals → Edit',
                                goal: 'Release Relay comes with one credential per provider it runs on, RLY_Git_GitHub and RLY_Git_GitLab: you only paste the token. Access comes with `RLY_Access`, in every Release Relay group.',
                                items: [
                                    'External Credential `RLY_Git_GitHub` → principal `RLY_Git_GitHub` → Edit → Authentication Parameter `Token` = the GitHub token → **Save**.',
                                    'External Credential `RLY_Git_GitLab` → principal `RLY_Git_GitLab` → Edit → Authentication Parameter `Token` = the GitLab project access token → **Save**.'
                                ],
                                check: 'Each principal shows the parameter Token.'
                            },
                            {
                                title: 'Point the connection at its new credential',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Connection & route → 1 · Where the code lives → Edit',
                                goal: 'A connection keeps working with the credential name it has until you change it.',
                                items: ['Named Credential: `RLY_Git_GitHub` (or `RLY_Git_GitLab` for a GitLab connection) → **Save** → **Check connection**.', 'The Migration tab\'s new-connection step does the same for the provider you move to.', 'Once no Git connection names them any more, the older credentials from before the update (`RLY_GitHub`, `RLY_GitLab`) can be deleted in Setup.'],
                                check: 'Check says Connected.'
                            }
                        ]
                    }
                ]
            }
        ]
    },
    {
        key: 'security',
        group: 'setup',
        label: 'K. Security',
        adminOnly: true,
        cards: [
            {
                key: 'sec-signing',
                title: 'K. Run signing: only the hub starts runs that deploy',
                aside: 'Build 48. Until the key is set, nothing changes',
                blocks: [
                    { type: 'text', paras: ['Anyone who can write to the repository could otherwise start the pipeline by hand and deploy to an org. With a **run-signing key**, the hub signs every run it starts and the pipeline refuses any run without the hub\'s signature before it signs in to an org. The pipeline signs every result it writes, and the hub only trusts signed results.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Generate the key',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Security & credentials → Run signing → Generate key',
                                items: ['The key is shown **once**, with Copy. It isn\'t saved yet.'],
                                check: 'The card shows "New run-signing key · Not saved yet".'
                            },
                            {
                                title: 'Put the key in the repository',
                                who: 'Repository admin',
                                where: 'GitHub: Settings → Environments · GitLab: Settings → CI/CD → Variables',
                                items: [
                                    'GitHub: in **every environment the pipeline uses** (each org\'s Git environment as on the Pipeline tab, the hub\'s, and `relay-signing`; see L) → **Add environment secret** `RELAY_RUN_KEY` = the key, and limit each environment\'s deployment branches to the pipeline branch. Not a repository secret: a workflow on any branch can read those.',
                                    'GitLab: **Add variable** `RELAY_RUN_KEY` = the key, **Masked** and **Protected**, environments `*`.'
                                ],
                                check: 'Pipeline → Security & credentials → Repository security → Check shows the key in every org environment.'
                            },
                            {
                                title: 'Save the key in the hub',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Security & credentials → Run signing → Save key',
                                items: ['Do it right after the previous step: runs started in between are refused by the pipeline. Start them again after saving.', 'The key is never shown again. **Replace key** makes a new one the same way (repository first, then Save).'],
                                check: 'Run signing shows **On**, when and by whom.'
                            }
                        ]
                    },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['What you may see', 'What it means'],
                        rows: [
                            ['"This run wasn\'t started by the Release Relay hub (missing or wrong signature)" in a pipeline run', 'Someone started the run by hand, or the repository\'s RELAY_RUN_KEY isn\'t the key saved in the hub. Start it from the hub; if it still happens, Replace the key in both places.'],
                            ['"Result rejected: not signed by the pipeline" on a release', 'A result file on release-relay-results wasn\'t signed with the hub\'s key. The release stays where it was. Check that both keys match, then run the checks again.'],
                            ['"The release branch changed after it was approved; run the checks again."', 'Someone pushed to the release branch after its checks passed. The approval is pinned to the commit the checks validated: run the checks again and approve again.'],
                            ['A pipeline warning that RELAY_RUN_KEY isn\'t set', 'The repository has no key yet: runs aren\'t checked. Set it up as above.']
                        ]
                    },
                    { type: 'note', text: 'Protect the key: require a reviewed pull request on the pipeline branch and limit each environment\'s deployment branches to it, so a change to the pipeline file can\'t read the secret from another branch. The Repository security card checks this.' },
                    { type: 'note', text: 'Releases whose checks passed before the key was set: Approve says "Run the checks again". Press Run checks again once; the new check pins the commit it validated, and its validation can then be quick-deployed.' },
                    { type: 'links', links: [{ label: 'M. Secure your repository: run signing and the rest, in order', to: 'secure' }] }
                ]
            },
            {
                key: 'sec-repo',
                title: 'K. Repository security check',
                aside: 'Pipeline → Security & credentials → Repository security → Check (admins)',
                blocks: [
                    { type: 'text', paras: ['**Check** reads the repository through the active Git connection and lists each protection with ✓ (in place), ! (missing, with How to fix) or ? (couldn\'t be read: the token lacks a permission). It changes nothing; secrets and variables are read by name only.'] },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['Row', 'GitHub', 'GitLab'],
                        rows: [
                            ['Pipeline branch protected and reviewed', 'Branch protection or a ruleset requiring a pull request with 1+ approvals (token: Administration: read)', 'Protected branch with Allowed to push = No one; merge request approvals 1+ (approval rules need GitLab Premium)'],
                            ['Run-signing key', 'Environment secret RELAY_RUN_KEY in every org environment; a repository-level copy is flagged "Move it to the environments" (token: Environments: read, Secrets: read)', 'CI/CD variable RELAY_RUN_KEY, masked, protected, environments *'],
                            ['Each org\'s environment', 'Deployment branches: the pipeline branch only, or protected branches only (token: Environments: read)', 'A protected environment (GitLab Premium)']
                        ]
                    },
                    { type: 'text', paras: ['The token permissions these rows need, and how to fix each row on GitHub, are in **M. Secure your repository** (steps 1, 3 and 4).'] },
                    { type: 'links', links: [{ label: 'M. Secure your repository', to: 'secure' }] }
                ]
            },
            {
                key: 'sec-more',
                title: 'K. Other protections in build 48',
                blocks: [
                    {
                        type: 'list',
                        items: [
                            '**Tickets**: only the release\'s raiser or a Release Relay admin can add or remove its tickets.',
                            '**Run checks again**: the raiser, an approver, the deployment team or an admin.',
                            '**ServiceNow change gate**: the change request must name the release (for example REL-00042, an example) in its short description or description. It is the tracker\'s **Change must mention the release** chip, on for new trackers; **trackers that existed before this update have it on too**: turn it off on the tracker if your changes don\'t name releases.',
                            '**Links** from pipeline results (Open the run) are shown only when they start with https://.',
                            '**Slack**: requests are checked in constant time and their payload is read only from the signed body. Testing or saving the Slack connection records the workspace (team) ID, after which presses from any other workspace are refused. **Link my account** is offered only to someone whose Slack email matches a user\'s Federation ID or email; anyone else is told to ask an admin to link them.',
                            '**Manual steps**: the Release Relay Developer permission set reads steps and their runs; every save goes through Release Relay\'s own pages.',
                            '**GitLab**: pipeline variables are sent raw, so a `$NAME` in a release title is never expanded.'
                        ]
                    },
                    { type: 'links', links: [{ label: 'Open the Pipeline tab', tab: 'RLY_Pipeline' }] }
                ]
            }
        ]
    },
    {
        key: 'pipeline-security',
        group: 'setup',
        label: 'L. Pipeline security (pipeline files version 27)',
        adminOnly: true,
        cards: [
            {
                key: 'ps-main',
                title: 'L. Lock down the pipeline: run-signing key, protected main, pinned tools',
                aside: 'Once, when you copy pipeline files version 27 into the repository',
                blocks: [
                    { type: 'text', paras: ['From version 27 the pipeline only runs what the hub signed, signs every result it writes, merges only the approved head and deploys only what the check passed. It needs the run-signing key from the Pipeline tab (Security & credentials → Run signing) in your Git provider, and a protected pipeline branch.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Add the run-signing key to your Git provider',
                                who: 'Repository admin',
                                where: 'GitHub: Settings → Environments; GitLab: Settings → CI/CD → Variables',
                                goal: 'Only pipeline runs on the protected main branch can read the key, so nobody can sign a run of their own.',
                                items: ['Pick your provider:'],
                                providers: {
                                    GitHub: [
                                        'Environment secret `RELAY_RUN_KEY` = the key the Pipeline tab showed, in every environment the pipeline uses: each org\'s (for example `dev`, `qa`, `prod`), the hub\'s, and a new environment `relay-signing` (for the jobs that have no org: scan-save, sync-branch, compare, routediff, migrate).',
                                        'Each of those environments → Deployment branches and tags → **Selected branches** → `main` only.',
                                        'Don\'t keep a repository secret `RELAY_RUN_KEY`: anyone who can push a branch can read repository secrets from their own workflow.',
                                        'When every environment has it: repository variable `RELAY_SIGNING` = `required` (a job that can\'t see the key then fails instead of warning).'
                                    ],
                                    GitLab: [
                                        'Variable `RELAY_RUN_KEY` = the key, **Masked**, **Protected**, environment scope `*` (All).',
                                        'When it\'s in place: variable `RELAY_SIGNING` = `required`.',
                                        'Keep **Use separate caches for protected branches** on (Settings → CI/CD → General pipelines; the default).'
                                    ],
                                    Bitbucket: ['Repository variable `RELAY_RUN_KEY` (Secured). Running releases from the hub on Bitbucket comes in a later version.'],
                                    AzureDevOps: ['Pipeline secret variable `RELAY_RUN_KEY`. Running releases from the hub on Azure DevOps comes in a later version.']
                                },
                                check: 'The next run\'s log says "The run\'s signature is the hub\'s." and has no RELAY_RUN_KEY warning.'
                            },
                            {
                                title: 'Protect the pipeline branch',
                                who: 'Repository admin',
                                where: 'GitHub → Settings → Branches (or Rules → Rulesets); GitLab → Settings → Repository → Protected branches',
                                goal: 'The pipeline file and its key settings can only change through a reviewed pull or merge request.',
                                items: [
                                    'GitHub: `main` requires a pull request with at least one approval, no force pushes, no deletions, and admins included.',
                                    'GitLab: `main` allowed to merge: Maintainers; allowed to push and merge: No one; merge requests need an approval.',
                                    '`release-relay-results`: let only the pipeline push if your plan allows it. The signatures are the real control: the hub ignores results it can\'t verify.'
                                ],
                                check: 'The Pipeline tab\'s Repository security check lists nothing missing.'
                            }
                        ]
                    },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['What changed in version 27', 'Why'],
                        rows: [
                            ['Every job that signs in or pushes checks the hub\'s signature first (15 minutes from the run\'s start)', 'A repository writer can\'t start a deployment the hub didn\'t ask for'],
                            ['Result files are `{"payload": ..., "sig": ...}`', 'A pushed fake Passed or Deployed result is rejected'],
                            ['Merge needs the approved head; deploy fails when the branch changed after the check', 'Commits added after approval are never deployed'],
                            ['Quick deploy asks the org about the validation first', 'A forged validate.json can\'t quick deploy someone else\'s validation'],
                            ['The Salesforce CLI never sees a secret; the branch\'s sfdx-project.json `replacements` and Code Analyzer or ESLint settings are ignored', 'Branch content can\'t leak keys into metadata or run code in the scan'],
                            ['Actions pinned by commit, `@salesforce/cli@2.135.7`, `@salesforce/plugin-code-analyzer@5.13.0` (GitLab: the image `node:22.22.3`)', 'A changed tag upstream can\'t change the pipeline'],
                            ['Archive and Slack runs started by hand need a signature too', 'The schedules still run unsigned']
                        ]
                    },
                    { type: 'note', text: 'Until `RELAY_RUN_KEY` is set, runs go on with a warning so nothing breaks while you set it up. Releases checked by an older pipeline need their checks run again before they deploy.' },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['What changed in version 28', 'Why'],
                        rows: [
                            ['A new release branch starts where the developer org\'s branch and the target meet; files on that branch you didn\'t select are left out (the run log and raise.json list them). The pipeline replaces the branch the hub made, so it must be allowed to force-push release branches', 'The pull request holds only what you selected, and the merge still keeps what the target added to the same files (a layout field, a permission, a picklist value)'],
                            ['A raise or an add that fails takes its `.relay-inbox/` files off the release branch; the next add also removes any an older pipeline left', 'Upload files never reach the target'],
                            ['Validate fails and merge refuses while the release branch adds `.relay-inbox/` files', 'Merging would copy them into the target']
                        ]
                    },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['What changed in version 29', 'Why'],
                        rows: [
                            ['A raise or an add from an org without a managed package puts the branch\'s references to that package (a layout item, a field permission, a list view column) back into the files, each in its place; the package\'s own components keep the branch\'s version and their deletions are dropped', 'An org without the package never adds, changes or removes its references, and the pull request shows only that org\'s own changes'],
                            ['Checking, deploying or back promoting to an org without a package strips its references in the temporary deploy copy and leaves the package\'s own components out (and any component that needs the package as a whole, such as a lookup to its object); the package\'s tests don\'t run there. The results list what was kept and left out', 'The org gets everything else; Git always keeps the full files'],
                            ['A quick deploy needs the check to have left out the same package references', 'An org whose packages changed since the check is deployed in full']
                        ]
                    },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['What changed in version 30', 'Why'],
                        rows: [
                            ['Org vs branch for an org the hub reads in parts skips a part the org sent back empty (only package.xml, for example list views it can\'t retrieve)', 'Such a part has nothing to compare; before, it stopped the whole check with "No results to format"']
                        ]
                    },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['What changed in version 31', 'Why'],
                        rows: [
                            ['No behaviour change: the script passes a strict lint (no unused variables, no waits inside loops)', 'Cleaner code for reviewers and code scanners']
                        ]
                    },
                    { type: 'links', links: [{ label: 'M. Secure your repository: every step in order', to: 'secure' }] }
                ]
            }
        ]
    },
    // ---------- M. Secure your repository (build 53): the one ordered list; K, L, B, E and Credentials link here ----------
    {
        key: 'secure',
        group: 'setup',
        label: 'M. Secure your repository',
        adminOnly: true,
        cards: [
            {
                key: 'secure-main',
                title: 'Secure your repository',
                aside: 'Once per hub, in order · a Release Relay admin who is also an admin of the Git repository',
                blocks: [
                    { type: 'text', paras: [
                        'Follow these steps once per hub, in order. When you\'re done, the Pipeline tab\'s **Security & credentials** section shows every row green, and nobody can deploy to an org except through an approved release in Release Relay.',
                        'Who does it: a Release Relay admin who is also an admin of the Git repository.'
                    ] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Git token permissions',
                                who: 'Git admin',
                                where: 'GitHub → your profile picture → Settings → Developer settings → Personal access tokens → Fine-grained tokens → the hub\'s token → Edit',
                                goal: 'The hub raises, approves, rejects and checks the repository with this one token. Use a bot account or a GitHub App for it, not a person\'s account, so it keeps working when people leave.',
                                items: [
                                    'Give the token each permission in the table under this step.',
                                    'Press **Update**. Nothing needs pasting in Salesforce when you only change permissions.'
                                ],
                                check: 'Pipeline → Security & credentials → Repository security → **Check again**. No row says "Couldn\'t read".'
                            }
                        ]
                    },
                    {
                        type: 'table',
                        stack: true,
                        cols: ['Permission', 'Access', 'Why'],
                        rows: [
                            ['Actions', 'Read and write', 'Start and read pipeline runs'],
                            ['Contents', 'Read and write', 'Commit release files and read results'],
                            ['Pull requests', 'Read and write', 'Open, comment on and close pull requests'],
                            ['Issues', 'Read and write', 'Post the reject reason as a comment'],
                            ['Workflows', 'Read and write', 'Update pipeline files'],
                            ['Administration', 'Read-only', 'Repository security check reads branch protection'],
                            ['Environments', 'Read-only', 'Repository security check reads environment rules'],
                            ['Secrets', 'Read-only', 'Repository security check sees RELAY_RUN_KEY by name'],
                            ['Metadata', 'Read-only', 'Comes with the others']
                        ]
                    },
                    {
                        type: 'steps',
                        start: 2,
                        steps: [
                            {
                                title: 'Renew the token before it expires',
                                who: 'Git admin + Salesforce admin',
                                where: 'GitHub: the hub\'s token · Salesforce: Setup → Named Credentials → External Credentials → RLY_Git_GitHub',
                                goal: 'A fine-grained token\'s expiry can\'t be edited. You regenerate it.',
                                items: [
                                    'Open the token in GitHub and press **Regenerate token**. Pick the new expiration (for example 90 days).',
                                    'Copy the new value. GitHub shows it only once, and the old value stops working at once.',
                                    'In Salesforce: Setup → Named Credentials → External Credentials → **RLY_Git_GitHub** → Principals → the RLY_Git_GitHub row → **Edit**.',
                                    'Paste the value into **Value** (Name: `Token`) and press **Save**. Paste it only there, never into a chat, a ticket or an email.'
                                ],
                                text: ['The Credentials card warns 30 days before expiry, and Slack gets an alert when it turns Critical.'],
                                check: 'Pipeline → Security & credentials → Credentials → **Check now**. The Git token row shows the new expiry.'
                            },
                            {
                                title: 'Environments deploy only from main',
                                who: 'Git admin',
                                where: 'GitHub → the repository → Settings → Environments → each org\'s environment',
                                goal: 'Each org\'s environment (for example `qa`, `staging`, `prod`) holds that org\'s sign-in secrets. Only the pipeline branch may use them.',
                                items: [
                                    'Under **Deployment branches and tags**, choose **Selected branches and tags**.',
                                    '**Add deployment branch or tag rule** → Name pattern: `main` → **Add rule**.',
                                    'Repeat for every org\'s environment.'
                                ],
                                check: 'Repository security shows each environment as "Deploys only from main".'
                            },
                            {
                                title: 'Protect the pipeline and org branches',
                                who: 'Git admin',
                                where: 'GitHub → the repository → Settings → Branches (or Rules → Rulesets)',
                                goal: 'Only reviewed changes reach the pipeline, and only Release Relay merges into an org\'s branch.',
                                items: [
                                    '**main** (the pipeline branch): require a pull request before merging, with at least 1 approval.',
                                    '**Each org\'s branch** (for example `qa`, `staging`, `prod`): allow only Release Relay to merge. Turn on "Require a pull request before merging" so nobody pushes or merges by hand. A pull request merged outside Release Relay changes the branch without deploying the org.'
                                ],
                                text: ['A solo owner can\'t approve their own pull request. Either add a second reviewer, or allow administrators to bypass. With a bypass, the Repository security row stays flagged as a reminder.'],
                                check: 'Repository security shows "main is protected and needs a reviewed pull request".'
                            },
                            {
                                title: 'Run signing',
                                who: 'Release Relay admin + Git admin',
                                where: 'Release Relay → Pipeline → Security & credentials → Run signing · GitHub → Settings → Environments',
                                goal: 'The hub signs every run it starts, and the pipeline signs every result it writes. A run started by hand from GitHub, or a hand-edited result file, is refused. The only way into an org is an approved release.',
                                items: [
                                    'Release Relay → Pipeline → Security & credentials → Run signing → **Generate key**. Copy it; it\'s shown once.',
                                    'GitHub → Settings → Environments → each org\'s environment → **Add environment secret** → Name `RELAY_RUN_KEY`, Value: the key.',
                                    'Back in Release Relay, **Save** the key on the Run signing card.',
                                    'Run one release through to check it works. The run\'s log shows the signature was checked.',
                                    'Then set the repository variable `RELAY_SIGNING` to `required` (GitHub → Settings → Secrets and variables → Actions → Variables). From now on unsigned runs and results are refused, not just warned about.'
                                ],
                                text: [
                                    'When you need it: always when other people can push to the repository (a shared team repo, or one a vendor can push to). For a repository only you can reach, it\'s optional, but it still protects you if a token or account ever leaks.',
                                    'After this, start Release Relay\'s own updates from Pipeline → Advanced → **Install Release Relay update**, not from GitHub.'
                                ],
                                check: 'Repository security shows RELAY_RUN_KEY in every org environment, and Run signing shows "Required".',
                                links: [{ label: 'K. Security: what run signing refuses', to: 'security', kind: 'neutral' }]
                            },
                            {
                                title: 'Hub access to itself',
                                who: 'Salesforce admin',
                                where: 'Hub: Setup → Permission Sets',
                                goal: 'The Credentials card reads the hub\'s own certificates through the RLY_Org_Self credential.',
                                items: [
                                    'Setup → Permission Sets → **New** → Label `RLY_Org_Self_Access`.',
                                    'External Credential Principal Access → Edit → enable the **RLY_Org_Self** principal → Save.',
                                    'Add the permission set to the Release Relay Full Access and Admin groups.'
                                ],
                                text: ['Don\'t add it to RLY_Access: deploying Release Relay replaces that set\'s principal list.'],
                                check: 'Credentials → **Check now**. Hub certificates shows OK with an expiry date.'
                            },
                            {
                                title: 'Approve in Slack',
                                who: 'Salesforce admin',
                                where: 'Hub: Setup → Permission Sets → Release Relay Slack Site → External Credential Principal Access',
                                goal: 'Slack\'s Approve and Reject buttons run as the Salesforce Site\'s guest user.',
                                items: [
                                    'Setup → Permission Sets → **Release Relay Slack Site** → External Credential Principal Access → Edit.',
                                    'Enable **RLY_Slack - Bot** and the Git credential\'s principal (**RLY_Git_GitHub**, and **RLY_Git_GitLab** if you use GitLab) → Save.'
                                ],
                                text: ['Whenever you rename or add a Git credential, add its principal here too. (Build 53 ships both Git principals in this permission set.)'],
                                check: 'Press Approve on a release in Slack. The card turns to "Deploying".',
                                links: [{ label: 'E. Slack: the rest of Approve in Slack', to: 'setup-slack', kind: 'neutral' }]
                            }
                        ]
                    },
                    { type: 'note', text: 'Written for GitHub. On GitLab the same protections are a protected `main`, protected environments and the masked, protected variable `RELAY_RUN_KEY`: see K. Security (Repository security check) and L. Pipeline security.' }
                ]
            },
            {
                key: 'secure-final',
                title: 'Final check',
                aside: 'Pipeline → Security & credentials',
                blocks: [
                    { type: 'list', items: [
                        '**Repository security**: all rows green.',
                        '**Credentials**: no Failed or Unknown rows.',
                        '**Run signing**: Required.'
                    ] },
                    { type: 'links', links: [{ label: 'Open the Pipeline tab', tab: 'RLY_Pipeline' }, { label: 'H. Checklist', to: 'setup-checklist', kind: 'neutral' }] }
                ]
            }
        ]
    },
    {
        key: 'naming',
        group: 'ref',
        label: 'Naming',
        cards: [
            {
                key: 'naming-main',
                title: 'How Release Relay names things',
                blocks: [
                    {
                        type: 'table',
                        stack: true,
                        cols: ['What', 'Name'],
                        rows: [
                            ['Objects, tabs, permission sets, custom permissions, credentials, static resources, documents, the cache partition', 'Metadata API name starts with `RLY_`'],
                            ['Apex classes and triggers', 'Start with `Rly`'],
                            ['Lightning web components', 'Start with `rly`'],
                            ['Fields on Release Relay\'s own objects', 'No prefix'],
                            ['Fields on standard objects', 'Start with `RLY_`'],
                            ['Credentials', '`RLY_Git_<Provider>`: `RLY_Git_GitHub` and `RLY_Git_GitLab` come with Release Relay; `RLY_Git_Bitbucket` and `RLY_Git_AzureDevOps` you create. `RLY_Slack` comes with it; `RLY_Org_Self` (optional) you create.'],
                            ['Git branches it owns', '`release-relay-*` (results, snapshots, hub)'],
                            ['Request ids', '`REL-` releases, `SYN-` sync checks, `CMP-` compares, `DAT-` data runs, `MIG-` migrations']
                        ]
                    },
                    { type: 'note', text: 'Known exception, to be renamed later: the app `Release_Relay`. The Slack member field on User is `RLY_Slack_Member_Id__c`.' }
                ]
            }
        ]
    }
];

const SECTIONS = [...START_SECTIONS, ...SETUP_SECTIONS, ...MIGRATION_SECTIONS, ...USE_SECTIONS, ...WINDOW_SECTIONS, ...PACKAGE_SECTIONS, ...REF_SECTIONS];

export default SECTIONS;
