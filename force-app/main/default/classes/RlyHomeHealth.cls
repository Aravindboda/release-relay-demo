/**
 * @description The Home tab's health line (RlyHomeController), from the last saved checks only (no callouts): the Git
 * connection (Status__c, Last_Checked__c), the pipeline files (the last check's message and the version packaged with
 * Release Relay; the repository's version needs a callout, so it stays on the Pipeline tab), Slack and approving in
 * Slack (RlyHomeSlackHealth), the code scan (the connection and the per-org overrides) and, for admins in the production
 * hub with Archive every night on, nights the pipeline's scheduled job missed (RlyArchiveStats.homeItem). Hub configuration is read in system mode in the private inner without sharing class; the signing
 * secret is only checked for a value and never leaves Apex.
 */
public with sharing class RlyHomeHealth {

    /** @description Tone of an item that's fine. */
    public static final String TONE_OK = 'ok';
    /** @description Tone of an item that needs attention. */
    public static final String TONE_WAIT = 'wait';
    /** @description Tone of an item that's broken. */
    public static final String TONE_BAD = 'bad';
    /** @description Tone of an item that's off or not checked (no attention needed). */
    public static final String TONE_NONE = 'none';

    private static final String TEXT_CONNECTED = 'Connected';
    private static final String FILES_FOUND = 'Pipeline files found';
    private static final String SCAN_OFF = 'Off';
    private static final String SCAN_ON = 'On';
    private static final Integer TITLE_LENGTH = 300;

    /** @description The health line. */
    public class Health {
        /** @description Nothing needs attention: the page shows one line "All connections OK". */
        @AuraEnabled public Boolean allOk = true;
        /** @description How many items need attention (tone wait or bad). */
        @AuraEnabled public Integer attention = 0;
        /** @description When the Git connection was last checked, or null. */
        @AuraEnabled public Datetime checkedOn;
        /** @description The items, in order. */
        @AuraEnabled public List<Item> items = new List<Item>();
    }

    /** @description One item of the health line. */
    public class Item {
        /** @description git, files, slack, approve, scan or archive. */
        @AuraEnabled public String key;
        /** @description What it is, for example "Git connection". */
        @AuraEnabled public String label;
        /** @description Its state in words, for example "Connected". */
        @AuraEnabled public String text;
        /** @description ok, wait, bad or none. */
        @AuraEnabled public String tone;
        /** @description More about it (hover), or null. */
        @AuraEnabled public String title;
        /** @description The tab the item opens (for example RLY_Archive), or null for the Pipeline tab. */
        @AuraEnabled public String tab;
    }

    /**
     * @description The health line.
     * @return the items
     */
    public static Health read() {
        Data store = new Data();
        RLY_Git_Connection__c git = store.git();
        RLY_Notification__c slack = store.slack();
        List<RLY_Org__c> orgs = store.routeOrgs();
        Health h = new Health();
        h.items.add(gitItem(git));
        h.items.add(filesItem(git));
        h.items.add(RlyHomeSlackHealth.slackItem(slack));
        Item approve = RlyHomeSlackHealth.approveItem(slack, orgs);
        if (approve != null) {
            h.items.add(approve);
        }
        h.items.add(scanItem(git, orgs));
        Item archive = RlyArchiveStats.homeItem();
        if (archive != null) {
            h.items.add(archive);
        }
        h.checkedOn = git == null ? null : git.Last_Checked__c;
        for (Item i : h.items) {
            h.attention += i.tone == TONE_WAIT || i.tone == TONE_BAD ? 1 : 0;
        }
        h.allOk = h.attention == 0;
        return h;
    }

    /**
     * @description An item with no state yet.
     * @param key git, files, slack, approve, scan or archive
     * @param label what it is
     * @return the item
     */
    public static Item item(String key, String label) {
        Item i = new Item();
        i.key = key;
        i.label = label;
        return i;
    }

    /**
     * @description Sets an item's state.
     * @param i the item
     * @param text its state in words
     * @param tone ok, wait, bad or none
     * @return the item
     */
    public static Item withState(Item i, String text, String tone) {
        i.text = text;
        i.tone = tone;
        return i;
    }

    private static Item gitItem(RLY_Git_Connection__c git) {
        Item i = item('git', 'Git connection');
        if (git == null) {
            return withState(i, 'Not set up', TONE_BAD);
        }
        i.title = String.isBlank(git.Status_Message__c) ? null : git.Status_Message__c.left(TITLE_LENGTH);
        if (git.Status__c == TEXT_CONNECTED) {
            return withState(i, TEXT_CONNECTED, TONE_OK);
        }
        return git.Status__c == 'Failed' ? withState(i, 'Failed', TONE_BAD) : withState(i, 'Not checked', TONE_WAIT);
    }

    private static Item filesItem(RLY_Git_Connection__c git) {
        Item i = item('files', 'Pipeline files');
        if (git == null || git.Status__c != TEXT_CONNECTED) {
            return withState(i, 'not checked', TONE_NONE);
        }
        if (git.Status_Message__c == null || !git.Status_Message__c.contains(FILES_FOUND)) {
            i.title = 'The last check didn\'t find them on the pipeline branch. Open Pipeline to add them.';
            return withState(i, 'not found', TONE_WAIT);
        }
        Integer version = RlyPipelineFiles.packagedVersion();
        i.title = version == null ? null
            : 'Found by the last check. Version ' + version + ' is packaged with ' + System.Label.RLY_App_Name
                + '; Pipeline compares it with your repository.';
        return withState(i, version == null ? 'found' : 'found (v' + version + ')', TONE_OK);
    }

    private static Item scanItem(RLY_Git_Connection__c git, List<RLY_Org__c> orgs) {
        Item i = item('scan', 'Code scan');
        Boolean onByDefault = git != null && git.Code_Scan__c;
        List<String> differ = new List<String>();
        for (RLY_Org__c o : orgs) {
            if (o.Code_Scan__c == (onByDefault ? SCAN_OFF : SCAN_ON)) {
                differ.add(o.Name);
            }
        }
        if (differ.isEmpty()) {
            return withState(i, onByDefault ? SCAN_ON : SCAN_OFF, onByDefault ? TONE_OK : TONE_NONE);
        }
        return withState(i, (onByDefault ? 'Off for ' : 'On for ') + String.join(differ, ', '), TONE_NONE);
    }

    /** @description Hub configuration, read in system mode. */
    private without sharing class Data {

        /**
         * @description The hub's Git connection.
         * @return the connection, or null
         */
        public RLY_Git_Connection__c git() {
            List<RLY_Git_Connection__c> rows = [SELECT Id, Status__c, Status_Message__c, Last_Checked__c, Code_Scan__c
                                                FROM RLY_Git_Connection__c WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description The Slack record (signing secret included: only checked for a value, never sent to the page).
         * @return the record, or null
         */
        public RLY_Notification__c slack() {
            List<RLY_Notification__c> rows = [SELECT Id, Enabled__c, Last_Result__c, Signing_Secret__c FROM RLY_Notification__c
                                              WHERE Channel__c = 'Slack' WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description The stages and the hub, with their approval and code scan settings.
         * @return the orgs, in route order
         */
        public List<RLY_Org__c> routeOrgs() {
            return [SELECT Id, Name, Role__c, Code_Scan__c, Approval_In__c, Approve_In_Salesforce__c, Approve_In_Slack__c
                    FROM RLY_Org__c WHERE Role__c IN ('Stage', 'Hub')
                    WITH SYSTEM_MODE ORDER BY Stage_Order__c ASC NULLS LAST, Name ASC LIMIT 200];
        }
    }
}
