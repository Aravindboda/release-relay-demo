/**
 * A release in the hub, from raise to deploy. The hub signs in to the developer org itself
 * (RlyOrgSession), retrieves the selected components, commits the Metadata API zip to a
 * release branch and starts the pipeline (mode hub). The pipeline converts the zip, opens the
 * pull request, scans and validates; later it merges and deploys. Each step writes a result
 * file that advance() reads.
 *
 * Statuses: Retrieving → Workflow running → Validating → Checks failed | Ready for approval
 *           → Deploying (after approval) → Deployed | Deploy failed. Rejected, Closed and
 *           Failed end it. Every method does its callouts first and its DML last.
 */
public with sharing class RlyReleaseFlow {

    public class FlowException extends Exception {}

    public static final String RESULTS_BRANCH = 'release-relay-results';
    public static final Set<String> OPEN_STATUSES = new Set<String>{ 'Retrieving', 'Workflow running', 'Validating', 'Deploying' };
    private static final Set<String> FINISHED = new Set<String>{ 'Passed', 'Failed', 'Skipped', 'Error', 'Bypassed' };
    private static final Set<String> APEX_TYPES = new Set<String>{ 'ApexClass', 'ApexTrigger' };

    // ---------- raise ----------

    public class Item {
        public String type;
        public String name;
        public Boolean deleted;
        public Boolean standard;
    }

    public class RaiseRequest {
        public Id sourceOrgId;
        public String title;
        public String description;
        public List<Item> items;
        public List<String> testClasses;
    }

    /** Starts the retrieve in the developer org and saves the release. Returns its Id. */
    public static Id raise(RaiseRequest req) {
        Data data = new Data();
        if (req == null || req.items == null || req.items.isEmpty()) {
            throw new FlowException('Select at least one component.');
        }
        if (String.isBlank(req.title) || req.title.trim().length() > 200) {
            throw new FlowException('Give the release a title (up to 200 characters).');
        }
        RLY_Org__c source = data.org(req.sourceOrgId);
        if (source == null || source.Role__c != 'Developer') {
            throw new FlowException('Pick a registered developer org.');
        }
        RLY_Org__c target = data.firstStage();
        if (target == null || String.isBlank(target.Branch__c)) {
            throw new FlowException('No stage to release into yet: register SIT with its branch on the Pipeline tab.');
        }
        RLY_Git_Connection__c git = data.git();
        if (git == null || git.Status__c != 'Connected') {
            throw new FlowException('The Git connection isn\'t set up and checked yet (Pipeline tab).');
        }

        Map<String, Set<String>> byType = new Map<String, Set<String>>();
        Boolean hasApex = false;
        Set<String> tests = new Set<String>();
        for (String t : req.testClasses == null ? new List<String>() : req.testClasses) {
            if (String.isNotBlank(t)) {
                tests.add(t.trim());
            }
        }
        for (Item i : req.items) {
            if (String.isBlank(i.type) || String.isBlank(i.name) || i.name.contains(',') || i.name.contains(':')) {
                throw new FlowException('Can\'t release "' + i.name + '": names with commas or colons aren\'t supported.');
            }
            if (i.deleted == true) {
                throw new FlowException(i.name + ' was deleted in ' + source.Name + '. Deletions come in a later build: leave it out for now.');
            }
            if (!byType.containsKey(i.type)) {
                byType.put(i.type, new Set<String>());
            }
            byType.get(i.type).add(i.name);
            if (APEX_TYPES.contains(i.type) && !tests.contains(i.name)) {
                hasApex = true;
            }
        }
        // The test rule, enforced here too: Apex needs at least one test class, no bypass.
        if (hasApex && tests.isEmpty()) {
            throw new FlowException('This release has Apex but no test class. Select the test class that covers it.');
        }
        for (String t : tests) {
            if (!byType.containsKey('ApexClass') || !byType.get('ApexClass').contains(t)) {
                throw new FlowException('Test class ' + t + ' must be in the release too.');
            }
        }

        String retrieveId = RlyMetadata.retrieve(source, byType); // callout before any DML

        RLY_Release__c rel = new RLY_Release__c(
            Title__c = req.title.trim(), Description__c = req.description == null ? null : req.description.left(5000),
            Mode__c = 'Org changes', Request_Type__c = 'Changes', Status__c = 'Retrieving',
            Source_Org__c = source.Id, Target_Org__c = target.Id, Org_Label__c = source.Name.left(40),
            Target_Branch__c = target.Branch__c, Source_Environment__c = source.Git_Environment__c,
            Target_Environment__c = target.Git_Environment__c, Retrieve_Id__c = retrieveId,
            Component_Count__c = req.items.size(), Deletion_Count__c = 0,
            Test_Classes__c = String.join(new List<String>(tests), ','),
            Scan_Status__c = git.Code_Scan__c ? 'Pending' : 'Not configured',
            Validation_Status__c = String.isBlank(target.Git_Environment__c) ? 'Not configured' : 'Pending',
            Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending', Last_Synced__c = System.now());
        List<RLY_Release_Item__c> items = new List<RLY_Release_Item__c>();
        for (Item i : req.items) {
            items.add(new RLY_Release_Item__c(Metadata_Type__c = i.type.left(80), Component_Name__c = i.name.left(255),
                Change_Type__c = 'Modified', Source__c = 'Detected'));
        }
        data.insertRelease(rel, items);
        return rel.Id;
    }

    // ---------- moving a release along ----------

    /** Reads where the release is (retrieve, pipeline run, pull request, result files) and saves what changed. */
    public static RLY_Release__c advance(Id releaseId) {
        Data data = new Data();
        RLY_Release__c rel = data.release(releaseId);
        if (rel == null) {
            throw new FlowException('Release not found.');
        }
        if (!OPEN_STATUSES.contains(rel.Status__c) || rel.Source_Org__c == null) {
            return rel;
        }
        RlyGit git = RlyGit.forConnection(data.git());
        try {
            if (rel.Status__c == 'Retrieving') {
                afterRetrieve(rel, git, data);
            } else if (rel.Status__c == 'Deploying') {
                readDeploy(rel, git);
            } else {
                readChecks(rel, git);
            }
        } catch (Exception e) {
            // Keep the release where it is; the message shows on the page and the next refresh tries again.
            rel.Error_Message__c = ('Couldn\'t read the latest status: ' + e.getMessage()).left(2000);
        }
        rel.Last_Synced__c = System.now();
        data.save(rel);
        return rel;
    }

    private static void afterRetrieve(RLY_Release__c rel, RlyGit git, Data data) {
        RLY_Org__c source = data.org(rel.Source_Org__c);
        RlyMetadata.RetrieveStatus st = RlyMetadata.checkRetrieve(source, rel.Retrieve_Id__c);
        if (!st.done) {
            return;
        }
        if (!st.success || String.isBlank(st.zipBase64)) {
            fail(rel, 'Retrieving from ' + source.Name + ' failed: ' + (st.message == null ? '' : st.message)
                + (st.problems.isEmpty() ? '' : ' ' + String.join(st.problems, '; ')));
            return;
        }
        if (!st.problems.isEmpty()) {
            fail(rel, 'Some components couldn\'t be retrieved from ' + source.Name + ': ' + String.join(st.problems, '; '));
            return;
        }
        String branch = branchName(rel);
        if (!git.branchExists(branch)) {
            git.createBranch(branch, rel.Target_Branch__c);
        }
        git.putFile('.relay-inbox/' + rel.Name + '.zip', branch, st.zipBase64, rel.Name + ': components from ' + source.Name);
        git.startPipeline(inputs(rel, 'hub', branch, data));
        rel.Source_Branch__c = branch;
        rel.Status__c = 'Workflow running';
        rel.Pending_Run__c = 'hub';
        rel.Checks_Requested__c = System.now();
        rel.Error_Message__c = null;
    }

    private static void readChecks(RLY_Release__c rel, RlyGit git) {
        RlyGit.PullRequest pr = git.findPullRequest(rel.Source_Branch__c, rel.Target_Branch__c);
        RlyGit.Run run = git.findRun(runTitle(rel));
        if (run != null) {
            rel.Run_ID__c = run.id.left(30);
            rel.Run_URL__c = run.url;
        }
        if (pr == null) {
            if (run != null && run.failed() && rel.Pending_Run__c == 'hub') {
                fail(rel, 'The pipeline couldn\'t open the pull request. Open the run for the reason.');
            }
            return;
        }
        rel.PR_Number__c = pr.prNumber;
        rel.PR_URL__c = pr.url;
        if (pr.state == 'closed') {
            rel.Status__c = 'Closed';
            return;
        }
        if (rel.Status__c == 'Workflow running') {
            rel.Status__c = 'Validating';
        }
        if (rel.Scan_Status__c == 'Pending') {
            Map<String, Object> scan = result(git, rel, 'scan');
            if (scan != null) {
                rel.Scan_Status__c = String.valueOf(scan.get('status'));
                rel.Scan_Violations__c = toNumber(scan.get('total'));
                rel.Scan_Blocking__c = toNumber(scan.get('blocking'));
                rel.Scan_Result__c = JSON.serialize(scan).left(131072);
            }
        }
        if (rel.Validation_Status__c == 'Pending') {
            Map<String, Object> val = result(git, rel, 'validate');
            if (val != null) {
                rel.Validation_Status__c = String.valueOf(val.get('status'));
                rel.Validation_Result__c = JSON.serialize(val).left(131072);
            }
        }
        // The run ended without writing a result (a job failed early): don't wait forever.
        if (run != null && run.completed()) {
            if (rel.Scan_Status__c == 'Pending') {
                rel.Scan_Status__c = 'Error';
                rel.Scan_Result__c = JSON.serialize(new Map<String, Object>{ 'message' => 'The code scan didn\'t write a result. Open the run.' });
            }
            if (rel.Validation_Status__c == 'Pending') {
                rel.Validation_Status__c = 'Error';
                rel.Validation_Result__c = JSON.serialize(new Map<String, Object>{ 'message' => 'The validation didn\'t write a result. Open the run.' });
            }
        }
        decide(rel);
    }

    /** Ready for approval when both checks are done and neither blocks; a blocking scan can be bypassed, a failed validation can't. */
    @TestVisible
    private static void decide(RLY_Release__c rel) {
        Boolean scanDone = rel.Scan_Status__c == 'Not configured' || FINISHED.contains(rel.Scan_Status__c);
        Boolean valDone = rel.Validation_Status__c == 'Not configured' || FINISHED.contains(rel.Validation_Status__c);
        if (!scanDone || !valDone) {
            return;
        }
        Boolean scanBlocks = rel.Scan_Status__c == 'Failed' || rel.Scan_Status__c == 'Error';
        Boolean valBlocks = rel.Validation_Status__c == 'Failed' || rel.Validation_Status__c == 'Error';
        rel.Status__c = scanBlocks || valBlocks ? 'Checks failed' : 'Ready for approval';
    }

    private static void readDeploy(RLY_Release__c rel, RlyGit git) {
        RlyGit.Run run = git.findRun(runTitle(rel));
        if (run != null) {
            rel.Run_ID__c = run.id.left(30);
            rel.Run_URL__c = run.url;
        }
        Map<String, Object> mergeResult = result(git, rel, 'merge');
        if (mergeResult != null && String.valueOf(mergeResult.get('status')) == 'Failed') {
            rel.Status__c = 'Deploy failed';
            rel.Deploy_Status__c = 'Failed';
            rel.Deploy_Result__c = JSON.serialize(mergeResult).left(131072);
            rel.Error_Message__c = ('Merge failed: ' + String.valueOf(mergeResult.get('message'))).left(2000);
            return;
        }
        if (mergeResult != null) {
            rel.Merge_Commit__c = String.valueOf(mergeResult.get('sha')).left(40);
        }
        Map<String, Object> deploy = result(git, rel, 'deploy');
        if (deploy != null) {
            Boolean ok = String.valueOf(deploy.get('status')) == 'Deployed';
            rel.Status__c = ok ? 'Deployed' : 'Deploy failed';
            rel.Deploy_Status__c = ok ? 'Deployed' : 'Failed';
            rel.Deploy_Result__c = JSON.serialize(deploy).left(131072);
            rel.Error_Message__c = ok ? null : String.valueOf(deploy.get('message')).left(2000);
        } else if (run != null && run.failed()) {
            rel.Status__c = 'Deploy failed';
            rel.Deploy_Status__c = 'Failed';
            rel.Error_Message__c = 'The pipeline run failed before it wrote a result. Open the run.';
        } else {
            rel.Deploy_Status__c = 'Deploying';
        }
    }

    // ---------- actions ----------

    /** Code scan blocked it: an approver accepts the findings, with a reason. */
    public static RLY_Release__c bypassScan(Id releaseId, String reason) {
        requireApprover();
        Data data = new Data();
        RLY_Release__c rel = data.release(releaseId);
        if (rel == null || rel.Status__c != 'Checks failed' || (rel.Scan_Status__c != 'Failed' && rel.Scan_Status__c != 'Error')) {
            throw new FlowException('Only a release whose code scan failed can bypass it.');
        }
        if (String.isBlank(reason) || reason.trim().length() < 10) {
            throw new FlowException('Say why the findings are accepted (at least 10 characters).');
        }
        rel.Scan_Status__c = 'Bypassed';
        rel.Scan_Bypassed_By__c = UserInfo.getUserId();
        rel.Scan_Bypass_Reason__c = reason.trim().left(2000);
        decide(rel);
        data.save(rel);
        return rel;
    }

    /** Runs the code scan and validation again (after a fix on the branch, or a change in the target org). */
    public static RLY_Release__c checkAgain(Id releaseId) {
        Data data = new Data();
        RLY_Release__c rel = data.release(releaseId);
        if (rel == null || (rel.Status__c != 'Checks failed' && rel.Status__c != 'Ready for approval') || rel.PR_Number__c == null) {
            throw new FlowException('Checks can run again on an open pull request that isn\'t approved yet.');
        }
        RlyGit git = RlyGit.forConnection(data.git());
        git.startPipeline(inputs(rel, 'check', rel.Source_Branch__c, data));
        RLY_Git_Connection__c conn = data.git();
        rel.Status__c = 'Validating';
        rel.Pending_Run__c = 'check';
        rel.Checks_Requested__c = System.now();
        rel.Scan_Status__c = conn.Code_Scan__c ? 'Pending' : 'Not configured';
        rel.Validation_Status__c = String.isBlank(rel.Target_Environment__c) ? 'Not configured' : 'Pending';
        rel.Scan_Bypassed_By__c = null;
        rel.Scan_Bypass_Reason__c = null;
        rel.Error_Message__c = null;
        data.save(rel);
        return rel;
    }

    /** Approves the release: the pipeline merges the pull request and deploys it to the target org. */
    public static RLY_Release__c approve(Id releaseId, String comment) {
        requireApprover();
        Data data = new Data();
        RLY_Release__c rel = data.release(releaseId);
        if (rel == null || rel.Status__c != 'Ready for approval') {
            throw new FlowException('Only a release that\'s ready for approval can be approved.');
        }
        RlyGit git = RlyGit.forConnection(data.git());
        git.startPipeline(inputs(rel, 'merge', rel.Source_Branch__c, data));
        rel.Status__c = 'Deploying';
        rel.Approval_Status__c = 'Approved';
        rel.Approved_By__c = UserInfo.getUserId();
        rel.Approved_On__c = System.now();
        rel.Approval_Comment__c = comment == null ? null : comment.left(2000);
        rel.Deploy_Status__c = 'Deploying';
        rel.Pending_Run__c = 'merge';
        rel.Checks_Requested__c = System.now();
        rel.Error_Message__c = null;
        data.save(rel);
        return rel;
    }

    public static RLY_Release__c reject(Id releaseId, String comment) {
        requireApprover();
        Data data = new Data();
        RLY_Release__c rel = data.release(releaseId);
        if (rel == null || (rel.Status__c != 'Ready for approval' && rel.Status__c != 'Checks failed')) {
            throw new FlowException('Only a release waiting for approval can be rejected.');
        }
        if (String.isBlank(comment)) {
            throw new FlowException('Say why it\'s rejected, so the developer knows what to change.');
        }
        if (rel.PR_Number__c != null) {
            try {
                RlyGit.forConnection(data.git()).closePullRequest(rel.PR_Number__c.intValue(),
                    'Rejected in Release Relay by ' + UserInfo.getName() + ': ' + comment.left(1000));
            } catch (Exception e) {
                rel.Error_Message__c = ('Rejected, but the pull request couldn\'t be closed: ' + e.getMessage()).left(2000);
            }
        }
        rel.Status__c = 'Rejected';
        rel.Approval_Status__c = 'Rejected';
        rel.Approved_By__c = UserInfo.getUserId();
        rel.Approved_On__c = System.now();
        rel.Approval_Comment__c = comment.left(2000);
        data.save(rel);
        return rel;
    }

    public static Boolean isApprover() {
        return FeatureManagement.checkPermission('RLY_Approver') || FeatureManagement.checkPermission('RLY_Admin');
    }

    private static void requireApprover() {
        if (!isApprover()) {
            throw new FlowException('Only approvers can do this (permission set Release Relay Approver).');
        }
    }

    // ---------- helpers ----------

    public static String branchName(RLY_Release__c rel) {
        return 'feature/' + rel.Name.toLowerCase();
    }

    public static String runTitle(RLY_Release__c rel) {
        return 'Release Relay ' + rel.Name + ' (' + rel.Pending_Run__c + ')';
    }

    /** The pipeline's inputs; options carry the hub flag, the org label, the tests and the scan switch. */
    @TestVisible
    private static Map<String, String> inputs(RLY_Release__c rel, String mode, String branch, Data data) {
        List<String> tests = String.isBlank(rel.Test_Classes__c) ? new List<String>() : rel.Test_Classes__c.split(',');
        Map<String, Object> options = new Map<String, Object>{ 'hub' => true, 'label' => rel.Org_Label__c, 'tests' => tests };
        RLY_Git_Connection__c conn = data.git();
        if (conn != null && conn.Code_Scan__c != true) {
            options.put('scan', 'off');
        }
        List<String> components = new List<String>();
        for (RLY_Release_Item__c i : data.items(rel.Id)) {
            components.add(i.Metadata_Type__c + ':' + i.Component_Name__c);
        }
        return new Map<String, String>{
            'request_id' => rel.Name, 'mode' => mode,
            'environment' => String.isBlank(rel.Source_Environment__c) ? 'release-relay' : rel.Source_Environment__c,
            'target_environment' => rel.Target_Environment__c == null ? '' : rel.Target_Environment__c,
            'branch' => branch, 'target' => rel.Target_Branch__c,
            'title' => (rel.Name + ': ' + rel.Title__c).left(200),
            'components' => mode == 'hub' ? String.join(components, ',').left(60000) : '',
            'deletions' => '', 'options' => JSON.serialize(options)
        };
    }

    /** A step's result file, when it was written after the latest run was requested. */
    private static Map<String, Object> result(RlyGit git, RLY_Release__c rel, String step) {
        String raw = git.getFileRaw('results/' + rel.Name + '/' + step + '.json', RESULTS_BRANCH);
        if (String.isBlank(raw)) {
            return null;
        }
        Map<String, Object> r = (Map<String, Object>) JSON.deserializeUntyped(raw);
        Object finished = r.get('finishedAt');
        if (finished != null && rel.Checks_Requested__c != null) {
            Datetime at = (Datetime) JSON.deserialize('"' + String.valueOf(finished) + '"', Datetime.class);
            if (at < rel.Checks_Requested__c.addMinutes(-2)) {
                return null; // from an earlier run
            }
        }
        return r;
    }

    private static Decimal toNumber(Object o) {
        return o == null ? null : Decimal.valueOf(String.valueOf(o));
    }

    private static void fail(RLY_Release__c rel, String message) {
        rel.Status__c = 'Failed';
        rel.Error_Message__c = message.left(2000);
    }

    /** Releases, orgs and the Git connection are shared hub records: read and updated for every hub user. */
    @TestVisible
    private without sharing class Data {
        public RLY_Org__c org(Id orgId) {
            List<RLY_Org__c> rows = [SELECT Id, Name, Role__c, My_Domain__c, Login_Type__c, Username__c, Client_Id__c, Certificate__c,
                                            Branch__c, Git_Environment__c, Stage_Order__c
                                     FROM RLY_Org__c WHERE Id = :orgId];
            return rows.isEmpty() ? null : rows[0];
        }
        public RLY_Org__c firstStage() {
            List<RLY_Org__c> rows = [SELECT Id, Name, Branch__c, Git_Environment__c FROM RLY_Org__c
                                     WHERE Role__c = 'Stage' ORDER BY Stage_Order__c ASC NULLS LAST, Name LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }
        public RLY_Git_Connection__c git() {
            List<RLY_Git_Connection__c> rows = [SELECT Id, Provider__c, Repository__c, Named_Credential__c, Pipeline__c, Pipeline_Branch__c,
                                                       Source_Path__c, Code_Scan__c, Status__c
                                                FROM RLY_Git_Connection__c ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }
        public RLY_Release__c release(Id releaseId) {
            List<RLY_Release__c> rows = [SELECT Id, Name, Title__c, Description__c, Status__c, Source_Org__c, Target_Org__c, Org_Label__c,
                    Source_Branch__c, Target_Branch__c, Source_Environment__c, Target_Environment__c, Retrieve_Id__c,
                    PR_Number__c, PR_URL__c, Run_ID__c, Run_URL__c, Pending_Run__c, Checks_Requested__c, Last_Synced__c,
                    Error_Message__c, Component_Count__c, Test_Classes__c,
                    Scan_Status__c, Scan_Violations__c, Scan_Blocking__c, Scan_Result__c, Scan_Bypassed_By__c, Scan_Bypassed_By__r.Name,
                    Scan_Bypass_Reason__c, Validation_Status__c, Validation_Result__c,
                    Approval_Status__c, Approved_By__c, Approved_By__r.Name, Approved_On__c, Approval_Comment__c,
                    Merge_Commit__c, Deploy_Status__c, Deploy_Result__c, CreatedDate, CreatedBy.Name, CreatedById
                FROM RLY_Release__c WHERE Id = :releaseId];
            return rows.isEmpty() ? null : rows[0];
        }
        public List<RLY_Release_Item__c> items(Id releaseId) {
            return [SELECT Id, Metadata_Type__c, Component_Name__c FROM RLY_Release_Item__c
                    WHERE Release__c = :releaseId ORDER BY Metadata_Type__c, Component_Name__c LIMIT 5000];
        }
        public void insertRelease(RLY_Release__c rel, List<RLY_Release_Item__c> items) {
            insert rel;
            for (RLY_Release_Item__c i : items) {
                i.Release__c = rel.Id;
            }
            insert items;
        }
        public void save(RLY_Release__c rel) {
            // Only the fields the flow owns; relationship fields from the query can't be saved.
            update new RLY_Release__c(Id = rel.Id, Status__c = rel.Status__c, Source_Branch__c = rel.Source_Branch__c,
                PR_Number__c = rel.PR_Number__c, PR_URL__c = rel.PR_URL__c, Run_ID__c = rel.Run_ID__c, Run_URL__c = rel.Run_URL__c,
                Pending_Run__c = rel.Pending_Run__c, Checks_Requested__c = rel.Checks_Requested__c, Last_Synced__c = rel.Last_Synced__c,
                Error_Message__c = rel.Error_Message__c, Scan_Status__c = rel.Scan_Status__c, Scan_Violations__c = rel.Scan_Violations__c,
                Scan_Blocking__c = rel.Scan_Blocking__c, Scan_Result__c = rel.Scan_Result__c, Scan_Bypassed_By__c = rel.Scan_Bypassed_By__c,
                Scan_Bypass_Reason__c = rel.Scan_Bypass_Reason__c, Validation_Status__c = rel.Validation_Status__c,
                Validation_Result__c = rel.Validation_Result__c, Approval_Status__c = rel.Approval_Status__c,
                Approved_By__c = rel.Approved_By__c, Approved_On__c = rel.Approved_On__c, Approval_Comment__c = rel.Approval_Comment__c,
                Merge_Commit__c = rel.Merge_Commit__c, Deploy_Status__c = rel.Deploy_Status__c, Deploy_Result__c = rel.Deploy_Result__c);
        }
    }
}
