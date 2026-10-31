import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement } from 'lwc';
import IS_ADMIN from '@salesforce/customPermission/RLY_Admin';
import SHOTS from '@salesforce/resourceUrl/RLY_Guide_Shots';
import getSetup from '@salesforce/apex/RlyRouteController.getSetup';
import SECTIONS, { GROUPS, PROVIDERS } from './guideContent';

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

/** The Release Relay guide: a left navigation (Start here, Daily use, Reference) and the chosen section on the right. */
export default class RlyReleaseGuide extends LightningElement {
    /** The app's name, from Custom Label RLY_App_Name, so each owner can rename it. */
    get appName() { return APP_NAME; }
    current = IS_ADMIN ? 'setup' : 'how';
    provider = 'GitHub';
    repository = '';
    setupStep = 1;
    zoom;
    focusClose = false;

    connectedCallback() {
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
            isShots: b.type === 'shots'
        };
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

    shot(s, key) {
        return { key, name: s.name, cap: s.cap, url: SHOTS + '/' + s.name + '.jpg', label: 'Open larger: ' + s.cap };
    }

    // ---------- events ----------

    handleNav(event) {
        this.current = event.currentTarget.dataset.name;
        this.zoom = undefined;
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
        const { url, cap } = event.currentTarget.dataset;
        this.zoom = { url, cap };
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
