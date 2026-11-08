/**
 * Release Relay archive and retention wording, shared by the Pipeline tab's Retention section (c/rlyPipeline) and the
 * Archive tab (c/rlyArchive): when the nightly job calls. The numbers, dates and storage sizes live in c/rlyShared
 * (build 50) and are exported from here too, so both tabs keep importing them from this module.
 */
import { num, count, about, toDate, longDate, shortDate, clock, sameDay, when, stamp, mb, size, duration, errorText } from 'c/rlyShared';

export { num, count, about, toDate, longDate, shortDate, clock, when, stamp, mb, size, duration, errorText };

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
