const fs = require('fs');
const path = require('path');
const assert = require('assert');
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
    process.env.FIREBASE_DATABASE_EMULATOR_HOST = '127.0.0.1:9000';

    const transitionalRules = fs.readFileSync(
      path.join(__dirname, '../../database.transitional.rules.json'),
      'utf8'
    );
    const finalRules = fs.readFileSync(
      path.join(__dirname, '../../database.rules.json'),
      'utf8'
    );

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

    it('Clients CANNOT write to userConversations in transitional rules', async () => {
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

    it('Session RSVP and Application restrictions work in transitional rules', async () => {
      await testEnvTransitional.withSecurityRulesDisabled(async (context) => {
        const db = context.database();
        await db.ref('Collabs/Sessions/sess_trans_test').set({
          CreatorId: 'creator_trans',
          Title: 'Transitional Session',
          Description: 'Testing transitional rules',
          SessionType: 'In person',
          Status: 'active',
        });
        await db.ref('Collabs/Applications/sess_trans_test/user_trans_acc').set({
          SessionId: 'sess_trans_test',
          CreatorId: 'creator_trans',
          Status: 'accepted',
        });
      });

      const userAcc = testEnvTransitional.authenticatedContext('user_trans_acc');
      await assertSucceeds(
        userAcc.database().ref('Collabs/Sessions/sess_trans_test/Responses/user_trans_acc').set({
          status: 'YES',
          timestamp: '2026-08-28T12:00:00Z',
        })
      );

      const userPending = testEnvTransitional.authenticatedContext('user_trans_pending');
      await assertFails(
        userPending.database().ref('Collabs/Sessions/sess_trans_test/Responses/user_trans_pending').set({
          status: 'YES',
          timestamp: '2026-08-28T12:00:00Z',
        })
      );
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
  });

  describe('3. Granular Session Node Security & Cascading Write Prevention', () => {
    beforeEach(async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        const db = context.database();
        await db.ref('Collabs/Sessions/sess_cascade_test').set({
          CreatorId: 'user_creator',
          Title: 'Original Title',
          Description: 'Original Desc',
          SessionType: 'In person',
          SessionCategory: 'Songwriting',
          IsDateFlexible: false,
          StartDateTime: '2026-09-01T19:00:00Z',
          EndDateTime: '2026-09-01T21:00:00Z',
          Location: 'Studio 1',
          Genres: ['Rock'],
          RequireResponse: true,
          RsvpDeadline: 1756789000000,
          ReminderIntervalHours: 48,
          CreatedAt: 1700000000000,
          UpdatedAt: 1700000000000,
          Status: 'active',
          SessionChatId: 'chat_session_999',
          ParentSessionId: 'sess_parent_1',
          SubSessionSequence: 2,
          customUnknownField: 'preserved_payload',
          Responses: {
            user_accepted: {
              status: 'YES',
              timestamp: '2026-08-28T12:00:00Z',
            },
          },
        });
        await db.ref('Collabs/Applications/sess_cascade_test/user_accepted').set({
          SessionId: 'sess_cascade_test',
          CreatorId: 'user_creator',
          Status: 'accepted',
        });
        await db.ref('Collabs/Applications/sess_cascade_test/user_pending').set({
          SessionId: 'sess_cascade_test',
          CreatorId: 'user_creator',
          Status: 'pending',
        });
      });
    });

    it('1. Creator can create a valid new Session (data.exists() == false)', async () => {
      const creator = testEnvFinal.authenticatedContext('user_new_creator');
      const ref = creator.database().ref('Collabs/Sessions/sess_brand_new');
      await assertSucceeds(ref.set({
        CreatorId: 'user_new_creator',
        Title: 'Brand New Jam',
        Description: 'New jam session',
        SessionType: 'Remote',
        SessionCategory: 'Jam',
        IsDateFlexible: false,
        Status: 'active',
      }));
    });

    it('2. Creator can update Title through supported narrow update', async () => {
      const creator = testEnvFinal.authenticatedContext('user_creator');
      const ref = creator.database().ref('Collabs/Sessions/sess_cascade_test/Title');
      await assertSucceeds(ref.set('Updated Session Title'));
    });

    it('3. Creator CANNOT replace the complete existing Session node (whole-node overwrite blocked)', async () => {
      const creator = testEnvFinal.authenticatedContext('user_creator');
      const ref = creator.database().ref('Collabs/Sessions/sess_cascade_test');
      // Direct whole-node set is blocked when data.exists() == true
      await assertFails(ref.set({
        CreatorId: 'user_creator',
        Title: 'Hacked Whole Node',
        Description: 'Replaced all children',
        SessionType: 'In person',
        Status: 'active',
      }));
    });

    it('4. Creator CANNOT overwrite or delete Responses node', async () => {
      const creator = testEnvFinal.authenticatedContext('user_creator');
      const ref = creator.database().ref('Collabs/Sessions/sess_cascade_test/Responses');
      await assertFails(ref.set({}));
    });

    it('5. Creator CANNOT change CreatorId', async () => {
      const creator = testEnvFinal.authenticatedContext('user_creator');
      const ref = creator.database().ref('Collabs/Sessions/sess_cascade_test/CreatorId');
      await assertFails(ref.set('user_other_creator'));
    });

    it('6. Creator CANNOT change CreatedAt', async () => {
      const creator = testEnvFinal.authenticatedContext('user_creator');
      const ref = creator.database().ref('Collabs/Sessions/sess_cascade_test/CreatedAt');
      await assertFails(ref.set(9999999999999));
    });

    it('7. Creator CANNOT change SessionChatId', async () => {
      const creator = testEnvFinal.authenticatedContext('user_creator');
      const ref = creator.database().ref('Collabs/Sessions/sess_cascade_test/SessionChatId');
      await assertFails(ref.set('injected_chat_id'));
    });

    it('8. Creator CANNOT change grouping identity (ParentSessionId / SubSessionSequence)', async () => {
      const creator = testEnvFinal.authenticatedContext('user_creator');
      const pRef = creator.database().ref('Collabs/Sessions/sess_cascade_test/ParentSessionId');
      const sRef = creator.database().ref('Collabs/Sessions/sess_cascade_test/SubSessionSequence');
      await assertFails(pRef.set('new_parent'));
      await assertFails(sRef.set(5));
    });

    it('9. Accepted participant can write only their own RSVP response', async () => {
      const acceptedUser = testEnvFinal.authenticatedContext('user_accepted');
      const ref = acceptedUser.database().ref('Collabs/Sessions/sess_cascade_test/Responses/user_accepted');
      await assertSucceeds(ref.set({
        status: 'NO',
        timestamp: '2026-08-28T13:00:00Z',
      }));
    });

    it('10. Accepted participant CANNOT modify metadata', async () => {
      const acceptedUser = testEnvFinal.authenticatedContext('user_accepted');
      const ref = acceptedUser.database().ref('Collabs/Sessions/sess_cascade_test/Title');
      await assertFails(ref.set('Tampered Title'));
    });

    it('11. Unknown existing fields survive a normal creator metadata update', async () => {
      const creator = testEnvFinal.authenticatedContext('user_creator');
      await assertSucceeds(
        creator.database().ref('Collabs/Sessions/sess_cascade_test/Description').set('Updated Description only')
      );

      // Verify custom field still intact
      let customFieldVal;
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        const snap = await context.database().ref('Collabs/Sessions/sess_cascade_test/customUnknownField').get();
        customFieldVal = snap.val();
      });
      assert.strictEqual(customFieldVal, 'preserved_payload');
    });

    it('12. Unauthorized user cannot update or delete the Session', async () => {
      const unauthorized = testEnvFinal.authenticatedContext('user_unauthorized');
      const sessionRef = unauthorized.database().ref('Collabs/Sessions/sess_cascade_test');
      await assertFails(sessionRef.remove());
      await assertFails(unauthorized.database().ref('Collabs/Sessions/sess_cascade_test/Title').set('Hacked'));
    });
  });

  describe('4. Secure Application Status Transitions', () => {
    it('1. Applicant can create own application only with status pending', async () => {
      const applicant = testEnvFinal.authenticatedContext('user_applicant_1');
      const ref = applicant.database().ref('Collabs/Applications/sess_cascade_test/user_applicant_1');
      await assertSucceeds(ref.set({
        SessionId: 'sess_cascade_test',
        CreatorId: 'user_creator',
        Status: 'pending',
      }));
    });

    it('2. Applicant CANNOT create application with status accepted or declined', async () => {
      const applicant = testEnvFinal.authenticatedContext('user_applicant_2');
      const ref = applicant.database().ref('Collabs/Applications/sess_cascade_test/user_applicant_2');
      await assertFails(ref.set({
        SessionId: 'sess_cascade_test',
        CreatorId: 'user_creator',
        Status: 'accepted',
      }));
    });

    it('3. Direct client writes changing Status to accepted/declined are BLOCKED', async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        await context.database().ref('Collabs/Applications/sess_cascade_test/user_app_test').set({
          SessionId: 'sess_cascade_test',
          CreatorId: 'user_creator',
          Status: 'pending',
        });
      });

      const creator = testEnvFinal.authenticatedContext('user_creator');
      const ref = creator.database().ref('Collabs/Applications/sess_cascade_test/user_app_test/Status');
      // Direct client write changing status is blocked (must use Cloud Function callable)
      await assertFails(ref.set('accepted'));
    });

    it('4. Applicant can withdraw/delete their own application', async () => {
      const applicant = testEnvFinal.authenticatedContext('user_pending');
      const ref = applicant.database().ref('Collabs/Applications/sess_cascade_test/user_pending');
      await assertSucceeds(ref.remove());
    });
  });

  describe('5. MULTI-SUBS-01: SubRequests & Band Event External Invitees Staffing Authorization Rules Tests', () => {
    before(async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        const db = context.database();
        // Seed band, members, and event
        await db.ref('Bands/band_rules_test/Members_band/user_leader').set({
          Role: 'Leader',
          Nickname: 'Band Leader',
        });
        await db.ref('Bands/band_rules_test/Members_band/user_admin').set({
          Role: 'Admin',
          Nickname: 'Band Admin',
        });
        await db.ref('Bands/band_rules_test/Members_band/user_member').set({
          Role: 'Member',
          Nickname: 'Band Member',
        });
        await db.ref('Bands/band_rules_test/Events/event_open').set({
          title: 'Open Gig',
          isLocked: false,
          createdBy: 'user_leader',
        });
        await db.ref('Bands/band_rules_test/Events/event_locked').set({
          title: 'Locked Gig',
          isLocked: true,
          createdBy: 'user_leader',
        });
      });
    });

    it('1. Authenticated user can publish and update SubRequests with additive fields', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      const ref = leader.database().ref('SubRequests/sub_slot_1');
      await assertSucceeds(
        ref.set({
          SubRequestId: 'sub_slot_1',
          SlotId: 'slot_guitar_1',
          ReplacedMemberId: 'user_member',
          ReplacedMemberName: 'Band Member',
          VoicePart: 'Electric Guitar',
          Status: 'published',
          SearchSource: 'favorites',
          CreatorUserId: 'user_leader',
          BandId: 'band_rules_test',
          EventId: 'event_open',
        })
      );
    });

    it('2. Unauthenticated user CANNOT read or write SubRequests', async () => {
      const unauth = testEnvFinal.unauthenticatedContext();
      await assertFails(unauth.database().ref('SubRequests/sub_slot_1').get());
      await assertFails(unauth.database().ref('SubRequests/sub_slot_1').set({ Status: 'hacked' }));
    });

    it('3. Band Leader can write to externalInvitees for any candidate', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      const ref = leader.database().ref('Bands/band_rules_test/Events/event_open/externalInvitees/user_sub_cand_1');
      await assertSucceeds(
        ref.set({
          userId: 'user_sub_cand_1',
          status: 'attending',
          instrument: 'Electric Guitar',
          displayName: 'Candidate One',
        })
      );
    });

    it('4. Band Admin can write to externalInvitees for any candidate', async () => {
      const admin = testEnvFinal.authenticatedContext('user_admin');
      const ref = admin.database().ref('Bands/band_rules_test/Events/event_open/externalInvitees/user_sub_cand_2');
      await assertSucceeds(
        ref.set({
          userId: 'user_sub_cand_2',
          status: 'attending',
          instrument: 'Drums',
          displayName: 'Candidate Two',
        })
      );
    });

    it('5. Candidate can write their OWN response under externalInvitees when event is not locked', async () => {
      const candidate = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const ref = candidate.database().ref('Bands/band_rules_test/Events/event_open/externalInvitees/user_sub_cand_1');
      await assertSucceeds(
        ref.set({
          userId: 'user_sub_cand_1',
          status: 'attending',
          instrument: 'Electric Guitar',
        })
      );
    });

    it('6. Candidate CANNOT modify another candidate’s externalInvitees entry', async () => {
      const candidate1 = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const ref = candidate1.database().ref('Bands/band_rules_test/Events/event_open/externalInvitees/user_sub_cand_2');
      await assertFails(
        ref.set({
          userId: 'user_sub_cand_2',
          status: 'declined',
        })
      );
    });

    it('7. Unrelated user from another band CANNOT write to externalInvitees', async () => {
      const outsider = testEnvFinal.authenticatedContext('user_outsider_stranger');
      const ref = outsider.database().ref('Bands/band_rules_test/Events/event_open/externalInvitees/user_sub_cand_1');
      await assertFails(
        ref.set({
          userId: 'user_sub_cand_1',
          status: 'hacked',
        })
      );
    });

    it('8. Candidate CANNOT modify externalInvitees when event is locked (isLocked: true)', async () => {
      const candidate = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const ref = candidate.database().ref('Bands/band_rules_test/Events/event_locked/externalInvitees/user_sub_cand_1');
      await assertFails(
        ref.set({
          userId: 'user_sub_cand_1',
          status: 'attending',
        })
      );
    });

    it('9. Band Leader CAN still manage externalInvitees when event is locked', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      const ref = leader.database().ref('Bands/band_rules_test/Events/event_locked/externalInvitees/user_sub_cand_1');
      await assertSucceeds(
        ref.set({
          userId: 'user_sub_cand_1',
          status: 'attending',
          instrument: 'Electric Guitar',
        })
      );
    });

    it('10. User cannot write to another band member’s regular Responses node', async () => {
      const candidate = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const ref = candidate.database().ref('Bands/band_rules_test/Events/event_open/Responses/user_member');
      await assertFails(
        ref.set({
          status: 'YES',
        })
      );
    });
  });
});
