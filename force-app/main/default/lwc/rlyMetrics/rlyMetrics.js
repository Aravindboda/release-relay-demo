import { LightningElement } from 'lwc';
import options from '@salesforce/apex/RlyMetricsController.options';
import metrics from '@salesforce/apex/RlyMetricsController.metrics';
import checkReasons from '@salesforce/apex/RlyMetricsController.checkReasons';
import { CHART, barsOf, csvOf, formatValue, hbarsOf, mergeBars, trendOf } from './metricsHelpers';
import { errorText } from 'c/rlyShared';

const PERIOD_LABELS = { 30: '30 days', 90: '90 days', 180: '6 months', 365: '12 months' };
const ALL = '';
/** Releases read per call for "why checks fail" (RlyMetricsChecks.MAX_PER_CALL). */
const REASONS_PER_CALL = 10;
const DORA_KEYS = ['deploys', 'leadTime', 'failureRate', 'restore'];

/**
 * Metrics tab (build 42): the four DORA measures (deploys, lead time, change failure rate, time to restore) plus approval
 * wait and checks failing, for one org (or every org), one developer org (or all) and the last 30, 90, 180 or 365 days,
 * each tile against the period before, a bar chart per measure (weeks up to 90 days, months beyond), why checks fail and
 * the files that conflict most (read ten releases a call, the page joins the parts) and a CSV of every number. Read only.
 */
export default class RlyMetrics extends LightningElement {
    orgs = [];
    devOrgs = [];
    orgId = ALL;
    devOrgId = ALL;
    days = 90;
    periods = [30, 90, 180, 365];
    data;
    loading = false;
    error;
    reasons = [];
    files = [];
    reasonsRead = 0;
    reasonsTotal = 0;
    reasonsError;
    /** Bumped on every load: an older load's parts are dropped. */
    loadId = 0;
    csvHref;
    csvName;
    clickCsv = false;

    async connectedCallback() {
        try {
            const o = await options();
            this.orgs = o.orgs || [];
            this.devOrgs = o.devOrgs || [];
            this.orgId = o.defaultOrgId || ALL;
            this.periods = o.periods && o.periods.length ? o.periods : this.periods;
        } catch (e) {
            this.error = errorText(e);
        }
        this.load();
    }

    // ---------- filters ----------

    get orgOptions() { return [{ label: 'All orgs', value: ALL }].concat(this.orgs.map((o) => ({ label: o.name, value: o.id }))); }
    get devOrgOptions() { return [{ label: 'All developer orgs', value: ALL }].concat(this.devOrgs.map((o) => ({ label: o.name, value: o.id }))); }
    get periodButtons() {
        return this.periods.map((d) => ({
            value: String(d), label: PERIOD_LABELS[d] || d + ' days',
            cls: 'rr-seg' + (d === this.days ? ' rr-seg-on' : ''), pressed: d === this.days ? 'true' : 'false'
        }));
    }
    get orgName() {
        const o = this.orgs.find((x) => x.id === this.orgId);
        return o ? o.name : 'every org';
    }
    get filterText() {
        const dev = this.devOrgs.find((x) => x.id === this.devOrgId);
        return this.orgName + ' · ' + (dev ? dev.name : 'all developer orgs') + ' · last ' + (PERIOD_LABELS[this.days] || this.days + ' days');
    }

    handleOrg(event) {
        this.orgId = event.detail.value;
        this.load();
    }
    handleDevOrg(event) {
        this.devOrgId = event.detail.value;
        this.load();
    }
    handlePeriod(event) {
        this.days = Number(event.currentTarget.dataset.value);
        this.load();
    }
    refresh() {
        this.load();
    }

    // ---------- loading ----------

    async load() {
        this.loadId += 1;
        const id = this.loadId;
        this.loading = true;
        this.error = undefined;
        this.reasons = [];
        this.files = [];
        this.reasonsRead = 0;
        this.reasonsTotal = 0;
        this.reasonsError = undefined;
        try {
            const m = await metrics({ filterJson: JSON.stringify({ orgId: this.orgId || null, devOrgId: this.devOrgId || null, days: this.days }) });
            if (id !== this.loadId) {
                return;
            }
            this.data = m;
            this.loading = false;
            this.readReasons(id, m.failedReleaseIds || []);
        } catch (e) {
            if (id === this.loadId) {
                this.error = errorText(e);
                this.loading = false;
            }
        }
    }

