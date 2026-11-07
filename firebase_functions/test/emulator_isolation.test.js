'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const places = require('../google_places_cities');
const {fakeKey} = require('./emulator_isolation_guard');

describe('EMULATOR-ISOLATION-GATE-01 fail-closed bootstrap', function() {
  it('has no ambient ADC, live project, or external network attempt', function() {
    assert.equal(globalThis.__EMULATOR_ISOLATION_GUARD_ACTIVE__,true);
    assert.equal(process.env.GOOGLE_APPLICATION_CREDENTIALS,undefined);
    assert.equal(process.env.GCLOUD_PROJECT,'demo-musicians-test');
    assert.equal(process.env.GOOGLE_CLOUD_PROJECT,'demo-musicians-test');
    assert.equal(process.env.FIREBASE_DATABASE_EMULATOR_HOST,'127.0.0.1:9000');
    assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9099');
    assert.equal(process.env.FUNCTIONS_EMULATOR_HOST,'127.0.0.1:5001');
    assert.equal(process.env.LIVEKIT_API_KEY,'EMULATOR_ONLY_FAKE_LIVEKIT_KEY');
    assert.equal(process.env.LIVEKIT_API_SECRET,'EMULATOR_ONLY_FAKE_LIVEKIT_SECRET');
    assert.equal(process.env.LIVEKIT_URL,'ws://127.0.0.1:65535');
    assert(process.env.APPDATA.startsWith(process.env.EMULATOR_ISOLATION_TEMP));
    assert(!fs.existsSync(path.join(process.env.APPDATA,'gcloud',
      'application_default_credentials.json')));
    assert(!fs.existsSync(process.env.EMULATOR_ISOLATION_ATTEMPTS));
  });

  it('uses only a local fake Places secret and deterministic provider responses', async function() {
    const token='12345678-1234-4234-8234-123456789abc';
    const results=await places.search('Berlin',token,fakeKey);
    assert.deepEqual(results,[{placeId:'PlaceBerlin123',city:'Berlin',country:'Germany'}]);
    const resolved=await places.resolve('PlaceBerlin123',token,fakeKey);
    assert.equal(resolved.city,'Berlin');
    assert.equal(resolved.country,'Germany');
    assert(!fs.existsSync(process.env.EMULATOR_ISOLATION_ATTEMPTS));
  });

  it('retains the deterministic emulator FCM stub', async function() {
    // Load the entry point that installs the stub, even in a focused run.
    require('../index');
    const result=await admin.messaging().sendEach([{token:'emulator-fake-token',
      notification:{title:'local'}}]);
    assert.equal(result.successCount,1);
    assert.equal(result.responses[0].messageId,'mock-fcm-id');
    assert(!fs.existsSync(process.env.EMULATOR_ISOLATION_ATTEMPTS));
  });
});
