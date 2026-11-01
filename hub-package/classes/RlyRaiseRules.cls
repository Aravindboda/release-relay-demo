/**
 * @description The rules a release request must meet before anything is called or saved: components selected,
 * a title, a source and target (RlyRaiseRoute: a developer org with its own branch, into the first stage), a checked Git connection, supported names,
 * and deletions that aren't also added. Items flagged deleted count as deletions. The test rule is RlyTestRule.
 */
public with sharing class RlyRaiseRules {

    /** @description Where a release goes: its source org, its target (RlyRaiseRoute) and the Git connection. */
    public class Route {
        /** @description The developer org. */
        public RLY_Org__c source;
        /** @description The first stage. */
        public RLY_Org__c target;
        /** @description The hub's Git connection. */
        public RLY_Git_Connection__c git;
    }

    /**
     * @description Checks the request has components or deletions, and a title.
     * @param req the request
     */
    public static void checkRequest(RlyRaiseService.RaiseRequest req) {
        if (req == null || (isEmpty(req.items) && isEmpty(req.deletions))) {
            throw new RlyReleaseException('Select at least one component.');
        }
        if (String.isBlank(req.title) || req.title.trim().length() > 200) {
            throw new RlyReleaseException('Give the release a title (up to 200 characters).');
        }
    }

    private static Boolean isEmpty(List<RlyRaiseService.Item> items) {
        return items == null || items.isEmpty();
    }

    /**
     * @description The components to add: the selected items not flagged deleted.
     * @param req the checked request
     * @return the items
     */
    public static List<RlyRaiseService.Item> added(RlyRaiseService.RaiseRequest req) {
        List<RlyRaiseService.Item> out = new List<RlyRaiseService.Item>();
        for (RlyRaiseService.Item i : req.items == null ? new List<RlyRaiseService.Item>() : req.items) {
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
        List<RlyRaiseService.Item> all = new List<RlyRaiseService.Item>();
        all.addAll(req.deletions == null ? new List<RlyRaiseService.Item>() : req.deletions);
        for (RlyRaiseService.Item i : req.items == null ? new List<RlyRaiseService.Item>() : req.items) {
            if (i != null && i.deleted == true) {
                all.add(i);
            }
        }
        Set<String> addedKeys = new Set<String>();
        for (RlyRaiseService.Item i : added(req)) {
            addedKeys.add(i.type + ':' + i.name);
        }
        List<String> out = new List<String>();
        for (RlyRaiseService.Item d : all) {
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

    private static String deletionKey(RlyRaiseService.Item d, RLY_Org__c source) {
        if (d == null || String.isBlank(d.type) || String.isBlank(d.name)) {
            throw new RlyReleaseException('Give each deletion a type and a name.');
        }
        checkName(d, source);
        return d.type.trim() + ':' + d.name.trim();
    }

    /**
     * @description The source org, its target (the first stage) and the Git connection, each checked.
     * @param sourceOrgId the developer org
     * @return the route
     */
    public static Route route(Id sourceOrgId) {
        Route r = new Route();
        r.source = RlyRaiseRoute.source(sourceOrgId);
        r.target = RlyRaiseRoute.target(r.source);
        r.git = git();
        return r;
    }

    private static RLY_Git_Connection__c git() {
        RLY_Git_Connection__c git = RlyReleaseStore.git();
        if (git == null || git.Status__c != 'Connected') {
            throw new RlyReleaseException('The Git connection isn\'t set up and checked yet (Pipeline tab).');
        }
        return git;
    }

    /**
     * @description The components by type; refuses names the pipeline can't carry.
     * @param items the selected components
     * @param source the developer org (for the message)
     * @return component names by metadata type
     */
    public static Map<String, Set<String>> byType(List<RlyRaiseService.Item> items, RLY_Org__c source) {
        Map<String, Set<String>> out = new Map<String, Set<String>>();
        for (RlyRaiseService.Item i : items) {
            checkName(i, source);
            if (!out.containsKey(i.type)) {
                out.put(i.type, new Set<String>());
            }
            out.get(i.type).add(i.name);
        }
        return out;
    }

    private static void checkName(RlyRaiseService.Item i, RLY_Org__c source) {
        if (String.isBlank(i.type) || String.isBlank(i.name) || i.name.contains(',') || i.name.contains(':') || i.type.contains(':')) {
            throw new RlyReleaseException('Can\'t release "' + i.name + '" from ' + source.Name + ': names with commas or colons aren\'t supported.');
        }
    }
}
