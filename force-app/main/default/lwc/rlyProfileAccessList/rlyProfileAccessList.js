import { LightningElement, api, wire } from 'lwc';
import forRelease from '@salesforce/apex/RlyProfileAccessController.forRelease';
import { errorText } from 'c/rlyShared';
import { sectionOf, describe } from 'c/rlyAccessRows';

/**
 * A release's profile access (build 58), read only: each profile with the rows the release sends. Nothing shows
 * when the release has none.
 */
export default class RlyProfileAccessList extends LightningElement {
    @api releaseId;
    profiles = [];
    error;

    @wire(forRelease, { releaseId: '$releaseId' })
    wired({ data, error }) {
        if (data) {
            this.profiles = data;
            this.error = undefined;
        } else if (error) {
            this.error = errorText(error);
        }
    }

    get hasAccess() { return (this.profiles || []).length > 0; }

    get rowCount() {
        return (this.profiles || []).reduce((n, p) => n + (p.rows || []).length, 0);
    }

    get countText() {
        const n = this.rowCount;
        return n + (n === 1 ? ' row' : ' rows');
    }

    get groups() {
        return (this.profiles || []).map((p) => ({
            key: p.profile,
            label: p.label || p.profile,
            rows: (p.rows || []).map((r) => ({
                key: r.section + '|' + r.key,
                kind: (sectionOf(r.section) || { label: r.section }).label,
                name: r.key,
                sends: sectionOf(r.section) ? describe(r.section, r.values) : JSON.stringify(r.values)
            }))
        }));
    }
}
