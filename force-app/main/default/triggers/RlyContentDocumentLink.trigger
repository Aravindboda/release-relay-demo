trigger RlyContentDocumentLink on ContentDocumentLink (before insert, after insert, before delete) {
    RlyStepFileGuard.onLinks(Trigger.operationType, Trigger.new, Trigger.old);
}
