import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import readMatrix from '@salesforce/apex/RlyOrgPackagesController.matrix';
import checkNow from '@salesforce/apex/RlyOrgPackagesController.checkNow';
import markNotInstalled from '@salesforce/apex/RlyOrgPackagesController.markNotInstalled';
import countInstalled from '@salesforce/apex/RlyOrgPackagesController.countInstalled';
import allowRaising from '@salesforce/apex/RlyOrgPackagesController.allowRaising';
import stopRaising from '@salesforce/apex/RlyOrgPackagesController.stopRaising';
import { errorText, dateTime } from 'c/rlyShared';

const GUIDE_TAB = 'RLY_Relay_Guide';
const GUIDE_SECTION = 'packages';

/** "A", "A and B", "A, B and C". */
function names(list) {
    if (list.length <= 1) {
        return list.join('');
    }
    return list.slice(0, -1).join(', ') + ' and ' + list[list.length - 1];
}

/**
 * Pipeline → Orgs (build 55, board "Package-aware releases" a): which org has which managed package. Packages down,
 * orgs across (developer orgs, then the route), each cell the version, "Not installed" or "Not read yet". An admin
 * presses a version to mark the package "treat as not installed" in that org (installed but unlicensed) and presses it
 * again to take the mark off (a toggle chip). A note says what happens where a package is missing. Below the table, an
 * admin switches Can raise releases on a stage (its releases go to the next stop). Check now reads every org again
 * (one query each); the nightly pass does the same.
 */
export default class RlyOrgPackages extends NavigationMixin(LightningElement) {
    matrix;
    busy = false;
    error;
    message;

    connectedCallback() {
        readMatrix().then((m) => { this.matrix = m; }).catch((e) => { this.error = errorText(e); });
    }

    get loaded() { return !!this.matrix; }
    get isAdmin() { return !!this.matrix && this.matrix.isAdmin === true; }
    get checkLabel() { return this.busy ? 'Checking…' : 'Check now'; }
    get orgs() { return (this.matrix && this.matrix.orgs) || []; }
    get hasPackages() { return !!this.matrix && (this.matrix.packages || []).length > 0; }
    get noPackages() { return !!this.matrix && !this.hasPackages; }
    get noPackagesText() {
        return this.matrix && this.matrix.checkedAt
            ? 'No managed package in any org: releases work as before.'
            : 'Not read yet. ' + (this.isAdmin ? 'Check now reads every org\'s installed packages, or wait for the nightly pass.' : 'The nightly pass reads them.');
    }

    get headers() {
        return this.orgs.map((o) => ({ key: 'h-' + o.id, name: o.name }));
    }

    /** One row per package; each cell a tag (or, for admins, a toggle chip on an installed package). */
    get rows() {
        const orgs = this.orgs;
        return ((this.matrix && this.matrix.packages) || []).map((p) => {
            const versions = (p.cells || []).filter((c) => c.installed).map((c) => c.version);
            const common = versions.slice().sort((a, b) => versions.filter((v) => v === b).length - versions.filter((v) => v === a).length)[0];
            return {
                key: 'p-' + p.ns,
                name: p.name || p.ns,
                ns: p.ns,
                cells: (p.cells || []).map((c, i) => this.cell(p, c, orgs[i] || {}, common))
            };
        });
    }

    cell(p, c, org, common) {
        const where = org.name || '';
        const base = { key: p.ns + '-' + c.orgId, orgId: c.orgId, ns: p.ns };
        if (c.unknown && !c.installed) {
            return { ...base, toggle: false, text: 'Not read yet', cls: 'rr-tag rr-tag-none rr-tag-hint', title: where + '\'s packages haven\'t been read' };
        }
        if (!c.installed) {
            return { ...base, toggle: false, text: 'Not installed', cls: 'rr-tag rr-tag-none', title: p.name + ' isn\'t installed in ' + where };
        }
        const odd = common && c.version !== common;
        const text = c.off ? c.version + ' · treated as not installed' : c.version;
        let cls = 'rr-tag ' + (odd ? 'rr-tag-odd' : 'rr-tag-ok');
        if (c.off) {
            cls = 'rr-tag rr-tag-off';
        }
        return {
            ...base,
            toggle: this.isAdmin,
            text,
            cls: this.isAdmin ? cls + ' rr-tchip' : cls,
            pressed: c.off ? 'true' : 'false',
            off: c.off ? 'true' : 'false',
            title: c.off ? where + ': treated as not installed. Press to count it as installed again.'
                : (this.isAdmin ? 'Installed in ' + where + '. Press to treat it as not installed (installed but unlicensed).' : 'Installed in ' + where)
        };
    }

