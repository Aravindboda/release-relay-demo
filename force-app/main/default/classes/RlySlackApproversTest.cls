/**
 * @description Tests for Slack approvers (RlySlackApprovers, RlySlackApproverAdd, RlySlackApproverRows, RlySlackReason,
 * RlySlackMatch, RlySlackMatchPlan, RlySlackLookup, RlySlackFix, RlySlackScopes, RlySlackPeople, RlySlackDirectory,
 * RlySlackApi.read): adding approvers, matching by SSO Federation ID in passes, Slack busy (429 with Retry-After),
 * missing scopes, Self and Admin links kept, Slack IDs moved from deactivated users, Set ID by hand, row fixes, unlink
 * and remove. Each test runs through System.runAs as the active System Administrator with Release Relay Admin; records
 * are saved before Test.startTest and callouts come after it (a callout can't follow uncommitted DML).
 */
@IsTest
private class RlySlackApproversTest {

    /** @description One answer of the Slack mock. */
    private class Rule {
        /** @description Fragment of the decoded URL. */
        public String part;
        /** @description HTTP status. */
        public Integer status;
        /** @description Body. */
        public String body;
        /** @description Headers. */
        public Map<String, String> headers = new Map<String, String>();
    }

    /** @description Slack Web API mock with headers; anything unmatched is users_not_found. */
    private class SlackMock implements HttpCalloutMock {
        /** @description The rules, first match wins. */
        public List<Rule> rules = new List<Rule>();
        /** @description Decoded URLs called. */
        public List<String> calls = new List<String>();

        /**
         * @description Adds an answer.
         * @param part URL fragment
         * @param status HTTP status
         * @param body body
         * @return this mock
         */
        public SlackMock reply(String part, Integer status, String body) {
            Rule r = new Rule();
            r.part = part;
            r.status = status;
            r.body = body;
            rules.add(r);
            return this;
        }

        /**
         * @description Adds a header to the last answer.
         * @param name header name
         * @param value header value
         * @return this mock
         */
        public SlackMock header(String name, String value) {
            rules[rules.size() - 1].headers.put(name, value);
            return this;
        }

