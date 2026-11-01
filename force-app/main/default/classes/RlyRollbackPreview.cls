/**
 * @description What rolling back one org will do, read from the snapshot's manifest.json on the snapshots branch (one
 * callout): what will be restored (the components the org had, and those the release deleted) and removed (what the
 * deploy added), whether Apex is in it (production then runs tests), and later releases that deployed the same
 * components to the same org (the rollback puts them back as they were before this release, so it undoes those too).
 * Releases and their components are shared hub records: read in system mode, in the private inner without sharing class.
 */
public with sharing class RlyRollbackPreview {

    private static final Set<String> APEX_TYPES = new Set<String>{ 'ApexClass', 'ApexTrigger' };

    /** @description What rolling back one org will do (read from the snapshot's manifest). */
    public class Preview {
        /** @description The org. */
        @AuraEnabled public RlyRollbackPlan.OrgChoice org;
        /** @description When the snapshot was taken (manifest takenAt, ISO), or null. */
        @AuraEnabled public Datetime takenOn;
        /** @description Type:Name of the components restored as they were. */
        @AuraEnabled public List<String> restore = new List<String>();
        /** @description Type:Name of the components the deploy added, which the rollback deletes. */
        @AuraEnabled public List<String> remove = new List<String>();
        /** @description Apex is in the rollback (production then runs tests). */
        @AuraEnabled public Boolean apex = false;
        /** @description "REL-00027 also deployed PayClient to PROD after this release (1 Nov 11:40)." per later release. */
        @AuraEnabled public List<String> later = new List<String>();
    }

    /**
     * @description What rolling back one org will do: reads the snapshot's manifest.json (a callout).
     * @param releaseId the release
     * @param orgId the org
     * @return the preview
     */
    public static Preview preview(Id releaseId, Id orgId) {
        Preview p = new Preview();
        p.org = RlyRollbackPlan.choiceFor(releaseId, orgId);
        if (p.org.hasSnapshot != true) {
            throw new RlyReleaseException(p.org.orgName + ' has no snapshot to roll back to (' + p.org.why + ').');
        }
        String raw = RlyGit.forConnection(RlyReleaseStore.git()).getFileRaw(p.org.snapshotPath + '/manifest.json', RlyRollbackPlan.SNAPSHOT_BRANCH);
        if (String.isBlank(raw)) {
            throw new RlyReleaseException('The snapshot ' + p.org.snapshotPath + ' isn\'t on ' + RlyRollbackPlan.SNAPSHOT_BRANCH + ' any more.');
        }
        Map<String, Object> manifest = RlyEvidenceText.parse(raw);
        p.takenOn = RlyRollbackPlan.toTime(manifest.get('takenAt'));
        p.restore = strings(manifest.get('existing'));
        p.restore.addAll(strings(manifest.get('deleted')));
        p.remove = strings(manifest.get('added'));
        for (String k : allOf(p)) {
            p.apex = p.apex || APEX_TYPES.contains(k.substringBefore(':'));
        }
        p.later = laterReleases(p.org, allOf(p));
        return p;
    }

    private static Set<String> allOf(Preview p) {
        Set<String> keys = new Set<String>(p.restore);
        keys.addAll(p.remove);
        return keys;
    }

    private static List<String> strings(Object raw) {
        List<String> out = new List<String>();
        for (Object o : raw instanceof List<Object> ? (List<Object>) raw : new List<Object>()) {
            if (o != null) {
                out.add(String.valueOf(o));
            }
        }
        return out;
    }

    // Releases deployed to the same org after the owner (approved after it) that changed the same components: the
    // rollback puts those components back as they were before the owner, so it undoes those changes too.
    private static List<String> laterReleases(RlyRollbackPlan.OrgChoice c, Set<String> keys) {
        List<String> out = new List<String>();
        if (c.approvedOn == null || keys.isEmpty()) {
            return out;
        }
        SystemAccess access = new SystemAccess();
        List<RLY_Release__c> later = access.deployedAfter(c);
        Map<Id, Set<String>> touched = access.componentsOf(later);
        for (RLY_Release__c r : later) {
            List<String> same = sameNames(touched.get(r.Id), keys);
            if (!same.isEmpty()) {
                Datetime deployedOn = RlyRollbackPlan.toTime(RlyEvidenceText.parse(r.Deploy_Result__c).get('finishedAt'));
                out.add(r.Name + ' also deployed ' + String.join(same, ', ').abbreviate(200) + ' to ' + c.orgName + ' after this release'
                    + (deployedOn == null ? '' : ' (' + deployedOn.format('d MMM HH:mm') + ')') + '. Rolling back undoes that change too.');
            }
        }
        return out;
    }

    // The names of a later release's components that are in the rollback.
    private static List<String> sameNames(Set<String> touched, Set<String> keys) {
        List<String> same = new List<String>();
        for (String k : touched == null ? new Set<String>() : touched) {
            if (keys.contains(k)) {
                same.add(k.substringAfter(':'));
            }
        }
        return same;
    }

    /** @description Shared hub releases and their components, read in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description Releases and promotions deployed to the choice's org that were approved after its owner.
         * @param c the choice
         * @return up to 50, oldest approval first
         */
        public List<RLY_Release__c> deployedAfter(RlyRollbackPlan.OrgChoice c) {
            return [SELECT Id, Name, Deploy_Result__c, Carried_Releases__c, Release_Type__c FROM RLY_Release__c
                    WHERE Target_Org__c = :c.orgId AND Status__c = 'Deployed' AND Id != :c.ownerId AND Approved_On__c > :c.approvedOn
                    WITH SYSTEM_MODE ORDER BY Approved_On__c ASC LIMIT 50];
        }

        /**
         * @description The components (Type:Name) each release deployed: its own, and for a promotion its carried releases'.
         * @param rels the releases
         * @return the components by release Id
         */
        public Map<Id, Set<String>> componentsOf(List<RLY_Release__c> rels) {
            Map<Id, Id> ownerOf = new Map<Id, Id>();
            for (RLY_Release__c r : rels) {
                ownerOf.put(r.Id, r.Id);
                for (Id carriedId : RlyCarried.ids(r)) {
                    ownerOf.put(carriedId, r.Id);
                }
            }
            Map<Id, Set<String>> out = new Map<Id, Set<String>>();
            for (RLY_Release_Item__c i : [SELECT Release__c, Metadata_Type__c, Component_Name__c FROM RLY_Release_Item__c
                                          WHERE Release__c IN :ownerOf.keySet() WITH SYSTEM_MODE LIMIT 10000]) {
                Id owner = ownerOf.get(i.Release__c);
                if (!out.containsKey(owner)) {
                    out.put(owner, new Set<String>());
                }
                out.get(owner).add(i.Metadata_Type__c + ':' + i.Component_Name__c);
            }
            return out;
        }
    }
}
