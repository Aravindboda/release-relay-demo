import { LightningElement, api } from 'lwc';

const MARKERS = ['<<<<<<<', '>>>>>>>'];

function parse(json) {
    if (!json) {
        return null;
    }
    try {
        return JSON.parse(json);
    } catch {
        return null;
    }
}

function lines(text) {
    return (text || '').split(/\r?\n/);
}

/** One row per line; a line that isn't in the other version is highlighted. */
function lineRows(text, other, side) {
    const elsewhere = new Set(lines(other));
    return lines(text).map((line, i) => ({
        key: side + i,
        num: i + 1,
        text: line === '' ? ' ' : line,
        cls: 'rr-code' + (elsewhere.has(line) ? '' : ' rr-code-' + side),
        changed: !elsewhere.has(line)
    }));
}

function editProblem(content) {
    if (!content || !content.trim()) {
        return 'The edited file is empty.';
    }
    const marker = MARKERS.find((m) => content.includes(m));
    return marker ? 'Remove the conflict markers (' + marker + ') and keep the lines you want.' : null;
}

/**
 * The conflicts of a release with its target branch (validate.json with status Conflict). For each file the user
 * keeps theirs, keeps the target's or edits the merged text; "Resolve and check again" sends every choice up as
 * a resolve event: { resolutions: [{ file, choice, content (edit only) }] }.
 */
export default class RlyMergeConflicts extends LightningElement {
    @api sourceName;
    @api targetName;
    @api targetBranch;
    @api canResolve = false;
    @api busy = false;

    result;
    choices = {};
    selectedFile;
    _resultJson;

    @api
    get resultJson() {
        return this._resultJson;
    }
    set resultJson(value) {
        if (value === this._resultJson) {
            return;
        }
        this._resultJson = value;
        this.result = parse(value) || {};
        this.choices = {};
        const first = this.conflicts[0];
        this.selectedFile = first ? first.file : undefined;
    }

    get conflicts() {
        const list = this.result && Array.isArray(this.result.conflicts) ? this.result.conflicts : [];
        return list.filter((c) => c && c.file);
    }

    get target() { return this.targetName || 'the target'; }
    get heading() { return 'Conflict with ' + this.target; }
    get intro() {
        const n = this.conflicts.length;
        const text = this.result.message || n + (n === 1 ? ' file conflicts' : ' files conflict') + ' with ' + (this.targetBranch || this.target) + '.';
        return text + ' Both sides changed the same lines. Choose for each file; the choices are committed to the release branch, then the checks run again.';
    }

    choiceLabel(choice) {
        if (choice === 'mine') {
            return 'Keep mine';
        }
        return choice === 'theirs' ? 'Keep ' + this.target + '\'s' : 'Edited';
    }

    get files() {
        return this.conflicts.map((c) => {
            const chosen = this.choices[c.file];
            const valid = chosen && (chosen.choice !== 'edit' || !editProblem(chosen.content));
            const on = c.file === this.selectedFile;
            return {
                key: c.file,
                file: c.file,
                rowCls: on ? 'rr-row-on' : '',
                pillCls: valid ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-bad',
                pillText: valid ? this.choiceLabel(chosen.choice) : 'Conflict',
                openLabel: (on ? 'Showing ' : 'Show ') + c.file,
                pressed: on ? 'true' : 'false'
            };
        });
    }

    handleSelect(event) {
        this.selectedFile = event.currentTarget.dataset.file;
    }

    get current() {
        return this.conflicts.find((c) => c.file === this.selectedFile);
    }
    get hasCurrent() { return !!this.current; }
    get currentFile() { return this.current ? this.current.file : ''; }
    get truncated() { return !!(this.current && this.current.truncated); }
    get mineRows() { return this.current ? lineRows(this.current.mine, this.current.theirs, 'mine') : []; }
    get theirsRows() { return this.current ? lineRows(this.current.theirs, this.current.mine, 'theirs') : []; }
    get mineTitle() { return 'Yours (' + (this.sourceName || 'your org') + ')'; }
    get theirsTitle() { return 'In ' + this.target + ' now'; }
    get compareLabel() { return 'Your version and the version in ' + this.target + ', side by side. Lines that differ are highlighted.'; }

    get currentChoice() {
        return this.current ? this.choices[this.current.file] : undefined;
    }

    get choiceButtons() {
        const chosen = this.currentChoice ? this.currentChoice.choice : null;
        return [
            { value: 'mine', label: 'Keep mine', disabled: false },
            { value: 'theirs', label: 'Keep ' + this.target + '\'s', disabled: false },
            { value: 'edit', label: 'Edit', disabled: this.truncated }
        ].map((b) => ({
            ...b,
            disabled: b.disabled || !this.canResolve,
            cls: 'rr-seg' + (b.value === chosen ? ' rr-seg-on' : ''),
            pressed: b.value === chosen ? 'true' : 'false'
        }));
    }
    get choiceGroupLabel() { return 'How to resolve ' + this.currentFile; }

    handleChoice(event) {
        const choice = event.currentTarget.dataset.value;
        const file = this.current.file;
        const previous = this.choices[file];
        const content = choice === 'edit' ? (previous && previous.content) || this.current.merged || '' : undefined;
        this.choices = { ...this.choices, [file]: { choice, content } };
    }

    get isEditing() { return !!(this.currentChoice && this.currentChoice.choice === 'edit'); }
    get editText() { return this.isEditing ? this.currentChoice.content : ''; }
    get editLabel() { return 'Merged ' + this.currentFile + ' (remove the conflict markers)'; }
    get editError() { return this.isEditing ? editProblem(this.currentChoice.content) : null; }

    handleEdit(event) {
        const file = this.current.file;
        this.choices = { ...this.choices, [file]: { choice: 'edit', content: event.detail.value } };
    }

    get resolvedCount() {
        return this.conflicts.filter((c) => {
            const chosen = this.choices[c.file];
            return chosen && (chosen.choice !== 'edit' || !editProblem(chosen.content));
        }).length;
    }
    get progressText() { return this.resolvedCount + ' of ' + this.conflicts.length + ' files resolved'; }
    get cantResolve() { return !this.canResolve || this.busy || this.resolvedCount < this.conflicts.length; }
    get resolveLabel() { return this.busy ? 'Resolving…' : 'Resolve and check again'; }
    get readOnly() { return !this.canResolve; }

    handleResolve() {
        const resolutions = this.conflicts.map((c) => {
            const chosen = this.choices[c.file];
            return chosen.choice === 'edit' ? { file: c.file, choice: 'edit', content: chosen.content } : { file: c.file, choice: chosen.choice };
        });
        this.dispatchEvent(new CustomEvent('resolve', { detail: { resolutions } }));
    }
}
