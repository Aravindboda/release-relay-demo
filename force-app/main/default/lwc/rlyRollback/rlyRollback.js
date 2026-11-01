import { LightningElement, api } from 'lwc';
import rollbackChoices from '@salesforce/apex/RlyRollbackController.rollbackChoices';
import previewRollback from '@salesforce/apex/RlyRollbackController.previewRollback';
import startRollback from '@salesforce/apex/RlyRollbackController.startRollback';

/** RlyRollback.TESTS_RELEASE and TESTS_ALL: the production tests choice. */
const TESTS_RELEASE = 'release';
const TESTS_ALL = 'all';
const SHOWN_COMPONENTS = 12;

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function shortWhen(value) {
    return value ? new Date(value).toLocaleString([], { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '';
}

/** "ApexClass:PayClient" → "ApexClass PayClient". */
function componentText(key) {
    const at = String(key).indexOf(':');
    return at > 0 ? String(key).slice(0, at) + ' ' + String(key).slice(at + 1) : String(key);
}

function listText(keys) {
    const shown = keys.slice(0, SHOWN_COMPONENTS).map(componentText);
    const more = keys.length - shown.length;
    return shown.join(' · ') + (more > 0 ? ' · and ' + more + ' more' : '');
}

function countText(n) {
    return n + (n === 1 ? ' component' : ' components');
}

/**
 * Roll back REL-…: the confirm dialog (board HubRollbackValuesGates, panel 1). One chip per org the release (or the
 * promotion that carried it) was deployed to, in route order; an org without a snapshot is a grey "No snapshot" chip that
 * can't be picked. Picking an org reads what will be restored and removed from its snapshot. Production gets a tests
 * choice (this release's tests, or all local tests); a reason is required. Fires "close" (cancelled) and "started".
 */
export default class RlyRollback extends LightningElement {
    /** The release. */
    @api releaseId;
    /** Its number, for the title. */
    @api releaseName;

    choices = [];
    orgId;
    preview;
    reason = '';
    tests = TESTS_RELEASE;
    loading = false;
    busy = false;
    error;

    connectedCallback() {
        this.loadChoices();
    }

    async loadChoices() {
        this.loading = true;
        try {
            this.choices = (await rollbackChoices({ releaseId: this.releaseId })) || [];
            const usable = this.choices.filter((c) => c.hasSnapshot);
            if (usable.length === 1) {
                this.pick(usable[0].orgId);
            }
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loading = false;
        }
    }

    get heading() { return 'Roll back ' + (this.releaseName || ''); }
    get noChoices() { return !this.loading && this.choices.length === 0; }
    get noChoicesText() { return 'This release hasn\'t been deployed to an org that can be rolled back.'; }

    get chips() {
        return this.choices.map((c) => {
            const picked = c.orgId === this.orgId;
            const off = !c.hasSnapshot || this.busy;
            let cls = 'rr-chip';
            if (picked) {
                cls += ' rr-chip-on';
            } else if (!c.hasSnapshot) {
                cls += ' rr-chip-off';
            }
            return {
                key: c.orgId + c.ownerName,
                orgId: c.orgId,
                orgName: c.orgName,
                sub: c.hasSnapshot ? 'deployed ' + shortWhen(c.deployedOn) : (c.why || 'No snapshot'),
                picked,
                checked: picked ? 'true' : 'false',
                off,
                cls,
                title: c.hasSnapshot ? '' : 'No snapshot was taken before this deploy, so it can\'t be rolled back.'
            };
        });
    }

    pickOrg(event) {
        this.pick(event.currentTarget.dataset.id);
    }

    async pick(orgId) {
        if (!orgId || orgId === this.orgId) {
            return;
        }
        this.orgId = orgId;
        this.preview = undefined;
        this.error = undefined;
        this.loading = true;
        try {
            this.preview = await previewRollback({ releaseId: this.releaseId, orgId });
            this.tests = this.releaseTests.length ? TESTS_RELEASE : TESTS_ALL;
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loading = false;
        }
    }

    // ---------- what will happen ----------

    get org() { return (this.preview && this.preview.org) || {}; }
    get orgName() { return this.org.orgName || ''; }
    get ownerName() { return this.org.ownerName || this.releaseName || ''; }
    get production() { return this.org.production === true; }
    get whatHeading() { return 'What will happen in ' + this.orgName; }
    get restore() { return (this.preview && this.preview.restore) || []; }
    get remove() { return (this.preview && this.preview.remove) || []; }
    get restoreCount() { return this.restore.length; }
    get removeCount() { return this.remove.length; }
    get restoreText() { return countText(this.restore.length); }
    get removeText() { return countText(this.remove.length); }
    get restoreList() { return listText(this.restore); }
    get removeList() { return listText(this.remove); }
    get deployedText() { return this.org.deployedOn ? ' on ' + shortWhen(this.org.deployedOn) : ''; }
    get snapshotPath() { return this.org.snapshotPath || ''; }
    get takenText() {
        const taken = this.preview && this.preview.takenOn;
        return taken ? 'Taken ' + shortWhen(taken) + ', just before the deploy' : 'Taken just before the deploy';
    }
    /** A promotion's snapshot holds everything that promotion deployed, not only this release. */
    get promotionNote() {
        return this.org.byPromotion
            ? this.ownerName + ' carried this release to ' + this.orgName + '. Its snapshot puts back everything ' + this.ownerName + ' deployed there.'
            : '';
    }
    get laterLines() {
        const later = (this.preview && this.preview.later) || [];
        return later.map((text, i) => ({ key: 'l' + i, text }));
    }

    // ---------- tests in production ----------

    get releaseTests() { return Array.isArray(this.org.tests) ? this.org.tests : []; }
    get testChoices() {
        const n = this.releaseTests.length;
        return [
            { value: TESTS_RELEASE, label: 'This release\'s tests (' + n + ')', off: n === 0 || this.busy },
            { value: TESTS_ALL, label: 'All local tests', off: this.busy }
        ].map((t) => {
            const on = t.value === this.tests;
            return { ...t, checked: on ? 'true' : 'false', cls: 'rr-seg-btn' + (on ? ' rr-seg-on' : '') + (t.off && !on ? ' rr-seg-off' : '') };
        });
    }
    pickTests(event) {
        this.tests = event.currentTarget.dataset.value;
    }
    get testsHint() {
        if (!this.preview.apex) {
            return 'No Apex in this rollback, so no tests are needed.';
        }
        const which = this.tests === TESTS_RELEASE && this.releaseTests.length ? this.releaseTests.join(', ') : 'all local tests';
        return 'Apex is in this rollback, so production runs tests: ' + which + '. Salesforce\'s 75% coverage rule still applies.';
    }

    // ---------- reason and actions ----------

    handleReason(event) {
        this.reason = event.target.value || '';
    }

    get confirmDisabled() {
        return this.busy || this.loading || !this.preview || !this.reason.trim();
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.cancel();
        }
    }

    cancel() {
        if (!this.busy) {
            this.dispatchEvent(new CustomEvent('close'));
        }
    }

    async confirm() {
        if (this.confirmDisabled) {
            return;
        }
        this.busy = true;
        this.error = undefined;
        try {
            await startRollback({
                releaseId: this.releaseId,
                requestJson: JSON.stringify({ orgId: this.orgId, reason: this.reason.trim(), tests: this.production ? this.tests : TESTS_ALL })
            });
            this.dispatchEvent(new CustomEvent('started', { detail: { orgName: this.orgName } }));
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }
}
