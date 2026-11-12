'use strict';

const assert = require('node:assert/strict');
const { createHash, randomBytes } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInAnonymously } = require('firebase/auth');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');
const delivery = require('../notification_delivery');

const project = 'demo-musicians-test';
const legacyReminder = { notification: { sound: 'reminder_rsvp', channelId: 'rsvp_reminder_channel' } };
const notFound = error => error.code === 'functions/not-found';
const get = async (db, path) => (await db.ref(path).get()).val();
const idFor = (uid, type, key) => createHash('sha256')
  .update(JSON.stringify([uid, type, key])).digest('hex');

describe('Native notification payloads and sound resources', () => {
  const root = path.join(__dirname, '../..');
  const read = name => fs.readFileSync(path.join(root, name));
  const native = read('android/app/src/main/kotlin/com/musiciansonly/musicians_flutter/MainActivity.kt').toString();
  const ios = read('ios/Runner.xcodeproj/project.pbxproj').toString();
  const mappings = [
    ['gig_request', 'gig_request_channel', ['sub_request_invite', 'grouped_sub_request']],
    ['gig_response', 'gig_response_channel', ['sub_request_response', 'session_application', 'session_application_status']],
    ['event_rsvp', 'rsvp_reminder_channel', ['event_invite', 'event_reminder', 'event_threshold', 'event_ready_to_finalize']],
    ['gig_confirmed', 'finalized_gig_channel', ['gig_finalized']],
  ];
  it('uses fixed activity titles and includes only opaque routing data', () => {
    const titles = [
      ['sub_request_invite', 'Substitute Request'],
      ['grouped_sub_request', 'Substitute Request'],
      ['sub_request_response', 'Substitute Request Response'],
      ['event_invite', 'Event Request'],
      ['event_reminder', 'Event Request'],
      ['event_ready_to_finalize', 'Event Ready to Finalize'],
      ['gig_finalized', 'Gig Confirmed'],
      ['session_application', 'Collab Application'],
      ['session_application_status', 'Collab Application Update'],
      ['band_section_chat', 'New Band Message'],
      ...['system', 'sound_test', 'event_threshold', 'unknown', '__proto__']
        .map(type => [type, 'New activity in Musicians']),
    ];
    const recipient = {
      token: 'device-token', userId: 'private-user-id', soundProfile: 'ios-v2',
      bandId: 'private-band-id', name: 'private name', date: 'private date',
      description: 'private description', response: 'private response',
    };
    for (const [type, title] of titles) {
      const payload = delivery.messageFor(recipient, 'opaque-id', type);
      assert.deepEqual(payload.notification, { title, body: 'Open the app to view details.' });
      assert.deepEqual(payload.data, { schemaVersion: '2', notificationId: 'opaque-id', type });
      assert.deepEqual(Object.keys(payload).sort(), ['android', 'apns', 'data', 'notification', 'token']);
      assert.doesNotMatch(JSON.stringify(payload), /private/);
    }
  });
  for (const [name, channel, types] of mappings) {
    it(`packages and maps ${name} on both native platforms and the tester`, () => {
      const stem = `notification_${name}_v2`;
      const file = `${stem}.wav`;
      const android = read(`android/app/src/main/res/raw/${file}`);
      assert.equal(android.toString('ascii', 0, 4), 'RIFF');
      assert.equal(android.toString('ascii', 8, 12), 'WAVE');
      assert.equal(android.readUInt16LE(20), 1);
      assert.equal(android.readUInt16LE(22), 1);
      assert.equal(android.readUInt32LE(24), 44100);
      assert.equal(android.readUInt16LE(34), 16);
      assert.deepEqual(read(`ios/Runner/${file}`), android);
      assert.deepEqual(read(`assets/audio/${file}`), android);
      assert.ok(native.includes(`Triple("${channel}_v2",`));
      assert.ok(native.includes(`"${stem}"`));
      assert.equal(ios.split('\n').filter(line =>
        line.trim().endsWith(`/* ${file} in Resources */,`)).length, 1);
      for (const type of types) {
        assert.deepEqual(delivery.messageFor({ soundProfile: 'android-v2' }, 'id', type).android.notification,
          { sound: stem, channelId: `${channel}_v2` });
        assert.equal(delivery.messageFor({ soundProfile: 'ios-v2' }, 'id', type).apns.payload.aps.sound, file);
      }
    });
  }

  it('uses the system sound for unknown mappings and never forwards supplied filenames or channels', () => {
    assert.ok(native.includes('Triple("chat_notifications_v2", "Band Section Messages", null)'));
    assert.ok(native.includes('RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)'));
    assert.ok(native.includes('"event_notifications"'));
    assert.doesNotMatch(read('android/app/src/main/AndroidManifest.xml').toString(),
      /com\.google\.firebase\.messaging\.default_notification_channel_id/);
    const payload = delivery.messageFor({
      soundProfile: 'android-v2', android: { notification: { sound: 'guitarsound', channelId: 'event_notifications' } },
    }, 'id', 'sound_test', 'unapproved.wav');
    assert.deepEqual(payload.android.notification, { sound: 'default', channelId: 'chat_notifications_v2' });
    assert.equal(payload.apns.payload.aps.sound, 'default');
    assert.equal(delivery.testSoundPlatform('reminder_72h', 'android-v2').sound, 'notification_event_rsvp_v2');
    assert.equal(delivery.testSoundPlatform('constructor', 'android-v2'), null);
  });
});

async function waitForRow(db, uid, id, write) {
  const ref = db.ref(`notificationFeedV2/${uid}/${id}`);
  let listener;
  try {
    const arrived = new Promise((resolve, reject) => {
      listener = ref.on('value', snap => { if (snap.exists()) resolve(snap.val()); }, reject);
    });
    await write();
    return await arrived;
  } finally {
    ref.off('value', listener);
  }
}

