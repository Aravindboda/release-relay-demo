/**
 * @description A release can't be raised, moved along or acted on; the message says why, in words the page shows.
 * Also turns any error into the one the page shows (every controller uses these, so the wording stays the same).
 */
public with sharing class RlyReleaseException extends Exception {

    /**
     * @description The page's error for an exception: an AuraHandledException as it is, any other with its message.
     * @param e the exception
     * @return the error the page shows
     */
    public static AuraHandledException toAura(Exception e) {
        return toAura(e, null);
    }

    /**
     * @description The page's error for an exception, with a prefix for errors that aren't Release Relay's own.
     * @param e the exception
     * @param prefix put before the message of an unexpected error (null for none)
     * @return the error the page shows
     */
    public static AuraHandledException toAura(Exception e, String prefix) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        Boolean own = prefix == null || e instanceof RlyReleaseException;
        return toAura(own ? e.getMessage() : prefix + e.getMessage());
    }

    /**
     * @description An error the page shows as it is.
     * @param message the sentence
     * @return the exception to throw
     */
    public static AuraHandledException toAura(String message) {
        AuraHandledException a = new AuraHandledException(message);
        a.setMessage(message);
        return a;
    }
}
