// Only updatable content as of 2024 is Slides and Sheets
const driveListQuery = "(mimeType='application/vnd.google-apps.presentation' or mimeType='application/vnd.google-apps.spreadsheet') and trashed=false"

// Entrypoint function
function updateLinkedContent() {

    // Turns data execution on for BigQuery data sources that are used for some Google sheets
    SpreadsheetApp.enableBigQueryExecution()

    var content = getAllFilesToBeUpdated()

    // No update in Docs for any linked content
    for (var index in content) {
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

function getAllFilesToBeUpdated() {
    var result = new Array();

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

    console.log(`${result.length} files will be updated`)

    return result;
}