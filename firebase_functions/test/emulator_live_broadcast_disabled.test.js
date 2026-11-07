'use strict';

const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInAnonymously } = require('firebase/auth');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');
const { createAuthoritativeLiveKitToken } = require('../live_broadcasts');

describe('Disabled Live broadcasts', function () {
  this.timeout(60000);
  let app;
  let functions;

  before(async function () {
    assert.equal(globalThis.__EMULATOR_ISOLATION_GUARD_ACTIVE__, true);
    assert.equal(process.env.GCLOUD_PROJECT, 'demo-musicians-test');
    assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9099');
    assert.equal(process.env.FUNCTIONS_EMULATOR_HOST, '127.0.0.1:5001');
    app = initializeApp({ projectId: 'demo-musicians-test', apiKey: 'emulator-only' }, 'disabled-live');
    const auth = getAuth(app);
    connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
    await signInAnonymously(auth);
    functions = getFunctions(app, 'europe-west1');
    connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  });

  after(async function () {
    if (app) await deleteApp(app);
  });

  for (const name of ['startLiveBroadcast', 'joinLiveBroadcast', 'leaveLiveBroadcast', 'stopLiveBroadcast']) {
    it(`rejects ${name} before checking the request or accessing the broadcast`, async function () {
      await assert.rejects(httpsCallable(functions, name)({}), (error) =>
        error.code === 'functions/failed-precondition' &&
        error.message === 'Live broadcasts are currently unavailable.');
    });
  }

  for (const variable of ['LIVEKIT_API_KEY', 'LIVEKIT_API_SECRET', 'LIVEKIT_URL']) {
    it(`does not fall back when ${variable} is missing`, function () {
      const previous = process.env[variable];
      delete process.env[variable];
      try {
        assert.throws(() => createAuthoritativeLiveKitToken({
          identity: 'emulator-user', roomName: 'emulator-room', role: 'publisher',
        }), { code: 'failed-precondition' });
      } finally {
        if (previous !== undefined) process.env[variable] = previous;
      }
    });
  }
});
