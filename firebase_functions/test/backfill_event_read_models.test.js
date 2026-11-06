'use strict';
const assert=require('node:assert/strict');
const {configuration,run}=require('../scripts/backfill_event_read_models');

function memoryDb(initial){
  const tree=structuredClone(initial);
  let writes=0;
  const segments=path=>path?path.split('/'):[];
  const read=path=>segments(path).reduce((value,key)=>value?.[key],tree)??null;
  const assign=(path,value)=>{
    const keys=segments(path);let node=tree;
    for(const key of keys.slice(0,-1))node=node[key]??={};
    if(value===null)delete node[keys.at(-1)];
    else node[keys.at(-1)]=structuredClone(value);
    writes++;
  };
  return {tree,get writes(){return writes;},ref(path=''){
    return {get:async()=>({val:()=>structuredClone(read(path)),exists:()=>read(path)!==null}),
      set:async value=>assign(path,value),
      update:async values=>{
        for(const [child,value] of Object.entries(values))
          assign([path,child].filter(Boolean).join('/'),value);
      }};
  }};
}

describe('SANITIZED-EVENT-READ-MODEL-01 backfill safety',()=>{
  it('requires explicit matching demo target and refuses ambiguous or unconfirmed remote target',()=>{
    assert.throws(()=>configuration([],{}));
    assert.throws(()=>configuration(['--project=demo-musicians-test'],{}));
    assert.throws(()=>configuration(['--project=live-prod',
      '--database-url=https://live-prod-default-rtdb.firebaseio.com/'],{}));
    const options=configuration(['--project=demo-musicians-test',
      '--database-url=http://127.0.0.1:9000/?ns=demo-musicians-test'],{});
    assert.equal(options.apply,false);
    assert.equal(options.local,true);
  });

  it('dry-run writes nothing; apply is idempotent and removes stale projections without changing canonical Events',async()=>{
    const db=memoryDb({Bands:{band_a:{Name:'Band A',Members_band:{member:{Role:'Member',Status:'active'}},
      Events:{event_a:{title:'Concert',startDateTime:'2027-01-01T19:00:00Z',
        Responses:{member:{status:'YES',comment:'Private RSVP'}}}}}},
      bandMemberEvents:{band_a:{orphan:{title:'Stale'}}}});
    const canonical=structuredClone(db.tree.Bands);
    const dry=await run(db,{apply:false});
    assert.equal(db.writes,0);
    assert.equal(dry.canonicalEvents,1);
    assert(dry.proposedWrites>0);
    assert(dry.proposedDeletions>0);
    const first=await run(db,{apply:true});
    assert(first.writes>0);
    assert.equal(db.tree.bandMemberEvents.band_a.orphan,undefined);
    assert.equal(db.tree.bandMemberEvents.band_a.event_a.title,'Concert');
    assert.equal(db.tree.userEventReadModels.member.band_a.event_a.Responses.member.comment,
      'Private RSVP');
    assert.deepEqual(db.tree.Bands,canonical);
    const second=await run(db,{apply:true});
    assert.equal(second.writes,0);
    assert.deepEqual(db.tree.Bands,canonical);
    assert(!JSON.stringify(second).includes('member'));
    assert(!JSON.stringify(second).includes('Private RSVP'));
  });
});
