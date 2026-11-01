/**
 * @description Plain-language advice for failed Git calls: HTTP statuses (table-driven) and callouts
 * that didn't reach the provider.
 */
public with sharing class RlyGitAdvice {

    /** @description GitHub's workflow folder: changing files there needs the token's Workflows permission. */
    public static final String WORKFLOWS_FOLDER = '.github/workflows/';
    /** @description What a refused change to the workflow folder means. */
    public static final String WORKFLOWS_ADVICE = 'The token needs Workflows: Read and write to change files in .github/workflows.';

    private static final Map<Integer, String> BY_STATUS = new Map<Integer, String>{
        401 => 'The token in Named Credential {credential} was refused: check or renew it.',
        403 => 'The token lacks permission for this (or the provider rate-limited the request).',
        404 => 'Not found: check the repository name and that the token can see it.',
        400 => 'The provider rejected the request.',
        422 => 'The provider rejected the request.'
    };

    /**
     * @description Throws a GitException with advice unless the response is a 2xx.
     * @param res the provider's response
     * @param action what was being done, for the message
     * @param conn the Git connection
     */
    public static void requireSuccess(HttpResponse res, String action, RLY_Git_Connection__c conn) {
        Integer code = res.getStatusCode();
        if (code >= 200 && code < 300) {
            return;
        }
        String advice = BY_STATUS.containsKey(code)
            ? BY_STATUS.get(code).replace('{credential}', String.valueOf(conn.Named_Credential__c)) : '';
        throw new RlyGit.GitException((action + ' failed with HTTP ' + code + '. ' + advice + ' '
            + String.valueOf(res.getBody()).left(300)).trim());
    }

    /**
     * @description A failed pipeline files update in words: a refused commit in the workflow folder needs the token's
     * Workflows permission; anything else is said as it is.
     * @param raw the failure's message
     * @return the advice
     */
    public static String forPipelineFiles(String raw) {
        String m = raw == null ? '' : raw;
        if (m.startsWith('Committing ' + WORKFLOWS_FOLDER) && (m.contains('HTTP 403') || m.containsIgnoreCase('`workflow` scope'))) {
            return WORKFLOWS_ADVICE;
        }
        return m;
    }

    /**
     * @description Advice for a callout that didn't reach the provider.
     * @param raw the platform's error message
     * @param conn the Git connection
     * @return the advice
     */
    public static String forCallout(String raw, RLY_Git_Connection__c conn) {
        String m = raw == null ? '' : raw;
        if (m.containsIgnoreCase('named credential') || m.containsIgnoreCase('callout:') || m.containsIgnoreCase('credential')) {
            return 'Named Credential ' + conn.Named_Credential__c + ' wasn\'t found or you can\'t use it. Check it exists, and that your '
                + 'permission set has its principal under External Credential Principal Access. (' + m.left(300) + ')';
        }
        return 'Couldn\'t reach ' + conn.Provider__c + ': ' + m.left(300);
    }
}
