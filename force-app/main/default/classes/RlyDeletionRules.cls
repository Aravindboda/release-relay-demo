/**
 * @description The rules for a release's deletions: the request's deletions and its items flagged deleted are the
 * deletions (Type:Name, each once); a component can't be both added and deleted; names must be ones the pipeline can
 * carry; and they must fit in Deletions__c.
 */
public with sharing class RlyDeletionRules {

    /**
     * @description The components to add: the selected items not flagged deleted.
     * @param req the checked request
     * @return the items
     */
    public static List<RlyRaiseService.Item> added(RlyRaiseService.RaiseRequest req) {
        List<RlyRaiseService.Item> out = new List<RlyRaiseService.Item>();
        for (RlyRaiseService.Item i : orEmpty(req.items)) {
            if (i != null && i.deleted != true) {
                out.add(i);
            }
        }
        return out;
    }

    /**
     * @description The components to delete, as Type:Name, each once: the deletions and the items flagged deleted.
     * Refuses names the pipeline can't carry, a component both added and deleted, and more than Deletions__c holds.
     * @param req the checked request
     * @param source the developer org (for the message)
     * @return Type:Name of each
     */
    public static List<String> deletions(RlyRaiseService.RaiseRequest req, RLY_Org__c source) {
        Set<String> addedKeys = new Set<String>();
        for (RlyRaiseService.Item i : added(req)) {
            addedKeys.add(i.type + ':' + i.name);
        }
        List<String> out = new List<String>();
        for (RlyRaiseService.Item d : requested(req)) {
            String key = deletionKey(d, source);
            if (addedKeys.contains(key)) {
                throw new RlyReleaseException(d.type.trim() + ' ' + d.name.trim() + ' is both added and deleted.');
            }
            if (!out.contains(key)) {
                out.add(key);
            }
        }
        if (String.join(out, ',').length() > RlyDeletions.MAX_LENGTH) {
            throw new RlyReleaseException('Too many deletions for one release: split them into two releases.');
        }
        return out;
    }

    // The deletions, then the items flagged deleted.
    private static List<RlyRaiseService.Item> requested(RlyRaiseService.RaiseRequest req) {
        List<RlyRaiseService.Item> out = new List<RlyRaiseService.Item>(orEmpty(req.deletions));
        for (RlyRaiseService.Item i : orEmpty(req.items)) {
            if (i != null && i.deleted == true) {
                out.add(i);
            }
        }
        return out;
    }

    private static List<RlyRaiseService.Item> orEmpty(List<RlyRaiseService.Item> items) {
        return items == null ? new List<RlyRaiseService.Item>() : items;
    }

    private static String deletionKey(RlyRaiseService.Item d, RLY_Org__c source) {
        if (d == null || String.isBlank(d.type) || String.isBlank(d.name)) {
            throw new RlyReleaseException('Give each deletion a type and a name.');
        }
        RlyRaiseRules.checkName(d, source);
        return d.type.trim() + ':' + d.name.trim();
    }
}
