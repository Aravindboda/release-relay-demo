/**
 * @description Results the hub trusts (build 48, contract C). The pipeline writes each result file as the wrapper
 * {"payload": "<the result JSON as a string>", "sig": "…"} (version 2), with
 * sig = Base64(HMAC-SHA256(key, "rr1-result\n" + request_id + "\n" + step + "\n" + sha256hex(payload))), so the
 * signature covers the exact payload text (Apex can't rebuild JavaScript's key order). The hub checks it over that
 * text and only then parses the payload. request_id is the folder under results/ and step the file name.
 *
 * Strict files (release steps, rollback, data): with a run-signing key set, a file without a good signature is
 * rejected; without a key, a wrapper's payload and an older unwrapped file are both read. Lenient files (migrate,
 * compare, drift and route pages): a wrapper is unwrapped and a signature that is there is checked; a missing one is
 * accepted. A rejected file is never acted on: the caller shows REJECTED and leaves the release where it was.
 */
public with sharing class RlyResultSignature {

    /** @description What a result that failed the check is shown as. */
    public static final String REJECTED = 'Result rejected: not signed by the pipeline';
    /** @description The canonical's version line. */
    public static final String VERSION = 'rr1-result';
    private static final String PAYLOAD_KEY = 'payload';
    private static final String SIG_KEY = 'sig';
    /** @description Checker mode: a missing signature is rejected while a key is set. */
    public static final String MODE_STRICT = 'strict';
    /** @description Checker mode: a missing signature is accepted; one that is there is checked. */
    public static final String MODE_LENIENT = 'lenient';

    /** @description One result file, opened. */
    public class Opened {
        /** @description The result, or null when there is none (or it was rejected). */
        public Map<String, Object> data;
        /** @description The file was there but failed the signature check. */
        public Boolean rejected = false;
        /** @description The file carried a good signature. */
        public Boolean signed = false;
    }

    /**
     * @description Opens a strict result file with the hub's run-signing key.
     * @param raw the file's text, or null
     * @param requestId the run's request_id (the folder under results/)
     * @param step the step (the file name without .json)
     * @return the opened file
     */
    public static Opened open(String raw, String requestId, String step) {
        return new Checker(RlyRunKeyStore.key(), MODE_STRICT).open(raw, requestId, step);
    }

    /**
     * @description Opens a lenient result file (a signature that is there is checked; a missing one is accepted).
     * @param raw the file's text, or null
     * @param requestId the run's request_id
     * @param step the step
     * @return the result, or null when there is none or it was rejected
     */
    public static Map<String, Object> lenient(String raw, String requestId, String step) {
        return new Checker(RlyRunKeyStore.key(), MODE_LENIENT).open(raw, requestId, step).data;
    }

    /** @description Opens result files with a key, strict or lenient. */
    public class Checker {
        private final String key;
        private final Boolean sigRequired;

        /**
         * @description A checker.
         * @param key the Base64 run-signing key, or null when the hub has none
         * @param mode MODE_STRICT or MODE_LENIENT
         */
        public Checker(String key, String mode) {
            this.key = key;
            this.sigRequired = mode == MODE_STRICT;
        }

        /**
         * @description Opens a result file.
         * @param raw the file's text, or null
         * @param requestId the run's request_id
         * @param step the step
         * @return the opened file
         */
        public Opened open(String raw, String requestId, String step) {
            Opened o = new Opened();
            Map<String, Object> wrapper = parsed(raw);
            if (wrapper == null) {
                return o;
            }
            if (!isWrapper(wrapper)) {
                o.rejected = key != null && sigRequired;
                o.data = o.rejected ? null : wrapper;
                return o;
            }
            String payload = (String) wrapper.get(PAYLOAD_KEY);
            Object sig = wrapper.get(SIG_KEY);
            if (key != null && (sig != null || sigRequired)) {
                o.signed = sig instanceof String && RlyRunSigning.same(RlyRunSigning.mac(key, canonical(requestId, step, payload)), (String) sig);
                o.rejected = !o.signed;
            }
            o.data = o.rejected ? null : parsed(payload);
            return o;
        }
    }

    /**
     * @description The text a result's signature covers.
     * @param requestId the run's request_id
     * @param step the step
     * @param payload the payload text
     * @return the canonical text
     */
    public static String canonical(String requestId, String step, String payload) {
        return VERSION + '\n' + (requestId == null ? '' : requestId) + '\n' + (step == null ? '' : step) + '\n' + RlyRunSigning.sha256Hex(payload);
    }

    /**
     * @description The message a release shows when a step's result was rejected.
     * @param step the step
     * @return the message
     */
    public static String rejectedMessage(String step) {
        return REJECTED + ' (' + step + '.json). The release stays where it was. If you just set the run-signing key, add the same '
            + 'key to the repository as RELAY_RUN_KEY, then run the checks again.';
    }

    // The wrapper: a payload text and nothing but a sig besides.
    private static Boolean isWrapper(Map<String, Object> wrapper) {
        if (!(wrapper.get(PAYLOAD_KEY) instanceof String)) {
            return false;
        }
        for (String k : wrapper.keySet()) {
            if (!k.equals(PAYLOAD_KEY) && !k.equals(SIG_KEY)) {
                return false;
            }
        }
        return true;
    }

    private static Map<String, Object> parsed(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            Object o = JSON.deserializeUntyped(raw);
            return o instanceof Map<String, Object> ? (Map<String, Object>) o : null;
        } catch (JSONException e) {
            return null;
        }
    }
}
