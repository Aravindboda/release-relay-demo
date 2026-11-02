import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import read from '@salesforce/apex/RlyBuildInfo.read';
import readCounts from '@salesforce/apex/RlyBuildInfo.counts';
import BUILD_DATA from './buildData';
import { highlightParts, matchesSearch, searchTerm } from 'c/rlyListSearch';

/**
 * "What's built" as a technical document (build 30): numbered Contents (sticky; a dropdown at 480px and below),
 * breadcrumb with Prev / Next, exactly one section open (Expand all opens every one), search across the sections,
 * Print / PDF (opens everything, then window.print()). Prose and field tables come from the generated buildData.js;
 * the counts are read live (RlyBuildInfo.counts, cacheable) where cheap, with the generated figures as the fallback.
 */

/** Salesforce counts most custom object records as 2 KB. */
const KB_PER_RECORD = 2;
/** Org limit for Apex code (characters, non-test classes, without comments). */
const APEX_CHAR_LIMIT = 6000000;
/** RlyBuildInfo.COUNT_CAP: counts stop here. */
const COUNT_CAP = 7000;
const PS_COLUMNS = ['RLY_Admin', 'RLY_Approver', 'RLY_Deploy_Team', 'RLY_Developer'];

const SECTIONS = [
    { key: 'overview', num: '1', title: 'Overview' },
    { key: 'architecture', num: '2', title: 'Architecture' },
    { key: 'model', num: '3', title: 'Data model' },
    { key: 'security', num: '4', title: 'Security & access' },
    { key: 'apex', num: '5', title: 'Apex' },
    { key: 'lwc', num: '6', title: 'Lightning components & tabs' },
    { key: 'pipeline', num: '7', title: 'Pipeline files' },
    { key: 'limits', num: '8', title: 'Limits & resources' },
    { key: 'tests', num: '9', title: 'Tests to run' },
    { key: 'manual', num: '10', title: 'Not in the package' },
    { key: 'history', num: '11', title: 'Build history' }
];

const FIXED_SUBS = {
    overview: [['1.1', 'Counts'], ['1.2', 'What it does'], ['1.3', 'Design rules']],
    architecture: [['2.1', 'System'], ['2.2', 'Flow of one release']],
    security: [['4.1', 'Permission sets'], ['4.2', 'Object and tab access'], ['4.3', 'Custom permissions'], ['4.4', 'Who can do what'], ['4.5', 'Credentials']],
    lwc: [['6.1', 'Components'], ['6.2', 'Tabs']],
    limits: [['8.1', 'Use in this org'], ['8.2', 'Callouts per step'], ['8.3', 'Records per release']]
};

const FIELD_FILTERS = [
    { key: 'all', label: 'All' },
    { key: 'lookup', label: 'Lookups' },
    { key: 'picklist', label: 'Picklists' },
    { key: 'required', label: 'Required' }
];

function fmt(n) {
    return Number(n || 0).toLocaleString('en-US');
}

function plural(n, one, many) {
    return fmt(n) + ' ' + (n === 1 ? one : many);
}

function pct(part, whole) {
    if (!whole) {
        return 0;
    }
    return Math.max(0, Math.min(100, (part / whole) * 100));
}

function width(p) {
    return p.toFixed(2) + '%';
}

function pctText(p) {
    if (p > 0 && p < 0.1) {
        return '< 0.1%';
    }
    return p.toFixed(1) + '%';
}

function sizeText(kb) {
    if (kb >= 1024) {
        return (kb / 1024).toFixed(1) + ' MB';
    }
    return fmt(Math.round(kb)) + ' KB';
}

function bytesText(bytes) {
    return sizeText((bytes || 0) / 1024);
}

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function meterCls(p) {
    if (p >= 90) {
        return 'rr-meter-fill rr-meter-bad';
    }
    return p >= 70 ? 'rr-meter-fill rr-meter-warn' : 'rr-meter-fill';
}

function isNum(v) {
    return v !== undefined && v !== null && !Number.isNaN(Number(v));
}

/** A live count with the generated figure as fallback; hint when they differ. */
function liveOr(liveValue, generated) {
    if (!isNum(liveValue)) {
        return { value: generated, live: false, hint: '' };
    }
    const n = Number(liveValue);
    return { value: n, live: true, hint: n !== generated ? 'generated ' + fmt(generated) : '' };
}

function fieldSearchValues(f) {
    return [f.name, f.label, f.type, f.description, f.allValues, f.values, f.flags];
}

export default class RlyBuildInfo extends LightningElement {
    data = BUILD_DATA;
    live;
    liveCounts;
    loading = false;
    error;

    /** The one open section (null: all closed). */
    openKey = 'overview';
    /** Expand all: every section open. */
    allOpen = false;
    /** The sub-entry in view (breadcrumb, Contents). */
    subKey = '';
    openObject = 'RLY_Release__c';
    openArea = BUILD_DATA.apexAreas.length ? BUILD_DATA.apexAreas[0].name : '';
    openPs = 'RLY_Admin';
    fieldFilter = 'all';
    term = '';
    printing = false;
    pendingPrint = false;
    pendingScroll = '';
    /** Bumped with every scroll request so the template renders again and renderedCallback scrolls. */
    renderTick = 0;

    connectedCallback() {
        this.load();
    }

    renderedCallback() {
        if (this.pendingPrint) {
            this.pendingPrint = false;
            window.print();
            this.printing = false;
            return;
        }
        if (this.pendingScroll) {
            const el = this.template.querySelector('[data-anchor="' + this.pendingScroll + '"]');
            this.pendingScroll = '';
            if (el && el.scrollIntoView) {
                el.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }
        }
    }

