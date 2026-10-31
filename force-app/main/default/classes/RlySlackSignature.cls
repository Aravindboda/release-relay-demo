/**
 * @description Checks that a request really comes from the hub's Slack app: X-Slack-Signature must be
 * v0=HMAC-SHA256('v0:' + timestamp + ':' + raw body) with the saved signing secret, and the timestamp
 * (X-Slack-Request-Timestamp) at most five minutes old. Apex REST hands a form post over as parameters, so when the
 * raw body is empty it's rebuilt from the payload parameter (with the encodings Slack may use).
 */
public with sharing class RlySlackSignature {

    /** @description Oldest request accepted, in seconds. */
    public static final Integer MAX_AGE_SECONDS = 300;

    /**
     * @description Whether the request is signed by the Slack app and recent.
     * @param req the request
     * @param secret the saved signing secret
     * @return true when it is
     */
    public static Boolean isValid(RestRequest req, String secret) {
        String stamp = header(req, 'X-Slack-Request-Timestamp');
        String signature = header(req, 'X-Slack-Signature');
        if (String.isBlank(secret) || String.isBlank(signature) || !isRecent(stamp)) {
            return false;
        }
        for (String body : bodies(req)) {
            if (sign(secret, stamp, body).equals(signature.trim())) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description The signature Slack sends for a body.
     * @param secret the signing secret
     * @param stamp the request timestamp (seconds)
     * @param body the raw body
     * @return v0= and the hex HMAC-SHA256
     */
    public static String sign(String secret, String stamp, String body) {
        Blob mac = Crypto.generateMac('hmacSHA256', Blob.valueOf('v0:' + stamp + ':' + body), Blob.valueOf(secret));
        return 'v0=' + EncodingUtil.convertToHex(mac);
    }

    /**
     * @description The payload JSON of a Slack interaction (form field payload).
     * @param req the request
     * @return the JSON, or null
     */
    public static String payload(RestRequest req) {
        if (req.params != null && req.params.containsKey('payload')) {
            return req.params.get('payload');
        }
        for (String pair : rawBody(req).split('&')) {
            if (pair.startsWith('payload=')) {
                return EncodingUtil.urlDecode(pair.substringAfter('payload='), 'UTF-8');
            }
        }
        return null;
    }

    private static Boolean isRecent(String stamp) {
        if (String.isBlank(stamp) || !stamp.trim().isNumeric()) {
            return false;
        }
        Long age = System.now().getTime() / 1000 - Long.valueOf(stamp.trim());
        return Math.abs(age) <= MAX_AGE_SECONDS;
    }

    private static String rawBody(RestRequest req) {
        return req.requestBody == null ? '' : req.requestBody.toString();
    }

    // The raw body, or the form body rebuilt from the payload parameter.
    private static List<String> bodies(RestRequest req) {
        String raw = rawBody(req);
        if (String.isNotBlank(raw)) {
            return new List<String>{ raw };
        }
        String payloadJson = payload(req);
        if (payloadJson == null) {
            return new List<String>();
        }
        String encoded = EncodingUtil.urlEncode(payloadJson, 'UTF-8');
        return new List<String>{ 'payload=' + encoded, 'payload=' + encoded.replace('*', '%2A'),
            'payload=' + encoded.replace('*', '%2A').replace('%7E', '~') };
    }

    private static String header(RestRequest req, String name) {
        if (req.headers == null) {
            return null;
        }
        for (String key : req.headers.keySet()) {
            if (key.equalsIgnoreCase(name)) {
                return req.headers.get(key);
            }
        }
        return null;
    }
}
