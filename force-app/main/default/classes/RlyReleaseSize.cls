/**
 * @description How big one release can be (build 37). A release's components go to the pipeline as one list of names
 * (the workflow input holds 60,000 characters) and are saved as items in one go, so a release past these limits is
 * refused with a clear message instead of being cut short: split it into several releases. Adding changes to an open
 * release is one retrieve (not in parts), so an add takes at most MAX_ADD components.
 */
public with sharing class RlyReleaseSize {

    /** @description Most components in one release. */
    public static final Integer MAX_COMPONENTS = 2000;
    /** @description Most deletions in one release. */
    public static final Integer MAX_DELETIONS = 500;
    /** @description Most characters of the list of names the pipeline takes (Type:Name, comma between). */
    public static final Integer MAX_INPUT = 60000;
    /** @description Most components one add to an open release takes. */
    public static final Integer MAX_ADD = 100;

    /**
     * @description Checks a new release.
     * @param req the request
     */
    public static void checkRaise(RlyRaiseService.RaiseRequest req) {
        check(keysOf(req == null ? null : req.items), keysOf(req == null ? null : req.deletions), 0);
    }

    /**
     * @description Checks an add to an open release.
     * @param inRelease how many components and deletions the release has
     * @param added the new components
     * @param deletions the new deletions (Type:Name)
     */
    public static void checkAdd(Integer inRelease, List<RlyRaiseService.Item> added, List<String> deletions) {
        List<String> keys = keysOf(added);
        if (keys.size() > MAX_ADD) {
            throw new RlyReleaseException('An add takes at most ' + MAX_ADD + ' components (this one has ' + keys.size()
                + '): add them in a few goes, or raise a new release.');
        }
        check(keys, deletions == null ? new List<String>() : deletions, inRelease == null ? 0 : inRelease);
    }

    // The counts and the length of the names' list, with the release's own count for an add.
    private static void check(List<String> components, List<String> deletions, Integer already) {
        if (components.size() + already > MAX_COMPONENTS) {
            throw new RlyReleaseException('A release takes at most ' + MAX_COMPONENTS.format() + ' components (this one would have '
                + (components.size() + already).format() + '): split the release.');
        }
        if (deletions.size() > MAX_DELETIONS) {
            throw new RlyReleaseException('A release takes at most ' + MAX_DELETIONS + ' deletions (this one has ' + deletions.size()
                + '): split the release.');
        }
        Integer chars = String.join(components, ',').length();
        Integer deletionChars = String.join(deletions, ',').length();
        if (chars > MAX_INPUT || deletionChars > MAX_INPUT) {
            throw new RlyReleaseException('The list of names is too long for one pipeline run (' + Math.max(chars, deletionChars).format()
                + ' characters, the most is ' + MAX_INPUT.format() + '): split the release.');
        }
    }

    private static List<String> keysOf(List<RlyRaiseService.Item> items) {
        List<String> out = new List<String>();
        for (RlyRaiseService.Item i : items == null ? new List<RlyRaiseService.Item>() : items) {
            out.add(i == null ? '' : i.type + ':' + i.name);
        }
        return out;
    }
}
