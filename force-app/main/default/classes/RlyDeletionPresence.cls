/**
 * @description Find deleted components, the org side, one type per call (RlyChangePartsController): the full names of
 * every component of a type in the developer org, managed ones included, lower case. listMetadata is read by
 * scanning its text (RlyMetadataList); custom fields can also be read a page at a time through the Tooling API
 * (RlyFieldPages) when listMetadata of CustomField fails or its answer is too large. The page compares these names
 * with the components on the branch (RlyDeletionPlan).
 */
public with sharing class RlyDeletionPresence {

    private static final Pattern TYPE_NAME = Pattern.compile('^[A-Za-z][A-Za-z0-9]{1,79}$');

    /** @description The names of one type in the org (or one page of custom fields). */
    public class Presence {
        /** @description The type. */
        @AuraEnabled public String type;
        /** @description Full names, lower case. */
        @AuraEnabled public List<String> names = new List<String>();
        /** @description Custom fields read through the Tooling API: the next page's cursor, or null after the last. */
        @AuraEnabled public String nextCursor;
    }

    /**
     * @description Every component of one type in the org (listMetadata).
     * @param org the developer org
     * @param type the metadata type
     * @return the names
     */
    public static Presence names(RLY_Org__c org, String type) {
        if (String.isBlank(type) || !TYPE_NAME.matcher(type).matches()) {
            throw new RlyReleaseException('"' + type + '" isn\'t a metadata type.');
        }
        Presence p = new Presence();
        p.type = type;
        for (RlyMetadata.FileProp f : RlyMetadata.listFiles(org, new List<RlyMetadata.Query>{ new RlyMetadata.Query(type, null) })) {
            p.names.add(f.fullName.toLowerCase());
        }
        return p;
    }

    /**
     * @description One page of the org's custom fields through the Tooling API, managed ones included.
     * @param org the developer org
     * @param cursor the page to read, or blank for the first
     * @return the names and the next page's cursor
     */
    public static Presence fields(RLY_Org__c org, String cursor) {
        RlyFieldPages.Batch b = RlyFieldPages.every(org, cursor);
        Presence p = new Presence();
        p.type = 'CustomField';
        for (RlyFieldPages.Field f : b.fields) {
            p.names.add(f.fullName.toLowerCase());
        }
        p.nextCursor = b.nextCursor;
        return p;
    }
}
