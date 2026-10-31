/**
 * @description The releases a promotion carries (Carried_Releases__c: their Ids, comma separated, oldest deploy first)
 * and their merge commits, which are the components of the promotion's promote run.
 */
public with sharing class RlyCarried {

    /**
     * @description The Ids of the releases a promotion carries, in order.
     * @param rel the promotion, with Carried_Releases__c
     * @return the Ids (empty for other releases)
     */
    public static List<Id> ids(RLY_Release__c rel) {
        List<Id> out = new List<Id>();
        for (String s : String.isBlank(rel.Carried_Releases__c) ? new List<String>() : rel.Carried_Releases__c.split(',')) {
            if (String.isNotBlank(s)) {
                out.add(Id.valueOf(s.trim()));
            }
        }
        return out;
    }

    /**
     * @description The releases a promotion carries, in Carried_Releases__c order.
     * @param rel the promotion
     * @return the releases (empty for other releases)
     */
    public static List<RLY_Release__c> releases(RLY_Release__c rel) {
        List<Id> carriedIds = ids(rel);
        Map<Id, RLY_Release__c> byId = new Map<Id, RLY_Release__c>(RlyPromoteStore.byIds(new Set<Id>(carriedIds)));
        List<RLY_Release__c> out = new List<RLY_Release__c>();
        for (Id i : carriedIds) {
            if (byId.containsKey(i)) {
                out.add(byId.get(i));
            }
        }
        return out;
    }

    /**
     * @description The carried releases' merge commits, oldest deploy first.
     * @param rel the promotion
     * @return the SHAs, comma separated
     */
    public static String mergeCommits(RLY_Release__c rel) {
        List<String> shas = new List<String>();
        for (RLY_Release__c r : releases(rel)) {
            if (String.isNotBlank(r.Merge_Commit__c)) {
                shas.add(r.Merge_Commit__c.trim());
            }
        }
        return String.join(shas, ',');
    }

    /**
     * @description The carried releases' numbers.
     * @param rel the promotion
     * @return the names, in order
     */
    public static List<String> names(RLY_Release__c rel) {
        List<String> out = new List<String>();
        for (RLY_Release__c r : releases(rel)) {
            out.add(r.Name);
        }
        return out;
    }

    /**
     * @description The carried releases' components, each once, as new items for the promotion.
     * @param carried the carried releases
     * @return the items (not saved)
     */
    public static List<RLY_Release_Item__c> items(List<RLY_Release__c> carried) {
        Map<String, RLY_Release_Item__c> byKey = new Map<String, RLY_Release_Item__c>();
        for (RLY_Release_Item__c i : RlyPromoteStore.itemsOf(new Map<Id, RLY_Release__c>(carried).keySet())) {
            String key = i.Metadata_Type__c + ':' + i.Component_Name__c;
            if (!byKey.containsKey(key)) {
                byKey.put(key, new RLY_Release_Item__c(Metadata_Type__c = i.Metadata_Type__c, Component_Name__c = i.Component_Name__c,
                    Change_Type__c = i.Change_Type__c, Source__c = i.Source__c));
            }
        }
        return byKey.values();
    }
}
