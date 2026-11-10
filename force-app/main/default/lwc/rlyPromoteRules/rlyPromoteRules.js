import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const GUIDE_TAB = 'RLY_Relay_Guide';
const GUIDE_SECTION = 'moves';

/**
 * How promoting works (board HubPromoteRules): one source for the rules the Promote tab enforces (RlyPromoteOverlap,
 * mirrored by overlapOf in rlyPromote), shown in three places:
 *   variant="panel"  the side panel a Promote card opens ("How promoting works"): the route, the stage rule, the four
 *                    rules with a small before → after each, and "Full guide ›" (Guide › How a change moves)
 *   variant="rules"  the Guide's four rule tiles, each drawn as an inline SVG
 *   variant="card"   the Guide's annotated example of a Promote card (callouts 1 to 4)
 * The stage names come in (stage-name, next-name); the releases and components are clearly example values.
 */
export default class RlyPromoteRules extends NavigationMixin(LightningElement) {
    /** The stage the card promotes from (for example QA). */
    @api stageName;
    /** The next stop (for example Staging). */
    @api nextName;
    /** panel, rules or card. */
    @api variant = 'panel';
    /** The route for the panel's small picture: [{ name, dev }] in order, developer orgs first (dev: true). */
    @api route;

    get isPanel() { return this.variant !== 'rules' && this.variant !== 'card'; }
    get isRules() { return this.variant === 'rules'; }
    get isCard() { return this.variant === 'card'; }

    // Names from the route (build 52); the Guide's drawings, without a route, use neutral QA and Staging.
    get fromName() { return this.stageName || this.routeStop(0) || (this.isPanel ? 'this stage' : 'QA'); }
    get toName() { return this.nextName || this.routeStop(1) || (this.isPanel ? 'the next stop' : 'Staging'); }
    routeStop(n) {
        const stops = (Array.isArray(this.route) ? this.route : []).filter((s) => s && !s.dev && s.name);
        return stops[n] ? stops[n].name : '';
    }
    get routeText() { return this.fromName + ' → ' + this.toName; }
    get staysTitle() { return 'Stays in ' + this.fromName; }
    get goesLabel() { return 'Goes to ' + this.toName; }
    get hotfixButton() { return 'Promote hotfix to ' + this.toName; }
    get promoteButton() { return 'Promote 2 releases to ' + this.toName; }
    get bundleTitle() { return 'Bundle into one ' + this.toName + ' release'; }
    get bigLead() { const t = this.toName; return t.charAt(0).toUpperCase() + t.slice(1) + ' gets each file as it is in ' + this.fromName + '.'; }
    get bigTail() {
        return ' A release can\'t leave ' + this.fromName + ' without the other changes ' + this.fromName + ' already has in the same component.';
    }
    get footTail() {
        return ': ' + this.toName + '\'s checks (scan, check-only deploy, tests), then ' + this.toName
            + '\'s approval, then the deploy. Only approvers and admins can promote.';
    }

    // ---------- the drawings' full text (the svg's accessible name says the whole example) ----------
    get hotAria() {
        return 'Hotfix first: REL-00021 is a hotfix, ticked on its own; REL-00018 stays in ' + this.fromName + '; only REL-00021 goes to ' + this.toName + '.';
    }
    get goesAria() {
        return 'Goes too: REL-00018 and REL-00019 both change AccountService. Ticking the newer REL-00019 carries the older REL-00018 to ' + this.toName + '.';
    }
    get mustAria() {
        return 'Must add: REL-00018 is ticked; REL-00019 changed AccountService later. Promote stays grey until REL-00019 is added.';
    }
    get stayAria() {
        return 'Stays in ' + this.fromName + ': REL-00019 is ticked; REL-00020 changes a different component (CaseListView) and stays in ' + this.fromName + '.';
    }
    get cardAria() {
        return 'Example Promote card ' + this.fromName + ' to ' + this.toName + ' with callouts 1 to 4, explained in the list next to it.';
    }

    /** The small route: each stop, with the hop between (New Release from developer orgs, then Promote); this card's two stops and hop are marked. */
    get routeItems() {
        const stops = Array.isArray(this.route) && this.route.length
            ? this.route
            : [{ name: this.fromName }, { name: this.toName }];
        const items = [];
        stops.forEach((st, i) => {
            const on = !st.dev && (st.name === this.fromName || st.name === this.toName);
            items.push({ key: 's' + i, isHop: false, label: st.name, cls: on ? 'rp-rm rp-rm-on' : 'rp-rm' });
            if (i < stops.length - 1) {
                const next = stops[i + 1];
                const hopOn = st.name === this.fromName && next.name === this.toName && !st.dev;
                items.push({ key: 'h' + i, isHop: true, label: st.dev ? 'New Release' : 'Promote', cls: hopOn ? 'rp-rma rp-rma-on' : 'rp-rma' });
            }
        });
        return items;
    }

    /** Moves the focus to the panel's heading (the Promote tab calls it when the panel opens). */
    @api
    focusHeading() {
        const heading = this.template.querySelector('.rp-h2');
        if (heading) {
            heading.focus();
        }
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    /** Esc closes the panel. */
    handleKey(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.close();
        }
    }

    /** "Full guide ›": Guide › Start here › How a change moves. */
    openGuide() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: GUIDE_TAB },
            state: { c__section: GUIDE_SECTION }
        });
    }
}
