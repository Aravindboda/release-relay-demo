/**
 * @description GitLab pipelines as the hub's runs (build 45): find finds the newest API-started pipeline on the
 * pipeline branch whose name (from the CI file's workflow:name) stands for a run title (RlyRunTitles), reading a
 * pipeline and its variables when the list has no names (older GitLab); a pipeline's status and conclusion as GitHub
 * says them, a merge request's state as a pull request's, and the project's API path.
 */
public with sharing class RlyGitLabRuns {

    /** @description The newest pipelines find looks through. */
    private static final Integer RUNS_LISTED = 30;
    /** @description Most pipelines find opens one by one when the list has no names. */
    private static final Integer RUNS_OPENED = 5;

    /** @description A pipeline's status as a run's status: queued, in_progress or completed. */
    private static final Map<String, String> STATUS_OF = new Map<String, String>{
        'created' => 'queued', 'waiting_for_resource' => 'queued', 'preparing' => 'queued', 'pending' => 'queued',
        'scheduled' => 'queued', 'running' => 'in_progress', 'manual' => 'in_progress', 'canceling' => 'in_progress',
        'success' => 'completed', 'failed' => 'completed', 'canceled' => 'completed', 'skipped' => 'completed'
    };
    /** @description A finished pipeline's status as a run's conclusion. */
    private static final Map<String, String> CONCLUSION_OF = new Map<String, String>{
        'success' => 'success', 'failed' => 'failure', 'canceled' => 'cancelled', 'skipped' => 'skipped'
    };
    /** @description A merge request's state as a pull request's. */
    private static final Map<String, String> STATE_OF = new Map<String, String>{
        'opened' => 'open', 'locked' => 'open', 'merged' => 'merged', 'closed' => 'closed'
    };

    /**
     * @description The newest pipeline whose name stands for the title, among the recent API-started pipelines on the
     * connection's pipeline branch.
     * @param git the GitLab provider
     * @param title the run title
     * @return the run, or null
     */
    public static RlyGit.Run find(RlyGit git, String title) {
        List<Object> rows = (List<Object>) read(git, '/pipelines?ref=' + RlyGitRequest.encode(git.connection().Pipeline_Branch__c.trim())
            + '&source=api&order_by=id&sort=desc&per_page=' + RUNS_LISTED, 'Reading pipeline runs');
        Integer opened = 0;
        for (Object o : rows) {
            Map<String, Object> row = (Map<String, Object>) o;
            String name = RlySyncParse.text(row.get('name'));
            if (name == null && opened < RUNS_OPENED) {
                opened++;
                row = (Map<String, Object>) read(git, '/pipelines/' + row.get('id'), 'Reading pipeline ' + row.get('id'));
                name = RlySyncParse.text(row.get('name'));
                name = name == null ? nameFromVariables((List<Object>) read(git, '/pipelines/' + row.get('id') + '/variables',
                    'Reading pipeline ' + row.get('id'))) : name;
            }
            if (RlyRunTitles.matches(name, title)) {
                return toRun(row); // newest first
            }
        }
        return null;
    }

    // GET a path of the project, checked, parsed.
    private static Object read(RlyGit git, String path, String action) {
        HttpResponse res = git.request(new RlyGitRequest('GET', project(git, path), null));
        git.requireOk(res, action);
        return JSON.deserializeUntyped(res.getBody());
    }

    /**
     * @description A path of the connection's project in the GitLab API (the project path URL-encoded, slashes too).
     * @param git the GitLab provider
     * @param path what follows the project, for example /pipelines
     * @return /projects/group%2Fproject and the path
     */
    public static String project(RlyGit git, String path) {
        return '/projects/' + RlyGitRequest.encode(git.connection().Repository__c.trim()) + path;
    }

    /**
     * @description A pipeline as a run.
     * @param pipeline the pipeline (id, web_url, status)
     * @return the run
     */
    public static RlyGit.Run toRun(Map<String, Object> pipeline) {
        RlyGit.Run run = new RlyGit.Run();
        run.id = RlySyncParse.text(pipeline.get('id'));
        run.url = RlySyncParse.text(pipeline.get('web_url'));
        String state = RlySyncParse.text(pipeline.get('status'));
        run.status = STATUS_OF.containsKey(state) ? STATUS_OF.get(state) : 'queued';
        run.conclusion = run.status == 'completed' ? CONCLUSION_OF.get(state) : null;
        return run;
    }

    /**
     * @description The name workflow:name gives a pipeline, from its variables: Release Relay REQUEST_ID (MODE), and
     * " · " and TITLE when set.
     * @param variables the pipeline's variables ([{key, value}])
     * @return the name, or null without REQUEST_ID and MODE
     */
    public static String nameFromVariables(List<Object> variables) {
        Map<String, String> byKey = new Map<String, String>();
        for (Object o : variables == null ? new List<Object>() : variables) {
            Map<String, Object> v = o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
            byKey.put(RlySyncParse.text(v.get('key')), RlySyncParse.text(v.get('value')));
        }
        if (String.isBlank(byKey.get('REQUEST_ID')) || String.isBlank(byKey.get('MODE'))) {
            return null;
        }
        String name = 'Release Relay ' + byKey.get('REQUEST_ID') + ' (' + byKey.get('MODE') + ')';
        return String.isBlank(byKey.get('TITLE')) ? name : name + RlyRunTitles.SEPARATOR + byKey.get('TITLE');
    }

    /**
     * @description A merge request's state as a pull request's.
     * @param state opened, locked, merged or closed
     * @return open, merged or closed
     */
    public static String mergeRequestState(String state) {
        return STATE_OF.containsKey(state) ? STATE_OF.get(state) : state;
    }

    /**
     * @description A text value of a JSON object, or null when the body isn't one or hasn't got it.
     * @param body the JSON
     * @param key the key
     * @return the value
     */
    public static String textOf(String body, String key) {
        try {
            Object parsed = JSON.deserializeUntyped(body);
            return parsed instanceof Map<String, Object> ? RlySyncParse.text(((Map<String, Object>) parsed).get(key)) : null;
        } catch (JSONException e) {
            return null;
        }
    }
}
