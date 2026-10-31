/**
 * @description The Metadata API types and listings of a registered org (through RlySoapClient):
 *   describe   every metadata type the org has, with child types (CustomField…) and folder types
 *   listFiles  listMetadata, up to three queries per call
 * Retrieving components is in RlyRetrieve.
 */
public with sharing class RlyMetadata {

    /** @description Queries per listMetadata call (the API's limit). */
    public static final Integer QUERIES_PER_CALL = 3;

    /** @description Folder types for the types that live in folders. */
    public static final Map<String, String> FOLDER_TYPE = new Map<String, String>{
        'Report' => 'ReportFolder', 'Dashboard' => 'DashboardFolder', 'EmailTemplate' => 'EmailFolder', 'Document' => 'DocumentFolder'
    };

    // Types listMetadata can't list, or that aren't release material.
    private static final Set<String> SKIP = new Set<String>{
        'ApexTestSuite', 'Certificate', 'ConnectedApp', 'ExternalClientApplication', 'ExtlClntAppOauthSettings',
        'ExtlClntAppGlobalOauthSettings', 'ExtlClntAppOauthConfigurablePolicies', 'Index', 'InstalledPackage',
        'ManagedTopics', 'Package', 'Portal', 'SiteDotCom', 'Territory', 'Territory2Settings', 'Scontrol'
    };

    /** @description The org answered with an error, or something it can't do. */
    public class MetadataException extends Exception {}

    /** @description The types the page can list: plain types, and folder-based types apart. */
    public class TypeList {
        /** @description Listable types, sorted. */
        @AuraEnabled public List<String> types = new List<String>();
        /** @description Types that live in folders (Report…), sorted. */
        @AuraEnabled public List<String> folderTypes = new List<String>();
    }

    /** @description One listMetadata result. */
    public class FileProp {
        /** @description Full name. */
        public String fullName;
        /** @description Metadata type. */
        public String type;
        /** @description Last change. */
        public Datetime lastModifiedDate;
        /** @description Who changed it last. */
        public String lastModifiedByName;
        /** @description unmanaged, installed… */
        public String manageableState;
        /** @description Namespace of a managed component. */
        public String namespacePrefix;
    }

    /** @description One listMetadata query: a type, and a folder for folder-based types. */
    public class Query {
        /** @description Metadata type. */
        public String type;
        /** @description Folder, or null. */
        public String folder;

        /**
         * @description A query.
         * @param type the metadata type
         * @param folder the folder, or null
         */
        public Query(String type, String folder) {
            this.type = type;
            this.folder = folder;
        }
    }

    /**
     * @description Every listable type, sorted, with child types; folder-based types apart.
     * @param org the registered org
     * @return the types
     */
    public static TypeList describe(RLY_Org__c org) {
        Dom.XmlNode result = RlySoapClient.call(org, 'describeMetadata', '<met:asOfVersion>' + RlyOrgSession.API_VERSION + '</met:asOfVersion>');
        Set<String> names = new Set<String>();
        TypeList out = new TypeList();
        for (Dom.XmlNode obj : result.getChildElements()) {
            if (obj.getName() == 'metadataObjects') {
                addType(obj, names, out);
            }
        }
        for (String n : names) {
            if (isListable(n)) {
                out.types.add(n);
            }
        }
        out.types.sort();
        out.folderTypes.sort();
        return out;
    }

    private static void addType(Dom.XmlNode obj, Set<String> names, TypeList out) {
        String xmlName = RlySoapClient.text(obj, 'xmlName');
        if (String.isBlank(xmlName)) {
            return;
        }
        if (RlySoapClient.text(obj, 'inFolder') == 'true' && FOLDER_TYPE.containsKey(xmlName)) {
            out.folderTypes.add(xmlName);
            return;
        }
        names.add(xmlName);
        for (Dom.XmlNode child : obj.getChildElements()) {
            if (child.getName() == 'childXmlNames' && String.isNotBlank(child.getText())) {
                names.add(child.getText());
            }
        }
    }

    private static Boolean isListable(String typeName) {
        return !SKIP.contains(typeName) && !typeName.endsWith('Settings') && !FOLDER_TYPE.values().contains(typeName);
    }

    /**
     * @description listMetadata, three queries per call.
     * @param org the registered org
     * @param queries the queries
     * @return every component found
     */
    public static List<FileProp> listFiles(RLY_Org__c org, List<Query> queries) {
        List<FileProp> out = new List<FileProp>();
        for (Integer i = 0; i < queries.size(); i += QUERIES_PER_CALL) {
            Dom.XmlNode response = RlySoapClient.call(org, 'listMetadata', queryXml(queries, i));
            for (Dom.XmlNode r : response.getParent().getChildElements()) {
                FileProp f = r.getName() == 'result' ? toFileProp(r) : null;
                if (f != null && String.isNotBlank(f.fullName)) {
                    out.add(f);
                }
            }
        }
        return out;
    }

    // The queries of one call: up to QUERIES_PER_CALL from position offset.
    private static String queryXml(List<Query> queries, Integer offset) {
        String body = '';
        for (Integer j = offset; j < Math.min(offset + QUERIES_PER_CALL, queries.size()); j++) {
            Query q = queries[j];
            body += '<met:queries>' + (q.folder == null ? '' : '<met:folder>' + RlySoapClient.esc(q.folder) + '</met:folder>')
                + '<met:type>' + RlySoapClient.esc(q.type) + '</met:type></met:queries>';
        }
        return body + '<met:asOfVersion>' + RlyOrgSession.API_VERSION + '</met:asOfVersion>';
    }

    private static FileProp toFileProp(Dom.XmlNode r) {
        FileProp f = new FileProp();
        f.fullName = RlySoapClient.text(r, 'fullName');
        f.type = RlySoapClient.text(r, 'type');
        f.lastModifiedByName = RlySoapClient.text(r, 'lastModifiedByName');
        f.manageableState = RlySoapClient.text(r, 'manageableState');
        f.namespacePrefix = RlySoapClient.text(r, 'namespacePrefix');
        String stamp = RlySoapClient.text(r, 'lastModifiedDate');
        f.lastModifiedDate = String.isBlank(stamp) ? null : (Datetime) JSON.deserialize('"' + stamp + '"', Datetime.class);
        return f;
    }
}
