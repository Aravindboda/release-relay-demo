// Line diff for rlyDiffView: Myers' O(ND) diff on lines (common prefix and suffix trimmed first), a GitHub
// unified-diff patch reader, and the rows the template shows (split or unified, long unchanged runs folded).
// No external libraries.

export const MAX_LINES = 5000;
const MAX_EDITS = 2000; // beyond this many edits the middle is shown as one removed block and one added block
const FOLD_OVER = 8; // unchanged runs longer than this are folded
const CONTEXT = 3; // unchanged lines kept next to a change
const HUNK = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$/;

// Lines of a text; a final line break doesn't add an empty last line. Empty text = no lines.
export function toLines(text) {
    if (text === null || text === undefined || text === '') {
        return [];
    }
    const lines = String(text).split(/\r?\n/);
    if (lines.length && lines[lines.length - 1] === '') {
        lines.pop();
    }
    return lines;
}

function op(kind, oldNo, newNo, text) {
    return { kind, oldNo, newNo, text };
}

// Myers: the shortest edit script between a and b (arrays of lines), or null when it needs more than maxEdits edits.
function myers(a, b, maxEdits) {
    const n = a.length;
    const m = b.length;
    const max = n + m;
    const offset = max + 1;
    const v = new Int32Array(2 * max + 3);
    const trace = [];
    let found = -1;
    for (let d = 0; d <= max && found < 0; d++) {
        if (d > maxEdits) {
            return null;
        }
        trace.push(v.slice(offset - d - 1, offset + d + 2));
        for (let k = -d; k <= d; k += 2) {
            let x = (k === -d || (k !== d && v[offset + k - 1] < v[offset + k + 1])) ? v[offset + k + 1] : v[offset + k - 1] + 1;
            let y = x - k;
            while (x < n && y < m && a[x] === b[y]) {
                x++;
                y++;
            }
            v[offset + k] = x;
            if (x >= n && y >= m) {
                found = d;
                break;
            }
        }
    }
    return backtrack(a, b, trace, found);
}

function backtrack(a, b, trace, edits) {
    const out = [];
    let x = a.length;
    let y = b.length;
    for (let d = edits; d >= 0; d--) {
        const snap = trace[d];
        const at = (k) => snap[k + d + 1];
        const k = x - y;
        const prevK = (k === -d || (k !== d && at(k - 1) < at(k + 1))) ? k + 1 : k - 1;
        const prevX = d === 0 ? 0 : at(prevK);
        const prevY = d === 0 ? 0 : prevX - prevK;
        while (x > prevX && y > prevY) {
            out.push(op('same', x, y, a[x - 1]));
            x--;
            y--;
        }
        if (d > 0) {
            if (x === prevX) {
                out.push(op('add', null, y, b[y - 1]));
            } else {
                out.push(op('del', x, null, a[x - 1]));
            }
        }
        x = prevX;
        y = prevY;
    }
    return out.reverse();
}

// Line diff of two texts: [{kind: 'same'|'del'|'add', oldNo, newNo, text}] with 1-based line numbers.
export function diffTexts(leftText, rightText) {
    const a = toLines(leftText);
    const b = toLines(rightText);
    let start = 0;
    while (start < a.length && start < b.length && a[start] === b[start]) {
        start++;
    }
    let endA = a.length;
    let endB = b.length;
    while (endA > start && endB > start && a[endA - 1] === b[endB - 1]) {
        endA--;
        endB--;
    }
    const ops = [];
    for (let i = 0; i < start; i++) {
        ops.push(op('same', i + 1, i + 1, a[i]));
    }
    const midA = a.slice(start, endA);
    const midB = b.slice(start, endB);
    let mid = myers(midA, midB, MAX_EDITS);
    if (mid === null) {
        mid = midA.map((t, i) => op('del', i + 1, null, t)).concat(midB.map((t, i) => op('add', null, i + 1, t)));
    }
    mid.forEach((o) => {
        ops.push(op(o.kind, o.oldNo === null ? null : o.oldNo + start, o.newNo === null ? null : o.newNo + start, o.text));
    });
    for (let i = endA, j = endB; i < a.length; i++, j++) {
        ops.push(op('same', i + 1, j + 1, a[i]));
    }
    return ops;
}

