/**
 * @description The pipeline run call (RlyRunMonitorRest, POST /services/apexrest/rly/pipeline-run) from the Git
 * pipeline's monitor jobs, signed in as the hub's pipeline user (Release Relay Admin), once when a run starts and once
 * when it ends. Body (unknown keys are ignored): runId (GitHub run id, digits), attempt (1 by default), mode, step,
 * branch, targetOrg, status (Queued, In progress, Succeeded, Failed, Cancelled, or GitHub's words), started, finished
 * (ISO 8601), durationSeconds, actor, runUrl (https), requestId (REL-00031), failureMessage, steps
 * ([{name, outcome, seconds}]). The run is upserted by Run_Id__c = runId + "-" + attempt; a value left out keeps what an
 * earlier call saved, and a finished run is never set back to Queued or In progress. A run that ends Succeeded while its
 * release's checks failed in it is saved Failed with why (RlyRunMonitorChecks). Answer: {ok, id, runKey, status,
 * release, warnings} or {ok:false, error}.
 */
public with sharing class RlyRunMonitorInbound {

    /** @description Refused for a caller without Release Relay Admin. */
    public static final String NOT_ADMIN = 'The pipeline\'s hub user needs Release Relay Admin.';
    /** @description Refused without a GitHub run id. */
    public static final String NO_RUN_ID = 'runId must be the GitHub run id (digits).';
    /** @description Refused without a known status. */
    public static final String NO_STATUS = 'status must be Queued, In progress, Succeeded, Failed or Cancelled.';
    /** @description Refused for a bad attempt. */
    public static final String BAD_ATTEMPT = 'attempt must be a whole number from 1 to 999.';

    /** @description Fields only the end of a run sets; a late start never changes them on a finished run. */
    private static final Set<String> ENDING_FIELDS = new Set<String>{ 'Finished__c', 'Failure_Message__c', 'Duration_Seconds__c', 'Steps__c' };

    /** @description The HTTP status of the last answer (200, 400 or 403), for RlyRunMonitorRest. */
    public static Integer httpStatus = 200;

    /**
     * @description Handles one call.
     * @param body the request body (JSON)
     * @return the answer
     */
    public static Map<String, Object> handle(String body) {
        if (!RlyOrgController.isAdmin()) {
            return refuse(403, NOT_ADMIN);
        }
        Reader rd = new Reader(RlyRunMonitorInput.parse(body));
        String problem = rd.problem();
        if (problem != null) {
            return refuse(400, problem);
        }
        RLY_Pipeline_Run__c built = rd.build();
        RLY_Pipeline_Run__c row = settle(built, RlyRunMonitorStore.byRunKey(built.Run_Id__c), rd.status);
        failIfChecksFailed(row, rd);
        Id saved = RlyRunMonitorStore.save(row);
        httpStatus = 200;
        String release = built.Release__c != null ? built.Request_Id__c : null;
        return new Map<String, Object>{ 'ok' => true, 'id' => saved, 'runKey' => row.Run_Id__c, 'status' => row.Status__c,
            'release' => release, 'warnings' => rd.warnings };
    }

    /** @description Reads one call's body into a run row, collecting warnings for values it had to skip. */
    private class Reader {
        /** @description The body's values. */
        private Map<String, Object> input;
        /** @description The GitHub run id. */
        private Long runId;
        /** @description The run attempt. */
        private Long attempt;
        /** @description The status. */
        public String status;
        /** @description Values sent in a format that couldn't be read. */
        public List<String> warnings = new List<String>();
        /** @description The run's release (requestId), with its check results, or null. */
        public RLY_Release__c release;

        /**
         * @description Reads the key values.
         * @param input the body's values
         */
        public Reader(Map<String, Object> input) {
            this.input = input;
            runId = RlyRunMonitorInput.whole(input.get('runId'));
            attempt = input.containsKey('attempt') ? RlyRunMonitorInput.whole(input.get('attempt')) : 1L;
            status = RlyRunMonitorInput.status(input.get('status'));
        }

        /**
         * @description The GitHub run id.
         * @return the id
         */
        public Long githubRunId() {
            return runId;
        }

        /**
         * @description Why the call is refused, or null.
         * @return the problem, or null
         */
        public String problem() {
            if (runId == null || runId <= 0) {
                return NO_RUN_ID;
            }
            if (attempt == null || attempt < 1 || attempt > 999) {
                return BAD_ATTEMPT;
            }
            return status == null ? NO_STATUS : null;
        }

        /**
         * @description The row with every value the call sent (a value left out stays null, so the upsert keeps the
         * saved one).
         * @return the row
         */
        public RLY_Pipeline_Run__c build() {
            RLY_Pipeline_Run__c row = new RLY_Pipeline_Run__c(Run_Id__c = runId + '-' + attempt);
            setIfSent(row, 'Mode__c', RlyRunMonitorInput.text(input.get('mode'), 40));
            setIfSent(row, 'Workflow_Step__c', RlyRunMonitorInput.text(input.get('step'), 80));
            setIfSent(row, 'Branch__c', RlyRunMonitorInput.text(input.get('branch'), 255));
            setIfSent(row, 'Target_Org__c', RlyRunMonitorInput.text(input.get('targetOrg'), 80));
            setIfSent(row, 'Actor__c', RlyRunMonitorInput.text(input.get('actor'), 120));
            setIfSent(row, 'Failure_Message__c', RlyRunMonitorInput.text(input.get('failureMessage'), 32768));
            setIfSent(row, 'Started__c', checked('started', RlyRunMonitorInput.moment(input.get('started'))));
            setIfSent(row, 'Finished__c', checked('finished', RlyRunMonitorInput.moment(input.get('finished'))));
            setIfSent(row, 'Run_Url__c', checked('runUrl', RlyRunMonitorInput.url(input.get('runUrl'))));
            setIfSent(row, 'Steps__c', checked('steps', RlyRunMonitorSteps.steps(input.get('steps'))));
            Long seconds = RlyRunMonitorInput.whole(input.get('durationSeconds'));
            setIfSent(row, 'Duration_Seconds__c', seconds == null || seconds < 0 ? null : Decimal.valueOf(seconds));
            withRelease(row);
            return row;
        }

        // Only values that were sent are set: a field left untouched keeps what an earlier call saved.
        private void setIfSent(RLY_Pipeline_Run__c row, String field, Object value) {
            if (value != null) {
                row.put(field, value);
            }
        }

        // The release named by requestId, found by its number.
        private void withRelease(RLY_Pipeline_Run__c row) {
            String requestId = (String) checked('requestId', RlyRunMonitorInput.releaseNumber(input.get('requestId')));
            if (requestId == null) {
                return;
            }
            row.Request_Id__c = requestId;
            release = RlyRunMonitorReleases.releaseByName(requestId);
            row.Release__c = release == null ? null : release.Id;
            if (row.Release__c == null) {
                warnings.add('No release ' + requestId + ' in this org.');
            }
        }

        // A value that was sent but couldn't be read is skipped with a warning.
        private Object checked(String key, Object value) {
            Object sent = input.get(key);
            Boolean blank = sent == null || (sent instanceof String && String.isBlank((String) sent))
                || (sent instanceof List<Object> && ((List<Object>) sent).isEmpty());
            if (value == null && !blank) {
                warnings.add(key + ' was ignored: it isn\'t in the expected format.');
            }
            return value;
        }
    }

    // Status, start, finish and duration against the saved run: a finished run stays finished; the start defaults to now.
    private static RLY_Pipeline_Run__c settle(RLY_Pipeline_Run__c row, RLY_Pipeline_Run__c saved, String status) {
        Boolean keepFinal = saved != null && RlyRunMonitorInput.isFinal(saved.Status__c) && !RlyRunMonitorInput.isFinal(status);
        if (keepFinal) {
            // A late start after the end: keep the end's finish, duration and failure (only the start's values are added).
            RLY_Pipeline_Run__c kept = new RLY_Pipeline_Run__c(Run_Id__c = row.Run_Id__c, Status__c = saved.Status__c);
            for (String f : row.getPopulatedFieldsAsMap().keySet()) {
                if (!ENDING_FIELDS.contains(f)) {
                    kept.put(f, row.get(f));
                }
            }
            return kept;
        }
        row.Status__c = status;
        if (row.Started__c == null) {
            row.Started__c = saved != null && saved.Started__c != null ? saved.Started__c : System.now();
        }
        if (RlyRunMonitorInput.isFinal(status)) {
            finish(row);
        }
        return row;
    }

    // A run GitHub ended green whose release's checks failed in it (the failure is in the result files): Failed, with why.
    private static void failIfChecksFailed(RLY_Pipeline_Run__c row, Reader rd) {
        String why = row.Status__c == RlyRunMonitorInput.SUCCEEDED ? RlyRunMonitorChecks.failedChecksOf(rd.release, rd.githubRunId()) : null;
        if (why != null) {
            row.Status__c = RlyRunMonitorInput.FAILED;
            row.Failure_Message__c = why;
        }
    }

    // A finished run gets its finish time (now when not sent) and its duration (when not sent).
    private static void finish(RLY_Pipeline_Run__c row) {
        if (row.Finished__c == null) {
            row.Finished__c = System.now();
        }
        if (row.Duration_Seconds__c == null) {
            Long secs = (row.Finished__c.getTime() - row.Started__c.getTime()) / 1000;
            row.Duration_Seconds__c = Math.max(secs, 0L);
        }
    }

    private static Map<String, Object> refuse(Integer code, String error) {
        httpStatus = code;
        return new Map<String, Object>{ 'ok' => false, 'error' => error };
    }
}
