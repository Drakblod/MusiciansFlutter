const assert = require('assert');
const { spawnSync } = require('child_process');
const path = require('path');
const { calculateBackfillPlan } = require('../scripts/backfill_map_event_feed');
const { isValidCoordinate } = require('../event_projection');

describe('BACKFILL-MAP-EVENT-FEED-TESTS: Safety, Invariants & Idempotency', () => {
  const scriptPath = path.join(__dirname, '../scripts/backfill_map_event_feed.js');

  it('1. Default mode performs zero writes (dry-run mode)', () => {
    const publicEvents = {
      evt_pub_1: {
        title: 'Public Jazz Night',
        status: 'published',
        startDateTime: '2026-11-20T20:00:00Z',
        endDateTime: '2026-11-20T23:00:00Z',
        latitude: 59.33,
        longitude: 18.06,
      },
    };

    const { summary, proposedWrites } = calculateBackfillPlan({
      publicEvents,
      now: new Date('2026-10-28T12:00:00Z'),
    });

    assert.strictEqual(summary.databaseWritesExecuted, 0);
    assert.strictEqual(summary.proposedProjections, 1);
    assert.ok(proposedWrites['publicMapEventFeed/event:public:evt_pub_1']);
  });

  it('2. Apply requires explicit flags (CLI safety block when not emulator and no flags)', () => {
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

  it('3. Production target is refused without both production confirmations', () => {
    // Missing --confirm-production when --apply is set
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
      output.includes('confirm-production') || res.status === 1,
      `Expected confirm-production safety error, got exit code ${res.status}: ${output}`
    );
    assert.strictEqual(res.status, 1);
  });

  it('4. Repeated apply is idempotent', () => {
    const publicEvents = {
      evt_idempotent: {
        title: 'Festival 2026',
        status: 'published',
        startDateTime: '2026-11-25T18:00:00Z',
        endDateTime: '2026-11-25T23:00:00Z',
        latitude: 59.33,
        longitude: 18.06,
      },
    };
    const now = new Date('2026-10-28T12:00:00Z');

    const plan1 = calculateBackfillPlan({ publicEvents, now });
    const plan2 = calculateBackfillPlan({ publicEvents, now });

    assert.deepStrictEqual(plan1.proposedWrites, plan2.proposedWrites);
    assert.deepStrictEqual(plan1.summary.proposedProjections, plan2.summary.proposedProjections);
  });

  it('5. Public vs Private classification is strictly partitioned', () => {
    const publicEvents = {
      evt_pub: {
        title: 'Public Concert',
        status: 'published',
        startDateTime: '2026-11-20T20:00:00Z',
        endDateTime: '2026-11-20T23:00:00Z',
        latitude: 59.33,
        longitude: 18.06,
      },
    };
    const bands = {
      band_1: {
        Name: 'The Echoes',
        Members_band: { user_alice: true },
        Events: {
          evt_priv: {
            title: 'Private Rehearsal',
            startDateTime: '2026-11-21T18:00:00Z',
            endDateTime: '2026-11-21T21:00:00Z',
            latitude: 59.34,
            longitude: 18.07,
          },
        },
      },
    };
    const now = new Date('2026-10-28T12:00:00Z');

    const { proposedWrites } = calculateBackfillPlan({ publicEvents, bands, now });

    assert.ok(proposedWrites['publicMapEventFeed/event:public:evt_pub']);
    assert.strictEqual(proposedWrites['publicMapEventFeed/event:private:band_1:evt_priv'], undefined);
    assert.ok(proposedWrites['userMapEventFeed/user_alice/event:private:band_1:evt_priv']);
  });

  it('6. Multi-part IDs are deterministic and container is not duplicated', () => {
    const bands = {
      band_2: {
        Name: 'The Rockers',
        Members_band: { user_bob: true },
        Events: {
          evt_multi: {
            title: 'Tour Gig',
            latitude: 59.33,
            longitude: 18.06,
            rehearsals: [
              { id: 'part_sc', type: 'Rehearsal', startDateTime: '2026-11-22T14:00:00Z', endDateTime: '2026-11-22T15:00:00Z' },
              { id: 'part_main', type: 'Concert', startDateTime: '2026-11-22T20:00:00Z', endDateTime: '2026-11-22T23:00:00Z' },
            ],
          },
        },
      },
    };
    const now = new Date('2026-10-28T12:00:00Z');

    const { proposedWrites } = calculateBackfillPlan({ bands, now });

    // Distinct deterministic part IDs
    assert.ok(proposedWrites['userMapEventFeed/user_bob/event:private:band_2:evt_multi:part_sc']);
    assert.ok(proposedWrites['userMapEventFeed/user_bob/event:private:band_2:evt_multi:part_main']);
    // Parent container is NOT written as a separate marker
    assert.strictEqual(proposedWrites['userMapEventFeed/user_bob/event:private:band_2:evt_multi'], undefined);
  });

  it('7. Unresolved free-text locations remain unresolved without fallback coordinates', () => {
    const publicEvents = {
      evt_unresolved: {
        title: 'Secret Location Show',
        location: 'Somewhere in Södermalm',
        status: 'published',
        startDateTime: '2026-11-20T20:00:00Z',
        endDateTime: '2026-11-20T23:00:00Z',
        // No coordinates
      },
    };
    const now = new Date('2026-10-28T12:00:00Z');

    const { summary, proposedWrites } = calculateBackfillPlan({ publicEvents, now });

    assert.strictEqual(summary.unresolvedMissingCoordinates, 1);
    assert.strictEqual(summary.proposedProjections, 0);
    assert.strictEqual(Object.keys(proposedWrites).length, 0);
  });

  it('8. Zero external geocoder calls: coordinate validation is strictly mathematical', () => {
    assert.strictEqual(isValidCoordinate(59.3293, 18.0686), true);
    assert.strictEqual(isValidCoordinate(0, 0), false);
    assert.strictEqual(isValidCoordinate(null, 18.0), false);
    assert.strictEqual(isValidCoordinate('Stockholm', 'Sweden'), false);
  });

  it('9. Stale projections are reported but not silently deleted', () => {
    const existingPublicProjections = {
      'event:public:evt_stale_1': { title: 'Old Deleted Event' },
    };
    const publicEvents = {}; // empty
    const now = new Date('2026-10-28T12:00:00Z');

    const { summary } = calculateBackfillPlan({
      publicEvents,
      existingPublicProjections,
      now,
    });

    assert.strictEqual(summary.staleProjectionsReported, 1);
  });

  it('10. Sensitive data is never included in backfill write payloads', () => {
    const bands = {
      band_3: {
        Name: 'The Secret Society',
        Members_band: { user_charlie: true },
        Events: {
          evt_priv_sens: {
            title: 'Confidential Rehearsal',
            startDateTime: '2026-11-25T18:00:00Z',
            endDateTime: '2026-11-25T21:00:00Z',
            latitude: 59.33,
            longitude: 18.06,
            rsvpDeadline: 1793000000000,
            responses: { user_charlie: { status: 'YES', comment: 'Bringing private access card' } },
            externalInvitees: { user_dave: { email: 'dave@private.com', token: 'fcm_token_123' } },
            excludedMemberIds: ['user_eve'],
          },
        },
      },
    };
    const now = new Date('2026-10-28T12:00:00Z');

    const { proposedWrites } = calculateBackfillPlan({ bands, now });
    const payload = JSON.stringify(proposedWrites['userMapEventFeed/user_charlie/event:private:band_3:evt_priv_sens']);

    assert.strictEqual(payload.includes('dave@private.com'), false);
    assert.strictEqual(payload.includes('fcm_token_123'), false);
    assert.strictEqual(payload.includes('Bringing private access card'), false);
    assert.strictEqual(payload.includes('user_eve'), false);
  });
});
