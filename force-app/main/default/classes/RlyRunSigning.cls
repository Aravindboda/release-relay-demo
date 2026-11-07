/**
 * @description Run signing (build 48, contract A): the hub signs every pipeline run it starts, so a run dispatched any
 * other way (someone with write access to the repository) is refused by the pipeline before it signs in to an org.
 * RlyGit.startPipeline calls sign() for every provider, so no caller can forget it.
 *
 * canonical = "rr1", request_id, mode, environment, target_environment, branch, target, title, sha256hex(components),
 * sha256hex(deletions), sha256hex(options as sent before iat and sig), iat; joined with "\n", no trailing newline.
 * sig = Base64(HMAC-SHA256(Base64-decoded key, canonical)). iat (epoch seconds) and sig are appended to the options
 * string as its last two keys by string manipulation, so the pipeline strips exactly that suffix to rebuild what was
 * signed. Absent inputs are empty strings; blank options are sent as {}. Without a key nothing is added.
 * Also: SHA-256 hex, the HMAC and a constant-time compare (RlyResultSignature, the Slack checks).
 */
public with sharing class RlyRunSigning {

    /** @description The canonical's version line. */
    public static final String VERSION = 'rr1';
    /** @description Bytes in a run-signing key. */
    public static final Integer KEY_BYTES = 32;
    private static final List<String> FIELDS = new List<String>{
        'request_id', 'mode', 'environment', 'target_environment', 'branch', 'target', 'title' };
    private static final List<String> HASHED = new List<String>{ 'components', 'deletions' };
    private static final String OPTIONS = 'options';
    private static final String EMPTY_OPTIONS = '{}';

    /**
     * @description The inputs to start a run with: signed when the hub has a run-signing key, otherwise unchanged.
     * @param inputs the pipeline inputs (not changed)
     * @return the inputs to send
     */
    public static Map<String, String> sign(Map<String, String> inputs) {
        String key = RlyRunKeyStore.key();
        if (key == null || inputs == null) {
            return inputs;
        }
        return sign(inputs, key, System.now().getTime() / 1000);
    }

    /**
     * @description Signs the inputs with a key at a time.
     * @param inputs the pipeline inputs (not changed)
     * @param key the Base64 run-signing key
     * @param iat the time, in epoch seconds
     * @return a copy whose options end with "iat" and "sig"
     */
    public static Map<String, String> sign(Map<String, String> inputs, String key, Long iat) {
        Map<String, String> out = inputs.clone();
        String options = optionsBase(inputs.get(OPTIONS));
        String sig = mac(key, canonical(inputs, options, iat));
        String suffix = '"iat":' + iat + ',"sig":"' + sig + '"}';
        out.put(OPTIONS, options == EMPTY_OPTIONS ? '{' + suffix : options.removeEnd('}') + ',' + suffix);
        return out;
    }

    /**
     * @description The text a run's signature covers.
     * @param inputs the pipeline inputs
     * @param options the options as sent before iat and sig
     * @param iat the time, in epoch seconds
     * @return the canonical text
     */
    public static String canonical(Map<String, String> inputs, String options, Long iat) {
        List<String> lines = new List<String>{ VERSION };
        for (String f : FIELDS) {
            lines.add(valueOf(inputs, f));
        }
        for (String f : HASHED) {
            lines.add(sha256Hex(valueOf(inputs, f)));
        }
        lines.add(sha256Hex(options));
        lines.add(String.valueOf(iat));
        return String.join(lines, '\n');
    }

    /**
     * @description Lower-case hex SHA-256 of a text's UTF-8 bytes.
     * @param text the text (null is empty)
     * @return 64 hex characters
     */
    public static String sha256Hex(String text) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(text == null ? '' : text)));
    }

    /**
     * @description Base64 HMAC-SHA256 of a text with the run-signing key.
     * @param key the Base64 key
     * @param text the text
     * @return the Base64 signature
     */
    public static String mac(String key, String text) {
        return EncodingUtil.base64Encode(Crypto.generateMac('hmacSHA256', Blob.valueOf(text), EncodingUtil.base64Decode(key)));
    }

    /**
     * @description Whether two texts are equal, in time that doesn't depend on where they differ.
     * @param a one text
     * @param b the other
     * @return true when both are set and equal
     */
    public static Boolean same(String a, String b) {
        if (a == null || b == null) {
            return false;
        }
        Integer diff = a.length() ^ b.length();
        Integer n = Math.max(a.length(), b.length());
        for (Integer i = 0; i < n; i++) {
            Integer x = i < a.length() ? a.charAt(i) : 0;
            Integer y = i < b.length() ? b.charAt(i) : 0;
            diff = diff | (x ^ y);
        }
        return diff == 0;
    }

    /**
     * @description A new random run-signing key.
     * @return Base64 of 32 random bytes
     */
    public static String newKey() {
        return EncodingUtil.base64Encode(Crypto.generateAesKey(KEY_BYTES * 8));
    }

    /**
     * @description Whether a text is a run-signing key: Base64 of exactly 32 bytes.
     * @param key the text
     * @return true when it is
     */
    public static Boolean isKey(String key) {
        if (String.isBlank(key) || !Pattern.matches('[A-Za-z0-9+/]{43}=', key.trim())) {
            return false;
        }
        try {
            return EncodingUtil.base64Decode(key.trim()).size() == KEY_BYTES;
        } catch (Exception e) {
            return false;
        }
    }

    // The options as sent before iat and sig: the caller's JSON object (trimmed), or {} when there is none.
    private static String optionsBase(String options) {
        String o = String.isBlank(options) ? EMPTY_OPTIONS : options.trim();
        if (!o.startsWith('{') || !o.endsWith('}')) {
            throw new RlyGit.GitException('The run\'s options must be a JSON object to be signed.');
        }
        return o.replaceAll('^\\{\\s*\\}$', EMPTY_OPTIONS);
    }

    private static String valueOf(Map<String, String> inputs, String name) {
        String v = inputs.get(name);
        return v == null ? '' : v;
    }
}
