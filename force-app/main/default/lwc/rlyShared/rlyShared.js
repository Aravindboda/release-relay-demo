/**
 * Release Relay's shared page helpers (build 50), used by every tab: error text, counts, dates and times, the hub
 * status gate, the search box and the parts runner. One copy here instead of one in each component.
 */

/** Modes of RlyHubGuard.getHubStatus in which a tab shows only the org gate. */
export const GATED_MODES = ['sandbox', 'copy', 'setup'];

/**
 * Whether a tab shows only the org gate (a sandbox, a sandbox copy of the hub, or an org being set up).
 * @param {object} hubStatus RlyHubGuard.getHubStatus's answer, or undefined
 * @returns {boolean} gated
 */
export function isGated(hubStatus) {
    return !!hubStatus && GATED_MODES.includes(hubStatus.mode);
}

/**
 * "1 file", "3 files".
 * @param {number} n how many
 * @param {string} one the word for one
 * @param {string} many the word for more
 * @returns {string} the count with its word
 */
export function plural(n, one, many) {
    return n + ' ' + (n === 1 ? one : many);
}

/**
 * "Nov 2, 2:00 PM": a moment's month, day and time.
 * @param {string|Date} value the moment
 * @returns {string} the date and time, or blank
 */
export function dateTime(value) {
    return value ? new Date(value).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '';
}

/**
 * Empties a component's search box (c-rly-search-box).
 * @param {object} template the component's template
 * @param {string} selector the box (when the component has more than one)
 */
export function clearSearchBox(template, selector = 'c-rly-search-box') {
    const box = template.querySelector(selector);
    if (box) {
        box.clear();
    }
}

/**
 * "1,240" (blank for null).
 * @param {number} n the number
 * @returns {string} the number with thousands separators
 */
export function num(n) {
    if (n === null || n === undefined || n === '') {
        return '';
    }
    return Number(n).toLocaleString();
}

/**
 * "1 release", "3 releases".
 * @param {number} n how many
 * @param {string} one the word for one
 * @param {string} many the word for more
 * @returns {string} the count with its word
 */
export function count(n, one, many) {
    return num(n || 0) + ' ' + (Number(n) === 1 ? one : many);
}

/**
 * About this many: 11,904 → 11,900, 131 → 130, 9 → 9.
 * @param {number} n the number
 * @returns {string} the rounded number
 */
export function about(n) {
    const v = Number(n) || 0;
    if (v >= 1000) {
        return num(Math.round(v / 100) * 100);
    }
    if (v >= 100) {
        return num(Math.round(v / 10) * 10);
    }
    return num(v);
}

/**
 * An Apex Date ("2024-11-02") or DateTime as a JavaScript Date (a Date-only value in local time).
 * @param {string|Date} value the value from Apex
 * @returns {Date|null} the date
 */
export function toDate(value) {
    if (!value) {
        return null;
    }
    if (value instanceof Date) {
        return value;
    }
    const s = String(value);
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
    if (m) {
        return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
    }
    const d = new Date(s);
    return isNaN(d.getTime()) ? null : d;
}

/**
 * "Nov 2, 2024".
 * @param {string|Date} value the date
 * @returns {string} the date with its year
 */
export function longDate(value) {
    const d = toDate(value);
    return d ? d.toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' }) : '';
}

/**
 * "Oct 29".
 * @param {string|Date} value the date
 * @returns {string} month and day
 */
export function shortDate(value) {
    const d = toDate(value);
    return d ? d.toLocaleDateString([], { month: 'short', day: 'numeric' }) : '';
}

/**
 * "2:00 AM".
 * @param {string|Date} value the time
 * @returns {string} the clock time
 */
export function clock(value) {
    const d = toDate(value);
    return d ? d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }) : '';
}

/**
 * Whether two dates fall on the same day.
 * @param {Date} a one date
 * @param {Date} b the other
 * @returns {boolean} the same day
 */
export function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

/**
 * "Today, 2:00 AM", "Yesterday, 2:00 AM", "Oct 29, 2:00 AM" (with the year when it isn't this year).
 * @param {string|Date} value the moment
 * @param {Date} now the time now
 * @returns {string} when, in words
 */
