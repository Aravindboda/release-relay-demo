/**
 * @description Settings changes (build 50): the parts of RlySettingsLog that turn records into snapshot items (orgs with
 * the route order, work trackers with their order) and two snapshots into log rows. No SOQL or DML here.
 */
public with sharing class RlySettingsLogDiff {

    /** @description The subject of the route order item. */
    public static final String ROUTE = 'route';
    /** @description The subject of the tracker order item. */
    public static final String TRACKER_ORDER = 'trackers';
    /** @description Between the names in an order. */
    public static final String ARROW = ' → ';

    /**
     * @description Adds the orgs to a snapshot: each org's settings (labelled with its name), the org itself (added,
     * removed or renamed) and the route order.
     * @param orgs the orgs
     * @param sp how to read an org
     * @param into the snapshot
     */
    public static void orgsInto(List<RLY_Org__c> orgs, RlySettingsLog.Spec sp, RlySettingsLog.Snapshot into) {
        List<RLY_Org__c> stages = new List<RLY_Org__c>();
        for (RLY_Org__c o : orgs) {
            into.items.put(o.Id + '|*', marker(o.Id, 'Org', o.Name));
            RlySettingsLog.addRecord(o, RlySettingsLog.withPrefix(sp, o.Name + ' · '), into);
            if (RlyRouteRules.isStage(o)) {
                stages.add(o);
            }
        }
        List<String> names = new List<String>();
        for (RLY_Org__c o : RlyRouteRules.ordered(stages)) {
            names.add(o.Name);
        }
        into.items.put(ROUTE + '|order', order(ROUTE, 'Route', names));
    }

    /**
     * @description Adds the work trackers to a snapshot: each tracker's settings, the tracker itself and their order.
     * @param trackers the trackers, in routing order
     * @param sp how to read a tracker
     * @param into the snapshot
     */
    public static void trackersInto(List<RLY_Work_Tracker__c> trackers, RlySettingsLog.Spec sp, RlySettingsLog.Snapshot into) {
        List<String> names = new List<String>();
        for (RLY_Work_Tracker__c t : trackers) {
            RlySettingsLog.Item m = marker(t.Id, 'Tracker', t.Name);
            m.section = RlySettingsLog.SECTION_TRACKING;
            into.items.put(t.Id + '|*', m);
            RlySettingsLog.addRecord(t, RlySettingsLog.withPrefix(sp, 'Tracker "' + t.Name + '" · '), into);
            names.add(t.Name);
        }
        into.items.put(TRACKER_ORDER + '|order', order(TRACKER_ORDER, 'Tracker order', names));
    }

    /**
     * @description The log rows for what differs between two snapshots of one area: a changed value, an added or removed
     * record (one row, not one per field) or a renamed one. At most RlySettingsLog.MOST_PER_SAVE rows.
     * @param was the items before the save
     * @param now the items after it
     * @return the rows, not saved
     */
    public static List<RLY_Settings_Change__c> rows(Map<String, RlySettingsLog.Item> was, Map<String, RlySettingsLog.Item> now) {
        Set<String> moved = new Set<String>();
        Set<String> keys = new Set<String>(was.keySet());
        keys.addAll(now.keySet());
        for (String k : keys) {
            if (k.endsWith('|*') && was.containsKey(k) != now.containsKey(k)) {
                moved.add(k.removeEnd('|*'));
            }
        }
        List<RLY_Settings_Change__c> out = new List<RLY_Settings_Change__c>();
        for (String k : keys) {
            RLY_Settings_Change__c r = rowFor(was.get(k), now.get(k), moved);
            if (r != null && out.size() < RlySettingsLog.MOST_PER_SAVE) {
                out.add(r);
            }
        }
        return out;
    }

    private static RLY_Settings_Change__c rowFor(RlySettingsLog.Item a, RlySettingsLog.Item b, Set<String> moved) {
        RlySettingsLog.Item any = b == null ? a : b;
        List<String> values = new List<String>{ a == null ? null : a.value, b == null ? null : b.value };
        if (any.marker) {
            return markerRow(any, values, a != null && b != null);
        }
        if (moved.contains(any.subject) || same(values[0], values[1])) {
            return null;
        }
        return row(any, any.what, any.secret ? masked(values) : values);
    }

    // An added or removed record is one row; a renamed one says both names.
    private static RLY_Settings_Change__c markerRow(RlySettingsLog.Item m, List<String> values, Boolean both) {
        if (both) {
            return same(values[0], values[1]) ? null : row(m, m.what + ' "' + values[0] + '" renamed', values);
        }
        return row(m, m.what + ' "' + m.value + '" ' + (values[0] == null ? 'added' : 'removed'), new List<String>{ null, null });
    }

    // A secret: never its value, only that it was set, changed or removed.
    private static List<String> masked(List<String> values) {
        String now = values[1] == null ? 'removed' : 'changed';
        return new List<String>{ null, values[0] == null && values[1] != null ? 'set' : now };
    }

    private static RLY_Settings_Change__c row(RlySettingsLog.Item i, String what, List<String> values) {
        return new RLY_Settings_Change__c(
            Section__c = i.section?.left(40),
            What__c = what.left(255),
            Old_Value__c = values[0]?.left(255),
            New_Value__c = values[1]?.left(255),
            Changed_By__c = UserInfo.getName().left(121)
        );
    }

    private static Boolean same(String x, String y) {
        return x == null ? y == null : x.equals(y);
    }

    private static RlySettingsLog.Item marker(Id recordId, String what, String name) {
        RlySettingsLog.Item m = new RlySettingsLog.Item();
        m.subject = String.valueOf(recordId);
        m.section = RlySettingsLog.SECTION_ORGS;
        m.what = what;
        m.marker = true;
        m.value = name;
        return m;
    }

    private static RlySettingsLog.Item order(String subject, String what, List<String> names) {
        RlySettingsLog.Item i = new RlySettingsLog.Item();
        i.subject = subject;
        i.section = subject == ROUTE ? RlySettingsLog.SECTION_CONNECTION : RlySettingsLog.SECTION_TRACKING;
        i.what = what;
        i.value = names.isEmpty() ? null : String.join(names, ARROW);
        return i;
    }
}
