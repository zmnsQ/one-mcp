import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {createInterface} from 'node:readline';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {defaults, preferencesSchema, configuredTunnelRecords, workspace, writeConfiguration} from '../dist/configuration.js';
import {TunnelManager} from '../dist/tunnels.js';
import {validateTunnelBinding} from '../dist/tunnel-bindings.js';
const server = id => ({id,name:id,executable:process.execPath,arguments:[path.resolve('validation/mock-server.mjs')],workingDirectory:'',environmentKeys:[],allowedTools:['echo'],profile:id,tunnelID:`tunnel_${id}`});
const old = {...defaults(),servers:[server('a'),server('b')]};
const migrated = configuredTunnelRecords(old);
assert.deepEqual(migrated[0].serverIDs,['a','b']);
assert.equal(old.tunnelRecords,undefined);
assert.deepEqual(configuredTunnelRecords({...old,tunnelRecords:migrated,servers:[...old.servers,server('c')]}),migrated);
assert.deepEqual(configuredTunnelRecords({...old,tunnelRecords:[]}),[]);
assert.deepEqual(configuredTunnelRecords({...old,mode:'individual'}).map(r=>r.serverIDs),[['a'],['b']]);
assert.equal(preferencesSchema.safeParse({...old,tunnelRecords:[migrated[0],migrated[0]]}).success,false);
assert.throws(()=>validateTunnelBinding('x',[],'openai'));
assert.throws(()=>validateTunnelBinding('x',['a','a'],'openai'));
assert.throws(()=>validateTunnelBinding('../x',['a'],'openai'));
const folder=await fs.mkdtemp(path.join(os.tmpdir(),'onemcp-records-'));
const savedFile=path.join(folder,'settings.json');const original=JSON.stringify(old);await fs.writeFile(savedFile,original);
let loaded=await workspace(folder);assert.equal(await fs.readFile(savedFile,'utf8'),original);
assert.deepEqual(loaded.config.tunnelRecords[0].serverIDs,['a','b']);
await writeConfiguration(loaded,{...loaded.config,servers:[...loaded.config.servers,server('c')]},loaded.revision);
loaded=await workspace(folder);assert.deepEqual(loaded.config.tunnelRecords[0].serverIDs,['a','b']);
const cliSource=await fs.readFile('src/cli.ts','utf8');assert.match(cliSource,/tunnelRecordsVersion !== configurationFingerprint/);assert.match(cliSource,/Saved OAuth policy is not active/);
const nativeSource=await fs.readFile('../Sources/MCPHarbor/HarborStore.swift','utf8');assert.match(nativeSource,/guard requireScopedTunnelRuntime/);
const executable=path.join(folder,'client');
await fs.writeFile(executable,`#!${process.execPath}\nprocess.on('SIGTERM',()=>process.exit(0));setInterval(()=>{},1000);\n`,{mode:0o700});
const profiles=new TunnelManager(19879,()=>{},()=>true);
const fileA=path.join(folder,'a.profile'),fileB=path.join(folder,'b.profile');await fs.writeFile(fileA,'{}');await fs.writeFile(fileB,'{}');
try {
 const base={action:'run',executable,profile:'',runtimeKey:'',serverIDs:['a']};
 await profiles.action({...base,key:'one',tunnelID:'tunnel_one',profileFile:fileA});
 await profiles.action({...base,key:'two',tunnelID:'tunnel_two',profileFile:fileB});
 await assert.rejects(profiles.action({...base,key:'three',tunnelID:'tunnel_three',profileFile:fileA}));
}finally{await profiles.stopAll();}
const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r));
const child=spawn(process.execPath,['dist/index.js','--port',String(port)],{stdio:['pipe','pipe','pipe']});
const events=[],waiters=[];
createInterface({input:child.stdout}).on('line',line=>{const e=JSON.parse(line);events.push(e);for(const w of [...waiters])w(e);});
child.stderr.on('data',b=>process.stderr.write(b));
function wait(match){const prior=events.find(match);if(prior)return Promise.resolve(prior);return new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('timeout')),15000);const f=e=>{if(match(e)){clearTimeout(timer);waiters.splice(waiters.indexOf(f),1);resolve(e);}};waiters.push(f);});}
let seq=0;
async function command(method,params={}){const id=String(++seq);child.stdin.write(JSON.stringify({id,method,params})+'\n');return wait(e=>e.type==='response'&&e.id===id);}
async function rpc(route,method='tools/list',params={}){const response=await fetch(`http://127.0.0.1:${port}${route}`,{method:'POST',headers:{'content-type':'application/json',accept:'application/json, text/event-stream'},body:JSON.stringify({jsonrpc:'2.0',id:++seq,method,params}),signal:AbortSignal.timeout(10000)});return {status:response.status,data:await response.json()};}
const run=(key,ids)=>command('tunnelAction',{key,serverIDs:ids,action:'run',executable,profile:key,tunnelID:`tunnel_${key}`,runtimeKey:''});
try{
 await wait(e=>e.type==='ready');
 for(const id of ['a','b','c'])assert.equal((await command('startServer',{server:{...server(id),environment:{}}})).ok,true);
 assert.equal((await run('work',['a','b'])).ok,true);
 assert.equal((await run('personal',['c'])).ok,true);
 assert.equal((await run('work',['c'])).ok,false);
 assert.equal((await run('empty',[])).ok,false);
 assert.equal((await run('missing',['absent'])).ok,false);
 const work=await rpc('/tunnels/work/mcp'),personal=await rpc('/tunnels/personal/mcp');
 assert.equal(work.status,200);assert.equal(work.data.result.tools.length,2);assert.equal(personal.data.result.tools.length,1);
 const a=work.data.result.tools.find(t=>t.description.startsWith('[a]')).name;
 const c=personal.data.result.tools[0].name;
 assert.ok((await rpc('/tunnels/work/mcp','tools/call',{name:c,arguments:{text:'forbidden'}})).data.error);
 assert.equal((await rpc('/tunnels/work/mcp','tools/call',{name:a,arguments:{text:'bound'}})).data.result.content[0].text,'bound');
 assert.equal((await rpc('/tunnels/unknown/mcp')).status,404);
 assert.equal((await command('stopServer',{serverId:'a'})).ok,true);
 assert.equal((await rpc('/tunnels/work/mcp')).status,404);
 assert.equal((await rpc('/tunnels/personal/mcp')).data.result.tools.length,1);
 assert.equal((await command('stopTunnel',{key:'personal'})).ok,true);
 assert.equal((await rpc('/tunnels/personal/mcp')).status,404);
 await command('shutdown');await new Promise(r=>child.once('exit',r));
 console.log('PASS record migration, empty/duplicate rejection, subset tool isolation, independent lifecycle and stopped-route invalidation');
}finally{if(child.exitCode===null)child.kill('SIGTERM');await fs.rm(folder,{recursive:true,force:true});}

