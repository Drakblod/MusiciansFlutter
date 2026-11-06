'use strict';
const { validMember } = require('./band_membership_index');
const record = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const placeholders = new Set(['null','none','undefined','n/a','na','browse musicians','browse profiles','browse_musicians']);
const text = (v, max=200) => typeof v === 'string' && v.trim() && v.trim().length <= max && !placeholders.has(v.trim().toLowerCase()) ? v.trim() : undefined;
const key = v => typeof v === 'string' && v.length > 0 && v.length <= 128 && !/[.#$\[\]/\u0000-\u001f\u007f]/.test(v) && !['__proto__','constructor','prototype'].includes(v);
function field(source, name) {
  const lower = name[0].toLowerCase()+name.slice(1);
  const info = record(source.info) ? source.info : {};
  return info[name] ?? source[name] ?? info[lower] ?? source[lower];
}
function list(value) {
  const raw = Array.isArray(value) ? value : record(value) ? Object.keys(value).sort().map(k=>value[k]) : typeof value === 'string' ? value.split(',') : [];
  const result=[],seen=new Set();
  for (const v of raw) { const s=text(v); if(s && !seen.has(s.toLowerCase())) {seen.add(s.toLowerCase());result.push(s);} }
  return result;
}
// Only exact legacy Swedish aliases are recognized. New locations require the
// confirmed structured contract; no address extraction or global city guesses.
const cities = ['Stockholm','Göteborg','Malmö','Uppsala','Linköping','Örebro','Västerås','Helsingborg','Jönköping','Norrköping','Lund','Umeå','Gävle','Borås','Halmstad','Karlstad','Sundsvall','Ljusdal'];
const legacyCities = new Map(cities.map(c=>[c.toLowerCase(),c]));
legacyCities.set('gothenburg','Göteborg');
function city(value) {
  const s=text(value,100);if(!s)return undefined;
  const parts=s.split(',').map(x=>x.trim());
  const known=legacyCities.get(parts[0].toLowerCase());
  return known && parts.length <= 2 && (parts.length===1 || ['sweden','sverige'].includes(parts[1].toLowerCase())) ? `${known}, Sweden` : undefined;
}
const locationPart=value=>typeof value==='string' && value.trim().length>0 && value.trim().length<=100 &&
  !/[,\u0000-\u001f\u007f]/.test(value) ? value.trim().replace(/\s+/g,' ').normalize('NFC') : undefined;
function structuredLocation(value) {
  if(!record(value)||value.version!==1||value.precision!=='city'||value.confirmed!==true)return undefined;
  if(['latitude','longitude','placeId','address','venue','formattedAddress','providerPayload','sessionToken'].some(k=>k in value))return undefined;
  const c=locationPart(value.city),country=locationPart(value.country);
  if(!c||!country)return undefined;
  const region=value.region==null?undefined:locationPart(value.region);
  if(value.region!=null&&!region)return undefined;
  const code=value.countryCode==null?undefined:typeof value.countryCode==='string'&&/^[A-Za-z]{2}$/.test(value.countryCode.trim())?value.countryCode.trim().toUpperCase():undefined;
  if(value.countryCode!=null&&!code)return undefined;
  const label=[c,region,country].filter(Boolean).join(', ');
  return {city:c,...(region?{region}:{}),country,...(code?{countryCode:code}:{}),label};
}
function publicLocation(source) {
  // A modern profile can explicitly clear an old root-level Location alias.
  if(field(source,'LocationCleared')===true)return undefined;
  const value=field(source,'PublicLocation');
  if(value!=null) return structuredLocation(value);
  const legacy=city(field(source,'Location'));
  return legacy?{city:legacy.split(',')[0],country:'Sweden',countryCode:'SE',label:legacy}:undefined;
}
function url(value) {
  const s=text(value,2048);if(!s)return undefined;
  try { const candidate=/^(?:www\.|open\.spotify\.com|spotify\.com|youtube\.com|youtu\.be)/i.test(s)?`https://${s}`:s;const parsed=new URL(candidate);return parsed.protocol==='https:' && !parsed.username && !parsed.password ? candidate : undefined; } catch (_) {return undefined;}
}
function userProfile(uid, source) {
  if(!key(uid)||!record(source))return null;
  const out={userId:uid};
  for(const f of ['DisplayName','Nickname','UserType','MainInstrument','Level']) {const v=text(field(source,f));if(v)out[f]=v;}
  for(const f of ['About','CollabBio']) {const v=text(field(source,f),4000);if(v)out[f]=v;}
  for(const f of ['ProfilePictureUrl','SpotifyUrl','YoutubeUrl','AudioSnippetUrl']) {const v=url(field(source,f));if(v)out[f]=v;}
  const location=publicLocation(source);if(location){out.Location=location.label;out.PublicLocation=location;}
  for(const f of ['Instruments','Styles','Genres','CollabRoles']) {const v=list(field(source,f));if(v.length)out[f]=v;}
  const main=list(out.MainInstrument).find(s=>!out.Instruments?.length || out.Instruments.includes(s));
  const primary=main || out.Instruments?.[0] || out.UserType;
  const skills=list([...(out.MainInstrument?.split(',')||[]),...(out.Instruments||[])]).filter(s=>s.toLowerCase()!==primary?.toLowerCase());
  if(skills.length)out.SecondarySkills=skills;
  if(typeof field(source,'CollabRemote')==='boolean')out.CollabRemote=field(source,'CollabRemote');
  return out;
}
function countMembers(source) {
  if(!record(source))return 0;
  return Object.entries(source).filter(([id,m])=>key(id)&&record(m)&&Object.keys(m).length>0&&validMember(m)&&
    !(m.Status!=null&&m.status!=null&&String(m.Status).trim().toLowerCase()!==String(m.status).trim().toLowerCase())).length;
}
function bandProfile(id, source) {
  if(!key(id)||!record(source))return null;
  const out={bandId:id,activeMemberCount:countMembers(source.Members_band ?? source.members_band)};
  for(const f of ['Name','EnsembleType','Style','Level','Qualification']) {const v=text(field(source,f));if(v)out[f]=v;}
  for(const f of ['About','Description']) {const v=text(field(source,f),4000);if(v)out[f]=v;}
  for(const f of ['Genres','Style_band']) {const v=list(field(source,f));if(v.length)out[f]=v;}
  const location=publicLocation(source);if(location){out.Location=location.label;out.PublicLocation=location;}
  return out;
}
const equal=(a,b)=>JSON.stringify(stable(a))===JSON.stringify(stable(b));
function stable(v){if(Array.isArray(v))return v.map(stable);if(record(v))return Object.fromEntries(Object.keys(v).sort().map(k=>[k,stable(v[k])]));return v;}
async function reconcile(db,kind,id) {
  if(!key(id))throw new Error('Invalid catalogue identity');
  const user=kind==='user';if(!user&&kind!=='band')throw new Error('Invalid catalogue kind');
  const canonical=db.ref(`${user?'users':'Bands'}/${id}`),projection=db.ref(`${user?'publicUserProfiles':'publicBandProfiles'}/${id}`);
  const sanitize=user?userProfile:bandProfile;
  for(let i=0;i<10;i++) {
    const source=(await canonical.get()).val(),next=sanitize(id,source);
    const previous=(await projection.get()).val();
    const result=equal(previous,next)?{committed:false}:await projection.transaction(()=>next,undefined,false);
    if(equal(source,(await canonical.get()).val()))return {changed:result.committed};
  }
  throw new Error('Catalogue source changed repeatedly; retry reconciliation');
}
function plan(users={},bands={},publicUsers={},publicBands={}) {
  const updates={},counts={scanned:0,eligible:0,skipped:0,malformed:0,unchanged:0,proposedWrites:0,proposedDeletions:0,
    structuredLocations:0,legacyCities:0,omittedLocations:0};
  for(const [sources,existing,root,sanitize] of [[users,publicUsers,'publicUserProfiles',userProfile],[bands,publicBands,'publicBandProfiles',bandProfile]]) {
    for(const id of [...new Set([...Object.keys(sources||{}),...Object.keys(existing||{})])].sort()) {
      if(!key(id)){counts.malformed++;counts.skipped++;continue;}
      const source=sources?.[id];let next=null;
      if(source!=null){counts.scanned++;next=sanitize(id,source);if(next){counts.eligible++;
        const structured=structuredLocation(field(source,'PublicLocation'));
        if(structured&&next.Location)counts.structuredLocations++;
        else if(next.Location)counts.legacyCities++;
        else counts.omittedLocations++;
      }else{counts.malformed++;counts.skipped++;}}
      if(equal(existing?.[id]??null,next)){counts.unchanged++;continue;}
      updates[`${root}/${id}`]=next;if(next)counts.proposedWrites++;else counts.proposedDeletions++;
    }
  }
  return {updates,counts};
}
module.exports={userProfile,bandProfile,countMembers,city,structuredLocation,publicLocation,list,key,equal,reconcile,plan};
