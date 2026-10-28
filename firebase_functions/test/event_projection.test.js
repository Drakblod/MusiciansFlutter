const assert = require('assert');
const {
  isValidCoordinate,
  buildMapItemId,
  buildProjectionIndexKey,
  sanitizeDescription,
  isEventPast,
  getAuthorizedUserIdsForBandEvent,
  buildEventProjections,
  calculateReconciliationDiff,
} = require('../event_projection');

describe('EVENT-PROJECTION-UNIT-TESTS', () => {
  it('1. Coordinates: rejects 0/0, null, undefined, out-of-bounds, accepts valid coords', () => {
    assert.strictEqual(isValidCoordinate(0, 0), false);
    assert.strictEqual(isValidCoordinate(null, 18.0), false);
    assert.strictEqual(isValidCoordinate(59.3, undefined), false);
    assert.strictEqual(isValidCoordinate(95.0, 18.0), false);
    assert.strictEqual(isValidCoordinate(59.3, 190.0), false);
    assert.strictEqual(isValidCoordinate('invalid', 18.0), false);
    assert.strictEqual(isValidCoordinate(59.3293, 18.0686), true);
  });

  it('2. Deterministic IDs: single private, multi-part private, and public', () => {
    assert.strictEqual(
      buildMapItemId('private_band', 'band_1', 'evt_1', null),
      'event:private:band_1:evt_1'
    );
    assert.strictEqual(
      buildMapItemId('private_band', 'band_1', 'evt_1', 'part_soundcheck'),
      'event:private:band_1:evt_1:part_soundcheck'
    );
    assert.strictEqual(
      buildMapItemId('public_calendar', null, 'pub_evt_1', null),
      'event:public:pub_evt_1'
    );
  });

  it('3. Sanitization: strips HTML, script tags, caps length', () => {
    const dirty = '<script>alert("xss")</script><b>Hello</b>   World!';
    const clean = sanitizeDescription(dirty);
    assert.strictEqual(clean, 'Hello World!');
  });

  it('4. Authorization: includes members, invitees, confirmed subs, creator; excludes excludedMemberIds', () => {
    const bandData = {
      Members_band: {
        user_leader: { Role: 'Leader' },
        user_member1: { Role: 'Member' },
        user_member2: { Role: 'Member' },
        user_excluded: { Role: 'Member' },
      },
    };

    const eventData = {
      createdBy: 'user_leader',
      excludedMemberIds: ['user_excluded'],
      externalInvitees: {
        user_guest1: { status: 'attending' },
        user_declined: { status: 'declined' },
      },
      substituteAssignments: {
        slot_1: { assignedUserId: 'user_sub1', status: 'assigned' },
        slot_2: { assignedUserId: 'user_sub_unassigned', status: 'unassigned' },
      },
    };

    const authorized = getAuthorizedUserIdsForBandEvent(bandData, eventData);
    assert.ok(authorized.includes('user_leader'));
    assert.ok(authorized.includes('user_member1'));
    assert.ok(authorized.includes('user_member2'));
    assert.ok(authorized.includes('user_guest1'));
    assert.ok(authorized.includes('user_sub1'));

    // Strictly excluded
    assert.strictEqual(authorized.includes('user_excluded'), false);
    assert.strictEqual(authorized.includes('user_declined'), false);
    assert.strictEqual(authorized.includes('user_sub_unassigned'), false);
  });

  it('5. Projection allowlist: sensitive fields are NEVER leaked', () => {
    const refNow = new Date('2026-10-28T12:00:00Z');
    const privateEvent = {
      title: 'Secret Album Rehearsal',
      description: 'Preparing new tracks',
      eventType: 'Rehearsal',
      location: 'Studio A',
      startDateTime: '2026-10-30T18:00:00Z',
      endDateTime: '2026-10-30T21:00:00Z',
      latitude: 59.33,
      longitude: 18.06,
      createdBy: 'user_creator',
      // Sensitive fields that MUST NOT leak
      Responses: {
        user_1: { status: 'YES', comment: 'Private comment', uncertainReason: 'none' },
      },
      ScheduleResponses: { part_1: { user_1: { status: 'NO' } } },
      externalInvitees: { user_guest: { phone: '+12345678', email: 'guest@example.com' } },
      substituteAssignments: { slot_1: { assignedUserId: 'sub_uid', token: 'secret_token' } },
      fcmToken: 'fcm_12345',
      deviceToken: 'token_abc',
      internalChatId: 'chat_secret',
    };

    const projections = buildEventProjections(
      'private_band',
      privateEvent,
      'evt_secret',
      'band_test',
      'The Band',
      refNow
    );

    assert.strictEqual(projections.length, 1);
    const p = projections[0];

    assert.strictEqual(p.mapItemId, 'event:private:band_test:evt_secret');
    assert.strictEqual(p.title, 'Secret Album Rehearsal');
    assert.strictEqual(p.latitude, 59.33);
    assert.strictEqual(p.longitude, 18.06);

    // Verify sensitive fields are completely absent
    assert.strictEqual(p.Responses, undefined);
    assert.strictEqual(p.ScheduleResponses, undefined);
    assert.strictEqual(p.externalInvitees, undefined);
    assert.strictEqual(p.substituteAssignments, undefined);
    assert.strictEqual(p.fcmToken, undefined);
    assert.strictEqual(p.deviceToken, undefined);
    assert.strictEqual(p.internalChatId, undefined);
    assert.strictEqual(p.phone, undefined);
    assert.strictEqual(p.email, undefined);
  });

  it('6. Multi-part events: part inherits parent coords, never sibling coords; parent container not duplicated', () => {
    const refNow = new Date('2026-10-28T12:00:00Z');
    const multiEvent = {
      title: 'Weekend Festival',
      eventType: 'Festival',
      location: 'Central Park',
      startDateTime: '2026-10-29T10:00:00Z',
      endDateTime: '2026-10-31T22:00:00Z',
      latitude: 59.33,
      longitude: 18.06,
      rehearsals: [
        {
          id: 'part_soundcheck',
          title: 'Soundcheck',
          date: '2026-10-29',
          startTime: '10:00',
          endTime: '12:00',
          // Lacks coordinates: should inherit parent (59.33, 18.06)
        },
        {
          id: 'part_stage_b',
          title: 'Stage B Gig',
          date: '2026-10-30',
          startTime: '18:00',
          endTime: '20:00',
          latitude: 59.35,
          longitude: 18.08,
          // Has own coordinates
        },
      ],
    };

    const projections = buildEventProjections(
      'private_band',
      multiEvent,
      'evt_fest',
      'band_fest',
      'Festival Band',
      refNow
    );

    // Two parts -> two projections. Container event is NOT duplicated as a third pin.
    assert.strictEqual(projections.length, 2);

    const soundcheck = projections.find((p) => p.schedulePartId === 'part_soundcheck');
    const stageB = projections.find((p) => p.schedulePartId === 'part_stage_b');

    assert.ok(soundcheck);
    assert.ok(stageB);

    // Soundcheck inherited parent coordinates
    assert.strictEqual(soundcheck.latitude, 59.33);
    assert.strictEqual(soundcheck.longitude, 18.06);

    // Stage B kept its own coordinates
    assert.strictEqual(stageB.latitude, 59.35);
    assert.strictEqual(stageB.longitude, 18.08);
  });

  it('7. Missing coordinates: omits pin entirely, never Stockholm fallback', () => {
    const refNow = new Date('2026-10-28T12:00:00Z');
    const eventWithoutCoords = {
      title: 'TBD Gig',
      eventType: 'Concert',
      location: 'Unknown Venue',
      startDateTime: '2026-11-01T20:00:00Z',
      endDateTime: '2026-11-01T23:00:00Z',
      // No latitude / longitude
    };

    const projections = buildEventProjections(
      'private_band',
      eventWithoutCoords,
      'evt_no_coords',
      'band_test',
      'Band',
      refNow
    );

    assert.strictEqual(projections.length, 0);
  });

  it('8. Past events: omitted from feed', () => {
    const refNow = new Date('2026-10-28T12:00:00Z');
    const pastEvent = {
      title: 'Past Gig',
      eventType: 'Concert',
      startDateTime: '2026-10-20T20:00:00Z',
      endDateTime: '2026-10-20T23:00:00Z',
      latitude: 59.33,
      longitude: 18.06,
    };

    const projections = buildEventProjections(
      'private_band',
      pastEvent,
      'evt_past',
      'band_test',
      'Band',
      refNow
    );

    assert.strictEqual(projections.length, 0);
  });

  it('9. Locked upcoming events: remain visible on the map', () => {
    const refNow = new Date('2026-10-28T12:00:00Z');
    const lockedEvent = {
      title: 'Finalized Gig',
      eventType: 'Concert',
      startDateTime: '2026-10-30T20:00:00Z',
      endDateTime: '2026-10-30T23:00:00Z',
      latitude: 59.33,
      longitude: 18.06,
      isLocked: true,
      lockedAt: 1793000000000,
    };

    const projections = buildEventProjections(
      'private_band',
      lockedEvent,
      'evt_locked',
      'band_test',
      'Band',
      refNow
    );

    assert.strictEqual(projections.length, 1);
    assert.strictEqual(projections[0].status, 'locked');
  });

  it('10. Public calendar: draft or cancelled events are omitted', () => {
    const refNow = new Date('2026-10-28T12:00:00Z');
    const cancelledPubEvent = {
      title: 'Cancelled Show',
      status: 'cancelled',
      startDateTime: '2026-10-30T20:00:00Z',
      endDateTime: '2026-10-30T23:00:00Z',
      latitude: 59.33,
      longitude: 18.06,
    };

    const draftPubEvent = {
      title: 'Draft Show',
      status: 'draft',
      startDateTime: '2026-10-30T20:00:00Z',
      endDateTime: '2026-10-30T23:00:00Z',
      latitude: 59.33,
      longitude: 18.06,
    };

    assert.strictEqual(
      buildEventProjections('public_calendar', cancelledPubEvent, 'c1', null, '', refNow).length,
      0
    );
    assert.strictEqual(
      buildEventProjections('public_calendar', draftPubEvent, 'd1', null, '', refNow).length,
      0
    );
  });
  describe('calculateReconciliationDiff Tests', () => {
    const refNow = new Date('2026-10-28T12:00:00Z');

    it('1. Schedule part removal: removes deleted part projections and updates index', () => {
      const prevIndex = {
        sourceType: 'private_band',
        bandId: 'band_1',
        eventId: 'evt_1',
        mapItemIds: {
          'event:private:band_1:evt_1:part_soundcheck': true,
          'event:private:band_1:evt_1:part_gig': true,
        },
        authorizedUids: {
          user_alice: true,
          user_bob: true,
        },
      };

      // Part gig removed, only soundcheck remains
      const eventData = {
        title: 'Festival Day',
        latitude: 59.33,
        longitude: 18.06,
        rehearsals: [
          {
            id: 'part_soundcheck',
            type: 'Rehearsal',
            startDateTime: '2026-10-30T14:00:00Z',
            endDateTime: '2026-10-30T15:00:00Z',
          },
        ],
      };

      const bandData = {
        Members_band: { user_alice: true, user_bob: true },
      };

      const { updates, desiredMapItemIds } = calculateReconciliationDiff({
        source: 'private_band',
        eventId: 'evt_1',
        bandId: 'band_1',
        bandName: 'The Band',
        bandData,
        eventData,
        prevIndex,
        now: refNow,
      });

      // Assert part_gig is removed for both users
      assert.strictEqual(updates['/userMapEventFeed/user_alice/event:private:band_1:evt_1:part_gig'], null);
      assert.strictEqual(updates['/userMapEventFeed/user_bob/event:private:band_1:evt_1:part_gig'], null);

      // Assert part_soundcheck is retained/written
      assert.ok(updates['/userMapEventFeed/user_alice/event:private:band_1:evt_1:part_soundcheck']);
      assert.ok(updates['/userMapEventFeed/user_bob/event:private:band_1:evt_1:part_soundcheck']);

      // Assert index only contains remaining part
      assert.deepStrictEqual(desiredMapItemIds, ['event:private:band_1:evt_1:part_soundcheck']);
      const updatedIndex = updates['/mapEventProjectionIndex/band:band_1:evt_1'];
      assert.ok(updatedIndex);
      assert.strictEqual(updatedIndex.mapItemIds['event:private:band_1:evt_1:part_soundcheck'], true);
      assert.strictEqual(updatedIndex.mapItemIds['event:private:band_1:evt_1:part_gig'], undefined);
    });

    it('2. Public -> Private transition: removes public projection and cleans index', () => {
      const prevPublicIndex = {
        sourceType: 'public_calendar',
        eventId: 'evt_switch',
        mapItemIds: {
          'event:public:evt_switch': true,
        },
        authorizedUids: {
          public: true,
        },
      };

      // Event is now private, not public
      const { updates } = calculateReconciliationDiff({
        source: 'public_calendar',
        eventId: 'evt_switch',
        bandId: null,
        bandName: '',
        bandData: null,
        eventData: null, // deleted from public
        prevIndex: prevPublicIndex,
        now: refNow,
      });

      assert.strictEqual(updates['/publicMapEventFeed/event:public:evt_switch'], null);
      assert.strictEqual(updates['/mapEventProjectionIndex/public:evt_switch'], null);
    });

    it('3. Private -> Public transition: removes private projections and writes public projection', () => {
      const prevPrivateIndex = {
        sourceType: 'private_band',
        bandId: 'band_1',
        eventId: 'evt_to_pub',
        mapItemIds: {
          'event:private:band_1:evt_to_pub': true,
        },
        authorizedUids: {
          user_alice: true,
        },
      };

      // Deleted from private
      const privateCleanup = calculateReconciliationDiff({
        source: 'private_band',
        eventId: 'evt_to_pub',
        bandId: 'band_1',
        bandName: 'Band',
        bandData: { Members_band: {} },
        eventData: null,
        prevIndex: prevPrivateIndex,
        now: refNow,
      });

      assert.strictEqual(privateCleanup.updates['/userMapEventFeed/user_alice/event:private:band_1:evt_to_pub'], null);
      assert.strictEqual(privateCleanup.updates['/mapEventProjectionIndex/band:band_1:evt_to_pub'], null);

      // Now written as public
      const publicWrite = calculateReconciliationDiff({
        source: 'public_calendar',
        eventId: 'evt_to_pub',
        bandId: null,
        bandName: 'Organizer',
        bandData: null,
        eventData: {
          title: 'Public Show',
          eventType: 'liveGig',
          status: 'published',
          startDateTime: '2026-10-31T20:00:00Z',
          endDateTime: '2026-10-31T23:00:00Z',
          latitude: 59.33,
          longitude: 18.06,
        },
        prevIndex: null,
        now: refNow,
      });

      assert.ok(publicWrite.updates['/publicMapEventFeed/event:public:evt_to_pub']);
      assert.ok(publicWrite.updates['/mapEventProjectionIndex/public:evt_to_pub']);
    });

    it('4. Event deletion: removes all projections and clears index', () => {
      const prevIndex = {
        sourceType: 'private_band',
        bandId: 'band_1',
        eventId: 'evt_del',
        mapItemIds: {
          'event:private:band_1:evt_del': true,
        },
        authorizedUids: {
          user_alice: true,
          user_bob: true,
        },
      };

      const { updates } = calculateReconciliationDiff({
        source: 'private_band',
        eventId: 'evt_del',
        bandId: 'band_1',
        bandName: 'Band',
        bandData: { Members_band: {} },
        eventData: null,
        prevIndex,
        now: refNow,
      });

      assert.strictEqual(updates['/userMapEventFeed/user_alice/event:private:band_1:evt_del'], null);
      assert.strictEqual(updates['/userMapEventFeed/user_bob/event:private:band_1:evt_del'], null);
      assert.strictEqual(updates['/mapEventProjectionIndex/band:band_1:evt_del'], null);
    });

    it('5. Audience removal: excluded member loses projection, remaining member keeps it', () => {
      const prevIndex = {
        sourceType: 'private_band',
        bandId: 'band_1',
        eventId: 'evt_excl',
        mapItemIds: {
          'event:private:band_1:evt_excl': true,
        },
        authorizedUids: {
          user_alice: true,
          user_bob: true,
        },
      };

      // user_bob is added to excludedMemberIds
      const eventData = {
        title: 'Secret Gig',
        eventType: 'Concert',
        startDateTime: '2026-10-30T20:00:00Z',
        endDateTime: '2026-10-30T23:00:00Z',
        latitude: 59.33,
        longitude: 18.06,
        excludedMemberIds: ['user_bob'],
      };

      const bandData = {
        Members_band: { user_alice: true, user_bob: true },
      };

      const { updates } = calculateReconciliationDiff({
        source: 'private_band',
        eventId: 'evt_excl',
        bandId: 'band_1',
        bandName: 'Band',
        bandData,
        eventData,
        prevIndex,
        now: refNow,
      });

      // user_bob lost authorization
      assert.strictEqual(updates['/userMapEventFeed/user_bob/event:private:band_1:evt_excl'], null);
      // user_alice retained authorization
      assert.ok(updates['/userMapEventFeed/user_alice/event:private:band_1:evt_excl']);
    });

    it('6. Event cancellation: status cancelled removes projections', () => {
      const prevIndex = {
        sourceType: 'private_band',
        bandId: 'band_1',
        eventId: 'evt_canc',
        mapItemIds: {
          'event:private:band_1:evt_canc': true,
        },
        authorizedUids: {
          user_alice: true,
        },
      };

      const eventData = {
        title: 'Cancelled Gig',
        status: 'cancelled',
        startDateTime: '2026-10-30T20:00:00Z',
        endDateTime: '2026-10-30T23:00:00Z',
        latitude: 59.33,
        longitude: 18.06,
      };

      const { updates } = calculateReconciliationDiff({
        source: 'private_band',
        eventId: 'evt_canc',
        bandId: 'band_1',
        bandName: 'Band',
        bandData: { Members_band: { user_alice: true } },
        eventData,
        prevIndex,
        now: refNow,
      });

      assert.strictEqual(updates['/userMapEventFeed/user_alice/event:private:band_1:evt_canc'], null);
      assert.strictEqual(updates['/mapEventProjectionIndex/band:band_1:evt_canc'], null);
    });

    it('7. Coordinates removed: invalid coordinates cleans up projections', () => {
      const prevIndex = {
        sourceType: 'private_band',
        bandId: 'band_1',
        eventId: 'evt_no_coord',
        mapItemIds: {
          'event:private:band_1:evt_no_coord': true,
        },
        authorizedUids: {
          user_alice: true,
        },
      };

      const eventData = {
        title: 'Gig Without Coords',
        startDateTime: '2026-10-30T20:00:00Z',
        endDateTime: '2026-10-30T23:00:00Z',
        latitude: null,
        longitude: null,
      };

      const { updates } = calculateReconciliationDiff({
        source: 'private_band',
        eventId: 'evt_no_coord',
        bandId: 'band_1',
        bandName: 'Band',
        bandData: { Members_band: { user_alice: true } },
        eventData,
        prevIndex,
        now: refNow,
      });

      assert.strictEqual(updates['/userMapEventFeed/user_alice/event:private:band_1:evt_no_coord'], null);
      assert.strictEqual(updates['/mapEventProjectionIndex/band:band_1:evt_no_coord'], null);
    });

    it('8. Retry idempotency: executing same state twice produces identical desired writes', () => {
      const prevIndex = null;
      const eventData = {
        title: 'Upcoming Gig',
        eventType: 'Concert',
        startDateTime: '2026-10-30T20:00:00Z',
        endDateTime: '2026-10-30T23:00:00Z',
        latitude: 59.33,
        longitude: 18.06,
      };
      const bandData = { Members_band: { user_alice: true } };

      const run1 = calculateReconciliationDiff({
        source: 'private_band',
        eventId: 'evt_idem',
        bandId: 'band_1',
        bandName: 'Band',
        bandData,
        eventData,
        prevIndex,
        now: refNow,
      });

      // Second run receives run1 index as prevIndex
      const run2Index = run1.updates['/mapEventProjectionIndex/band:band_1:evt_idem'];
      const run2 = calculateReconciliationDiff({
        source: 'private_band',
        eventId: 'evt_idem',
        bandId: 'band_1',
        bandName: 'Band',
        bandData,
        eventData,
        prevIndex: run2Index,
        now: refNow,
      });

      // Projections written in run2 should match run1
      assert.deepStrictEqual(
        run2.updates['/userMapEventFeed/user_alice/event:private:band_1:evt_idem'].mapItemId,
        run1.updates['/userMapEventFeed/user_alice/event:private:band_1:evt_idem'].mapItemId
      );
      // No deletions should be produced
      assert.strictEqual(run2.updates['/userMapEventFeed/user_alice/event:private:band_1:evt_idem:stale'], undefined);
    });
  });
});