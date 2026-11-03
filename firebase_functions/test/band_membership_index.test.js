const assert = require('assert');
const { validMember, reconcileMembershipIndex, calculatePlan } = require('../band_membership_index');
const { configuration, readPaged, run } = require('../scripts/backfill_band_membership_index');

describe('Server-owned band membership index', () => {
  for (const status of [undefined, 'active', ' ACTIVE ', 'on_hold', 'temporarily_off']) {
    it(`accepts canonical member status ${status}`, () => assert(validMember({ Status: status })));
  }
  for (const status of ['inactive', 'removed', 'blocked', 'invited', 'suspended', 'unknown', '', 42]) {
    it(`rejects status ${status}`, () => assert(!validMember({ Status: status })));
  }
  it('rejects legacy scalar/list membership shapes', () => {
    for (const member of [null, true, 'Leader', []]) assert(!validMember(member));
  });
  it('reconciles current state on role, removal, restoration, retry and delayed event', async () => {
    let member = { Role: 'Leader' };
    const index = { 'userBandMembershipIndex/other/band': true };
    const db = { ref: path => ({ get: async () => ({ val: () => member }),
      update: async updates => Object.assign(index, updates) }) };
    for (const next of [member, { Role: 'Admin' }, { Status: 'inactive' }, null, { Status: 'active' }, { Status: 'active' }]) {
      member = next;
      await reconcileMembershipIndex(db, 'band', 'user');
      assert.strictEqual(index['userBandMembershipIndex/user/band'], validMember(member) ? true : null);
      assert.strictEqual(index['userBandMembershipIndex/other/band'], true);
    }
    member = null; // replay of an earlier create sees current deletion
    await reconcileMembershipIndex(db, 'band', 'user');
    assert.strictEqual(index['userBandMembershipIndex/user/band'], null);
  });
  it('propagates failed writes so the trigger retries', async () => {
    await assert.rejects(reconcileMembershipIndex({ ref: () => ({ get: async () => ({ val: () => ({}) }), update: async () => { throw Error('retry'); } }) }, 'b', 'u'), /retry/);
  });
  it('repairs an older write racing with restoration or removal', async () => {
    for (const initial of [null, { Status: 'active' }]) {
      let member = initial;
      let indexed;
      let writes = 0;
      const db = { ref: () => ({ get: async () => ({ val: () => member }), update: async updates => {
        indexed = updates['userBandMembershipIndex/u/b'];
        if (++writes === 1) member = initial ? null : { Status: 'active' };
      } }) };
      await reconcileMembershipIndex(db, 'b', 'u');
      assert.strictEqual(indexed, initial ? null : true);
      assert.strictEqual(writes, 2);
    }
  });
});

describe('Membership historical backfill', () => {
  const bands = { b: { Members_band: { a: { Role: 'Leader' }, held: { Status: 'on_hold' }, bad: true, off: { Status: 'inactive' } } } };
  it('proposes exact missing entries and reports stale, missing band and malformed', () => {
    const plan = calculatePlan(bands, { a: { missing: true, b: 'bad' } });
    assert.deepStrictEqual(plan.updates, { 'userBandMembershipIndex/a/b': true, 'userBandMembershipIndex/held/b': true });
    assert.deepStrictEqual(plan.stale, ['userBandMembershipIndex/a/missing']);
    assert.deepStrictEqual(plan.missingBands, plan.stale);
    assert.deepStrictEqual(plan.malformed, ['Bands/b/Members_band/bad']);
  });
  it('repeated apply is idempotent and cleanup is explicit', () => {
    const existing = { a: { b: true, missing: true }, held: { b: true } };
    assert.deepStrictEqual(calculatePlan(bands, existing).updates, {});
    assert.deepStrictEqual(calculatePlan(bands, existing, true).updates, { 'userBandMembershipIndex/a/missing': null });
  });
  it('dry-run performs zero writes; apply produces exact batched updates', async () => {
    const writes = [];
    const db = { ref: path => ({ orderByKey() { return this; }, limitToFirst() { return this; }, get: async () => ({ forEach: cb => Object.entries(path === 'Bands' ? bands : {}).forEach(([key, value]) => cb({ key, val: () => value })) }), update: async values => writes.push(values) }) };
    const dry = await run(db, { apply: false });
    assert.strictEqual(dry.writes, 0); assert.deepStrictEqual(writes, []);
    const applied = await run(db, { apply: true });
    assert.strictEqual(applied.writes, 2); assert.deepStrictEqual(writes, [dry.updates]);
  });
  it('defaults to local dry-run', () => assert.strictEqual(configuration([], {}).apply, false));
  it('pages at most 200 canonical bands per request without losing a boundary', async () => {
    const rows = Array.from({ length: 401 }, (_, i) => [`band_${String(i).padStart(3, '0')}`, { Members_band: {} }]);
    let cursor;
    const requests = [];
    const ref = { orderByKey() { return this; }, startAfter(key) { cursor = key; return this; },
      limitToFirst(size) { requests.push(size); return this; },
      get: async () => ({ forEach: cb => rows.filter(([key]) => cursor === undefined || key > cursor).slice(0, 200).forEach(([key, value]) => cb({ key, val: () => value })) }) };
    assert.strictEqual(Object.keys(await readPaged(ref)).length, 401);
    assert.deepStrictEqual(requests, [200, 200, 200]);
  });
  for (const flags of [[], ['--allow-production'], ['--confirm-production']]) {
    it(`rejects nonlocal target before access with flags ${flags}`, () => {
      assert.throws(() => configuration(['--project=demo-fake', '--database-url=https://example.invalid', ...flags], {}), /requires/);
    });
  }
  it('accepts explicit dual authorization only', () => assert.strictEqual(configuration(['--database-url=https://example.invalid', '--allow-production', '--confirm-production'], {}).local, false));
  it('rejects nonlocal emulator environment', () => assert.throws(() => configuration([], { FIREBASE_DATABASE_EMULATOR_HOST: 'example.invalid:9000' }), /requires/));
});
