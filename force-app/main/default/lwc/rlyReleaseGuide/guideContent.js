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
 *   steps     { steps: [{ title, who, where, goal, items | text, check, problems, links, providers, shot }] }
 *             goal: why the step is needed (one line); check: what you should see when it worked;
 *             problems: [['You see', 'Do this']]; links: [{ label, to: section key }] (buttons that open that section).
 *             In a step with an illustration, the numbered items match the numbered callouts in the picture.
 *   checklist { stages: [{ to, label, who, time }] }  the setup stages with a tick each and a progress bar (per browser)
 *   links     { links: [{ label, to }] }               to: a section key; or tab: a tab's API name (opens that tab, state optional); kind 'neutral' for a plain button
 *   seq       { stops: [{ title, text }], shots: [] } a row of stops with arrows, screenshots under it
 *   repo      { providers }                           tree + files table, one tab per Git provider
 *   shots     { shots: [] }
 *   files     {}                                      the pipeline files to download (PIPELINE_FILES), versions from the hub
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

const SHOT_NOTE = 'Screenshots are examples from a demo hub on GitHub.';

const TOKENS = {
    GitHub: [
        'A fine-grained personal access token on the repository: **Contents**, **Pull requests**, **Actions** and **Workflows**, all Read and write (**Metadata** Read-only comes with it). See Set up → B. Hub org.',
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
        'Settings → Environments → one environment per stage org, named as the org\'s **Git environment** (Pipeline → Connected orgs → the org).',
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

const SETUP_NOTE = 'Pictures are simple drawings of each settings screen. The numbers in a picture match the numbered actions next to it. Menu names can differ slightly between releases.';
const EXAMPLE_NOTE = 'Org and branch names such as SIT, PROD, `sit`, `prod` and `dev1` are examples only: use your own.';

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
                            { to: 'setup-checklist', label: 'H. Check everything', who: 'Salesforce admin', time: '10 min' }
                        ]
                    },
                    {
                        type: 'table',
                        cols: ['Who you need', 'For'],
                        rows: [
                            ['A **Salesforce admin of the hub** (System Administrator)', 'Certificate, Remote Site Settings, Named Credentials, permission sets, the Pipeline tab.'],
                            ['A **Salesforce admin of each other org** (developer orgs, test stages)', 'The sign-in app (External Client App) and an integration user in that org.'],
                            ['A **Git repository admin**', 'The repository, its branches, Actions settings, environments with secrets, and a token for the hub.'],
                            ['A **Slack workspace admin** (only if you use Slack)', 'Creating and installing the Slack app, and the channels.']
                        ]
                    },
                    {
                        type: 'list',
                        items: [
                            '**Have ready:** the My Domain URL of each org (Setup → My Domain, for example `https://your-domain.my.salesforce.com`, or `https://your-domain--sit.sandbox.my.salesforce.com` for a sandbox), and a list of the orgs on your route: developer orgs → test stages → production.',
                            '**Never paste real secrets into tickets or chat.** Tokens, keystore passwords and consumer keys go only where these steps say. In this guide they are shown as placeholders such as `xoxb-…` or `github_pat_…`.',
                            'Release Relay\'s pipeline for **GitHub** is complete. GitLab, Bitbucket and Azure DevOps have pipeline files too (see Repository files); their differences are listed on the provider tabs in C. Git provider.'
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
                                title: 'Give people their permission sets',
                                who: 'Salesforce admin',
                                where: 'Setup → Users → Permission Sets → (permission set) → Manage Assignments → Add Assignment',
                                goal: 'The tabs and buttons show only to people with the right permission set.',
                                items: [
                                    'Admins of Release Relay: `RLY_Admin` (it includes Hotfix and the deployment team).',
                                    'Approvers: `RLY_Approver`.',
                                    'Developers who raise releases: `RLY_Developer`.',
                                    'People who do the manual steps in each org: `RLY_Deploy_Team`.',
                                    'Give yourself `RLY_Admin` first, then reload the page.'
                                ],
                                check: 'The Release Relay app shows the Pipeline tab, and this Guide shows the Set up group.',
                                links: [{ label: 'What each permission set gives', to: 'perms' }]
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
                                    'Write it with `https://` in front, for example `https://your-domain.my.salesforce.com` or `https://your-domain--sit.sandbox.my.salesforce.com` (examples).'
                                ]
                            },
                            {
                                title: 'Add a Remote Site Setting per org',
                                who: 'Salesforce admin',
                                where: 'Setup → Security → Remote Site Settings → New Remote Site',
                                goal: 'Salesforce blocks calls to other addresses unless they are listed here.',
                                items: [
                                    'Remote Site Name: a name you recognize, for example `RLY_Org_SIT` (example).',
                                    'Remote Site URL: the org\'s My Domain URL.',
                                    'Leave **Active** ticked.',
                                    'Press **Save**. Repeat for every org you will register, **the hub\'s own My Domain included**.'
                                ],
                                text: ['Git and Slack need no Remote Site: the hub reaches them through Named Credentials (`RLY_GitHub`, `RLY_Slack`).'],
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
                                    'Token name: for example `release-relay-hub`.',
                                    'Expiration: as your company allows (put a reminder to renew it).',
                                    'Resource owner: the account or organization that owns the repository.',
                                    'Repository access: **Only select repositories** → your repository.',
                                    'Repository permissions: **Actions**, **Contents**, **Pull requests** and **Workflows**: Read and write. **Metadata**: Read-only (it comes with the others).',
                                    'Press **Generate token** and copy it (`github_pat_…`). It is shown once.'
                                ],
                                text: ['Why each permission: Contents (branches, commits, the release files), Pull requests (open, comment, close), Actions (start the workflow and read its runs), Workflows (update the pipeline file in `.github/workflows` from the Pipeline tab). If an organization owns the repository, an owner may have to approve the token.'],
                                check: 'The token shows under Fine-grained tokens with access to one repository.',
                                problems: [
                                    ['"… failed with HTTP 401. The token in Named Credential RLY_GitHub was refused"', 'The token expired, was revoked or was pasted wrongly. Make a new one and update the External Credential (step 9).'],
                                    ['"… failed with HTTP 403. The token lacks permission for this"', 'Add the missing permission to the token (list above). Organization-owned repositories may also need the token approved.'],
                                    ['"… failed with HTTP 404. Not found: check the repository name and that the token can see it"', 'Repository on the Git connection must be `owner/repository`, and the token must include that repository.'],
                                    ['"The token needs Workflows: Read and write to change files in .github/workflows."', 'Edit the token: Workflows → Read and write.']
                                ],
                                shot: { ill: 'gh-token', cap: 'New fine-grained token: name, expiry, owner, one repository, five permissions, Generate.', alt: 'Drawing of the new fine-grained token form with callouts 1 Token name, 2 Expiration, 3 Resource owner, 4 Only select repositories, 5 the permission table Actions, Contents, Pull requests, Workflows read and write and Metadata read-only, 6 Generate token.' }
                            },
                            {
                                title: 'Not on GitHub? Your provider\'s token',
                                who: 'Git admin',
                                goal: 'The other providers use their own kind of token and Named Credential.',
                                items: ['Only if your repository isn\'t on GitHub. Pick your provider:'],
                                providers: OTHER_TOKENS
                            },
                            {
                                title: 'Keep the token in an External Credential',
                                who: 'Salesforce admin',
                                where: 'Setup → Named Credentials → External Credentials tab → New',
                                goal: 'Salesforce stores the token encrypted; no page or person can read it back.',
                                items: [
                                    'Label `RLY GitHub`, Name: `RLY_GitHub`.',
                                    'Authentication Protocol: **Custom**. Save.',
                                    'Under **Principals** press New: Parameter Name `GitHub`, Sequence 1.',
                                    'Under Authentication Parameters press Add: Name `Token`, Value: the token (`github_pat_…`).',
                                    'Press **Save**.'
                                ],
                                check: 'External Credential RLY_GitHub has one principal, GitHub, with the parameter Token.',
                                shot: { ill: 'gh-extcred', cap: 'External Credential RLY_GitHub: Custom, principal GitHub, parameter Token.', alt: 'Drawing of the New External Credential form with callouts 1 Name RLY_GitHub, 2 Authentication Protocol Custom, 3 principal Parameter Name GitHub, 4 authentication parameter Token with the token value, 5 Save.' }
                            },
                            {
                                title: 'Create the Named Credential RLY_GitHub',
                                who: 'Salesforce admin',
                                where: 'Setup → Named Credentials → Named Credentials tab → New',
                                goal: 'Release Relay calls `callout:RLY_GitHub`; this tells Salesforce where that is and how to send the token.',
                                items: [
                                    'Label `RLY GitHub`, Name: `RLY_GitHub`.',
                                    'URL: `https://api.github.com`. Leave **Enabled for Callouts** on.',
                                    'External Credential: `RLY GitHub`.',
                                    'Untick **Generate Authorization Header**.',
                                    'Tick **Allow Formulas in HTTP Header**.',
                                    'After Save: Custom Headers → New: Name `Authorization`, Value `{!\'Bearer \' & $Credential.RLY_GitHub.Token}`.',
                                    'Press **Save**.'
                                ],
                                check: 'The Named Credential shows URL https://api.github.com and one custom header, Authorization.',
                                shot: { ill: 'gh-namedcred', cap: 'Named Credential RLY_GitHub with its Authorization header.', alt: 'Drawing of the New Named Credential form with callouts 1 Name RLY_GitHub, 2 URL https://api.github.com, 3 External Credential RLY GitHub, 4 Generate Authorization Header unticked, 5 Allow Formulas in HTTP Header ticked, 6 custom header Authorization, 7 Save.' }
                            },
                            {
                                title: 'Let Release Relay users use the token',
                                who: 'Salesforce admin',
                                where: 'Setup → Permission Sets → (a permission set) → External Credential Principal Access → Edit',
                                goal: 'Raising, approving and promoting call Git as the person who presses the button, so each of them needs access to the principal.',
                                items: [
                                    'Move `RLY_GitHub - GitHub` to **Enabled**. Do it in a permission set every Release Relay user has: for example a new permission set `RLY_Git_Access` (example name) assigned to all developers, approvers, the deployment team and admins.',
                                    'Press **Save**.'
                                ],
                                text: ['The Slack principal (`RLY_Slack - Bot`) is already in the Release Relay permission sets.'],
                                check: 'Pipeline → Git connection → Check connection shows Connected (after step 12).',
                                problems: [['"Named Credential RLY_GitHub wasn\'t found or you can\'t use it. Check it exists, and that your permission set has its principal under External Credential Principal Access."', 'Do this step for the user who saw it, and check the Named Credential\'s name.']],
                                shot: { ill: 'perm-principal', cap: 'External Credential Principal Access: enable RLY_GitHub - GitHub.', alt: 'Drawing of the External Credential Principal Access edit page with callouts 1 RLY_GitHub - GitHub in Enabled, 2 Save.' }
                            },
                            {
                                title: 'Connect the repository on the Pipeline tab',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → 1 · Where the code lives → Edit',
                                goal: 'One Git connection for the whole pipeline.',
                                items: [
                                    'Provider: **GitHub** (or yours).',
                                    'Repository: `owner/repository`.',
                                    'Workflow file: `release-relay.yml`.',
                                    'Pipeline branch: `main` (where the pipeline files live).',
                                    'Named Credential (token): `RLY_GitHub`.',
                                    'Source path: `force-app/main/default`.',
                                    '**Code scan on every pull request**: on (the default) or off. Each org can follow it or set its own (D. Each org).',
                                    'Press **Save**: it tests the connection. **Check connection** on the card tests it again later.'
                                ],
                                text: ['First time in a new hub? The Pipeline tab opens **Set up Release Relay**, a short walk-through: 1 This org is the hub, 2 Git connection, 3 Pipeline files, 4 Add orgs, 5 Slack (optional). Each step is checked before **Check and continue** goes on; **Do this later** hides it, and the header button **Set up Release Relay** opens it again. It fills in the same records as this step and the next one.'],
                                check: 'The card shows Connected and lists what it checked.',
                                problems: [
                                    ['Git connection: check failed', 'Read the list on the card: a token permission, the repository name, or the pipeline files missing on the pipeline branch (C. Git provider, step 2).'],
                                    ['"No Git connection yet. Press Edit to choose the provider and repository."', 'Nothing is saved yet: press **Edit**.']
                                ],
                                shot: { ill: 'pipeline-git', cap: 'Edit Git connection: provider, repository, workflow file, branch, credential, path, Save.', alt: 'Drawing of the Edit Git connection window with callouts 1 Provider, 2 Repository, 3 Workflow file, 4 Pipeline branch, 5 Named Credential RLY_GitHub, 6 Source path, 7 Save.' }
                            },
                            {
                                title: 'Register the hub as production',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Register an org',
                                goal: 'Releases deploy to production through the hub\'s own record, and the hub knows which org is the real hub (sandbox copies are refused).',
                                items: [
                                    'Org name: for example `PROD`.',
                                    'Role: **Hub (this org, production)**. There is one hub only: once it is registered, Hub is no longer offered for other orgs, and the hub\'s own Role box is grey (it keeps its role).',
                                    'My Domain URL: the hub\'s own. **Login type** and **Salesforce environment** then turn grey: the hub signs in as production, and its environment is Production.',
                                    'Branch `prod` and Git environment `prod` (examples). Fill the sign-in fields as in D. Each org: the hub needs its own External Client App too.',
                                    'Press **Check connection and next**, then set the hub\'s Approval (Never isn\'t offered for production).'
                                ],
                                text: ['In Set up Release Relay, step 1 does the same: it reads the hub\'s My Domain and Org Id itself, and asks for the org name, integration username, consumer key, certificate, branch and Git environment.'],
                                check: 'Connected orgs → Production: the PROD card shows Connected with the role Hub, and the tab says "Production holds one org: the hub."',
                                links: [{ label: 'D. Each org: the sign-in app', to: 'setup-orgs' }],
                                shot: { ill: 'hub-register', cap: 'Register the hub: role Hub, its own My Domain, branch prod.', alt: 'Drawing of Register an org for the hub with callouts 1 Org name PROD, 2 Role Hub, 3 My Domain URL, 4 Branch and Git environment prod.' }
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
                                where: 'Guide → Repository files → Download, or Pipeline → Update pipeline files',
                                goal: 'The pipeline does the work: convert, open the pull request, scan, check-only deploy, merge, deploy.',
                                items: [
                                    'Download the workflow (`release-relay.yml`) and the script (`release-relay.js`) from Repository files.',
                                    'Commit them to `main` at `.github/workflows/release-relay.yml` and `scripts/release-relay.js`.',
                                    'Or, once the Git connection works: Pipeline → **Update pipeline files** opens a pull request with them (it needs the token\'s Workflows permission).'
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
                                where: 'Release Relay → Pipeline → 2 · Route → Create missing branches',
                                goal: 'Each org has its own branch: stages (for example `sit`, `prod`) and each developer org (for example `dev1`).',
                                items: [
                                    'Register the orgs first (D. Each org), each with its branch.',
                                    'Open **2 · Route** (it starts closed: press its arrow or title) and press **Create missing branches**: every route branch your repository doesn\'t have yet is made from the pipeline branch. The button shows once the Git connection is saved.',
                                    '`release-relay-results` (the step results) is created by the pipeline on its first run. Don\'t protect it.',
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
                                    'Name: the org\'s **Git environment** (Pipeline → Connected orgs → the org), for example `sit` or `prod`. Press Configure environment.',
                                    'Required reviewers: optional. **Recommended on `prod` for real use**: GitHub then waits for a reviewer before each job in prod (the check-only deploy too).',
                                    'Deployment branches and tags: **Selected branches** → add `main`.',
                                    'Add the four secrets (step 7).',
                                    'Add the variables (step 8).'
                                ],
                                text: ['Create one for every stage and production, and for back promote orgs. Developer orgs need none: the hub reads them itself.'],
                                check: 'Settings → Environments lists one environment per stage org.',
                                shot: { ill: 'gh-env', cap: 'An environment: name, reviewers, branches, secrets and variables.', alt: 'Drawing of a repository environment named sit with callouts 1 name, 2 Required reviewers, 3 Selected branches main, 4 Add environment secret with SF_USERNAME, SF_CLIENT_ID, SF_JKS, SF_JKS_PASSWORD, 5 Add environment variable with SF_INSTANCE_URL and SF_JKS_ALIAS.' }
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
                                where: 'Hub: Release Relay → Pipeline → Register an org (opens a window)',
                                goal: 'The hub saves how to reach the org and where it sits on the route.',
                                items: [
                                    'Org name: a short name people know, for example `SIT` or `DEV1` (examples).',
                                    'Role: **Developer org** (people build here; the label says which branch it raises into), **Stage (an org on the route)** or **Back promote (after production)**. **Hub (this org, production)** is offered only until the hub is registered (B. Hub org).',
                                    'My Domain URL: the org\'s, with `https://`.',
                                    'Login type: read from the My Domain URL and grey. A URL with `.sandbox.` is **Sandbox**; any other is **Production or Developer Edition**.',
                                    'Salesforce environment: follows the login type. A sandbox login: pick the sandbox type (**Developer sandbox or Developer Edition**, **Developer Pro sandbox**, **Partial Copy sandbox**, **Full Copy sandbox**). A production login that isn\'t the hub is a Developer Edition org, so it is set to **Developer sandbox or Developer Edition** and grey. Production belongs to the hub alone. New Release and Connected orgs group the orgs by it.',
                                    'Integration username: from step 1.',
                                    'Consumer key: from step 3. It is saved encrypted and never shown again.',
                                    'Hub certificate: `release_relay`.',
                                    'Branch: the org\'s branch, for example `sit` or `dev1`.',
                                    'Git environment: the environment holding its login (C. Git provider, step 5), usually the same as the branch.',
                                    'The fields start empty: the grey text in each is an example only. Press **Check connection and next**: it saves, signs in and reads the Org Id, sandbox name and Metadata API version.',
                                    'The window then shows the org\'s next steps one at a time: **Approval** (stages and the hub), **Back promote** (back promote orgs) and **Slack** (once Slack is set up), each with **Save and next** or **Save and finish**. **Skip** goes on without changing that step (approval Always, approved in Salesforce, no Slack channel).'
                                ],
                                check: 'The window closes, Connected orgs shows the org\'s environment tab and its card lights up, Connected.',
                                problems: SIGN_IN_PROBLEMS,
                                shot: { ill: 'register-org', cap: 'Register an org: the things to fill in, then Check connection and next.', alt: 'Drawing of the Register an org window with callouts 1 Org name, 2 Role, 3 Salesforce environment, 4 My Domain URL, 5 Login type, 6 Integration username, 7 Consumer key, 8 Hub certificate, 9 Branch, 10 Git environment, 11 Check connection and next.' }
                            },
                            {
                                title: 'Choose its code scan',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Connected orgs → click the org → Edit → Approval',
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
                                where: 'Release Relay → Pipeline → Connected orgs → click the org → Check connection',
                                goal: 'Proves the hub can still sign in (after a sandbox refresh, a new certificate or a changed user).',
                                items: ['Click the org\'s card and press **Check connection** in its window. On a failure the Sign-in section names the fix (table above).'],
                                check: 'Connected, with the time it was checked.',
                                shot: { name: 'register', cap: 'Example: Register an org. The consumer key is saved encrypted and shown as ••••.' }
                            },
                            {
                                title: 'After a sandbox refresh',
                                who: 'Salesforce admin of the sandbox',
                                where: 'The refreshed sandbox',
                                goal: 'A refresh copies production\'s setup, so the sandbox\'s app and user may change.',
                                items: [
                                    'Check the integration user is active in the sandbox, and the External Client App is there with the hub certificate.',
                                    'If the consumer key changed: Pipeline → Connected orgs → click the org → **Edit** → paste it into **Consumer key** → **Save** (a changed sign-in is checked again). The next check notes the new Org Id by itself.'
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
                        'With Slack each release posts **one card** in its target org\'s channel: a header with the release number and title, the card, and a divider under it, so each release stands on its own. The card is edited as the release moves, and each step (pull request, checks, approval, deploy) is a reply in the card\'s **thread**. Steps 1 to 6 set this up.',
                        'Approving from the card is a further, optional part (steps 7 to 15). Slack sends each Approve or Reject press to a public **Salesforce Site** in the hub, so it needs a Site, its guest user\'s access, and Slack\'s Interactivity pointed at it. Do those steps in order.',
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
                                title: 'Give it the bot scope and install it',
                                who: 'Slack admin',
                                where: 'Your app → OAuth & Permissions',
                                goal: 'The app may post and update messages, nothing more.',
                                items: [
                                    'Scopes → Bot Token Scopes → Add an OAuth Scope → `chat:write`.',
                                    'OAuth Tokens → **Install to Workspace** → Allow.',
                                    'Copy the **Bot User OAuth Token** (`xoxb-…`).'
                                ],
                                check: 'The page shows a Bot User OAuth Token starting xoxb-.',
                                shot: { ill: 'slack-scopes', cap: 'OAuth & Permissions: chat:write, install, copy the bot token.', alt: 'Drawing of the Slack app OAuth and Permissions page with callouts 1 bot token scope chat:write, 2 Install to Workspace, 3 copy Bot User OAuth Token.' }
                            },
                            {
                                title: 'Switch Slack on and save the bot token',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Slack connection → Edit',
                                goal: 'The hub posts through the Named Credential `RLY_Slack` (installed with Release Relay); the token goes into its credential store.',
                                items: [
                                    'Open **Slack connection** (it starts closed) and press **Edit**.',
                                    'Switch **Slack** on. Off stops every message; nothing else changes.',
                                    '**Bot token (starts with xoxb-)**: paste the bot token. It is never shown again.',
                                    'Under **Send a message when a release is**, tick the events: Ready for approval, Checks failed, Deployed, Deploy failed, Rejected, Raised.',
                                    'Press **Save and test**: it saves, then checks the token and shows your workspace name.'
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
                                text: ['Access to this principal is already in `RLY_Admin`, `RLY_Developer`, `RLY_Approver`, `RLY_Deploy_Team` and `RLY_Slack_Site`. If people use other permission sets, add `RLY_Slack - Bot` under External Credential Principal Access there.'],
                                check: 'The Bot principal lists the parameter Token, and the Slack connection shows Connected.',
                                shot: { ill: 'ext-cred-slack', cap: 'RLY_Slack: principal Bot → parameter Token = the bot token.', alt: 'Drawing of the RLY Slack external credential with callouts 1 Edit on principal Bot, 2 parameter name Token, 3 value xoxb placeholder, 4 Save.' }
                            },
                            {
                                title: 'Create a channel per org and invite the app',
                                who: 'Slack admin',
                                where: 'Slack → the channel',
                                goal: 'The app can only post in channels it has joined.',
                                items: [
                                    'Create one channel per org, for example `#rr-sit` and `#rr-prod` (examples). In each, type `/invite @Release Relay` (your app\'s name) and press Enter.',
                                    'Slack confirms the app was added.'
                                ],
                                problems: [['Send test message fails with not_in_channel', 'Invite the app to that channel.']],
                                shot: { ill: 'slack-invite', cap: 'In each channel: /invite @your app.', alt: 'Drawing of a Slack channel with callouts 1 the message box with /invite @Release Relay, 2 the confirmation that the app was added.' }
                            },
                            {
                                title: 'Set the channel on each org',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Connected orgs → click the org → Edit → Slack',
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
                                title: 'Approve in Slack: save the signing secret',
                                who: 'Slack admin + Release Relay admin',
                                where: 'Slack app settings → your app → Basic Information → App Credentials; then Release Relay → Pipeline → Slack connection → Edit',
                                goal: 'Proves that an Approve or Reject press really comes from your Slack app. Without it the hub refuses every press.',
                                items: [
                                    'In Slack: under **App Credentials** find **Signing Secret** and press **Show**. Copy it (not the Client Secret, not the token).',
                                    'In Release Relay: Pipeline → **Slack connection** → **Edit** → open **Approve in Slack (optional, advanced)**.',
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
                                goal: 'The Slack callback runs as the Site\'s guest user. This permission set lets it run Release Relay\'s Slack class and answer through the Slack credential, nothing else.',
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
                                where: 'Setup → Sites → your Site → Public Access Settings (the guest profile); then Setup → Permission Sets → Release Relay Slack Site',
                                goal: 'Approve starts the deploy through your Git credential as the guest user, so it needs that credential too. Without it pressing Approve does nothing at all. Apex checks Slack\'s signature and the linked approver before either credential is used.',
                                items: [
                                    'Guest profile: on the Site press **Public Access Settings** → **Edit**. Under Standard Object Permissions find **User External Credentials** and tick **Read** → **Save**. (The permission set doesn\'t offer this object for guest users.)',
                                    'Permission set **Release Relay Slack Site** → **External Credential Principal Access** → **Edit** → move your Git credential\'s principal (`RLY_GitHub - GitHub`, or your provider\'s) to Enabled → **Save**.',
                                    'In the same list check `RLY_Slack - Bot` is Enabled (it comes with `RLY_Slack_Site`; add it again if someone removed it).'
                                ],
                                check: 'The permission set lists both principals, and the guest profile has Read on User External Credentials.'
                            },
                            {
                                title: 'Approve in Slack: copy the Interactivity URL',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Slack connection → Edit → Approve in Slack (optional, advanced)',
                                goal: 'The address Slack sends the presses to: the Site\'s URL followed by `/services/apexrest/rly/slack/actions`.',
                                items: [
                                    '**Interactivity URL to paste in Slack** shows the full URL. Press **Copy**.',
                                    'Press **Cancel** (nothing changed) or **Save and test**.'
                                ],
                                text: ['The URL shows only once an active Site\'s guest user has `RLY_Slack_Site`. Until then the window says "Interactivity URL: set up a Salesforce Site first (Guide → Set up → Slack)": check steps 8 and 9, and that the Site is Active.'],
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
                                title: 'Approve in Slack: link each approver',
                                who: 'Each approver + Release Relay admin',
                                where: 'Slack → the approver\'s profile; then Release Relay → Pipeline → Slack connection → Edit → Approve in Slack (optional, advanced)',
                                goal: 'Only approvers linked to a Slack member may press Approve or Reject.',
                                items: [
                                    'Each approver, in Slack: click their own name or picture → **Profile** → **⋮** (More) → **Copy member ID**. It looks like `U0…`.',
                                    'In Release Relay: **Approvers linked** → **Link Slack member IDs**: paste each member ID next to that person\'s name (blank unlinks) → **Save and test**.',
                                    'The list holds everyone with `RLY_Approver` or `RLY_Admin`. Empty? It says "No approvers yet: assign the RLY_Approver permission set."'
                                ],
                                check: 'Show approvers on the Slack connection lists each approver as Linked.',
                                problems: [['Slack says "You can\'t approve REL-… Ask an admin to link your Slack account in Release Relay → Pipeline."', 'Link that person\'s member ID, check they have `RLY_Approver` or `RLY_Admin`, and that the release\'s target org has Approve in Slack on.']]
                            },
                            {
                                title: 'Approve in Slack: turn it on per org',
                                who: 'Release Relay admin',
                                where: 'Release Relay → Pipeline → Connected orgs → click the org → Edit → Approval',
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
                                    ['Slack shows "This app responded with status code 404" or similar', 'The Request URL is wrong or the Site isn\'t Active: copy it again from Pipeline → Slack connection (step 11).'],
                                    ['Slack shows an error after a few seconds and the card doesn\'t change', 'The signing secret is missing or wrong (step 7), or Slack is off on the Slack connection. The hub refuses unsigned presses.'],
                                    ['Pressing Approve does nothing and the release stays Ready for approval', 'The guest user can\'t use the Git credential or read User External Credentials (step 10). To see it for yourself, add a debug log for the Site guest user (Setup → Debug Logs) and press Approve again.'],
                                    ['The card shows Open in Release Relay instead of Approve', 'The org has Approve in Slack off (step 14), or the release isn\'t waiting for an approver.']
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
                                where: 'Release Relay → Pipeline → Connected orgs → click the org → Edit → Approval',
                                goal: 'Decide when a release into the org waits for a person.',
                                items: [
                                    'Always (the default), Only when it contains…, or Never (not offered for production). Optionally: hotfixes need 2 approvers.',
                                    'In the same section: the org\'s code scan (Follow the Git connection, Always scan or Don\'t scan) and where it is approved (Approve in Salesforce, Approve in Slack).'
                                ],
                                links: [{ label: 'Approval rules', to: 'approvalrules' }]
                            },
                            {
                                title: 'Name the deployment team',
                                who: 'Salesforce admin',
                                where: 'Setup → Permission Sets → RLY_Deploy_Team → Manage Assignments',
                                goal: 'Only they (and admins) tick manual steps off per org.',
                                items: ['Assign `RLY_Deploy_Team` (Release Relay Deployment Team) to the people who do manual steps.'],
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
                                items: ['Pick `RlySandboxCopy` as the Apex Class. When the copy is ready it switches Slack off, marks the Git connection Not checked and removes everyone\'s assignments of Release Relay\'s own permission sets (`RLY_Developer`, `RLY_Approver`, `RLY_Deploy_Team`, `RLY_Slack_Site`; `RLY_Admin` stays, and your own sets are left alone). Release Relay detects the sandbox by itself and refuses actions there anyway.'],
                                links: [{ label: 'Sandbox copies of the hub', to: 'sandboxcopy' }]
                            },
                            {
                                title: 'Keep production reviewers on',
                                who: 'Git admin',
                                where: 'Repository → Settings → Environments → prod → Required reviewers',
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
                                where: 'Release Relay → Pipeline → 1 · Where the code lives → Update pipeline files',
                                goal: 'Lets the Git pipeline ask the hub every night to remove finished releases older than the Retention days, so storage stays free without anyone pressing Run now. It needs Retention days set and “Archive every night” on (Pipeline tab).',
                                items: ['Update pipeline files (Pipeline tab, section 1) to version 15, or add this to `.github/workflows/release-relay.yml`:'],
                                code: 'on:\n'
                                    + '  workflow_dispatch:      # already there\n'
                                    + '  schedule:\n'
                                    + '    - cron: "0 8 * * *"   # 08:00 UTC = 2:00 AM Central (CST)\n'
                                    + '\n'
                                    + 'jobs:\n'
                                    + '  archive:\n'
                                    + '    if: github.event_name == \'schedule\'\n'
                                    + '    runs-on: ubuntu-latest\n'
                                    + '    steps:\n'
                                    + '      - uses: actions/checkout@v4\n'
                                    + '      - name: Archive finished releases in the hub\n'
                                    + '        # signs in to the hub and calls\n'
                                    + '        # /services/apexrest/rly/archive until done\n'
                                    + '        run: ./relay/archive.sh',
                                text: ['**Cron is UTC.** Pick the UTC hour for your quiet time: 2:00 AM Central is `0 8 * * *` in winter (CST) and `0 7 * * *` in summer (CDT); with one fixed line it runs an hour later in summer. GitHub may start scheduled jobs a few minutes late, and pauses schedules in public repositories after 60 days without activity.'],
                                problems: [
                                    ['The Archive tab says "Missed the last 2 nights"', 'Check the schedule in `release-relay.yml` on the pipeline branch, and that the workflow is enabled in GitHub → Actions. The job signs in to the hub like the other jobs, so the prod environment needs its secrets and variables.'],
                                    ['"Last call skipped: nightly is off"', 'Turn on **Archive every night** in Pipeline → Retention → Edit (it needs the days set first).']
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
                            ['Permission sets assigned', 'Hub: Setup → Permission Sets', 'People see their tabs; admins see Pipeline'],
                            ['Certificate `release_relay`', 'Hub: Setup → Certificate and Key Management', 'Listed, exportable key'],
                            ['`release_relay.crt` and the `.jks` + password', 'Your computer / password manager', 'Both files kept safe'],
                            ['Remote Site per org (the hub too)', 'Hub: Setup → Remote Site Settings', 'One active row per org'],
                            ['Git token', 'Git provider → Fine-grained tokens', 'Actions, Contents, Pull requests, Workflows: read and write'],
                            ['External Credential + Named Credential `RLY_GitHub`', 'Hub: Setup → Named Credentials', 'Principal GitHub with Token; header Authorization'],
                            ['Principal access `RLY_GitHub - GitHub`', 'Hub: a permission set every user has', 'No "can\'t use it" errors'],
                            ['Git connection', 'Pipeline → 1 · Where the code lives', 'Connected'],
                            ['Pipeline files on `main`', 'Repository / Guide → Repository files', 'Pipeline files: up to date'],
                            ['Workflow permissions', 'Repository → Settings → Actions → General', 'Read and write; may create pull requests'],
                            ['Environment per stage org + prod', 'Repository → Settings → Environments', '4 secrets + 2 variables each'],
                            ['Integration user + External Client App per org', 'Each org: Setup', 'JWT on, hub .crt, user pre-authorized'],
                            ['Each org registered (the hub as Hub)', 'Pipeline → Connected orgs', 'Every card Connected'],
                            ['Route branches', 'Pipeline → 2 · Route → Create missing branches', 'Every route branch already exists'],
                            ['Slack (optional): token, channels, test', 'Pipeline → Slack connection · each org → Edit → Slack', 'Connected; test message arrives'],
                            ['Approve in Slack (optional)', 'Signing secret · Site with RLY_Slack_Site on its guest user · guest Read on User External Credentials and the Git principal · Request URL in the App Manifest, Socket Mode off · linked approvers · Approve in Slack per org', 'Slack connection says Approve in Slack: Set up; Approve works from the card'],
                            ['Approval rules, deployment team', 'Pipeline → Connected orgs · RLY_Deploy_Team', 'Set as your process needs'],
                            ['Caching on, prod reviewers on', 'Session Settings · Environments → prod', 'Before real users start'],
                            ['Retention and the nightly archive (optional)', 'Pipeline → Retention · pipeline files version 15 (scheduled job)', 'Archive tab shows a nightly call'],
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
                            '**Git provider**: one repository (GitHub, GitLab, Bitbucket or Azure DevOps). Each org has a branch; every release is a pull request into the next stage\'s branch.',
                            '**Pipeline**: your provider\'s pipeline runs the code scan and a check-only deploy with your tests, and later merges and deploys.',
                            '**Route**: developer orgs → stages in order → production (the hub). Pipeline → Route shows yours. Releases, hotfixes too, are raised from developer orgs only.',
                            '**Promote**: what is deployed to a stage moves on to the next stop from the Promote tab, hotfixes first.'
                        ]
                    },
                    { type: 'links', links: [{ label: 'Admins: set it up', to: 'setup' }, { label: 'Raise a release', to: 'raise' }, { label: 'Approve', to: 'approve' }] }
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
                            { name: 'conflict', cap: 'Conflict: your version and the target\'s side by side.' },
                            { name: 'approval', cap: 'Approval: scan findings and the decision.' }
                        ]
                    },
                    { type: 'text', paras: ['**The test rule.** A release with an Apex class or trigger must include the test classes that cover it; Release Relay won\'t let you continue without one. Those tests run (RunSpecifiedTests) in every org the release deploys to. A release without Apex deploys without tests.'] }
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
                        'The greeting says how many things need you. The **Health** line shows the last saved checks: Git connection, pipeline files, Slack, approving in Slack and the code scan. When all is fine it shows one line, **All connections OK**; admins open **Pipeline ›** to check again.'
                    ] },
                    { type: 'table', cols: ['Part', 'What it shows', 'Click it to'], rows: [
                        ['Tiles', 'Open releases, Waiting for approval, Checks failed, Deployed this week, Rollbacks in 30 days, and the average days from raising a release to its first deploy.', 'Open Releases or Approvals with the matching chip picked.'],
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
                        'You build in your developer org and raise releases from it. You need the `RLY_Developer` permission set. New Release has five steps: **Where**, **Org**, **Select**, **Review**, **Raise**.',
                        'Releases always come from a **developer org**. Stage orgs (for example SIT) and production are never offered as sources: a hotfix is raised from the developer org that has the fix, and what is in a stage moves on with **Promote** (for example SIT → PROD).'
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
                                ],
                                shot: { name: 'source', cap: 'Example: Source, with Goes to under the org cards.' }
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
                                    'Deleted something? Orgs with source tracking list it with a red **Delete** pill. Otherwise press **Find deleted components** and tick only what you deleted (see Deleting components).',
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
                                shot: { name: 'select', cap: 'Example: Select, with the test rule in the bar.' }
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
                                    'Urgent fix? With the Hotfix permission tick **This is a hotfix** and answer **Why is this a hotfix?** (see Hotfix).',
                                    'Flows: each shows its version in your org; choose **After deploy** per flow (see Flows).',
                                    'Anything that can\'t be deployed (access, data, setup)? **Add a manual step** (see Manual steps).',
                                    'A blue box says whether the first stage asks for approval, for example "Approval in SIT: Always needs approval in SIT." (an example).'
                                ],
                                links: [{ label: 'Compare and changes', to: 'compare' }, { label: 'Flows', to: 'flows' }, { label: 'Manual steps', to: 'manual' }, { label: 'Hotfix', to: 'hotfix' }],
                                shot: { name: 'review', cap: 'Example: Review, what goes in and which tests run.' }
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
                                    'Status: **Open** (running, checks failed or waiting for approval; the default), **Deployed**, **Rolled back**, **Failed**, **Rejected** (rejected or closed) or **All**. Each shows a count.',
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
                                    'Under the steps: **Quality gates failed**, **Code scan findings** (priority, rule, where, finding) and **Deployment errors**. Fix them in your org and add the fix (Add changes), or raise again, or ask an approver to bypass a blocking code scan.',
                                    '**Details**: status, code scan, validation, branch, why it is a hotfix, what a promotion carries, deletions, manual steps, Promoted in and the Slack card. Then **Components** and **Changes** (see Compare and changes), **Flows**, **History** (newest first) and **Manual steps**.',
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
                                    'An org approved in Slack only has no Approve button here: "Approved from the Slack card."'
                                ],
                                problems: [['"Checks can run again on an open pull request that isn\'t approved yet."', 'The release is approved, deploying or closed: nothing to check again.']]
                            },
                            {
                                title: 'Resolve a conflict',
                                where: 'The release page → Progress → Conflict with <target>',
                                goal: 'Two releases changed the same lines; you decide which lines stay.',
                                items: [
                                    'Press **Resolve conflicts**. The window shows your version and the target\'s side by side.',
                                    'For each file choose **Keep mine**, **Keep <target>\'s** (for example Keep SIT\'s) or **Edit** (keep the lines you want and remove the conflict markers). **Next file** goes on.',
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
                                    'Compared: Apex classes and triggers, Visualforce pages and components, flows, layouts, permission sets, Lightning web components and Aura components. Objects, fields, record types, profiles and other types show **Not available** ("Compare isn\'t available for … yet"): see them under **Changes** after raising. Static resources and other binary files aren\'t compared either.',
                                    'Up to 25 components at a time: with more, the window says so and shows the first 25. A very large file says **Too large to compare here**.',
                                    'A flow shows its versions on both sides, for example Version 8 · Draft against Version 7 · Active (an example). When your org has an active version and a newer draft, the copy compared is the active one, and the window says the newer version isn\'t compared.'
                                ],
                                check: 'Close and press Compare again to read a fresh copy.'
                            },
                            {
                                title: 'See the changes after raising',
                                where: 'The release page → Details → Changes',
                                goal: 'The pull request\'s files as GitHub shows them, for releases and promotions.',
                                items: [
                                    'The **Changes** tab is next to **Components** once the release has a pull request. Its files load the first time you open it ("Reading the pull request\'s files…"), each with its lines added and removed.',
                                    'Click a file to see its diff in a wide window; ↑ and ↓ (or the file list) step through the files. **Open in GitHub ↗** opens the pull request\'s files.',
                                    'A binary or very large file says **No preview: open in GitHub.** Up to 300 files are listed ("Showing 300 of … files"); the pull request has the rest.',
                                    'With GitLab, Bitbucket or Azure DevOps the tab says "Changes are shown for GitHub only; open the pull request." If reading fails, the tab says why and has **Try again**.'
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
                                    'Press **Add to** the release. The page shows the release again: the changes are committed to its branch, its pull request updates, then the code scan and check-only deploy run again (with the release\'s tests and the new ones).'
                                ],
                                problems: [['"… already matches … for these components. Nothing to add."', 'The release\'s branch already has these components as your org has them: pick what actually changed.']],
                                check: 'The History shows **Added 1 component from** the developer org, and any approval given before is cleared.'
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
                                title: 'Review',
                                where: 'New Release → Review',
                                text: [
                                    'Deletions are listed in red under **Deleted from** the target. A component can\'t be both added and deleted in one release.',
                                    'Deleting Apex needs no test class unless Apex is also added. Into production, Salesforce runs the local tests when Apex is deleted.'
                                ],
                                problems: [['"<Type> <Name> isn\'t in <branch>, so there\'s nothing to delete."', 'The component isn\'t in the target\'s branch: untick it.']]
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
                aside: SHOT_NOTE,
                blocks: [
                    { type: 'text', paras: ['You decide what goes into each stage. You need the `RLY_Approver` permission set. Each org card on the Pipeline tab sets **whether** a release into that org needs you (its approval rule) and **where** it is approved: **Approve in Salesforce**, **Approve in Slack**, and optionally your Git provider\'s reviewers too.'] },
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
                                problems: [['"Nothing waiting for approval."', 'Nothing has finished its checks. Running releases are on the Releases tab.']],
                                shot: { name: 'approvals', cap: 'Example: the Approvals tab.' }
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
                                    ['"Only approvers can do this (permission set Release Relay Approver)."', 'Ask an admin for `RLY_Approver`.']
                                ],
                                shot: { name: 'approval', cap: 'Example: a release ready for approval.' }
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
                                problems: [['"couldn\'t close the pull request"', 'The Git token needs Pull requests: Read and write (Set up → B. Hub org).']]
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
                                where: 'Pipeline → Connected orgs → click the org → Edit → Approval',
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
                            'Each stop decides for itself: a release into the first stage follows that org\'s rule; a promotion into production follows production\'s. For example (an example only): a test stage set to Never, and production set to Always.'
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
                                who: 'Developer',
                                where: 'New Release → Review → Manual steps',
                                items: [
                                    'Press **Add a manual step**: a **Title**, the **Category** (Profile or permission access, Data, Setup configuration, Other), **When** (Before deploy or After deploy) and the exact **Instructions**, for example `Profile Sales User: Account.Region__c read/edit`.',
                                    '**Also in back promote orgs** is on by default. **Orgs**: all orgs on the route, or pick the orgs it applies to.',
                                    'Order them with the up and down arrows: the deployment team does them in that order. Up to 50 steps.',
                                    'A flow set to **Leave inactive** adds the step **Activate flow <name>** (Setup, After deploy, every org) for you.',
                                    'Until the release is first deployed, the person who raised it (or an admin) can add, edit, reorder and delete steps on the release page.',
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
                                    'Do the step, then tick it: the page records who did it and when.',
                                    '**Not needed** asks why (for example: already set in this org). **Reopen** puts a step back to do.',
                                    '**Show instructions** opens what exactly to do.',
                                    '**Add a manual step** adds one (until the first deploy).'
                                ],
                                text: ['Only users with `RLY_Deploy_Team` (Release Relay Deployment Team) or `RLY_Admin` tick steps and see **Log in to <org> ↗** and **Open org ▾**. Only the login address is shown, never a password or other sign-in detail.'],
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
                                    'After the deploy, the release page → Flows shows one line per flow and org, for example `SIT v9 active · PROD v9 active` (an example only), or why activation failed.'
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
                                text: ['Hotfixes are listed first, with the reason. The Slack card starts with **Hotfix:** and shows **Why:**. Whether an approver is needed follows the org\'s approval rule: give the org **Always**, or tick **Hotfixes**, so every hotfix waits for one.']
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
                    }
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
                                who: 'Release Relay admin or deployment team (`RLY_Admin`, `RLY_Deploy_Team`)',
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
                    { type: 'note', text: 'A snapshot is taken before every deploy by pipeline version 13 or later. Release Relay\'s own components are never rolled back. The Releases tab lists rolled back releases under their own chip, and Export CSV has **Rolled back in** and **Rolled back on** columns.' }
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
                    { type: 'text', paras: ['Some values differ per org: an endpoint, an email address, a record id. Keep one placeholder in Git and let the pipeline put each org\'s value in when it deploys.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Add the value per org',
                                who: 'Developer or Git admin',
                                where: 'Pipeline → Per-org values → Edit .relay/values.json ↗ (or Create .relay/values.json ↗)',
                                items: [
                                    'Open **Per-org values** on the Pipeline tab (it starts closed) and press the link beside its title. It opens your Git provider\'s editor for `.relay/values.json` on the pipeline branch. When the file isn\'t there yet the link reads **Create .relay/values.json ↗** and opens a new file with a starter: one example value with a column per org\'s Git environment.',
                                    'Add a name with a value per org, keyed by each org\'s **Git environment**. Example: `{ "values": { "PAYMENT_URL": { "dev1": "https://dev.pay.example", "sit": "https://sit.pay.example", "prod": "https://pay.example" } } }`.',
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
                    { type: 'note', text: 'Every org on the route needs a value, or the check fails and says which (for example "PAYMENT_URL has no value for sit in .relay/values.json"); the closed Per-org values section shows a pill such as **1 missing value**. Values shorter than 6 characters aren\'t turned back into placeholders on retrieve. Values are in Git, so never put passwords there. The Pipeline tab only shows them: you change them in Git. If the file isn\'t valid JSON the section says ".relay/values.json isn\'t a valid JSON object, so the values can\'t be shown."' }
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
                        'The Pipeline tab shows them under **Quality gates** (it starts closed), one line each, set or not. The link beside the title opens your Git provider\'s editor: **Edit .relay/gates.json ↗**, or **Create .relay/gates.json ↗** when the file isn\'t there yet (a new file with a starter: scan at priority 2, 75% per class, tests for Apex). Commit it in your Git provider; the next release uses it.'
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
                title: 'Promote to the next stop (for example SIT → PROD)',
                blocks: [
                    { type: 'text', paras: ['Releases deployed to a stage move on to the next stop (the next stage, or production) from the **Promote** tab. You need `RLY_Approver` or `RLY_Admin`.', '**The next stop gets each file as it is in the stage** (for example PROD gets each file as it is in SIT). So older releases that changed the same file go too, and a newer one must be added: a file can\'t go without the changes the stage already has in it.'] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Pick what goes',
                                who: 'Approver or admin',
                                where: 'Promote tab',
                                goal: 'One block per stage, for example SIT → PROD · prod: the releases deployed there and not yet in the next stop.',
                                items: [
                                    'Tick the releases to promote: nothing is ticked when the tab opens. Hotfixes are first, then the oldest deploy first ("Changes are promoted in that order"). Unticked ones show **Stays in** the stage, for later. A hotfix can go on its own.',
                                    'An older release that changed the same component as one you ticked goes too: it shows a dashed box and **Goes with** the release, and the panel lists it under **Also goes**. It is marked promoted with the others and leaves the list.',
                                    'A newer release that changed the same component blocks the promotion, in red: "… changed … after …: add it, or wait and promote them together." Press **+ Add** and its number to tick it. The Promote button stays grey until then.',
                                    'The panel on the right (**Bundle into one** next stop **release**, or **Promote the hotfix alone**) counts the releases, components and deletions, lists the test classes that run in the next stop (RunSpecifiedTests, 75% each) and the manual steps it carries, in order.',
                                    '**Title**: suggested for you ("Promote 2 releases to PROD", or the hotfix\'s own title; an example); change it if you like. It is required.',
                                    'Press **Promote <n> releases to** the next stop (or **Promote hotfix to** it).'
                                ],
                                check: 'The new release of type Promotion shows on the tab, on the branch `promote/rel-xxxxx`, and runs the scan, check-only deploy and tests. **Promote more** goes back to the list.',
                                problems: [
                                    ['"You can see what is waiting. Approvers and admins promote it."', 'You can\'t promote: ask for `RLY_Approver`.'],
                                    ['"No stage on the route yet. An admin sets up the route on the Pipeline tab."', 'An admin registers the stages (Pipeline tab).'],
                                    ['"Nothing deployed to … is waiting to be promoted."', 'Nothing to do for that stage: everything deployed there is already in the next stop.'],
                                    ['"Some of these releases aren\'t waiting in … any more. Reload the list."', 'Someone promoted them meanwhile: press ↻ (Read again) and pick again.'],
                                    ['"The Git connection isn\'t set up and checked yet (Pipeline tab)."', 'An admin presses Check connection on 1 · Where the code lives.']
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
                                ]
                            },
                            {
                                title: 'If it fails with files that clash',
                                where: 'The promotion\'s page → Progress',
                                goal: 'The next stop has a change to a file that the stage doesn\'t have, for example a hotfix that wasn\'t merged back down.',
                                items: [
                                    'The page says, for example, "prod has a change to … that sit doesn\'t have (a hotfix not merged back down?). Merge prod into sit first, then promote again." (branch names are examples) and lists the **Files that clash**.',
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
                                where: 'Pipeline → Register an org',
                                text: ['Use the role **Back promote (after production)**, with its own branch and Git environment (and that environment\'s login, as for a stage). On the route it shows dashed after production, with how many releases it is behind.']
                            },
                            {
                                title: 'Switch it on',
                                who: 'Admin',
                                where: 'Pipeline → Back promote (next to 1 · Where the code lives) → Edit',
                                text: ['Press **Edit** on the small Back promote card beside the Git connection, turn on **Send <hub>\'s changes to other orgs after a deploy** (your hub\'s name, for example PROD), and press **Save**. The card then shows **On**; while it is off it shows **Off by default**.']
                            },
                            {
                                title: 'Choose when, and whether to approve',
                                who: 'Admin',
                                where: 'Pipeline → Connected orgs → click the org → Edit → Back promote',
                                items: [
                                    '**When** the org gets the hub\'s changes: **After every <hub> deploy**, or **When an admin clicks Sync now** (the default).',
                                    '**Approve before syncing**: off by default, so production\'s approval is enough. On: each sync waits for an approver.',
                                    'Press **Save**.'
                                ]
                            },
                            {
                                title: 'Sync now',
                                who: 'Admin',
                                where: 'Pipeline → Connected orgs → click the org → Back promote → Sync now',
                                items: [
                                    'Brings the org up to date with production at once. The section shows how many releases it is behind (or **Matches** the hub), which ones, and the last sync with its result.',
                                    '**Sync now** is grey while back promote is off: "Back promote is off. Switch it on under Back promote, next to the Git connection, to sync this org."'
                                ],
                                text: ['A sync merges production\'s branch into the org\'s branch, deploys what changed, and only then pushes the branch. A conflict or a failed deploy stops it, and nothing is pushed.']
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
                                    '**Files**: each PDF is kept (for example `REL-00034 evidence 2026-10-31 16:05.pdf`, an example only). Press it again later for a newer copy; the older ones stay.'
                                ],
                                problems: [['Download evidence (PDF) fails', 'The message says why. Try again later; Copy summary and History still work meanwhile.']],
                                shot: { ill: 'evidence', cap: 'Release page: Download evidence (PDF), Copy summary, History, Files.', alt: 'Drawing of a release page header with callouts 1 Download evidence PDF, 2 Copy summary, 3 the History timeline, 4 the saved PDF under Files.' }
                            },
                            {
                                title: 'Export CSV',
                                where: 'Releases tab → Export CSV',
                                text: ['Exports the releases that match the filters (Raised by, status, search) to `releases-<date>.csv`: release, title, route, raised by and on, status, approved by and on, approved via, comment, second approver, deployed to, deploy ids, pull request link, and rolled back in and on.']
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
                                    ['A private message "You can\'t approve REL-… Ask an admin to link your Slack account in Release Relay → Pipeline."', 'An admin links your Slack member ID (Slack connection → Edit → Approve in Slack → Link Slack member IDs), and you need `RLY_Approver`. The release\'s org must have Approve in Slack on.'],
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
        key: 'pipelinetab',
        group: 'daily',
        label: 'Pipeline tab (admin)',
        adminOnly: true,
        cards: [
            {
                key: 'pt-main',
                title: 'Pipeline tab',
                aside: SHOT_NOTE,
                blocks: [
                    { type: 'text', paras: [
                        'The Pipeline tab holds the setup, in sections: **1 · Where the code lives** (the Git connection) with **Back promote** beside it, **2 · Route**, **Per-org values** and **Quality gates** (once the Git connection is saved), **Slack connection** and **Connected orgs**.',
                        'Every section folds: press the arrow (or the title) to open or close it. A closed section shows one grey line with what it holds, for example the provider, repository and status, and a pill when something needs you. Section 1 and Connected orgs start open; the tab remembers what you open or close in this browser. A section with a problem (a failed check, missing pipeline files, route warnings, a file that can\'t be read, a Slack error) opens by itself. A section being edited stays open until you Save or Cancel.',
                        'Everything is read-only until you press **Edit**, and nothing changes until you press Save. One thing is edited at a time: the other Edit buttons and Register an org are grey meanwhile.',
                        'In the header: **Setup steps for a new org** shows what each org needs before you register it (**Hide setup steps** closes it), **Set up Release Relay** opens the first-run walk-through (B. Hub org), and **Register an org**.'
                    ] },
                    {
                        type: 'steps',
                        steps: [
                            {
                                title: 'Register an org',
                                who: 'Admin',
                                where: 'Pipeline → Register an org (page header, or the + Register an org card on a Connected orgs tab)',
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
                                where: 'Pipeline → Connected orgs → the org\'s environment tab → its card',
                                goal: 'Keep each org\'s sign-in, approval and Slack settings right.',
                                items: [
                                    'Connected orgs has one tab per Salesforce environment (Developer sandbox or Developer Edition, Developer Pro sandbox, Partial Copy sandbox, Full Copy sandbox, Production), each with how many orgs it has. An org with no environment is under **Not set**. Arrow keys move between the tabs; the tab you pick is remembered.',
                                    '**Production** holds one org: the hub. Once the hub is registered that tab has no + Register an org card: "Production holds one org: the hub. Register other orgs on their sandbox tab." An empty tab says "No orgs in … yet."',
                                    'Each card shows the org\'s name, role (Developer, Stage 1, Hub, Back promote), sign-in status, branch, a line about approval (for example **Always · Code scan: Follows Git (on)**, or **Raises into sit** for a developer org), and when it was last checked.',
                                    'Click a card (or press Enter on it) to open the org\'s window: Sign-in, Approval (with code scan, where it is approved, Git reviewers and the two-approver rule), Back promote for those orgs, and Slack (once Slack is set up). The line under the name says its environment, branch and last check.',
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
                                where: 'Pipeline → 1 · Where the code lives',
                                items: [
                                    'Shows the provider, repository, Named Credential (token), workflow file, pipeline branch, source path and **Code scan** (on or off for every pull request; each org can follow it or set its own).',
                                    '**Check connection** tests it again; **Edit** changes it ("Save tests the connection.").',
                                    'A line under it says whether the pipeline files are up to date (see Update the pipeline files).'
                                ],
                                problems: [['Git connection: check failed', 'Read the list on the card: a token permission, the repository name, or the pipeline files missing on the pipeline branch (Set up → B and C).']]
                            },
                            {
                                title: 'Back promote',
                                who: 'Admin',
                                where: 'Pipeline → Back promote (beside 1 · Where the code lives)',
                                items: ['The small Back promote card beside the Git connection shows whether it is on (**On**, or **Off by default**), when the back promote orgs get the hub\'s changes and how many there are. **Edit** switches it on or off in place. Each back promote org\'s own When and Sync now are in its window under Connected orgs. Folding section 1 folds this card too.'],
                                links: [{ label: 'Back promote', to: 'backpromote' }]
                            },
                            {
                                title: 'Check the route',
                                who: 'Admin',
                                where: 'Pipeline → 2 · Route',
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
                                where: 'Pipeline → Per-org values · Quality gates',
                                items: [
                                    'Both are read from the pipeline branch (the line beside the title says from which branch and when) and only shown here. You change them in Git.',
                                    'The link beside each title, **Edit .relay/values.json ↗** or **Edit .relay/gates.json ↗**, opens the file in your Git provider\'s editor. When the file isn\'t there yet it reads **Create … ↗** and opens a new file with a starter.'
                                ],
                                links: [{ label: 'Per-org values', to: 'values' }, { label: 'Quality gates', to: 'gates' }]
                            },
                            {
                                title: 'Slack connection',
                                who: 'Admin',
                                where: 'Pipeline → Slack connection',
                                items: [
                                    'Until Slack answers it shows a checklist: Slack app created, Bot token saved, Check connection, Pick a channel per org.',
                                    'Once connected: workspace, bot token (saved, never shown), the events, Approve in Slack (Set up, Not ready with what the Site\'s guest user still needs, or Not set up (optional)) and approvers linked. **Show approvers** lists them; **Check connection** checks Slack again; the last message and its result are under it.',
                                    '**Edit**: Slack on or off, bot token, events, and **Approve in Slack (optional, advanced)** with the signing secret, the Interactivity URL to paste in Slack and the approvers\' Slack member IDs. **Save and test** saves and checks.'
                                ],
                                links: [{ label: 'Set up: E. Slack', to: 'setup-slack' }]
                            },
                            {
                                title: 'Update the pipeline files',
                                who: 'Admin',
                                where: 'Pipeline → 1 · Where the code lives → Update pipeline files',
                                items: [
                                    'The line under the Git connection says **Pipeline files: up to date**, an older version in your repository, or **not found in your repository**, with a pill (Update available, Not found).',
                                    '**Update pipeline files** opens **Update pipeline files to version** n: **Files that will change**, and **How**: **Open a pull request (recommended)** or **Commit directly to** the pipeline branch. Press **Update**; then open the pull request (or the commit) from the link.'
                                ],
                                problems: [['"The token needs Workflows: Read and write to change files in .github/workflows."', 'Edit the Git token: Workflows → Read and write.']],
                                shot: { name: 'pipeline', cap: 'Example: Git connection shows Connected and lists what it checked.' }
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
                            ['Retrieving', 'The hub is reading the components from the source org.', 'Wait. Usually under a minute.'],
                            ['Workflow running', 'The pipeline is converting the files and opening the pull request.', 'Wait.'],
                            ['Validating', 'Code scan and check-only deploy are running.', 'Wait, or Check now.'],
                            ['Resolving conflicts', 'Your conflict choices were committed; the pipeline merges the target and checks again.', 'Wait.'],
                            ['Checks failed', 'The code scan blocked it, the validation failed, a quality gate failed, or it conflicts with the target.', 'Add the fix (Add changes from …), resolve the conflict, ask an approver to bypass the scan, or Check again.'],
                            ['Ready for approval', 'All checks passed (or the scan was bypassed) and the target org\'s approval rule asks for an approver.', 'An approver approves or rejects, in Salesforce or Slack. When the rule needs no approver, the release is approved automatically and deploys.'],
                            ['Deploying', 'Merging the pull request and deploying.', 'Wait.'],
                            ['Deployed', 'In the target org; developer branches updated; flows set to Activate activated.', 'Nothing. Download evidence (PDF) if the change request needs it.'],
                            ['Deploy failed', 'The merge or the deploy failed.', 'Read the reason; raise a new release.'],
                            ['Rejected', 'An approver rejected it; the pull request was closed.', 'Read the comment; raise again.'],
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
                    { type: 'note', text: '**Manual steps only** releases skip Retrieving, Workflow running and Validating: Submitted → Ready for approval → Deploying while the deployment team does the manual steps in that org → Deployed when all of them are Done or Not needed.' }
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
                        paras: ['Put each file at its path on the pipeline branch (usually `main`). Your provider\'s file and `release-relay.js` are all you need. When a new version of Release Relay brings new files, update them from the Pipeline tab: it opens a pull request with them.']
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
                    {
                        type: 'table',
                        cols: ['Permission set', 'Gives'],
                        rows: [
                            ['`RLY_Developer`', 'New Release, Releases, Guide and What\'s built tabs: raise and follow releases, read their history, download evidence and export CSV.'],
                            ['`RLY_Approver`', 'Approvals, Releases and Promote tabs (Releases for following releases and Export CSV): approve, reject, bypass a code scan, resolve conflicts, promote what is deployed to a stage. Linked to a Slack member ID, approve from the Slack card.'],
                            ['`RLY_Deploy_Team`', 'Release Relay Deployment Team: Approvals, Releases and Promote tabs (Promote read-only: what waits in each stage); tick manual steps done or not needed in each org, **Open org ▾** / **Log in to <org>**, and roll a deployed release back.'],
                            ['`RLY_Admin`', 'Pipeline tab: Git connection, orgs, route, approval rules, Slack, linked approvers, back promote. Promote tab. Includes Hotfix and the deployment team (so admins can roll back too). Shows the Set up sections of this Guide.'],
                            ['`RLY_Slack_Site`', 'For the Site guest user only, so Approve in Slack can reach the hub (with your Git credential\'s principal added, and Read on User External Credentials on the guest profile: Set up → E). Needed only when an org is approved in Slack.'],
                            ['Your Git access permission set', 'External Credential Principal Access to `RLY_GitHub` (or your provider\'s credential), for everyone who uses Release Relay. See Set up → B. Hub org.']
                        ]
                    }
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
                                    'In **Apex Class**, pick `RlySandboxCopy`. When the copy is ready it switches Slack off, marks the Git connection Not checked and removes everyone\'s assignments of Release Relay\'s own permission sets (`RLY_Developer`, `RLY_Approver`, `RLY_Deploy_Team`, `RLY_Slack_Site`; `RLY_Admin` stays, and your own sets are left alone), so only admins see the copy. If Salesforce refuses to remove them in the same step, the Git connection\'s note says so: remove them in Setup → Permission Sets.'
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
                            ['Git connection: check failed', 'The token is missing a permission or expired, the repository name is wrong, or the pipeline files aren\'t on the pipeline branch (Set up → B and C).'],
                            ['"Named Credential … wasn\'t found or you can\'t use it"', 'Give the user\'s permission set the credential\'s principal under External Credential Principal Access (Set up → B).'],
                            ['"couldn\'t close the pull request"', 'The Git token needs pull request (merge request) write access.'],
                            ['The pipeline can\'t save a result to release-relay-results', 'Settings → Actions → General: Read and write permissions, and no branch protection on release-relay-results (Set up → C).'],
                            ['A test class doesn\'t show as a test', 'It must contain @IsTest. If it isn\'t in the list, set Changed to Any time and Changed by to Anyone.'],
                            ['Slack: Not set up or Error', 'Paste the bot token again (Pipeline → Slack connection → Edit), or check the External Credential `RLY_Slack` → principal Bot → parameter Token, then **Check connection** on the Slack connection.'],
                            ['Send test message fails with not_in_channel', 'Invite the Slack app to that channel.'],
                            ['Slack: "You can\'t approve REL-… Ask an admin to link your Slack account…"', 'An admin links your Slack member ID (Slack connection → Edit → Approve in Slack → Link Slack member IDs), you need `RLY_Approver`, and the org needs Approve in Slack on.'],
                            ['"Interactivity URL: set up a Salesforce Site first (Guide → Set up → Slack)."', 'No active Site\'s guest user has `RLY_Slack_Site` yet: Set up → E, steps 8 and 9.'],
                            ['Approve in Slack does nothing, or Slack shows an error', 'Check the signing secret, the Request URL (App Manifest, Socket Mode off), and the Site guest user\'s access: Set up → E, steps 7 to 12 and the last step\'s table.'],
                            ['Raise fails: "… already matches … for these components. Nothing to commit."', 'The target branch already has these components as your org has them. Check the selection.'],
                            ['Every tab says "Release Relay isn\'t set up yet"', 'An admin finishes Set up on the Pipeline tab: the hub registered and the Git connection saved (Set up → B).'],
                            ['A flow: activation failed', 'The org\'s integration user needs the **Manage Flow** permission, or the flow version has errors in that org. Activate it in Setup → Flows, or raise again.'],
                            ['Approved automatically, but you expected an approver', 'Check the target org\'s approval rule on the Pipeline tab: Always, or tick the kind of change under Only when the release contains….'],
                            ['Download evidence (PDF) fails', 'The message says why. Try again later; Copy summary and the History card still work meanwhile.'],
                            ['A notice: this is a sandbox copy of the hub, or this org is a sandbox', 'Release Relay runs only in production. Do Set up there; see Sandbox copies of the hub.'],
                            ['Waiting for reviewers in the Git provider', 'The org requires the provider\'s reviewers too, or its environment has required reviewers: approve there, or change the org card / environment.']
                        ]
                    },
                    { type: 'links', links: [{ label: 'Set up: H. Checklist', to: 'setup-checklist' }] }
                ]
            }
        ]
    }
];

const SECTIONS = [...START_SECTIONS, ...SETUP_SECTIONS, ...USE_SECTIONS, ...REF_SECTIONS];

export default SECTIONS;
