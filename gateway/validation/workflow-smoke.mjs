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
try {
  const pending=gateway.cmd('startServer',{server:gateway.config('slow',{START_DELAY:'500'})});
  await delay(75);
  assert.equal((await gateway.rpc('tools/list',{},'slow')).status,404);
  assert.equal((await pending).ok,true);pass('starting server remains hidden until initialized and discovered');
  await gateway.start('normal',{EXPLICIT_VALUE:'explicit-only'});
  const stats=await gateway.stats('normal');assert.equal(stats.parentSecret,null);assert.equal(stats.explicit,'explicit-only');pass('upstream receives explicit environment but no unrelated parent credential');
  const eventStart=gateway.events.length;
  assert.equal((await gateway.cmd('startServer',{server:gateway.config('normal')})).ok,false);
  assert.equal(gateway.events.slice(eventStart).some(e=>e.type==='serverStatus'&&e.serverId==='normal'&&e.status==='error'),false);
  assert.ok((await gateway.call('normal','echo')).result);pass('duplicate start preserves running status and live route');
  for(const [id,mode] of [['dupes','duplicate'],['cycle','cursor']]){
    assert.equal((await gateway.cmd('startServer',{server:gateway.config(id,{FIXTURE_MODE:mode})})).ok,false);
    assert.equal((await gateway.rpc('tools/list',{},id)).status,404);
  }pass('duplicate tool names and cyclic pagination fail closed without orphan routes');
  await gateway.start('paged',{FIXTURE_MODE:'pages'});
  assert.equal((await gateway.rpc('tools/list',{},'paged')).body.result.tools.length,2);pass('multi-page discovery includes all allowed tools');
  await gateway.start('refresh',{LIST_DELAY:'150'});
  const before=(await gateway.stats('refresh')).listCalls;
  await Promise.all(Array.from({length:10},()=>gateway.rpc('tools/list',{},'refresh')));
  assert.equal((await gateway.stats('refresh')).listCalls-before,1);pass('concurrent discoveries coalesce into one upstream catalogue request');
  await gateway.call('normal','control',{mode:'changed',notify:true});
  await gateway.wait(e=>e.type==='tools'&&e.serverId==='normal'&&e.tools.some(t=>t.name==='new_echo'));
  assert.ok((await gateway.call('normal','echo')).error);
  assert.ok((await gateway.call('normal','new_echo')).result);pass('list_changed updates native catalogue and removes obsolete routes immediately');
  await gateway.call('normal','control',{mode:'fail'});
  const aggregate=await gateway.rpc('tools/list');assert.ok(aggregate.body.result.tools.some(t=>t.description.startsWith('[slow]')));
  assert.equal(aggregate.body.result.tools.some(t=>t.description.startsWith('[normal]')),false);
  assert.ok((await gateway.call('normal','new_echo')).error);
  assert.ok((await gateway.rpc('tools/list',{},'normal')).body.error);pass('failed refresh clears stale routes while healthy aggregate tools remain available');
  await gateway.cmd('stopServer',{serverId:'normal'});
  await gateway.start('normal');
  assert.ok((await gateway.call('normal','echo')).result);pass('failed catalogue can recover through stop and restart with same id');
  assert.equal((await gateway.raw('/mcp',{}, {headers:{origin:''}})).status,403);
  assert.equal((await gateway.raw('/mcp',{}, {headers:{'content-type':'x-application/json'}})).status,415);
  assert.equal((await gateway.raw('http://[',{})).status,400);
  assert.equal((await gateway.raw('/mcp','bad-json')).status,400);
  assert.equal((await gateway.raw('/mcp',[])).status,400);
  const method=await gateway.raw('/mcp','',{method:'GET'});assert.equal(method.status,405);assert.equal(method.headers.allow,'POST');
  assert.equal((await gateway.raw('/health','',{method:'GET'})).status,200);pass('malformed targets, empty Origin, invalid content types and JSON fail without crashing');
  assert.equal((await gateway.raw('/mcp',' '.repeat(1024*1024+1))).status,413);
  assert.equal((await gateway.raw('/health','',{method:'GET'})).status,200);pass('oversized streaming body receives 413 and gateway remains healthy');
  assert.equal((await gateway.raw('/mcp',{jsonrpc:'2.0',method:'notifications/initialized'})).status,202);pass('stateless initialized notification accepted');
  const callStarts=()=>gateway.events.filter(e=>e.type==='serviceCall'&&e.serverId==='normal'&&e.outcome==='started').length;
  const startsBefore=callStarts();
  const controllers=Array.from({length:4},()=>new AbortController());
  const calls=controllers.map(controller=>gateway.rpc('tools/call',{name:'delay',arguments:{ms:30000}},'normal',{signal:controller.signal}).catch(error=>error));
  // stats shares the same concurrency limit, so wait until four call logs are visible.
  await eventually(()=>callStarts()===startsBefore+4);
  assert.ok((await gateway.call('normal','delay',{ms:1})).error);
  controllers.forEach(controller=>controller.abort());await Promise.all(calls);
  await eventually(async()=>{const result=await gateway.call('normal','stats');if(!result.result)return false;const stats=JSON.parse(result.result.content[0].text);return stats.active===0&&stats.cancelled===4;});
  assert.ok(gateway.events.filter(e=>e.type==='serviceCall'&&e.serverId==='normal'&&e.reason==='cancelled').length>=4);
  pass('per-upstream concurrency is bounded and HTTP disconnect cancels upstream work');
  const crashPid=(await gateway.stats('normal')).pid;
  await gateway.call('normal','control',{crash:true});
  await gateway.wait(e=>e.type==='serverStatus'&&e.serverId==='normal'&&e.status==='error');
  assert.equal((await gateway.rpc('tools/list',{},'normal')).status,404);
  assert.throws(()=>process.kill(crashPid,0));
  await gateway.start('normal');pass('unexpected upstream exit removes routes and permits clean restart');
  await gateway.start('redaction',{SHORT_SECRET:'private-prefix',PRIVATE_SECRET:'private-prefix-sensitive-suffix',LIST_DELAY:'100'});
  await gateway.call('redaction','control',{mode:'fail'});
  const redacted=await gateway.cmd('listTools',{serverId:'redaction'});
  assert.equal(redacted.ok,false);assert.match(redacted.error,/redacted/);assert.equal(redacted.error.includes('sensitive-suffix'),false);
  assert.equal(JSON.stringify(gateway.events).includes('private-prefix'),false);pass('discovery errors redact overlapping configured secrets before IPC delivery');
  const started=Date.now();
  const timed=await gateway.call('normal','delay',{ms:65000});
  assert.ok(gateway.events.some(e=>e.type==='serviceCall'&&e.serverId==='normal'&&e.reason==='timeout'));
  assert.equal(timed.result.isError,true);assert.match(timed.result.content[0].text,/timed out/i);
  assert.ok(Date.now()-started>=59000&&Date.now()-started<68000);
  await eventually(async()=>{const stats=await gateway.stats('normal');return stats.active===0&&stats.cancelled===1;});
  assert.ok((await gateway.call('normal','echo')).result);pass('real 60-second call timeout cancels upstream and releases capacity for later calls');
  await gateway.shutdown();pass('shutdown exits cleanly after multi-server and in-flight lifecycle tests');
} finally {if(gateway.child.exitCode===null)gateway.child.kill('SIGTERM');}
const startup=await launch();
try {
  startup.cmd('startServer',{server:startup.config('pending',{START_DELAY:'10000'})}).catch(()=>undefined);
  await delay(150);startup.child.kill('SIGTERM');
  const exit=await Promise.race([startup.exited,delay(10000,undefined,{ref:false}).then(()=>{throw Error('startup shutdown timeout');})]);
  assert.equal(exit.code,0);
  assert.equal(startup.events.some(e=>e.type==='serverStatus'&&e.status==='running'),false);
  pass('SIGTERM during initialization cannot resurrect a stopped server');
} finally {if(startup.child.exitCode===null)startup.child.kill('SIGTERM');}
console.log(`Completed ${checks} workflow checks against freshly built gateway.`);
