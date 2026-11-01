/**
 * @description Removes one pass of releases (RlyArchiveBatch.nextPass): for each release its manual step runs (and
 * runs of its steps), manual steps, history (RLY_Release_Event__c), items, its Files linked only to it (links to users
 * don't count), then the release itself, and empties the Recycle Bin for them. The caller holds the savepoint, so a
 * failure removes nothing of this pass. Deletes run in system mode in the private inner without sharing class; files
 * are deleted one by one where allowed (a file that can't be deleted loses only its link to the release).
 */
public with sharing class RlyArchivePass {

    /** @description Tests make the pass fail after the children are deleted (to check the rollback). */
    @TestVisible
    private static Boolean failForTest = false;

    /** @description What one pass removed. */
    public class Outcome {
        /** @description Releases removed. */
        public Integer releases = 0;
        /** @description Records removed: the releases and their items, history, manual steps and step runs. */
        public Integer records = 0;
        /** @description Files removed (not counted in records). */
        public Integer files = 0;
        /** @description The files left the Recycle Bin too (false: they leave it on their own after 15 days). */
        public Boolean filesEmptied = true;
        /** @description When the oldest release removed had finished, or null. */
        public Datetime oldest;
        /** @description When the newest release removed had finished, or null. */
        public Datetime newest;
    }

    /**
     * @description Removes the releases and everything that belongs to them.
     * @param pass the releases, oldest finished first
     * @return what was removed
     */
    public static Outcome remove(List<RlyArchiveBatch.Candidate> pass) {
        Outcome o = new Outcome();
        if (pass == null || pass.isEmpty()) {
            return o;
        }
        Set<Id> ids = new Set<Id>();
        for (RlyArchiveBatch.Candidate c : pass) {
            ids.add(c.id);
            o.oldest = earlier(o.oldest, c.finished);
            o.newest = later(o.newest, c.finished);
        }
        Data data = new Data();
        Set<Id> fileIds = data.filesOnlyOn(ids);
        List<Id> removed = new List<Id>();
        removed.addAll(data.removeChildren(ids));
        if (failForTest) {
            throw new RlyReleaseException('UNABLE_TO_LOCK_ROW on a release (test)');
        }
        removed.addAll(data.removeReleases(ids));
        o.releases = ids.size();
        o.records = removed.size();
        List<Id> filesRemoved = data.removeFiles(fileIds);
        o.files = filesRemoved.size();
        data.emptyBin(removed);
        o.filesEmptied = data.emptyFiles(filesRemoved);
        return o;
    }

    private static Datetime earlier(Datetime a, Datetime b) {
        return a == null || b < a ? b : a;
    }

    private static Datetime later(Datetime a, Datetime b) {
        return a == null || b > a ? b : a;
    }

    /** @description Releases, their children and files are shared hub records: removed in system mode. */
    private without sharing class Data {

        /**
         * @description Files linked to these releases and to nothing else (links to users are ignored).
         * @param ids the releases
         * @return the files' ContentDocument Ids
         */
        public Set<Id> filesOnlyOn(Set<Id> ids) {
            Set<Id> docs = new Set<Id>();
            for (ContentDocumentLink l : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :ids
                                          WITH SYSTEM_MODE]) {
                docs.add(l.ContentDocumentId);
            }
            if (docs.isEmpty()) {
                return docs;
            }
            Set<Id> elsewhere = new Set<Id>();
            for (ContentDocumentLink l : [SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink
                                          WHERE ContentDocumentId IN :docs WITH SYSTEM_MODE]) {
                Boolean ignored = ids.contains(l.LinkedEntityId) || l.LinkedEntityId.getSObjectType() == User.SObjectType;
                if (!ignored) {
                    elsewhere.add(l.ContentDocumentId);
                }
            }
            docs.removeAll(elsewhere);
            return docs;
        }

        /**
         * @description Deletes the releases' manual step runs (and runs of their steps), manual steps, history and items.
         * @param ids the releases
         * @return the Ids deleted
         */
        public List<Id> removeChildren(Set<Id> ids) {
            List<Id> out = new List<Id>();
            List<RLY_Manual_Step__c> steps = [SELECT Id FROM RLY_Manual_Step__c WHERE Release__c IN :ids WITH SYSTEM_MODE];
            Set<Id> stepIds = new Map<Id, RLY_Manual_Step__c>(steps).keySet();
            out.addAll(remove([SELECT Id FROM RLY_Manual_Step_Run__c WHERE Release__c IN :ids OR Step__c IN :stepIds
                               WITH SYSTEM_MODE]));
            out.addAll(remove(steps));
            out.addAll(remove([SELECT Id FROM RLY_Release_Event__c WHERE Release__c IN :ids WITH SYSTEM_MODE]));
            out.addAll(remove([SELECT Id FROM RLY_Release_Item__c WHERE Release__c IN :ids WITH SYSTEM_MODE]));
            return out;
        }

        /**
         * @description Deletes the releases.
         * @param ids the releases
         * @return the Ids deleted
         */
        public List<Id> removeReleases(Set<Id> ids) {
            List<RLY_Release__c> rows = new List<RLY_Release__c>();
            for (Id i : ids) {
                rows.add(new RLY_Release__c(Id = i));
            }
            return remove(rows);
        }

        /**
         * @description Deletes files where allowed.
         * @param fileIds the ContentDocument Ids
         * @return the Ids deleted
         */
        public List<Id> removeFiles(Set<Id> fileIds) {
            List<Id> out = new List<Id>();
            if (fileIds.isEmpty()) {
                return out;
            }
            List<ContentDocument> rows = new List<ContentDocument>();
            for (Id i : fileIds) {
                rows.add(new ContentDocument(Id = i));
            }
            for (Database.DeleteResult r : Database.delete(rows, false, AccessLevel.SYSTEM_MODE)) {
                if (r.isSuccess()) {
                    out.add(r.getId());
                }
            }
            return out;
        }

        /**
         * @description Empties the Recycle Bin for the records deleted.
         * @param records the records deleted
         */
        public void emptyBin(List<Id> records) {
            if (!records.isEmpty()) {
                Database.emptyRecycleBin(records);
            }
        }

        /**
         * @description Empties the Recycle Bin for the files deleted, where allowed.
         * @param files the files deleted
         * @return false when they stay in the Recycle Bin (it empties itself after 15 days)
         */
        public Boolean emptyFiles(List<Id> files) {
            if (files.isEmpty()) {
                return true;
            }
            try {
                Database.emptyRecycleBin(files);
                return true;
            } catch (Exception e) {
                return false;
            }
        }

        private List<Id> remove(List<SObject> rows) {
            List<Id> out = new List<Id>();
            if (rows.isEmpty()) {
                return out;
            }
            Database.delete(rows, true, AccessLevel.SYSTEM_MODE);
            for (SObject r : rows) {
                out.add(r.Id);
            }
            return out;
        }
    }
}