// Separate gateway with shared issuer policy: per-record audiences stay isolated.
const authDir=await fs.mkdtemp(path.join(os.tmpdir(),'onemcp-record-auth-'));
const authConfig={...defaults(),remoteConnection:{oauth:{enabled:true,publicURL:'https://main.example.com/mcp',issuer:'https://auth.example.com',jwksURL:'https://auth.example.com/jwks',scope:'mcp:tools'}}};
await fs.writeFile(path.join(authDir,'settings.json'),JSON.stringify(authConfig));
const fake=path.join(authDir,'cloudflared');await fs.writeFile(fake,`#!${process.execPath}\nprocess.on('SIGTERM',()=>process.exit(0));setInterval(()=>{},1000);\n`,{mode:0o700});
const credential1=path.join(authDir,'one.json'),credential2=path.join(authDir,'two.json');await fs.writeFile(credential1,'{}');await fs.writeFile(credential2,'{}');
const secure=spawn(process.execPath,['dist/index.js','--port',String(port),'--settings-file',path.join(authDir,'settings.json')],{stdio:['pipe','pipe','pipe']});
const se=[],sw=[];createInterface({input:secure.stdout}).on('line',line=>{const event=JSON.parse(line);se.push(event);for(const f of [...sw])f(event);});
function secureWait(match){const found=se.find(match);if(found)return Promise.resolve(found);return new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('secure fixture timeout')),15000);const f=e=>{if(match(e)){clearTimeout(timer);sw.splice(sw.indexOf(f),1);resolve(e);}};sw.push(f);});}
async function secureCommand(method,params){const id=String(++seq);secure.stdin.write(JSON.stringify({id,method,params})+'\n');return secureWait(e=>e.type==='response'&&e.id===id);}
try{
 await secureWait(e=>e.type==='ready');
 assert.equal((await secureCommand('startServer',{server:{...server('a'),environment:{}}})).ok,true);
 for(const [key,credential,id] of [['first',credential1,'00000000-0000-0000-0000-000000000001'],['second',credential2,'00000000-0000-0000-0000-000000000002']]){
  assert.equal((await secureCommand('cloudflareAction',{key,serverIDs:['a'],action:'run',executable:fake,mode:'named',tunnelID:id,credentialsFile:credential,publicURL:`https://${key}.example.com`})).ok,true);
  const metadata=await fetch(`http://127.0.0.1:${port}/.well-known/oauth-protected-resource/tunnels/${key}/mcp`);
  assert.equal(metadata.status,200);assert.equal((await metadata.json()).resource,`https://${key}.example.com/mcp`);
  const denied=await fetch(`http://127.0.0.1:${port}/tunnels/${key}/mcp`);
  assert.equal(denied.status,401);assert.ok(denied.headers.get('www-authenticate').includes(`${key}.example.com`));
 }
 assert.equal((await secureCommand('cloudflareAction',{key:'pending-quick',serverIDs:['a'],action:'run',executable:fake,mode:'quick'})).ok,true);
 assert.equal((await fetch(`http://127.0.0.1:${port}/tunnels/pending-quick/mcp`)).status,503);
 await secureCommand('stopTunnel',{key:'pending-quick'});
 const main=await fetch(`http://127.0.0.1:${port}/.well-known/oauth-protected-resource/mcp`);assert.equal((await main.json()).resource,'https://main.example.com/mcp');
 await secureCommand('stopTunnel',{key:'first'});
 assert.equal((await fetch(`http://127.0.0.1:${port}/tunnels/first/mcp`)).status,404);
 assert.equal((await fetch(`http://127.0.0.1:${port}/tunnels/second/mcp`)).status,401);
 await secureCommand('shutdown');await new Promise(r=>secure.once('exit',r));
 console.log('PASS two Cloudflare record audiences, isolated metadata/challenges, unchanged global policy and independent stop (mock processes)');
}finally{if(secure.exitCode===null)secure.kill('SIGTERM');await fs.rm(authDir,{recursive:true,force:true});}
