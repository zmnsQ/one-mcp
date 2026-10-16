import assert from 'node:assert/strict';
import {ConnectionJournal} from '../dist/connection-events.js';
const j=new ConnectionJournal();
assert.equal(j.record({type:'stderr',message:'secret-private'}),undefined);
j.record({type:'tunnelStatus',key:'secret-private',action:'run',running:false,errorCode:'TUNNEL_AUTH',message:'secret-private',signature:'secret-private'});
j.record({type:'tools',serverId:'secret-private',tools:[{name:'secret-private',description:'secret-private'}]});
assert.equal(j.snapshot()[0].code,'TUNNEL_AUTH');assert.equal(j.snapshot()[1].toolCount,1);
assert.equal(JSON.stringify(j.snapshot()).includes('secret-private'),false);
assert.equal(j.record({type:'tools',serverId:'secret-private',tools:[{}]}),undefined);
for(let i=0;i<250;i++)j.record({type:'tunnelStatus',key:'same',running:i%2===0,ready:false,action:'run'});
assert.equal(j.snapshot().length,200);
const snapshot=j.snapshot();snapshot[0].message='modified';assert.notEqual(j.snapshot()[0].message,'modified');
assert.deepEqual(new ConnectionJournal().snapshot(),[]);
console.log('PASS safe connection projection, deduplication, bounds, export copy and per-runtime isolation');

j.record({type:'response',ok:false,error:'[TUNNEL_PROFILE_FILE] private-secret',id:'private-secret'});assert.equal(j.snapshot().at(-1).code,'TUNNEL_PROFILE_FILE');assert.equal(JSON.stringify(j.snapshot()).includes('private-secret'),false);