function readHunk(m, state) {
    const oldStart = parseInt(m[1], 10);
    const newStart = parseInt(m[3], 10);
    state.oldNo = oldStart === 0 ? 1 : oldStart;
    state.newNo = newStart === 0 ? 1 : newStart;
    state.hunks.push({ oldStart, oldCount: m[2] === undefined ? 1 : parseInt(m[2], 10), newStart, newCount: m[4] === undefined ? 1 : parseInt(m[4], 10) });
    state.ops.push({ kind: 'hunk', oldNo: null, newNo: null, text: m[0] });
}

function readLine(line, state) {
    const sign = line.charAt(0);
    const text = line.substring(1);
    if (sign === '+') {
        state.ops.push(op('add', null, state.newNo++, text));
    } else if (sign === '-') {
        state.ops.push(op('del', state.oldNo++, null, text));
    } else if (sign === ' ') {
        state.ops.push(op('same', state.oldNo++, state.newNo++, text));
    }
    // '\' (no newline at end of file) and anything else: nothing to show
}

// A GitHub unified-diff patch (hunks "@@ -a,b +c,d @@" then ' ', '+', '-', '\' lines) as the same ops as diffTexts,
// with a 'hunk' op (its @@ line) before each hunk. isNew / isDeleted when the patch adds or removes the whole file.
export function parsePatch(patch) {
    const state = { ops: [], hunks: [], oldNo: 1, newNo: 1 };
    const lines = String(patch || '').split(/\r?\n/);
    let inHunk = false;
    lines.forEach((line) => {
        const m = HUNK.exec(line);
        if (m) {
            readHunk(m, state);
            inHunk = true;
        } else if (inHunk) {
            readLine(line, state);
        }
    });
    const h = state.hunks;
    const isNew = h.length === 1 && h[0].oldStart === 0 && h[0].oldCount === 0;
    const isDeleted = h.length === 1 && h[0].newStart === 0 && h[0].newCount === 0;
    return { ops: state.ops, isNew, isDeleted };
}

// Folds unchanged runs longer than FOLD_OVER lines, keeping CONTEXT lines next to each change.
// expanded: { foldId: true } for the folds the user opened.
export function foldOps(ops, expanded) {
    const out = [];
    let i = 0;
    while (i < ops.length) {
        if (ops[i].kind !== 'same') {
            out.push(ops[i]);
            i++;
            continue;
        }
        let j = i;
        while (j < ops.length && ops[j].kind === 'same') {
            j++;
        }
        const keepBefore = i === 0 ? 0 : CONTEXT;
        const keepAfter = j === ops.length ? 0 : CONTEXT;
        const hidden = j - i - keepBefore - keepAfter;
        const foldId = 'f' + i;
        if (j - i > FOLD_OVER && hidden > 0 && !expanded[foldId]) {
            for (let k = i; k < i + keepBefore; k++) {
                out.push(ops[k]);
            }
            out.push({ kind: 'fold', foldId, count: hidden });
            for (let k = j - keepAfter; k < j; k++) {
                out.push(ops[k]);
            }
        } else {
            for (let k = i; k < j; k++) {
                out.push(ops[k]);
            }
        }
        i = j;
    }
    return out;
}

function foldText(count) {
    return '⋯ ' + count.toLocaleString() + (count === 1 ? ' unchanged line' : ' unchanged lines');
}

// The changed middle of a removed line against the added line beside it: { pre, mark, post } of each.
function marks(oldText, newText) {
    let pre = 0;
    const max = Math.min(oldText.length, newText.length);
    while (pre < max && oldText.charAt(pre) === newText.charAt(pre)) {
        pre++;
    }
    let post = 0;
    while (post < max - pre && oldText.charAt(oldText.length - 1 - post) === newText.charAt(newText.length - 1 - post)) {
        post++;
    }
    const cut = (t) => ({ pre: t.substring(0, pre), mark: t.substring(pre, t.length - post), post: t.substring(t.length - post) });
    return pre + post === 0 ? null : { old: cut(oldText), new: cut(newText) };
}