    /** The amber notes: a package missing in some orgs, and different versions. */
    get notes() {
        const out = [];
        ((this.matrix && this.matrix.packages) || []).forEach((p) => {
            const missing = p.missingIn || [];
            const has = (p.cells || []).some((c) => c.installed && !c.off);
            if (missing.length && has) {
                out.push({ key: 'm-' + p.ns, text: (p.name || p.ns) + ' isn\'t in ' + names(missing) + ': its references are kept on the branch when you raise from '
                    + (missing.length === 1 ? 'it' : 'them') + ', and left out when deploying to ' + (missing.length === 1 ? 'it' : 'them') + '.' });
            }
            const versions = new Set((p.cells || []).filter((c) => c.installed).map((c) => c.version));
            if (versions.size > 1) {
                out.push({ key: 'v-' + p.ns, text: 'Different versions of ' + (p.name || p.ns) + ' (' + Array.from(versions).join(', ') + ') are shown, not blocked.' });
            }
        });
        return out;
    }
    get hasNotes() { return this.notes.length > 0; }

    get errorRows() {
        const errs = (this.matrix && this.matrix.errors) || {};
        return Object.keys(errs).map((k) => ({ key: 'e-' + k, text: k + ' wasn\'t read: ' + errs[k] }));
    }

    /** The Can raise releases row: developer orgs always, a stage when switched on (a toggle chip for admins). */
    get raiseCells() {
        return this.orgs.map((o) => {
            const base = { key: 'r-' + o.id, id: o.id };
            if (o.role === 'Developer') {
                return { ...base, toggle: false, text: 'Always', cls: 'rr-small rr-weak' };
            }
            if (!o.canRaiseSwitch) {
                return { ...base, toggle: false, text: '–', cls: 'rr-small rr-weak' };
            }
            if (!this.isAdmin) {
                return { ...base, toggle: false, text: o.canRaise ? 'On · into ' + o.raisesInto : 'Off', cls: o.canRaise ? 'rr-tag rr-tag-on' : 'rr-small rr-weak' };
            }
            return {
                ...base,
                toggle: true,
                text: o.canRaise ? 'Can raise releases ✓' : 'Can raise releases',
                cls: 'rr-tchip' + (o.canRaise ? ' rr-tchip-on' : ''),
                pressed: o.canRaise ? 'true' : 'false',
                on: o.canRaise ? 'false' : 'true',
                title: (o.canRaise ? 'Releases are raised from ' + o.name : 'Let releases be raised from ' + o.name) + ': they go to ' + o.raisesInto + '.'
            };
        });
    }

    get footText() {
        const n = ((this.matrix && this.matrix.packages) || []).length;
        const at = this.matrix && this.matrix.checkedAt;
        return (at ? 'Checked ' + dateTime(at) : 'Not checked yet') + ' · ' + n + (n === 1 ? ' package' : ' packages') + ' · ';
    }

    run(promise) {
        this.busy = true;
        this.error = undefined;
        this.message = undefined;
        return promise.then((m) => {
            this.matrix = m;
            this.message = m.message;
        }).catch((e) => {
            this.error = errorText(e);
        }).finally(() => {
            this.busy = false;
        });
    }

    handleCheck() {
        this.run(checkNow());
    }

    handleMark(event) {
        const d = event.currentTarget.dataset;
        const args = { orgId: d.org, namespace: d.ns };
        this.run(d.off === 'true' ? countInstalled(args) : markNotInstalled(args));
    }

    handleRaise(event) {
        const d = event.currentTarget.dataset;
        this.run(d.on === 'true' ? allowRaising({ orgId: d.id }) : stopRaising({ orgId: d.id }));
    }

    openGuide(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: GUIDE_TAB }, state: { c__section: GUIDE_SECTION } });
    }
}
