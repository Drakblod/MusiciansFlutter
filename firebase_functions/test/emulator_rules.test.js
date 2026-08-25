const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID_TRANSITIONAL = 'demo-musicians-transitional';
const PROJECT_ID_FINAL = 'demo-musicians-final';
const DB_PORT = 9000;

describe('Real RTDB Emulator Rules Tests', function () {
  this.timeout(15000);

  let testEnvTransitional;
  let testEnvFinal;

  before(async () => {
    // Fail fast if database emulator host env is not set
    process.env.FIREBASE_DATABASE_EMULATOR_HOST = '127.0.0.1:9000';

    const transitionalRules = fs.readFileSync(
      path.join(__dirname, '../../database.transitional.rules.json'),
      'utf8'
    );
    const finalRules = fs.readFileSync(
      path.join(__dirname, '../../database.rules.json'),
      'utf8'
    );

    // Using separate project IDs ensures isolated RTDB emulator namespaces
    testEnvTransitional = await initializeTestEnvironment({
      projectId: PROJECT_ID_TRANSITIONAL,
      database: {
        host: '127.0.0.1',
        port: DB_PORT,
        rules: transitionalRules,
      },
    });

    testEnvFinal = await initializeTestEnvironment({
      projectId: PROJECT_ID_FINAL,
      database: {
        host: '127.0.0.1',
        port: DB_PORT,
        rules: finalRules,
      },
    });
  });

  after(async () => {
    if (testEnvTransitional) await testEnvTransitional.cleanup();
    if (testEnvFinal) await testEnvFinal.cleanup();
  });

  describe('1. Transitional Rules Evaluation (database.transitional.rules.json)', () => {
    it('User A can read userConversations/user_a', async () => {
      const userAContext = testEnvTransitional.authenticatedContext('user_a');
      const ref = userAContext.database().ref('userConversations/user_a');
      await assertSucceeds(ref.get());
    });

    it('User A CANNOT read userConversations/user_b', async () => {
      const userAContext = testEnvTransitional.authenticatedContext('user_a');
      const ref = userAContext.database().ref('userConversations/user_b');
      await assertFails(ref.get());
    });

    it('Clients CANNOT write to userConversations', async () => {
      const userAContext = testEnvTransitional.authenticatedContext('user_a');
      const ref = userAContext.database().ref('userConversations/user_a/conv_1');
      await assertFails(ref.set({ otherUserId: 'user_b' }));
    });

    it('Authenticated legacy client CAN write to conversations during transitional phase', async () => {
      const userAContext = testEnvTransitional.authenticatedContext('user_a');
      const ref = userAContext.database().ref('conversations/legacy_conv_1/messages/msg_1');
      await assertSucceeds(ref.set({ text: 'Legacy message', senderId: 'user_a' }));
    });

    it('Unauthenticated access to conversations is DENIED in transitional rules', async () => {
      const unauthContext = testEnvTransitional.unauthenticatedContext();
      const ref = unauthContext.database().ref('conversations/legacy_conv_1');
      await assertFails(ref.get());
      await assertFails(ref.set({ text: 'Hack' }));
    });
  });

  describe('2. Final Restrictive Rules Evaluation (database.rules.json)', () => {
    beforeEach(async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        const db = context.database();
        await db.ref('conversations/conv_canonical').set({
          participants: { user_a: true, user_b: true },
          createdTimestamp: '2026-08-12T12:00:00Z',
        });
        await db.ref('conversations/conv_migrated').set({
          participants: { user_a: true, user_b: true },
          Participants: ['user_a', 'user_b'],
          createdTimestamp: '2026-08-12T12:00:00Z',
        });
      });
    });

    it('Participant A and Participant B CAN read canonical lowercase conversation', async () => {
      const userA = testEnvFinal.authenticatedContext('user_a');
      const userB = testEnvFinal.authenticatedContext('user_b');
      await assertSucceeds(userA.database().ref('conversations/conv_canonical').get());
      await assertSucceeds(userB.database().ref('conversations/conv_canonical').get());
    });

    it('Non-participant User C CANNOT read canonical conversation', async () => {
      const userC = testEnvFinal.authenticatedContext('user_c');
      await assertFails(userC.database().ref('conversations/conv_canonical').get());
    });

    it('Migrated conversation with canonical participants map is readable by A & B and denied to C', async () => {
      const userA = testEnvFinal.authenticatedContext('user_a');
      const userB = testEnvFinal.authenticatedContext('user_b');
      const userC = testEnvFinal.authenticatedContext('user_c');

      await assertSucceeds(userA.database().ref('conversations/conv_migrated').get());
      await assertSucceeds(userB.database().ref('conversations/conv_migrated').get());
      await assertFails(userC.database().ref('conversations/conv_migrated').get());
    });

    it('Direct client writes to conversations are BLOCKED in final rules', async () => {
      const userA = testEnvFinal.authenticatedContext('user_a');
      const ref = userA.database().ref('conversations/conv_canonical/messages/msg_new');
      await assertFails(ref.set({ text: 'Client write attempt' }));
    });

    it('User can read ONLY their own conversation index', async () => {
      const userA = testEnvFinal.authenticatedContext('user_a');
      await assertSucceeds(userA.database().ref('userConversations/user_a').get());
      await assertFails(userA.database().ref('userConversations/user_b').get());
    });

    it('Unauthenticated access to any node is DENIED in final rules', async () => {
      const unauth = testEnvFinal.unauthenticatedContext();
      await assertFails(unauth.database().ref('conversations/conv_canonical').get());
      await assertFails(unauth.database().ref('userConversations/user_a').get());
    });

    it('Participant who is current band member CAN read band_section conversation', async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        const db = context.database();
        await db.ref('Bands/band_sec_1/Members_band/user_a').set({ Role: 'Member' });
        await db.ref('conversations/conv_section_1').set({
          conversationType: 'band_section',
          bandId: 'band_sec_1',
          participants: { user_a: true, user_b: true },
        });
      });

      const userA = testEnvFinal.authenticatedContext('user_a');
      await assertSucceeds(userA.database().ref('conversations/conv_section_1').get());
    });

    it('Participant who is NOT a current band member CANNOT read band_section conversation', async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        const db = context.database();
        // user_b is in participants but NOT in Bands/band_sec_1/Members_band
        await db.ref('conversations/conv_section_1').set({
          conversationType: 'band_section',
          bandId: 'band_sec_1',
          participants: { user_a: true, user_b: true },
        });
      });

      const userB = testEnvFinal.authenticatedContext('user_b');
      await assertFails(userB.database().ref('conversations/conv_section_1').get());
    });

    it('Clients CANNOT read or write to bandSectionConversations', async () => {
      const userA = testEnvFinal.authenticatedContext('user_a');
      await assertFails(userA.database().ref('bandSectionConversations/band_sec_1').get());
      await assertFails(userA.database().ref('bandSectionConversations/band_sec_1/conv_1').set(true));
    });
  });
});