function plain(text) {
    return { pre: text, mark: '', post: '' };
}

const TONE = { del: 'rr-del', add: 'rr-add', same: '' };
const SIGN = { del: '−', add: '+', same: '' };

function cell(o, side, parts) {
    if (!o) {
        return { no: '', sign: '', pre: '', mark: '', post: '', rowCls: 'rr-pad' };
    }
    const no = side === 'left' ? o.oldNo : o.newNo;
    const p = parts || plain(o.text);
    return { no: no === null ? '' : String(no), sign: SIGN[o.kind], pre: p.pre, mark: p.mark, post: p.post, rowCls: TONE[o.kind] };
}

function special(o, key) {
    if (o.kind === 'fold') {
        return { key, isFold: true, foldId: o.foldId, text: foldText(o.count) };
    }
    return { key, isHunk: true, text: o.text };
}

// Takes the run of removed and added lines starting at i; pairs[n] = { del, add, m } (m: changed characters).
function changeRun(ops, start) {
    const dels = [];
    const adds = [];
    let i = start;
    while (i < ops.length && (ops[i].kind === 'del' || ops[i].kind === 'add')) {
        (ops[i].kind === 'del' ? dels : adds).push(ops[i]);
        i++;
    }
    const pairs = [];
    for (let p = 0; p < Math.max(dels.length, adds.length); p++) {
        const m = dels[p] && adds[p] ? marks(dels[p].text, adds[p].text) : null;
        pairs.push({ del: dels[p], add: adds[p], m });
    }
    return { pairs, dels, adds, next: i };
}

// Rows for the side-by-side view: removed lines on the left beside the added lines on the right.
// Each row has l and r cells; both sides are drawn from the same rows so they stay level.
export function splitRows(ops) {
    const rows = [];
    let i = 0;
    while (i < ops.length) {
        const o = ops[i];
        const key = 's' + i;
        if (o.kind === 'fold' || o.kind === 'hunk') {
            rows.push(special(o, key));
            i++;
        } else if (o.kind === 'same') {
            rows.push({ key, isLine: true, l: cell(o, 'left'), r: cell(o, 'right') });
            i++;
        } else {
            const run = changeRun(ops, i);
            run.pairs.forEach((pr, p) => {
                rows.push({ key: key + '-' + p, isLine: true, l: cell(pr.del, 'left', pr.m && pr.m.old), r: cell(pr.add, 'right', pr.m && pr.m.new) });
            });
            i = run.next;
        }
    }
    return rows;
}

function unifiedRow(o, key, parts) {
    const c = cell(o, 'left', parts);
    return {
        key, isLine: true, rowCls: c.rowCls, sign: c.sign, pre: c.pre, mark: c.mark, post: c.post,
        oldNo: o.oldNo === null ? '' : String(o.oldNo), newNo: o.newNo === null ? '' : String(o.newNo)
    };
}

// Rows for the unified view: removed lines first, then added lines, of each change.
export function unifiedRows(ops) {
    const rows = [];
    let i = 0;
    while (i < ops.length) {
        const o = ops[i];
        if (o.kind === 'fold' || o.kind === 'hunk') {
            rows.push(special(o, 'u' + i));
            i++;
        } else if (o.kind === 'same') {
            rows.push(unifiedRow(o, 'u' + i));
            i++;
        } else {
            const run = changeRun(ops, i);
            run.pairs.forEach((pr, p) => {
                if (pr.del) {
                    rows.push(unifiedRow(pr.del, 'u' + i + 'd' + p, pr.m && pr.m.old));
                }
            });
            run.pairs.forEach((pr, p) => {
                if (pr.add) {
                    rows.push(unifiedRow(pr.add, 'u' + i + 'a' + p, pr.m && pr.m.new));
                }
            });
            i = run.next;
        }
    }
    return rows;
}

// +n / −n of the ops.
export function countOps(ops) {
    let added = 0;
    let removed = 0;
    ops.forEach((o) => {
        if (o.kind === 'add') {
            added++;
        } else if (o.kind === 'del') {
            removed++;
        }
    });
    return { added, removed };
}
