/**
 * @description The pipeline files packaged with the hub (static resources RLY_Pipeline_*), compared with the copies in
 * the hub's Git repository on the pipeline branch, and updated there (admins) by a pull request or a direct commit.
 * Every file carries a line "Release Relay pipeline files: version N"; the lowest version among this hub's files counts.
 * Callouts only; nothing is saved in the hub.
 */
public with sharing class RlyPipelineFiles {

    /** @description Update by a pull request into the pipeline branch (the default). */
    public static final String VIA_PULL_REQUEST = 'pullRequest';
    /** @description Update by committing straight to the pipeline branch. */
    public static final String VIA_COMMIT = 'commit';
    /** @description Provider value of the files every provider needs. */
    public static final String EVERY_PROVIDER = 'All';

    private static final Pattern VERSION_LINE = Pattern.compile('Release Relay pipeline files: version (\\d+)');
    private static final String WORKFLOWS_FOLDER = RlyGitAdvice.WORKFLOWS_FOLDER;
    private static final String DEFAULT_WORKFLOW = 'release-relay.yml';
    private static final String DEFAULT_GITLAB_FILE = '.gitlab-ci.yml';
    private static final String NO_CONNECTION = 'Save the Git connection first.';

    /** @description What the Pipeline tab and the Guide show about the pipeline files. */
    public class Status {
        /** @description The version packaged with the hub (lowest among this hub's files). */
        @AuraEnabled public Integer packagedVersion;
        /** @description The version in the repository (lowest among this hub's files), or null when a file isn't there. */
        @AuraEnabled public Integer repoVersion;
        /** @description The hub's Git provider (GitHub, GitLab, Bitbucket, AzureDevOps), or null without a connection. */
        @AuraEnabled public String provider;
        /** @description The pipeline branch the files are read from. */
        @AuraEnabled public String branch;
        /** @description The current user is an admin (can update the files). */
        @AuraEnabled public Boolean isAdmin = false;
        /** @description The repository has this version or a newer one. */
        @AuraEnabled public Boolean upToDate = false;
        /** @description Every packaged file, this hub's first. */
        @AuraEnabled public List<FileInfo> files = new List<FileInfo>();
        /** @description The comparison in words, or why it couldn't be made. */
        @AuraEnabled public String message;
    }

    /** @description One packaged pipeline file. */
    public class FileInfo {
        /** @description The file's name, for example release-relay.yml. */
        @AuraEnabled public String name;
        /** @description Its path in the repository. */
        @AuraEnabled public String repoPath;
        /** @description GitHub, GitLab, Bitbucket, AzureDevOps or All. */
        @AuraEnabled public String provider;
        /** @description The static resource it's packaged in. */
        @AuraEnabled public String resourceName;
        /** @description It's for this hub's provider (or every provider). */
        @AuraEnabled public Boolean forThisHub = false;
        /** @description Its version in the repository, or null (not read, or not there). */
        @AuraEnabled public Integer repoVersion;

        /**
         * @description A packaged file.
         * @param resourceName the static resource
         * @param provider the provider it's for, or All
         * @param repoPath its path in the repository
         */
        public FileInfo(String resourceName, String provider, String repoPath) {
            this.resourceName = resourceName;
            this.provider = provider;
            this.repoPath = repoPath;
            this.name = repoPath.contains('/') ? repoPath.substringAfterLast('/') : repoPath;
        }
    }

    /** @description What an update did. */
    public class UpdateResult {
        /** @description The files were written. */
        @AuraEnabled public Boolean ok = false;
        /** @description Link to the pull request or the commit, or null. */
        @AuraEnabled public String url;
        /** @description What happened, in words. */
        @AuraEnabled public String message;
    }

    /**
     * @description The packaged version, the repository's version and every file.
     * @return the status
     */
    public static Status currentStatus() {
        Data data = new Data();
        RLY_Git_Connection__c conn = data.git();
        Status s = new Status();
        s.isAdmin = RlyOrgController.isAdmin();
        s.files = catalog(conn);
        s.packagedVersion = lowestPackaged(hubFiles(s.files), data.bodies(s.files));
        if (conn == null) {
            s.message = NO_CONNECTION;
            return s;
        }
        s.provider = conn.Provider__c;
        s.branch = conn.Pipeline_Branch__c;
        try {
            compare(RlyGit.forConnection(conn), s);
        } catch (Exception e) {
            s.message = RlyGitAdvice.forPipelineFiles(e.getMessage());
        }
        return s;
    }

    /**
     * @description The version packaged with the hub, read without a callout (the Home tab's health line).
     * @return the lowest version among this hub's packaged files, or null when none is packaged
     */
    public static Integer packagedVersion() {
        Data data = new Data();
        List<FileInfo> files = catalog(data.git());
        return lowestPackaged(hubFiles(files), data.bodies(files));
    }

    /**
     * @description Writes this hub's packaged files to the repository: on a branch with a pull request into the
     * pipeline branch, or straight to the pipeline branch. The caller checks the user is an admin.
     * @param how pullRequest (the default) or commit
     * @return what happened
     */
    public static UpdateResult updateRepository(String how) {
        UpdateResult r = new UpdateResult();
        Data data = new Data();
        RLY_Git_Connection__c conn = data.git();
        if (conn == null) {
            r.message = NO_CONNECTION;
            return r;
        }
        try {
            List<FileInfo> files = hubFiles(catalog(conn));
            Map<String, String> packaged = data.bodies(files);
            RlyPipelineUpdate job = new RlyPipelineUpdate(RlyGit.forConnection(conn), conn.Pipeline_Branch__c.trim(), files);
            job.load(packaged, lowestPackaged(files, packaged));
            job.apply(how, r);
        } catch (Exception e) {
            r.ok = false;
            r.message = RlyGitAdvice.forPipelineFiles(e.getMessage());
        }
        return r;
    }

    /**
     * @description The version stamped in a pipeline file.
     * @param text the file's content
     * @return the version, or 0 when the file has no version line (older than numbered files)
     */
    public static Integer versionIn(String text) {
        Matcher m = VERSION_LINE.matcher(text == null ? '' : text);
        return m.find() ? Integer.valueOf(m.group(1)) : 0;
    }

    // Every packaged file and its path in this hub's repository, this hub's files first.
    private static List<FileInfo> catalog(RLY_Git_Connection__c conn) {
        String hub = conn == null ? null : conn.Provider__c;
        List<FileInfo> known = new List<FileInfo>{
            new FileInfo('RLY_Pipeline_GitHub', 'GitHub', WORKFLOWS_FOLDER + configured(conn, 'GitHub', DEFAULT_WORKFLOW)),
            new FileInfo('RLY_Pipeline_GitLab', 'GitLab', configured(conn, 'GitLab', DEFAULT_GITLAB_FILE)),
            new FileInfo('RLY_Pipeline_Bitbucket', RlyGit.BITBUCKET, 'bitbucket-pipelines.yml'),
            new FileInfo('RLY_Pipeline_Azure', 'AzureDevOps', 'azure-pipelines.yml'),
            new FileInfo('RLY_Pipeline_Script', EVERY_PROVIDER, 'scripts/release-relay.js')
        };
        List<FileInfo> ordered = new List<FileInfo>();
        List<FileInfo> others = new List<FileInfo>();
        for (FileInfo f : known) {
            f.forThisHub = f.provider == EVERY_PROVIDER || f.provider == hub;
            if (f.forThisHub) {
                ordered.add(f);
            } else {
                others.add(f);
            }
        }
        ordered.addAll(others);
        return ordered;
    }

    // The connection's Pipeline__c when the hub is on this provider (its workflow or CI file), otherwise the usual name.
    private static String configured(RLY_Git_Connection__c conn, String provider, String fallback) {
        return conn != null && conn.Provider__c == provider && String.isNotBlank(conn.Pipeline__c) ? conn.Pipeline__c.trim() : fallback;
    }

    private static List<FileInfo> hubFiles(List<FileInfo> files) {
        List<FileInfo> out = new List<FileInfo>();
        for (FileInfo f : files) {
            if (f.forThisHub) {
                out.add(f);
            }
        }
        return out;
    }

    // The lowest version among the files' packaged copies, or null when none is packaged.
    private static Integer lowestPackaged(List<FileInfo> files, Map<String, String> bodies) {
        Integer lowest;
        for (FileInfo f : files) {
            if (bodies.containsKey(f.resourceName)) {
                lowest = lower(lowest, versionIn(bodies.get(f.resourceName)));
            }
        }
        return lowest;
    }

    // Reads this hub's files on the pipeline branch (callouts only).
    private static void compare(RlyGit git, Status s) {
        List<String> missing = new List<String>();
        Integer lowest;
        for (FileInfo f : hubFiles(s.files)) {
            String text = git.getFileRaw(f.repoPath, s.branch.trim());
            if (text == null) {
                missing.add(f.repoPath);
            } else {
                f.repoVersion = versionIn(text);
                lowest = lower(lowest, f.repoVersion);
            }
        }
        s.repoVersion = missing.isEmpty() ? lowest : null;
        s.upToDate = s.repoVersion != null && s.packagedVersion != null && s.repoVersion >= s.packagedVersion;
        s.message = describe(s, missing);
    }

    private static String describe(Status s, List<String> missing) {
        if (!missing.isEmpty()) {
            return 'Not found in your repository on ' + s.branch + ': ' + String.join(missing, ', ') + '.';
        }
        if (s.upToDate) {
            return 'Up to date (version ' + s.repoVersion + ').';
        }
        String inRepo = s.repoVersion == 0 ? 'An older version without a number' : 'Version ' + s.repoVersion;
        return inRepo + ' in your repository · version ' + s.packagedVersion + ' available.';
    }

    // The lower of two versions (null counts as none yet).
    private static Integer lower(Integer lowest, Integer candidate) {
        return lowest == null || candidate < lowest ? candidate : lowest;
    }

    /** @description The Git connection and the packaged files are hub configuration: read in system mode. */
    private without sharing class Data {

        /**
         * @description The hub's Git connection.
         * @return the connection, or null
         */
        public RLY_Git_Connection__c git() {
            List<RLY_Git_Connection__c> rows = [SELECT Id, Provider__c, Repository__c, Named_Credential__c, Pipeline__c, Pipeline_Branch__c
                                                FROM RLY_Git_Connection__c WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description The packaged content of the files.
         * @param files the files
         * @return static resource name to content
         */
        public Map<String, String> bodies(List<FileInfo> files) {
            Set<String> names = new Set<String>();
            for (FileInfo f : files) {
                names.add(f.resourceName);
            }
            Map<String, String> out = new Map<String, String>();
            for (StaticResource sr : [SELECT Name, Body FROM StaticResource WHERE Name IN :names WITH SYSTEM_MODE]) {
                out.put(sr.Name, sr.Body.toString());
            }
            return out;
        }
    }
}
