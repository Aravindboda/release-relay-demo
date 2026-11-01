/**
 * @description The Slack bot token, saved from the Pipeline tab straight into the External Credential RLY_Slack
 * (named principal Bot, authentication parameter Token, encrypted) through ConnectApi.NamedCredentials. The token is
 * never stored in a record, logged, returned or put in a message: only its last four characters are kept, for the
 * masked hint. Saving a credential counts as uncommitted work, so no callout may follow it in the same transaction:
 * the page tests the connection in its next call. The running admin needs Read, Create, Edit and Delete on User
 * External Credentials (RLY_Admin grants it) and access to the principal RLY_Slack-Bot.
 * Tests replace store() through RlySlackController.tokenStore, because ConnectApi credentials can't be written there.
 */
public virtual with sharing class RlyBotToken {

    /** @description The External Credential that holds the bot token. */
    public static final String SLACK_CREDENTIAL = 'RLY_Slack';
    /** @description Its named principal. */
    public static final String PRINCIPAL = 'Bot';
    /** @description The authentication parameter the Named Credential reads ($Credential.RLY_Slack.Token). */
    public static final String TOKEN_PARAMETER = 'Token';
    /** @description What every Slack bot token starts with. */
    public static final String BOT_PREFIX = 'xoxb-';
    /** @description The status of a Slack app that answers. */
    public static final String CONNECTED = 'Connected';

    private static final Pattern TOKEN_SHAPE = Pattern.compile('^xoxb-[A-Za-z0-9-]{10,250}$');

    private final String credentialName;

    /** @description Saving into RLY_Slack. */
    public RlyBotToken() {
        this(SLACK_CREDENTIAL);
    }

    /**
     * @description Saving into another External Credential (tests).
     * @param credentialName the External Credential's developer name
     */
    public RlyBotToken(String credentialName) {
        this.credentialName = credentialName;
    }

    /**
     * @description Checks the pasted token and returns it trimmed, or throws with a message that never contains it.
     * @param token what the admin pasted
     * @return the token, trimmed
     */
    public static String checked(String token) {
        String value = token == null ? '' : token.trim();
        if (String.isBlank(value)) {
            throw RlySlackController.auraError('Paste the bot token (it starts with ' + BOT_PREFIX + ').');
        }
        if (!value.startsWith(BOT_PREFIX)) {
            throw RlySlackController.auraError('That isn\'t a bot token. Copy the Bot User OAuth Token (it starts with '
                + BOT_PREFIX + ') from OAuth & Permissions in your Slack app.');
        }
        if (!TOKEN_SHAPE.matcher(value).matches()) {
            throw RlySlackController.auraError('The bot token looks incomplete. Copy it again from your Slack app.');
        }
        return value;
    }

    /**
     * @description The masked hint for a saved token.
     * @param lastFour the last four characters kept on the Slack record, or null
     * @param status the connection status (Connected when the Slack app answers)
     * @return Saved (ends ••••xxxx), Saved in Setup when connected without a hint, or null
     */
    public static String hint(String lastFour, String status) {
        if (String.isNotBlank(lastFour)) {
            return 'Saved (ends ••••' + lastFour + ')';
        }
        return status == CONNECTED ? 'Saved in Setup' : null;
    }

    /**
     * @description Writes the token into the principal's encrypted Token parameter: patched when the principal has
     * credentials already, created otherwise. Other parameters of the principal are kept.
     * @param token the checked token
     */
    public virtual void store(String token) {
        ConnectApi.CredentialInput input = new ConnectApi.CredentialInput();
        input.externalCredential = credentialName;
        input.principalName = PRINCIPAL;
        input.principalType = ConnectApi.CredentialPrincipalType.NamedPrincipal;
        input.authenticationProtocol = ConnectApi.CredentialAuthenticationProtocol.Custom;
        ConnectApi.CredentialValueInput secret = new ConnectApi.CredentialValueInput();
        secret.encrypted = true;
        secret.value = token;
        input.credentials = new Map<String, ConnectApi.CredentialValueInput>{ TOKEN_PARAMETER => secret };
        try {
            if (hasCredentials()) {
                ConnectApi.NamedCredentials.patchCredential(input);
            } else {
                ConnectApi.NamedCredentials.createCredential(input);
            }
        } catch (Exception e) {
            throw RlySlackController.auraError(failure(e.getMessage(), token));
        }
    }

    /**
     * @description Why saving failed, in words, with the token blanked out of Salesforce's message.
     * @param reason Salesforce's message
     * @param token the token, to blank out
     * @return the message
     */
    public static String failure(String reason, String token) {
        String cleanReason = String.isBlank(reason) ? 'no reason given' : reason;
        if (String.isNotBlank(token)) {
            cleanReason = cleanReason.replace(token, '••••');
        }
        return ('The bot token wasn\'t saved: ' + cleanReason + ' Check that you have the ' + System.Label.RLY_App_Name
            + ' Admin permission set, or save it in Setup: Named Credentials > External Credentials > RLY Slack > '
            + 'principal Bot > parameter Token.').left(1000);
    }

    // Whether the principal has any credentials yet (a principal without any is created, not patched).
    private Boolean hasCredentials() {
        try {
            ConnectApi.Credential saved = ConnectApi.NamedCredentials.getCredential(credentialName, PRINCIPAL,
                ConnectApi.CredentialPrincipalType.NamedPrincipal);
            return saved != null && saved.credentials != null && !saved.credentials.isEmpty();
        } catch (ConnectApi.ConnectApiException e) {
            return false;
        }
    }
}
