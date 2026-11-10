/**
 * @description The SOAP Metadata API of a registered org, called with the hub's own sign-in (RlyOrgSession):
 * builds the envelope, sends it and reads the result or the fault. Also the small XML helpers the
 * Metadata classes share.
 */
public with sharing class RlySoapClient {

    /** @description The Metadata API namespace. */
    public static final String MET = 'http://soap.sforce.com/2006/04/metadata';
    /** @description The SOAP envelope namespace. */
    public static final String ENV = 'http://schemas.xmlsoap.org/soap/envelope/';

    /**
     * @description Posts a SOAP body (the operation element) to the org's Metadata API.
     * @param org the registered org
     * @param bodyXml the operation element, for example met:checkRetrieveStatus
     * @return the org's response
     */
    public static HttpResponse post(RLY_Org__c org, String bodyXml) {
        String envelope = '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="' + ENV + '" xmlns:met="' + MET + '">'
            + '<soapenv:Header><met:SessionHeader><met:sessionId>' + esc(RlyOrgSession.accessToken(org))
            + '</met:sessionId></met:SessionHeader></soapenv:Header>'
            + '<soapenv:Body>' + bodyXml + '</soapenv:Body></soapenv:Envelope>';
        return RlyOrgSession.send(org, new RlyOrgSession.Call('POST', '/services/Soap/m/' + RlyOrgSession.API_VERSION)
            .withBody(envelope)
            .withHeader('Content-Type', 'text/xml; charset=UTF-8')
            .withHeader('SOAPAction', '""'));
    }

    /**
     * @description Sends one call and returns its first result element (or, when there are none, a stand-in
     * whose parent is an empty response).
     * @param org the registered org
     * @param operation the operation, for example listMetadata
     * @param payload the operation's child elements
     * @return the first result element
     */
    public static Dom.XmlNode call(RLY_Org__c org, String operation, String payload) {
        HttpResponse res = post(org, '<met:' + operation + '>' + payload + '</met:' + operation + '>');
        Dom.Document doc = new Dom.Document();
        try {
            doc.load(res.getBody());
        } catch (Exception e) {
            throw new RlyMetadata.MetadataException(org.Name + ' answered HTTP ' + res.getStatusCode() + ' to ' + operation + ': '
                + String.valueOf(res.getBody()).left(300));
        }
        Dom.XmlNode body = doc.getRootElement().getChildElement('Body', ENV);
        Dom.XmlNode fault = body.getChildElement('Fault', ENV);
        if (fault != null) {
            throw new RlyMetadata.MetadataException(org.Name + ': ' + operation + ' failed: ' + faultReason(fault));
        }
        Dom.XmlNode response = body.getChildElement(operation + 'Response', MET);
        Dom.XmlNode firstResult = response == null ? null : response.getChildElement('result', MET);
        return firstResult == null ? emptyResult() : firstResult;
    }

    private static String faultReason(Dom.XmlNode fault) {
        String reason = 'no reason given';
        for (Dom.XmlNode f : fault.getChildElements()) {
            if (f.getName() == 'faultstring') {
                reason = f.getText();
            }
        }
        return reason;
    }

    // listMetadata with no matches returns an empty response: a stand-in result whose parent is the response.
    private static Dom.XmlNode emptyResult() {
        Dom.Document empty = new Dom.Document();
        Dom.XmlNode root = empty.createRootElement('response', MET, null);
        return root.addChildElement('result', MET, null);
    }

    /**
     * @description The text of a child element in the Metadata namespace.
     * @param node the parent element
     * @param name the child's name
     * @return its text, or null when it isn't there
     */
    public static String text(Dom.XmlNode node, String name) {
        Dom.XmlNode child = node.getChildElement(name, MET);
        return child == null ? null : child.getText();
    }

    /**
     * @description The text between the first startTag and the next endTag.
     * @param s the text to search
     * @param startTag where it starts
     * @param endTag where it ends
     * @return the text between, or null
     */
    public static String between(String s, String startTag, String endTag) {
        if (s == null) {
            return null;
        }
        Integer i = s.indexOf(startTag);
        if (i < 0) {
            return null;
        }
        Integer j = s.indexOf(endTag, i + startTag.length());
        return j < 0 ? null : s.substring(i + startTag.length(), j);
    }

    /**
     * @description Escapes a value for XML.
     * @param value the value
     * @return the escaped value ('' for null)
     */
    public static String esc(String value) {
        return value == null ? '' : value.escapeXml();
    }
}
