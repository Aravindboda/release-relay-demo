/**
 * @description Which waiting releases a promotion takes along. The pipeline promotes each file as it is in the stage
 * (options.stageBranch), so a file goes with every change the stage has to it. When a picked release shares a component
 * (Type and Name, deletions included) with a release waiting in the same stage that wasn't picked:
 * the unpicked one deployed to the stage EARLIER goes too (carried: marked promoted with the others); the unpicked one
 * deployed LATER than every picked release touching that component blocks the promotion until it is added. Releases
 * carried this way count as picked for the next round, until nothing more is carried.
 */
public with sharing class RlyPromoteOverlap {

    /** @description What a choice of releases takes along, or why it can't go. */
    public class Outcome {
        /** @description Releases not picked that go too, in the order found. */
        public List<Id> carriedIds = new List<Id>();
        /** @description Why the choice can't be promoted, or null. */
        public String blocked;
        /** @description The release to add to unblock it, or null. */
        public Id blockerId;
    }

    // One unpicked release against what goes: it goes too, it blocks, or it stays.
    private class Verdict {
        /** @description It shares a component with an older change that goes. */
        public Boolean carry = false;
        /** @description Why it blocks, or null. */
        public String block;
    }

    // One check: the releases waiting, those going so far and their components.
    private class Pass {
        /** @description The releases waiting in the stage. */
        public List<RLY_Release__c> waiting;
        /** @description The releases going so far (picked, then carried). */
        public List<RLY_Release__c> going = new List<RLY_Release__c>();
        /** @description Each release's components. */
        public Map<Id, Set<String>> keys;
        /** @description The outcome so far. */
        public Outcome out = new Outcome();
    }

    /**
     * @description Checks a choice against the releases waiting in its stage.
     * @param waiting the releases waiting in the stage, with Last_Synced__c (the deploy to the stage)
     * @param pickedIds the releases picked
     * @return what goes too, or why it is blocked
     */
    public static Outcome check(List<RLY_Release__c> waiting, Set<Id> pickedIds) {
        Pass p = new Pass();
        p.waiting = waiting;
        p.keys = componentsOf(new Map<Id, RLY_Release__c>(waiting).keySet());
        for (RLY_Release__c r : waiting) {
            if (pickedIds.contains(r.Id)) {
                p.going.add(r);
            }
        }
        Integer added = 1;
        while (added > 0 && p.out.blocked == null) {
            added = sweep(p);
        }
        return p.out;
    }

    /**
     * @description The picked releases and those they carry; refuses a choice a newer waiting release blocks.
     * @param waiting the releases waiting in the stage
     * @param pickedIds the releases picked
     * @return the Ids of every release that goes
     */
    public static Set<Id> withCarried(List<RLY_Release__c> waiting, Set<Id> pickedIds) {
        Outcome overlap = check(waiting, pickedIds);
        if (overlap.blocked != null) {
            throw new RlyReleaseException(overlap.blocked);
        }
        Set<Id> out = new Set<Id>(pickedIds);
        out.addAll(overlap.carriedIds);
        return out;
    }

    /**
     * @description The components (Type:Name, deletions included) of each release.
     * @param releaseIds the releases
     * @return the keys by release (every release has an entry)
     */
    public static Map<Id, Set<String>> componentsOf(Set<Id> releaseIds) {
        Map<Id, Set<String>> out = new Map<Id, Set<String>>();
        for (Id i : releaseIds) {
            out.put(i, new Set<String>());
        }
        if (releaseIds.isEmpty()) {
            return out;
        }
        for (RLY_Release_Item__c i : RlyPromoteStore.itemsOf(releaseIds)) {
            if (out.containsKey(i.Release__c)) {
                out.get(i.Release__c).add(i.Metadata_Type__c + ':' + i.Component_Name__c);
            }
        }
        return out;
    }

    // One round over the releases not going yet; returns how many were carried this round.
    private static Integer sweep(Pass p) {
        Set<Id> goingIds = new Map<Id, RLY_Release__c>(p.going).keySet().clone();
        Integer added = 0;
        for (RLY_Release__c candidate : p.waiting) {
            if (goingIds.contains(candidate.Id)) {
                continue;
            }
            Verdict v = judge(candidate, p.going, p.keys);
            if (v.block != null) {
                p.out.blocked = v.block;
                p.out.blockerId = candidate.Id;
                return added;
            }
            if (v.carry) {
                p.going.add(candidate);
                p.out.carriedIds.add(candidate.Id);
                added++;
            }
        }
        return added;
    }

    private static Verdict judge(RLY_Release__c candidate, List<RLY_Release__c> going, Map<Id, Set<String>> keys) {
        Verdict v = new Verdict();
        for (String k : keys.get(candidate.Id)) {
            RLY_Release__c latest = latestTouching(k, going, keys);
            if (latest == null) {
                continue;
            }
            if (isLater(candidate, latest)) {
                v.block = candidate.Name + ' changed ' + k.substringAfter(':') + ' after ' + latest.Name
                    + ': add it, or wait and promote them together.';
                return v;
            }
            v.carry = true;
        }
        return v;
    }

    // The release going that touches the component and was deployed to the stage last.
    private static RLY_Release__c latestTouching(String k, List<RLY_Release__c> going, Map<Id, Set<String>> keys) {
        RLY_Release__c latest = null;
        for (RLY_Release__c r : going) {
            Set<String> touched = keys.get(r.Id);
            if (touched != null && touched.contains(k) && (latest == null || isLater(r, latest))) {
                latest = r;
            }
        }
        return latest;
    }

    private static Boolean isLater(RLY_Release__c a, RLY_Release__c b) {
        return a.Last_Synced__c != null && b.Last_Synced__c != null && a.Last_Synced__c > b.Last_Synced__c;
    }
}