        /**
         * @description Answers a callout.
         * @param req the request
         * @return the answer
         */
        public HttpResponse respond(HttpRequest req) {
            String url = EncodingUtil.urlDecode(req.getEndpoint(), 'UTF-8');
            calls.add(url);
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"ok":false,"error":"users_not_found"}');
            for (Rule r : rules) {
                if (url.contains(r.part)) {
                    res.setStatusCode(r.status);
                    res.setBody(r.body);
                    for (String k : r.headers.keySet()) {
                        res.setHeader(k, r.headers.get(k));
                    }
                    break;
                }
            }
            return res;
        }
    }

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // A new active user (System Administrator profile, no Release Relay permission sets); fed: email, blank or number.
    private static User person(String last, String fed) {
        Id profileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        String tag = last.toLowerCase() + '.' + Datetime.now().getTime() + '.' + Math.abs(Crypto.getRandomInteger());
        String fedId = fed == 'email' ? tag + '@rly-sso.example.com' : (fed == 'number' ? 'E' + Math.abs(Crypto.getRandomInteger()) : null);
        User u = new User(Alias = last.left(8), Email = last.toLowerCase() + '@rly-mail.example.com', EmailEncodingKey = 'UTF-8',
            LastName = last, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = profileId,
            TimeZoneSidKey = 'America/Chicago', Username = 'rly.' + tag + '@example.com', FederationIdentifier = fedId);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return [SELECT Id, Name, FederationIdentifier, Email FROM User WHERE Id = :u.Id];
    }

    private static void approve(User u) {
        Id setId = [SELECT Id FROM PermissionSet WHERE Name = 'RLY_Approver' LIMIT 1].Id;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = setId);
        }
    }

    private static String slackUser(String id, String email) {
        return '{"ok":true,"user":{"id":"' + id + '","name":"' + id.toLowerCase() + '","team_id":"T1","profile":{"email":"'
            + email + '","real_name":"Person ' + id + '"}}}';
    }

    private static User reload(Id userId) {
        return [SELECT RLY_Slack_Member_Id__c, RLY_Slack_Linked_By__c, RLY_Slack_Linked_On__c, RLY_Slack_Match_Note__c,
                       RLY_Slack_Linked_By_User__c FROM User WHERE Id = :userId];
    }

    private static RlySlackApproverRows.Row rowOf(RlySlackApprovers.Window w, Id userId) {
        for (RlySlackApproverRows.Row r : w.rows) {
            if (r.userId == userId) {
                return r;
            }
        }
        return null;
    }

    @IsTest
    static void addThenMatchBySso() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Deployed');
            User ann = person('Annsso', 'email');
            User bob = person('Bobsso', 'blank');
            User cy = person('Cysso', 'number');
            User dee = person('Deesso', 'email');
            List<RlySlackApproverAdd.Candidate> found = RlySlackApprovers.searchUsers('sso');
            System.assert(found.size() >= 4, 'Found by name: ' + found);
            System.assertEquals(0, RlySlackApprovers.searchUsers('a').size(), 'Two letters at least');
            RlySlackApproverAdd.AddResult added;
            System.runAs(new User(Id = UserInfo.getUserId())) {
                added = RlySlackApprovers.addApprovers(new List<Id>{ ann.Id, bob.Id, cy.Id, dee.Id });
            }
            System.assertEquals(4, added.added.size(), 'Added: ' + added.problems);
            System.assert(!added.manual, 'SSO by default');
            RlySlackApproverAdd.Candidate again = RlySlackApprovers.searchUsers('Annsso')[0];
            System.assertEquals('Approver', again.blockedTag, 'Already an approver');
            SlackMock mock = new SlackMock().reply('email=' + ann.FederationIdentifier, 200, slackUser('U0ANN1', ann.FederationIdentifier));
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlySlackMatch.Pass pass = RlySlackApprovers.matchPass(added.added, 0);
            RlySlackApprovers.Window w = RlySlackApprovers.finishMatch();
            Test.stopTest();
            System.assertEquals(4, pass.total, 'Only the added ones');
            System.assertEquals(1, pass.changed, 'Ann linked');
            System.assertEquals(2, pass.looked, 'Ann and Dee asked; Bob and Cy not looked up: ' + mock.calls);
            System.assertEquals(null, pass.nextOffset, 'One pass');
            System.assert(mock.calls[0].contains('callout:RLY_Slack/users.lookupByEmail?email='), mock.calls[0]);
            User a = reload(ann.Id);
            System.assertEquals('U0ANN1', a.RLY_Slack_Member_Id__c, 'Linked');
            System.assertEquals('SSO', a.RLY_Slack_Linked_By__c, 'By SSO');
            System.assertEquals('fedEmpty', rowOf(w, bob.Id).reasonCode, 'No Federation ID');
            System.assertEquals('fedNotEmail', rowOf(w, cy.Id).reasonCode, 'Employee number');
            System.assertEquals('notFound', rowOf(w, dee.Id).reasonCode, 'Not in Slack');
            System.assertEquals(null, rowOf(w, ann.Id).reasonCode, 'Fine');
            System.assert(w.attention >= 3 && w.lastMatch != null && w.lastMatchBy != null, 'Stamped: ' + w);
            System.assertEquals('Approver', rowOf(w, ann.Id).access, 'Approver');
            System.assertEquals(null, rowOf(w, ann.Id).removeNote, 'Can be removed');
            Map<String, Integer> counts = RlySlackApproverRows.counts();
            System.assert(counts.get('linked') >= 1 && counts.get('total') >= 4, 'Counts: ' + counts);
        }
    }

    @IsTest
    static void busySlackStopsThePass() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Deployed');
            User ann = person('Annbusy', 'email');
            approve(ann);
            Test.setMock(HttpCalloutMock.class, new SlackMock().reply('users.lookupByEmail', 429, '').header('Retry-After', '20'));
            Test.startTest();
            RlySlackMatch.Pass pass = RlySlackApprovers.matchPass(new List<Id>{ ann.Id }, 0);
            Test.stopTest();
            System.assertEquals(20, pass.retryAfter, 'Slack said 20 s');
            System.assertEquals(0, pass.nextOffset, 'Go on from Ann');
            System.assertEquals(null, reload(ann.Id).RLY_Slack_Member_Id__c, 'Nothing linked');
        }
    }

    @IsTest
    static void missingScopeStopsTheRun() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Deployed');
            User ann = person('Annscope', 'email');
            approve(ann);
            Test.setMock(HttpCalloutMock.class, new SlackMock()
                .reply('users.lookupByEmail', 200, '{"ok":false,"error":"missing_scope"}')
                .reply('auth.test', 200, '{"ok":true,"team":"Acme"}').header('x-oauth-scopes', 'chat:write,users:read'));
            Test.startTest();
            RlySlackMatch.Pass pass = RlySlackApprovers.matchPass(new List<Id>{ ann.Id }, 0);
            RlySlackScopes.ScopeCheck check = RlySlackApprovers.checkScopes();
            Test.stopTest();
            System.assert(pass.problem.contains('users:read.email'), pass.problem);
            System.assertEquals(null, pass.nextOffset, 'Stopped');
            System.assertEquals(3, check.items.size(), 'Three scopes');
            System.assert(check.missingText.startsWith('Slack app is missing users:read.email'), check.missingText);
            RlySlackApprovers.Window w = RlySlackApprovers.load();
            System.assertEquals(new List<String>{ 'users:read.email' }, w.missingScopes, 'Kept');
            System.assert(w.slackProblem.contains('users:read.email'), w.slackProblem);
        }
    }

    @IsTest
    static void selfLinksKeptAndDeactivatedHolderMoves() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Deployed');
            User ann = person('Annself', 'email');
            User bob = person('Bobmove', 'email');
            User zed = person('Zedgone', 'blank');
            approve(ann);
            approve(bob);
            update new User(Id = ann.Id, RLY_Slack_Member_Id__c = 'U0OLD1', RLY_Slack_Linked_By__c = 'Self');
            System.runAs(new User(Id = UserInfo.getUserId())) {
                update new User(Id = zed.Id, RLY_Slack_Member_Id__c = 'U0BOB1', IsActive = false);
            }
            Test.setMock(HttpCalloutMock.class, new SlackMock()
                .reply('email=' + ann.FederationIdentifier, 200, slackUser('U0ANN1', ann.FederationIdentifier))
                .reply('email=' + bob.FederationIdentifier, 200, slackUser('U0BOB1', bob.FederationIdentifier)));
            Test.startTest();
            RlySlackMatch.Pass pass = RlySlackApprovers.matchPass(new List<Id>{ ann.Id, bob.Id }, 0);
            Test.stopTest();
            User a = reload(ann.Id);
            System.assertEquals('U0OLD1', a.RLY_Slack_Member_Id__c, 'Self link kept');
            System.assert(a.RLY_Slack_Match_Note__c.startsWith('Changed in Slack'), a.RLY_Slack_Match_Note__c);
            System.assertEquals('U0BOB1', reload(bob.Id).RLY_Slack_Member_Id__c, 'Moved from the deactivated user');
            System.assertEquals(null, reload(zed.Id).RLY_Slack_Member_Id__c, 'Cleared');
            System.assertEquals(1, pass.changed, 'Bob');
            RlySlackApprovers.Window w = RlySlackApprovers.load();
            System.assertEquals(RlySlackReason.CHANGED, rowOf(w, ann.Id).reasonCode, 'Changed in Slack');
            w = RlySlackApprovers.fixRow(ann.Id, 'keep');
            System.assertEquals(null, rowOf(w, ann.Id).reasonCode, 'Kept: ' + w.message);
        }
    }

    @IsTest
    static void usedIdIsNotedThenMoved() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Deployed');
            User ann = person('Annmove', 'email');
            User ex = person('Exholder', 'blank');
            approve(ann);
            update new User(Id = ex.Id, RLY_Slack_Member_Id__c = 'U0ANN1');
            update new User(Id = ann.Id, RLY_Slack_Match_Note__c = 'Slack ID already used · by Exholder');
            Test.setMock(HttpCalloutMock.class, new SlackMock()
                .reply('email=' + ann.FederationIdentifier, 200, slackUser('U0ANN1', ann.FederationIdentifier)));
            RlySlackApprovers.Window before = RlySlackApprovers.load();
            System.assertEquals('used', rowOf(before, ann.Id).reasonCode, 'Used elsewhere');
            Test.startTest();
            Integer refused = 0;
            try { RlySlackApprovers.fixRow(ann.Id, 'use'); } catch (AuraHandledException e) { refused++; }
            try { RlySlackApprovers.fixRow(ann.Id, 'nope'); } catch (AuraHandledException e) { refused++; }
            RlySlackApprovers.Window w = RlySlackApprovers.fixRow(ann.Id, 'move');
            Test.stopTest();
            System.assertEquals(2, refused, 'Use refuses a held ID; unknown fix');
            System.assertEquals('U0ANN1', reload(ann.Id).RLY_Slack_Member_Id__c, 'Moved here');
            System.assertEquals('Admin', reload(ann.Id).RLY_Slack_Linked_By__c, 'By an admin');
            System.assertEquals(null, reload(ex.Id).RLY_Slack_Member_Id__c, 'Cleared there');
            System.assert(w.message.contains('moved from'), w.message);
        }
    }

    @IsTest
    static void setByHandUnlinkAndRemove() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Deployed');
            User ann = person('Annhand', 'blank');
            User ex = person('Exhand', 'blank');
            approve(ann);
            update new User(Id = ex.Id, RLY_Slack_Member_Id__c = 'U0TAKEN');
            Test.setMock(HttpCalloutMock.class, new SlackMock()
                .reply('user=U0NOPE', 200, '{"ok":false,"error":"user_not_found"}')
                .reply('user=U0TAKEN', 200, slackUser('U0TAKEN', 'ex@example.com'))
                .reply('user=U0NEW1', 200, slackUser('U0NEW1', 'ann@example.com')));
            Test.startTest();
            List<String> errors = new List<String>();
            for (String id : new List<String>{ 'U0NOPE', 'U0TAKEN', 'bad id', '' }) {
                try {
                    RlySlackApprovers.setMember(ann.Id, id);
                } catch (AuraHandledException e) {
                    errors.add(e.getMessage());
                }
            }
            RlySlackApprovers.Window w = RlySlackApprovers.setMember(ann.Id, ' u0new1 ');
            Test.stopTest();
            System.assertEquals(4, errors.size(), 'Refused: ' + errors);
            System.assertEquals('Slack has no member U0NOPE.', errors[0], 'Unknown');
            System.assert(errors[1].contains('already linked to'), errors[1]);
            System.assert(w.message.startsWith('Slack says U0NEW1 is Person U0NEW1'), w.message);
            User a = reload(ann.Id);
            System.assertEquals('Admin', a.RLY_Slack_Linked_By__c, 'By hand');
            System.assertEquals(UserInfo.getUserId(), a.RLY_Slack_Linked_By_User__c, 'Who set it');
            w = RlySlackApprovers.unlink(ann.Id);
            System.assertEquals(null, reload(ann.Id).RLY_Slack_Member_Id__c, 'Unlinked');
            Integer refused = 0;
            try { RlySlackApprovers.removeApprover(UserInfo.getUserId()); } catch (AuraHandledException e) { refused++; }
            try { RlySlackApprovers.removeApprover(ex.Id); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(2, refused, 'Admins and non-approvers can\'t be removed here');
            System.runAs(new User(Id = UserInfo.getUserId())) {
                w = RlySlackApprovers.removeApprover(ann.Id);
            }
            System.assertEquals(null, rowOf(w, ann.Id), 'No longer listed');
        }
    }

    @IsTest
    static void emailModeAndManual() {
        System.runAs(RlyTestData.admin()) {
            RLY_Notification__c s = RlyReleaseTestData.slackOn('Deployed');
            update new RLY_Notification__c(Id = s.Id, Slack_Match_By__c = 'Manual');
            User ann = person('Annmail', 'blank');
            approve(ann);
            RlySlackApprovers.Window w = RlySlackApprovers.load();
            System.assertEquals('notLinked', rowOf(w, ann.Id).reasonCode, 'Manual: not linked');
            System.assert(RlySlackApprovers.matchPass(null, 0).problem.contains('manual'), 'Nothing matched');
            update new RLY_Notification__c(Id = s.Id, Slack_Match_By__c = 'Email');
            User twin = person('Annmail', 'blank');
            approve(twin);
            update new List<User>{ new User(Id = ann.Id, RLY_Slack_Match_Note__c = RlySlackMatch.NOTE_SAME_EMAIL),
                new User(Id = twin.Id, RLY_Slack_Match_Note__c = RlySlackMatch.NOTE_SAME_EMAIL) };
            Test.setMock(HttpCalloutMock.class, new SlackMock()
                .reply('email=' + ann.Email, 200, slackUser('U0TWIN', ann.Email)));
            Test.startTest();
            RlySlackMatch.Pass pass = RlySlackApprovers.matchPass(new List<Id>{ ann.Id, twin.Id }, 0);
            System.assertEquals(0, pass.looked, 'Shared email: not looked up');
            w = RlySlackApprovers.fixRow(ann.Id, 'pick');
            Test.stopTest();
            System.assertEquals('U0TWIN', reload(ann.Id).RLY_Slack_Member_Id__c, 'Picked');
            System.assertEquals('pick', rowOf(w, twin.Id).reasonCode, 'The other still needs a pick');
        }
    }

    @IsTest
    static void othersAreRefused() {
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            Integer refused = 0;
            try { RlySlackApprovers.load(); } catch (AuraHandledException e) { refused++; }
            try { RlySlackApprovers.addApprovers(new List<Id>{ plain.Id }); } catch (AuraHandledException e) { refused++; }
            try { RlySlackApprovers.searchUsers('pla'); } catch (AuraHandledException e) { refused++; }
            try { RlySlackApprovers.unlink(plain.Id); } catch (AuraHandledException e) { refused++; }
            try { RlySlackApprovers.checkScopes(); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(5, refused, 'Admins only (and approvers for the list)');
        }
        System.runAs(RlyTestData.admin()) {
            Integer refused = 0;
            try { RlySlackApprovers.addApprovers(new List<Id>()); } catch (AuraHandledException e) { refused++; }
            try { RlySlackApprovers.fixRow(plain.Id, 'keep'); } catch (AuraHandledException e) { refused++; }
            try { RlySlackController.saveSlack('{"enabled":false,"matchBy":"Sometimes"}'); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(3, refused, 'Nobody picked; not an approver; unknown match setting');
            System.assertEquals('a\\%b\\_c', RlySlackApproverAdd.likeText('a%b_c'), 'Wildcards escaped');
            System.assertEquals(new List<String>(), RlySlackPeople.missing(null), 'Unknown scopes: nothing missing');
            System.assertEquals(null, RlySlackPeople.missingText(new List<String>()), 'Nothing missing');
        }
    }
}
