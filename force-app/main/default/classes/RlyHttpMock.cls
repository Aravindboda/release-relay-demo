/**
 * @description A table-driven callout mock for the tests: answers by the first rule whose method and URL fragment
 * (and, when given, request body fragment) match; anything else is 404. Records every call.
 */
@IsTest
public with sharing class RlyHttpMock implements HttpCalloutMock {

    /** @description METHOD url (decoded) of every call, in order. */
    public List<String> calls = new List<String>();

    private static final String NOT_FOUND = '{"message":"Not Found"}';
    private List<Rule> rules = new List<Rule>();
    private List<List<String>> sent = new List<List<String>>();

    /** @description One row of the table. */
    private class Rule {
        /** @description HTTP method. */
        public String method;
        /** @description Fragment of the decoded URL. */
        public String urlPart;
        /** @description Fragment the request body must contain, or null. */
        public String bodyPart;
        /** @description Status to answer with. */
        public Integer status = 200;
        /** @description Body to answer with. */
        public String body = '';
    }

    /**
     * @description Adds a rule for a method and URL fragment; reply sets its answer.
     * @param method HTTP method
     * @param urlPart fragment of the decoded URL
     * @return this mock
     */
    public RlyHttpMock match(String method, String urlPart) {
        Rule r = new Rule();
        r.method = method;
        r.urlPart = urlPart;
        rules.add(r);
        return this;
    }

    /**
     * @description Makes the last rule apply only when the request body contains this.
     * @param bodyPart fragment of the request body
     * @return this mock
     */
    public RlyHttpMock ifBodyHas(String bodyPart) {
        rules[rules.size() - 1].bodyPart = bodyPart;
        return this;
    }

    /**
     * @description Sets the last rule's answer.
     * @param status HTTP status
     * @param body response body
     * @return this mock
     */
    public RlyHttpMock reply(Integer status, String body) {
        Rule r = rules[rules.size() - 1];
        r.status = status;
        r.body = body;
        return this;
    }

    /**
     * @description Answers a callout from the table.
     * @param req the request
     * @return the answer
     */
    public HttpResponse respond(HttpRequest req) {
        String url = EncodingUtil.urlDecode(req.getEndpoint(), 'UTF-8');
        String body = req.getBody() == null ? '' : req.getBody();
        calls.add(req.getMethod() + ' ' + url);
        sent.add(new List<String>{ url, body });
        Rule r = find(req.getMethod(), url, body);
        HttpResponse res = new HttpResponse();
        res.setStatusCode(r == null ? 404 : r.status);
        res.setBody(r == null ? NOT_FOUND : r.body);
        res.setHeader('Content-Type', res.getBody().startsWith('<') ? 'text/xml' : 'application/json');
        return res;
    }

    private Rule find(String method, String url, String body) {
        for (Rule r : rules) {
            if (r.method == method && url.contains(r.urlPart) && (r.bodyPart == null || body.contains(r.bodyPart))) {
                return r;
            }
        }
        return null;
    }

    /**
     * @description The body of the last request whose URL contains the fragment.
     * @param urlPart fragment of the decoded URL
     * @return the body, or null when there was no such request
     */
    public String bodyFor(String urlPart) {
        String found;
        for (List<String> s : sent) {
            if (s[0].contains(urlPart)) {
                found = s[1];
            }
        }
        return found;
    }

    /**
     * @description Every call, one per line.
     * @return the calls
     */
    public String callLog() {
        return String.join(calls, '\n');
    }
}
