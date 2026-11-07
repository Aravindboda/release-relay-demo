/**
 * @description Work items (build 40): the shapes the Work items pages read and the tracker calls pass around. Data only.
 */
public with sharing class RlyWorkTypes {

    /** @description The work tracking settings as the pages read them (no secrets: those stay in the Named Credential). */
    public class Settings {
        /** @description Jira, Azure_Boards, ServiceNow, None or Other. */
        @AuraEnabled public String tracker;
        /** @description Tickets required to raise. */
        @AuraEnabled public Boolean required = false;
        /** @description Ticket formats (regular expressions, space separated). */
        @AuraEnabled public String ticketPattern;
        /** @description Link with {id}. */
        @AuraEnabled public String linkPattern;
        /** @description The Named Credential's API name. */
        @AuraEnabled public String namedCredential;
        /** @description Post each moment to the ticket. */
        @AuraEnabled public Boolean postUpdates = false;
        /** @description Moment → state JSON. */
        @AuraEnabled public String stateMap;
        /** @description ServiceNow table for work notes. */
        @AuraEnabled public String serviceNowTable;
        /** @description ServiceNow: approved change before production. */
        @AuraEnabled public Boolean requireChange = false;
        /** @description ServiceNow change format. */
        @AuraEnabled public String changePattern;
        /** @description The tracker in words. */
        @AuraEnabled public String trackerLabel;
        /** @description The viewer can change the settings. */
        @AuraEnabled public Boolean isAdmin = false;
    }

    /** @description A ticket on a release. */
    public class TicketView {
        /** @description The ticket. */
        @AuraEnabled public String ticket;
        /** @description Its link, or null. */
        @AuraEnabled public String link;
        /** @description Posted, Failed or Tracked here. */
        @AuraEnabled public String status;
        /** @description The moment last posted. */
        @AuraEnabled public String posted;
        /** @description What the tracker said. */
        @AuraEnabled public String message;
        /** @description When. */
        @AuraEnabled public Datetime syncedOn;
    }

    /** @description A release's tickets. */
    public class ReleaseTickets {
        /** @description The tickets. */
        @AuraEnabled public List<TicketView> tickets = new List<TicketView>();
        /** @description They can still change (not deployed, rejected or closed). */
        @AuraEnabled public Boolean canEdit = false;
        /** @description The tracker in words. */
        @AuraEnabled public String trackerLabel;
    }

    /** @description The Work items tab. */
    public class Board {
        /** @description The route's stages and the hub, in order. */
        @AuraEnabled public List<String> orgs = new List<String>();
        /** @description One row per ticket, newest first. */
        @AuraEnabled public List<TicketRow> tickets = new List<TicketRow>();
        /** @description The tracker, for the header. */
        @AuraEnabled public String trackerLabel;
        /** @description More rows than one read takes. */
        @AuraEnabled public Boolean truncated = false;
    }

    /** @description One ticket on the tab. */
    public class TicketRow {
        /** @description The ticket. */
        @AuraEnabled public String ticket;
        /** @description Its link, or null. */
        @AuraEnabled public String link;
        /** @description The releases carrying it, newest first. */
        @AuraEnabled public List<ReleaseRef> releases = new List<ReleaseRef>();
        /** @description When it was first raised. */
        @AuraEnabled public Datetime raisedOn;
        /** @description One cell per route org. */
        @AuraEnabled public List<Cell> cells = new List<Cell>();
        /** @description In PROD, Waiting for PROD, In SIT approval, Blocked or In progress. */
        @AuraEnabled public String status;
        /** @description ok, run, wait or bad. */
        @AuraEnabled public String tone;
        /** @description inprod, blocked or inprogress (the tab's filter). */
        @AuraEnabled public String bucket;
        /** @description Synced, Couldn't post, Tracked here. */
        @AuraEnabled public String syncText;
        /** @description ok, bad or none. */
        @AuraEnabled public String syncTone;
        /** @description What the tracker last said. */
        @AuraEnabled public String syncMessage;
        /** @description Lower-cased text the search looks in. */
        @AuraEnabled public String searchText;
    }

    /** @description A release on a ticket. */
    public class ReleaseRef {
        /** @description The release. */
        @AuraEnabled public Id id;
        /** @description REL-00044. */
        @AuraEnabled public String name;
        /** @description Hotfix or promotion. */
        @AuraEnabled public String kind;
    }

    /** @description Where a ticket is in one org. */
    public class Cell {
        /** @description The org. */
        @AuraEnabled public String org;
        /** @description For example deployed 5 Nov. */
        @AuraEnabled public String text;
        /** @description ok, run, wait, bad or none. */
        @AuraEnabled public String tone;
    }

    /** @description One moment for one ticket, as posted to the tracker. */
    public class Message {
        /** @description The ticket. */
        public String ticket;
        /** @description The moment, for example Deployed to SIT. */
        public String moment;
        /** @description The comment. */
        public String text;
        /** @description The release's details (release, title, org, url) for a web call. */
        public Map<String, Object> data = new Map<String, Object>();
        /** @description The tracker state mapped to the moment, or null. */
        public String state;
    }

    /** @description What one post came to. */
    public class Outcome {
        /** @description It worked. */
        public Boolean ok = false;
        /** @description What the tracker said, or why it failed. */
        public String message;
    }

    /** @description A ServiceNow change request. */
    public class Change {
        /** @description Approved and inside its planned window now. */
        public Boolean allowed = false;
        /** @description In words. */
        public String message;
    }
}
