/**
 * @description The Credentials dashboard for the pages (build 49; rows from RlyCredentialViews): the Pipeline tab's Credentials card (every row, with
 * how to renew each kind; admins press Check now) and the Home tab's tile (what needs attention, or "All credentials
 * OK"). Check now runs the same pass as the nightly call: callouts first, then the rows are saved.
 */
public with sharing class RlyCredentialController {

    /** @description The Pipeline tab's card. */
    public class Board {
        /** @description Every row, worst first. */
        @AuraEnabled public List<RlyCredentialViews.Row> rows = new List<RlyCredentialViews.Row>();
        /** @description The newest check. */
        @AuraEnabled public Datetime checkedOn;
        /** @description Rows per status. */
        @AuraEnabled public Map<String, Integer> counts = new Map<String, Integer>();
        /** @description The viewer may press Check now (admins, in the hub). */
        @AuraEnabled public Boolean canCheck = false;
        /** @description What the last Check now did, or null. */
        @AuraEnabled public String message;
    }

    /** @description The Home tab's tile. */
    public class Tile {
        /** @description What needs attention (Expiring, Critical, Expired, Failed), worst first. */
        @AuraEnabled public List<RlyCredentialViews.Row> problems = new List<RlyCredentialViews.Row>();
        /** @description How many rows there are. */
        @AuraEnabled public Integer total = 0;
        /** @description The newest check, or null before the first one. */
        @AuraEnabled public Datetime checkedOn;
        /** @description The viewer is an admin (the tile links to the Pipeline tab). */
        @AuraEnabled public Boolean isAdmin = false;
    }

    /**
     * @description The Credentials card.
     * @return the board
     */
    @AuraEnabled
    public static Board board() {
        try {
            return read();
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Checks every credential now (admins): callouts first, then the rows are saved.
     * @return the board, with what the pass did
     */
    @AuraEnabled
    public static Board checkNow() {
        try {
            RlyHubGuard.requireHub();
            if (!RlyOrgController.isAdmin()) {
                throw new RlyReleaseException('Only a Release Relay admin can check the credentials.');
            }
            RlyCredentialCheck.Pass p = RlyCredentialCheck.gather();
            RlyCredentialCheck.save(p);
            Board b = read();
            b.message = 'Checked: ' + RlyCredentialCheck.summary(p) + '.';
            return b;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description The Home tab's tile.
     * @return the tile
     */
    @AuraEnabled
    public static Tile tile() {
        try {
            Tile t = new Tile();
            t.isAdmin = RlyOrgController.isAdmin();
            for (RlyCredentialViews.Row r : RlyCredentialViews.sorted(RlyCredentialStore.rows())) {
                t.total++;
                t.checkedOn = t.checkedOn == null || (r.lastChecked != null && r.lastChecked > t.checkedOn) ? r.lastChecked : t.checkedOn;
                if (RlyCredentialRows.ATTENTION.contains(r.status)) {
                    t.problems.add(r);
                }
            }
            return t;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    private static Board read() {
        Board b = new Board();
        b.canCheck = RlyOrgController.isAdmin() && RlyHubGuard.isHub();
        for (RlyCredentialViews.Row r : RlyCredentialViews.sorted(RlyCredentialStore.rows())) {
            b.rows.add(r);
            b.counts.put(r.status, (b.counts.containsKey(r.status) ? b.counts.get(r.status) : 0) + 1);
            b.checkedOn = b.checkedOn == null || (r.lastChecked != null && r.lastChecked > b.checkedOn) ? r.lastChecked : b.checkedOn;
        }
        return b;
    }

    private static AuraHandledException handled(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        String message = e instanceof RlyReleaseException ? e.getMessage() : 'Something went wrong: ' + e.getMessage();
        AuraHandledException a = new AuraHandledException(message);
        a.setMessage(message);
        return a;
    }
}
