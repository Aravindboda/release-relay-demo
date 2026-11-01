/**
 * @description The rules a release request must meet before anything is called or saved: components selected (or, for a
 * release with only manual steps, at least one manual step),
 * a title, a source and target (RlyRaiseRoute: a developer org with its own branch, into the first stage), a checked Git connection, supported names,
 * and supported deletions (RlyDeletionRules). The test rule is RlyTestRule.
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
        if (req == null || (isEmpty(req.items) && isEmpty(req.deletions) && !hasSteps(req))) {
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
     * @description Whether the request has manual steps only: no components, no deletions and at least one manual step.
     * @param req the request
     * @return true for a manual-steps-only release
     */
    public static Boolean isManualOnly(RlyRaiseService.RaiseRequest req) {
        return req != null && isEmpty(req.items) && isEmpty(req.deletions) && hasSteps(req);
    }

    private static Boolean hasSteps(RlyRaiseService.RaiseRequest req) {
        return req.manualSteps != null && !req.manualSteps.isEmpty();
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

    /**
     * @description Refuses a component name the pipeline can't carry (commas and colons separate its lists).
     * @param i the component
     * @param source the developer org (for the message)
     */
    public static void checkName(RlyRaiseService.Item i, RLY_Org__c source) {
        if (String.isBlank(i.type) || String.isBlank(i.name) || i.name.contains(',') || i.name.contains(':') || i.type.contains(':')) {
            throw new RlyReleaseException('Can\'t release "' + i.name + '" from ' + source.Name + ': names with commas or colons aren\'t supported.');
        }
    }
}
