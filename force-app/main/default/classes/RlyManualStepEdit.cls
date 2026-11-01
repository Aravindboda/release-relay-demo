/**
 * @description Adds, changes and deletes a release's manual steps from its page (RlyManualStepController), under the
 * rules of RlyManualStepRules: who raised the release, or an admin, until it is first deployed; up to 50 steps. The
 * release's runs in its current target follow (RlyManualStepRuns.refresh). Reordering is two saves that swap sequences,
 * so two steps may share a sequence for a moment.
 */
public with sharing class RlyManualStepEdit {

    private static final Set<String> OPTIONAL_KEYS = new Set<String>{ 'id', 'releaseId', 'sequence', 'backPromote' };

    /**
     * @description Reads the JSON the page sends; blank optional values (a new step's id) count as missing.
     * @param stepJson {id (blank for a new step), releaseId, title, instructions, category, timing, sequence, backPromote, orgScope}
     * @return the step input
     */
    public static RlyManualSteps.StepInput parse(String stepJson) {
        Map<String, Object> sent;
        try {
            sent = (Map<String, Object>) JSON.deserializeUntyped(stepJson);
        } catch (Exception e) {
            throw new RlyReleaseException('The manual step couldn\'t be read.');
        }
        for (String k : OPTIONAL_KEYS) {
            if (sent.containsKey(k) && (sent.get(k) == null || String.isBlank(String.valueOf(sent.get(k))))) {
                sent.remove(k);
            }
        }
        return (RlyManualSteps.StepInput) JSON.deserialize(JSON.serialize(sent), RlyManualSteps.StepInput.class);
    }

    /**
     * @description Adds or changes a step and refreshes the release's runs in its current target.
     * @param input the step
     * @return the release the step belongs to
     */
    public static Id save(RlyManualSteps.StepInput input) {
        RLY_Manual_Step__c existing = input == null || input.id == null ? null : stepOf(input.id);
        RLY_Release__c rel = RlyReleaseStore.release(existing != null ? existing.Release__c : input?.releaseId);
        if (rel == null) {
            throw new RlyReleaseException('Release not found.');
        }
        RlyManualStepRules.requireEdit(rel);
        RLY_Manual_Step__c step = RlyManualStepRules.toStep(input, RlyManualStepRules.knownOrgNames());
        if (existing != null) {
            step.Id = existing.Id;
            step.Sequence__c = step.Sequence__c == null ? existing.Sequence__c : step.Sequence__c;
        } else {
            step.Release__c = rel.Id;
            step.Sequence__c = sequenceFor(rel.Id, step.Sequence__c);
        }
        RlyManualStepStore.saveSteps(new List<RLY_Manual_Step__c>{ step });
        RlyManualStepRuns.refresh(rel);
        return rel.Id;
    }

    /**
     * @description Deletes a step (and its runs) and renumbers the release's runs in its current target. The last step of
     * a release with only manual steps can't be deleted.
     * @param stepId the step
     * @return the release the step belonged to
     */
    public static Id remove(Id stepId) {
        RLY_Manual_Step__c step = stepOf(stepId);
        RLY_Release__c rel = RlyReleaseStore.release(step.Release__c);
        RlyManualStepRules.requireEdit(rel);
        if (RlyManualOnly.isManualOnly(rel) && RlyManualStepStore.stepsOf(new Set<Id>{ rel.Id }).size() <= 1) {
            throw new RlyReleaseException('A release with only manual steps needs at least one. Change this step instead.');
        }
        RlyManualStepStore.deleteStep(step.Id);
        RlyManualStepRuns.refresh(rel);
        return rel.Id;
    }

    private static RLY_Manual_Step__c stepOf(Id stepId) {
        List<RLY_Manual_Step__c> rows = stepId == null ? new List<RLY_Manual_Step__c>()
            : RlyManualStepStore.stepsById(new Set<Id>{ stepId });
        if (rows.isEmpty()) {
            throw new RlyReleaseException('This manual step isn\'t there any more. Reload the page.');
        }
        return rows[0];
    }

    // The sequence of a step added to a release (the next after its last one when none is given); refuses a 51st step.
    private static Decimal sequenceFor(Id releaseId, Decimal given) {
        List<RLY_Manual_Step__c> steps = RlyManualStepStore.stepsOf(new Set<Id>{ releaseId });
        if (steps.size() >= RlyManualSteps.MAX_STEPS) {
            throw new RlyReleaseException('A release can have up to ' + RlyManualSteps.MAX_STEPS + ' manual steps.');
        }
        if (given != null) {
            return given;
        }
        Decimal highest = 0;
        for (RLY_Manual_Step__c s : steps) {
            highest = s.Sequence__c != null && s.Sequence__c > highest ? s.Sequence__c : highest;
        }
        return highest >= 9999 ? 9999 : highest + 1;
    }
}
