import { LightningElement, api } from 'lwc';

/**
 * Search box for long lists: a search input with a clear button and a count ("12 of 48", or "48" when nothing is hidden).
 * The parent filters its rows client-side on every "search" event (detail { value }). Escape clears the box.
 */
export default class RlySearchBox extends LightningElement {
    /** Read by screen readers, e.g. "Search releases". */
    @api label = 'Search';
    /** Grey hint inside the box. */
    @api placeholder = 'Search';
    /** Rows shown after filtering. */
    @api shown;
    /** Rows before filtering. */
    @api total;

    term = '';

    /** Clears the box from the parent (e.g. a "Clear search" link in an empty list). */
    @api
    clear() {
        this.setTerm('');
    }

    /** Puts the cursor in the box. */
    @api
    focus() {
        const input = this.template.querySelector('input');
        if (input) {
            input.focus();
        }
    }

    get hasTerm() { return this.term !== ''; }

    get hasCount() {
        return this.total !== undefined && this.total !== null && this.total !== '';
    }

    get totalNum() { return Number(this.total) || 0; }

    get shownNum() {
        return this.shown === undefined || this.shown === null || this.shown === '' ? this.totalNum : Number(this.shown) || 0;
    }

    get isFiltered() { return this.shownNum !== this.totalNum; }
    get shownText() { return String(this.shownNum); }
    get totalText() { return String(this.totalNum); }

    get countText() {
        return this.isFiltered ? this.shownNum + ' of ' + this.totalNum : String(this.totalNum);
    }

    get countLabel() {
        return this.countText + ' shown';
    }

    get clearLabel() {
        return 'Clear ' + (this.label || 'search').toLowerCase();
    }

    setTerm(value) {
        const next = value || '';
        const input = this.template.querySelector('input');
        if (input && input.value !== next) {
            input.value = next;
        }
        if (next === this.term) {
            return;
        }
        this.term = next;
        this.dispatchEvent(new CustomEvent('search', { detail: { value: next } }));
    }

    handleInput(event) {
        this.setTerm(event.target.value);
    }

    handleKeydown(event) {
        if (event.key === 'Escape' && this.term !== '') {
            event.preventDefault();
            event.stopPropagation();
            this.setTerm('');
        }
    }

    handleClear() {
        this.setTerm('');
        this.focus();
    }
}
