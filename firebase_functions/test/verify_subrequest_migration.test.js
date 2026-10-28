/**
 * Automated Test Suite for verify_subrequest_migration.js
 *
 * Runs against the Firebase RTDB Emulator and tests all 8 verification conditions:
 * 1. Valid complete migration -> exit success
 * 2. Private request in public feed -> failure
 * 3. Missing creator feed -> failure
 * 4. Missing public feed -> failure
 * 5. Map pin in staffing feed -> failure
 * 6. Orphan feed entry -> failure
 * 7. Sensitive field in sanitized feed -> failure
 * 8. Incorrect private recipient -> failure
 */

const assert = require('assert');
const admin = require('firebase-admin');

if (!process.env.FIREBASE_DATABASE_URL) {
  process.env.FIREBASE_DATABASE_URL = 'http://127.0.0.1:9000?ns=demo-musicians-test';
}

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: 'demo-musicians-test',
      databaseURL: process.env.FIREBASE_DATABASE_URL,
    });
  }
  return admin.database();
}

const { runBackfill } = require('../scripts/migrate_subrequests');
const { verifyMigration } = require('../scripts/verify_subrequest_migration');

describe('VERIFIER-AUDIT: Automated Migration Verifier Tests', function () {
  this.timeout(10000);
  let db;

  beforeEach(() => {
    db = getDb();
  });

  async function seedValidFixture() {
    await db.ref().set(null);

    const fixture = {
      users: {
        creator_alice: {
          DisplayName: 'Alice Creator',
          Favorites: {
            user_fav_bob: true,
          },
        },
        user_fav_bob: { DisplayName: 'Bob Favorite' },
        user_direct_charlie: { DisplayName: 'Charlie Target' },
        user_stranger_eve: { DisplayName: 'Eve Stranger' },
      },
      SubRequests: {
        // Public Staffing Request
        req_pub_1: {
          SubRequestId: 'req_pub_1',
          CreatorUserId: 'creator_alice',
          NotificationMode: 'both',
          VoicePart: 'Drums',
          Status: 'published',
        },
        // Direct Invitation
        req_direct_1: {
          SubRequestId: 'req_direct_1',
          CreatorUserId: 'creator_alice',
          NotificationMode: 'both',
          Type: 'direct_invitation',
          targetUserIds: ['user_direct_charlie'],
          VoicePart: 'Bass',
          Status: 'published',
        },
        // Favorites-only Request
        req_fav_1: {
          SubRequestId: 'req_fav_1',
          CreatorUserId: 'creator_alice',
          NotificationMode: 'both',
          IsFavoritesOnly: true,
          targetUserIds: ['user_fav_bob'],
          VoicePart: 'Guitar',
          Status: 'published',
        },
        // Promo Map Pin
        pin_promo_1: {
          SubRequestId: 'pin_promo_1',
          CreatorUserId: 'creator_alice',
          NotificationMode: 'map_pin',
          SnippetTitle: 'Promo Snippet',
          Status: 'published',
        },
      },
    };

    await db.ref().set(fixture);
    // Run backfill to create clean canonical feeds
    await runBackfill(db, true);
  }

  it('1. Valid complete migration -> returns success true and 0 violations', async () => {
    await seedValidFixture();
    const result = await verifyMigration();
    assert.strictEqual(result.success, true);
    assert.strictEqual(result.violations.length, 0);
  });

  it('2. Private request in public feed -> detected as DIRECT_INVITATION_LEAK_IN_PUBLIC', async () => {
    await seedValidFixture();
    // Infiltrate direct invitation into public feed
    await db.ref('publicSubRequests/req_direct_1').set({
      id: 'req_direct_1',
      Type: 'direct_invitation',
      VoicePart: 'Bass',
    });

    const result = await verifyMigration();
    assert.strictEqual(result.success, false);
    const leaked = result.violations.find((v) => v.category === 'DIRECT_INVITATION_LEAK_IN_PUBLIC');
    assert(leaked, 'Should detect DIRECT_INVITATION_LEAK_IN_PUBLIC');
    assert.strictEqual(leaked.id, 'req_direct_1');
  });

  it('3. Missing creator feed -> detected as MISSING_CREATOR_FEED_ENTRY', async () => {
    await seedValidFixture();
    // Delete creator feed entry
    await db.ref('creatorSubRequestFeed/creator_alice/req_pub_1').remove();

    const result = await verifyMigration();
    assert.strictEqual(result.success, false);
    const missing = result.violations.find((v) => v.category === 'MISSING_CREATOR_FEED_ENTRY');
    assert(missing, 'Should detect MISSING_CREATOR_FEED_ENTRY');
    assert.strictEqual(missing.id, 'req_pub_1');
  });

  it('4. Missing public feed -> detected as MISSING_PUBLIC_FEED_ENTRY', async () => {
    await seedValidFixture();
    // Delete public feed entry
    await db.ref('publicSubRequests/req_pub_1').remove();

    const result = await verifyMigration();
    assert.strictEqual(result.success, false);
    const missing = result.violations.find((v) => v.category === 'MISSING_PUBLIC_FEED_ENTRY');
    assert(missing, 'Should detect MISSING_PUBLIC_FEED_ENTRY');
    assert.strictEqual(missing.id, 'req_pub_1');
  });

  it('5. Map pin in staffing feed -> detected as MAP_PIN_IN_PUBLIC_FEED', async () => {
    await seedValidFixture();
    // Erroneously put promo pin in publicSubRequests
    await db.ref('publicSubRequests/pin_promo_1').set({
      id: 'pin_promo_1',
      SnippetTitle: 'Promo',
    });

    const result = await verifyMigration();
    assert.strictEqual(result.success, false);
    const mapLeak = result.violations.find((v) => v.category === 'MAP_PIN_IN_PUBLIC_FEED');
    assert(mapLeak, 'Should detect MAP_PIN_IN_PUBLIC_FEED');
    assert.strictEqual(mapLeak.id, 'pin_promo_1');
  });

  it('6. Orphan feed entry -> detected as ORPHAN_PUBLIC_FEED_ENTRY', async () => {
    await seedValidFixture();
    // Inject rogue entry in publicSubRequests that does not exist in /SubRequests
    await db.ref('publicSubRequests/orphan_ghost_1').set({
      id: 'orphan_ghost_1',
      VoicePart: 'Trumpet',
    });

    const result = await verifyMigration();
    assert.strictEqual(result.success, false);
    const orphan = result.violations.find((v) => v.category === 'ORPHAN_PUBLIC_FEED_ENTRY');
    assert(orphan, 'Should detect ORPHAN_PUBLIC_FEED_ENTRY');
    assert.strictEqual(orphan.id, 'orphan_ghost_1');
  });

  it('7. Sensitive field in sanitized feed -> detected as SENSITIVE_FIELD_LEAK', async () => {
    await seedValidFixture();
    // Inject private email into public feed item
    await db.ref('publicSubRequests/req_pub_1/email').set('secret@creator.com');

    const result = await verifyMigration();
    assert.strictEqual(result.success, false);
    const leak = result.violations.find((v) => v.category === 'SENSITIVE_FIELD_LEAK');
    assert(leak, 'Should detect SENSITIVE_FIELD_LEAK');
    assert.strictEqual(leak.id, 'req_pub_1');
  });

  it('8. Incorrect private recipient -> detected as UNAUTHORIZED_DIRECT_RECIPIENT', async () => {
    await seedValidFixture();
    // Infiltrate direct invitation intended for Charlie into Eve's feed
    await db.ref('userSubRequestFeed/user_stranger_eve/req_direct_1').set({
      id: 'req_direct_1',
      VoicePart: 'Bass',
    });

    const result = await verifyMigration();
    assert.strictEqual(result.success, false);
    const unauth = result.violations.find((v) => v.category === 'UNAUTHORIZED_DIRECT_RECIPIENT');
    assert(unauth, 'Should detect UNAUTHORIZED_DIRECT_RECIPIENT');
    assert.strictEqual(unauth.id, 'req_direct_1');
  });
});
