import { LightningElement } from 'lwc';
import IS_ADMIN from '@salesforce/customPermission/RLY_Admin';
import SECTIONS from './guideContent';

/** The Release Relay guide: one section at a time, chosen from the tabs at the top. */
export default class RlyReleaseGuide extends LightningElement {
    current = 'how';

    get visibleSections() {
        return SECTIONS.filter((s) => !s.adminOnly || IS_ADMIN);
    }

    get tabs() {
        return this.visibleSections.map((s) => ({
            key: s.key,
            label: s.label,
            cls: 'rr-tab' + (s.key === this.current ? ' rr-tab-on' : ''),
            selected: s.key === this.current ? 'true' : 'false'
        }));
    }

    get section() {
        return this.visibleSections.find((s) => s.key === this.current) || this.visibleSections[0];
    }

    get hasRoute() {
        return Array.isArray(this.section.route);
    }

    get routeStops() {
        return (this.section.route || []).map((label, i) => ({ key: 'r' + i, label }));
    }

    get steps() {
        return this.section.steps.map((st, i) => ({
            ...st,
            num: i + 1,
            hasText: Array.isArray(st.text),
            paragraphs: (st.text || []).map((t, j) => ({ key: st.key + 'p' + j, t })),
            hasItems: Array.isArray(st.items),
            listItems: (st.items || []).map((t, j) => ({ key: st.key + 'i' + j, t })),
            hasTable: !!st.table,
            tableCols: st.table ? st.table.cols.map((c, j) => ({ key: st.key + 'c' + j, c })) : [],
            tableRows: st.table
                ? st.table.rows.map((row, j) => ({ key: st.key + 'r' + j, cells: row.map((c, k) => ({ key: st.key + 'r' + j + 'c' + k, c })) }))
                : []
        }));
    }

    handleTab(event) {
        this.current = event.currentTarget.dataset.key;
    }
}
