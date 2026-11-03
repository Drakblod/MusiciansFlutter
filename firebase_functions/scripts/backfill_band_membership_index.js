'use strict';

const { calculatePlan } = require('../band_membership_index');

function configuration(args, env = process.env) {
  const option = key => args.find(arg => arg.startsWith(`--${key}=`))?.slice(key.length + 3);
  const projectId = option('project') || env.GCLOUD_PROJECT || 'demo-musicians-test';
  const databaseURL = option('database-url') || `http://127.0.0.1:9000?ns=${projectId}`;
  const url = new URL(databaseURL);
  const localHost = host => ['localhost', '127.0.0.1', '[::1]'].includes(host);
  const emulatorHost = env.FIREBASE_DATABASE_EMULATOR_HOST;
  const local = localHost(url.hostname) && projectId.startsWith('demo-') &&
    (!emulatorHost || localHost(new URL(`http://${emulatorHost}`).hostname));
  if (!local && !(args.includes('--allow-production') && args.includes('--confirm-production'))) {
    throw new Error('Non-local access requires --allow-production AND --confirm-production (including dry-run).');
  }
  if (local && emulatorHost && emulatorHost !== url.host) throw new Error('Conflicting emulator host');
  return { projectId, databaseURL, local, apply: args.includes('--apply'), cleanup: args.includes('--cleanup-stale') };
}

async function readPaged(ref, pageSize = 200) {
  const result = {};
  let last;
  while (true) {
    let query = ref.orderByKey();
    if (last !== undefined) query = query.startAfter(last);
    const snap = await query.limitToFirst(pageSize).get();
    const keys = [];
    snap.forEach(child => { keys.push(child.key); result[child.key] = child.val(); });
    if (keys.length < pageSize) break;
    last = keys[keys.length - 1];
  }
  return result;
}

async function run(db, options) {
  const bands = await readPaged(db.ref('Bands'));
  const existing = await readPaged(db.ref('userBandMembershipIndex'));
  const plan = calculatePlan(bands, existing, options.cleanup);
  const entries = Object.entries(plan.updates);
  if (options.apply) {
    for (let i = 0; i < entries.length; i += 200) {
      await db.ref().update(Object.fromEntries(entries.slice(i, i + 200)));
    }
  }
  return { mode: options.apply ? 'apply' : 'dry-run', bandsScanned: Object.keys(bands).length,
    proposedWrites: entries.length, writes: options.apply ? entries.length : 0, ...plan };
}

if (require.main === module) {
  (async () => {
    // Validate authorization before loading Admin, obtaining credentials, or opening connections.
    const options = configuration(process.argv.slice(2));
    if (options.local) process.env.FIREBASE_DATABASE_EMULATOR_HOST = new URL(options.databaseURL).host;
    const admin = require('firebase-admin');
    const app = admin.initializeApp({ projectId: options.projectId, databaseURL: options.databaseURL });
    try { console.log(JSON.stringify(await run(app.database(), options), null, 2)); }
    finally { await app.delete(); }
  })().catch(error => { console.error(error.message); process.exitCode = 1; });
}

module.exports = { configuration, readPaged, run };
