/**
 * @description With production approval on (RlyProdApproval's add-on setting), nobody approves their own release into
 * production (build 59, D19): the raiser is refused wherever a release is approved, and the page says why.
 */
public with sharing class RlyOwnRelease {

    /** @description What the person who raised a production release is told. */
    public static final String OWN_NOTE = 'You raised this release, so another approver approves it into production.';

    /**
     * @description Whether the user raised this production release while production approval is on.
     * @param rel the release, with CreatedById
     * @param userId who approves
     * @return true for the raiser
     */
    public static Boolean isOwnProduction(RLY_Release__c rel, Id userId) {
        if (rel == null || userId == null || !rel.getPopulatedFieldsAsMap().containsKey('CreatedById')) {
            return false;
        }
        return rel.CreatedById == userId && RlyProdApproval.needsAddon(rel);
    }

    /**
     * @description Throws when the approver raised this production release.
     * @param rel the release
     * @param who who approves
     */
    public static void require(RLY_Release__c rel, RlyApprover who) {
        if (who != null && isOwnProduction(rel, who.userId)) {
            throw new RlyReleaseException(OWN_NOTE);
        }
    }

    /**
     * @description The release page's note for the raiser of a production release.
     * @param rel the release
     * @return the note, or null
     */
    public static String noteFor(RLY_Release__c rel) {
        return isOwnProduction(rel, UserInfo.getUserId()) ? OWN_NOTE : null;
    }
}
