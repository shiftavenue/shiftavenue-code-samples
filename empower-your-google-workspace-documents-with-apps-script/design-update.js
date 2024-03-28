/*
 * Apps Script for updating Google Slide designs with a central master slide deck design
 * Iterates through all Google Slides presentations and updates those that have the "Auto Design Update" label set to "True"
 */

// Master Slide Deck presentation ID
// TODO: change according to your master presentation
const masterSlideDeckID = "masterSlideDeckID"

// ID of "Auto Design Update" label
// TODO: change according to your label
const autoDesignUpdateLabelID = "ABC1234DEF"
// ID of label text field
// TODO: change according to your label
const autoDesignUpdateLabelTextFieldID = "FED4321CBA"
// ID of label text field value representing 'True'
// TODO: change according to your label
const autoDesignUpdateLabelTextFieldValueID = "CAB3421FDE"

// Drive API search query to get all Google Slides presentations
const driveListQuery = `mimeType='application/vnd.google-apps.presentation' 
    and trashed=false 
    and labels/${autoDesignUpdateLabelID}.${autoDesignUpdateLabelTextFieldID}='${autoDesignUpdateLabelTextFieldValueID}'`

// Entrypoint function
function runDesignUpdate() {
  var allSlides = getAllSlidesToBeUpdated();

  var masterPres = SlidesApp.openById(masterSlideDeckID);
  // Use first slide to be able to copy latest design to all presentations
  var masterTemplateSlide = masterPres.getSlides()[0]

  for (let i = 0; i < allSlides.length; i++) {
    try {
      let s = SlidesApp.openById(allSlides[i].id);

      // Append master presentation slide, we now have two designs
      s.appendSlide(masterTemplateSlide);
      // Remove old design, applies the latest master design on all slides
      s.getMasters()[0].remove();
      // Remove appended slide
      s.getSlides()[(s.getSlides().length)-1].remove();
  
      console.log(`Presentation ${allSlides[i].id} updated successfully`);
    }
    catch(err) {
      console.log(`Presentation ${allSlides[i].id} could not be updated: ${err.message}`);
    }
  }
}

function getAllSlidesToBeUpdated() {
  var result = new Array();
  var pageToken, page;
  do {
    var optionalArgs = {
        // Use constructed search query
        q: driveListQuery,
        corpora: "allDrives",
        includeItemsFromAllDrives: true,
        supportsAllDrives: true,
        maxResults: 500,
        pageToken: pageToken };
    
    // Requires the advanced Drive service: https://developers.google.com/apps-script/advanced/drive
    page = Drive.Files.list(optionalArgs);
    var allFiles = page.files;

    for (var file in allFiles) {
      result.push(allFiles[file]);
    }

    pageToken = page.nextPageToken;
  }
  while (pageToken);

  return result;
}