    load() {
        this.loading = true;
        this.error = undefined;
        readCounts()
            .then((result) => {
                this.liveCounts = result;
            })
            .catch(() => {
                this.liveCounts = undefined;
            });
        read()
            .then((result) => {
                this.live = result;
            })
            .catch((e) => {
                this.live = undefined;
                this.error = 'Live figures could not be read: ' + errorText(e) + ' The figures below are the generated ones.';
            })
            .finally(() => {
                this.loading = false;
            });
    }

    reload() {
        this.load();
    }

    // ---------- header ----------

    get appName() { return APP_NAME || 'Release Relay'; }
    get subtitle() {
        return 'Technical reference · build ' + this.data.build + ' · ' + (this.liveCounts ? 'counts read live from the org' : 'generated ' + this.data.generated);
    }
    get readText() {
        const when = this.liveCounts && this.liveCounts.readOn
            ? new Date(this.liveCounts.readOn).toLocaleString([], { year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })
            : '';
        return 'Build ' + this.data.build + (when ? ' · read ' + when : ' · generated ' + this.data.generated);
    }

    // ---------- counts (live where cheap) ----------

    get counts() {
        const g = this.data.counts;
        const lc = this.liveCounts || {};
        const resBytes = isNum(lc.staticResources) ? lc.staticResourceBytes : g.staticResourceBytes;
        return {
            apex: liveOr(lc.apexClasses, g.apexClasses),
            fields: liveOr(lc.customFields, g.fields),
            tabs: liveOr(lc.tabs, g.tabs),
            ps: liveOr(lc.permissionSets, g.permissionSets),
            cp: liveOr(lc.customPermissions, g.customPermissions),
            res: liveOr(lc.staticResources, g.staticResources),
            resBytes
        };
    }

    get tiles() {
        const g = this.data.counts;
        const c = this.counts;
        const objFields = (name) => {
            const o = this.data.objects.find((x) => x.name === name);
            const live = this.liveCounts && this.liveCounts.fieldsByObject ? this.liveCounts.fieldsByObject[name] : undefined;
            return isNum(live) ? live : (o ? o.fields.length : 0);
        };
        const psNames = this.data.permissionSets.map((p) => p.label.replace('Release Relay ', '')).join(' · ');
        const cpNames = this.data.customPermissions.map((p) => p.name).join(' · ');
        const tile = (key, label, v, sub, cls) => ({
            key, label, value: fmt(v.value), sub, hint: v.hint, hasHint: !!v.hint,
            live: v.live, cls: 'rr-tile ' + (cls || 'rr-tile-plain'), title: v.live ? 'Read live from this org' : 'Generated with the package'
        });
        return [
            tile('obj', 'Custom objects', { value: g.objects, live: false, hint: '' }, '+ ' + plural(g.userFields, 'field', 'fields') + ' on User · RLY_Archive_Run__c since build 29', 'rr-tile-blue'),
            tile('fld', 'Custom fields', c.fields, fmt(objFields('RLY_Release__c')) + ' on RLY_Release__c · ' + fmt(objFields('RLY_Org__c')) + ' on RLY_Org__c', 'rr-tile-blue'),
            tile('apex', 'Apex classes', c.apex, fmt(g.apexNonTest) + ' classes · ' + fmt(g.testClasses) + ' tests · ' + fmt(g.testHelpers) + ' test helpers', 'rr-tile-blue'),
            tile('tests', 'Test classes', { value: g.testClasses, live: false, hint: '' }, fmt(g.testMethods) + ' test methods · RunSpecifiedTests'),
            tile('lwc', 'Lightning components', { value: g.lwc, live: false, hint: '' }, fmt(g.lwcOnTabs) + ' on tabs · ' + fmt(g.lwc - g.lwcOnTabs) + ' inside pages'),
            tile('tabs', 'Tabs', c.tabs, '1 app · ' + this.appName),
            tile('ps', 'Permission sets', c.ps, psNames, 'rr-tile-good'),
            tile('cp', 'Custom permissions', c.cp, cpNames, 'rr-tile-good'),
            tile('res', 'Static resources', c.res, bytesText(c.resBytes) + ' · ' + fmt(g.pipelineFiles) + ' pipeline files')
        ];
    }

    get overviewFacts() {
        const a = this.data.apexCharacters;
        return [
            { key: 'hub', label: 'Hub', text: 'Production only; a sandbox copy shows Set up only (RlyHubGuard).' },
            { key: 'async', label: 'Async Apex', text: 'None: no @future, Queueable, Batch, Schedulable or triggers. The nightly archive is a REST call from the Git pipeline.' },
            { key: 'size', label: 'Apex size', text: fmt(a.nonTestWithoutComments) + ' characters of non-test code without comments (' + pctText(pct(a.nonTestWithoutComments, APEX_CHAR_LIMIT)) + ' of the 6 MB limit); live figure under Limits & resources.' },
            { key: 'cred', label: 'Credentials', text: '1 Named Credential (RLY_Slack) · 1 External Credential · the Git credential is set up by hand.' }
        ];
    }

    get features() { return this.data.features.filter((f) => matchesSearch([f.title, f.text], this.term)); }
    get principles() { return this.data.principles.filter((p) => matchesSearch([p.title, p.text], this.term)); }

    // ---------- sections, Contents, breadcrumb ----------

    isOpen(key) {
        return this.printing || this.allOpen || this.openKey === key;
    }

