/**
 * @description Tests for E2EProbe.
 */
@IsTest
private class E2EProbeTest {
    @IsTest
    static void returnsTheLabel() {
        User u = new User(Id = UserInfo.getUserId());
        System.runAs(u) {
            System.assertEquals('E2E probe v1', E2EProbe.label(), 'The probe returns its version label');
        }
    }
}
