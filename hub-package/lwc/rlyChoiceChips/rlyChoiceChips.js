import { LightningElement, api } from 'lwc';

/**
 * Settings choices without checkboxes or bare radios.
 *   mode "multi"  (default): a row of selectable chips (aria-pressed); value is a list of option values.
 *   mode "single": radio cards (role radio, aria-checked); value is one option value.
 * Options: { value, label, help?, disabled? }. Fires "change" with detail { value } (the new list or value).
 */
export default class RlyChoiceChips extends LightningElement {
    /** The group's name, shown above it and read by screen readers. */
    @api label;
    /** multi or single. */
    @api mode = 'multi';
    /** The choices. */
    @api options = [];
    /** The chosen values (multi) or value (single). */
    @api value;
    /** Every choice off. */
    @api disabled = false;

    get isSingle() { return this.mode === 'single'; }
    get isMulti() { return !this.isSingle; }

    get picked() {
        if (this.isSingle) {
            return this.value === undefined || this.value === null ? [] : [this.value];
        }
        return Array.isArray(this.value) ? this.value : [];
    }

    get items() {
        const picked = this.picked;
        return (this.options || []).map((o) => {
            const selected = picked.includes(o.value);
            const off = this.disabled === true || o.disabled === true;
            let cls = this.isSingle ? 'rr-rcard' : 'rr-chip';
            cls += selected ? ' rr-sel' : '';
            cls += off ? ' rr-off' : '';
            return {
                value: o.value,
                label: o.label,
                help: o.help || '',
                selected,
                off,
                pressed: selected ? 'true' : 'false',
                cls,
                helpCls: off ? 'rr-rcard-help rr-rcard-warn' : 'rr-rcard-help'
            };
        });
    }

    handleClick(event) {
        const value = event.currentTarget.dataset.value;
        const option = (this.options || []).find((o) => o.value === value);
        if (!option || option.disabled === true || this.disabled === true) {
            return;
        }
        let next;
        if (this.isSingle) {
            if (value === this.value) {
                return;
            }
            next = value;
        } else {
            const picked = this.picked;
            const on = picked.includes(value) ? picked.filter((v) => v !== value) : [...picked, value];
            // Keep the options' order, whatever order they were picked in.
            next = this.options.map((o) => o.value).filter((v) => on.includes(v));
        }
        this.dispatchEvent(new CustomEvent('change', { detail: { value: next } }));
    }
}
