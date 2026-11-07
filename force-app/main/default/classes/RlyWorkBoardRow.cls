/**
 * @description Work items (build 40): one ticket's row on the Work items tab, from the releases that carry it (newest
 * first): where it is in each route org (deployed, in progress, waiting, failed, rolled back), its status (In PROD,
 * Waiting for PROD, In SIT approval, Blocked, In progress) and how its tracker updates went. Reads only.
 */
public with sharing class RlyWorkBoardRow {

    private static final String OK = 'ok';
    private static final String RUN = 'run';
    private static final String WAIT = 'wait';
    private static final String BAD = 'bad';
    private static final String NONE = 'none';
    private static final String WAITING_TEXT = 'waiting to deploy';
    private static final List<String> SYNC_TONES = new List<String>{ NONE, NONE, OK, BAD };
    private static final List<String> SYNC_TEXTS = new List<String>{ '', 'Tracked here', 'Synced', 'Couldn\'t post' };
    private static final Set<String> FAILED_STATUSES = new Set<String>{ 'Checks failed', 'Deploy failed', 'Failed', 'Rejected' };

    /**
     * @description A ticket's row (its link is added by the caller).
     * @param ticket the ticket
     * @param rows the ticket's rows, newest first, with their releases
     * @param orgs the route orgs, in order
     * @return the row
     */
    public static RlyWorkTypes.TicketRow rowOf(String ticket, List<RLY_Work_Item__c> rows, List<String> orgs) {
        RlyWorkTypes.TicketRow r = new RlyWorkTypes.TicketRow();
        r.ticket = ticket;
        List<String> words = new List<String>{ ticket };
        Map<String, RLY_Release__c> latestByOrg = new Map<String, RLY_Release__c>();
        Integer worst = 0;
        for (RLY_Work_Item__c w : rows) {
            RLY_Release__c rel = w.Release__r;
            r.raisedOn = rel.CreatedDate;
            r.releases.add(refOf(rel));
            words.addAll(new List<String>{ rel.Name, String.valueOf(rel.Title__c), rel.CreatedBy == null ? '' : rel.CreatedBy.Name });
            String org = rel.Target_Org__r == null ? null : rel.Target_Org__r.Name;
            if (org != null && !latestByOrg.containsKey(org)) {
                latestByOrg.put(org, rel);
            }
            if (rankOf(w) > worst) {
                worst = rankOf(w);
                syncOf(r, w);
            }
        }
        for (String org : orgs) {
            r.cells.add(cellOf(org, latestByOrg.get(org)));
        }
        statusOf(r, orgs);
        r.searchText = String.join(words, ' ').toLowerCase();
        return r;
    }

    private static RlyWorkTypes.ReleaseRef refOf(RLY_Release__c rel) {
        RlyWorkTypes.ReleaseRef x = new RlyWorkTypes.ReleaseRef();
        x.id = rel.Id;
        x.name = rel.Name;
        if (rel.Is_Hotfix__c == true) {
            x.kind = 'hotfix';
        } else if (RlyPromotion.typeOf(rel) != RlyPromotion.TYPE_RELEASE) {
            x.kind = 'promotion';
        }
        return x;
    }

    // The worst sync result wins: a failed post, then posted, then tracked here.
    private static Integer rankOf(RLY_Work_Item__c w) {
        if (w.Sync_Status__c == RlyWorkSync.FAILED) {
            return 3;
        }
        return w.Sync_Status__c == RlyWorkSync.POSTED ? 2 : 1;
    }

    private static void syncOf(RlyWorkTypes.TicketRow r, RLY_Work_Item__c w) {
        Integer rank = rankOf(w);
        r.syncTone = SYNC_TONES[rank];
        r.syncText = SYNC_TEXTS[rank];
        r.syncMessage = w.Sync_Message__c;
    }

    // Where the ticket is in one org, from the newest release into it.
    private static RlyWorkTypes.Cell cellOf(String org, RLY_Release__c rel) {
        RlyWorkTypes.Cell c = new RlyWorkTypes.Cell();
        c.org = org;
        c.tone = NONE;
        c.text = '—';
        if (rel == null || rel.Status__c == 'Closed') {
            return c;
        }
        if (String.isNotBlank(rel.Rollback_Status__c) && rel.Rollback_Status__c.containsIgnoreCase('rolled back')) {
            c.tone = BAD;
            c.text = 'rolled back';
        } else if (rel.Status__c == 'Deployed') {
            c.tone = OK;
            c.text = 'deployed ' + rel.LastModifiedDate.format('d MMM');
        } else if (FAILED_STATUSES.contains(rel.Status__c)) {
            c.tone = BAD;
            c.text = rel.Status__c.toLowerCase();
        } else {
            pendingCell(c, rel);
        }
        return c;
    }

    // Not deployed or failed yet: waiting to deploy, ready for approval, or in progress.
    private static void pendingCell(RlyWorkTypes.Cell c, RLY_Release__c rel) {
        c.tone = RUN;
        c.text = 'in progress';
        if (rel.Status__c != 'Ready for approval') {
            return;
        }
        if (RlyWorkGate.isWaiting(rel) || rel.Approval_Status__c == 'Approved') {
            c.text = WAITING_TEXT;
        } else {
            c.tone = WAIT;
            c.text = 'ready for approval';
        }
    }

    // The ticket's status from its cells: in the last org, blocked, waiting, in approval, or in progress.
    private static void statusOf(RlyWorkTypes.TicketRow r, List<String> orgs) {
        r.status = 'In progress';
        r.tone = RUN;
        r.bucket = 'inprogress';
        if (!r.cells.isEmpty() && r.cells[r.cells.size() - 1].tone == OK) {
            r.status = 'In ' + orgs[orgs.size() - 1];
            r.tone = OK;
            r.bucket = 'inprod';
        } else if (hasTone(r.cells, BAD)) {
            r.status = 'Blocked';
            r.tone = BAD;
            r.bucket = 'blocked';
        } else {
            waitingStatus(r);
        }
    }

    private static Boolean hasTone(List<RlyWorkTypes.Cell> cells, String tone) {
        for (RlyWorkTypes.Cell c : cells) {
            if (c.tone == tone) {
                return true;
            }
        }
        return false;
    }

    private static void waitingStatus(RlyWorkTypes.TicketRow r) {
        for (RlyWorkTypes.Cell c : r.cells) {
            if (c.text == WAITING_TEXT) {
                r.status = 'Waiting for ' + c.org;
                return;
            }
            if (c.tone == WAIT) {
                r.status = 'In ' + c.org + ' approval';
                r.tone = WAIT;
                return;
            }
        }
    }
}
