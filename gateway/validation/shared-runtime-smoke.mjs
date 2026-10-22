// Real gateway subprocess + two independent RPC clients over stdin, not Unix-socket transport.
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {createInterface} from 'node:readline';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
import {RuntimeClient,validateIdentity} from '../dist/runtime-client.js';
const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r));
const child=spawn(process.execPath,['dist/index.js','--port',String(port)],{stdio:['pipe','pipe','pipe']});
let seq=0;const requests=new Map();let ready;
const readyPromise=new Promise(r=>ready=r);
createInterface({input:child.stdout}).on('line',line=>{const e=JSON.parse(line);if(e.type==='ready')ready();if(e.type==='response'){const f=requests.get(e.id);requests.delete(e.id);f?.(e);}});
child.stderr.on('data',()=>{});
const rpc=(method,params={})=>new Promise((resolve,reject)=>{const id='test'+(++seq);const t=setTimeout(()=>reject(Error('timeout')),20000);requests.set(id,e=>{clearTimeout(t);e.ok?resolve(e.result):reject(Error(e.error));});child.stdin.write(JSON.stringify({id,method,params})+'\n');});
try {
 await readyPromise;
 // Test gateway identity checks through real dispatch; canonical root validation separately below.
 const rpcAtRoot=async(method,params)=>{const result=await rpc(method,params);return method==='snapshot'?{...result,controlRoot:'/fixture'}:result;};
 const gui=new RuntimeClient('/fixture','default',rpcAtRoot),ai=new RuntimeClient('/fixture','default',rpcAtRoot);
 const a=await gui.snapshot(),b=await ai.snapshot();assert.equal(a.instanceID,b.instanceID);assert.equal(a.pid,b.pid);
 await ai.command('startServer',{server:{id:'shared',name:'Shared',executable:process.execPath,arguments:[resolve('validation/mock-server.mjs')],environment:{},allowedTools:['echo']}});
 const s=await gui.snapshot();assert.equal(s.servers[0].running,true);assert.ok(s.servers[0].tools.some(t=>t.name==='echo'));
 await gui.command('updateAllowedTools',{serverId:'shared',allowedTools:[],expectedAllowedTools:['echo']});
 assert.deepEqual((await ai.snapshot()).servers[0].allowedTools,[]);
 await assert.rejects(ai.command('updateAllowedTools',{serverId:'shared',allowedTools:['echo'],expectedAllowedTools:['echo']}),/allowlist changed/);
 await ai.command('updateAllowedTools',{serverId:'shared',allowedTools:['echo'],expectedAllowedTools:[]});
 assert.deepEqual((await gui.snapshot()).servers[0].allowedTools,['echo']);
 await gui.command('stopServer',{serverId:'shared'});assert.equal((await ai.snapshot()).servers.length,0);
 assert.throws(()=>validateIdentity({...a,workspaceID:'other'},'/fixture','default'));
 assert.throws(()=>validateIdentity({...a,controlRoot:'/other'},'/fixture','default'));
 assert.throws(()=>validateIdentity({...a,protocolVersion:2},'/fixture','default'));
 await assert.rejects(rpc('stopAllTunnels',{expectedInstanceID:'00000000-0000-0000-0000-000000000000'}),/instance changed/);
 let changedID=false; const changed=new RuntimeClient('/fixture','default',async()=>({...a,instanceID:changedID?'11111111-1111-1111-1111-111111111111':a.instanceID}));
 await changed.snapshot();changedID=true;await assert.rejects(changed.snapshot(),/identity/);
 await assert.rejects(new RuntimeClient('/fixture','default',rpcAtRoot).command('shutdown'),/not been attached/);
 const exited=new Promise(r=>child.once('exit',r));await gui.command('shutdown');assert.equal(await exited,0);
 console.log('PASS two clients share one real gateway PID, catalogue and stop state; identity/unknown-client guards; explicit shutdown (stdin transport, Unix socket untested)');
}finally{if(child.exitCode===null)child.kill('SIGTERM');}
// Native lifecycle source invariants, not native execution.
const fs=await import('node:fs/promises');
const swift=await fs.readFile('../Sources/MCPHarbor/SharedRuntime.swift','utf8');
const detach=swift.slice(swift.indexOf('    func detachSharedGateway()'));
assert.doesNotMatch(detach,/command\(|shutdown\(/);
assert.match(detach,/bridge\?\.stop\(\)/);
const app=await fs.readFile('../Sources/MCPHarbor/MCPHarborApp.swift','utf8');
assert.match(app,/if store.isAttachedGateway \{ store.detachSharedGateway\(\); return .terminateNow \}/);
const bridge=await fs.readFile('src/runtime-bridge.ts','utf8');
assert.match(bridge,/process.stdin.on\('end',\(\)=>\{closing=true;clearInterval\(timer\);\}\)/);
console.log('PASS native detach/quit and adapter EOF source invariants (not native execution)');