export function when(value, now = new Date()) {
    const d = toDate(value);
    if (!d) {
        return '';
    }
    const y = new Date(now.getTime());
    y.setDate(y.getDate() - 1);
    if (sameDay(d, now)) {
        return 'Today, ' + clock(d);
    }
    if (sameDay(d, y)) {
        return 'Yesterday, ' + clock(d);
    }
    const opts = d.getFullYear() === now.getFullYear() ? { month: 'short', day: 'numeric' } : { month: 'short', day: 'numeric', year: 'numeric' };
    return d.toLocaleDateString([], opts) + ', ' + clock(d);
}

/**
 * "Nov 1, 2:00 AM" (a runs list date: no "Today"; the year only when it isn't this year).
 * @param {string|Date} value the moment
 * @param {Date} now the time now
 * @returns {string} the date and time
 */
export function stamp(value, now = new Date()) {
    const d = toDate(value);
    if (!d) {
        return '';
    }
    const opts = d.getFullYear() === now.getFullYear() ? { month: 'short', day: 'numeric' } : { month: 'short', day: 'numeric', year: 'numeric' };
    return d.toLocaleDateString([], opts) + ', ' + clock(d);
}

/**
 * Storage in MB from KB, one decimal: 69,760 KB → "68.1".
 * @param {number} kb kilobytes
 * @returns {string} megabytes
 */
export function mb(kb) {
    const v = (Number(kb) || 0) / 1024;
    return v.toLocaleString([], { minimumFractionDigits: 1, maximumFractionDigits: 1 });
}

/**
 * "262 KB", "7.8 MB", "–" for nothing.
 * @param {number} kb kilobytes
 * @returns {string} the size
 */
export function size(kb) {
    const v = Number(kb) || 0;
    if (!v) {
        return '–';
    }
    return v < 1024 ? num(v) + ' KB' : mb(v) + ' MB';
}

/**
 * "1 min 2 s", "45 s".
 * @param {number} ms milliseconds
 * @returns {string} the duration
 */
export function duration(ms) {
    const s = Math.max(0, Math.round((Number(ms) || 0) / 1000));
    const m = Math.floor(s / 60);
    return m ? m + ' min ' + (s % 60) + ' s' : s + ' s';
}

/**
 * The text of an Apex or JavaScript error.
 * @param {*} e the error
 * @returns {string} what to show
 */
export function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

/** A component name from a file name (some are URL-encoded, like Account-Account %28Old%29 Layout). */
export function decodeName(name) {
    if (!name.includes('%')) {
        return name;
    }
    try {
        return decodeURIComponent(name.replace(/\+/g, '%2B'));
    } catch {
        return name;
    }
}

/** A standard object (Account) or field (Account.Industry): it can't be deleted. */
export function isStandard(type, name) {
    const own = type === 'CustomField' ? name.substring(name.indexOf('.') + 1) : name;
    return (type === 'CustomObject' || type === 'CustomField') && !own.includes('__');
}

/**
 * The comparison key of a component in the org or on the branch, lower case. A field's object is compared without its
 * suffix (__c, __mdt, __e, __b, __x), as custom fields read through the Tooling API may only know the object's base name.
 */
export function presenceKey(type, name) {
    let n = name.toLowerCase();
    if (type === 'CustomField' && n.includes('.')) {
        const dot = n.indexOf('.');
        n = n.substring(0, dot).replace(/__(c|mdt|e|b|x)$/, '') + n.substring(dot);
    }
    return type + ':' + n;
}

/** The types listMetadata can't list without a folder (rule kind folder: reports, dashboards, email templates). */
export function folderTypesOf(rules) {
    return new Set((rules || []).filter((r) => r.kind === 'folder').map((r) => r.type));
}

/**
 * Runs jobs (functions returning a promise that handles its own errors) a few at a time. Jobs added to the list while
 * it runs are picked up too (a failed part's retries).
 */
