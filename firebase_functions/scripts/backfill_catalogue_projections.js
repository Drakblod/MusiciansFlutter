'use strict';
const { plan,reconcile } = require('../catalogue_projections');
const { readPaged } = require('./backfill_band_membership_index');
function configuration(args,env=process.env) {
  const option=k=>args.find(a=>a.startsWith(`--${k}=`))?.slice(k.length+3);
  if(args.some(a=>!['--apply','--allow-production','--confirm-production'].includes(a)&&!/^--(project|database-url)=/.test(a)))throw new Error('Unknown option');
  const projectId=option('project')||env.GCLOUD_PROJECT;
  const databaseURL=option('database-url')||env.FIREBASE_DATABASE_URL;
  if(!projectId||!databaseURL||! /^[a-z][a-z0-9-]{4,61}[a-z0-9]$/.test(projectId))throw new Error('Explicit project and database URL are required');
  const url=new URL(databaseURL),local=['localhost','127.0.0.1','[::1]'].includes(url.hostname);
  if(url.username||url.password||url.hash)throw new Error('Credentials or fragments are forbidden in database URL');
  if(local) {
    if(!projectId.startsWith('demo-')||url.protocol!=='http:'||url.searchParams.get('ns')!==projectId||[...url.searchParams.keys()].some(k=>k!=='ns'))throw new Error('Local execution requires an explicit matching demo namespace');
    if(env.FIREBASE_DATABASE_EMULATOR_HOST&&env.FIREBASE_DATABASE_EMULATOR_HOST!==url.host)throw new Error('Conflicting emulator host');
  } else {
    if(env.FIREBASE_DATABASE_EMULATOR_HOST)throw new Error('Ambiguous remote/emulator target');
    if(url.protocol!=='https:'||url.search||!([`${projectId}.firebaseio.com`,`${projectId}-default-rtdb.firebaseio.com`].includes(url.hostname)||url.hostname===`${projectId}-default-rtdb.europe-west1.firebasedatabase.app`))throw new Error('Database target does not match explicit project');
    if(!args.includes('--allow-production')||!args.includes('--confirm-production'))throw new Error('Remote reads/writes require --allow-production AND --confirm-production');
  }
  if(url.pathname!=='/')throw new Error('Database URL must identify the root');
  return {projectId,databaseURL,local,apply:args.includes('--apply')};
}
async function run(db,options) {
  const [users,bands,pUsers,pBands]=await Promise.all(['users','Bands','publicUserProfiles','publicBandProfiles'].map(p=>readPaged(db.ref(p))));
  const result=plan(users,bands,pUsers,pBands);let writes=0;
  if(options.apply) {
    // Re-read canonical data on apply; a stale dry-run snapshot never wins over live triggers.
    for(const path of Object.keys(result.updates)) {
      const [root,id]=path.split('/');const change=await reconcile(db,root==='publicUserProfiles'?'user':'band',id);if(change.changed)writes++;
    }
  }
  return {mode:options.apply?'apply':'dry-run',...result.counts,writes};
}
if(require.main===module) {
  (async()=>{
    const options=configuration(process.argv.slice(2));
    console.log(JSON.stringify({project:options.projectId,database:options.databaseURL,mode:options.apply?'apply':'dry-run'}));
    if(options.local)process.env.FIREBASE_DATABASE_EMULATOR_HOST=new URL(options.databaseURL).host;
    const admin=require('firebase-admin');const app=admin.initializeApp({projectId:options.projectId,databaseURL:options.databaseURL});
    try{console.log(JSON.stringify(await run(app.database(),options)));}finally{await app.delete();}
  })().catch(()=>{console.error('Catalogue backfill refused or failed; verify configuration and emulator/server availability.');process.exitCode=1;});
}
module.exports={configuration,run};
