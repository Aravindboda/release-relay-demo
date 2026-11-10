/**
 * @description The Migration tab's steps up to the new setup (build 46): start a migration from the active connection,
 * read what it holds, configure and check the new connection, pick the method, the dry run and the run, Update pipeline
 * files and Check on the new connection, the checklists' Done marks and moving between steps. Each action makes its
 * callouts first and saves once at the end; every action is logged with who and when. The controller checks the admin.
 */
public with sharing class RlyMigrationSteps {

    private static final Set<Integer> STEPS = new Set<Integer>{ 1, 2, 3, 4, 5, 6, 7, 8 };
    private static final Set<String> PROVIDERS = new Set<String>{ 'GitHub', 'GitLab', 'Bitbucket', 'AzureDevOps' };

    /**
     * @description Starts a migration from the active connection (one at a time), reading its branches.
     * @return the migration
     */
    public static RLY_Migration__c start() {
        if (RlyMigrationStore.current() != null) {
            throw new RlyReleaseException('A migration is already going: continue it, or cancel it first.');
        }
        RLY_Git_Connection__c current = RlyGitConnections.byId(RlyGitConnections.activeId());
        if (current == null) {
            throw new RlyReleaseException('Set up the Git connection first (Pipeline tab).');
        }
        RlyMigrationState state = new RlyMigrationState();
        readBranches(current, state);
        RLY_Migration__c m = new RLY_Migration__c(Current_Connection__c = current.Id, Status__c = RlyMigrationStore.OPEN, Step__c = 1,
            Migration_Id__c = 'MIG-' + String.valueOf(System.now().getTime()).leftPad(13, '0'));
        state.log('Current → New', 'Started the move away from ' + RlyMigrationMethods.labelOf(current.Provider__c) + ' ' + current.Repository__c);
        m.State__c = state.toJson();
        RlyMigrationStore.save(m);
        return m;
    }

    /**
     * @description Reads the current repository's branches again.
     * @param m the migration
     */
    public static void readCurrentBranches(RLY_Migration__c m) {
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        readBranches(RlyGitConnections.byId(m.Current_Connection__c), state);
        RlyMigrationGuard.save(m, state);
    }

    /**
     * @description Saves the new connection (inactive until the switch): its provider can't be the current one's.
     * @param m the migration
     * @param connectionJson {Provider__c, Repository__c, Named_Credential__c, Pipeline__c, Pipeline_Branch__c}
     */
    public static void saveNewConnection(RLY_Migration__c m, String connectionJson) {
        RlyMigrationGuard.requireOpen(m);
        RLY_Git_Connection__c input = (RLY_Git_Connection__c) JSON.deserialize(connectionJson, RLY_Git_Connection__c.class);
        RLY_Git_Connection__c current = RlyGitConnections.byId(m.Current_Connection__c);
        RLY_Git_Connection__c row = rowOf(input, current);
        String p = row.Provider__c;
        for (RLY_Git_Connection__c c : RlyGitConnections.connections()) {
            if (c.Provider__c == p) {
                row.Id = c.Id; // one connection per provider: the existing (inactive) one is reused
            }
        }
        RlyMigrationStore.saveConnection(row);
        RlyGitConnections.forget();
        m.New_Connection__c = row.Id;
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        state.targetCheck = null;
        state.targetBranches = null;
        state.log('Current → New', 'New connection: ' + row.Name);
        RlyMigrationGuard.save(m, state);
    }

    /**
     * @description Checks the new repository: reachable, and empty or holding branches (which methods fit).
     * @param m the migration
     */
    public static void checkNewRepository(RLY_Migration__c m) {
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        try {
            RlyMigrationRepo.Refs refs = RlyMigrationRepo.refs(RlyGit.forConnection(RlyMigrationGuard.requireTarget(m)));
            state.targetBranches = refs.branches.size();
            state.targetCheck = refs.branches.isEmpty() ? 'Reachable · empty'
                : 'Reachable · holds ' + refs.branches.size() + (refs.more ? '+' : '') + ' branch(es): ' + refs.someNames();
        } catch (Exception e) {
            state.targetBranches = null;
            state.targetCheck = 'Not reachable: ' + e.getMessage().left(500);
        }
        state.log('Current → New', 'Checked the new repository: ' + state.targetCheck);
        RlyMigrationGuard.save(m, state);
    }

    /**
     * @description Picks the method (only one that's possible for the pair).
     * @param m the migration
     * @param method lift, importer or fresh
     */
    public static void choose(RLY_Migration__c m, String method) {
        RlyMigrationGuard.requireOpen(m);
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        RlyMigrationMethods.Method picked;
        for (RlyMigrationMethods.Method x : RlyMigrationMethods.forPair(RlyGitConnections.byId(m.Current_Connection__c),
                RlyGitConnections.byId(m.New_Connection__c), state.targetBranches)) {
            picked = x.key == method ? x : picked;
        }
        if (picked == null || picked.possible != true) {
            throw new RlyReleaseException(picked == null ? 'Pick lift and shift, the importer or a fresh start.' : picked.why);
        }
        m.Method__c = method;
        m.Dry_Run__c = null;
        m.Result__c = null;
        m.Run_Status__c = null;
        m.Step__c = 2; // stays on How: Next goes to the dry run (build 52)
        state.log('How', 'Picked ' + picked.label);
        RlyMigrationGuard.save(m, state);
    }






    /**
     * @description Sets or clears a checklist item's Done mark.
     * @param m the migration
     * @param key the item
     * @param value done, or anything else to clear it
     */
    public static void mark(RLY_Migration__c m, String key, String value) {
        Boolean done = value == RlyMigrationState.DONE;
        if (String.isBlank(key)) {
            throw new RlyReleaseException('That checklist item isn\'t known.');
        }
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        state.mark(key, value);
        state.log(key.startsWith('old.') ? 'Old setup' : 'New setup', (done == true ? 'Done: ' : 'Not done: ') + key);
        RlyMigrationGuard.save(m, state);
    }

    /**
     * @description Moves the wizard to a step.
     * @param m the migration
     * @param step 1 to 8
     */
    public static void goTo(RLY_Migration__c m, Integer step) {
        if (!STEPS.contains(step)) {
            throw new RlyReleaseException('Steps go from 1 to 8.');
        }
        m.Step__c = step;
        RlyMigrationStore.save(new RLY_Migration__c(Id = m.Id, Step__c = step));
    }




    // The new connection's fields, checked: another provider than the current one, the fields filled, the repository's shape.
    private static RLY_Git_Connection__c rowOf(RLY_Git_Connection__c input, RLY_Git_Connection__c current) {
        String p = input.Provider__c;
        if (!PROVIDERS.contains(p) || p == current.Provider__c) {
            throw new RlyReleaseException('Pick a provider other than the current one: GitHub, GitLab, Bitbucket or Azure DevOps.');
        }
        if (String.isBlank(input.Repository__c) || String.isBlank(input.Named_Credential__c) || String.isBlank(input.Pipeline_Branch__c)) {
            throw new RlyReleaseException('Fill in the repository, the Named Credential and the pipeline branch.');
        }
        RLY_Git_Connection__c row = new RLY_Git_Connection__c(Provider__c = p, Repository__c = input.Repository__c.trim(),
            Named_Credential__c = input.Named_Credential__c.trim(), Pipeline_Branch__c = input.Pipeline_Branch__c.trim(),
            Pipeline__c = String.isBlank(input.Pipeline__c) ? null : input.Pipeline__c.trim(), Source_Path__c = current.Source_Path__c,
            Name = (RlyMigrationMethods.labelOf(p) + ' ' + input.Repository__c.trim()).left(80), Status__c = 'Not checked');
        RlyGit.forConnection(row); // the repository's shape, checked without a callout
        return row;
    }

    private static void readBranches(RLY_Git_Connection__c current, RlyMigrationState state) {
        RlyMigrationRepo.Refs refs = RlyMigrationRepo.refs(RlyGit.forConnection(current));
        state.branches = refs.branches;
        state.moreBranches = refs.more;
        state.branchesReadOn = System.now();
    }
}
