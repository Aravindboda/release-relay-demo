import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import logDownload from '@salesforce/apex/RlyManualStepController.logDownload';

/** File badges by extension: the letters shown and the tone (board HubStepFiles: CSV green, PDF red, images blue). */
const BADGE_TONE = { csv: 'ok', xls: 'ok', xlsx: 'ok', pdf: 'bad', png: 'info', jpg: 'info', jpeg: 'info', gif: 'info', svg: 'info', webp: 'info' };

/**
 * Files on a manual step, or proof on one org's run (board HubStepFiles). Lists RlyStepFiles.FileRow rows with Download
 * (every file; on a release it also writes "Downloaded" to History), Preview (PDF and images: the standard file preview)
 * and Remove (rows with canRemove). With a record-id and can-attach it shows lightning-file-upload: the files go straight
 * to Salesforce Files linked to that record (a step, a run, or on New Release the raiser's own user record).
 * Events: uploaded { files: [{ documentId, name }] }, remove { documentId, recordId }.
 */
export default class RlyStepFiles extends NavigationMixin(LightningElement) {
    /** RlyStepFiles.FileRow rows. */
    @api files;
    /** The record uploads link to (step, run, or the raiser's user record on New Release). */
    @api recordId;
    /** Uploads (and the drop zone) are shown. */
    @api canAttach = false;
    /** "Step files", "Proof in SIT", "Attach files". */
    @api label = 'Step files';
    /** The upload's own label. */
    @api uploadLabel = 'Upload files';
    /** Grey text when there are no files, or empty for none. */
    @api emptyText = '';
    /** The step's files are locked (the release is approved). */
    @api locked = false;
    /** The lock's tooltip. */
    @api lockText = '';
    /** The release page's release (Download writes History there); empty on New Release. */
    @api releaseId;
    /** The org tab the card shows (History's org for a download). */
    @api orgId;
    /** Upload, Remove are off (busy, or a sandbox copy of the hub). */
    @api disabled = false;
    /** Tighter, for proof inside a run row. */
    @api compact = false;

    get rows() {
        return (Array.isArray(this.files) ? this.files : []).map((f) => {
            const ext = (f.extension || '').toLowerCase();
            const tone = BADGE_TONE[ext] || 'none';
            return {
                ...f,
                key: f.documentId,
                badge: (ext || 'file').slice(0, 4).toUpperCase(),
                badgeCls: 'rr-sf-badge rr-sf-badge-' + tone,
                whoTitle: f.createdBy ? 'Attached by ' + f.createdBy : '',
                previewLabel: 'Preview ' + f.title,
                downloadLabel: 'Download ' + f.title,
                removeLabel: 'Remove ' + f.title
            };
        });
    }
    get hasFiles() { return this.rows.length > 0; }
    get count() { return String(this.rows.length); }
    get showCount() { return this.hasFiles; }
    get showEmpty() { return !this.hasFiles && !!this.emptyText; }
    get showUpload() { return !!this.canAttach && !!this.recordId && !this.locked; }
    get uploadHint() { return 'Any type · Salesforce file size limit'; }
    get wrapCls() { return 'rr-sf' + (this.compact ? ' rr-sf-compact' : ''); }
    get groupLabel() { return this.label; }
    get lockAria() { return 'Locked: approved files. ' + (this.lockText || ''); }

    fileOf(id) {
        return this.rows.find((f) => f.documentId === id);
    }

    /** Opens the file's download address; on a release page it also writes "Downloaded" to History (not waited for). */
    download(event) {
        const f = this.fileOf(event.currentTarget.dataset.id);
        if (!f) {
            return;
        }
        window.open(f.downloadUrl, '_blank');
        if (this.releaseId) {
            logDownload({ contentDocumentId: f.documentId, releaseId: this.releaseId, orgId: this.orgId || null }).catch(() => {
                // the download itself already started; a missing History row is not worth an error
            });
        }
    }

    /** The standard Salesforce file preview (PDF and images). */
    preview(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: event.currentTarget.dataset.id }
        });
    }

    remove(event) {
        this.dispatchEvent(new CustomEvent('remove', { detail: { documentId: event.currentTarget.dataset.id, recordId: this.recordId } }));
    }

    handleUpload(event) {
        const files = ((event.detail && event.detail.files) || []).map((x) => ({ documentId: x.documentId, name: x.name }));
        this.dispatchEvent(new CustomEvent('uploaded', { detail: { files } }));
    }
}
