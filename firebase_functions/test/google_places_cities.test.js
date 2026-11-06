'use strict';
const assert=require('assert');
const places=require('../google_places_cities');
const TOKEN='12345678-1234-4234-8234-123456789abc';
const prediction=(id='City123',types=['locality','political'])=>({placeId:id,types,
  structuredFormat:{mainText:{text:'Berlin'},secondaryText:{text:'Germany'}}});
const details=(types=['locality','political'])=>({primaryType:types[0],types,addressComponents:[
  {types:['locality'],longText:'Berlin'},
  {types:['administrative_area_level_1'],longText:'Berlin'},
  {types:['country'],longText:'Germany',shortText:'de'},
]});
describe('Google Places city-only provider boundary',()=>{
 it('accepts city prediction and displays city and country',()=>assert.deepStrictEqual(
   places.candidate(prediction()),{placeId:'City123',city:'Berlin',country:'Germany'}));
 for(const type of ['street_address','route','premise','establishment','point_of_interest','neighborhood'])
  it(`rejects ${type} prediction`,()=>assert.strictEqual(places.candidate(prediction('City123',['locality',type])),null));
 it('rejects prediction without country',()=>assert.strictEqual(places.candidate({...prediction(),structuredFormat:{mainText:{text:'Berlin'}}}),null));
 it('deduplicates search and requests only Google cities with one session token',async()=>{
  let body,headers;const fetcher=async(url,options)=>{body=JSON.parse(options.body);headers=options.headers;
    return {ok:true,json:async()=>({suggestions:[{placePrediction:prediction()},{placePrediction:prediction()}]})};};
  const result=await places.search('Ber',TOKEN,'fake-test-key',fetcher);
  assert.strictEqual(result.length,1);assert.deepStrictEqual(body.includedPrimaryTypes,['(cities)']);
  assert.strictEqual(body.sessionToken,TOKEN);assert.strictEqual(body.includeQueryPredictions,false);
  assert(!headers['X-Goog-FieldMask'].includes('location'));
 });
 it('resolved international locality returns only safe structured fields',()=>{
  assert.deepStrictEqual(places.confirmed(details()),{version:1,precision:'city',confirmed:true,
    city:'Berlin',region:'Berlin',country:'Germany',countryCode:'DE'});
 });
 it('normalizes decomposed Unicode city names before confirmation',()=>{
  const d=details();d.addressComponents[0].longText='Va\u0308xjo\u0308';
  assert.strictEqual(places.confirmed(d).city,'Växjö');
 });
 it('postal town is an accepted city-level equivalent',()=>{
  const d=details(['postal_town','political']);d.addressComponents[0]={types:['postal_town'],longText:'Bath'};
  assert.strictEqual(places.confirmed(d).city,'Bath');
 });
 for(const type of ['street_address','premise','establishment','point_of_interest','administrative_area_level_1'])
  it(`rejects resolved ${type}`,()=>assert.strictEqual(places.confirmed({...details(),primaryType:type}),null));
 it('rejects details without city or country',()=>{
  assert.strictEqual(places.confirmed({...details(),addressComponents:details().addressComponents.slice(1)}),null);
  assert.strictEqual(places.confirmed({...details(),addressComponents:details().addressComponents.slice(0,2)}),null);
 });
 it('details resolution sends same session token and excludes coordinates/placeId from result',async()=>{
  let url,mask;const fetcher=async(u,o)=>{url=u;mask=o.headers['X-Goog-FieldMask'];return {ok:true,json:async()=>({...details(),location:{latitude:1},id:'secret'})};};
  const result=await places.resolve('City123',TOKEN,'fake-test-key',fetcher);
  assert(url.includes(TOKEN));assert(!mask.includes('location'));assert(mask.includes('attributions'));
  assert(!('location'in result));assert(!('id'in result));
 });
 it('passes every Place Details provider credit transiently with its link',()=>{
  const result=places.confirmed({...details(),attributions:[
    {provider:'City data partner',providerUri:'https://example.test/source'}]});
  assert.deepStrictEqual(result.attributions,[
    {provider:'City data partner',providerUri:'https://example.test/source'}]);
  assert.strictEqual(places.confirmed({...details(),attributions:[
    {provider:'Bad',providerUri:'javascript:alert(1)'}]}),null);
 });
 it('rejects malformed session token',async()=>assert.rejects(()=>places.search('Berlin','bad','fake',async()=>{})));
});
