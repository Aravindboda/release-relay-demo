/**
 * @description Metadata API retrieve of a release's components from a developer org (through RlySoapClient):
 *   start  starts the retrieve (one package, zip root = package.xml) and returns its id
 *   check  reads its status; when it's done, hands back the zip (base64) and any problems
 */
public with sharing class RlyRetrieve {

    /** @description Where a retrieve is. */
    public class RetrieveStatus {
        /** @description The retrieve has ended. */
        public Boolean done = false;
        /** @description It ended with status Succeeded. */
        public Boolean success = false;
        /** @description The zip, base64, when it succeeded. */
        public String zipBase64;
        /** @description fileName: problem, for each component that couldn't be retrieved. */
        public List<String> problems = new List<String>();
        /** @description The error message, when it failed. */
        public String message;
    }

    /**
     * @description package.xml types for a release: folder types (ReportFolder…) go under their item type, as package.xml expects.
     * @param byType component names by metadata type
     * @return component names by package.xml type
     */
    public static Map<String, Set<String>> packageTypes(Map<String, Set<String>> byType) {
        Map<String, String> folderOf = new Map<String, String>();
        for (String t : RlyMetadata.FOLDER_TYPE.keySet()) {
            folderOf.put(RlyMetadata.FOLDER_TYPE.get(t), t);
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

    /**
     * @description Starts a Metadata API retrieve of these components.
     * @param org the developer org
     * @param byType component names by metadata type
     * @return the retrieve's async id
     */
    public static String start(RLY_Org__c org, Map<String, Set<String>> byType) {
        Dom.XmlNode result = RlySoapClient.call(org, 'retrieve', '<met:retrieveRequest><met:apiVersion>' + RlyOrgSession.API_VERSION + '</met:apiVersion>'
            + '<met:singlePackage>true</met:singlePackage><met:unpackaged>' + unpackaged(byType)
            + '<met:version>' + RlyOrgSession.API_VERSION + '</met:version></met:unpackaged></met:retrieveRequest>');
        String asyncId = RlySoapClient.text(result, 'id');
        if (String.isBlank(asyncId)) {
            throw new RlyMetadata.MetadataException(org.Name + ' didn\'t start the retrieve.');
        }
        return asyncId;
    }

    // The package's types, sorted, each with its members sorted.
    private static String unpackaged(Map<String, Set<String>> byType) {
        Map<String, Set<String>> types = packageTypes(byType);
        List<String> names = new List<String>(types.keySet());
        names.sort();
        String xml = '';
        for (String t : names) {
            List<String> members = new List<String>(types.get(t));
            members.sort();
            xml += '<met:types>';
            for (String m : members) {
                xml += '<met:members>' + RlySoapClient.esc(m) + '</met:members>';
            }
            xml += '<met:name>' + RlySoapClient.esc(t) + '</met:name></met:types>';
        }
        return xml;
    }

    /**
     * @description Checks a retrieve; when it's done, hands back the zip (base64) and any problems.
     * The response is read as text, because the zip can be large.
     * @param org the developer org
     * @param asyncId the retrieve's async id
     * @return where the retrieve is
     */
    public static RetrieveStatus check(RLY_Org__c org, String asyncId) {
        HttpResponse res = RlySoapClient.post(org, '<met:checkRetrieveStatus><met:asyncProcessId>' + RlySoapClient.esc(asyncId)
            + '</met:asyncProcessId><met:includeZip>true</met:includeZip></met:checkRetrieveStatus>');
        String body = res.getBody();
        if (body == null || !body.contains('checkRetrieveStatusResponse')) {
            String fault = RlySoapClient.between(body, 'faultstring>', '</');
            throw new RlyMetadata.MetadataException(org.Name + ' answered HTTP ' + res.getStatusCode() + ' to checkRetrieveStatus: '
                + (String.isNotBlank(fault) ? fault : String.valueOf(body).left(300)));
        }
        return read(body);
    }

    private static RetrieveStatus read(String body) {
        RetrieveStatus st = new RetrieveStatus();
        String zip = RlySoapClient.between(body, '<zipFile>', '</zipFile>');
        // Take the zip out before reading the rest, so the small remainder is all that's searched.
        String rest = zip == null ? body : body.replace(zip, '');
        st.done = RlySoapClient.between(rest, '<done>', '</done>') == 'true';
        String status = RlySoapClient.between(rest, '<status>', '</status>');
        st.success = status == 'Succeeded';
        st.message = RlySoapClient.between(rest, '<errorMessage>', '</errorMessage>');
        st.problems = problems(rest);
        if (st.done && st.success) {
            st.zipBase64 = zip;
        }
        if (st.done && !st.success && String.isBlank(st.message)) {
            st.message = 'The retrieve ended with status ' + status + '.';
        }
        return st;
    }

    private static List<String> problems(String rest) {
        List<String> out = new List<String>();
        Integer at = rest.indexOf('<messages>');
        while (at >= 0) {
            Integer close = rest.indexOf('</messages>', at);
            String m = rest.substring(at, close < 0 ? rest.length() : close);
            out.add((RlySoapClient.between(m, '<fileName>', '</fileName>') + ': ' + RlySoapClient.between(m, '<problem>', '</problem>')).unescapeXml());
            at = close < 0 ? -1 : rest.indexOf('<messages>', close);
        }
        return out;
    }
}
