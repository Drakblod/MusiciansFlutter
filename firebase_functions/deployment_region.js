'use strict';

// The RTDB emulator registers triggers in us-central1. No flag can change the
// region for a real project: only an explicit disposable demo project and hub
// use this emulator compatibility path.
function databaseRegion(env = process.env) {
  const project = env.GCLOUD_PROJECT || env.GOOGLE_CLOUD_PROJECT || '';
  return project.startsWith('demo-') && env.FUNCTIONS_EMULATOR === 'true' &&
    Boolean(env.FIREBASE_EMULATOR_HUB) ? 'us-central1' : 'europe-west1';
}
module.exports = {databaseRegion};
