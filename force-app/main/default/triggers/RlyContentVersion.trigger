trigger RlyContentVersion on ContentVersion (before insert) {
    RlyStepFileGuard.onVersions(Trigger.new);
}
