import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IS_ADMIN from '@salesforce/customPermission/RLY_Admin';
import SHOTS from '@salesforce/resourceUrl/RLY_Guide_Shots';
import SETUP_PICS from '@salesforce/resourceUrl/RLY_Guide_Setup';
import PIPE_GITHUB from '@salesforce/resourceUrl/RLY_Pipeline_GitHub';
import PIPE_GITLAB from '@salesforce/resourceUrl/RLY_Pipeline_GitLab';
import PIPE_BITBUCKET from '@salesforce/resourceUrl/RLY_Pipeline_Bitbucket';
import PIPE_AZURE from '@salesforce/resourceUrl/RLY_Pipeline_Azure';
import PIPE_SCRIPT from '@salesforce/resourceUrl/RLY_Pipeline_Script';
import getSetup from '@salesforce/apex/RlyRouteController.getSetup';
import getPipelineFiles from '@salesforce/apex/RlyRouteController.getPipelineFiles';
import SECTIONS, { GROUPS, PROVIDERS, PIPELINE_FILES } from './guideContent';
import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';

const PIPELINE_TAB = 'RLY_Pipeline';
/** Modes of RlyHubGuard.getHubStatus in which the Guide shows only Set up and Sandbox copies of the hub. */
const SANDBOX_MODES = ['sandbox', 'copy'];
const SANDBOX_SECTION = 'sandboxcopy';
const RESOURCE_URLS = {
    RLY_Pipeline_GitHub: PIPE_GITHUB,
    RLY_Pipeline_GitLab: PIPE_GITLAB,
    RLY_Pipeline_Bitbucket: PIPE_BITBUCKET,
    RLY_Pipeline_Azure: PIPE_AZURE,
    RLY_Pipeline_Script: PIPE_SCRIPT
};

/** Where each browser keeps the ticks of the setup checklist (a convenience only: nothing depends on it). */
const DONE_KEY = 'rlyGuideSetupDone';

function readDone() {
    try {
        const raw = window.localStorage.getItem(DONE_KEY);
        const parsed = raw ? JSON.parse(raw) : {};
        return parsed && typeof parsed === 'object' ? parsed : {};
    } catch {
        return {};
    }
}

function writeDone(done) {
    try {
        window.localStorage.setItem(DONE_KEY, JSON.stringify(done));
    } catch {
        // Storage blocked (private window, previews): the ticks then last for this page only.
    }
}

