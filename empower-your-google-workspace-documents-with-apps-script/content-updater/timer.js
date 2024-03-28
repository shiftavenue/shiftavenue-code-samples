/*
 * Helper class used for checking runtime
 */

class Timer {
    constructor() {
        // Apps Script timeout is 30 min
        // Set threshold to 20 min
        // Cleanup (creating/deleting trigger and creating/deleting state file) takes a lot of time (~5 min)
        // Threshold is set in milliseconds
        this.threshold = 20 * 60 * 1000;
    }

    start() {
        this.start = Date.now();
    }

    getDuration() {
        return Date.now() - this.start;
    }
}