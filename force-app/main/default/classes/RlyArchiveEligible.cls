/**
 * @description Which finished releases the archive may remove, and how many records go with them. Finished: Status__c
 * Deployed, Rejected, Closed, Failed or Deploy failed, or Rollback_Status__c Rolled_Back; never while a rollback is
 * Running, and never while the promotion that carries it (Promoted_In__c) is still open. A promotion goes only once
 * none of the releases it carried is left, so a group never loses its promotion first. The finished date is the
 * release's last RLY_Release_Event__c (its LastModifiedDate when it has none), or its rollback when that is later; a
 * release is eligible when that date is before the cutoff (now minus the Retention days): it was raised before the
 * cutoff and has no history from the cutoff on. Counts use COUNT() queries (one query row each). RlyArchiveBatch picks
 * a pass from the oldest-raised eligible releases. Releases are shared hub records: read in system mode in the private
 * inner without sharing class.
 */
public with sharing class RlyArchiveEligible {

    /** @description Release statuses that count as finished. */
    public static final List<String> FINISHED = new List<String>{ 'Deployed', 'Rejected', 'Closed', 'Failed', 'Deploy failed' };
    /** @description The rollback status that counts as finished. */
    public static final String ROLLED_BACK = 'Rolled_Back';
    /** @description The rollback status that holds a release back. */
    public static final String ROLLBACK_RUNNING = 'Running';

    /** @description Most eligible releases whose children are counted for the records estimate. */
    @TestVisible
    private static Integer sampleSize = 10000;

    /**
     * @description How many finished releases are eligible at a cutoff.
     * @param cutoff releases finished before this are eligible
     * @return the count
     */
    public static Integer countReleases(Datetime cutoff) {
        Data data = new Data();
        Set<Id> held = data.heldPromotions(cutoff);
        return data.countWithEvents(cutoff, held) + data.countWithoutEvents(cutoff, held);
    }

    /**
     * @description About how many records go with the eligible releases (the releases included). Children are counted
     * for up to 10,000 eligible releases; more are estimated from those.
     * @param cutoff releases finished before this are eligible
     * @param releases how many releases are eligible (countReleases)
     * @return the count
     */
    public static Integer countRecords(Datetime cutoff, Integer releases) {
        if (releases == null || releases == 0) {
            return 0;
        }
        Set<Id> ids = new Map<Id, RLY_Release__c>(oldestRaised(cutoff, sampleSize)).keySet();
        if (ids.isEmpty()) {
            return releases;
        }
        Integer counted = ids.size() + new Data().childCount(ids);
        if (ids.size() >= releases) {
            return counted;
        }
        return (Decimal.valueOf(counted) * releases / ids.size()).round().intValue();
    }

    /**
     * @description Eligible releases, oldest raised first: those with history, then those without.
     * @param cutoff releases finished before this are eligible
     * @param max the most to read
     * @return the releases, with LastModifiedDate, Rollback_Status__c and Rollback_On__c
     */
    public static List<RLY_Release__c> oldestRaised(Datetime cutoff, Integer max) {
        Data data = new Data();
        Set<Id> held = data.heldPromotions(cutoff);
        List<RLY_Release__c> rows = data.withEvents(cutoff, held, max);
        if (rows.size() < max) {
            rows.addAll(data.withoutEvents(cutoff, held, max - rows.size()));
        }
        return rows;
    }

    /** @description Releases and their children are shared hub records: read in system mode. */
    private without sharing class Data {

        /**
         * @description Promotions that still carry a release (they wait until every release they carried is gone).
         * @param cutoff only promotions raised before this can be eligible
         * @return the promotions
         */
        public Set<Id> heldPromotions(Datetime cutoff) {
            Set<Id> out = new Set<Id>();
            for (AggregateResult a : [SELECT Promoted_In__c p, COUNT(Id) n FROM RLY_Release__c
                                      WHERE Promoted_In__c != null AND Promoted_In__r.CreatedDate < :cutoff
                                      WITH SYSTEM_MODE GROUP BY Promoted_In__c]) {
                out.add((Id) a.get('p'));
            }
            return out;
        }

        /**
         * @description How many eligible releases have history.
         * @param cutoff the cutoff
         * @param held promotions that still carry releases
         * @return the count
         */
        public Integer countWithEvents(Datetime cutoff, Set<Id> held) {
            return [SELECT COUNT() FROM RLY_Release__c
                    WHERE (Status__c IN :FINISHED OR Rollback_Status__c = :ROLLED_BACK)
                    AND (Rollback_Status__c = null OR Rollback_Status__c != :ROLLBACK_RUNNING)
                    AND (Rollback_Status__c != :ROLLED_BACK OR Rollback_On__c = null OR Rollback_On__c < :cutoff)
                    AND (Promoted_In__c = null OR Promoted_In__r.Status__c IN :FINISHED)
                    AND CreatedDate < :cutoff AND Id NOT IN :held
                    AND Id IN (SELECT Release__c FROM RLY_Release_Event__c)
                    AND Id NOT IN (SELECT Release__c FROM RLY_Release_Event__c WHERE CreatedDate >= :cutoff)
                    WITH SYSTEM_MODE];
        }

        /**
         * @description How many eligible releases have no history (their LastModifiedDate counts).
         * @param cutoff the cutoff
         * @param held promotions that still carry releases
         * @return the count
         */
        public Integer countWithoutEvents(Datetime cutoff, Set<Id> held) {
            return [SELECT COUNT() FROM RLY_Release__c
                    WHERE (Status__c IN :FINISHED OR Rollback_Status__c = :ROLLED_BACK)
                    AND (Rollback_Status__c = null OR Rollback_Status__c != :ROLLBACK_RUNNING)
                    AND (Rollback_Status__c != :ROLLED_BACK OR Rollback_On__c = null OR Rollback_On__c < :cutoff)
                    AND (Promoted_In__c = null OR Promoted_In__r.Status__c IN :FINISHED)
                    AND CreatedDate < :cutoff AND LastModifiedDate < :cutoff AND Id NOT IN :held
                    AND Id NOT IN (SELECT Release__c FROM RLY_Release_Event__c)
                    WITH SYSTEM_MODE];
        }

        /**
         * @description Eligible releases with history, oldest raised first.
         * @param cutoff the cutoff
         * @param held promotions that still carry releases
         * @param max the most to read
         * @return the releases
         */
        public List<RLY_Release__c> withEvents(Datetime cutoff, Set<Id> held, Integer max) {
            return [SELECT Id, LastModifiedDate, Rollback_Status__c, Rollback_On__c FROM RLY_Release__c
                    WHERE (Status__c IN :FINISHED OR Rollback_Status__c = :ROLLED_BACK)
                    AND (Rollback_Status__c = null OR Rollback_Status__c != :ROLLBACK_RUNNING)
                    AND (Rollback_Status__c != :ROLLED_BACK OR Rollback_On__c = null OR Rollback_On__c < :cutoff)
                    AND (Promoted_In__c = null OR Promoted_In__r.Status__c IN :FINISHED)
                    AND CreatedDate < :cutoff AND Id NOT IN :held
                    AND Id IN (SELECT Release__c FROM RLY_Release_Event__c)
                    AND Id NOT IN (SELECT Release__c FROM RLY_Release_Event__c WHERE CreatedDate >= :cutoff)
                    WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC LIMIT :max];
        }

        /**
         * @description Eligible releases with no history, oldest changed first.
         * @param cutoff the cutoff
         * @param held promotions that still carry releases
         * @param max the most to read
         * @return the releases
         */
        public List<RLY_Release__c> withoutEvents(Datetime cutoff, Set<Id> held, Integer max) {
            return [SELECT Id, LastModifiedDate, Rollback_Status__c, Rollback_On__c FROM RLY_Release__c
                    WHERE (Status__c IN :FINISHED OR Rollback_Status__c = :ROLLED_BACK)
                    AND (Rollback_Status__c = null OR Rollback_Status__c != :ROLLBACK_RUNNING)
                    AND (Rollback_Status__c != :ROLLED_BACK OR Rollback_On__c = null OR Rollback_On__c < :cutoff)
                    AND (Promoted_In__c = null OR Promoted_In__r.Status__c IN :FINISHED)
                    AND CreatedDate < :cutoff AND LastModifiedDate < :cutoff AND Id NOT IN :held
                    AND Id NOT IN (SELECT Release__c FROM RLY_Release_Event__c)
                    WITH SYSTEM_MODE ORDER BY LastModifiedDate ASC, Id ASC LIMIT :max];
        }

        /**
         * @description How many child records the releases have in all (items, history, manual steps, step runs).
         * @param ids the releases
         * @return the count
         */
        public Integer childCount(Set<Id> ids) {
            return [SELECT COUNT() FROM RLY_Release_Item__c WHERE Release__c IN :ids WITH SYSTEM_MODE]
                + [SELECT COUNT() FROM RLY_Release_Event__c WHERE Release__c IN :ids WITH SYSTEM_MODE]
                + [SELECT COUNT() FROM RLY_Manual_Step__c WHERE Release__c IN :ids WITH SYSTEM_MODE]
                + [SELECT COUNT() FROM RLY_Manual_Step_Run__c WHERE Release__c IN :ids WITH SYSTEM_MODE];
        }
    }
}
