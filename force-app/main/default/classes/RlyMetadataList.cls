/**
 * @description listMetadata read without building an XML document (RlyMetadata.listFiles). A Dom.Document of a large
 * answer (thousands of fields or list views) takes several times the answer's size in heap; scanning the text keeps
 * only the answer and one small piece per result: fullName, type, lastModifiedByName, lastModifiedDate, manageableState
 * and namespacePrefix. A SOAP fault or an answer that isn't a listMetadata answer is an error with the org's words.
 */
public with sharing class RlyMetadataList {

    private static final String OPERATION = 'listMetadata';
    private static final String RESULT_OPEN = '<result';
    private static final String RESULT_CLOSE = '</result>';

    /**
     * @description Sends one listMetadata call and reads its results.
     * @param org the registered org
     * @param payload the call's queries and asOfVersion
     * @return every component found (blank full names left out)
     */
    public static List<RlyMetadata.FileProp> call(RLY_Org__c org, String payload) {
        HttpResponse res = RlySoapClient.post(org, '<met:' + OPERATION + '>' + payload + '</met:' + OPERATION + '>');
        return read(org.Name, res.getStatusCode(), res.getBody());
    }

    /**
     * @description Reads a listMetadata answer.
     * @param orgName the org's name (for the errors)
     * @param status the HTTP status
     * @param body the answer
     * @return every component found (blank full names left out)
     */
    public static List<RlyMetadata.FileProp> read(String orgName, Integer status, String body) {
        String text = body == null ? '' : body;
        String fault = RlySoapClient.between(text, '<faultstring>', '</faultstring>');
        if (fault != null) {
            throw new RlyMetadata.MetadataException(orgName + ': ' + OPERATION + ' failed: ' + fault.unescapeXml());
        }
        if (!text.contains(OPERATION + 'Response')) {
            throw new RlyMetadata.MetadataException(orgName + ' answered HTTP ' + status + ' to ' + OPERATION + ': ' + text.left(300));
        }
        List<RlyMetadata.FileProp> out = new List<RlyMetadata.FileProp>();
        Integer pos = nextResult(text, 0);
        while (pos >= 0) {
            Integer close = text.indexOf(RESULT_CLOSE, pos);
            if (close < 0) {
                break;
            }
            RlyMetadata.FileProp f = toProp(text.substring(pos, close));
            if (String.isNotBlank(f.fullName)) {
                out.add(f);
            }
            pos = nextResult(text, close + RESULT_CLOSE.length());
        }
        return out;
    }

    // The next <result> or <result …> element from a position, or -1.
    private static Integer nextResult(String text, Integer fromPos) {
        Integer at = text.indexOf(RESULT_OPEN, fromPos);
        while (at >= 0) {
            String next = text.mid(at + RESULT_OPEN.length(), 1);
            if (next == '>' || next == ' ') {
                return at;
            }
            at = text.indexOf(RESULT_OPEN, at + RESULT_OPEN.length());
        }
        return -1;
    }

    private static RlyMetadata.FileProp toProp(String chunk) {
        RlyMetadata.FileProp f = new RlyMetadata.FileProp();
        f.fullName = valueOf(chunk, 'fullName');
        f.type = valueOf(chunk, 'type');
        f.lastModifiedByName = valueOf(chunk, 'lastModifiedByName');
        f.manageableState = valueOf(chunk, 'manageableState');
        f.namespacePrefix = valueOf(chunk, 'namespacePrefix');
        f.id = valueOf(chunk, 'id');
        String stamp = valueOf(chunk, 'lastModifiedDate');
        f.lastModifiedDate = String.isBlank(stamp) ? null : (Datetime) JSON.deserialize('"' + stamp + '"', Datetime.class);
        return f;
    }

    // An element's text, XML escapes undone; null when it's missing or empty (xsi:nil).
    private static String valueOf(String chunk, String name) {
        String v = RlySoapClient.between(chunk, '<' + name + '>', '</' + name + '>');
        return v == null ? null : v.unescapeXml();
    }
}
