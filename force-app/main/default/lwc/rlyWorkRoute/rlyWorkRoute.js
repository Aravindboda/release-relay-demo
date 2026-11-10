/**
 * Work items (build 47): which tracker a ticket goes to, as the hub decides it (RlyWorkRouting): the active trackers
 * in order, the first whose pattern matches; then a tracker with no pattern. Used by the ticket input and the Pipeline
 * tab's "Try a ticket". The hub checks again on save.
 */

/** Whether a ticket matches one of the space-separated patterns (whole ticket, any case). */
export function matchesPatterns(ticket, patterns) {
    if (!patterns || !patterns.trim() || !ticket) {
        return false;
    }
    return patterns.trim().split(/\s+/).some((f) => {
        try {
            return new RegExp('^(?:' + f + ')$', 'i').test(ticket);
        } catch {
            return false;
        }
    });
}

/**
 * The tracker a ticket goes to.
 * @param trackers the trackers (TrackerView: name, ticketPattern, active) in routing order
 * @param ticket the ticket
 * @returns {{ tracker: object|undefined, ok: boolean, problem: string|undefined }}
 */
export function routeTicket(trackers, ticket) {
    const active = (trackers || []).filter((t) => t.active);
    const hit = active.find((t) => t.ticketPattern && t.ticketPattern.trim() && matchesPatterns(ticket, t.ticketPattern))
        || active.find((t) => !t.ticketPattern || !t.ticketPattern.trim());
    if (hit || active.length === 0) {
        return { tracker: hit, ok: true, problem: undefined };
    }
    return { tracker: undefined, ok: false, problem: 'No tracker matches "' + ticket + '". Expected one of: ' + patternList(active) + '.' };
}

/** CLAIMS-\d+ (Claims stories), CHG\d{7} (Change requests). */
export function patternList(trackers) {
    return (trackers || []).filter((t) => t.active && t.ticketPattern).map((t) => t.ticketPattern.trim() + ' (' + t.name + ')').join(', ');
}
