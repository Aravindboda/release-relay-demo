/**
 * @description Work items (build 40): the HTTP calls to each tracker, through the admin's Named Credential.
 *   Jira          POST /rest/api/2/issue/<id>/comment; with a mapped state, the matching transition
 *                 (GET /rest/api/2/issue/<id>/transitions, POST …/transitions)
 *   Azure_Boards  PATCH /_apis/wit/workitems/<number>?api-version=7.0 (System.History, and System.State when mapped)
 *   ServiceNow    GET /api/now/table/<table>?sysparm_query=number=<id>, PATCH /api/now/table/<table>/<sys_id>
 *                 (work_notes, and state when mapped)
 *   Other         POST to the Named Credential's address: {ticket, release, title, moment, org, url, at}
 *   Test          Jira GET /rest/api/2/myself, Azure Boards GET /_apis/wit/workitemtypes, ServiceNow GET one row of the
 *                 table (build 47)
 * Each call goes through the ticket's own tracker (build 47: a hub can have several). Callouts only, no DML.
 */
public with sharing class RlyWorkCalls {

    private static final Integer TIMEOUT_MS = 10000;
    private static final String JSON_TYPE = 'application/json';
    private static final String PATCH_TYPE = 'application/json-patch+json';
    private static final String UTF8 = 'UTF-8';

    /**
     * @description Jira: a comment, then the transition named like the mapped state.
     * @param s the tracker
     * @param m the message
     * @param o the outcome to fill
     */
    public static void jira(RLY_Work_Tracker__c s, RlyWorkTypes.Message m, RlyWorkTypes.Outcome o) {
        String issue = '/rest/api/2/issue/' + EncodingUtil.urlEncode(m.ticket, UTF8);
        check(send(withBody(request(s, 'POST', issue + '/comment'), new Map<String, Object>{ 'body' => m.text }, JSON_TYPE)), o, 'Comment added');
        if (!o.ok || String.isBlank(m.state)) {
            return;
        }
        String transition = transitionId(send(request(s, 'GET', issue + '/transitions')), m.state);
        if (transition == null) {
            o.message = 'Comment added; no transition "' + m.state + '" from the ticket\'s current state.';
            return;
        }
        Map<String, Object> body = new Map<String, Object>{ 'transition' => new Map<String, Object>{ 'id' => transition } };
        check(send(withBody(request(s, 'POST', issue + '/transitions'), body, JSON_TYPE)), o, 'Comment added, moved to ' + m.state);
    }

    /**
     * @description Azure Boards: the comment in System.History, and System.State when mapped.
     * @param s the tracker
     * @param m the message
     * @param o the outcome to fill
     */
    public static void azure(RLY_Work_Tracker__c s, RlyWorkTypes.Message m, RlyWorkTypes.Outcome o) {
        String itemNo = m.ticket.replaceAll('[^0-9]', '');
        if (String.isBlank(itemNo)) {
            o.message = 'An Azure Boards work item is a number (for example 1234 or AB#1234).';
            return;
        }
        List<Object> ops = new List<Object>{ new Map<String, Object>{ 'op' => 'add', 'path' => '/fields/System.History', 'value' => m.text } };
        if (String.isNotBlank(m.state)) {
            ops.add(new Map<String, Object>{ 'op' => 'add', 'path' => '/fields/System.State', 'value' => m.state });
        }
        check(send(withBody(request(s, 'PATCH', '/_apis/wit/workitems/' + itemNo + '?api-version=7.0'), ops, PATCH_TYPE)),
            o, String.isBlank(m.state) ? 'Comment added' : 'Comment added, state ' + m.state);
    }

    /**
     * @description ServiceNow: finds the record by number, then a work note (and the state when mapped).
     * @param s the tracker
     * @param m the message
     * @param o the outcome to fill
     */
    public static void serviceNow(RLY_Work_Tracker__c s, RlyWorkTypes.Message m, RlyWorkTypes.Outcome o) {
        String table = EncodingUtil.urlEncode(String.isBlank(s.ServiceNow_Table__c) ? 'change_request' : s.ServiceNow_Table__c.trim(), UTF8);
        Map<String, Object> rec = firstRecord(send(request(s, 'GET', '/api/now/table/' + table
            + '?sysparm_limit=1&sysparm_fields=sys_id&sysparm_query=number%3D' + EncodingUtil.urlEncode(m.ticket, UTF8))));
        if (rec == null) {
            o.message = m.ticket + ' wasn\'t found in ServiceNow ' + EncodingUtil.urlDecode(table, UTF8) + '.';
            return;
        }
        Map<String, Object> body = new Map<String, Object>{ 'work_notes' => m.text };
        if (String.isNotBlank(m.state)) {
            body.put('state', m.state);
        }
        check(send(withBody(request(s, 'PATCH', '/api/now/table/' + table + '/' + rec.get('sys_id')), body, JSON_TYPE)),
            o, String.isBlank(m.state) ? 'Work note added' : 'Work note added, state ' + m.state);
    }

    /**
     * @description Other: one JSON POST to the Named Credential's address.
     * @param s the tracker
     * @param m the message
     * @param o the outcome to fill
     */
    public static void webCall(RLY_Work_Tracker__c s, RlyWorkTypes.Message m, RlyWorkTypes.Outcome o) {
        Map<String, Object> body = new Map<String, Object>(m.data);
        body.putAll(new Map<String, Object>{ 'ticket' => m.ticket, 'moment' => m.moment, 'at' => System.now() });
        check(send(withBody(request(s, 'POST', ''), body, JSON_TYPE)), o, 'Sent to your tracker');
    }

    /**
     * @description A ServiceNow change request's number, approval, state and planned window.
     * @param s the tracker
     * @param itemNo the change number
     * @return the record, or null when not found
     */
    public static Map<String, Object> changeRecord(RLY_Work_Tracker__c s, String itemNo) {
        return firstRecord(send(request(s, 'GET', '/api/now/table/change_request?sysparm_limit=1&sysparm_display_value=false'
            + '&sysparm_fields=number,approval,state,start_date,end_date,short_description,description&sysparm_query=number%3D' + EncodingUtil.urlEncode(itemNo, UTF8))));
    }

    /**
     * @description Test: one read that needs the tracker's sign-in (who am I, the work item types, one row of the table).
     * @param s the tracker
     * @param o the outcome to fill
     */
    public static void ping(RLY_Work_Tracker__c s, RlyWorkTypes.Outcome o) {
        if (s.Type__c == RlyWorkTracker.JIRA) {
            HttpResponse res = send(request(s, 'GET', '/rest/api/2/myself'));
            check(res, o, 'Signed in to Jira' + jiraUser(res) + '.');
        } else if (s.Type__c == RlyWorkTracker.AZURE) {
            check(send(request(s, 'GET', '/_apis/wit/workitemtypes?api-version=7.0')), o, 'Signed in to Azure Boards: work items can be read.');
        } else {
            String table = EncodingUtil.urlEncode(String.isBlank(s.ServiceNow_Table__c) ? 'change_request' : s.ServiceNow_Table__c.trim(), UTF8);
            check(send(request(s, 'GET', '/api/now/table/' + table + '?sysparm_limit=1&sysparm_fields=sys_id')), o,
                'Signed in to ServiceNow: ' + EncodingUtil.urlDecode(table, UTF8) + ' can be read.');
        }
    }

    // " as <name>" from Jira's /myself, or empty.
    private static String jiraUser(HttpResponse res) {
        try {
            Object body = JSON.deserializeUntyped(res.getBody());
            Object found = body instanceof Map<String, Object> ? ((Map<String, Object>) body).get('displayName') : null;
            return found == null ? '' : ' as ' + String.valueOf(found);
        } catch (Exception e) {
            return '';
        }
    }

    private static String transitionId(HttpResponse res, String name) {
        if (res.getStatusCode() != 200) {
            return null;
        }
        Object body = JSON.deserializeUntyped(res.getBody());
        Object found = body instanceof Map<String, Object> ? ((Map<String, Object>) body).get('transitions') : null;
        for (Object t : found instanceof List<Object> ? (List<Object>) found : new List<Object>()) {
            Map<String, Object> row = (Map<String, Object>) t;
            if (name.equalsIgnoreCase(String.valueOf(row.get('name')))) {
                return String.valueOf(row.get('id'));
            }
        }
        return null;
    }

    private static Map<String, Object> firstRecord(HttpResponse res) {
        if (res.getStatusCode() != 200) {
            return null;
        }
        Object body = JSON.deserializeUntyped(res.getBody());
        Object result = body instanceof Map<String, Object> ? ((Map<String, Object>) body).get('result') : null;
        List<Object> rows = result instanceof List<Object> ? (List<Object>) result : new List<Object>();
        return rows.isEmpty() ? null : (Map<String, Object>) rows[0];
    }

    private static void check(HttpResponse res, RlyWorkTypes.Outcome o, String okText) {
        Integer code = res.getStatusCode();
        o.ok = code >= 200 && code < 300;
        o.message = o.ok ? okText : ('The tracker answered ' + code + ': ' + String.valueOf(res.getBody()).left(180)).left(255);
    }

    private static HttpRequest request(RLY_Work_Tracker__c s, String method, String path) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + s.Named_Credential__c.trim() + path);
        req.setMethod(method);
        req.setHeader('Accept', JSON_TYPE);
        req.setTimeout(TIMEOUT_MS);
        return req;
    }

    private static HttpRequest withBody(HttpRequest req, Object body, String contentType) {
        req.setHeader('Content-Type', contentType);
        req.setBody(JSON.serialize(body));
        return req;
    }

    private static HttpResponse send(HttpRequest req) {
        return new Http().send(req);
    }
}
