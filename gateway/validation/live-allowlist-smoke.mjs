import fs from 'node:fs/promises';
import os from 'node:os';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {createInterface} from 'node:readline';
import {resolve} from 'node:path';
import {request as httpRequest} from 'node:http';
import {setTimeout as delay} from 'node:timers/promises';
import assert from 'node:assert/strict';
const fixtures = resolve('validation/workflow-fixture.mjs');
let checks = 0;
const pass = label => { checks++; console.log(`PASS ${label}`); };
async function launch() {
  const probe=createServer(); await new Promise(r=>probe.listen(0,'127.0.0.1',r)); const port=probe.address().port; await new Promise(r=>probe.close(r));
  const child=spawn(process.execPath,['dist/index.js','--port',String(port)],{stdio:['pipe','pipe','pipe'],env:{...process.env,PARENT_PRIVATE_SECRET:'must-not-be-inherited'}});
  const events=[], waiters=new Set(); let requestId=0;
  createInterface({input:child.stdout}).on('line',line=>{const e=JSON.parse(line);events.push(e);for(const fn of [...waiters])fn(e);});
  child.stderr.on('data',b=>process.stderr.write(b));
  const exited = new Promise(resolve=>child.once('exit',(code,signal)=>resolve({code,signal})));
  const wait=(match, timeout=20000)=>{
    const previous=events.find(match); if(previous)return Promise.resolve(previous);
    return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{waiters.delete(listener);reject(Error('IPC timeout'));},timeout);timer.unref();const listener=e=>{if(match(e)){clearTimeout(timer);waiters.delete(listener);resolve(e);}};waiters.add(listener);});
  };
  const cmd=(method,params={})=>{const id=String(++requestId);child.stdin.write(JSON.stringify({id,method,params})+'\n');return wait(e=>e.type==='response'&&e.id===id);};
  const raw=(path='/mcp',payload={},options={})=>new Promise((resolve,reject)=>{
    const request=httpRequest({host:'127.0.0.1',port,path,method:options.method??'POST',headers:{'content-type':'application/json',accept:'application/json, text/event-stream',...options.headers},signal:options.signal},response=>{
      let data='';response.setEncoding('utf8');response.on('data',chunk=>data+=chunk);response.once('end',()=>{let body;try{body=JSON.parse(data);}catch{body=data;}resolve({status:response.statusCode,body,headers:response.headers});});
    });request.on('error',reject);request.setTimeout(75000,()=>request.destroy(Error('HTTP timeout')));
    request.end(typeof payload==='string'?payload:JSON.stringify(payload));
  });
  const rpc=(method,params={},id,options={})=>raw(id?`/servers/${id}/mcp`:'/mcp',{jsonrpc:'2.0',id:++requestId,method,params},options);
  const config=(id,environment={},allowedTools=['echo','new_echo','delay','stats','control'])=>({id,name:id,executable:process.execPath,arguments:[fixtures],environment,allowedTools});
  const start=async(id,environment={},allowed)=>{const response=await cmd('startServer',{server:config(id,environment,allowed)});assert.equal(response.ok,true,response.error);};
  const call=async(id,name,args={})=>{const response=await rpc('tools/call',{name,arguments:args},id);assert.equal(response.status,200);return response.body;};
  const stats=async id=>JSON.parse((await call(id,'stats')).result.content[0].text);
  const shutdown=async()=>{assert.equal((await cmd('shutdown')).ok,true);const exit=await Promise.race([exited,delay(10000,undefined,{ref:false}).then(()=>{throw Error('exit timeout');})]);assert.equal(exit.code,0);};
  await wait(e=>e.type==='ready');
  return {child,events,wait,cmd,raw,rpc,config,start,call,stats,shutdown,exited};
}
async function eventually(check,ms=4000){const end=Date.now()+ms;while(Date.now()<end){if(await check())return;await delay(30);}assert.fail('Condition did not become true');}
const gateway=await launch();
const folder=await fs.mkdtemp(resolve(os.tmpdir(),'onemcp-live-tools-'));
const executable=resolve(folder,'tunnel-fixture');
await fs.writeFile(executable,`#!${process.execPath}\nprocess.on('SIGTERM',()=>process.exit(0));setInterval(()=>{},1000);\n`,{mode:0o700});
try {
  const initial=['echo','delay','stats'];
  await gateway.start('a',{LIST_DELAY:'150'},initial);
  await gateway.start('b',{},['echo','stats']);
  const snapshot=()=>gateway.cmd('snapshot').then(r=>r.result);
  const before=await snapshot();
  assert.ok(before.configurationFingerprints.liveToolSelectionVersion);
  const server=state=>state.servers.find(s=>s.id==='a');
  const pid=(await gateway.stats('a')).pid;
  const update=(allowedTools,expectedAllowedTools=initial,extra={})=>gateway.cmd('updateAllowedTools',{serverId:'a',allowedTools,expectedAllowedTools,...extra});
  const alias=name=>server(before).tools.find(t=>t.name===name).publicName;
  const run=(key,ids)=>gateway.cmd('tunnelAction',{key,serverIDs:ids,action:'run',executable,profile:key,tunnelID:`tunnel_${key}`,runtimeKey:''});
  assert.equal((await run('work',['a'])).ok,true);
  assert.equal((await run('other',['b'])).ok,true);
  const tunnels=(await snapshot()).tunnels;
  const scoped=(key,method='tools/list',params={})=>gateway.raw(`/tunnels/${key}/mcp`,{jsonrpc:'2.0',id:999,method,params});
  for(const value of [undefined,null,'echo',{},['*'],[''],['x\0y'],['x'.repeat(257)],['echo','echo'],[3],Array.from({length:501},(_,i)=>'tool'+i)]) {
    assert.equal((await update(value)).ok,false);
    assert.equal((await gateway.cmd('updateAllowedTools',{serverId:'a',allowedTools:[],expectedAllowedTools:value})).ok,false);
  }
  assert.equal((await update([],initial,{unexpected:true})).ok,false);
  assert.equal((await update([],initial,{expectedInstanceID:'stale'})).ok,false);
  for(const serverId of ['missing','../a',null,4]) assert.equal((await update([],initial,{serverId})).ok,false);
  assert.deepEqual(server(await snapshot()),server(before));
  assert.equal((await update([],['echo'])).ok,false);
  assert.equal((await gateway.rpc('updateAllowedTools',{serverId:'a',allowedTools:[],expectedAllowedTools:initial})).body.error.code,-32601);
  pass('strict array/parameter validation, absent server, instance guard, CAS conflict and private-only control fail without mutation');

  const pending=gateway.call('a','delay',{ms:900});
  await eventually(async()=> (await gateway.stats('a')).active===1);
  const previousLists=(await gateway.stats('a')).listCalls;
  const pendingList=gateway.rpc('tools/list',{},'a');
  await eventually(async()=> (await gateway.stats('a')).listCalls>previousLists);
  const marker=gateway.events.length;
  const disabled=await update([],initial.toReversed());
  assert.equal(disabled.ok,true,disabled.error);
  assert.equal(disabled.result.clientRefreshRequired,true);
  assert.deepEqual(disabled.result.allowedTools,[]);
  assert.deepEqual((await pendingList).body.result.tools,[]);
  const authoritative=gateway.events.slice(marker).find(e=>e.type==='serverStatus');
  const {type,...reported}=authoritative;
  assert.deepEqual(reported,disabled.result);
  assert.notEqual(disabled.result.configurationFingerprints.allowedTools,server(before).configurationFingerprints.allowedTools);
  for(const [key,value] of Object.entries(server(before).configurationFingerprints)) if(key!=='allowedTools') assert.equal(disabled.result.configurationFingerprints[key],value);
  assert.deepEqual((await gateway.rpc('tools/list',{},'a')).body.result.tools,[]);
  assert.equal((await gateway.rpc('tools/list')).body.result.tools.some(t=>t.name===alias('echo')),false);
  assert.deepEqual((await scoped('work')).body.result.tools,[]);
  assert.ok((await gateway.call('a','echo')).error);
  assert.ok((await gateway.rpc('tools/call',{name:alias('echo')})).body.error);
  assert.ok((await scoped('work','tools/call',{name:alias('echo')})).body.error);
  assert.equal((await pending).result.isError,undefined);
  assert.deepEqual((await snapshot()).tunnels,tunnels);
  assert.equal((await scoped('other')).body.result.tools.length,2);
  assert.ok((await gateway.call('b','echo')).result);
  assert.equal(gateway.events.slice(marker).some(e=>e.type==='serverStatus'&&e.status!=='running'),false);
  pass('disable-all immediately blocks all routes, preserves admitted call and isolated server/tunnels');

  const raced=await Promise.all([update(['echo'],[]),update(['stats'],[])]);
  assert.equal(raced.filter(r=>r.ok).length,1);
  const winner=raced.find(r=>r.ok).result.allowedTools;
  assert.equal((await update(initial,winner)).ok,true);
  assert.equal((await gateway.stats('a')).pid,pid);
  assert.equal((await gateway.stats('a')).cancelled,0);
  assert.equal((await gateway.rpc('tools/list',{},'a')).body.result.tools.length,3);
  assert.ok((await gateway.rpc('tools/call',{name:alias('echo')})).body.result);
  assert.ok((await scoped('work','tools/call',{name:alias('echo')})).body.result);
  assert.ok((await scoped('other','tools/call',{name:alias('echo')})).body.error);
  const init=await gateway.rpc('initialize',{protocolVersion:'2025-03-26',capabilities:{},clientInfo:{name:'test',version:'1'}});
  assert.notEqual(init.body.result.capabilities.tools.listChanged,true);
  assert.equal((await gateway.raw('/mcp','', {method:'GET'})).status,405);
  assert.deepEqual(server(await snapshot()).configurationFingerprints,server(before).configurationFingerprints);
  pass('concurrent CAS has one winner; re-enable preserves PID/fingerprints/routing isolation and does not advertise push notifications');

  const maximum=Array.from({length:500},(_,i)=>'future'+i);
  assert.equal((await update(maximum,initial)).ok,true);
  assert.deepEqual((await gateway.rpc('tools/list',{},'a')).body.result.tools,[]);
  assert.equal((await update(initial,maximum)).ok,true);
  const cli={tools:[{name:'inspect',description:'Fixture',arguments:[]}],timeoutMs:1000,maxOutputBytes:2048,maxConcurrent:1};
  assert.equal((await gateway.cmd('startServer',{server:{id:'cli',name:'CLI',kind:'cli',cli,
    executable:process.execPath,arguments:[resolve('validation/cli-service-fixture.mjs'),'echo'],environment:{},allowedTools:[]}})).ok,true);
  const cliUpdate=(allowedTools,expectedAllowedTools=[])=>gateway.cmd('updateAllowedTools',{serverId:'cli',allowedTools,expectedAllowedTools});
  assert.equal((await cliUpdate(['undefined'])).ok,false);
  assert.equal((await cliUpdate(['inspect'])).ok,true);
  assert.equal((await gateway.rpc('tools/list',{},'cli')).body.result.tools.length,1);
  assert.equal((await cliUpdate([],['inspect'])).ok,true);
  assert.ok((await gateway.call('cli','inspect')).error);
  pass('500-name boundary succeeds but unknown upstream names stay hidden; CLI descriptor bounds live updates');

  assert.equal((await gateway.cmd('stopServer',{serverId:'a'})).ok,true);
  assert.equal((await update([],initial)).ok,false);
  await gateway.shutdown();
} finally {
  if(gateway.child.exitCode===null)gateway.child.kill('SIGTERM');
  await fs.rm(folder,{recursive:true,force:true});
}
console.log(`Completed ${checks} live allowlist integration groups.`);
