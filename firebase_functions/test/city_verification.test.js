'use strict';
const assert=require('assert');
const gate=require('../city_verification');
const places=require('../google_places_cities');
const callables=require('../index');

describe('INTERNATIONAL-CITY-PICKER-01 policy and request validation',()=>{
  it('rejects unauthenticated Places calls before reading secrets or provider data',async()=>{
    for(const fn of [callables.startCatalogueCitySession,callables.searchCatalogueCities,
      callables.resolveCatalogueCity])
      await assert.rejects(()=>fn.run({data:{}}),error=>error.code==='unauthenticated');
  });
  it('rejects malformed and oversized callable requests before a provider call',async()=>{
    const auth={uid:'alice'};
    await assert.rejects(()=>callables.startCatalogueCitySession.run({auth,data:{extra:true}}),
      error=>error.code==='invalid-argument');
    for(const data of [{query:'x'.repeat(101),sessionToken:'bad'},
      {query:'Berlin',sessionToken:'bad',extra:'injected'},
      {query:'Berlin'}])
      await assert.rejects(()=>callables.searchCatalogueCities.run({auth,data}),
        error=>error.code==='invalid-argument');
    await assert.rejects(()=>callables.resolveCatalogueCity.run({auth,
      data:{placeId:'bad',sessionToken:'bad',purpose:'profile',targetId:'alice',
        city:'Berlin',country:'Germany',extra:'injected'}}),
      error=>error.code==='invalid-argument');
  });
  it('accepts only explicit user-authored city and country fields',()=>{
    assert.deepStrictEqual(gate.authored('  Växjö  ',' Sweden '),{city:'Växjö',country:'Sweden'});
    for(const city of ['','Street 12, Stockholm','x','x'.repeat(101)])
      assert.throws(()=>gate.authored(city,'Sweden'));
  });
  it('profile target must equal caller; band target must be a safe canonical key',()=>{
    assert.deepStrictEqual(gate.scope('profile','alice','alice'),{purpose:'profile',targetId:'alice'});
    assert.throws(()=>gate.scope('profile','bob','alice'));
    assert.throws(()=>gate.scope('band','bad/path','alice'));
    assert.throws(()=>gate.scope('event','band','alice'));
  });
  it('limits provider predictions and provider response bytes',async()=>{
    const token='12345678-1234-4234-8234-123456789abc';
    const prediction=i=>({placePrediction:{placeId:`City${i}123`,types:['locality'],
      structuredFormat:{mainText:{text:`City ${i}`},secondaryText:{text:'Germany'}}}});
    const many=Array.from({length:12},(_,i)=>prediction(i));
    const result=await places.search('City',token,'fake-test-key',async()=>({ok:true,
      json:async()=>({suggestions:many})}));
    assert.strictEqual(result.length,5);
    await assert.rejects(()=>places.search('City',token,'fake-test-key',async()=>({ok:true,
      headers:{get:()=>70000},json:async()=>({})})));
    await assert.rejects(()=>places.search('City',token,'fake-test-key',async()=>({ok:true,
      json:async()=>({large:'x'.repeat(70000)})})));
    let reads=0;
    await assert.rejects(()=>places.search('City',token,'fake-test-key',async()=>({ok:true,
      body:{getReader:()=>({read:async()=>{reads++;return {done:false,value:Buffer.alloc(40000)};},
        cancel:async()=>{}})}})));
    assert.strictEqual(reads,2); // streaming response stops before a third chunk
  });
  it('maps provider quota to a distinct code without exposing response content',async()=>{
    const token='12345678-1234-4234-8234-123456789abc';
    await assert.rejects(()=>places.search('City',token,'fake-test-key',async()=>({ok:false,status:429})),
      error=>error.code==='quota'&&!error.message.includes('fake-test-key'));
    await assert.rejects(()=>places.search('City',token,'fake-test-key',async()=>({ok:false,status:403,
      json:async()=>({error:{status:'RESOURCE_EXHAUSTED',message:'private provider text'}})})),
      error=>error.code==='quota'&&!error.message.includes('private provider text'));
  });
});
