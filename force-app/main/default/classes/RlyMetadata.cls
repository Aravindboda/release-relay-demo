/**
 * The Metadata API (SOAP) of a registered org, called with the hub's own sign-in (RlyOrgSession).
 *   describe  every metadata type the org has, with child types (CustomField…) and folder types
 *   list      listMetadata for up to three queries per call
 */
public with sharing class RlyMetadata {

    public class MetadataException extends Exception {}

    private static final String MET = 'http://soap.sforce.com/2006/04/metadata';
    private static final String ENV = 'http://schemas.xmlsoap.org/soap/envelope/';
    public static final Integer QUERIES_PER_CALL = 3;

    /** Types listMetadata can't list, or that aren't release material. */
    private static final Set<String> SKIP = new Set<String>{
        'ApexTestSuite', 'Certificate', 'ConnectedApp', 'ExternalClientApplication', 'ExtlClntAppOauthSettings',
        'ExtlClntAppGlobalOauthSettings', 'ExtlClntAppOauthConfigurablePolicies', 'Index', 'InstalledPackage',
        'ManagedTopics', 'Package', 'Portal', 'SiteDotCom', 'Territory', 'Territory2Settings', 'Scontrol'
    };
    /** Folder types for the types that live in folders. */
    public static final Map<String, String> FOLDER_TYPE = new Map<String, String>{
        'Report' => 'ReportFolder', 'Dashboard' => 'DashboardFolder', 'EmailTemplate' => 'EmailFolder', 'Document' => 'DocumentFolder'
    };

    public class TypeList {
        @AuraEnabled public List<String> types = new List<String>();
        @AuraEnabled public List<String> folderTypes = new List<String>();
    }

    public class FileProp {
        public String fullName;
        public String type;
        public Datetime lastModifiedDate;
        public String lastModifiedByName;
        public String manageableState;
        public String namespacePrefix;
    }

    public class Query {
        public String type;
        public String folder;
        public Query(String type, String folder) {
            this.type = type;
            this.folder = folder;
        }
    }

    /** Every listable type, sorted, with child types; folder-based types apart. */
    public static TypeList describe(RLY_Org__c org) {
        Dom.XmlNode result = call(org, 'describeMetadata', '<met:asOfVersion>' + RlyOrgSession.API_VERSION + '</met:asOfVersion>');
        Set<String> names = new Set<String>();
        TypeList out = new TypeList();
        for (Dom.XmlNode obj : result.getChildElements()) {
            if (obj.getName() != 'metadataObjects') {
                continue;
            }
            String xmlName = text(obj, 'xmlName');
            if (String.isBlank(xmlName)) {
                continue;
            }
            if (text(obj, 'inFolder') == 'true' && FOLDER_TYPE.containsKey(xmlName)) {
                out.folderTypes.add(xmlName);
                continue;
            }
            names.add(xmlName);
            for (Dom.XmlNode child : obj.getChildElements()) {
                if (child.getName() == 'childXmlNames' && String.isNotBlank(child.getText())) {
                    names.add(child.getText());
                }
            }
        }
        for (String n : names) {
            if (!SKIP.contains(n) && !n.endsWith('Settings') && !FOLDER_TYPE.values().contains(n)) {
                out.types.add(n);
            }
        }
        out.types.sort();
        out.folderTypes.sort();
        return out;
    }

    /** listMetadata, three queries per call. */
    public static List<FileProp> listFiles(RLY_Org__c org, List<Query> queries) {
        List<FileProp> out = new List<FileProp>();
        for (Integer i = 0; i < queries.size(); i += QUERIES_PER_CALL) {
            String body = '';
            for (Integer j = i; j < Math.min(i + QUERIES_PER_CALL, queries.size()); j++) {
                Query q = queries[j];
                body += '<met:queries>' + (q.folder == null ? '' : '<met:folder>' + esc(q.folder) + '</met:folder>')
                    + '<met:type>' + esc(q.type) + '</met:type></met:queries>';
            }
            body += '<met:asOfVersion>' + RlyOrgSession.API_VERSION + '</met:asOfVersion>';
            Dom.XmlNode response = call(org, 'listMetadata', body);
            for (Dom.XmlNode r : response.getParent().getChildElements()) {
                if (r.getName() != 'result') {
                    continue;
                }
                FileProp f = new FileProp();
                f.fullName = text(r, 'fullName');
                f.type = text(r, 'type');
                f.lastModifiedByName = text(r, 'lastModifiedByName');
                f.manageableState = text(r, 'manageableState');
                f.namespacePrefix = text(r, 'namespacePrefix');
                String stamp = text(r, 'lastModifiedDate');
                f.lastModifiedDate = String.isBlank(stamp) ? null : (Datetime) JSON.deserialize('"' + stamp + '"', Datetime.class);
                if (String.isNotBlank(f.fullName)) {
                    out.add(f);
                }
            }
        }
        return out;
    }

    // ---------- retrieve ----------

    public class RetrieveStatus {
        public Boolean done = false;
        public Boolean success = false;
        public String zipBase64;
        public List<String> problems = new List<String>();
        public String message;
    }

    /** package.xml types for a release: folder types (ReportFolder…) go under their item type, as package.xml expects. */
    public static Map<String, Set<String>> packageTypes(Map<String, Set<String>> byType) {
        Map<String, String> folderOf = new Map<String, String>();
        for (String t : FOLDER_TYPE.keySet()) {
            folderOf.put(FOLDER_TYPE.get(t), t);
        }
        Map<String, Set<String>> out = new Map<String, Set<String>>();
        for (String t : byType.keySet()) {
            String name = folderOf.containsKey(t) ? folderOf.get(t) : t;
            if (!out.containsKey(name)) {
                out.put(name, new Set<String>());
            }
            out.get(name).addAll(byType.get(t));
        }
        return out;
    }

    /** Starts a Metadata API retrieve of these components (one package, zip root = package.xml). Returns its id. */
    public static String retrieve(RLY_Org__c org, Map<String, Set<String>> byType) {
        Map<String, Set<String>> types = packageTypes(byType);
        List<String> names = new List<String>(types.keySet());
        names.sort();
        String unpackaged = '';
        for (String t : names) {
            unpackaged += '<met:types>';
            List<String> members = new List<String>(types.get(t));
            members.sort();
            for (String m : members) {
                unpackaged += '<met:members>' + esc(m) + '</met:members>';
            }
            unpackaged += '<met:name>' + esc(t) + '</met:name></met:types>';
        }
        Dom.XmlNode result = call(org, 'retrieve', '<met:retrieveRequest><met:apiVersion>' + RlyOrgSession.API_VERSION + '</met:apiVersion>'
            + '<met:singlePackage>true</met:singlePackage><met:unpackaged>' + unpackaged
            + '<met:version>' + RlyOrgSession.API_VERSION + '</met:version></met:unpackaged></met:retrieveRequest>');
        String id = text(result, 'id');
        if (String.isBlank(id)) {
            throw new MetadataException(org.Name + ' didn\'t start the retrieve.');
        }
        return id;
    }

    /** Checks a retrieve; when it's done, hands back the zip (base64) and any problems. Read as text: the zip can be large. */
    public static RetrieveStatus checkRetrieve(RLY_Org__c org, String asyncId) {
        String envelope = '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="' + ENV + '" xmlns:met="' + MET + '">'
            + '<soapenv:Header><met:SessionHeader><met:sessionId>' + esc(RlyOrgSession.accessToken(org))
            + '</met:sessionId></met:SessionHeader></soapenv:Header>'
            + '<soapenv:Body><met:checkRetrieveStatus><met:asyncProcessId>' + esc(asyncId) + '</met:asyncProcessId>'
            + '<met:includeZip>true</met:includeZip></met:checkRetrieveStatus></soapenv:Body></soapenv:Envelope>';
        HttpResponse res = RlyOrgSession.send(org, 'POST', '/services/Soap/m/' + RlyOrgSession.API_VERSION, envelope,
            new Map<String, String>{ 'Content-Type' => 'text/xml; charset=UTF-8', 'SOAPAction' => '""' });
        String body = res.getBody();
        RetrieveStatus st = new RetrieveStatus();
        if (body == null || !body.contains('checkRetrieveStatusResponse')) {
            String fault = between(body, 'faultstring>', '</');
            throw new MetadataException(org.Name + ' answered HTTP ' + res.getStatusCode() + ' to checkRetrieveStatus: '
                + (String.isNotBlank(fault) ? fault : String.valueOf(body).left(300)));
        }
        String zip = between(body, '<zipFile>', '</zipFile>');
        // Take the zip out before reading the rest, so the small remainder is all that's searched.
        String rest = zip == null ? body : body.replace(zip, '');
        st.done = between(rest, '<done>', '</done>') == 'true';
        String status = between(rest, '<status>', '</status>');
        st.success = status == 'Succeeded';
        st.message = between(rest, '<errorMessage>', '</errorMessage>');
        Integer at = 0;
        while (true) {
            Integer open = rest.indexOf('<messages>', at);
            if (open < 0) {
                break;
            }
            Integer close = rest.indexOf('</messages>', open);
            String m = rest.substring(open, close < 0 ? rest.length() : close);
            st.problems.add((between(m, '<fileName>', '</fileName>') + ': ' + between(m, '<problem>', '</problem>')).unescapeXml());
            at = close < 0 ? rest.length() : close;
        }
        if (st.done && st.success) {
            st.zipBase64 = zip;
        }
        if (st.done && !st.success && String.isBlank(st.message)) {
            st.message = 'The retrieve ended with status ' + status + '.';
        }
        return st;
    }

    private static String between(String s, String startTag, String endTag) {
        if (s == null) {
            return null;
        }
        Integer i = s.indexOf(startTag);
        if (i < 0) {
            return null;
        }
        Integer j = s.indexOf(endTag, i + startTag.length());
        return j < 0 ? null : s.substring(i + startTag.length(), j);
    }

    /** Sends one call and returns its first result element (or the response element when there are none). */
    private static Dom.XmlNode call(RLY_Org__c org, String operation, String payload) {
        String envelope = '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="' + ENV + '" xmlns:met="' + MET + '">'
            + '<soapenv:Header><met:SessionHeader><met:sessionId>' + esc(RlyOrgSession.accessToken(org))
            + '</met:sessionId></met:SessionHeader></soapenv:Header>'
            + '<soapenv:Body><met:' + operation + '>' + payload + '</met:' + operation + '></soapenv:Body></soapenv:Envelope>';
        HttpResponse res = RlyOrgSession.send(org, 'POST', '/services/Soap/m/' + RlyOrgSession.API_VERSION, envelope,
            new Map<String, String>{ 'Content-Type' => 'text/xml; charset=UTF-8', 'SOAPAction' => '""' });
        Dom.Document doc = new Dom.Document();
        try {
            doc.load(res.getBody());
        } catch (Exception e) {
            throw new MetadataException(org.Name + ' answered HTTP ' + res.getStatusCode() + ' to ' + operation + ': '
                + String.valueOf(res.getBody()).left(300));
        }
        Dom.XmlNode body = doc.getRootElement().getChildElement('Body', ENV);
        Dom.XmlNode fault = body.getChildElement('Fault', ENV);
        if (fault != null) {
            String reason = 'no reason given';
            for (Dom.XmlNode f : fault.getChildElements()) {
                if (f.getName() == 'faultstring') {
                    reason = f.getText();
                }
            }
            throw new MetadataException(org.Name + ': ' + operation + ' failed: ' + reason);
        }
        Dom.XmlNode response = body.getChildElement(operation + 'Response', MET);
        Dom.XmlNode firstResult = response == null ? null : response.getChildElement('result', MET);
        if (firstResult == null) {
            // listMetadata with no matches returns an empty response: hand back a stand-in whose parent is the response.
            Dom.Document empty = new Dom.Document();
            Dom.XmlNode root = empty.createRootElement('response', MET, null);
            return root.addChildElement('result', MET, null);
        }
        return firstResult;
    }

    private static String text(Dom.XmlNode node, String name) {
        Dom.XmlNode child = node.getChildElement(name, MET);
        return child == null ? null : child.getText();
    }

    public static String esc(String value) {
        return value == null ? '' : value.escapeXml();
    }
}
