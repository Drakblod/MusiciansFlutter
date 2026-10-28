const assert = require('assert');
const {
  isValidCoordinate,
  buildMapItemId,
  buildEventProjections,
  getAuthorizedUserIdsForBandEvent,
  isEventPast,
} = require('../event_projection');

describe('EVENT-MAP-FEED-INTEGRATION-TESTS', () => {
  const refNow = new Date('2026-10-28T12:00:00Z');

  // Test 1 & 2: Public calendar events
  it('1. Published public Event produces projection for publicMapEventFeed', () => {
    const pubEvent = {
      title: 'Stockholm Jazz Festival',
      organizerName: 'Jazz Sthlm',
      status: 'published',
      eventType: 'liveGig',
      startDateTime: '2026-10-30T19:00:00Z',
      endDateTime: '2026-10-30T22:00:00Z',
      latitude: 59.3293,
      longitude: 18.0686,
      venueName: 'Fasching',
      city: 'Stockholm',
    };

    const projections = buildEventProjections('public_calendar', pubEvent, 'pub_1', null, 'Jazz Sthlm', refNow);
    assert.strictEqual(projections.length, 1);
    assert.strictEqual(projections[0].mapItemId, 'event:public:pub_1');
    assert.strictEqual(projections[0].visibility, 'public');
    assert.strictEqual(projections[0].latitude, 59.3293);
    assert.strictEqual(projections[0].longitude, 18.0686);
  });

  it('2. Draft/private/cancelled/deleted public Event does not appear publicly', () => {
    const cancelled = {
      title: 'Cancelled Show',
      status: 'cancelled',
      startDateTime: '2026-10-30T19:00:00Z',
      endDateTime: '2026-10-30T22:00:00Z',
      latitude: 59.3293,
      longitude: 18.0686,
    };
    const draft = {
      title: 'Draft Show',
      status: 'draft',
      startDateTime: '2026-10-30T19:00:00Z',
      endDateTime: '2026-10-30T22:00:00Z',
      latitude: 59.3293,
      longitude: 18.0686,
    };

    assert.strictEqual(buildEventProjections('public_calendar', cancelled, 'c1', null, '', refNow).length, 0);
    assert.strictEqual(buildEventProjections('public_calendar', draft, 'd1', null, '', refNow).length, 0);
  });

  // Test 3: Private Band Event never appears publicly
  it('3. Private Band Event never appears publicly', () => {
    const bandEvent = {
      title: 'Band Rehearsal',
      eventType: 'Rehearsal',
      startDateTime: '2026-10-30T18:00:00Z',
      endDateTime: '2026-10-30T21:00:00Z',
      latitude: 59.33,
      longitude: 18.06,
    };

    const projections = buildEventProjections('private_band', bandEvent, 'evt_1', 'band_1', 'The Band', refNow);
    assert.strictEqual(projections.length, 1);
    assert.strictEqual(projections[0].visibility, 'private');
    assert.ok(projections[0].mapItemId.startsWith('event:private:band_1:'));
  });

  // Test 4 & 5: Authorized vs Unrelated
  it('4 & 5. Authorized band member sees private Event; unrelated user excluded', () => {
    const bandData = {
      Members_band: {
        member_alice: { Role: 'Leader' },
        member_bob: { Role: 'Member' },
      },
    };
    const eventData = {
      createdBy: 'member_alice',
      startDateTime: '2026-10-30T18:00:00Z',
      endDateTime: '2026-10-30T21:00:00Z',
      latitude: 59.33,
      longitude: 18.06,
    };

    const authorized = getAuthorizedUserIdsForBandEvent(bandData, eventData);
    assert.ok(authorized.includes('member_alice'));
    assert.ok(authorized.includes('member_bob'));
    assert.strictEqual(authorized.includes('unrelated_charlie'), false);
  });

  // Test 6: Removed band member loses private Event projection
  it('6. Excluded or removed member loses authorization', () => {
    const bandData = {
      Members_band: {
        member_alice: { Role: 'Leader' },
      },
    };
    const eventData = {
      createdBy: 'member_alice',
      excludedMemberIds: ['member_bob'],
    };

    const authorized = getAuthorizedUserIdsForBandEvent(bandData, eventData);
    assert.ok(authorized.includes('member_alice'));
    assert.strictEqual(authorized.includes('member_bob'), false);
  });

  // Test 7, 8, 9, 10, 11: Single vs Multi-part mapping
  it('7 & 11. Single Event creates one deterministic marker; container not duplicated with parts', () => {
    const single = {
      title: 'Solo Show',
      eventType: 'Concert',
      startDateTime: '2026-10-30T20:00:00Z',
      endDateTime: '2026-10-30T23:00:00Z',
      latitude: 59.33,
      longitude: 18.06,
    };

    const projections = buildEventProjections('private_band', single, 'single_evt', 'band_1', 'Band', refNow);
    assert.strictEqual(projections.length, 1);
    assert.strictEqual(projections[0].mapItemId, 'event:private:band_1:single_evt');
    assert.strictEqual(projections[0].schedulePartId, null);
  });

  it('8 & 9 & 10. Multi-part Event creates correct deterministic markers for parts', () => {
    const multi = {
      title: 'Two Venue Tour',
      eventType: 'Tour',
      rehearsals: [
        {
          id: 'venue_1',
          title: 'Stockholm Club',
          date: '2026-10-29',
          startTime: '19:00',
          endTime: '21:00',
          latitude: 59.33,
          longitude: 18.06,
        },
        {
          id: 'venue_2',
          title: 'Uppsala Hall',
          date: '2026-10-30',
          startTime: '19:00',
          endTime: '21:00',
          latitude: 59.85,
          longitude: 17.63,
        },
      ],
    };

    const projections = buildEventProjections('private_band', multi, 'tour_evt', 'band_1', 'Band', refNow);
    assert.strictEqual(projections.length, 2);
    assert.strictEqual(projections[0].mapItemId, 'event:private:band_1:tour_evt:venue_1');
    assert.strictEqual(projections[1].mapItemId, 'event:private:band_1:tour_evt:venue_2');
    assert.strictEqual(projections[0].latitude, 59.33);
    assert.strictEqual(projections[1].latitude, 59.85);

    // If venue_2 is removed
    const removedPart = {
      ...multi,
      rehearsals: [multi.rehearsals[0]],
    };
    const updatedProjections = buildEventProjections('private_band', removedPart, 'tour_evt', 'band_1', 'Band', refNow);
    assert.strictEqual(updatedProjections.length, 1);
    assert.strictEqual(updatedProjections[0].mapItemId, 'event:private:band_1:tour_evt:venue_1');
  });

  // Test 12, 13, 14: Coordinates resolution
  it('12. Missing coordinates create NO fallback marker (Stockholm / 0,0 rejected)', () => {
    const missing = {
      title: 'TBD Event',
      startDateTime: '2026-10-30T19:00:00Z',
      endDateTime: '2026-10-30T22:00:00Z',
    };
    assert.strictEqual(buildEventProjections('private_band', missing, 'm1', 'b1', 'Band', refNow).length, 0);

    const nullIsland = {
      ...missing,
      latitude: 0,
      longitude: 0,
    };
    assert.strictEqual(buildEventProjections('private_band', nullIsland, 'm2', 'b1', 'Band', refNow).length, 0);
  });

  it('13 & 14. Part inherits parent coordinates; unrelated parts never inherit each other', () => {
    const eventWithParentCoords = {
      title: 'Band Rehearsal Day',
      latitude: 59.33,
      longitude: 18.06,
      rehearsals: [
        {
          id: 'p1',
          date: '2026-10-29',
          startTime: '10:00',
          endTime: '12:00',
          // Lacks coordinates -> inherits parent (59.33, 18.06)
        },
      ],
    };
    const p1Proj = buildEventProjections('private_band', eventWithParentCoords, 'e1', 'b1', 'Band', refNow);
    assert.strictEqual(p1Proj.length, 1);
    assert.strictEqual(p1Proj[0].latitude, 59.33);
    assert.strictEqual(p1Proj[0].longitude, 18.06);

    const eventWithoutParentCoords = {
      title: 'No Parent Coords',
      // No parent latitude/longitude
      rehearsals: [
        {
          id: 'part_with_coords',
          date: '2026-10-29',
          startTime: '10:00',
          endTime: '12:00',
          latitude: 57.70,
          longitude: 11.97,
        },
        {
          id: 'part_without_coords',
          date: '2026-10-30',
          startTime: '10:00',
          endTime: '12:00',
          // Must NOT inherit from part_with_coords!
        },
      ],
    };
    const projections = buildEventProjections('private_band', eventWithoutParentCoords, 'e2', 'b1', 'Band', refNow);
    assert.strictEqual(projections.length, 1);
    assert.strictEqual(projections[0].schedulePartId, 'part_with_coords');
  });

  // Test 18 & 19: Lifecycle & Past & Locked
  it('18. Past Event disappears', () => {
    const past = {
      title: 'Old Gig',
      startDateTime: '2026-10-20T20:00:00Z',
      endDateTime: '2026-10-20T23:00:00Z',
      latitude: 59.33,
      longitude: 18.06,
    };
    assert.strictEqual(buildEventProjections('private_band', past, 'old_1', 'b1', 'Band', refNow).length, 0);
  });

  it('19. Locked/finalized upcoming Event remains visible', () => {
    const locked = {
      title: 'Locked Upcoming Gig',
      startDateTime: '2026-10-30T20:00:00Z',
      endDateTime: '2026-10-30T23:00:00Z',
      latitude: 59.33,
      longitude: 18.06,
      isLocked: true,
      lockedAt: 1793000000000,
      lockedBy: 'admin_user',
    };
    const proj = buildEventProjections('private_band', locked, 'l_1', 'b1', 'Band', refNow);
    assert.strictEqual(proj.length, 1);
    assert.strictEqual(proj[0].status, 'locked');
  });

  // Test 26: Sensitive fields projection allowlist
  it('26. Projection contains no sensitive RSVP/member/contact/token fields', () => {
    const sensitiveEvent = {
      title: 'Concert',
      description: 'Public description',
      startDateTime: '2026-10-30T20:00:00Z',
      endDateTime: '2026-10-30T23:00:00Z',
      latitude: 59.33,
      longitude: 18.06,
      Responses: { u1: { status: 'YES', comment: 'private' } },
      ScheduleResponses: { s1: { u1: { status: 'NO' } } },
      externalInvitees: { guest: { email: 'guest@band.se', phone: '0701234567' } },
      substituteAssignments: { sub1: { assignedUserId: 'u2', internalRate: 5000 } },
      pushToken: 'fcm_xyz',
      chatId: 'room_123',
    };

    const proj = buildEventProjections('private_band', sensitiveEvent, 'sens_1', 'b1', 'Band', refNow)[0];
    const keys = Object.keys(proj);

    assert.strictEqual(keys.includes('Responses'), false);
    assert.strictEqual(keys.includes('ScheduleResponses'), false);
    assert.strictEqual(keys.includes('externalInvitees'), false);
    assert.strictEqual(keys.includes('substituteAssignments'), false);
    assert.strictEqual(keys.includes('pushToken'), false);
    assert.strictEqual(keys.includes('chatId'), false);
    assert.strictEqual(keys.includes('email'), false);
    assert.strictEqual(keys.includes('phone'), false);
  });
});