export function runPool(jobs, size) {
    let next = 0;
    const worker = () => {
        if (next >= jobs.length) {
            return Promise.resolve();
        }
        const job = jobs[next++];
        return Promise.resolve().then(job).then(worker);
    };
    return Promise.all(Array.from({ length: Math.min(size, Math.max(jobs.length, 1)) }, worker));
}

/**
 * Sending a developer org's components in parts (Sync status, Migration): which waiting parts start now, keeping at
 * most atOnce running, or that every part is ready.
 * @param {object} sending { parts: [{ id, phase: waiting | running | ready }] }
 * @param {number} atOnce most parts running at once
 * @returns {{ allReady: boolean, ids: string[] }} the parts to start
 */
export function partsToSend(sending, atOnce) {
    if (sending.parts.every((p) => p.phase === 'ready')) {
        return { allReady: true, ids: [] };
    }
    let running = sending.parts.filter((p) => p.phase === 'running').length;
    const ids = [];
    sending.parts.forEach((p) => {
        if (running < atOnce && p.phase === 'waiting') {
            running += 1;
            ids.push(p.id);
        }
    });
    return { allReady: false, ids };
}

/**
 * The sending state with one part's values changed.
 * @param {object} sending the state, or undefined (returned as it is)
 * @param {string} id the part
 * @param {object} values its new values
 * @returns {object} the new state
 */
export function withPart(sending, id, values) {
    // A send that failed or finished is undefined: a late part changes nothing (build 52).
    if (!sending || !sending.parts) {
        return sending;
    }
    return { ...sending, parts: sending.parts.map((p) => (p.id === id ? { ...p, ...values } : p)) };
}

/**
 * One part of the sending state.
 * @param {object} sending the state, or undefined
 * @param {string} id the part
 * @returns {object} the part, or undefined
 */
export function partIn(sending, id) {
    return sending && sending.parts ? sending.parts.find((p) => p.id === id) : undefined;
}

/**
 * Runs async steps one after the other until a step says it is done (build 57: sequential server calls without an
 * await inside a loop). Each step gets the state the last one returned.
 * @param {Function} step async (state) => ({ done, state })
 * @param {*} state the first step's state
 * @returns {Promise<*>} the last step's state
 */
export async function oneAfterAnother(step, state) {
    const r = await step(state);
    return r.done ? r.state : oneAfterAnother(step, r.state);
}

/** The Git providers a connection can use, with their hints (build 57: shared by the Pipeline tab and the setup wizard). */
export const GIT_PROVIDERS = [
    { label: 'GitHub', value: 'GitHub', how: 'Actions workflow', repo: 'owner/repository', pipeLabel: 'Workflow file', pipe: 'release-relay.yml', cred: 'RLY_Git_GitHub' },
    { label: 'GitLab', value: 'GitLab', how: 'CI pipeline', repo: 'group/project', pipeLabel: 'CI file', pipe: '.gitlab-ci.yml', cred: 'RLY_Git_GitLab' },
    { label: 'Bitbucket', value: 'Bitbucket', how: 'Custom pipeline', repo: 'workspace/repository', pipeLabel: 'Custom pipeline', pipe: 'release-relay', cred: 'RLY_Git_Bitbucket' },
    { label: 'Azure DevOps', value: 'AzureDevOps', how: 'Azure Pipeline', repo: 'organization/project/repository', pipeLabel: 'Pipeline id', pipe: '12', cred: 'RLY_Git_AzureDevOps' }
];

/**
 * Sizes a page to the browser window, from its top edge down (build 57: shared by Pipeline Monitor and Sync status).
 * @param {HTMLElement} page the page element, or null before it is drawn
 * @param {number} current the height set last
 * @param {number} minHeight the smallest height
 * @param {number} bottomGap the space kept under the page
 * @returns {number} the height now set
 */
export function fitPageToWindow(page, current, minHeight, bottomGap) {
    if (!page) {
        return current;
    }
    const top = page.getBoundingClientRect().top + (window.scrollY || 0);
    const height = Math.max(minHeight, Math.floor(window.innerHeight - top - bottomGap));
    if (current !== height) {
        page.style.height = height + 'px';
    }
    return height;
}
