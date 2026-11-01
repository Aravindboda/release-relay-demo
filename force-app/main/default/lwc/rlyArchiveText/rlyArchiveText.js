/**
 * Release Relay archive and retention wording, shared by the Pipeline tab's Retention section (c/rlyPipeline) and the
 * Archive tab (c/rlyArchive): numbers, dates, storage sizes and when the nightly job calls.
 */

/** The Git pipeline's scheduled job: cron "0 8 * * *" (08:00 UTC = 2:00 AM Central in winter). */
export const NIGHTLY_UTC_HOUR = 8;
/** Salesforce data storage counts about 2 KB per record. */
export const KB_PER_RECORD = 2;
/** The fewest days Retention accepts. */
export const MIN_DAYS = 30;
/** Releases per pass (at most; a pass also stops at 4,000 records). */
export const PASS_SIZE = 200;
export const DAY_MS = 24 * 60 * 60 * 1000;

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

function sameDay(a, b) {
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
 * The next time the nightly job calls (08:00 UTC), in this browser's time.
 * @param {Date} now the time now
 * @returns {Date} the next call
 */
export function nextNightly(now = new Date()) {
    const next = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), NIGHTLY_UTC_HOUR, 0, 0));
    if (next.getTime() <= now.getTime()) {
        next.setTime(next.getTime() + DAY_MS);
    }
    return next;
}

/**
 * "2:00 AM": the nightly job's time of day in this browser's time.
 * @returns {string} the clock time
 */
export function nightlyClock() {
    return clock(nextNightly());
}

/**
 * "Tonight, 2:00 AM" (the next call in the small hours of tomorrow, or later today), "Today, 2:00 AM" or the date.
 * @param {Date} now the time now
 * @returns {string} the next nightly call in words
 */
export function nextNightlyText(now = new Date()) {
    const next = nextNightly(now);
    const tomorrow = new Date(now.getTime());
    tomorrow.setDate(tomorrow.getDate() + 1);
    if ((sameDay(next, tomorrow) && next.getHours() < 6) || (sameDay(next, now) && next.getHours() >= 18)) {
        return 'Tonight, ' + clock(next);
    }
    if (sameDay(next, now)) {
        return 'Today, ' + clock(next);
    }
    return when(next, now);
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