const MARK = /(`[^`]+`|\*\*[^*]+\*\*)/;

/**
 * Splits text with `code` and **bold** marks into pieces the template renders as spans (no HTML is injected).
 * In GitLab, a pull request is called a merge request. "Release Relay" becomes the app's name.
 */
function plain(text, gitlab) {
    const value = String(text).replace(/Release Relay/g, APP_NAME);
    return gitlab ? value.replace(/pull request/g, 'merge request').replace(/Pull request/g, 'Merge request') : value;
}

function rich(text, key, gitlab) {
    const value = plain(text, gitlab);
    return {
        key,
        segs: value.split(MARK).filter((t) => t !== '').map((t, i) => {
            if (t.startsWith('`') && t.endsWith('`') && t.length > 1) {
                return { key: key + 's' + i, t: t.slice(1, -1), cls: 'rr-mono' };
            }
            if (t.startsWith('**') && t.endsWith('**') && t.length > 3) {
                return { key: key + 's' + i, t: t.slice(2, -2), cls: 'rr-strong' };
            }
            return { key: key + 's' + i, t, cls: '' };
        })
    };
}

/** "Pipeline files: …" as the Pipeline tab says it: up to date, older in the repository, or not found. */
function filesStatusText(st) {
    if (!st || !st.packagedVersion) {
        return '';
    }
    if (st.repoVersion === null || st.repoVersion === undefined) {
        return 'Pipeline files: not found in your repository · version ' + st.packagedVersion + ' available';
    }
    if (st.upToDate) {
        return 'Pipeline files: up to date (version ' + st.packagedVersion + ')';
    }
    return 'Pipeline files: version ' + st.repoVersion + ' in your repository · version ' + st.packagedVersion + ' available';
}

/** The Release Relay guide: a left navigation (Start here, Daily use, Reference) and the chosen section on the right. */
export default class RlyReleaseGuide extends NavigationMixin(LightningElement) {
    /**
     * RlyHubGuard.getHubStatus: the org's mode. In a sandbox or a sandbox copy of the hub the Guide shows the notice, then
     * only Set up and Sandbox copies of the hub; in production not set up yet it opens at Set up.
     */
    hubStatus;
    /** The status has been read, or failed to read (then the full Guide shows). */
    statusRead = false;
    /** The user picked a section: the status no longer moves them. */
    navigated = false;
    get hubCopy() { return !!(this.hubStatus && this.hubStatus.isHubCopy); }
    get hubCopyMessage() { return this.hubCopy ? this.hubStatus.message : ''; }
    /** A sandbox or a copy of the hub (no override): the notice and the Set up sections only. */
    get limited() { return !!this.hubStatus && SANDBOX_MODES.includes(this.hubStatus.mode); }
    get notLimited() { return !this.limited; }
    /** Set up in a sandbox: these steps are done in production. */
    get showSandboxLine() { return this.limited && this.section.group === 'setup'; }

    /** Reads the hub status once; then, outside a sandbox, what the Guide reads from the hub. */
    readHubStatus() {
        getHubStatus()
            .then((status) => {
                this.hubStatus = status;
            })
            .catch(() => {
                this.hubStatus = undefined;
            })
            .finally(() => {
                this.statusRead = true;
                const mode = this.hubStatus && this.hubStatus.mode;
                if (!this.navigated && (this.limited || mode === 'setup')) {
                    this.current = 'setup';
                }
                if (!this.limited) {
                    this.readFromHub();
                }
            });
    }

    /** The app's name, from Custom Label RLY_App_Name, so each owner can rename it. */
    get appName() { return APP_NAME; }
    current = IS_ADMIN ? 'setup' : 'how';
    provider = 'GitHub';
    repository = '';
    setupStep = 1;
    zoom;
    focusClose = false;
    /** RlyRouteController.getPipelineFiles: versions in the repository and packaged (admins, read once). */
    pipeStatus;
    pipeLoading = false;
    pipeError;
    showOtherFiles = false;
    /** The setup checklist's ticks, by section key (kept in this browser). */
    setupDone = {};
    scrollTop = false;

    connectedCallback() {
        this.setupDone = readDone();
        this.readHubStatus();
    }

    /** The pipeline files' versions and the Git connection's provider (not in a sandbox: they are production's). */
    readFromHub() {
        this.loadFilesIfShown();
        // The Git connection decides which provider tab opens first (admins only: the setup sections are theirs).
        if (IS_ADMIN) {
            getSetup()
                .then((s) => {
                    if (s && s.git) {
                        this.provider = s.git.Provider__c || this.provider;
                        this.repository = s.git.Repository__c || '';
                    }
                })
                .catch(() => {
                    this.repository = '';
                });
        }
    }

    renderedCallback() {
        if (this.scrollTop) {
            this.scrollTop = false;
            const main = this.template.querySelector('.rr-main');
            if (main && main.scrollIntoView) {
                main.scrollIntoView({ block: 'start' });
            }
            // The section opened: its first heading takes the focus, so keyboard and screen reader users land there too.
            const heading = this.template.querySelector('.rr-main .rr-h2');
            if (heading && heading.focus) {
                heading.focus({ preventScroll: true });
            }
        }
        if (this.focusClose) {
            const close = this.template.querySelector('.rr-close');
            if (close) {
                close.focus();
                this.focusClose = false;
            }
        }
    }

    get isAdmin() { return !!IS_ADMIN; }
    get adminNote() { return 'Admin sections show only to ' + APP_NAME + ' Admin'; }
    /** The Git connection is set up: its provider's instructions show without the provider tabs. */
    get providerKnown() { return !!this.repository && PROVIDERS.some((p) => p.value === this.provider); }
    /** The repository's own name (the last part of owner/repository), for the files tree. */
    get repoName() { return this.repository ? this.repository.split('/').pop() : ''; }
    get gitlab() { return this.provider === 'GitLab'; }

    get visibleSections() {
        if (this.limited) {
            return SECTIONS.filter((s) => s.group === 'setup' || s.key === SANDBOX_SECTION);
        }
        return SECTIONS.filter((s) => !s.adminOnly || IS_ADMIN);
    }

    get navGroups() {
        return GROUPS.map((g) => ({
            key: g.key,
            label: g.label,
            items: this.visibleSections.filter((s) => s.group === g.key).map((s) => ({
                key: s.key,
                label: s.label,
                cls: s.key === this.section.key ? 'rr-nav-item rr-nav-on' : 'rr-nav-item',
                current: s.key === this.section.key ? 'page' : null
            }))
        })).filter((g) => g.items.length > 0);
    }

    /** The section on screen shows the download list (Repository files, or Set up, which includes it). */
    get filesShown() {
        const s = this.section;
        return !!s && (s.cards.some((c) => c.blocks.some((b) => b.type === 'files'))
            || (s.more || []).some((m) => m.key === 'repo-files'));
    }

    loadFilesIfShown() {
        if (!IS_ADMIN || this.limited || !this.statusRead || this.pipeStatus || this.pipeLoading || !this.filesShown) {
            return;
        }
        this.pipeLoading = true;
        getPipelineFiles()
            .then((st) => {
                this.pipeStatus = st;
                if (st && st.provider) {
                    this.provider = st.provider;
                }
            })
            .catch((e) => {
                this.pipeError = (e && e.body && e.body.message) || 'The versions in your repository could not be read.';
            })
            .finally(() => {
                this.pipeLoading = false;
            });
    }

    /** The hub's provider (Git connection), or none yet: then every file shows. */
    get hubProvider() {
        return (this.pipeStatus && this.pipeStatus.provider) || (this.repository ? this.provider : '');
    }

    /** Every packaged file: this hub's provider first (and the script), the other providers behind "Show other providers". */
    get fileRows() {
        const st = this.pipeStatus;
        const fromHub = (st && st.files) || [];
        const hub = this.hubProvider;
        const packaged = st && st.packagedVersion;
        return PIPELINE_FILES.map((f, i) => {
            const h = fromHub.find((x) => x.resourceName === f.resource) || {};
            const name = h.name || f.name;
            const mine = !hub || f.provider === 'All' || f.provider === hub;
            const repo = mine && st ? h.repoVersion : undefined;
            let repoText = '';
            let repoCls = '';
            if (mine && st) {
                if (repo === null || repo === undefined) {
                    repoText = 'Not in your repository';
                    repoCls = 'rr-pill rr-pill-none';
                } else if (repo >= packaged) {
                    repoText = 'Up to date in your repository';
                    repoCls = 'rr-pill rr-pill-ok';
                } else {
                    repoText = 'Version ' + repo + ' in your repository';
                    repoCls = 'rr-pill rr-pill-wait';
                }
            }
            const providerLabel = f.provider === 'All' ? 'Every provider' : (PROVIDERS.find((p) => p.value === f.provider) || {}).label;
            return {
                key: 'pf' + i,
                name,
                path: h.repoPath || f.path,
                what: plain(f.what, (f.provider === 'GitLab') || (f.provider === 'All' && this.gitlab)),
                providerLabel,
                version: packaged ? 'Version ' + packaged : '',
                repoText,
                repoCls,
                url: RESOURCE_URLS[f.resource],
                downloadLabel: 'Download ' + name,
                order: mine ? 0 : 1,
                mine,
                // The script last among this hub's files.
                rank: f.provider === 'All' ? 1 : 0
            };
        }).sort((a, b) => (a.order - b.order) || (a.rank - b.rank));
    }

    get filesStatusLine() {
        if (this.pipeLoading) {
            return 'Pipeline files: checking your repository…';
        }
        return filesStatusText(this.pipeStatus);
    }
    get filesStatusCls() {
        const st = this.pipeStatus;
        if (!st || this.pipeLoading) {
            return 'rr-pill rr-pill-none';
        }
        return st.upToDate ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-wait';
    }
    get filesStatusPill() {
        const st = this.pipeStatus;
        if (!st || this.pipeLoading) {
            return 'Checking';
        }
        if (st.upToDate) {
            return 'Up to date';
        }
        return st.repoVersion === null || st.repoVersion === undefined ? 'Not found' : 'Update available';
    }
    get filesCanUpdate() { return !!this.pipeStatus && this.pipeStatus.isAdmin === true && !this.pipeStatus.upToDate; }

    get section() {
        return this.visibleSections.find((s) => s.key === this.current) || this.visibleSections[0];
    }

    /** The section's cards, then the cards of other sections it also shows (more). */
    get cards() {
        const own = this.section.cards.map((c) => this.card(c, c.blocks, c.aside));
        const all = [];
        this.visibleSections.forEach((s) => s.cards.forEach((c) => all.push(c)));
        const extra = (this.section.more || []).map((m) => {
            const c = all.find((x) => x.key === m.key);
            return c ? this.card(c, m.only ? c.blocks.filter((b) => b.type === m.only) : c.blocks, m.noAside ? null : c.aside) : null;
        }).filter((c) => c);
        return own.concat(extra);
    }

    card(c, blocks, aside) {
        return {
            key: c.key,
            title: c.title,
            aside: c.asideFromRepo ? this.repository : aside,
            blocks: blocks.map((b, i) => this.block(b, c.key + 'b' + i))
        };
    }

    block(b, key) {
        const g = this.gitlab;
        const out = {
            key,
            isText: b.type === 'text',
            isList: b.type === 'list',
            isNote: b.type === 'note',
            isTable: b.type === 'table',
            isProgress: b.type === 'progress',
            isSteps: b.type === 'steps',
            isSeq: b.type === 'seq',
            isRepo: b.type === 'repo',
            isShots: b.type === 'shots',
            isFiles: b.type === 'files',
            isChecklist: b.type === 'checklist',
            isLinks: b.type === 'links'
        };
        if (out.isChecklist) {
            Object.assign(out, this.checklist(b.stages || [], key));
        }
        out.links = this.links(b.links, key);
        if (out.isFiles) {
            const rows = this.fileRows;
            const other = rows.filter((r) => !r.mine);
            out.fileList = rows.filter((r) => r.mine || this.showOtherFiles);
            out.hasOtherFiles = other.length > 0;
            out.otherFilesLabel = this.showOtherFiles ? 'Hide other providers' : 'Show other providers (' + other.length + ')';
            out.filesStatus = IS_ADMIN && (this.pipeLoading || !!this.pipeStatus) ? {
                text: this.filesStatusLine,
                cls: this.filesStatusCls,
                pill: this.filesStatusPill,
                canUpdate: this.filesCanUpdate,
                note: this.pipeStatus && this.pipeStatus.message
            } : null;
            out.filesError = this.pipeError;
        }
        out.paras = (b.paras || []).map((t, i) => rich(t, key + 'p' + i, g));
        out.items = (b.items || []).map((t, i) => rich(t, key + 'i' + i, g));
        out.note = b.text ? rich(b.text, key + 'n', g) : null;
        out.cols = (b.cols || []).map((c, i) => ({ key: key + 'c' + i, c }));
        out.rows = (b.rows || []).map((r, i) => ({ key: key + 'r' + i, cells: r.map((c, j) => rich(c, key + 'r' + i + 'c' + j, g)) }));
        out.progress = (b.labels || []).map((label, i) => this.progressItem(label, i + 1, key));
        out.steps = (b.steps || []).map((s, i) => this.step(s, i + 1, key + 's' + i));
        out.stops = (b.stops || []).map((s, i) => ({
            key: key + 'st' + i, title: plain(s.title, g), text: plain(s.text, g), arrow: i > 0
        }));
        out.shots = (b.shots || []).map((s, i) => this.shot(s, key + 'sh' + i));
        out.hasShots = out.shots.length > 0;
        out.tabs = b.type === 'repo' ? this.repoTabs(b, key) : [];
        out.repoOne = b.type === 'repo' && this.providerKnown ? out.tabs.find((t) => t.value === this.provider) : null;
        out.repoTabs = b.type === 'repo' && !out.repoOne;
        return out;
    }

    /** The setup stages with their ticks, and how many are done. */
    checklist(stages, key) {
        const rows = stages.map((st, i) => {
            const done = this.setupDone[st.to] === true;
            return {
                key: key + 'ck' + i,
                to: st.to,
                label: st.label,
                meta: [st.who, st.time].filter((x) => x).join(' · '),
                done,
                cls: done ? 'rr-ck rr-ck-done' : 'rr-ck',
                openLabel: 'Open ' + st.label
            };
        });
        const count = rows.filter((r) => r.done).length;
        return {
            checkRows: rows,
            checkPct: rows.length ? Math.round((count * 100) / rows.length) : 0,
            checkText: count + ' of ' + rows.length + ' stages done'
        };
    }

    /** Buttons that open another section; a section this user can't see is left out. */
    links(list, key) {
        return (list || []).filter((l) => this.visibleSections.some((s) => s.key === l.to))
            .map((l, i) => ({ key: key + 'l' + i, label: l.label, to: l.to }));
    }

    progressItem(label, num, key) {
        let cls = 'rr-prog-item';
        if (num < this.setupStep) {
            cls += ' rr-prog-done';
        } else if (num === this.setupStep) {
            cls += ' rr-prog-current';
        }
        return { key: key + 'pg' + num, num: String(num), label, cls, current: num === this.setupStep ? 'step' : null, aria: 'Step ' + num + ': ' + label };
    }

    step(s, num, key) {
        const g = this.gitlab;
        // With a known provider, its lines join the step's list (no provider tabs).
        const lead = (s.items || []).map((t) => t.replace(/\s*Pick your provider:$/, '')).filter((t) => t);
        const own = s.providers && this.providerKnown ? lead.concat(s.providers[this.provider] || []) : s.items;
        return {
            key,
            num: String(num),
            title: s.title,
            who: s.who,
            where: s.where ? plain(s.where, g) : null,
            goal: s.goal ? rich(s.goal, key + 'g', g) : null,
            check: s.check ? rich(s.check, key + 'ok', g) : null,
            problems: (s.problems || []).map((pr, i) => ({
                key: key + 'pr' + i,
                see: rich(pr[0], key + 'pr' + i + 's', g),
                fix: rich(pr[1], key + 'pr' + i + 'f', g)
            })),
            hasProblems: Array.isArray(s.problems) && s.problems.length > 0,
            links: this.links(s.links, key),
            hasLinks: this.links(s.links, key).length > 0,
            items: (own || []).map((t, i) => rich(t, key + 'i' + i, g)),
            hasItems: Array.isArray(own),
            paras: (s.text || []).map((t, i) => rich(t, key + 'p' + i, g)),
            tabs: s.providers ? PROVIDERS.map((p) => ({
                key: key + p.value,
                value: p.value,
                label: p.label,
                items: (s.providers[p.value] || []).map((t, i) => rich(t, key + p.value + i, p.value === 'GitLab'))
            })) : [],
            hasTabs: !!s.providers && !this.providerKnown,
            shot: s.shot ? this.shot(s.shot, key + 'shot') : null
        };
    }

    repoTabs(b, key) {
        return PROVIDERS.map((p) => ({
            key: key + p.value,
            value: p.value,
            label: p.label,
            tree: this.repoName ? b.providers[p.value].tree.replace('<repository>/', this.repoName + '/') : b.providers[p.value].tree,
            rows: b.providers[p.value].rows.map((r, i) => ({
                key: key + p.value + 'r' + i,
                cells: r.map((c, j) => rich(c, key + p.value + 'r' + i + 'c' + j, p.value === 'GitLab'))
            }))
        }));
    }

    /** A screenshot (RLY_Guide_Shots, jpg) or an annotated drawing (RLY_Guide_Setup, svg). */
    shot(s, key) {
        const url = s.ill ? SETUP_PICS + '/' + s.ill + '.svg' : SHOTS + '/' + s.name + '.jpg';
        return { key, name: s.ill || s.name, cap: s.cap, alt: s.alt || s.cap, url, label: 'Open larger: ' + s.cap };
    }

    // ---------- events ----------

    handleNav(event) {
        this.navigated = true;
        this.current = event.currentTarget.dataset.name;
        this.zoom = undefined;
        this.loadFilesIfShown();
    }

    /**
     * A button that opens a section (the setup checklist's Open, the Next buttons, links inside steps): another section opens
     * from its top; the section already on screen scrolls to its first step instead, so Open always visibly goes there.
     */
    handleLink(event) {
        if (event.currentTarget.dataset.name === this.section.key) {
            this.goToFirstStep();
            return;
        }
        this.handleNav(event);
        this.scrollTop = true;
    }

    /** The section on screen: scrolls to its first numbered step (or the first part after the checklist), focuses its heading and highlights it. */
    goToFirstStep() {
        const main = this.template.querySelector('.rr-main');
        if (!main) {
            return;
        }
        let target = main.querySelector('.rr-stp');
        if (!target) {
            const blocks = Array.from(main.querySelectorAll('.rr-block'));
            const at = blocks.findIndex((el) => !!el.querySelector('.rr-cklist'));
            target = blocks[at + 1] || blocks[0] || main;
        }
        if (target.scrollIntoView) {
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
        const heading = target.querySelector('.rr-h3') || target;
        if (heading.focus) {
            heading.focus({ preventScroll: true });
        }
        target.classList.remove('rr-flash');
        target.addEventListener('animationend', () => target.classList.remove('rr-flash'), { once: true });
        target.classList.add('rr-flash');
    }

    /** Ticks or unticks a setup stage (kept in this browser). */
    handleCheck(event) {
        const to = event.target.dataset.name;
        this.setupDone = { ...this.setupDone, [to]: event.target.checked === true };
        writeDone(this.setupDone);
    }

    toggleOtherFiles() {
        this.showOtherFiles = !this.showOtherFiles;
    }

    /** Updating the files (pull request or commit) lives on the Pipeline tab, next to the Git connection. */
    openPipelineTab() {
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: PIPELINE_TAB } });
    }

    handleProgress(event) {
        const num = Number(event.currentTarget.dataset.num);
        this.setupStep = num;
        const target = this.template.querySelector('[data-step="' + num + '"]');
        if (target) {
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    openShot(event) {
        const { url, cap, alt } = event.currentTarget.dataset;
        this.zoom = { url, cap, alt: alt || cap };
        this.focusClose = true;
    }

    closeShot() {
        this.zoom = undefined;
    }

    handleModalKey(event) {
        if (event.key === 'Escape') {
            this.closeShot();
        }
    }
}
