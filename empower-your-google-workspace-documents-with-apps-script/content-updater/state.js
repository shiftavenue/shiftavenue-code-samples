/*
 * Helper functions to work with current progress of script saved as a file 
 * Necessary to avoid script timeouts and to tell the script where to continue
 */

const stateFileName = "link-updater-state.json"

function saveState(remainingFiles) {
    const files = DriveApp.getFilesByName(stateFileName);
    let file;
    if (files.hasNext()) {
        file = files.next();
    }
    else {
        file = DriveApp.createFile(stateFileName, '');
    }
    // Set file content to current progress
    file.setContent(JSON.stringify(remainingFiles));
};

function readState() {
    const files = DriveApp.getFilesByName(stateFileName);
    if (files.hasNext()) {
        return JSON.parse(files.next().getBlob().getDataAsString());
    }
    return null;
};

function deleteState() {
    const files = DriveApp.getFilesByName(stateFileName);
    if (files.hasNext()) {
        files.next().setTrashed(true);
    }
};