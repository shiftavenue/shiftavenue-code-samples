/*
 * Helper class that creates Apps Script triggers to follow-up on execution
 */

class Trigger {
    constructor(functionName) {
        return ScriptApp.newTrigger(functionName)
            .timeBased()
            // Run once one minute after trigger was created
            .at(new Date(Date.now() + 1 * 60 * 1000))
            .create();
    }

    static deleteTriggers() {
        ScriptApp.getProjectTriggers().forEach(trigger => {
            console.log('deleting trigger', trigger.getUniqueId());
            return ScriptApp.deleteTrigger(trigger);
        });
    }
}