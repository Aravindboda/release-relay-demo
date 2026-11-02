/**
 * @description Tests for LabelFormatter. The expected text still has the old format (no comma), so this test fails
 * on purpose: it shows a release stopped at "Checks failed".
 */
@IsTest
private class LabelFormatterTest {
    @IsTest
    static void formatsLine() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals('ANA RUIZ Plano TX', LabelFormatter.line(' Ana Ruiz ', 'Plano', 'tx'), 'Label line');
        }
    }
}