    /** "Why checks fail": ten releases a call, joined here; a newer load stops this one. */
    async readReasons(id, ids) {
        this.reasonsTotal = ids.length;
        for (let i = 0; i < ids.length; i += REASONS_PER_CALL) {
            try {
                // eslint-disable-next-line no-await-in-loop
                const part = await checkReasons({ releaseIds: ids.slice(i, i + REASONS_PER_CALL) });
                if (id !== this.loadId) {
                    return;
                }
                this.reasons = mergeBars(this.reasons, part.reasons);
                this.files = mergeBars(this.files, part.files);
                this.reasonsRead = Math.min(ids.length, i + REASONS_PER_CALL);
            } catch (e) {
                if (id === this.loadId) {
                    this.reasonsError = errorText(e);
                }
                return;
            }
        }
    }

    // ---------- tiles and charts ----------

    get hasData() { return !!this.data && !this.error; }
    get showSpinner() { return this.loading && !this.data; }
    get busyText() { return this.loading ? 'Reading…' : ''; }
    get truncated() { return !!this.data && this.data.truncated; }

    get tiles() {
        const days = this.days;
        return ((this.data && this.data.tiles) || []).map((t) => {
            const trend = trendOf(t, days);
            return {
                key: t.key, label: t.label, dora: t.dora,
                value: formatValue(t.value, t.unit),
                detail: t.detail || '',
                trend: trend.text,
                trendCls: 'rr-trend rr-' + trend.tone
            };
        });
    }

    get charts() {
        const tiles = new Map(((this.data && this.data.tiles) || []).map((t) => [t.key, t]));
        const order = DORA_KEYS.concat(['approvalWait', 'checksFailing']);
        return ((this.data && this.data.series) || [])
            .slice()
            .sort((a, b) => order.indexOf(a.key) - order.indexOf(b.key))
            .map((s) => {
                const t = tiles.get(s.key);
                const bars = barsOf(s);
                return {
                    key: s.key,
                    title: s.label + ' · ' + this.orgName + ' · per ' + (this.data.byWeek ? 'week' : 'month'),
                    note: t && t.dora ? 'DORA' : '',
                    bars,
                    empty: !bars.some((b) => b.valueText),
                    viewBox: '0 0 ' + CHART.width + ' ' + CHART.height,
                    baseY: CHART.height - CHART.bottom,
                    baseX2: CHART.width - CHART.right,
                    ariaLabel: s.label + ' per ' + (this.data.byWeek ? 'week' : 'month') + ': '
                        + bars.filter((b) => b.valueText).map((b) => b.title).join('; ')
                };
            });
    }

    get reasonBars() {
        const scan = this.data && this.data.scanFailures ? [{ label: 'Code scan', value: this.data.scanFailures }] : [];
        return hbarsOf(mergeBars(this.reasons, scan), 8);
    }
    get fileBars() { return hbarsOf(this.files, 8); }
    get hasReasons() { return this.reasonBars.length > 0; }
    get hasFiles() { return this.fileBars.length > 0; }
    get reasonsProgress() {
        if (this.reasonsTotal === 0) {
            return '';
        }
        return this.reasonsRead < this.reasonsTotal
            ? 'Reading the failed checks: ' + this.reasonsRead + ' of ' + this.reasonsTotal + '…'
            : 'From the last ' + this.reasonsTotal + (this.reasonsTotal === 1 ? ' failed check' : ' failed checks') + ' (each release\'s latest result).';
    }
    get noReasons() { return !!this.data && !this.hasReasons && this.reasonsTotal === 0; }

    // ---------- CSV ----------

    downloadCsv() {
        if (!this.data) {
            return;
        }
        const csv = csvOf(this.data, this.reasonBars, this.fileBars, this.filterText);
        const today = new Date();
        const pad = (n) => String(n).padStart(2, '0');
        this.csvName = 'release-metrics-' + today.getFullYear() + '-' + pad(today.getMonth() + 1) + '-' + pad(today.getDate()) + '.csv';
        this.csvHref = 'data:text/csv;charset=utf-8,' + encodeURIComponent('﻿' + csv);
        this.clickCsv = true;
    }

    /** Starts the download once the link is drawn; the link stays, in case the browser asks first. */
    renderedCallback() {
        if (!this.clickCsv) {
            return;
        }
        const link = this.template.querySelector('a.rr-csv');
        if (link) {
            this.clickCsv = false;
            link.click();
        }
    }
}