async function waitForRoute(db, uid, predicate, write) {
  const ref = db.ref(`notificationRoutesV2/${uid}`);
  let listener;
  try {
    const arrived = new Promise((resolve, reject) => {
      listener = ref.on('value', snap => {
        const match = Object.entries(snap.val() || {}).find(([, route]) => predicate(route));
        if (match) resolve(match[0]);
      }, reject);
    });
    await write();
    return await arrived;
  } finally {
    ref.off('value', listener);
  }
}

for (const rules of ['database.rules.json', 'database.transitional.rules.json']) {
  describe(`Notification ownership and routing — ${rules}`, function () {
    this.timeout(90_000);
    let adminApp, db, env, a, b, outsider, suffix;
    const clients = [];

    async function client() {
      const app = initializeApp({ projectId: project, apiKey: 'emulator-only' }, randomBytes(8).toString('hex'));
      clients.push(app);
      const auth = getAuth(app);
      connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
      const { user } = await signInAnonymously(auth);
      const functions = getFunctions(app, 'europe-west1');
      connectFunctionsEmulator(functions, '127.0.0.1', 5001);
      return {
        uid: user.uid,
        call: async (name, data = {}) => (await httpsCallable(functions, name)({
          accountUid: user.uid, ...data,
        })).data,
        rulesDb: env.authenticatedContext(user.uid).database(),
      };
    }

    before(async () => {
      assert.equal(globalThis.__EMULATOR_ISOLATION_GUARD_ACTIVE__, true);
      assert.equal(process.env.GCLOUD_PROJECT, project);
      suffix = randomBytes(5).toString('hex');
      adminApp = admin.initializeApp({
        projectId: project, databaseURL: `http://127.0.0.1:9000?ns=${project}`,
      }, `notifications_${suffix}`);
      db = adminApp.database();
      env = await initializeTestEnvironment({
        projectId: project, database: {
          host: '127.0.0.1', port: 9000,
          rules: fs.readFileSync(path.join(__dirname, '../..', rules), 'utf8'),
        },
      });
      [a, b, outsider] = await Promise.all([client(), client(), client()]);
    });

    after(async () => {
      await Promise.all(clients.map(deleteApp));
      await env?.cleanup();
      await adminApp?.delete();
    });

    it('atomically transfers one installation without logout and rejects stale operations', async () => {
      const installation = randomBytes(16).toString('hex');
      const proof = randomBytes(32).toString('hex');
      const token = randomBytes(32).toString('base64url');
      const reg = { installation, proof, token, sequence: 1 };
      await a.call('registerNotificationInstallation', reg);
      await a.call('registerNotificationInstallation', reg);
      await assert.rejects(() => b.call('registerNotificationInstallation', {
        ...reg, accountUid: a.uid,
      }), error => error.code === 'functions/permission-denied');
      const [old] = await delivery.recipients(db, [a.uid]);
      assert.ok(old);
      await assert.rejects(() => outsider.call('registerNotificationInstallation', {
        ...reg, installation: randomBytes(16).toString('hex'),
      }), error => error.code === 'functions/failed-precondition');
      await b.call('registerNotificationInstallation', { ...reg, sequence: 2 });
      await assert.rejects(() => a.call('registerNotificationInstallation', reg),
        error => error.code === 'functions/failed-precondition');
      assert.equal((await a.call('unregisterNotificationInstallation', { installation, proof, sequence: 3 })).success, false);
      assert.deepEqual(await delivery.recipients(db, [a.uid]), []);
      const [owner] = await delivery.recipients(db, [b.uid]);
      assert.equal(owner.installation, installation);
      const sent = [];
      const messaging = { send: async payload => { sent.push(payload); return 'accepted'; } };
      assert.deepEqual(await delivery.deliver(db, messaging, old, 'old-id', 'event_invite'),
        { success: false, superseded: true });
      assert.equal(sent.length, 0);
      const next = randomBytes(32).toString('base64url');
      await b.call('registerNotificationInstallation', { ...reg, sequence: 4, token: next });
      assert.equal(await delivery.stillCurrent(db, owner), false);
      await delivery.removeInvalid(db, owner, { code: 'messaging/registration-token-not-registered' });
      assert.equal((await delivery.recipients(db, [b.uid]))[0].token === next, true);
      const remove = { installation, proof, sequence: 5 };
      await b.call('unregisterNotificationInstallation', remove);
      assert.equal((await b.call('unregisterNotificationInstallation', remove)).success, true);
      assert.deepEqual(await delivery.recipients(db, [b.uid]), []);
    });

    it('revokes account bindings and feed on deletion without invalidating transferred generations', async () => {
      const subject = await client();
      const successor = await client();
      const binding = () => ({
        installation: randomBytes(16).toString('hex'),
        proof: randomBytes(32).toString('hex'),
        token: randomBytes(32).toString('base64url'),
        sequence: 1,
      });
      const [sameInstallation, newInstallation, transferred] = Array.from({ length: 3 }, binding);
      for (const row of [sameInstallation, newInstallation, transferred]) {
        await subject.call('registerNotificationInstallation', row);
      }
      await successor.call('registerNotificationInstallation', { ...transferred, sequence: 2 });
      const oldRecipients = await delivery.recipients(db, [subject.uid]);
      assert.equal(oldRecipients.length, 2);
      const registry = 'notificationTokenRegistry';
      const tokenKey = token => createHash('sha256').update(token).digest('hex');
      const legacy = `userNotifications/${subject.uid}/historical`;
      const feedPaths = ['notificationFeedV2', 'notificationRoutesV2', 'notificationFeedSignals'];
      await db.ref().update({
        [`${feedPaths[0]}/${subject.uid}/row`]: { type: 'event_invite' },
        [`${feedPaths[1]}/${subject.uid}/row`]: { type: 'event_invite' },
        [`${feedPaths[2]}/${subject.uid}`]: 'row',
        [legacy]: { type: 'event_invite' },
      });
      let sendStarted, finishSend;
      const started = new Promise(resolve => { sendStarted = resolve; });
      const hold = new Promise(resolve => { finishSend = resolve; });
      const inFlight = delivery.publish(db, {
        send: async () => {
          sendStarted();
          await hold;
          return 'accepted-before-revocation';
        },
      }, subject.uid, 'event_invite', 'in-flight-deletion', {});
      try {
        await Promise.race([started, inFlight.then(() => assert.fail('delivery did not reach provider'))]);
        // Hold an actual restricted writer across deletion. Each late write
        // must fail at the emulator, even if the sender never cleans up.
        await delivery.withNotificationWriter(db, subject.uid, async writer => {
          const signal = writer.ref(`${feedPaths[2]}/${subject.uid}`);
          assert.equal((await signal.get()).exists(), true);
          assert.deepEqual(await subject.call('deleteUserAccount'), { success: true });
          for (const path of feedPaths) {
            const late = writer.ref(`${path}/${subject.uid}`);
            await assert.rejects(late.set('late'), /permission.denied/i);
          }
          const claim = writer.ref(`${feedPaths[1]}/${subject.uid}/late`);
          await assert.rejects(claim.transaction(() => ({ type: 'event_invite' })), /permission.denied/i);
        });
      } finally {
        finishSend();
        await inFlight;
      }
      await assert.rejects(adminApp.auth().getUser(subject.uid), e => e.code === 'auth/user-not-found');
      for (const tree of feedPaths) assert.equal(await get(db, `${tree}/${subject.uid}`), null);
      assert.deepEqual(await get(db, legacy), { type: 'event_invite' });
      assert.equal(await get(db, `${registry}/owners/${subject.uid}`), null);
      for (const row of [sameInstallation, newInstallation]) {
        const fence = await get(db, `${registry}/installations/${row.installation}`);
        assert.deepEqual(fence, { proofHash: tokenKey(row.proof), sequence: 1 });
        assert.equal(await get(db, `${registry}/tokens/${tokenKey(row.token)}`), null);
      }
      // Broadcast uses this same enumeration. No provider call should be
      // attempted even by a sender that had already obtained the old binding.
      assert.ok((await delivery.recipients(db)).every(row => row.userId !== subject.uid));
      for (const old of oldRecipients) {
        const messaging = { send: () => assert.fail('stale installation was sent a notification') };
        assert.deepEqual(await delivery.deliver(db, messaging, old, 'stale', 'event_invite'),
          { success: false, superseded: true });
      }
      await assert.rejects(successor.call('registerNotificationInstallation', sameInstallation),
        e => e.code === 'functions/failed-precondition');
      const adopted = { ...binding(), token: newInstallation.token };
      await successor.call('registerNotificationInstallation', { ...sameInstallation, sequence: 2 });
      await successor.call('registerNotificationInstallation', adopted);
      // Exercise a retry at the registry boundary after Auth is already gone,
      // and stale in-flight requests that had authenticated before deletion.
      await delivery.revokeAccount(db, subject.uid);
      for (const row of [sameInstallation, newInstallation, transferred, binding()]) {
        const stale = { ...row, accountUid: subject.uid, sequence: 99 };
        await assert.rejects(delivery.changeBinding(db, subject.uid, stale),
          e => e.code === 'failed-precondition');
        assert.deepEqual(await delivery.changeBinding(db, subject.uid, stale, true), { success: false });
      }
      for (const old of oldRecipients) {
        await delivery.removeInvalid(db, old, { code: 'messaging/registration-token-not-registered' });
      }
      const broadcast = await delivery.recipients(db);
      for (const row of [sameInstallation, adopted, transferred]) {
        assert.ok(broadcast.some(dest => dest.userId === successor.uid &&
          dest.installation === row.installation && dest.token === row.token));
        assert.equal(await get(db, `${registry}/tokens/${tokenKey(row.token)}`), row.installation);
      }
      assert.deepEqual(await delivery.recipients(db, [subject.uid]), []);
      assert.equal(await delivery.publish(db, {}, subject.uid, 'event_invite', 'after-deletion', {}), null);
      for (const tree of feedPaths) assert.equal(await get(db, `${tree}/${subject.uid}`), null);
      for (const row of [sameInstallation, adopted, transferred]) {
        await successor.call('unregisterNotificationInstallation', { ...row, sequence: 3 });
      }
    });

    it('claims ready Events once per canonical RSVP audience and rechecks exact-band manager authority', async () => {
      const band = 'ready_' + suffix;
      const event = 'rsvp_ready';
      const [leader, member, guest, former] = await Promise.all([client(), client(), client(), client()]);
      const [adminMember, held] = await Promise.all([client(), client()]);
      const bandPath = `Bands/${band}`;
      const eventPath = `${bandPath}/Events/${event}`;
      const when = new Date(Date.now() + 86400000).toISOString();
      const rsvp = status => ({ status, timestamp: new Date().toISOString(), comment: 'Private response' });
      await db.ref(bandPath).set({
        Name: 'Ready Band',
        Members_band: {
          [leader.uid]: { Role: 'Leader', Status: 'active' },
          [adminMember.uid]: { Role: 'Admin', Status: 'active' },
          [member.uid]: { Role: 'Member', Status: 'active' },
          [former.uid]: { Role: 'Leader', Status: 'removed' },
          [held.uid]: { Role: 'Member', Status: 'on_hold' },
        },
        Events: { [event]: {
          title: 'Private title', description: 'Private description', eventType: 'Concert',
          startDateTime: when, endDateTime: when, requireResponse: true, createdBy: former.uid,
          excludedMemberIds: [adminMember.uid],
          externalInvitees: { [guest.uid]: { source: 'manual', status: 'pending' } },
        } },
      });
      const readyRoute = row => row.type === 'event_ready_to_finalize' && row.eventId === event;
      const routePath = uid => `notificationRoutesV2/${uid}`;
      const readyRows = async uid => Object.entries(await get(db, routePath(uid)) || {})
        .filter(([, row]) => readyRoute(row));
      const readiness = require('../event_readiness');
      const fakePublish = () => assert.fail('an invalid or missing RSVP must block the readiness claim');

      await leader.rulesDb.ref(`${eventPath}/Responses/${leader.uid}`).set(rsvp('Yes'));
      const invalid = rsvp('invalid');
      const no = rsvp('No');
      await db.ref(`${eventPath}/Responses/${member.uid}`).set(invalid);
      await readiness.notifyResponseChange(db, band, event, member.uid, null, invalid, fakePublish);
      await member.rulesDb.ref(`${eventPath}/Responses/${member.uid}`).set(no);
      await readiness.notifyResponseChange(db, band, event, member.uid, invalid, no, fakePublish);
      assert.deepEqual(await readyRows(leader.uid), []);

      const pendingEvent = await get(db, eventPath);
      const id = await waitForRoute(db, leader.uid, readyRoute, () => guest.call('mutateBandEvent', {
        action: 'inviteResponse', bandId: band, eventId: event, status: 'maybe',
      }));
      await waitForRoute(db, adminMember.uid, readyRoute, async () => {});
      const open = (user, notificationId = id) => user.call('resolveNotification', { notificationId });
      const route = await open(leader);
      assert.equal(route.kind, 'event');
      assert.equal(route.eventId, event);
      assert.equal(route.bandId, band);
      assert.equal(route.title, 'Event Ready to Finalize');
      assert.match(route.body, /Ready Band .* Concert/);
      assert.doesNotMatch(JSON.stringify(route), /Private title|Private description|Private response/);
      await assert.rejects(open(member), notFound);
      assert.deepEqual(await readyRows(member.uid), []);
      assert.deepEqual(await readyRows(former.uid), []);
      assert.deepEqual(await readyRows(guest.uid), []);
      assert.deepEqual(await readyRows(held.uid), []);

      const publish = (uid, type, key, data, options) => delivery.publish(db, {}, uid, type, key, data, options);
      const readyEvent = await get(db, eventPath);
      await Promise.all(Array.from({ length: 4 }, () =>
        readiness.notifyEventChange(db, band, event, pendingEvent, readyEvent, publish)));
      assert.equal((await readyRows(leader.uid)).length, 1);
      const answeredAgain = {
        ...readyEvent, externalInvitees: {
          ...readyEvent.externalInvitees,
          [guest.uid]: { ...readyEvent.externalInvitees[guest.uid], status: 'declined' },
        },
      };
      await readiness.notifyEventChange(db, band, event, answeredAgain, readyEvent,
        () => assert.fail('an RSVP edit within the same ready generation must not publish'));

      const routeGeneration = (await get(db, `${routePath(leader.uid)}/${id}`)).generation;
      // Removing an active member creates a new canonical generation.
      const newId = await waitForRoute(db, leader.uid, row => readyRoute(row) &&
        row.generation !== routeGeneration, () => db.ref(`${bandPath}/Members_band/${member.uid}/Status`).set('removed'));
      assert.notEqual(newId, id);
      await assert.rejects(open(leader), notFound);
      assert.equal((await open(leader, newId)).eventId, event);
      const adminId = (await readyRows(adminMember.uid)).find(([, row]) => row.generation !== routeGeneration)?.[0] ||
        await waitForRoute(db, adminMember.uid, row => readyRoute(row) && row.generation !== routeGeneration, async () => {});
      assert.equal((await adminMember.call('markFeatureNotificationsRead', { featureId: 'band_room' })).success, true);
      assert.equal((await get(db, `notificationFeedV2/${adminMember.uid}/${adminId}`)).isRead, true);
      await db.ref(`${bandPath}/Members_band/${adminMember.uid}/Role`).set('Member');
      await assert.rejects(open(adminMember, adminId), notFound);
      await leader.call('mutateBandEvent', { action: 'lock', bandId: band, eventId: event });
      await assert.rejects(open(leader, newId), notFound);
      await db.ref(eventPath).remove();
      await assert.rejects(open(leader, newId), notFound);
      await db.ref(bandPath).remove();
    });

    it('waits for the final main RSVP and skips empty or unchanged eligible audiences', async () => {
      const band = 'ready_member_' + suffix;
      const event = 'main_rsvp';
      const [leader, member, held] = await Promise.all([client(), client(), client()]);
      const bandPath = `Bands/${band}`;
      const eventPath = `${bandPath}/Events/${event}`;
      const when = new Date(Date.now() + 86400000).toISOString();
      const rsvp = status => ({ status, timestamp: new Date().toISOString(), comment: 'Private' });
      const members = {
        [leader.uid]: { Role: 'Leader', Status: 'active' },
        [member.uid]: { Role: 'Member', Status: 'active' },
        [held.uid]: { Role: 'Member', Status: 'temporarily_off' },
      };
      const base = {
        title: 'Test Event', startDateTime: when, requireResponse: true,
        createdAt: Date.now(),
      };
      const readyRoute = row => row.type === 'event_ready_to_finalize' && row.eventId === event;
      const readiness = require('../event_readiness');
      assert.equal(readiness.readiness({
        ...base, excludedMemberIds: [leader.uid, member.uid],
        externalInvitees: { [held.uid]: { source: 'direct', status: 'inactive' } },
      }, members), null);
      await db.ref(bandPath).set({ Members_band: members, Events: { [event]: base } });
      await leader.rulesDb.ref(`${eventPath}/Responses/${leader.uid}`).set(rsvp('Uncertain'));
      await member.rulesDb.ref(`${eventPath}/ScheduleResponses/part/${member.uid}`).set(rsvp('Yes'));
      assert.equal(readiness.readiness(await get(db, eventPath), members), null);
      const last = rsvp('maybe');
      const id = await waitForRoute(db, leader.uid, readyRoute, () =>
        member.rulesDb.ref(`${eventPath}/Responses/${member.uid}`).set(last));
      const routePath = `notificationRoutesV2/${leader.uid}`;
      const { generation } = await get(db, `${routePath}/${id}`);
      assert.equal((await waitForRow(db, leader.uid, id, async () => {})).type, 'event_ready_to_finalize');
      assert.ok(!Object.values(await get(db, `notificationRoutesV2/${member.uid}`) || {}).some(readyRoute));
      const publish = (uid, type, key, data, options) => delivery.publish(db, {}, uid, type, key, data, options);
      await Promise.all(Array.from({ length: 4 }, () =>
        readiness.notifyResponseChange(db, band, event, member.uid, null, last, publish)));
      assert.deepEqual(Object.entries(await get(db, routePath)).filter(([, row]) => readyRoute(row))
        .map(([id]) => id), [id]);

      await db.ref(`${eventPath}/excludedMemberIds`).set([held.uid]);
      assert.equal(readiness.readiness(await get(db, eventPath), members), generation);
      assert.equal(readiness.memberEligibilityChanged(members[member.uid],
        { ...members[member.uid], Role: 'Admin' }), false);
      await db.ref(bandPath).remove();
    });

    it('selects allowlisted sounds per registered installation and keeps legacy chat feed-only', async () => {
      const recipient = await client();
      const soundProfiles = ['android-v2', 'ios-v2', 'arbitrary-sound.wav'];
      const bindings = soundProfiles.map(soundProfile => ({
        installation: randomBytes(16).toString('hex'),
        proof: randomBytes(32).toString('hex'),
        token: randomBytes(32).toString('base64url'),
        sequence: 1, soundProfile,
      }));
      try {
        for (const binding of bindings) {
          await recipient.call('registerNotificationInstallation', binding);
        }
        await recipient.call('registerNotificationInstallation', bindings[0]);
        await assert.rejects(() => recipient.call('registerNotificationInstallation', {
          ...bindings[0], soundProfile: 'ios-v2',
        }), error => error.code === 'functions/failed-precondition');
        const destinations = await delivery.recipients(db, [recipient.uid]);
        assert.deepEqual(bindings.map(binding =>
          destinations.find(row => row.installation === binding.installation).soundProfile),
        ['android-v2', 'ios-v2', undefined]);

        const payloads = [];
        const messaging = { send: async payload => { payloads.push(payload); return 'accepted'; } };
        let readinessChecks = 0;
        await delivery.publish(db, messaging, recipient.uid, 'event_ready_to_finalize',
          [suffix, 'revoked-before-dispatch'], { bandId: 'privateBand', eventId: 'privateEvent' },
          { canPublish: async () => ++readinessChecks === 1 });
        assert.equal(readinessChecks, 4);
        assert.deepEqual(payloads, []);
        const publish = type => delivery.publish(db, messaging, recipient.uid, type,
          [suffix, type], { bandId: 'privateBand' });
        const { id } = await publish('sub_request_invite');
        assert.equal(payloads.length, 3);
        const [android, ios, legacy] = bindings.map(binding =>
          payloads.find(payload => payload.token === binding.token));
        assert.deepEqual(android.android.notification, {
          sound: 'notification_gig_request_v2', channelId: 'gig_request_channel_v2',
        });
        assert.equal(ios.apns.payload.aps.sound, 'notification_gig_request_v2.wav');
        assert.deepEqual(legacy.android.notification, {
          sound: 'gig_rquest', channelId: 'gig_request_channel',
        });
        for (const payload of payloads) {
          assert.deepEqual(payload.data, { schemaVersion: '2', notificationId: id, type: 'sub_request_invite' });
          assert.deepEqual(payload.notification, {
            title: 'Substitute Request', body: 'Open the app to view details.',
          });
        }
        payloads.length = 0;
        const ready = await publish('event_ready_to_finalize');
        assert.equal(payloads.length, 3);
        for (const payload of payloads) {
          assert.deepEqual(payload.notification, {
            title: 'Event Ready to Finalize', body: 'Open the app to view details.',
          });
          assert.deepEqual(payload.data, {
            schemaVersion: '2', notificationId: ready.id, type: 'event_ready_to_finalize',
          });
        }
        assert.deepEqual(payloads.find(payload => payload.token === android.token).android.notification,
          { sound: 'notification_event_rsvp_v2', channelId: 'rsvp_reminder_channel_v2' });
        assert.equal(payloads.find(payload => payload.token === ios.token).apns.payload.aps.sound,
          'notification_event_rsvp_v2.wav');
        payloads.length = 0;
        const chat = await publish('band_section_chat');
        assert.equal(payloads.length, 2);
        assert.ok(payloads.every(payload => payload.token !== legacy.token));
        assert.ok(payloads.every(payload => payload.notification.title === 'New Band Message'));
        assert.deepEqual(payloads.find(payload => payload.token === android.token).android.notification, {
          sound: 'default', channelId: 'chat_notifications_v2',
        });
        assert.equal(payloads.find(payload => payload.token === ios.token).apns.payload.aps.sound, 'default');
        assert.ok(await get(db, `notificationFeedV2/${recipient.uid}/${chat.id}`));

        payloads.length = 0;
        for (const type of ['direct_message', 'session_message', 'band_room_message', 'band_file_uploaded']) {
          const feed = await publish(type);
          assert.equal((await get(db, `notificationFeedV2/${recipient.uid}/${feed.id}`)).type, type);
          assert.equal((await get(db, `notificationRoutesV2/${recipient.uid}/${feed.id}`)).dispatchState, 'feed-only');
        }
        assert.equal(payloads.length, 0);
      } finally {
        for (const binding of bindings) {
          await recipient.call('unregisterNotificationInstallation', { ...binding, sequence: 2 });
        }
      }
    });

    it('keeps test pushes authenticated, restricts broadcast and rejects arbitrary sounds or other-account devices', async () => {
      const unauthenticated = await fetch(
        `http://127.0.0.1:5001/${project}/europe-west1/sendTestPushNotification`,
        { method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ data: { soundType: 'gig_rquest' } }) });
      assert.equal((await unauthenticated.json()).error.status, 'UNAUTHENTICATED');
      await assert.rejects(() => a.call('sendTestPushNotification', {
        soundType: 'gig_rquest', broadcastToAll: true,
      }), error => error.code === 'functions/permission-denied');
      for (const soundType of ['../guitarsound', '__proto__', ['gig_rquest']]) {
        await assert.rejects(() => a.call('sendTestPushNotification', { soundType }),
          error => error.code === 'functions/invalid-argument');
      }
      const binding = {
        installation: randomBytes(16).toString('hex'), proof: randomBytes(32).toString('hex'),
        token: randomBytes(32).toString('base64url'), sequence: 1,
      };
      await b.call('registerNotificationInstallation', binding);
      try {
        const result = await a.call('sendTestPushNotification', {
          soundType: 'gig_rquest', customToken: binding.token,
        });
        assert.deepEqual(result, { success: false, error: 'No registered device for this account.' });
      } finally {
        await b.call('unregisterNotificationInstallation', { ...binding, sequence: 2 });
      }
    });

    it('blocks legacy applicant data, token leaves and all private notification trees from clients', async () => {
      const root = `users/${a.uid}/info`;
      await db.ref().update({
        [`${root}/PushToken`]: 'synthetic-obsolete-token',
        [`${root}/DisplayName`]: 'Owner',
        [`userNotifications/${a.uid}/legacy/data/applicantName`]: 'private name',
        [`userNotifications/${a.uid}/legacy/type`]: 'sub_request_response',
        [`userNotifications/${a.uid}/legacy/createdAt`]: Date.now(),
      });
      for (const path of [
        root, `${root}/PushToken`, `userNotifications/${a.uid}`,
        `userNotifications/${a.uid}/legacy/data/applicantName`,
        'notificationTokenRegistry', `notificationRoutesV2/${a.uid}`, `notificationFeedV2/${a.uid}`,
      ]) await assertFails(a.rulesDb.ref(path).get());
      await assertSucceeds(a.rulesDb.ref(`${root}/DisplayName`).get());
      await assertFails(b.rulesDb.ref(`${root}/DisplayName`).get());
      await assertFails(a.rulesDb.ref(`${root}/PushToken`).set('new-synthetic-token'));
      await assertFails(a.rulesDb.ref(`notificationFeedSignals/${a.uid}`).set('forged'));
      await assertFails(b.rulesDb.ref(`notificationFeedSignals/${a.uid}`).get());
      await assertSucceeds(a.rulesDb.ref(`notificationFeedSignals/${a.uid}`).get());
      assert.equal((await a.call('listNotificationFeed')).some(row => row.id === 'legacy'), false);
      await assert.rejects(() => a.call('resolveNotification', { notificationId: 'legacy' }), notFound);
    });

    it('acknowledges an individual, a feature, and the rest of the V2 feed idempotently for the caller only', async () => {
      const own = idFor(a.uid, 'direct_message', 'ack-own');
      const feature = idFor(a.uid, 'event_invite', 'ack-feature');
      const remainder = idFor(a.uid, 'session_message', 'ack-remainder');
      const victim = idFor(b.uid, 'event_invite', 'ack-victim');
      const historical = idFor(a.uid, 'event_invite', 'ack-legacy');
      const aFeed = `notificationFeedV2/${a.uid}`;
      const bFeed = `notificationFeedV2/${b.uid}`;
      const legacy = `userNotifications/${a.uid}/${historical}`;
      const row = type => ({ type, createdAt: Date.now(), isRead: false });
      const old = { ...row('event_invite'), body: 'Historical text stays stored' };
      await db.ref().update({
        [`${aFeed}/${own}`]: row('direct_message'),
        [`${aFeed}/${feature}`]: row('event_invite'),
        [`${aFeed}/${remainder}`]: row('session_message'),
        [`${bFeed}/${victim}`]: row('event_invite'),
        [legacy]: old,
      });

      const mark = notificationId => a.call('markNotificationRead', { notificationId, uid: b.uid });
      await assert.rejects(() => mark('bad/path'), error => error.code === 'functions/invalid-argument');
      await assert.rejects(() => mark(victim), notFound);
      await assert.rejects(() => mark(historical), notFound);
      const before = await get(db, `notificationFeedSignals/${a.uid}`);
      const counts = await Promise.all([mark(own), mark(own)]);
      assert.equal(counts.reduce((sum, result) => sum + result.updatedCount, 0), 1);
      const acknowledged = await get(db, `${aFeed}/${own}`);
      assert.equal(acknowledged.isRead, true);
      assert.ok(acknowledged.readAt);
      assert.notEqual(await get(db, `notificationFeedSignals/${a.uid}`), before);
      assert.equal((await mark(own)).updatedCount, 0);
      assert.deepEqual(await get(db, `${aFeed}/${own}`), acknowledged);

      const markFeature = featureId => a.call('markFeatureNotificationsRead', { featureId, userId: b.uid });
      await assert.rejects(() => markFeature({ trim: 'invalid' }),
        error => error.code === 'functions/invalid-argument');
      assert.equal((await markFeature('band_room')).updatedCount, 1);
      assert.equal((await markFeature('band_room')).updatedCount, 0);
      assert.equal((await get(db, `${aFeed}/${feature}`)).isRead, true);
      assert.equal((await get(db, `${aFeed}/${remainder}`)).isRead, false);
      assert.equal((await a.call('markAllNotificationsRead', { userId: b.uid })).updatedCount, 1);
      assert.equal((await a.call('markAllNotificationsRead')).updatedCount, 0);
      assert.equal((await get(db, `${aFeed}/${remainder}`)).isRead, true);
      assert.equal((await get(db, `${bFeed}/${victim}`)).isRead, false);
      assert.deepEqual(await get(db, legacy), old);
      // Keep the later tests' fixture isolated from this test's read-state rows.
      await db.ref().update({
        [`${aFeed}/${own}`]: null, [`${aFeed}/${feature}`]: null,
        [`${aFeed}/${remainder}`]: null, [`${bFeed}/${victim}`]: null,
      });
    });

    it('publishes Band Room messages only to currently authorized recipients and denies a stale route', async () => {
      const band = `room_${suffix}`, messageId = `message_${suffix}`;
      const room = `bandconversations/${band}`;
      await db.ref().update({
        [`Bands/${band}/Members_band/${a.uid}`]: { Role: 'Leader', Status: 'active' },
        [`Bands/${band}/Members_band/${b.uid}`]: { Role: 'Member', Status: 'active' },
        [`Bands/${band}/Members_band/${outsider.uid}`]: { Role: 'Member', Status: 'inactive' },
        [`${room}/members/${a.uid}`]: true,
        [`${room}/members/${b.uid}`]: true,
        [`${room}/members/${outsider.uid}`]: true,
      });
      const type = 'band_room_message';
      const id = idFor(b.uid, type, [band, messageId]);
      const message = db.ref(`${room}/messages/${messageId}`);
      const row = await waitForRow(db, b.uid, id, () =>
        message.set({ SenderId: a.uid, Text: 'Private message text' }));
      assert.deepEqual(Object.keys(row).sort(), ['createdAt', 'isRead', 'type']);
      const trigger = require('../index').onBandRoomMessageCreated;
      await trigger.run(await message.get(), { params: { bandId: band, messageId } });
      const route = await b.call('resolveNotification', { notificationId: id });
      assert.equal(route.bandId, band);
      assert.equal(JSON.stringify(route).includes('Private message text'), false);
      for (const uid of [a.uid, outsider.uid]) {
        assert.equal(await get(db, `notificationFeedV2/${uid}/${idFor(uid, type, [band, messageId])}`), null);
      }
      await message.remove();
      await assert.rejects(() => b.call('resolveNotification', { notificationId: id }), notFound);
    });

    it('sends a session application to the canonical creator and its decision to the exact applicant', async () => {
      const sessionId = `session_${suffix}`;
      const session = db.ref(`Collabs/Sessions/${sessionId}`);
      const application = db.ref(`Collabs/Applications/${sessionId}/${b.uid}`);
      await session.set({ CreatorId: a.uid, Title: 'Session title' });
      const invite = await waitForRoute(db, a.uid,
        route => route.type === 'session_application' && route.sessionId === sessionId,
        () => application.set({ CreatorId: outsider.uid, Status: 'pending', Comment: 'Private comment' }));
      const row = await waitForRow(db, a.uid, invite, async () => {});
      assert.deepEqual(Object.keys(row).sort(), ['createdAt', 'isRead', 'type']);
      const authorized = await a.call('resolveNotification', { notificationId: invite });
      assert.equal(authorized.sessionId, sessionId);
      assert.equal('applicantId' in authorized, false);
      assert.equal(JSON.stringify(authorized).includes('Private comment'), false);
      assert.equal(await get(db, `notificationRoutesV2/${outsider.uid}`), null);
      const decision = await waitForRoute(db, b.uid,
        route => route.type === 'session_application_status' && route.sessionId === sessionId,
        () => application.child('Status').set('accepted'));
      const accepted = await b.call('resolveNotification', { notificationId: decision });
      assert.equal(accepted.title, 'Session application accepted');
      await assert.rejects(() => a.call('resolveNotification', { notificationId: decision }), notFound);
      await application.remove();
      await assert.rejects(() => a.call('resolveNotification', { notificationId: invite }), notFound);
      await assert.rejects(() => b.call('resolveNotification', { notificationId: decision }), notFound);
    });

    it('delivers one private-data-free alert after concurrent claims, with no retry after an ambiguous send', async () => {
      const installation = randomBytes(16).toString('hex');
      await a.call('registerNotificationInstallation', {
        installation, proof: randomBytes(32).toString('hex'), sequence: 1,
        token: randomBytes(32).toString('base64url'),
      });
      const payloads = [];
      const messaging = {
        send: async payload => {
          payloads.push(payload);
          throw Object.assign(new Error('provider result unknown'), { code: 'messaging/unknown' });
        },
      };
      const publish = () => delivery.publish(db, messaging, a.uid, 'event_invite', suffix, {
        bandId: 'privateBand', eventId: 'privateEvent',
      });
      const results = await Promise.all([publish(), publish(), publish()]);
      await publish();
      assert.equal(payloads.length, 1);
      assert.equal(new Set(results.map(result => result.id)).size, 1);
      const { id } = results[0];
      assert.deepEqual(payloads[0].notification, {
        title: 'Event Request', body: 'Open the app to view details.',
      });
      assert.deepEqual(payloads[0].data, { schemaVersion: '2', notificationId: id, type: 'event_invite' });
      assert.deepEqual(payloads[0].android, legacyReminder);
      assert.equal(payloads[0].apns.payload.aps.sound, 'reminder_rsvp.wav');
      const row = await get(db, `notificationFeedV2/${a.uid}/${id}`);
      assert.deepEqual(Object.keys(row).sort(), ['createdAt', 'isRead', 'type']);
      await assert.rejects(() => b.call('resolveNotification', { notificationId: id }), notFound);
    });

    it('routes several matching slots to a safe list and one matching slot to the exact request', async () => {
      const publicationId = `pub_${suffix}`;
      const first = `first_${suffix}`, second = `second_${suffix}`, hidden = `hidden_${suffix}`;
      const privateDescription = 'exact authorized Description';
      const request = { PublicationId: publicationId, Status: 'published',
        NotificationMode: 'grouped', Description: privateDescription, BandName: 'Band' };
      await db.ref().update({
        [`SubRequests/${first}`]: request,
        [`SubRequests/${second}`]: request,
        [`SubRequests/${hidden}`]: request,
        [`subRequestAudience/${first}/${b.uid}`]: true,
        [`subRequestAudience/${second}/${b.uid}`]: true,
        [`subRequestPublications/${publicationId}`]: {
          slots: [first, second, hidden].map(subRequestId => ({ subRequestId })),
        },
      });
      const id = createHash('sha256').update(JSON.stringify([b.uid, 'grouped_sub_request', publicationId])).digest('hex');
      const rowRef = db.ref(`notificationFeedV2/${b.uid}/${id}`);
      let listener;
      try {
        await new Promise((resolve, reject) => {
          listener = rowRef.on('value', snap => { if (snap.exists()) resolve(); }, reject);
        });
      } finally {
        rowRef.off('value', listener);
      }
      const resolve = data => b.call('resolveNotification', { notificationId: id, ...data });
      const group = await resolve();
      assert.equal(group.kind, 'group');
      assert.deepEqual(group.matches.map(slot => slot.id), [first, second]);
      assert.equal(JSON.stringify(group).includes(privateDescription), false);
      await assert.rejects(() => resolve({ slotId: hidden }), notFound);
      const exact = await resolve({ slotId: second });
      assert.equal(exact.request.id, second);
      assert.equal(exact.request.description, privateDescription);
      await db.ref(`SubRequests/${second}/Status`).set('cancelled');
      assert.equal((await resolve()).request.id, first);
      await assert.rejects(() => resolve({ slotId: second }), notFound);
      await db.ref(`subRequestAudience/${first}/${b.uid}`).remove();
      await assert.rejects(() => resolve(), notFound);
    });

    it('converges callable and response trigger, routes the exact responder and denies a former manager', async () => {
      const band = `band_${suffix}`, id = `request_${suffix}`;
      await db.ref().update({
        [`Bands/${band}/Name`]: 'Test band',
        [`Bands/${band}/Members_band/${a.uid}`]: { Role: 'Leader', Status: 'active' },
        [`SubRequests/${id}`]: {
          Status: 'published', BandId: band, BandName: 'Test band', CreatorUserId: a.uid,
          Description: 'private request text', VoicePart: 'Bass',
        },
      });
      await Promise.all([b.call('respondToSubRequest', { subRequestId: id }), b.call('respondToSubRequest', { subRequestId: id })]);
      const rows = await a.call('listNotificationFeed');
      const response = rows.filter(row => row.type === 'sub_request_response' && row.data.subRequestId === id);
      assert.equal(response.length, 1);
      const notificationId = response[0].id;
      const preview = await a.call('resolveNotification', { notificationId, preview: true });
      assert.equal(preview.title, 'Gig Request Response');
      assert.equal('responderId' in preview || 'request' in preview, false);
      assert.equal(JSON.stringify(rows).includes('private request text'), false);
      const exact = await a.call('resolveNotification', { notificationId });
      assert.equal(exact.request.id, id);
      assert.equal(exact.responderId, b.uid);
      await assert.rejects(() => b.call('resolveNotification', { notificationId }), notFound);
      await db.ref(`Bands/${band}/Members_band/${a.uid}/Status`).set('inactive');
      await assert.rejects(() => a.call('resolveNotification', { notificationId }), notFound);
      assert.equal((await a.call('listNotificationFeed')).some(row => row.id === notificationId), false);
    });

    it('routes Event Requests to the exact band event and fails closed on deletion', async () => {
      const band = `event_band_${suffix}`, event = `event_${suffix}`;
      await db.ref().update({
        [`Bands/${band}/Name`]: 'Event band',
        [`Bands/${band}/Members_band/${b.uid}`]: { Role: 'Member', Status: 'active' },
        [`Bands/${band}/Events/${event}`]: { title: 'Private title', createdBy: a.uid, eventType: 'Rehearsal' },
      });
      const { id } = await delivery.publish(db, {}, b.uid, 'event_invite', [band, event], { bandId: band, eventId: event });
      const result = await b.call('resolveNotification', { notificationId: id });
      assert.equal(result.title, 'Event Request');
      assert.equal(result.bandId, band);
      assert.equal(result.eventId, event);
      assert.equal(result.memberAccess, true);
      assert.equal(JSON.stringify(result).includes('Private title'), false);
      await db.ref(`Bands/${band}/Members_band/${b.uid}/Status`).set('inactive');
      await assert.rejects(() => b.call('resolveNotification', { notificationId: id }), notFound);
      await db.ref(`Bands/${band}/Members_band/${b.uid}/Status`).set('active');
      await db.ref(`Bands/${band}/Events/${event}`).remove();
      await assert.rejects(() => b.call('resolveNotification', { notificationId: id }), notFound);
    });
  });
}
