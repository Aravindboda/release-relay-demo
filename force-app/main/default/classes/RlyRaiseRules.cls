/**
 * @description The rules a release request must meet before anything is called or saved: components selected,
 * a title, a source and target (RlyRaiseRoute: a developer org with its own branch, or a stage org for a hotfix), a checked Git connection, supported names,
 * and no deletions yet. The test rule is RlyTestRule.
 */
public with sharing class RlyRaiseRules {

    /** @description Where a release goes: its source org, its target (RlyRaiseRoute) and the Git connection. */
    public class Route {
        /** @description The developer org, or the stage org of a hotfix. */
        public RLY_Org__c source;
        /** @description The first stage, or a hotfix's next stop. */
        public RLY_Org__c target;
        /** @description The hub's Git connection. */
        public RLY_Git_Connection__c git;
    }

    /**
     * @description Checks the request has components and a title.
     * @param req the request
     */
    public static void checkRequest(RlyRaiseService.RaiseRequest req) {
        if (req == null || req.items == null || req.items.isEmpty()) {
            throw new RlyReleaseException('Select at least one component.');
        }
        if (String.isBlank(req.title) || req.title.trim().length() > 200) {
            throw new RlyReleaseException('Give the release a title (up to 200 characters).');
        }
    }

    /**
     * @description The source org, its target (first stage, or a hotfix's next stop) and the Git connection, each checked.
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
     * @description The components by type; refuses names the pipeline can't carry and deleted components.
     * @param items the selected components
     * @param source the developer org (for the message)
     * @return component names by metadata type
     */
    public static Map<String, Set<String>> byType(List<RlyRaiseService.Item> items, RLY_Org__c source) {
        Map<String, Set<String>> out = new Map<String, Set<String>>();
        for (RlyRaiseService.Item i : items) {
            checkItem(i, source);
            if (!out.containsKey(i.type)) {
                out.put(i.type, new Set<String>());
            }
            out.get(i.type).add(i.name);
        }
        return out;
    }

    private static void checkItem(RlyRaiseService.Item i, RLY_Org__c source) {
        if (String.isBlank(i.type) || String.isBlank(i.name) || i.name.contains(',') || i.name.contains(':')) {
            throw new RlyReleaseException('Can\'t release "' + i.name + '": names with commas or colons aren\'t supported.');
        }
        if (i.deleted == true) {
            throw new RlyReleaseException(i.name + ' was deleted in ' + source.Name + '. Deletions come in a later build: leave it out for now.');
        }
    }
}
