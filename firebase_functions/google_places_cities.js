'use strict';

const {createHash} = require('node:crypto');
const logger = require('firebase-functions/logger');

const CITY_TYPES = new Set(['locality', 'postal_town']);
const DENIED = new Set(['street_address', 'route', 'street_number', 'premise',
  'subpremise', 'establishment', 'point_of_interest', 'neighborhood',
  'sublocality', 'postal_code']);
const clean = value => typeof value === 'string' && value.trim().length > 0 &&
  value.trim().length <= 100 && !/[\u0000-\u001f\u007f,]/.test(value) ?
  value.trim().replace(/\s+/g, ' ').normalize('NFC') : null;
const token = value => typeof value === 'string' &&
  (/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)||
   /^[A-Za-z0-9_-]{62}$/.test(value));
// Keep the signed app token for authorization. Places accepts at most 36 ASCII characters.
const providerToken = value => value.length <= 36 ? value :
  createHash('sha256').update('catalogue-city-places:').update(value).digest('base64url').slice(0, 36);
const placeId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{5,200}$/.test(value);
const cityType = types => Array.isArray(types) &&
  types.some(type => CITY_TYPES.has(type)) && !types.some(type => DENIED.has(type));

function candidate(prediction) {
  if (!prediction || !placeId(prediction.placeId) || !cityType(prediction.types)) return null;
  const city = clean(prediction.structuredFormat?.mainText?.text);
  const secondary = prediction.structuredFormat?.secondaryText?.text;
  if (!city || typeof secondary !== 'string') return null;
  const parts = secondary.split(',').map(clean);
  if (parts.some(x => !x)) return null;
  const country = parts.at(-1);
  if (!country || country.toLowerCase() === city.toLowerCase()) return null;
  return {placeId:prediction.placeId,city,country,
    ...(parts.length > 1 ? {region:parts.slice(0,-1).join(', ')} : {})};
}

function confirmed(details) {
  if (!details || !CITY_TYPES.has(details.primaryType) || !cityType(details.types)) return null;
  const components = Array.isArray(details.addressComponents) ? details.addressComponents : [];
  const component = type => components.find(c => Array.isArray(c?.types) && c.types.includes(type));
  const city = clean((component('locality') || component('postal_town'))?.longText);
  const countryComponent = component('country');
  const country = clean(countryComponent?.longText);
  const region = clean(component('administrative_area_level_1')?.longText);
  const rawCode = countryComponent?.shortText;
  if (!city || !country || (rawCode != null &&
      (typeof rawCode !== 'string' || !/^[A-Za-z]{2}$/.test(rawCode)))) return null;
  const attributions=details.attributions||[];
  if(!Array.isArray(attributions)||attributions.length>20)return null;
  const providers=[];
  for(const attribution of attributions) {
    const name=clean(attribution?.provider);
    const uri=attribution?.providerUri;
    if(!name||uri!=null&&(typeof uri!=='string'||uri.length>2048||!/^https:\/\//i.test(uri)))return null;
    providers.push({provider:name,...(uri?{providerUri:uri}:{})});
  }
  return {version:1,precision:'city',confirmed:true,city,country,
    ...(region ? {region} : {}),
    ...(rawCode ? {countryCode:rawCode.toUpperCase()} : {}),
    ...(providers.length ? {attributions:providers} : {})};
}

async function boundedJson(response) {
  if(Number(response.headers?.get?.('content-length')||0)>65536)
    throw new Error('City provider response too large');
  if(response.body?.getReader) {
    const reader=response.body.getReader();
    const chunks=[];
    let bytes=0;
    try {
      while(true) {
        const {done,value}=await reader.read();
        if(done)break;
        bytes+=value.byteLength;
        if(bytes>65536)throw new Error('City provider response too large');
        chunks.push(Buffer.from(value));
      }
    } finally {await reader.cancel().catch(()=>{});}
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  }
  // Test fetchers may expose json() without a ReadableStream.
  const data=await response.json();
  if(Buffer.byteLength(JSON.stringify(data))>65536)
    throw new Error('City provider response too large');
  return data;
}

async function requestJson(url, options, fetcher) {
  const response = await fetcher(url,{...options,signal:AbortSignal.timeout(7000)});
  if (!response.ok) {
    let quota=response.status===429;
    if(response.status===403) {
      try {quota=(await boundedJson(response))?.error?.status==='RESOURCE_EXHAUSTED';}
      catch (_) {quota=false;}
    }
    const error=new Error('City provider unavailable');
    error.code=quota?'quota':'provider';
    logger.warn('City provider request failed', {status: response.status, category: error.code});
    throw error;
  }
  return boundedJson(response);
}

async function search(query, sessionToken, apiKey, fetcher=fetch) {
  if (!clean(query) || !token(sessionToken) || !apiKey) throw new Error('Invalid city request');
  const data = await requestJson('https://places.googleapis.com/v1/places:autocomplete',{
    method:'POST', headers:{'Content-Type':'application/json','X-Goog-Api-Key':apiKey,
      'X-Goog-FieldMask':'suggestions.placePrediction.placeId,suggestions.placePrediction.structuredFormat,suggestions.placePrediction.types'},
    body:JSON.stringify({input:query.trim(),includedPrimaryTypes:['(cities)'],
      includeQueryPredictions:false,sessionToken:providerToken(sessionToken)}),
  },fetcher);
  const seen = new Set(), result = [];
  for (const item of data.suggestions || []) {
    const value = candidate(item.placePrediction);
    if (value && !seen.has(value.placeId)) {seen.add(value.placeId);result.push(value);}
    if(result.length>=5)break;
  }
  return result;
}

async function resolve(id, sessionToken, apiKey, fetcher=fetch) {
  if (!placeId(id) || !token(sessionToken) || !apiKey) throw new Error('Invalid city request');
  const url = `https://places.googleapis.com/v1/places/${encodeURIComponent(id)}?sessionToken=${providerToken(sessionToken)}`;
  const data = await requestJson(url,{headers:{'X-Goog-Api-Key':apiKey,
    'X-Goog-FieldMask':'primaryType,types,addressComponents,attributions'}},fetcher);
  return confirmed(data);
}
module.exports = {candidate,confirmed,search,resolve,token,cityType};
