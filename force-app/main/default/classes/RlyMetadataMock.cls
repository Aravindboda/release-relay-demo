/**
 * @description Plays a developer org for the change-listing tests: the Metadata API (describeMetadata and
 * listMetadata from the components added) and the REST/Tooling queries (SourceMember, User, ApexClass).
 * fault answers with a SOAP fault; garbage answers with something that isn't XML.
 */
@IsTest
public with sharing class RlyMetadataMock implements HttpCalloutMock {

    /** @description The user who changed the tracked components. */
    public static final String USER_ID = RlyTestData.fakeId('005', 1);

    /** @description Answer SOAP calls with a fault. */
    public Boolean fault = false;
    /** @description Answer SOAP calls with something that isn't XML. */
    public Boolean garbage = false;

    private static final String SOAP_HEAD = '<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope '
        + 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body>';
    private static final String SOAP_TAIL = '</soapenv:Body></soapenv:Envelope>';
    private static final Pattern QUERY = Pattern.compile('<met:queries>(?:<met:folder>([^<]*)</met:folder>)?<met:type>([^<]*)</met:type></met:queries>');

    // type, or type/folder => rows of { fullName, lastModifiedDate, manageableState, namespacePrefix }
    private Map<String, List<List<String>>> items = new Map<String, List<List<String>>>();

    /**
     * @description Adds an unmanaged component to listMetadata's answers.
     * @param key the type, or type/folder
     * @param fullName the component
     * @param modified its last change (ISO)
     * @return this mock
     */
    public RlyMetadataMock add(String key, String fullName, String modified) {
        return addRow(key, new List<String>{ fullName, modified, 'unmanaged', null });
    }

    /**
     * @description Adds a managed-package component (namespace pkg) to listMetadata's answers.
     * @param key the type, or type/folder
     * @param fullName the component
     * @param modified its last change (ISO)
     * @return this mock
     */
    public RlyMetadataMock addManaged(String key, String fullName, String modified) {
        return addRow(key, new List<String>{ fullName, modified, 'installed', 'pkg' });
    }

    private RlyMetadataMock addRow(String key, List<String> row) {
        if (!items.containsKey(key)) {
            items.put(key, new List<List<String>>());
        }
        items.get(key).add(row);
        return this;
    }

    /**
     * @description Answers like the developer org.
     * @param req the request
     * @return the answer
     */
    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        String url = EncodingUtil.urlDecode(req.getEndpoint(), 'UTF-8');
        if (url.contains('/services/Soap/m/')) {
            res.setHeader('Content-Type', 'text/xml');
            res.setStatusCode(fault || garbage ? 500 : 200);
            res.setBody(soap(req.getBody()));
            return res;
        }
        res.setHeader('Content-Type', 'application/json');
        String body = query(url);
        res.setStatusCode(body == null ? 404 : 200);
        res.setBody(body == null ? '[]' : body);
        return res;
    }

    private String query(String url) {
        if (url.contains('FROM SourceMember')) {
            return '{"records":['
                + '{"MemberName":"AccountService","MemberType":"ApexClass","IsNameObsolete":false,"LastModifiedDate":"2026-10-30T10:00:00.000+0000","LastModifiedById":"' + USER_ID + '"},'
                + '{"MemberName":"Account.Industry","MemberType":"CustomField","IsNameObsolete":false,"LastModifiedDate":"2026-10-29T10:00:00.000+0000","LastModifiedById":"' + USER_ID + '"},'
                + '{"MemberName":"OldPage","MemberType":"ApexPage","IsNameObsolete":true,"LastModifiedDate":"2026-10-28T10:00:00.000+0000","LastModifiedById":null}]}';
        }
        if (url.contains('FROM User')) {
            return '{"records":[{"Id":"' + USER_ID + '","Name":"Dev One"}]}';
        }
        if (url.contains('FROM ApexClass')) {
            return '{"records":['
                + '{"Name":"AccountService","Body":"public with sharing class AccountService { }"},'
                + '{"Name":"AccountServiceTest","Body":"@IsTest\\nprivate class AccountServiceTest { }"},'
                + '{"Name":"Helper","Body":"@isTest\\npublic class Helper { }"}]}';
        }
        return null;
    }

    private String soap(String body) {
        if (garbage) {
            return '<html>Service unavailable';
        }
        if (fault) {
            return SOAP_HEAD + '<soapenv:Fault><faultcode>sf:INVALID_SESSION_ID</faultcode><faultstring>Invalid Session ID</faultstring></soapenv:Fault>' + SOAP_TAIL;
        }
        if (body.contains('<met:describeMetadata>')) {
            return SOAP_HEAD + '<describeMetadataResponse><result>'
                + mdo('ApexClass', 'false', null) + mdo('CustomObject', 'false', 'CustomField') + mdo('ConnectedApp', 'false', null)
                + mdo('AccountSettings', 'false', null) + mdo('Report', 'true', null) + mdo('ReportFolder', 'false', null)
                + '<organizationNamespace></organizationNamespace></result></describeMetadataResponse>' + SOAP_TAIL;
        }
        return SOAP_HEAD + '<listMetadataResponse>' + listResults(body) + '</listMetadataResponse>' + SOAP_TAIL;
    }

    private String listResults(String body) {
        String out = '';
        Matcher m = QUERY.matcher(body);
        while (m.find()) {
            String key = m.group(1) == null ? m.group(2) : m.group(2) + '/' + m.group(1);
            for (List<String> row : items.containsKey(key) ? items.get(key) : new List<List<String>>()) {
                out += '<result><fullName>' + row[0] + '</fullName><lastModifiedByName>Dev One</lastModifiedByName>'
                    + '<lastModifiedDate>' + row[1] + '</lastModifiedDate><manageableState>' + row[2] + '</manageableState>'
                    + (row[3] == null ? '' : '<namespacePrefix>' + row[3] + '</namespacePrefix>')
                    + '<type>' + m.group(2) + '</type></result>';
            }
        }
        return out;
    }

    private String mdo(String name, String inFolder, String child) {
        return '<metadataObjects>' + (child == null ? '' : '<childXmlNames>' + child + '</childXmlNames>')
            + '<inFolder>' + inFolder + '</inFolder><xmlName>' + name + '</xmlName></metadataObjects>';
    }
}
