/**
 * @description One Slack reminders call's messages (RlySlackDue): posts within a budget of MAX_POSTS; Slack's "busy"
 * (429) stops the call so the next hour carries on; any other refusal is counted and skipped. Callouts only.
 */
public with sharing class RlySlackPoster {

    /** @description Most Slack messages in one call. */
    public static final Integer MAX_POSTS = 25;
    /** @description Said when Slack answers "busy". */
    public static final String BUSY = 'Slack is busy (rate limited); the next hour carries on.';

    /** @description Messages sent. */
    public Integer sent = 0;
    /** @description Messages Slack refused. */
    public Integer refused = 0;
    /** @description Everything due was handled (false: call again). */
    public Boolean done = true;
    /** @description No more messages in this call (budget used, or Slack busy). */
    public Boolean stopped = false;
    /** @description Notes for the pipeline's log. */
    public String reason = '';

    /**
     * @description Posts one message, within the budget.
     * @param msg the chat.postMessage body (channel, text, thread_ts)
     * @return whether it went out
     */
    public Boolean post(Map<String, Object> msg) {
        if (stopped) {
            return false;
        }
        if (sent + refused >= MAX_POSTS) {
            done = false;
            stopped = true;
            return false;
        }
        try {
            RlySlackApi.call('chat.postMessage', msg);
            sent++;
            return true;
        } catch (Exception e) {
            if (RlySlackApi.isRateLimited(e)) {
                reason += BUSY;
                stopped = true;
            } else {
                refused++;
                reason += 'Slack refused a message: ' + e.getMessage().left(200) + ' ';
            }
            return false;
        }
    }
}
