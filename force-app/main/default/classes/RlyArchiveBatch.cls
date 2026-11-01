/**
 * @description Picks the next pass of the archive: the eligible releases (RlyArchiveEligible) ordered by finished date
 * (oldest first), then as many as fit in one pass: at most 200 releases and at most 4,000 records (the release with its
 * items, history, manual steps, step runs and files), stopping at whichever comes first; the first release always goes,
 * so one large release never blocks the rest. Only the 400 oldest-raised eligible releases are ordered per pass, which
 * keeps the query rows low. History and children are shared hub records: counted in system mode in the private inner
 * without sharing class.
 */
public with sharing class RlyArchiveBatch {

    /** @description Most releases per pass. */
    @TestVisible
    private static Integer passReleases = 200;
    /** @description Most records per pass (releases and their children). */
    @TestVisible
    private static Integer passRecords = 4000;
    /** @description Most eligible releases a pass reads to find the oldest finished ones. */
    @TestVisible
    private static Integer candidates = 400;

    /** @description One eligible release, with its finished date and how many records go with it. */
    public class Candidate implements Comparable {
        /** @description The release. */
        public Id id;
        /** @description When it finished. */
        public Datetime finished;
        /** @description The release and its children. */
        public Integer weight = 1;

        /**
         * @description Oldest finished first (then by Id, so the order is stable).
         * @param other another candidate
         * @return negative, zero or positive
         */
        public Integer compareTo(Object other) {
            Candidate o = (Candidate) other;
            if (finished == o.finished) {
                return String.valueOf(id).compareTo(String.valueOf(o.id));
            }
            return finished < o.finished ? -1 : 1;
        }
    }

    /**
     * @description The next pass, oldest finished first.
     * @param cutoff releases finished before this are eligible
     * @return the releases (empty when nothing is eligible)
     */
    public static List<Candidate> nextPass(Datetime cutoff) {
        Data data = new Data();
        List<Candidate> top = oldestFinished(data, cutoff);
        weigh(data, top);
        List<Candidate> pass = new List<Candidate>();
        Integer records = 0;
        for (Candidate c : top) {
            if (!pass.isEmpty() && records + c.weight > passRecords) {
                break;
            }
            pass.add(c);
            records += c.weight;
        }
        return pass;
    }

    // The oldest finished of the eligible releases read, at most passReleases of them.
    private static List<Candidate> oldestFinished(Data data, Datetime cutoff) {
        List<RLY_Release__c> rows = RlyArchiveEligible.oldestRaised(cutoff, candidates);
        Map<Id, Datetime> lastEvent = data.lastEvents(new Map<Id, RLY_Release__c>(rows).keySet());
        List<Candidate> sorted = new List<Candidate>();
        for (RLY_Release__c r : rows) {
            sorted.add(candidate(r, lastEvent.get(r.Id)));
        }
        sorted.sort();
        List<Candidate> top = new List<Candidate>();
        for (Integer i = 0; i < Math.min(sorted.size(), passReleases); i++) {
            top.add(sorted[i]);
        }
        return top;
    }

    private static Candidate candidate(RLY_Release__c r, Datetime lastEvent) {
        Candidate c = new Candidate();
        c.id = r.Id;
        c.finished = lastEvent == null ? r.LastModifiedDate : lastEvent;
        Boolean laterRollback = r.Rollback_Status__c == RlyArchiveEligible.ROLLED_BACK && r.Rollback_On__c != null
            && r.Rollback_On__c > c.finished;
        if (laterRollback) {
            c.finished = r.Rollback_On__c;
        }
        return c;
    }

    // How many records go with each release: the release, its items, history, manual steps, step runs and files.
    private static void weigh(Data data, List<Candidate> rows) {
        Set<Id> ids = new Set<Id>();
        for (Candidate c : rows) {
            ids.add(c.id);
        }
        Map<Id, Integer> children = data.childrenPerRelease(ids);
        for (Candidate c : rows) {
            c.weight = 1 + (children.containsKey(c.id) ? children.get(c.id) : 0);
        }
    }

    /** @description History, children and file links are shared hub records: counted in system mode. */
    private without sharing class Data {

        /**
         * @description When each release's last history entry was made.
         * @param ids the releases
         * @return release Id to the CreatedDate of its last event
         */
        public Map<Id, Datetime> lastEvents(Set<Id> ids) {
            Map<Id, Datetime> out = new Map<Id, Datetime>();
            for (AggregateResult a : [SELECT Release__c r, MAX(CreatedDate) d FROM RLY_Release_Event__c
                                      WHERE Release__c IN :ids WITH SYSTEM_MODE GROUP BY Release__c]) {
                out.put((Id) a.get('r'), (Datetime) a.get('d'));
            }
            return out;
        }

        /**
         * @description How many child records and files each release has.
         * @param ids the releases
         * @return release Id to its count
         */
        public Map<Id, Integer> childrenPerRelease(Set<Id> ids) {
            Map<Id, Integer> out = new Map<Id, Integer>();
            if (ids.isEmpty()) {
                return out;
            }
            add(out, [SELECT Release__c r, COUNT(Id) n FROM RLY_Release_Item__c WHERE Release__c IN :ids
                      WITH SYSTEM_MODE GROUP BY Release__c]);
            add(out, [SELECT Release__c r, COUNT(Id) n FROM RLY_Release_Event__c WHERE Release__c IN :ids
                      WITH SYSTEM_MODE GROUP BY Release__c]);
            add(out, [SELECT Release__c r, COUNT(Id) n FROM RLY_Manual_Step__c WHERE Release__c IN :ids
                      WITH SYSTEM_MODE GROUP BY Release__c]);
            add(out, [SELECT Release__c r, COUNT(Id) n FROM RLY_Manual_Step_Run__c WHERE Release__c IN :ids
                      WITH SYSTEM_MODE GROUP BY Release__c]);
            for (ContentDocumentLink l : [SELECT LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :ids
                                          WITH SYSTEM_MODE]) {
                plus(out, l.LinkedEntityId, 1);
            }
            return out;
        }

        private void add(Map<Id, Integer> out, List<AggregateResult> rows) {
            for (AggregateResult a : rows) {
                plus(out, (Id) a.get('r'), (Integer) a.get('n'));
            }
        }

        private void plus(Map<Id, Integer> out, Id key, Integer n) {
            out.put(key, (out.containsKey(key) ? out.get(key) : 0) + n);
        }
    }
}