    summaryOf(key) {
        const g = this.data.counts;
        const c = this.counts;
        const map = {
            overview: plural(g.objects, 'object', 'objects') + ' · ' + plural(c.fields.value, 'field', 'fields') + ' · ' + plural(c.apex.value, 'Apex class', 'Apex classes') + ' · ' + fmt(g.lwc) + ' LWCs · ' + plural(c.tabs.value, 'tab', 'tabs') + ' · ' + plural(c.ps.value, 'permission set', 'permission sets') + ' · ' + plural(c.cp.value, 'custom permission', 'custom permissions'),
            architecture: 'Production hub · route developer orgs → stages → production · Git pipeline · Slack',
            model: fmt(g.objects) + ' custom objects + ' + plural(g.userFields, 'field', 'fields') + ' on User · ' + plural(c.fields.value, 'field', 'fields') + ' · ' + plural(g.lookups, 'lookup', 'lookups') + ' · ' + plural(g.masterDetails, 'master-detail', 'master-details'),
            security: plural(c.ps.value, 'permission set', 'permission sets') + ' · ' + plural(c.cp.value, 'custom permission', 'custom permissions') + ' · 1 named + 1 external credential',
            apex: fmt(g.apexNonTest) + ' classes + ' + fmt(g.testClasses) + ' test classes + ' + fmt(g.testHelpers) + ' test helpers · all with sharing',
            lwc: fmt(g.lwc) + ' LWC bundles (' + fmt(g.lwcOnTabs) + ' on tabs) · ' + plural(c.tabs.value, 'tab', 'tabs') + ' · 1 app',
            pipeline: 'GitHub · GitLab · Bitbucket · Azure Repos + shared script · ' + bytesText(g.pipelineBytes),
            limits: 'Callouts per step · records per release · Apex size ' + this.apexMeter.pctText + ' of 6 MB · no async Apex',
            tests: plural(g.testClasses, 'test class', 'test classes') + ' · ' + plural(g.testMethods, 'test method', 'test methods') + ' · RunSpecifiedTests list',
            manual: plural(this.data.manualSetup.length, 'set-up step', 'set-up steps') + ' done by hand (certificate, remote sites, credentials, Slack…)',
            history: 'Build ' + this.data.build + ' · ' + this.data.history[0].text
        };
        return map[key];
    }

    /** Search hits per section (0 when no search). */
    get hits() {
        const q = this.term;
        const out = {};
        if (!q) {
            return out;
        }
        out.overview = this.features.length + this.principles.length;
        out.model = this.data.objects.reduce((s, o) => s + this.objectHits(o), 0);
        out.security = this.permissionSetRows.length + this.cpRows.length + this.whoRows.length;
        out.apex = this.data.apexAreas.reduce((s, a) => s + this.areaClasses(a).length, 0);
        out.lwc = this.lwcRows.length + this.tabRows.length;
        out.pipeline = this.pipelineRows.length;
        out.limits = this.callouts.length + this.storageRows.length;
        out.tests = this.testRows.length;
        out.manual = this.manualSetup.length;
        out.history = this.historyRows.length;
        out.architecture = this.flowRows.length;
        return out;
    }

    get sec() {
        const out = {};
        const hits = this.hits;
        SECTIONS.forEach((s) => {
            const open = this.isOpen(s.key);
            const dim = !!this.term && !hits[s.key];
            out[s.key] = {
                open,
                expanded: open ? 'true' : 'false',
                num: s.num,
                title: s.title,
                summary: this.summaryOf(s.key),
                cls: 'rr-card rr-sec' + (open ? ' rr-sec-open' : '') + (dim ? ' rr-sec-dim' : ''),
                chevCls: open ? 'rr-chev rr-chev-open' : 'rr-chev',
                numCls: open ? 'rr-sn rr-sn-on' : 'rr-sn'
            };
        });
        return out;
    }

    subsOf(key) {
        if (key === 'model') {
            return [{ key: '3.1', title: 'Diagram', mono: false }].concat(this.data.objects.map((o) => ({ key: o.num, title: o.name, mono: true, object: o.name })));
        }
        if (key === 'apex') {
            return this.data.apexAreas.map((a) => ({ key: a.num, title: a.name, mono: false, area: a.name, count: String(a.classes.length) }));
        }
        return (FIXED_SUBS[key] || []).map(([k, title]) => ({ key: k, title, mono: false }));
    }

    countOf(key) {
        const g = this.data.counts;
        const c = this.counts;
        const map = {
            overview: '9 tiles', model: String(this.data.objects.length), security: fmt(c.ps.value) + ' · ' + fmt(c.cp.value),
            apex: fmt(c.apex.value), lwc: fmt(g.lwc) + ' · ' + fmt(c.tabs.value), pipeline: String(g.pipelineFiles),
            tests: fmt(g.testClasses), manual: String(this.data.manualSetup.length), history: String(this.data.history.length)
        };
        return map[key] || '';
    }

    get tocRows() {
        const hits = this.hits;
        return SECTIONS.map((s) => {
            const active = !this.allOpen && this.openKey === s.key;
            const hit = this.term ? hits[s.key] || 0 : null;
            const subs = active ? this.subsOf(s.key).map((x) => ({
                ...x,
                cls: 'rr-ti rr-ti-sub' + (x.key === this.subKey ? ' rr-ti-on2' : ''),
                ttCls: x.mono ? 'rr-tt rr-mono' : 'rr-tt',
                hasCount: !!x.count
            })) : [];
            return {
                key: s.key,
                num: s.num,
                title: s.title,
                count: hit === null ? this.countOf(s.key) : String(hit),
                countCls: hit === null ? 'rr-tc' : (hit ? 'rr-tc rr-tc-hit' : 'rr-tc rr-tc-zero'),
                cls: 'rr-ti' + (active ? ' rr-ti-on' : '') + (hit === 0 ? ' rr-ti-dim' : ''),
                current: active ? 'true' : 'false',
                subs,
                hasSubs: subs.length > 0
            };
        });
    }

