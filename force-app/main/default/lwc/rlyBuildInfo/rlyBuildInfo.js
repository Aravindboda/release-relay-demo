import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import read from '@salesforce/apex/RlyBuildInfo.read';
import BUILD_DATA from './buildData';

/** Salesforce counts most custom object records as 2 KB. */
const KB_PER_RECORD = 2;
/** Org limit for Apex code (characters, non-test classes, without comments). */
const APEX_CHAR_LIMIT = 6000000;
/** RlyBuildInfo.COUNT_CAP: counts stop here. */
const COUNT_CAP = 7000;

const SECTIONS = [
    { key: 'what', title: '1 · What it does', open: true },
    { key: 'apex', title: '2 · Apex by area', open: true },
    { key: 'lwc', title: '3 · Lightning components', open: false },
    { key: 'tests', title: '4 · Tests', open: true },
    { key: 'resources', title: '5 · Resources', open: true },
    { key: 'model', title: '6 · Data model and access', open: false },
    { key: 'manual', title: '7 · Not in the package', open: false }
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

export default class RlyBuildInfo extends LightningElement {
    data = BUILD_DATA;
    live;
    loading = false;
    error;
    selectedArea = BUILD_DATA.areas.length ? BUILD_DATA.areas[0].name : null;
    openState = SECTIONS.reduce((m, s) => ({ ...m, [s.key]: s.open }), {});

    connectedCallback() {
        this.load();
    }

    load() {
        this.loading = true;
        this.error = undefined;
        read()
            .then((result) => {
                this.live = result;
            })
            .catch((e) => {
                this.live = undefined;
                this.error = 'Live figures could not be read: ' + errorText(e) + ' The figures below come from the package inventory.';
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
    get title() { return this.appName + ' · What\'s built'; }
    get buildText() { return 'Build ' + this.data.build; }
    get kicker() { return 'Package inventory of ' + this.data.generated; }
    get headFacts() {
        const t = this.data.totals;
        return [
            { key: 'apex', text: plural(t.apexClasses, 'Apex class', 'Apex classes') },
            { key: 'lwc', text: plural(t.lwcBundles, 'component', 'components') },
            { key: 'tests', text: plural(this.data.tests.classes.length, 'test class', 'test classes') },
            { key: 'methods', text: plural(this.data.tests.methodTotal, 'test method', 'test methods') },
            { key: 'async', text: 'No async Apex' }
        ];
    }

    // ---------- folding sections (like the Pipeline tab) ----------

    get folds() {
        const out = {};
        SECTIONS.forEach((s) => {
            const open = this.openState[s.key] === true;
            out[s.key] = {
                open,
                expanded: open ? 'true' : 'false',
                title: s.title,
                headCls: open ? 'rr-sh rr-sh-open' : 'rr-sh',
                chevCls: open ? 'rr-chev rr-chev-open' : 'rr-chev',
                summary: this.summaryOf(s.key)
            };
        });
        return out;
    }

    summaryOf(key) {
        const t = this.data.totals;
        const summaries = {
            what: plural(this.data.features.length, 'feature', 'features') + ', ' + plural(this.data.principles.length, 'design rule', 'design rules'),
            apex: fmt(t.apexLinesNonTest) + ' lines of code and ' + fmt(t.apexLinesTest) + ' lines of tests in ' + plural(this.data.areas.length, 'area', 'areas'),
            lwc: plural(this.data.lwc.length, 'component', 'components') + ', ' + fmt(t.lwcLines) + ' lines',
            tests: plural(this.data.tests.classes.length, 'test class', 'test classes') + ', ' + plural(this.data.tests.methodTotal, 'method', 'methods'),
            resources: this.apexMeter.pctText + ' of the Apex limit, ' + (this.live ? this.recordsTotalText + ' records' : 'records not read yet') + ', no async Apex',
            model: plural(this.data.objects.length, 'object', 'objects') + ', ' + plural(this.data.permissionSets.length, 'permission set', 'permission sets'),
            manual: plural(this.data.manualSetup.length, 'set-up step', 'set-up steps') + ' done by hand'
        };
        return summaries[key];
    }

    handleFold(event) {
        const key = event.currentTarget.dataset.key;
        this.openState = { ...this.openState, [key]: !this.openState[key] };
    }

    // ---------- 1 · what it does ----------

    get features() { return this.data.features; }
    get principles() {
        return this.data.principles.map((p, i) => ({ ...p, key: 'p' + i }));
    }

    // ---------- 2 · Apex by area ----------

    get areaRows() {
        const max = this.data.areas.reduce((m, a) => Math.max(m, a.nonTestLines + a.testLines), 0);
        return this.data.areas.map((a) => {
            const on = a.name === this.selectedArea;
            const nonP = pct(a.nonTestLines, max);
            const testP = pct(a.testLines, max);
            return {
                name: a.name,
                countText: plural(a.classes.length, 'class', 'classes'),
                linesText: fmt(a.nonTestLines) + ' + ' + fmt(a.testLines),
                nonW: width(nonP),
                testW: width(testP),
                cls: on ? 'rr-bar-row rr-bar-on' : 'rr-bar-row',
                pressed: on ? 'true' : 'false',
                label: a.name + ': ' + fmt(a.nonTestLines) + ' lines of code, ' + fmt(a.testLines) + ' lines of tests. Show its classes.'
            };
        });
    }

    get scaleText() {
        const max = this.data.areas.reduce((m, a) => Math.max(m, a.nonTestLines + a.testLines), 0);
        return 'Bar length: non-blank lines, longest ' + fmt(max);
    }

    pickArea(event) {
        this.selectedArea = event.currentTarget.dataset.area;
    }

    get area() {
        return this.data.areas.find((a) => a.name === this.selectedArea);
    }

    get areaTitle() {
        const a = this.area;
        return a ? a.name + ' · ' + plural(a.classes.length, 'class', 'classes') : '';
    }

    get areaClasses() {
        const a = this.area;
        if (!a) {
            return [];
        }
        return a.classes.map((c) => ({
            ...c,
            linesText: fmt(c.lines),
            kindCls: c.isTest ? 'rr-pill rr-pill-none' : 'rr-pill rr-pill-info'
        }));
    }

    // ---------- 3 · components ----------

    get components() {
        return this.data.lwc.map((b) => ({ ...b, linesText: fmt(b.lines) }));
    }

    // ---------- 4 · tests ----------

    get testRows() {
        return this.data.tests.classes.map((c) => ({ ...c, methodsText: fmt(c.methods) }));
    }
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

    // ---------- 5 · resources ----------

    get isLive() { return !!this.live; }
    get sourceText() {
        if (this.loading && !this.live) {
            return 'Reading this org…';
        }
        return this.live ? 'Live from this org' : 'From the package inventory';
    }

    /** Non-test Apex characters: live classes minus the test classes the inventory lists. */
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
    get asyncNote() { return 'Release Relay jobs in the last day. None by design: a release moves when a page reads it or Slack posts.'; }

    get resourceBytes() {
        if (this.live && this.live.resources && this.live.resources.length) {
            return this.live.resources.reduce((s, r) => s + (r.bytes || 0), 0);
        }
        return this.data.staticResourceBytes;
    }
    get resourceCount() {
        return this.live && this.live.resources && this.live.resources.length ? this.live.resources.length : this.data.staticResources.length;
    }
    get resourceText() { return bytesText(this.resourceBytes); }
    get resourceNote() { return plural(this.resourceCount, 'static resource', 'static resources') + ' (Guide pictures and pipeline files).'; }

    get codeChangedText() {
        if (!this.live || !this.live.codeChangedOn) {
            return '';
        }
        return 'Release Relay code last deployed ' + new Date(this.live.codeChangedOn).toLocaleString([], { year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
    }

    get callouts() { return this.data.callouts; }
    get calloutNote() { return this.data.calloutNote; }
    get storageRows() { return this.data.storage; }

    // ---------- 6 · data model and access ----------

    get objects() {
        return this.data.objects.map((o) => ({
            ...o,
            fieldsText: fmt(o.fieldCount),
            fieldNames: o.fields.map((f) => f.name).join(', ')
        }));
    }
    get phase1Text() { return this.data.phase1.join('; '); }
    get permissionSets() { return this.data.permissionSets; }
    get credentials() { return this.data.credentials; }
    get customPermissions() { return this.data.customPermissions.map((c) => c.name).join(', '); }
    get staticResources() {
        return this.data.staticResources.map((s) => ({ ...s, sizeText: bytesText(s.bytes) }));
    }

    // ---------- 7 · not in the package ----------

    get manualSetup() {
        return this.data.manualSetup.map((text, i) => ({ key: 'm' + i, no: i + 1, text }));
    }
}
