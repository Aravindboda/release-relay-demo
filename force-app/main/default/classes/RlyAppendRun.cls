/**
 * @description The reader's side of adding changes to an open release (RlyAppendService saves the request). The release
 * keeps its add state in Append_State__c (JSON): how many adds it had (k), and while one is pending the components,
 * deletions and test classes being added. When the retrieve is done (RlyStatusReader) the zip goes to the release's
 * branch as .relay-inbox/<REL>-add-<k>.zip (an empty zip when only deletions are added), and the pipeline runs in mode hub
 * with options append and appendZip: it converts the zip into the branch, removes the new deletions, commits and pushes,
 * and the open pull request updates. Then the release counts the new components, tests and deletions, and its new items
 * are saved after the release (saveItems). A failed retrieve leaves the release as it was, with Checks failed and why.
 * Build 52: the add stays to be confirmed (confirming) until the run's raise.json says Opened; when the run failed to add
 * them, RlyAppendSettle undoes it: its items are removed, the counts, tests and deletions go back, and the release says
 * "Not added: the pipeline failed" with the retry.
 */
public with sharing class RlyAppendRun {

    /** @description The History event of an add (build 52: was Raised). */
    public static final String ADDED_EVENT = 'Changes_Added';
    /** @description The pending run of an add: the pipeline's hub run. */
    public static final String HUB_RUN = 'hub';

    private static final String FIELD = 'Append_State__c';
    private static final List<RLY_Release_Item__c> QUEUED_ITEMS = new List<RLY_Release_Item__c>();
    private static final List<RLY_Release_Item__c> QUEUED_REMOVALS = new List<RLY_Release_Item__c>();

    /** @description What Append_State__c holds. */
    public class State {
        /** @description Adds so far, the pending one included (its zip is <REL>-add-<adds>.zip). */
        public Integer adds = 0;
        /** @description An add waits for its retrieve and run. */
        public Boolean pending = false;
        /** @description The org the changes come from. */
        public String fromOrg;
        /** @description Type:Name of the components being added. */
        public List<String> components = new List<String>();
        /** @description Type:Name of the components being deleted. */
        public List<String> deletions = new List<String>();
        /** @description The test classes being added. */
        public List<String> tests = new List<String>();
        /** @description The hub run started: the add waits for the run to confirm it (build 52). */
        public Boolean confirming = false;
    }

    /**
     * @description A release's add state (empty for a release read without the field, or never added to).
     * @param rel the release
     * @return the state
     */
    public static State stateOf(RLY_Release__c rel) {
        Object raw = rel == null ? null : rel.getPopulatedFieldsAsMap().get(FIELD);
        if (raw == null || String.isBlank(String.valueOf(raw))) {
            return new State();
        }
        try {
            State st = (State) JSON.deserialize(String.valueOf(raw), State.class);
            return st == null ? new State() : orEmpty(st);
        } catch (Exception e) {
            return new State();
        }
    }

    private static State orEmpty(State st) {
        st.adds = st.adds == null ? 0 : st.adds;
        st.pending = st.pending == true;
        st.confirming = st.confirming == true;
        st.components = st.components == null ? new List<String>() : st.components;
        st.deletions = st.deletions == null ? new List<String>() : st.deletions;
        st.tests = st.tests == null ? new List<String>() : st.tests;
        return st;
    }

    /**
     * @description Saves the add state on the release (the caller saves the release).
     * @param rel the release
     * @param st the state
     */
    public static void writeState(RLY_Release__c rel, State st) {
        rel.Append_State__c = JSON.serialize(st);
    }

    /**
     * @description Whether an add waits for its retrieve and run.
     * @param rel the release
     * @return true while one is pending
     */
    public static Boolean isPending(RLY_Release__c rel) {
        return stateOf(rel).pending;
    }

    /**
     * @description Before the hub run starts: the release takes the new tests (so the run's options carry old and new),
     * deletions and counts, and its new items are queued (saveItems saves them after the release).
     * @param rel the release, with an add pending
     */
    public static void beforeDispatch(RLY_Release__c rel) {
        State st = stateOf(rel);
        Set<String> tests = new Set<String>(RlyReleasePhase.tests(rel));
        tests.addAll(st.tests);
        rel.Test_Classes__c = String.join(new List<String>(tests), ',');
        List<String> deletions = RlyDeletions.of(rel);
        for (String k : st.deletions) {
            if (!deletions.contains(k)) {
                deletions.add(k);
            }
        }
        rel.Deletions__c = deletions.isEmpty() ? null : String.join(deletions, ',').left(RlyDeletions.MAX_LENGTH);
        rel.Deletion_Count__c = deletions.size();
        rel.Component_Count__c = (rel.Component_Count__c == null ? 0 : rel.Component_Count__c) + st.components.size();
        QUEUED_ITEMS.addAll(itemsFor(rel.Id, st.components));
        for (RLY_Release_Item__c i : itemsFor(rel.Id, st.deletions)) {
            i.Is_Deletion__c = true;
            QUEUED_ITEMS.add(i);
        }
    }

    private static List<RLY_Release_Item__c> itemsFor(Id releaseId, List<String> keys) {
        List<RLY_Release_Item__c> out = new List<RLY_Release_Item__c>();
        for (String k : keys) {
            out.add(new RLY_Release_Item__c(Release__c = releaseId, Metadata_Type__c = k.substringBefore(':').left(80),
                Component_Name__c = k.substringAfter(':').left(255), Change_Type__c = 'Modified', Source__c = 'Detected',
                Is_Deletion__c = false));
        }
        return out;
    }

    /**
     * @description After the hub run started: the add is done (the count stays for the next add's zip name).
     * @param rel the release
     */
    public static void afterDispatch(RLY_Release__c rel) {
        State st = stateOf(rel);
        st.pending = false;
        st.confirming = true; // the lists stay until the run confirms the add (settle)
        writeState(rel, st);
    }

    /**
     * @description Ends the add's wait (build 52): confirmed, or undone by RlyAppendSettle; the count stays.
     * @param rel the release
     */
    public static void settled(RLY_Release__c rel) {
        writeState(rel, done(stateOf(rel)));
    }

    /**
     * @description Queues items to remove after the release is saved (saveItems): an add the pipeline didn't make.
     * @param rows the items
     */
    public static void removeLater(List<RLY_Release_Item__c> rows) {
        QUEUED_REMOVALS.addAll(rows);
    }

    /**
     * @description Starts the hub run of a release whose retrieve is done (its zip is on its branch). For an add, the
     * release takes the new tests, deletions and counts first, and the add is marked done after.
     * @param rel the release
     * @param git the Git provider
     * @param branch the release branch
     */
    public static void startHubRun(RLY_Release__c rel, RlyGit git, String branch) {
        Boolean adding = isPending(rel);
        if (adding) {
            beforeDispatch(rel);
        }
        git.startPipeline(RlyPipelineRun.inputs(rel, 'hub', branch));
        if (adding) {
            afterDispatch(rel);
        }
    }

    /**
     * @description A retrieve that failed: a raise ends Failed; an add goes back to Checks failed (abandon).
     * @param rel the release
     * @param problem why
     */
    public static void failRetrieve(RLY_Release__c rel, String problem) {
        if (isPending(rel)) {
            abandon(rel, problem);
        } else {
            RlyStatusReader.fail(rel, problem);
        }
    }

    /**
     * @description A retrieve that failed: the release goes back to Checks failed with why; nothing was added.
     * @param rel the release
     * @param problem why
     */
    public static void abandon(RLY_Release__c rel, String problem) {
        State st = stateOf(rel);
        rel.Status__c = 'Checks failed';
        rel.Pending_Run__c = null;
        rel.Error_Message__c = ('Couldn\'t add the changes from ' + st.fromOrg + ': ' + problem).left(2000);
        writeState(rel, done(st));
    }

    private static State done(State st) {
        st.pending = false;
        st.confirming = false;
        st.components = new List<String>();
        st.deletions = new List<String>();
        st.tests = new List<String>();
        return st;
    }

    /**
     * @description Saves the items queued by beforeDispatch (after the release is saved: no callout follows).
     */
    public static void saveItems() {
        if (!QUEUED_ITEMS.isEmpty()) {
            new SystemAccess().insertItems(QUEUED_ITEMS);
            QUEUED_ITEMS.clear();
        }
        if (!QUEUED_REMOVALS.isEmpty()) {
            new SystemAccess().deleteItems(QUEUED_REMOVALS); // an add the pipeline didn't make (notAdded)
            QUEUED_REMOVALS.clear();
        }
    }

    /** @description Release items are shared hub records: saved in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description See RlyAppendRun.saveItems.
         * @param rows the items
         */
        public void insertItems(List<RLY_Release_Item__c> rows) {
            insert as system rows;
        }

        /**
         * @description Removes the items of an add the pipeline didn't make.
         * @param rows the items
         */
        public void deleteItems(List<RLY_Release_Item__c> rows) {
            delete as system rows;
        }
    }
}