    get tocTitle() {
        if (!this.term) {
            return 'Contents';
        }
        const total = Object.values(this.hits).reduce((s, n) => s + n, 0);
        return 'Contents · ' + plural(total, 'hit', 'hits');
    }

    get pickOptions() {
        const none = [{ value: '', label: this.allOpen ? 'All sections' : 'Choose a section', selected: !this.openKey || this.allOpen }];
        return none.concat(SECTIONS.map((s) => ({
            value: s.key,
            label: s.num + ' ' + s.title + (this.term ? ' (' + (this.hits[s.key] || 0) + ')' : ''),
            selected: !this.allOpen && this.openKey === s.key
        })));
    }

    get sectionIndex() {
        return SECTIONS.findIndex((s) => s.key === this.openKey);
    }

    get crumbs() {
        const out = [{ key: 'root', label: "What's built", isLink: true, target: 'root' }];
        const s = SECTIONS[this.sectionIndex];
        if (s && !this.allOpen) {
            out.push({ key: 's', label: s.num + ' ' + s.title, isLink: !!this.subKey, target: s.key });
            if (this.subKey) {
                const sub = this.subsOf(s.key).find((x) => x.key === this.subKey);
                if (sub) {
                    out.push({ key: 'x', label: sub.title, isLink: false, target: '' });
                }
            }
        } else if (this.allOpen) {
            out.push({ key: 'all', label: 'All sections', isLink: false, target: '' });
        }
        return out.map((c, i) => ({ ...c, notFirst: i > 0, cls: c.isLink ? 'rr-crumb-link' : 'rr-crumb-cur' }));
    }

    get positionText() {
        const i = this.sectionIndex;
        return i >= 0 && !this.allOpen ? 'Section ' + (i + 1) + ' of ' + SECTIONS.length : SECTIONS.length + ' sections';
    }
    get prevDisabled() { return !this.allOpen && this.sectionIndex === 0; }
    get nextDisabled() { return !this.allOpen && this.sectionIndex === SECTIONS.length - 1; }

    openSection(key, anchor) {
        this.allOpen = false;
        this.openKey = key;
        this.scrollTo(anchor || 's-' + key);
    }

    scrollTo(anchor) {
        this.pendingScroll = anchor;
        this.renderTick += 1;
    }

    handleHeader(event) {
        const key = event.currentTarget.dataset.key;
        if (this.allOpen) {
            this.allOpen = false;
            this.openKey = key;
            this.subKey = '';
            this.scrollTo('s-' + key);
            return;
        }
        this.subKey = '';
        if (this.openKey === key) {
            this.openKey = null;
            return;
        }
        this.openSection(key);
    }

    handleToc(event) {
        this.subKey = '';
        this.openSection(event.currentTarget.dataset.key);
    }

    handleTocSub(event) {
        const ds = event.currentTarget.dataset;
        this.subKey = ds.sub;
        if (ds.object) {
            this.openObject = ds.object;
            this.fieldFilter = 'all';
        }
        if (ds.area) {
            this.openArea = ds.area;
        }
        this.openSection(ds.key, 'n-' + ds.sub);
    }

    handlePick(event) {
        const key = event.target.value;
        this.subKey = '';
        if (key) {
            this.openSection(key);
        }
    }

    handleCrumb(event) {
        const target = event.currentTarget.dataset.target;
        if (target === 'root') {
            this.subKey = '';
            this.scrollTo('top');
            return;
        }
        this.subKey = '';
        this.openSection(target);
    }

    step(delta) {
        const i = this.allOpen || this.sectionIndex < 0 ? (delta > 0 ? -1 : SECTIONS.length) : this.sectionIndex;
        const next = Math.max(0, Math.min(SECTIONS.length - 1, i + delta));
        this.subKey = '';
        this.openSection(SECTIONS[next].key);
    }

    handlePrev() { this.step(-1); }
    handleNext() { this.step(1); }

