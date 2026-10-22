import fs from 'node:fs/promises';
import os from 'node:os';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {createInterface} from 'node:readline';
import {resolve} from 'node:path';
import {request as httpRequest} from 'node:http';
import {setTimeout as delay} from 'node:timers/promises';
import assert from 'node:assert/strict';
const fixtures = resolve('validation/service-log-fixture.mjs');
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
const gateway=await launch();
try {
  await gateway.start('a',{},['echo','fail','throw']);
  await gateway.start('ab',{},['echo']);
  await gateway.call('a','echo',{secret:'PRIVATE_ARG'});
  await gateway.call('a','fail');
  await gateway.call('a','throw');
  await gateway.call('ab','echo');
  const a=gateway.events.filter(e=>e.type==='serviceCall'&&e.serverId==='a');
  assert.deepEqual(a.map(e=>e.outcome),['started','succeeded','started','failed','started','failed']);
  assert.equal(a[3].reason,'tool_error'); assert.equal(a[5].reason,'upstream_error');
  assert.equal(gateway.events.filter(e=>e.type==='serviceCall'&&e.serverId==='ab').length,2);
  for(const e of a)assert.ok(Object.keys(e).every(k=>['type','serverId','outcome','reason'].includes(k)));
  assert.ok(gateway.events.some(e=>e.type==='serverStatus'&&e.serverId==='a'&&e.status==='starting'));
  assert.ok(gateway.events.some(e=>e.type==='log'&&e.serverId==='a'&&e.message.includes('stderr received')));
  const snapshot=(await gateway.cmd('snapshot')).result;
  assert.ok(snapshot.events.some(e=>e.event.type==='serviceCall'));
  const logs=JSON.stringify(gateway.events.filter(e=>['serviceCall','serverStatus','log'].includes(e.type)));
  for(const secret of ['PRIVATE_BASIC','PRIVATE_URL','PRIVATE_ARG','PRIVATE_RESULT','PRIVATE_ERROR'])assert.ok(!logs.includes(secret));
  await gateway.shutdown();
  console.log('PASS per-service IDs, lifecycle, success, tool failure, exception, safe stderr, snapshot events and no private payloads');
} finally { if(gateway.child.exitCode===null)gateway.child.kill('SIGTERM'); }
