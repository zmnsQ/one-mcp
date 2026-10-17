import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {boundRuntimeSnapshot, SNAPSHOT_BYTE_BUDGET} from '../dist/runtime-snapshot.js';
import {serveControl, controlRequest, CONTROL_LIMIT} from '../dist/control.js';

const bytes = value => Buffer.byteLength(JSON.stringify(value));
const identity = {protocolVersion:1, instanceID:'11111111-1111-1111-1111-111111111111',
    controlRoot:'/fixture', workspaceID:'default', pid:process.pid, port:18787};
const small = {...identity, servers:[{id:'small',running:true,allowedTools:['echo'],toolCount:1,
    tools:[{name:'echo',publicName:'small__echo_1234567890',description:'Echo input',inputSchema:{type:'object'}}]}]};
assert.equal(boundRuntimeSnapshot(small), small);
const large = {...identity, servers: Array.from({length:3}, (_,s) => ({id:'large'+s,running:true,
    allowedTools:['tool0'],toolCount:3,tools:Array.from({length:3}, (_,t) => ({name:'tool'+t,
        publicName:`large${s}__tool${t}_1234567890`,description:'多'.repeat(200_000),inputSchema:{type:'object'}}))}))};
assert.ok(bytes(large) > CONTROL_LIMIT * 4);
const before = JSON.stringify(large);
const compact = boundRuntimeSnapshot(large);
assert.ok(bytes(compact) <= SNAPSHOT_BYTE_BUDGET);
assert.equal(JSON.stringify(large), before, 'projection must not mutate routing catalog');
for (let i=0;i<large.servers.length;i++) {
    assert.deepEqual(compact.servers[i].tools.map(t => [t.name,t.publicName]),large.servers[i].tools.map(t => [t.name,t.publicName]));
    assert.deepEqual(compact.servers[i].allowedTools,large.servers[i].allowedTools);
    assert.equal(compact.servers[i].running,true);
    assert.equal(compact.servers[i].toolCount,3);
}
assert.ok(compact.servers.some(s => s.toolMetadataTruncated));
for (const key of Object.keys(identity)) assert.equal(compact[key],identity[key]);
// Escaped characters and UTF-8 bytes count toward the exact wire budget.
const escaped = {...identity,servers:[{id:'escaped',running:true,allowedTools:['a'],toolCount:2,
    tools:[{name:'a',publicName:'escaped__a',description:'\"\\多'.repeat(600)}, {name:'b',publicName:'escaped__b',description:'short'}]}]};
const trimmed = boundRuntimeSnapshot(escaped, 700);
assert.ok(bytes(trimmed)<=700);
assert.equal(trimmed.servers[0].tools[1].description,'short');
assert.equal(trimmed.servers[0].toolMetadataTruncated,true);
const hugeNames = {...identity,servers:[{id:'names',running:true,allowedTools:['allowed'],toolCount:100,
    tools:Array.from({length:100},(_,i)=>({name:`${i}${'x'.repeat(256)}`,publicName:`names__${i}`}))}]};
const omitted = boundRuntimeSnapshot(hugeNames,1000);
assert.ok(bytes(omitted)<=1000);
assert.equal(omitted.servers[0].tools,undefined);
assert.equal(omitted.servers[0].toolCatalogOmitted,true);
assert.equal(omitted.servers[0].toolMetadataTruncated,true);
assert.equal(omitted.servers[0].toolCount,100);
assert.deepEqual(omitted.servers[0].allowedTools,['allowed']);
assert.equal(hugeNames.servers[0].tools.length,100);
assert.throws(()=>boundRuntimeSnapshot(small,1),/state exceeds limit/);
console.log('PASS bounded snapshot metadata, complete names, explicit extreme omission, UTF-8 bytes and immutable source');
if (process.argv.includes('--pure') || process.env.ONEMCP_SKIP_SOCKET_TEST === '1') {
    console.log('SKIP Unix socket integration explicitly requested');
    process.exit(0);
}

// Real Unix socket transport catches the response limit that stdin-only tests cannot exercise.
const root = await fs.mkdtemp(path.join(os.tmpdir(),'mcp-snapshot-'));
const socket = path.join(root,'control.sock');
let close;
try {
    await fs.chmod(root,0o700);
    close = await serveControl(socket,async request => ({type:'response',id:request.id,ok:true,
        result: request.method==='rawSnapshot' ? large : request.method==='snapshot' ? compact : identity}));
    await assert.rejects(controlRequest(socket,'rawSnapshot'),/Management response exceeds limit/);
    assert.deepEqual(await controlRequest(socket,'status'),identity,'oversized snapshot must not kill gateway');
    assert.deepEqual(await controlRequest(socket,'snapshot'),compact);
    assert.deepEqual(await controlRequest(socket,'snapshot'),compact,'reconnection remains successful');
    console.log('PASS real Unix socket oversized-response reproduction; compact snapshots and status remain available');
} finally {
    await close?.();
    await fs.rm(root,{recursive:true,force:true});
}