    handleTocKey(event) {
        if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') {
            return;
        }
        event.preventDefault();
        this.step(event.key === 'ArrowDown' ? 1 : -1);
    }

    expandAll() {
        this.allOpen = true;
        this.subKey = '';
    }

    collapseAll() {
        this.allOpen = false;
        this.openKey = null;
        this.subKey = '';
    }

    printPdf() {
        this.printing = true;
        this.pendingPrint = true;
    }

    // ---------- search ----------

    handleSearch(event) {
        this.term = searchTerm(event.detail && event.detail.value);
        if (!this.term) {
            return;
        }
        const hits = this.hits;
        const first = SECTIONS.find((s) => hits[s.key] > 0);
        if (first) {
            this.allOpen = false;
            this.openKey = first.key;
            this.subKey = '';
        }
        const obj = this.data.objects.find((o) => this.objectHits(o) > 0);
        if (obj) {
            this.openObject = obj.name;
            this.fieldFilter = 'all';
        }
        const area = this.data.apexAreas.find((a) => this.areaClasses(a).length > 0);
        if (area) {
            this.openArea = area.name;
        }
    }

    get searchTotal() {
        return Object.values(this.hits).reduce((s, n) => s + n, 0);
    }
    get searchShown() { return this.term ? this.searchTotal : undefined; }

    parts(text) {
        return highlightParts(text, this.term);
    }

    // ---------- 2 · architecture ----------

    get flowRows() {
        return this.data.flow.filter((f) => matchesSearch([f.title, f.objects, f.text], this.term));
    }

    // ---------- 3 · data model ----------

    get erText() {
        const n = (name) => {
            const o = this.data.objects.find((x) => x.name === name);
            return o ? o : { fields: [], label: name, lookups: 0, picklists: 0 };
        };
        const line = (name) => n(name).label + ' · ' + plural(n(name).fields.length, 'field', 'fields');
        const rel = n('RLY_Release__c');
        return {
            release: line('RLY_Release__c'),
            releaseSub: plural(rel.lookups, 'lookup', 'lookups') + ' · ' + plural(rel.picklists, 'picklist', 'picklists'),
            releaseFmt: 'REL-{00000} · OWD Read',
            item: line('RLY_Release_Item__c'),
            event: line('RLY_Release_Event__c'),
            step: line('RLY_Manual_Step__c'),
            run: line('RLY_Manual_Step_Run__c'),
            org: line('RLY_Org__c'),
            user: 'standard object · ' + plural(n('User').fields.length, 'field', 'fields'),
            git: plural(n('RLY_Git_Connection__c').fields.length, 'field', 'fields') + ' · 1 per hub · retention (build 29)',
            notif: plural(n('RLY_Notification__c').fields.length, 'field', 'fields') + ' · 1 per channel · Slack',
            archive: plural(n('RLY_Archive_Run__c').fields.length, 'field', 'fields') + ' · 1 per run · build 29'
        };
    }

    objectHits(o) {
        if (!this.term) {
            return 0;
        }
        const own = matchesSearch([o.name, o.label, o.purpose, o.description], this.term) ? 1 : 0;
        return own + o.fields.filter((f) => matchesSearch(fieldSearchValues(f), this.term)).length;
    }

    filteredFields(o) {
        const q = this.term;
        const filter = this.fieldFilter;
        return o.fields.filter((f) => {
            if (filter === 'lookup' && !f.isLookup) {
                return false;
            }
            if (filter === 'picklist' && !f.isPicklist) {
                return false;
            }
            if (filter === 'required' && !f.required) {
                return false;
            }
            return matchesSearch(fieldSearchValues(f), q);
        });
    }

    fieldRows(o) {
        const rows = [];
        let group = null;
        const shown = this.filteredFields(o);
        shown.forEach((f, i) => {
            if (o.grouped && f.group !== group) {
                group = f.group;
                const size = shown.filter((x) => x.group === group).length;
                rows.push({ key: 'g' + i, isGroup: true, group, size: String(size) });
            }
            rows.push({
                key: f.name,
                isGroup: false,
                nameParts: this.parts(f.name),
                label: f.label,
                type: f.type,
                typeCls: f.typeCls,
                length: f.length || '–',
                req: f.required ? '✓' : '',
                values: f.values,
                hasMore: f.more > 0,
                moreText: '+' + f.more,
                allValues: f.allValues || f.values,
                flags: f.flags,
                hasFlags: !!f.flags,
                hasDesc: !!f.description,
                descParts: this.parts(f.description),
                description: f.description,
                isNew: !!f.newIn,
                newText: 'build ' + f.newIn
            });
        });
        return rows;
    }

    get objectCards() {
        const all = this.printing;
        return this.data.objects.map((o) => {
            const open = all || this.openObject === o.name;
            const hits = this.objectHits(o);
            const counts = {
                all: o.fields.length,
                lookup: o.fields.filter((f) => f.isLookup).length,
                picklist: o.fields.filter((f) => f.isPicklist).length,
                required: o.fields.filter((f) => f.required).length
            };
            const fields = open ? this.fieldRows(o) : [];
            const shownCount = fields.filter((r) => !r.isGroup).length;
            return {
                name: o.name,
                num: o.num,
                anchor: 'n-' + o.num,
                label: o.label,
                open,
                expanded: open ? 'true' : 'false',
                cls: 'rr-ocard' + (open ? ' rr-ocard-open' : '') + (this.term && !hits ? ' rr-sec-dim' : ''),
                chevCls: open ? 'rr-chev rr-chev-open' : 'rr-chev',
                summary: this.term
                    ? plural(hits, 'match', 'matches') + ' of ' + plural(o.fields.length, 'field', 'fields')
                    : plural(o.fields.length, 'field', 'fields') + ' · ' + plural(o.lookups, 'lookup', 'lookups') + ' · ' + plural(o.picklists, 'picklist', 'picklists') + ' · ' + o.records,
                isNew: !!o.newIn,
                newText: (o.name === 'User' ? 'Fields added · build ' : 'New · build ') + o.newIn,
                objLabel: o.objLabel + (o.plural ? ' / ' + o.plural : ''),
                recordName: o.recordName,
                sharing: o.sharing,
                records: o.records,
                purpose: o.purpose,
                setupDescription: o.description,
                hasSetupDescription: !!o.description && o.description.slice(0, 30) !== o.purpose.slice(0, 30),
                statsText: plural(o.fields.length, 'field', 'fields') + (o.grouped ? ' · grouped by what they hold' : '') + ' · ' + plural(o.lookups, 'lookup', 'lookups') + ' · ' + plural(o.picklists, 'picklist', 'picklists') + (o.noDescription ? ' · ' + fmt(o.noDescription) + ' without description' : ''),
                chips: FIELD_FILTERS.map((ff) => ({
                    key: ff.key,
                    label: ff.label + ' ' + counts[ff.key],
                    pressed: this.fieldFilter === ff.key ? 'true' : 'false',
                    cls: 'rr-chip' + (this.fieldFilter === ff.key ? ' rr-chip-on' : '')
                })),
                fields,
                noFields: open && shownCount === 0,
                standardNote: o.name === 'User' ? 'Only the Release Relay fields on User are listed.' : 'Standard fields (Id, Name, Owner, Created, Last modified) not listed.'
            };
        });
    }

    toggleObject(event) {
        const name = event.currentTarget.dataset.object;
        this.openObject = this.openObject === name ? '' : name;
        this.fieldFilter = 'all';
        const o = this.data.objects.find((x) => x.name === name);
        this.subKey = this.openObject && o ? o.num : '';
    }

    openObjectByName(name) {
        const o = this.data.objects.find((x) => x.name === name);
        if (!o) {
            return;
        }
        this.openObject = name;
        this.fieldFilter = 'all';
        this.subKey = o.num;
        this.openSection('model', 'n-' + o.num);
    }

    handleDiagramClick(event) {
        this.openObjectByName(event.currentTarget.dataset.object);
    }

    handleDiagramKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.openObjectByName(event.currentTarget.dataset.object);
        }
    }

    pickFieldFilter(event) {
        this.fieldFilter = event.currentTarget.dataset.filter;
    }

    clearSearch() {
        const box = this.template.querySelector('c-rly-search-box');
        if (box) {
            box.clear();
        }
        this.term = '';
    }

    // ---------- 4 · security ----------

    livePs(name) {
        const rows = (this.liveCounts && this.liveCounts.permissionSetCounts) || [];
        return rows.find((r) => r.name === name);
    }

    get permissionSetRows() {
        const q = this.term;
        return this.data.permissionSets
            .filter((p) => matchesSearch([p.name, p.label, p.forWho, p.description, p.cps.join(' '), p.classes.join(' ')], q))
            .map((p) => {
                const l = this.livePs(p.name);
                const open = this.openPs === p.name;
                const access = p.objects.map((o) => ({
                    key: o.object,
                    object: o.object,
                    c: o.c ? '✓' : '–', r: o.r ? '✓' : '–', e: o.e ? '✓' : '–', d: o.d ? '✓' : '–', va: o.va ? '✓' : '–', ma: o.ma ? '✓' : '–'
                }));
                return {
                    name: p.name,
                    xkey: 'x-' + p.name,
                    nameParts: this.parts(p.name),
                    label: p.label,
                    forWho: p.forWho,
                    description: p.description,
                    cps: p.cps.map((c) => ({ key: c, name: c })),
                    hasCps: p.cps.length > 0,
                    classes: fmt(l ? l.classes : p.classes.length),
                    tabs: fmt(l ? l.tabs : p.tabs.length),
                    objects: fmt(l ? l.objects : p.objects.length),
                    fields: fmt(l ? l.fields : p.fieldCount),
                    countTitle: l ? 'Read live from this org' : 'Generated with the package',
                    ext: p.ext || '—',
                    open,
                    expanded: open ? 'true' : 'false',
                    chevCls: open ? 'rr-chev rr-chev-open' : 'rr-chev',
                    access,
                    hasAccess: access.length > 0,
                    tabChips: p.tabs.map((t) => ({ key: t.name, label: t.label })),
                    hasTabs: p.tabs.length > 0,
                    classList: p.classes.join(', ') || 'none',
                    objectsTitle: 'Object access · ' + plural(p.objects.length, 'object', 'objects'),
                    tabsTitle: 'Tabs visible · ' + p.tabs.length,
                    classesTitle: 'Apex classes · ' + p.classes.length,
                    fieldsTitle: 'Fields · ' + p.fieldCount + ' (' + p.fieldsEdit + ' editable)'
                };
            });
    }

    togglePs(event) {
        const name = event.currentTarget.dataset.ps;
        this.openPs = this.openPs === name ? '' : name;
    }

    psByName(name) {
        return this.data.permissionSets.find((p) => p.name === name);
    }

    get accessMatrix() {
        const order = ['RLY_Release__c', 'RLY_Release_Item__c', 'RLY_Release_Event__c', 'RLY_Manual_Step__c', 'RLY_Manual_Step_Run__c', 'RLY_Org__c',
            'RLY_Git_Connection__c', 'RLY_Notification__c', 'RLY_Archive_Run__c', 'UserExternalCredential'];
        return order.map((obj) => ({
            key: obj,
            object: obj,
            cells: PS_COLUMNS.map((ps) => {
                const p = this.psByName(ps);
                const a = p ? p.objects.find((o) => o.object === obj) : null;
                return { key: ps, text: a ? a.code : '–', cls: a ? 'rr-acc' : 'rr-nn' };
            })
        }));
    }

    get tabMatrix() {
        return this.data.tabs.map((t) => ({
            key: t.name,
            label: t.label,
            name: t.name,
            cells: PS_COLUMNS.map((ps) => {
                const p = this.psByName(ps);
                const on = p ? p.tabs.some((x) => x.name === t.name) : false;
                return { key: ps, text: on ? '✓' : '–', cls: on ? 'rr-y' : 'rr-nn' };
            })
        }));
    }

    get cpRows() {
        return this.data.customPermissions
            .filter((c) => matchesSearch([c.name, c.label, c.unlocks, c.checkedIn, c.description], this.term))
            .map((c) => ({ ...c, nameParts: this.parts(c.name) }));
    }

    get whoRows() {
        return this.data.who
            .filter((w) => matchesSearch([w.action, w.enforced], this.term))
            .map((w) => ({
                key: w.key,
                action: w.action,
                enforced: w.enforced,
                cells: w.cells.map((v, i) => ({
                    key: w.key + i,
                    text: v === 'yes' ? '✓' : (v || '–'),
                    cls: v === 'yes' ? 'rr-y' : (v ? 'rr-weak rr-small' : 'rr-nn')
                }))
            }));
    }

    get credentials() { return this.data.credentials; }

    // ---------- 5 · Apex ----------

    areaClasses(a) {
        return a.classes.filter((c) => matchesSearch([c.name, c.purpose, c.aura, c.rest, c.testedByAll], this.term));
    }

    get areaChips() {
        return this.data.apexAreas.map((a) => {
            const n = this.term ? this.areaClasses(a).length : a.classes.length;
            const on = this.openArea === a.name;
            return { key: a.name, label: a.name, count: String(n), pressed: on ? 'true' : 'false', cls: 'rr-chip' + (on ? ' rr-chip-on' : '') };
        });
    }

    get areaCards() {
        return this.data.apexAreas.map((a) => {
            const open = this.printing || this.openArea === a.name;
            const rows = open ? this.areaClasses(a).map((c) => ({
                key: c.name,
                nameParts: this.parts(c.name),
                inner: c.inner,
                lines: fmt(c.lines),
                purpose: c.purpose,
                purposeParts: this.parts(c.purpose),
                hasAura: !!c.aura,
                aura: c.aura,
                hasRest: !!c.rest,
                rest: c.rest,
                isInternal: !c.aura && !c.rest,
                testedBy: c.testedBy,
                testedByAll: c.testedByAll || 'Covered through the classes that call it'
            })) : [];
            return {
                key: a.name,
                num: a.num,
                anchor: 'n-' + a.num,
                name: a.name,
                text: a.text,
                open,
                expanded: open ? 'true' : 'false',
                chevCls: open ? 'rr-chev rr-chev-open' : 'rr-chev',
                cls: 'rr-ocard' + (open ? ' rr-ocard-open' : '') + (this.term && !this.areaClasses(a).length ? ' rr-sec-dim' : ''),
                summary: plural(a.classes.length, 'class', 'classes') + ' · ' + fmt(a.lines) + ' lines · ' + fmt(a.aura) + ' with @AuraEnabled' + (a.rest ? ' · ' + fmt(a.rest) + ' REST' : ''),
                rows,
                noRows: open && rows.length === 0
            };
        });
    }

    get apexSub() {
        const g = this.data.counts;
        return fmt(g.apexNonTest) + ' classes + ' + fmt(g.testClasses) + ' test classes + ' + fmt(g.testHelpers) + ' test helpers · all top-level with sharing · '
            + fmt(g.innerWithout) + ' have a private inner without sharing class · ' + fmt(g.auraMethods) + ' @AuraEnabled methods in ' + fmt(g.auraClasses) + ' classes · '
            + plural(g.restClasses, 'REST endpoint', 'REST endpoints');
    }

    pickArea(event) {
        const name = event.currentTarget.dataset.area;
        const a = this.data.apexAreas.find((x) => x.name === name);
        this.openArea = name;
        this.subKey = a ? a.num : '';
        if (a) {
            this.scrollTo('n-' + a.num);
        }
    }

    toggleArea(event) {
        const name = event.currentTarget.dataset.area;
        this.openArea = this.openArea === name ? '' : name;
        const a = this.data.apexAreas.find((x) => x.name === name);
        this.subKey = this.openArea && a ? a.num : '';
    }

    // ---------- 6 · components and tabs ----------

    get lwcRows() {
        return this.data.lwc
            .filter((b) => matchesSearch([b.name, b.label, b.purpose, b.tab, b.apex], this.term))
            .map((b) => ({ ...b, nameParts: this.parts(b.name), linesText: fmt(b.lines), tabText: b.tab || '—', apexText: b.apex || '—' }));
    }

    get tabRows() {
        return this.data.tabs
            .filter((t) => matchesSearch([t.name, t.label, t.component, t.description], this.term))
            .map((t) => ({ ...t, nameParts: this.parts(t.name) }));
    }

    get lwcNoMatch() { return !!this.term && this.lwcRows.length === 0; }

    // ---------- 7 · pipeline files ----------

    get pipelineRows() {
        return this.data.resources
            .filter((r) => matchesSearch([r.name, r.file, r.text], this.term))
            .map((r) => ({ ...r, nameParts: this.parts(r.name), sizeText: bytesText(r.bytes), kind: r.pipeline ? 'Pipeline' : 'Guide' }));
    }

    // ---------- 8 · limits and resources ----------

    get isLive() { return !!this.live; }
    get sourceText() {
        if (this.loading && !this.live) {
            return 'Reading this org…';
        }
        return this.live ? 'Live from this org' : 'Generated figures';
    }

    /** Non-test Apex characters: live classes minus the test classes the generated data lists. */
    get apexMeter() {
        let used = this.data.apexCharacters.nonTestWithoutComments;
        let tests = this.data.apexCharacters.testClasses;
        if (this.live && this.live.classes) {
            const testNames = new Set(this.data.testClassNames);
            used = 0;
            tests = 0;
            this.live.classes.forEach((c) => {
                if (testNames.has(c.name)) {
                    tests += c.chars || 0;
                } else {
                    used += c.chars || 0;
                }
            });
        }
        const p = pct(used, APEX_CHAR_LIMIT);
        return {
            value: fmt(used),
            of: 'of ' + fmt(APEX_CHAR_LIMIT) + ' characters',
            pctText: pctText(p),
            w: width(p),
            fillCls: meterCls(p),
            note: 'Tests (' + fmt(tests) + ' characters) and comments don\'t count toward the limit.'
        };
    }

    get recordRows() {
        const rows = (this.live && this.live.records) || [];
        return rows.map((r) => ({
            key: r.objectName,
            label: r.label,
            totalText: fmt(r.total) + (r.capped || r.total >= COUNT_CAP ? '+' : ''),
            sizeText: sizeText(r.total * KB_PER_RECORD)
        }));
    }
    get hasRecords() { return this.recordRows.length > 0; }

    get recordsTotal() {
        const rows = (this.live && this.live.records) || [];
        return rows.reduce((s, r) => s + (r.total || 0), 0);
    }
    get recordsCapped() {
        const rows = (this.live && this.live.records) || [];
        return rows.some((r) => r.capped);
    }
    get recordsTotalText() {
        return this.live ? fmt(this.recordsTotal) + (this.recordsCapped ? '+' : '') : '—';
    }
    get storageText() {
        return this.live ? '≈ ' + sizeText(this.recordsTotal * KB_PER_RECORD) : '—';
    }

    usageOf(name) {
        const rows = (this.live && this.live.usage) || [];
        return rows.find((u) => u.name === name);
    }

    get storageMeter() {
        const u = this.usageOf('DataStorageMB');
        if (!u) {
            return { known: false, note: 'Org data storage not read.' };
        }
        const p = pct(u.used, u.maxValue);
        const ours = pct((this.recordsTotal * KB_PER_RECORD) / 1024, u.maxValue);
        return {
            known: true,
            w: width(p),
            fillCls: meterCls(p),
            note: 'Org data storage ' + fmt(u.used) + ' of ' + fmt(u.maxValue) + ' MB used (' + pctText(p) + '); Release Relay about ' + pctText(ours) + '.'
        };
    }

    get apiMeter() {
        const u = this.usageOf('DailyApiRequests');
        if (!u) {
            return { known: false, value: '—', of: 'Not read', w: '0%', fillCls: 'rr-meter-fill', pctText: '' };
        }
        const p = pct(u.used, u.maxValue);
        return { known: true, value: fmt(u.used), of: 'of ' + fmt(u.maxValue) + ' in the last 24 hours (whole org)', w: width(p), fillCls: meterCls(p), pctText: pctText(p) };
    }

    get asyncText() { return fmt(this.live ? this.live.asyncJobs : 0); }
    get asyncNote() { return 'Release Relay jobs in the last day. None by design: a release moves when a page reads it, Slack posts or the pipeline calls back.'; }

    get resourceText() { return bytesText(this.counts.resBytes); }
    get resourceNote() { return plural(this.counts.res.value, 'static resource', 'static resources') + ' (pipeline files and Guide pictures).'; }

    get codeChangedText() {
        if (!this.live || !this.live.codeChangedOn) {
            return '';
        }
        return 'Release Relay code last deployed ' + new Date(this.live.codeChangedOn).toLocaleString([], { year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
    }

    get callouts() { return this.data.callouts.filter((c) => matchesSearch([c.label, c.text], this.term)); }
    get calloutNote() { return this.data.calloutNote; }
    get storageRows() { return this.data.storage.filter((s) => matchesSearch([s.label, s.text], this.term)); }

    // ---------- 9 · tests ----------

    get testRows() {
        return this.data.tests.classes.filter((c) => matchesSearch([c.name, c.area], this.term))
            .map((c) => ({ ...c, nameParts: this.parts(c.name), methodsText: fmt(c.methods) }));
    }
    get testsNoMatch() { return !!this.term && this.testRows.length === 0; }
    get testCount() { return fmt(this.data.tests.classes.length); }
    get methodCount() { return fmt(this.data.tests.methodTotal); }
    get helperCount() { return fmt(this.data.tests.helpers.length); }
    get helperText() { return this.data.tests.helpers.join(', '); }
    get runTests() { return this.data.tests.runSpecifiedTests; }

    copyTests() {
        const text = this.runTests;
        const clip = typeof navigator !== 'undefined' ? navigator.clipboard : null;
        if (!clip || !clip.writeText) {
            this.toast('Select the list and copy it.', 'info');
            return;
        }
        clip.writeText(text)
            .then(() => this.toast('Test list copied: ' + plural(this.data.tests.classes.length, 'class', 'classes'), 'success'))
            .catch(() => this.toast('Select the list and copy it.', 'info'));
    }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: 'RunSpecifiedTests', message, variant }));
    }

    // ---------- 10 · not in the package, 11 · history ----------

    get manualSetup() {
        return this.data.manualSetup
            .map((text, i) => ({ key: 'm' + i, no: String(i + 1), text, parts: this.parts(text) }))
            .filter((m) => matchesSearch([m.text], this.term));
    }

    get historyRows() {
        return this.data.history
            .filter((h) => matchesSearch([h.build, h.text], this.term))
            .map((h, i) => ({ ...h, parts: this.parts(h.text), cls: i === 0 && !this.term ? 'rr-hist rr-hist-now' : 'rr-hist' }));
    }

    get noHits() { return !!this.term && this.searchTotal === 0; }
}
