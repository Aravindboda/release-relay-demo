/**
 * @description The deployment team checks manual steps off per org (RlyManualSteps): Done, Not needed (with a note) or
 * back to To do. Only the deployment team (RLY_Deploy_Team) and admins may. When the last Before deploy run of a deploy is
 * checked off and the release is approved and waiting for it (RlyManualStepGate), the deploy starts as the approval would
 * have started it (mode merge; a queued back promote sync: its sync run). This is a user's click, so the callout is
 * allowed: callouts come first (Slack too), the saves last.
 */
public with sharing class RlyManualStepCheck {

    private static final Set<String> STATUSES = new Set<String>{
        RlyManualSteps.STATUS_TO_DO, RlyManualSteps.STATUS_DONE, RlyManualSteps.STATUS_NOT_NEEDED };

    /** @description What the release page sends to check a step off. */
    public class Mark {
        /** @description The run. */
        public Id runId;
        /** @description To_Do, Done or Not_Needed. */
        public String status;
        /** @description The note (required for Not_Needed, up to 255 characters). */
        public String note;
        /** @description The release whose page sent it (the board returned is that page's), or null. */
        public Id releaseId;
    }

    /**
     * @description Reads the JSON the page sends; a blank releaseId counts as missing.
     * @param runJson {runId, status, note, releaseId}
     * @return what to mark
     */
    public static Mark parse(String runJson) {
        Map<String, Object> sent;
        try {
            sent = (Map<String, Object>) JSON.deserializeUntyped(runJson);
        } catch (Exception e) {
            throw new RlyReleaseException('The manual step couldn\'t be read.');
        }
        if (sent.get('releaseId') == null || String.isBlank(String.valueOf(sent.get('releaseId')))) {
            sent.remove('releaseId');
        }
        return (Mark) JSON.deserialize(JSON.serialize(sent), Mark.class);
    }

    /**
     * @description Checks a run off (or back to To do) and, when it was the last Before deploy run of an approved
     * release's deploy, starts the deploy.
     * @param m what to mark
     * @return the release whose board the page shows (m.releaseId, or the run's release)
     */
    public static Id mark(Mark m) {
        if (!RlyManualSteps.canCheck()) {
            throw new RlyReleaseException('Only the deployment team can check off manual steps.');
        }
        String note = checkedNote(m);
        RLY_Manual_Step_Run__c run = RlyManualStepStore.run(m.runId);
        if (run == null) {
            throw new RlyReleaseException('This manual step isn\'t there any more. Reload the page.');
        }
        apply(run, m.status, note);
        RLY_Release__c rel = run.Status__c == RlyManualSteps.STATUS_TO_DO ? null : releaseToStart(run);
        if (rel != null) {
            String oldStatus = rel.Status__c;
            start(rel);
            RlySlack.notifyTransition(rel, oldStatus); // callouts before any DML
        }
        RlyManualStepStore.saveRuns(new List<RLY_Manual_Step_Run__c>{ run });
        RlyReleaseLog.manualStep(run);
        if (rel != null) {
            RlyReleaseStore.save(rel);
            RlySlack.saveResults();
        }
        RlyReleaseLog.flush();
        return m.releaseId == null ? run.Release__c : m.releaseId;
    }

    // A known status, and the note (required for Not_Needed), trimmed.
    private static String checkedNote(Mark m) {
        if (m == null || m.runId == null || !STATUSES.contains(m.status)) {
            throw new RlyReleaseException('Mark the manual step To_Do, Done or Not_Needed.');
        }
        String note = String.isBlank(m.note) ? null : m.note.trim().left(255);
        if (m.status == RlyManualSteps.STATUS_NOT_NEEDED && note == null) {
            throw new RlyReleaseException('Say why this manual step isn\'t needed.');
        }
        return note;
    }

    private static void apply(RLY_Manual_Step_Run__c run, String status, String note) {
        Boolean isDone = status != RlyManualSteps.STATUS_TO_DO;
        run.Status__c = status;
        run.Note__c = note;
        run.Done_By__c = isDone ? UserInfo.getUserId() : null;
        run.Done_On__c = isDone ? System.now() : null;
    }

    // The release whose deploy this run held: its last Before deploy run, the release approved (or queued) and waiting.
    private static RLY_Release__c releaseToStart(RLY_Manual_Step_Run__c run) {
        Boolean isBefore = run.Step__r != null && run.Step__r.Timing__c == RlyManualSteps.TIMING_BEFORE;
        if (!isBefore || RlyManualStepStore.openBefore(run.Release__c, run.Org__c, run.Id) > 0) {
            return null;
        }
        RLY_Release__c rel = RlyReleaseStore.release(run.Release__c);
        return rel != null && rel.Target_Org__c == run.Org__c && RlyManualStepGate.isWaiting(rel) ? rel : null;
    }

    // Starts the deploy as the approval would have: the merge (or the sync run), or the checks again when the target moved
    // since they passed (the approval is then cleared: the release is approved again after the checks).
    private static void start(RLY_Release__c rel) {
        try {
            RLY_Git_Connection__c conn = RlyReleaseStore.git();
            RlyGit git = RlyGit.forConnection(conn);
            if (RlyPromotion.typeOf(rel) == RlyPromotion.TYPE_BACK_PROMOTE && rel.Status__c == RlyPromotion.QUEUED) {
                RlyBackPromoteRun.dispatch(rel, git);
            } else if (RlyApprovalRuns.targetMoved(rel, git)) {
                RlyApprovalRuns.startChecks(rel, conn, RlyPipelineRun.RECHECK);
                rel.Approval_Status__c = 'Pending';
                rel.Approved_By__c = null;
                rel.Approved_On__c = null;
                rel.Second_Approved_By__c = null;
                rel.Second_Approved_On__c = null;
            } else {
                RlyApprovalRuns.dispatchMerge(rel, git);
            }
        } catch (Exception e) {
            rel.Error_Message__c = ('The manual steps are done, but the deploy couldn\'t start: ' + e.getMessage()).left(2000);
        }
    }
}
