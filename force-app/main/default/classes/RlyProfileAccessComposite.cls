/**
 * @description Sends the queries of a profile access read (RlyProfileAccessQueries) as composite requests of up to
 * 25 and reads each answer into the read (RlyProfileAccessRead): values, Ids found, sections done, or a note for a
 * query the org refused. A long answer is followed for up to 5 more pages.
 */
public with sharing class RlyProfileAccessComposite {

    private static final Integer PER_COMPOSITE = 25;
    private static final Integer MORE_PAGES = 5;
    private static final String RECORDS = 'records';

    /**
     * @description Sends the queries and reads the answers.
     * @param rd the read
     * @param subs the queries
     */
    public static void runAll(RlyProfileAccessRead rd, List<RlyProfileAccessQueries.Sub> subs) {
        for (Integer i = 0; i < subs.size(); i += PER_COMPOSITE) {
            List<RlyProfileAccessQueries.Sub> slice = new List<RlyProfileAccessQueries.Sub>();
            List<Object> requests = new List<Object>();
            for (Integer j = i; j < Math.min(i + PER_COMPOSITE, subs.size()); j++) {
                slice.add(subs[j]);
                requests.add(new Map<String, Object>{ 'method' => 'GET', 'url' => subs[j].url, 'referenceId' => 'q' + (j - i) });
            }
            List<Object> answers = send(rd, requests);
            for (Integer j = 0; answers != null && j < slice.size() && j < answers.size(); j++) {
                readAnswer(rd, slice[j], (Map<String, Object>) answers[j]);
            }
        }
    }

    // One composite request; null (with a note) when the org refused it.
    private static List<Object> send(RlyProfileAccessRead rd, List<Object> requests) {
        HttpResponse res = RlyOrgSession.send(rd.org, new RlyOrgSession.Call('POST', '/services/data/v' + RlyOrgSession.API_VERSION + '/composite')
            .withBody(JSON.serialize(new Map<String, Object>{ 'allOrNone' => false, 'compositeRequest' => requests }))
            .withHeader('Content-Type', 'application/json').withHeader('Accept', 'application/json'));
        readUsage(rd.out, res.getHeader('Sforce-Limit-Info'));
        if (res.getStatusCode() != 200) {
            rd.out.notes.add('Couldn\'t read profile access in ' + rd.org.Name + ': HTTP ' + res.getStatusCode() + ' '
                + String.valueOf(res.getBody()).left(200));
            return null;
        }
        return (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('compositeResponse');
    }

    /**
     * @description Reads the org's API usage from an answer's Sforce-Limit-Info header (api-usage=used/max).
     * @param out the values being read
     * @param header the header, or null
     */
    public static void readUsage(RlyProfileAccessReader.Values out, String header) {
        Matcher m = Pattern.compile('api-usage=(\\d+)/(\\d+)').matcher(header == null ? '' : header);
        if (m.find()) {
            out.apiUsed = Integer.valueOf(m.group(1));
            out.apiMax = Integer.valueOf(m.group(2));
        }
    }

    private static void readAnswer(RlyProfileAccessRead rd, RlyProfileAccessQueries.Sub s, Map<String, Object> answer) {
        if (String.valueOf(answer.get('httpStatusCode')) != '200') {
            rd.out.notes.add('Couldn\'t read ' + RlyProfileAccessRules.sectionLabel(labelSection(s)) + ' in ' + rd.org.Name + ': '
                + JSON.serialize(answer.get('body')).left(200));
            return;
        }
        Map<String, Object> body = (Map<String, Object>) answer.get('body');
        readRows(rd, s, (List<Object>) body.get(RECORDS));
        Integer pages = 0;
        while (body.get('nextRecordsUrl') != null && pages < MORE_PAGES) {
            body = (Map<String, Object>) RlyOrgSession.getJson(rd.org, String.valueOf(body.get('nextRecordsUrl')));
            readRows(rd, s, (List<Object>) body.get(RECORDS));
            pages++;
        }
        markDone(rd, s.kind);
    }

    // A section is done when its values are read; the ones read through SetupEntityAccess when that query answered.
    private static void markDone(RlyProfileAccessRead rd, String kind) {
        if (kind == RlyProfileAccessQueries.KIND_ACCESS) {
            rd.done.addAll(RlyProfileAccessRows.ID_SECTIONS);
        } else if (kind != RlyProfileAccessQueries.KIND_ENTITY && !RlyProfileAccessRows.ID_KINDS.contains(kind)) {
            rd.done.add(kind);
        }
    }

    private static String labelSection(RlyProfileAccessQueries.Sub s) {
        if (s.kind == RlyProfileAccessQueries.KIND_ENTITY) {
            return RlyProfileAccessRules.SETTINGS;
        }
        return s.kind == RlyProfileAccessQueries.KIND_ACCESS ? RlyProfileAccessRules.CLASSES : s.kind;
    }

    private static void readRows(RlyProfileAccessRead rd, RlyProfileAccessQueries.Sub s, List<Object> records) {
        for (Object o : records == null ? new List<Object>() : records) {
            Map<String, Object> r = (Map<String, Object>) o;
            if (s.kind == RlyProfileAccessQueries.KIND_ACCESS) {
                rd.readAccess(r);
            } else if (s.kind == RlyProfileAccessQueries.KIND_ENTITY) {
                for (String rowKey : rd.rowsByEntity.get(String.valueOf(r.get('QualifiedApiName')).toLowerCase())) {
                    rd.addId(String.valueOf(r.get('DurableId')), rowKey);
                }
            } else if (RlyProfileAccessRows.ID_KINDS.contains(s.kind)) {
                rd.addId(RlyProfileAccessRows.idOf(s.kind, r), s.kind + '|' + RlyProfileAccessRows.nameOf(s.kind, r));
            } else {
                RlyProfileAccessRows.put(rd, s, r);
            }
        }
    }
}
