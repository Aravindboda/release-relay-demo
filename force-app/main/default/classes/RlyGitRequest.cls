/**
 * @description One HTTP request to the Git provider (RlyGit.send): method, path after the Named Credential URL,
 * an optional JSON body and headers that replace the provider's defaults.
 */
public with sharing class RlyGitRequest {

    /** @description GET, POST and so on. */
    public String method;
    /** @description Path after the Named Credential URL. */
    public String path;
    /** @description JSON body, or null. */
    public String body;
    /** @description Headers that replace the provider's defaults. */
    public Map<String, String> headers = new Map<String, String>();

    /**
     * @description A request.
     * @param method HTTP method
     * @param path path after the Named Credential URL
     * @param body JSON body, or null
     */
    public RlyGitRequest(String method, String path, String body) {
        this.method = method;
        this.path = path;
        this.body = body;
    }

    /**
     * @description Sets a header.
     * @param name header name
     * @param value header value
     * @return this request
     */
    public RlyGitRequest withHeader(String name, String value) {
        headers.put(name, value);
        return this;
    }

    /**
     * @description URL-encodes a value (spaces as %20).
     * @param value the value
     * @return the encoded value
     */
    public static String encode(String value) {
        return EncodingUtil.urlEncode(value == null ? '' : value, 'UTF-8').replace('+', '%20');
    }

    /**
     * @description Encodes each path segment, keeping the slashes.
     * @param path the path
     * @return the encoded path
     */
    public static String encodePath(String path) {
        List<String> parts = new List<String>();
        for (String p : (path == null ? '' : path).split('/')) {
            parts.add(encode(p));
        }
        return String.join(parts, '/');
    }
}
