/**
 * @description Tests for comparing custom fields and value sets (build 60): RlyCompareFields, and the new types in
 * RlyCompareFiles and RlyCompareZip. Every test runs as an existing active System Administrator through System.runAs.
 */
@IsTest
private class RlyCompareFieldsTest {

    private static final String OBJECT_XML = '<?xml version="1.0" encoding="UTF-8"?>\n'
        + '<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n'
        + '    <fields>\n'
        + '        <fullName>Tier__c</fullName>\n'
        + '        <label>Tier</label>\n'
        + '        <type>Picklist</type>\n'
        + '    </fields>\n'
        + '    <fields>\n'
        + '        <fullName>Note__c</fullName>\n'
        + '        <label>Note</label>\n'
        + '    </fields>\n'
        + '</CustomObject>\n';

    @IsTest
    static void fieldsBecomeTheirOwnFiles() {
        System.runAs(RlyTestData.admin()) {
            System.assert(RlyCompareFields.isObjectFile('objects/Account.object'), 'An object file');
            System.assert(!RlyCompareFields.isObjectFile('objects/Account/fields/Tier__c.field-meta.xml'), 'Source format isn\'t');
            Map<String, RlyCompareFiles.FileDiff> fields = RlyCompareFields.fieldsOf('objects/Account.object', OBJECT_XML);
            System.assertEquals(new Set<String>{ 'CustomField:Account.Tier__c', 'CustomField:Account.Note__c' }, fields.keySet(), 'Both fields');
            RlyCompareFiles.FileDiff tier = fields.get('CustomField:Account.Tier__c');
            System.assertEquals('objects/Account/fields/Tier__c.field-meta.xml', tier.path, 'Its source-format path');
            System.assert(tier.right.startsWith('<?xml version="1.0" encoding="UTF-8"?>\n<CustomField'), tier.right);
            System.assert(tier.right.contains('\n    <fullName>Tier__c</fullName>\n') && tier.right.endsWith('</CustomField>\n'), tier.right);
            System.assertEquals(new List<String>{ 'objects/Account/fields/Tier__c.field-meta.xml' },
                RlyCompareFields.pathsOf('CustomField:Account.Tier__c'), 'A deleted field is read from its file');
            System.assertEquals('objects/Account/fields/Tier__c.field-meta.xml', RlyFileEditPaths.pathsFor('CustomField:Account.Tier__c')[0], 'Edited in its file');
            System.assert(RlyCompareFiles.isSupported('CustomField') && RlyCompareFiles.isSupported('GlobalValueSet'), 'Compared now');
            System.assertEquals('GlobalValueSet:Tiers', RlyCompareFiles.keyOf('globalValueSets/Tiers.globalValueSet'), 'A value set');
            System.assertEquals('standardValueSets/Industry.standardValueSet-meta.xml',
                RlyCompareFiles.sourcePathOf('standardValueSets/Industry.standardValueSet'), 'Gains -meta.xml');
        }
    }

    @IsTest
    static void zipReadsFields() {
        System.runAs(RlyTestData.admin()) {
            Compression.ZipWriter writer = new Compression.ZipWriter();
            writer.addEntry('package.xml', Blob.valueOf('<Package/>'));
            writer.addEntry('objects/Account.object', Blob.valueOf(OBJECT_XML));
            Map<String, List<RlyCompareFiles.FileDiff>> files = RlyCompareZip.read(EncodingUtil.base64Encode(writer.getArchive()), 'DEV1');
            System.assert(files.containsKey('customfield:account.note__c'), 'Each field is a component: ' + files.keySet());
            System.assertEquals('objects/Account/fields/Note__c.field-meta.xml', files.get('customfield:account.note__c')[0].path, 'Its file');
        }
    }
}
