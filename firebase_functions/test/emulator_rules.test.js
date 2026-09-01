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

    it('Transitional: Band Leader CAN create legacy SubRequest with valid bandId and existing event', async () => {
      await testEnvTransitional.withSecurityRulesDisabled(async (context) => {
        const db = context.database();
        await db.ref('Bands/band_trans_test/Members_band/user_trans_leader').set({ Role: 'Leader' });
        await db.ref('Bands/band_trans_test/Events/event_trans_1').set({ title: 'Gig' });
      });

      const leader = testEnvTransitional.authenticatedContext('user_trans_leader');
      await assertSucceeds(
        leader.database().ref('SubRequests/sub_trans_1').set({
          SubRequestId: 'sub_trans_1',
          bandId: 'band_trans_test',
          eventId: 'event_trans_1',
          CreatorUserId: 'user_trans_leader',
          VoicePart: 'Guitar',
          Status: 'published',
        })
      );
    });

    it('Transitional: Client CANNOT create standalone SubRequest omitting bandId', async () => {
      const user = testEnvTransitional.authenticatedContext('user_trans_cand');
      await assertFails(
        user.database().ref('SubRequests/sub_trans_standalone').set({
          SubRequestId: 'sub_trans_standalone',
          CreatorUserId: 'user_trans_cand',
          VoicePart: 'Guitar',
          Status: 'published',
        })
      );
    });

    it('Transitional: Outsider CANNOT create SubRequest for band where not Leader/Admin', async () => {
      const outsider = testEnvTransitional.authenticatedContext('user_trans_outsider');
      await assertFails(
        outsider.database().ref('SubRequests/sub_trans_outsider').set({
          SubRequestId: 'sub_trans_outsider',
          bandId: 'band_trans_test',
          eventId: 'event_trans_1',
          CreatorUserId: 'user_trans_outsider',
          VoicePart: 'Drums',
          Status: 'published',
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
        await db.ref('SubRequests/sub_rules_test').set({
          SubRequestId: 'sub_rules_test',
          SlotId: 'slot_rules_1',
          slotId: 'slot_rules_1',
          RequestGroupId: 'group_rules_1',
          requestGroupId: 'group_rules_1',
          VoicePart: 'Electric Guitar',
          Status: 'published',
          CreatorUserId: 'user_leader',
          bandId: 'band_rules_test',
          eventId: 'event_open',
        });
        await db.ref('SubRequests/sub_slot_1').set({
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
        });
        await db.ref('SubRequests/sub_group_slot_1').set({
          SubRequestId: 'sub_group_slot_1',
          SlotId: 'slot_guitar_1',
          slotId: 'slot_guitar_1',
          CreatorUserId: 'user_leader',
          bandId: 'band_rules_test',
          eventId: 'event_open',
          VoicePart: 'Electric Guitar',
          Status: 'published',
          IsPaid: true,
          PayAmount: 1500,
          Currency: 'SEK',
          RequestGroupId: 'group_band_rules_test_event_open_123',
          requestGroupId: 'group_band_rules_test_event_open_123',
        });
        await db.ref('subRequestAudience/sub_rules_test/user_sub_cand_1').set(true);
      });
    });

    it('1. Band Leader can manage legitimate fields on existing SubRequests', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      await assertSucceeds(leader.database().ref('SubRequests/sub_slot_1/Status').set('cancelled'));
      await assertSucceeds(leader.database().ref('SubRequests/sub_slot_1/PayAmountMinor').set(150000));
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

    it('11. Creator or Band Leader can write to substituteAssignments for an event slot', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      const ref = leader.database().ref('Bands/band_rules_test/Events/event_open/substituteAssignments/slot_guitar_1');
      await assertSucceeds(
        ref.set({
          slotId: 'slot_guitar_1',
          subRequestId: 'sub_req_1',
          assignedUserId: 'user_sub_cand_1',
          status: 'assigned',
          instrument: 'Electric Guitar',
        })
      );
    });

    it('12. Unrelated user CANNOT write to substituteAssignments', async () => {
      const otherUser = testEnvFinal.authenticatedContext('user_other_band');
      const ref = otherUser.database().ref('Bands/band_rules_test/Events/event_open/substituteAssignments/slot_guitar_1');
      await assertFails(
        ref.set({
          slotId: 'slot_guitar_1',
          subRequestId: 'sub_req_1',
          assignedUserId: 'user_other_band',
          status: 'assigned',
          instrument: 'Electric Guitar',
        })
      );
    });

    it('13. Candidate can write their own response under SubRequests/Responses when indexed in audience', async () => {
      const candidate = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const ref = candidate.database().ref('SubRequests/sub_rules_test/Responses/user_sub_cand_1');
      await assertSucceeds(ref.set(true));

      // Unindexed candidate is denied
      const unindexed = testEnvFinal.authenticatedContext('user_sub_cand_2');
      const unindexedRef = unindexed.database().ref('SubRequests/sub_rules_test/Responses/user_sub_cand_2');
      await assertFails(unindexedRef.set(true));
    });

    it('14. Candidate CANNOT tamper with root fields of SubRequests', async () => {
      const candidate = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const ref = candidate.database().ref('SubRequests/sub_rules_test/AssignedUserId');
      await assertFails(
        ref.set('user_sub_cand_1')
      );
    });

    it('15. Unrelated user CANNOT overwrite an existing SubRequest', async () => {
      const otherUser = testEnvFinal.authenticatedContext('user_other_band');
      const ref = otherUser.database().ref('SubRequests/sub_rules_test');
      await assertFails(
        ref.update({
          CreatorUserId: 'user_other_band',
          Status: 'cancelled',
        })
      );
    });

    it('16. Client direct whole-node and assignment-field writes are DENIED (must use server assignSubstitute callable)', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(leader.database().ref('SubRequests/sub_rules_test/AssignedUserId').set('user_sub_cand_1'));
      await assertFails(leader.database().ref('SubRequests/sub_rules_test/AssignedUserName').set('Candidate 1'));
      await assertFails(leader.database().ref('SubRequests/sub_rules_test/AssignedAt').set(Date.now()));
      await assertFails(leader.database().ref('SubRequests/sub_rules_test/Status').set('assigned'));
    });

    it('17. Band Leader can update PayAmount and Currency on existing SubRequests', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      await assertSucceeds(leader.database().ref('SubRequests/sub_group_slot_1/PayAmount').set(1500));
      await assertSucceeds(leader.database().ref('SubRequests/sub_group_slot_1/Currency').set('SEK'));
    });

    it('18. Candidate CANNOT modify PayAmount or Currency on SubRequests', async () => {
      const candidate = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const ref = candidate.database().ref('SubRequests/sub_group_slot_1/PayAmount');
      await assertFails(ref.set(9999));
    });

    it('19. Candidate CANNOT modify RequestGroupId on SubRequests', async () => {
      const candidate = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const ref = candidate.database().ref('SubRequests/sub_group_slot_1/RequestGroupId');
      await assertFails(ref.set('tampered_group_id'));
    });

    it('20. Candidate CANNOT write another user response under SubRequests/Responses', async () => {
      const candidate = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const ref = candidate.database().ref('SubRequests/sub_group_slot_1/Responses/user_sub_cand_2');
      await assertFails(ref.set(true));
    });

    it('21. Unrelated user CANNOT cancel or delete SubRequests', async () => {
      const outsider = testEnvFinal.authenticatedContext('user_other_band');
      const ref = outsider.database().ref('SubRequests/sub_group_slot_1');
      await assertFails(ref.update({ Status: 'cancelled' }));
    });

    it('22. Authorized Band Leader CAN cancel SubRequest', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      const ref = leader.database().ref('SubRequests/sub_group_slot_1/Status');
      await assertSucceeds(ref.set('cancelled'));
    });

    it('23. User CAN add and remove targets under their own Favorites path', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      const ref = leader.database().ref('users/user_leader/Favorites/target_guitarist_99');
      await assertSucceeds(ref.set(true));
      await assertSucceeds(ref.remove());
    });

    it('24. User CANNOT modify another user Favorites path', async () => {
      const outsider = testEnvFinal.authenticatedContext('user_other_band');
      const ref = outsider.database().ref('users/user_sub_cand_1/Favorites/target_guitarist_99');
      await assertFails(ref.set(true));
    });

    it('25. User CANNOT create SubRequest for another band where they are not Leader/Admin', async () => {
      const outsider = testEnvFinal.authenticatedContext('user_other_band');
      const ref = outsider.database().ref('SubRequests/sub_unauthorized_band_slot');
      await assertFails(
        ref.set({
          SubRequestId: 'sub_unauthorized_band_slot',
          CreatorUserId: 'user_other_band',
          bandId: 'band_rules_test', // outsider is not a leader of band_rules_test
          eventId: 'event_open',
          VoicePart: 'Drums',
          Status: 'published',
        })
      );
    });

    it('26. User CANNOT attach SubRequest to a non-existent event on band', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      const ref = leader.database().ref('SubRequests/sub_invalid_event_slot');
      await assertFails(
        ref.set({
          SubRequestId: 'sub_invalid_event_slot',
          CreatorUserId: 'user_leader',
          bandId: 'band_rules_test',
          eventId: 'non_existent_event_999',
          VoicePart: 'Drums',
          Status: 'published',
        })
      );
    });

    it('27. Immutable identity: bandId CANNOT be changed after creation', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      const ref = leader.database().ref('SubRequests/sub_group_slot_1/bandId');
      await assertFails(ref.set('other_band_id'));
    });

    it('28. Immutable identity: eventId CANNOT be changed after creation', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      const ref = leader.database().ref('SubRequests/sub_group_slot_1/eventId');
      await assertFails(ref.set('other_event_id'));
    });

    it('29. Immutable identity: SlotId and RequestGroupId CANNOT be changed after creation', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(leader.database().ref('SubRequests/sub_group_slot_1/SlotId').set('other_slot_id'));
      await assertFails(leader.database().ref('SubRequests/sub_group_slot_1/slotId').set('other_slot_id'));
      await assertFails(leader.database().ref('SubRequests/sub_group_slot_1/RequestGroupId').set('other_group_id'));
      await assertFails(leader.database().ref('SubRequests/sub_group_slot_1/requestGroupId').set('other_group_id'));
    });

    it('30. Candidate response to cancelled SubRequest is REJECTED', async () => {
      const candidate = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const ref = candidate.database().ref('SubRequests/sub_group_slot_1/Responses/user_sub_cand_1');
      await assertFails(ref.set(true));
    });

    it('31. Targeted Favorite user with subRequestAudience entry CAN read SubRequest', async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        const db = context.database();
        await db.ref('SubRequests/sub_fav_targeted_1').set({
          SubRequestId: 'sub_fav_targeted_1',
          CreatorUserId: 'user_leader',
          bandId: 'band_rules_test',
          eventId: 'event_open',
          VoicePart: 'Electric Guitar',
          SearchSource: 'favorites',
          Status: 'published',
          PayAmountMinor: 150000,
          Currency: 'SEK',
        });
        await db.ref('subRequestAudience/sub_fav_targeted_1/user_sub_cand_1').set(true);
      });

      const targetedUser = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const snap = await assertSucceeds(targetedUser.database().ref('SubRequests/sub_fav_targeted_1').get());
      assert.strictEqual(snap.val().VoicePart, 'Electric Guitar');
    });

    it('32. Unselected user NOT in subRequestAudience CANNOT read Favorites-only SubRequest', async () => {
      const untargetedUser = testEnvFinal.authenticatedContext('user_sub_cand_2');
      await assertFails(untargetedUser.database().ref('SubRequests/sub_fav_targeted_1').get());
    });

    it('33. Unrelated authenticated outsider CANNOT read Favorites-only SubRequest', async () => {
      const outsider = testEnvFinal.authenticatedContext('user_other_band');
      await assertFails(outsider.database().ref('SubRequests/sub_fav_targeted_1').get());
    });

    it('34. Creator CAN read their own SubRequest regardless of audience', async () => {
      const creator = testEnvFinal.authenticatedContext('user_leader');
      const snap = await assertSucceeds(creator.database().ref('SubRequests/sub_fav_targeted_1').get());
      assert.strictEqual(snap.val().CreatorUserId, 'user_leader');
    });

    it('35. Client CANNOT forge entry under /subRequestAudience', async () => {
      const hacker = testEnvFinal.authenticatedContext('user_sub_cand_2');
      await assertFails(hacker.database().ref('subRequestAudience/sub_fav_targeted_1/user_sub_cand_2').set(true));
    });

    it('36. Client CANNOT write entry under /userSubRequestFeed', async () => {
      const hacker = testEnvFinal.authenticatedContext('user_sub_cand_2');
      await assertFails(hacker.database().ref('userSubRequestFeed/user_sub_cand_2/sub_fav_targeted_1').set(true));
    });

    it('37. User CAN read their own /userSubRequestFeed', async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        await context.database().ref('userSubRequestFeed/user_sub_cand_1/sub_fav_targeted_1').set({
          slotId: 'sub_fav_targeted_1',
          bandName: 'Electric Band',
          voicePart: 'Electric Guitar',
        });
      });

      const user = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const snap = await assertSucceeds(user.database().ref('userSubRequestFeed/user_sub_cand_1').get());
      assert.strictEqual(snap.exists(), true);
    });

    it('38. User CANNOT read another user /userSubRequestFeed', async () => {
      const hacker = testEnvFinal.authenticatedContext('user_sub_cand_2');
      await assertFails(hacker.database().ref('userSubRequestFeed/user_sub_cand_1').get());
    });

    it('39. Targeted Favorite in subRequestAudience CAN submit response to published SubRequest', async () => {
      const candidate = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const respRef = candidate.database().ref('SubRequests/sub_fav_targeted_1/Responses/user_sub_cand_1');
      await assertSucceeds(respRef.set(true));
    });

    it('40. Candidate NOT in subRequestAudience CANNOT submit response to Favorites-only SubRequest', async () => {
      const untargeted = testEnvFinal.authenticatedContext('user_sub_cand_2');
      const respRef = untargeted.database().ref('SubRequests/sub_fav_targeted_1/Responses/user_sub_cand_2');
      await assertFails(respRef.set(true));
    });

    it('41. Candidate CANNOT write response for another user node', async () => {
      const candidate = testEnvFinal.authenticatedContext('user_sub_cand_1');
      const respRef = candidate.database().ref('SubRequests/sub_fav_targeted_1/Responses/user_sub_cand_2');
      await assertFails(respRef.set(true));
    });

    it('42. Client CANNOT write publication manifest under /subRequestPublications', async () => {
      const client = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(client.database().ref('subRequestPublications/pub_forged_1').set({
        bandId: 'band_rules_test',
        slots: [],
      }));
    });

    it('43. Client CANNOT write to /subRequestNotificationAudit', async () => {
      const client = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(client.database().ref('subRequestNotificationAudit/pub_test').set({
        processedAt: Date.now(),
      }));
    });

    it('44. Creator management view reads creatorSubRequestGroups for own UID', async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        await context.database().ref('creatorSubRequestGroups/user_leader/group_123').set(true);
      });

      const leader = testEnvFinal.authenticatedContext('user_leader');
      const snap = await assertSucceeds(leader.database().ref('creatorSubRequestGroups/user_leader').get());
      assert.strictEqual(snap.val().group_123, true);
    });

    it('45. Outsider CANNOT read another creator creatorSubRequestGroups index', async () => {
      const outsider = testEnvFinal.authenticatedContext('user_other_band');
      await assertFails(outsider.database().ref('creatorSubRequestGroups/user_leader').get());
    });

    it('46. Candidate A CAN write Candidate A own response when in audience', async () => {
      const candA = testEnvFinal.authenticatedContext('user_sub_cand_1');
      await assertSucceeds(candA.database().ref('SubRequests/sub_fav_targeted_1/Responses/user_sub_cand_1').set(true));
    });

    it('47. Candidate A CANNOT write Candidate B response', async () => {
      const candA = testEnvFinal.authenticatedContext('user_sub_cand_1');
      await assertFails(candA.database().ref('SubRequests/sub_fav_targeted_1/Responses/user_sub_cand_2').set(true));
    });

    it('48. Creator CANNOT create or overwrite Candidate A response through parent write', async () => {
      const creator = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(creator.database().ref('SubRequests/sub_fav_targeted_1/Responses/user_sub_cand_1').set({ forged: true }));
    });

    it('49. Creator CANNOT delete Candidate A response', async () => {
      // Seed candidate response
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        await context.database().ref('SubRequests/sub_fav_targeted_1/Responses/user_sub_cand_1').set(true);
      });
      const creator = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(creator.database().ref('SubRequests/sub_fav_targeted_1/Responses/user_sub_cand_1').remove());
    });

    it('50. Band Leader/Admin CANNOT forge or delete candidate responses under SubRequests/Responses', async () => {
      const admin = testEnvFinal.authenticatedContext('user_admin');
      await assertFails(admin.database().ref('SubRequests/sub_fav_targeted_1/Responses/user_sub_cand_2').set(true));
    });

    it('51. Creator CAN still update legitimate request-management fields without modifying Responses', async () => {
      const creator = testEnvFinal.authenticatedContext('user_leader');
      await assertSucceeds(creator.database().ref('SubRequests/sub_fav_targeted_1/Status').set('cancelled'));
      await assertSucceeds(creator.database().ref('SubRequests/sub_fav_targeted_1/PayAmountMinor').set(180000));
    });

    it('52. Request creation containing pre-populated forged Responses is REJECTED', async () => {
      const creator = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(creator.database().ref('SubRequests/sub_new_forged_responses').set({
        CreatorUserId: 'user_leader',
        bandId: 'band_rules_test',
        eventId: 'event_rules_1',
        VoicePart: 'Drums',
        Status: 'published',
        Responses: {
          user_sub_cand_1: true,
        },
      }));
    });

    it('53. Legacy record with only SlotId rejects adding slotId or mutating SlotId', async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        await context.database().ref('SubRequests/sub_legacy_slot_upper').set({
          SlotId: 'slot_only_upper',
          CreatorUserId: 'user_leader',
          bandId: 'band_rules_test',
          Status: 'published',
        });
      });
      const leader = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(leader.database().ref('SubRequests/sub_legacy_slot_upper/slotId').set('slot_new_lower'));
      await assertFails(leader.database().ref('SubRequests/sub_legacy_slot_upper/SlotId').set('slot_mutated'));
      await assertFails(leader.database().ref('SubRequests/sub_legacy_slot_upper/SlotId').remove());
    });

    it('54. Legacy record with only slotId rejects adding SlotId or mutating slotId', async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        await context.database().ref('SubRequests/sub_legacy_slot_lower').set({
          slotId: 'slot_only_lower',
          CreatorUserId: 'user_leader',
          bandId: 'band_rules_test',
          Status: 'published',
        });
      });
      const leader = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(leader.database().ref('SubRequests/sub_legacy_slot_lower/SlotId').set('slot_new_upper'));
      await assertFails(leader.database().ref('SubRequests/sub_legacy_slot_lower/slotId').set('slot_mutated'));
      await assertFails(leader.database().ref('SubRequests/sub_legacy_slot_lower/slotId').remove());
    });

    it('55. Legacy record with only RequestGroupId rejects adding requestGroupId or mutating RequestGroupId', async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        await context.database().ref('SubRequests/sub_legacy_group_upper').set({
          RequestGroupId: 'group_only_upper',
          CreatorUserId: 'user_leader',
          bandId: 'band_rules_test',
          Status: 'published',
        });
      });
      const leader = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(leader.database().ref('SubRequests/sub_legacy_group_upper/requestGroupId').set('group_new_lower'));
      await assertFails(leader.database().ref('SubRequests/sub_legacy_group_upper/RequestGroupId').set('group_mutated'));
      await assertFails(leader.database().ref('SubRequests/sub_legacy_group_upper/RequestGroupId').remove());
    });

    it('56. Legacy record with only requestGroupId rejects adding RequestGroupId or mutating requestGroupId', async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        await context.database().ref('SubRequests/sub_legacy_group_lower').set({
          requestGroupId: 'group_only_lower',
          CreatorUserId: 'user_leader',
          bandId: 'band_rules_test',
          Status: 'published',
        });
      });
      const leader = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(leader.database().ref('SubRequests/sub_legacy_group_lower/RequestGroupId').set('group_new_upper'));
      await assertFails(leader.database().ref('SubRequests/sub_legacy_group_lower/requestGroupId').set('group_mutated'));
      await assertFails(leader.database().ref('SubRequests/sub_legacy_group_lower/requestGroupId').remove());
    });

    it('57. Conflicting-casing bandId/BandId and eventId/EventId mutations are REJECTED', async () => {
      await testEnvFinal.withSecurityRulesDisabled(async (context) => {
        await context.database().ref('SubRequests/sub_casing_conflict').set({
          bandId: 'band_rules_test',
          eventId: 'event_open',
          CreatorUserId: 'user_leader',
          Status: 'published',
        });
      });
      const leader = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(leader.database().ref('SubRequests/sub_casing_conflict/BandId').set('band_other'));
      await assertFails(leader.database().ref('SubRequests/sub_casing_conflict/EventId').set('event_other'));
      await assertFails(leader.database().ref('SubRequests/sub_casing_conflict/bandId').set('band_other'));
      await assertFails(leader.database().ref('SubRequests/sub_casing_conflict/eventId').set('event_other'));
    });

    it('58. Direct client creation of published SubRequest is BLOCKED in final rules', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(leader.database().ref('SubRequests/sub_direct_client_publish').set({
        CreatorUserId: 'user_leader',
        bandId: 'band_rules_test',
        eventId: 'event_open',
        VoicePart: 'Vocals',
        Status: 'published',
      }));
    });

    it('59. Direct client creation of standalone SubRequest omitting bandId is BLOCKED', async () => {
      const user = testEnvFinal.authenticatedContext('user_sub_cand_1');
      await assertFails(user.database().ref('SubRequests/sub_direct_standalone').set({
        CreatorUserId: 'user_sub_cand_1',
        VoicePart: 'Electric Guitar',
        Status: 'published',
      }));
    });

    it('60. Direct client creation by unauthorized outsider is BLOCKED', async () => {
      const outsider = testEnvFinal.authenticatedContext('user_other_band');
      await assertFails(outsider.database().ref('SubRequests/sub_direct_outsider').set({
        CreatorUserId: 'user_other_band',
        bandId: 'band_rules_test',
        eventId: 'event_open',
        VoicePart: 'Bass',
        Status: 'published',
      }));
    });

    it('61. Clients CANNOT forge or mutate server-owned PublicationId or NotificationMode', async () => {
      const leader = testEnvFinal.authenticatedContext('user_leader');
      await assertFails(leader.database().ref('SubRequests/sub_rules_test/PublicationId').set('forged_pub'));
      await assertFails(leader.database().ref('SubRequests/sub_rules_test/publicationId').set('forged_pub'));
      await assertFails(leader.database().ref('SubRequests/sub_rules_test/NotificationMode').set('grouped'));
      await assertFails(leader.database().ref('SubRequests/sub_rules_test/notificationMode').set('grouped'));
    });
  });
});
