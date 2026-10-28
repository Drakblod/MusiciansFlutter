const assert = require('assert');
const { spawnSync } = require('child_process');
const path = require('path');
const { calculateMapPinBackfillPlan } = require('../scripts/backfill_public_map_pin_feed');
const { sanitizeMapPinProjection } = require('../index');

describe('BACKFILL-PUBLIC-MAP-PIN-FEED-TESTS: Safety, Invariants & Idempotency', function () {
  this.timeout(15000);
  const scriptPath = path.join(__dirname, '../scripts/backfill_public_map_pin_feed.js');

  it('1. Default mode performs zero writes (dry-run mode)', () => {
    const subRequests = {
      pin_promo_1: {
        SubRequestId: 'pin_promo_1',
        CreatorUserId: 'creator_1',
        NotificationMode: 'map_pin',
        Status: 'published',
        Title: 'Album Launch Party',
        Latitude: 59.33,
        Longitude: 18.06,
      },
    };

    const { summary, proposedWrites } = calculateMapPinBackfillPlan({
      subRequests,
      existingProjections: {},
    });

    assert.strictEqual(summary.databaseWritesExecuted, 0);
    assert.strictEqual(summary.proposedCreations, 1);
    assert.ok(proposedWrites['publicMapPinFeed/pin_promo_1']);
  });

  it('2. Production target is refused without both production flags', () => {
    const res = spawnSync('node', [
      scriptPath,
      '--project=musicians-prod',
      '--database-url=https://musicians-prod.europe-west1.firebasedatabase.app',
    ], {
      encoding: 'utf8',
      env: {
        ...process.env,
        FIREBASE_DATABASE_EMULATOR_HOST: '',
        GCLOUD_PROJECT: 'musicians-prod',
      },
    });

    const output = (res.stdout || '') + (res.stderr || '');
    assert(
      output.includes('FATAL SAFETY BLOCK') || res.status === 1,
      `Expected fatal safety block, got exit code ${res.status}: ${output}`
    );
    assert.strictEqual(res.status, 1);
  });

  it('3. Production apply is refused without confirm-production flag', () => {
    const res = spawnSync('node', [
      scriptPath,
      '--apply',
      '--allow-production',
      '--project=musicians-prod',
      '--database-url=https://musicians-prod.europe-west1.firebasedatabase.app',
    ], {
      encoding: 'utf8',
      env: {
        ...process.env,
        FIREBASE_DATABASE_EMULATOR_HOST: '',
        GCLOUD_PROJECT: 'musicians-prod',
      },
    });

    const output = (res.stdout || '') + (res.stderr || '');
    assert(
      output.includes('FATAL SAFETY BLOCK') || res.status === 1,
      `Expected safety error, got exit code ${res.status}: ${output}`
    );
    assert.strictEqual(res.status, 1);
  });

  it('4. Repeated calculation is idempotent', () => {
    const subRequests = {
      pin_promo_idemp: {
        SubRequestId: 'pin_promo_idemp',
        CreatorUserId: 'creator_1',
        NotificationMode: 'map_pin',
        Status: 'published',
        Title: 'Single Release Showcase',
        Latitude: 59.34,
        Longitude: 18.07,
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      },
    };

    const plan1 = calculateMapPinBackfillPlan({ subRequests, existingProjections: {} });
    const plan2 = calculateMapPinBackfillPlan({ subRequests, existingProjections: {} });

    assert.deepStrictEqual(plan1.proposedWrites, plan2.proposedWrites);
    assert.strictEqual(plan1.summary.proposedCreations, plan2.summary.proposedCreations);
  });

  it('5. Staffing records are strictly ignored and never enter publicMapPinFeed', () => {
    const subRequests = {
      staffing_req_1: {
        SubRequestId: 'staffing_req_1',
        CreatorUserId: 'creator_alice',
        VoicePart: 'Guitarist',
        Status: 'published',
        NotificationMode: 'all',
        Latitude: 59.33,
        Longitude: 18.06,
      },
      staffing_req_direct: {
        SubRequestId: 'staffing_req_direct',
        CreatorUserId: 'creator_alice',
        VoicePart: 'Drummer',
        Status: 'published',
        NotificationMode: 'direct',
        TargetUserIds: ['target_bob'],
        Latitude: 59.33,
        Longitude: 18.06,
      },
    };

    const { summary, proposedWrites } = calculateMapPinBackfillPlan({
      subRequests,
      existingProjections: {},
    });

    assert.strictEqual(summary.staffingSkipped, 2);
    assert.strictEqual(summary.proposedCreations, 0);
    assert.strictEqual(Object.keys(proposedWrites).length, 0);
  });

  it('6. Sanitization enforces allowlist and strips private target data, responses, assignment and tokens', () => {
    const rawPin = {
      id: 'pin_promo_dirty',
      SubRequestId: 'pin_promo_dirty',
      CreatorUserId: 'creator_123',
      NotificationMode: 'map_pin',
      Status: 'published',
      Title: 'Concert Promo',
      BandName: 'The Rockers',
      Latitude: 59.33,
      Longitude: 18.06,
      TargetUserIds: ['user_secret_1', 'user_secret_2'],
      Responses: { user_secret_1: true },
      AssignedUserId: 'user_secret_1',
      AssignedUserName: 'Secret User',
      DeviceTokens: ['fcm_token_123'],
      email: 'creator@example.com',
      phoneNumber: '+1234567890',
    };

    const sanitized = sanitizeMapPinProjection(rawPin);

    assert.strictEqual(sanitized.id, 'pin_promo_dirty');
    assert.strictEqual(sanitized.title, 'Concert Promo');
    assert.strictEqual(sanitized.bandName, 'The Rockers');
    assert.strictEqual(sanitized.creatorUserId, 'creator_123');
    assert.strictEqual(sanitized.NotificationMode, 'map_pin');
    assert.strictEqual(sanitized.latitude, 59.33);
    assert.strictEqual(sanitized.longitude, 18.06);

    // Stripped fields
    assert.strictEqual(sanitized.TargetUserIds, undefined);
    assert.strictEqual(sanitized.targetUserIds, undefined);
    assert.strictEqual(sanitized.Responses, undefined);
    assert.strictEqual(sanitized.responses, undefined);
    assert.strictEqual(sanitized.AssignedUserId, undefined);
    assert.strictEqual(sanitized.assignedUserId, undefined);
    assert.strictEqual(sanitized.AssignedUserName, undefined);
    assert.strictEqual(sanitized.DeviceTokens, undefined);
    assert.strictEqual(sanitized.email, undefined);
    assert.strictEqual(sanitized.phoneNumber, undefined);
  });

  it('7. Stale projections are scheduled for removal when canonical pin is deleted or cancelled', () => {
    const existingProjections = {
      pin_stale_1: {
        id: 'pin_stale_1',
        title: 'Old Pin',
      },
    };
    const subRequests = {
      pin_cancelled: {
        SubRequestId: 'pin_cancelled',
        NotificationMode: 'map_pin',
        Status: 'cancelled',
        Latitude: 59.33,
        Longitude: 18.06,
      },
    };

    const { summary, proposedWrites } = calculateMapPinBackfillPlan({
      subRequests,
      existingProjections,
    });

    assert.strictEqual(summary.proposedDeletions, 1);
    assert.strictEqual(proposedWrites['publicMapPinFeed/pin_stale_1'], null);
  });
});
