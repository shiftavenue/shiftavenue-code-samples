// Only updatable content as of 2024 is Slides and Sheets
const driveListQuery = "(mimeType='application/vnd.google-apps.presentation' or mimeType='application/vnd.google-apps.spreadsheet') and trashed=false"

// Entrypoint function
function updateLinkedContent() {
    // Start timer
    const timer = new Timer();
    timer.start();

    // Turns data execution on for BigQuery data sources that are used for some Google sheets
    SpreadsheetApp.enableBigQueryExecution()

    var content = getAllFilesToBeUpdated()

    // No update in Docs for any linked content
    for (var index in content) {
        // Abort execution to avoid timeout failure
        if (timer.getDuration() >= timer.threshold) {
            console.log(`Did not finish in time, updated ${index} files. Creating trigger for follow-up execution and saving current state...`);
            saveState(content.slice(index));
            return new Trigger("updateLinkedContent");
        } else {
            switch (content[index].mimeType) {
                case "application/vnd.google-apps.presentation":
                    try {
                        let presentation = SlidesApp.openById(content[index].id)
                        let slides = presentation.getSlides()
                        for (var slideIndex in slides) {
                            // Refresh linked slide
                            if (slides[slideIndex].getSlideLinkingMode() == SlidesApp.SlideLinkingMode.LINKED) {
                                slides[slideIndex].refreshSlide()
                            }

                            // Refresh linked sheets chart
                            let charts = slides[slideIndex].getSheetsCharts()

                            for (var chartIndex in charts) {
                                if (charts[chartIndex].getLink() != null) {
                                    charts[chartIndex].refresh()
                                }
                            }
                        }
                        console.log(`Presentation ${content[index].id} updated successfully`);
                    }
                    catch (err) {
                        console.log(`Presentation ${content[index].id} could not be updated: ${err.message}`);
                    }
                    break;
                case "application/vnd.google-apps.spreadsheet":
                    try {
                        let sheet = SpreadsheetApp.openById(content[index].id)
                        // Only content to be updated are data sources
                        sheet.refreshAllDataSources()
                        console.log(`Spreadsheet ${content[index].id} updated successfully`);
                    }
                    catch (err) {
                        console.log(`Spreadsheet ${content[index].id} could not be updated: ${err.message}`);
                    }
                    break;
                default:
                    console.log("Unexpected mime type.")
                    break;
            }
        }
    }

    // If the exeuction completed, cleanup state and triggers (if there are any)
    deleteState();
    Trigger.deleteTriggers();
}

function getAllFilesToBeUpdated() {
    // Two options:
    // 1. Fetch all files on new execution
    // 2. If there's a saved state file, use that one as source
    var result = new Array();
    var state = readState();

    if (state === null) {
        var pageToken, page;
        do {
            var optionalArgs = { corpora: "allDrives", includeItemsFromAllDrives: true, supportsAllDrives: true, q: driveListQuery, maxResults: 500, pageToken: pageToken }
            page = Drive.Files.list(optionalArgs)
            var allFiles = page.files

            for (var file in allFiles) {
                result.push(allFiles[file])
            }

            pageToken = page.nextPageToken;
        }
        while (pageToken);
    } else {
        for (var index in state) {
            result.push(state[index])
        }
    }

    console.log(`${result.length} files will be updated`)

    return result;
}