'use strict';

// Preloaded by the isolated runner into the CLI, Functions workers and Mocha.
// It is deliberately inactive in production and ordinary developer runs.
if (process.env.EMULATOR_ISOLATION_GATE !== 'true') {
  throw new Error('The emulator isolation guard may only run inside its runner.');
}

const fs = require('node:fs');
const net = require('node:net');
const tls = require('node:tls');
const http = require('node:http');
const https = require('node:https');
const dns = require('node:dns');
const path = require('node:path');
const os = require('node:os');

const project = 'demo-musicians-test';
const fakeKey = 'EMULATOR_ONLY_FAKE_KEY_DO_NOT_USE';
if (process.env.GCLOUD_PROJECT !== project ||
    process.env.GOOGLE_CLOUD_PROJECT !== project ||
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    process.env.FIREBASE_DATABASE_EMULATOR_HOST !== '127.0.0.1:9000' ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099' ||
    process.env.FUNCTIONS_EMULATOR_HOST !== '127.0.0.1:5001' ||
    process.env.LIVEKIT_API_KEY !== 'EMULATOR_ONLY_FAKE_LIVEKIT_KEY' ||
    process.env.LIVEKIT_API_SECRET !== 'EMULATOR_ONLY_FAKE_LIVEKIT_SECRET' ||
    process.env.LIVEKIT_URL !== 'ws://127.0.0.1:65535' ||
    process.env.METADATA_SERVER_DETECTION !== 'none' ||
    !process.env.EMULATOR_ISOLATION_ATTEMPTS) {
  throw new Error('Isolated demo emulator environment is incomplete.');
}
if (process.platform === 'win32' &&
    !process.env.APPDATA?.startsWith(process.env.EMULATOR_ISOLATION_TEMP)) {
  throw new Error('The normal Windows ADC location is still available.');
}
globalThis.__EMULATOR_ISOLATION_GUARD_ACTIVE__ = true;
process.stderr.write(`ISOLATION_GUARD_ACTIVE pid=${process.pid}\n`);

const ownAddresses = new Set(Object.values(os.networkInterfaces()).flat()
  .map(interfaceInfo => interfaceInfo.address.toLowerCase().split('%')[0]));
const local = host => {
  const value = String(host || 'localhost').toLowerCase().replace(/^\[|\]$/g, '');
  return value === 'localhost' || value === '127.0.0.1' || value === '::1' ||
    value === '0.0.0.0' || ownAddresses.has(value);
};
function deny(host, kind) {
  const destination = String(host || 'unknown').slice(0, 255);
  fs.appendFileSync(process.env.EMULATOR_ISOLATION_ATTEMPTS,
    JSON.stringify({pid:process.pid,kind,host:destination})+'\n');
  throw new Error(`External network destination blocked by emulator isolation: ${destination}`);
}
const socketConnect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function(...args) {
  const first = args[0];
  const options = first && typeof first === 'object' ? first : null;
  if (options?.path || typeof first === 'string' && !/^\d+$/.test(first))
    return socketConnect.apply(this,args);
  const host = options?.host ?? options?.hostname ??
    (typeof args[1] === 'string' ? args[1] : 'localhost');
  if (!local(host)) deny(host,'tcp');
  return socketConnect.apply(this,args);
};
const tlsConnect = tls.connect;
tls.connect = function(...args) {
  const options = args[0] && typeof args[0] === 'object' ? args[0] : null;
  const host = options?.host ?? options?.hostname ??
    (typeof args[1] === 'string' ? args[1] : 'localhost');
  if (!local(host)) deny(host,'tls');
  return tlsConnect.apply(this,args);
};
for (const [module,kind] of [[http,'http'],[https,'https']]) {
  const original = module.request;
  module.request = function(...args) {
    const input = args[0];
    const options = args[1] && typeof args[1] === 'object' ? args[1] : {};
    let host = options.hostname ?? options.host;
    if (!host && (typeof input === 'string' || input instanceof URL))
      host = new URL(input).hostname;
    if (!host && input && typeof input === 'object')
      host = input.hostname ?? input.host;
    if (!local(host)) deny(host,kind);
    return original.apply(this,args);
  };
}
const dnsLookup = dns.lookup;
dns.lookup = function(host,...rest) {
  if (!local(host)) deny(host,'dns');
  return dnsLookup.call(this,host,...rest);
};
for (const name of ['resolve','resolve4','resolve6','resolveAny','resolveCname',
  'resolveMx','resolveNs','resolveTxt','resolveSrv','resolveSoa','reverse']) {
  if (typeof dns[name] !== 'function') continue;
  const original = dns[name];
  dns[name] = function(host,...rest) {
    if (!local(host)) deny(host,'dns');
    return original.call(this,host,...rest);
  };
}

const realFetch = globalThis.fetch;
globalThis.fetch = async function(input,options={}) {
  const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url);
  if (url.hostname === 'places.googleapis.com') {
    const key = options.headers?.['X-Goog-Api-Key'];
    if (key !== fakeKey) deny(url.hostname,'places-key');
    if (url.pathname === '/v1/places:autocomplete' && options.method === 'POST') {
      const body = JSON.parse(options.body);
      if (typeof body.input !== 'string' || !body.sessionToken ||
          JSON.stringify(body.includedPrimaryTypes) !== '["(cities)"]')
        deny(url.hostname,'places-unmocked');
      return new Response(JSON.stringify({suggestions:[{placePrediction:{
        placeId:'PlaceBerlin123',types:['locality','political'],
        structuredFormat:{mainText:{text:'Berlin'},secondaryText:{text:'Germany'}}
      }}]}),{status:200,headers:{'Content-Type':'application/json'}});
    }
    if (url.pathname === '/v1/places/PlaceBerlin123' &&
        url.searchParams.has('sessionToken')) {
      return new Response(JSON.stringify({primaryType:'locality',
        types:['locality','political'],addressComponents:[
          {types:['locality'],longText:'Berlin'},
          {types:['country'],longText:'Germany',shortText:'DE'}],
        attributions:[]}),{status:200,headers:{'Content-Type':'application/json'}});
    }
    deny(url.hostname,'places-unmocked');
  }
  if (!local(url.hostname)) deny(url.hostname,'fetch');
  return realFetch.call(this,input,options);
};

// Auth Emulator accepts unsigned custom JWTs. Avoid Admin SDK's IAM signer,
// which would otherwise require ambient credentials or contact IAM.
const {BaseAuth} = require(path.join(__dirname,
  '../node_modules/firebase-admin/lib/auth/base-auth.js'));
BaseAuth.prototype.createCustomToken = async function(uid,claims={}) {
  if (typeof uid !== 'string' || !uid || uid.length > 128)
    throw new Error('Invalid emulator UID.');
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const now = Math.floor(Date.now()/1000);
  return `${encode({alg:'RS256',typ:'JWT'})}.${encode({
    iss:'emulator-only@demo-musicians-test.iam.gserviceaccount.com',
    sub:'emulator-only@demo-musicians-test.iam.gserviceaccount.com',
    aud:'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
    iat:now,exp:now+3600,uid,...(Object.keys(claims).length?{claims}:{})
  })}.emulator-only-signature`;
};

module.exports = {fakeKey};
