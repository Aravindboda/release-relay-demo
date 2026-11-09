/**
 * @description Tests for LabelFormatter. Fixed in Release Relay (Edit a file, E14 setup): the expected text has the comma.
 */
@IsTest
private class LabelFormatterTest {
    @IsTest
    static void formatsLine() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals('ANA RUIZ, Plano TX', LabelFormatter.line(' Ana Ruiz ', 'Plano', 'tx'), 'Label line');
        }
    }
}