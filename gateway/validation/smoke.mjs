import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {createInterface} from 'node:readline';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {workspace,writeConfiguration,defaults} from '../dist/configuration.js';
const configRoot=await fs.mkdtemp(path.join(os.tmpdir(),'onemcp-live-save-'));
const probe=createServer(); await new Promise(r=>probe.listen(0,'127.0.0.1',r)); const port=probe.address().port; await new Promise(r=>probe.close(r));
const child=spawn(process.execPath,['dist/index.js','--port',String(port)],{cwd:process.cwd(),stdio:['pipe','pipe','pipe']});
const events=[]; const waiters=[];
createInterface({input:child.stdout}).on('line',line=>{let e;try{e=JSON.parse(line)}catch{return;} events.push(e);for(const f of [...waiters])f(e);});
child.stderr.on('data',x=>process.stderr.write(x));
function wait(match){const prior=events.find(match);if(prior)return Promise.resolve(prior);return new Promise((resolve,reject)=>{const timeout=setTimeout(()=>{waiters.splice(waiters.indexOf(fn),1);reject(Error('IPC timeout'));},20000); const fn=e=>{if(match(e)){clearTimeout(timeout);waiters.splice(waiters.indexOf(fn),1);resolve(e);}};waiters.push(fn);});}
let n=0;async function rpc(method,params={},path='/mcp',headers={}){const r=await fetch(`http://127.0.0.1:${port}${path}`,{method:'POST',headers:{'content-type':'application/json',accept:'application/json, text/event-stream',...headers},body:JSON.stringify({jsonrpc:'2.0',id:++n,method,params}),signal:AbortSignal.timeout(10000)});return {status:r.status,data:await r.json()};}
try{
await wait(e=>e.type==='ready');
child.stdin.write(JSON.stringify({id:'start',method:'startServer',params:{server:{id:'fixture',name:'Fixture',executable:process.execPath,arguments:[resolve('validation/mock-server.mjs')],environment:{},allowedTools:['echo']}}})+'\n');
assert.equal((await wait(e=>e.type==='response'&&e.id==='start')).ok,true); console.log('PASS management start + upstream initialization');
let saved=await workspace(configRoot);await writeConfiguration(saved,{...defaults(),port,servers:[{id:'fixture',name:'Fixture',executable:process.execPath,arguments:[resolve('validation/mock-server.mjs')],workingDirectory:'',environmentKeys:[],allowedTools:[],tunnelID:'',profile:''}]},'missing');
assert.equal(child.exitCode,null);console.log('PASS saved-only configuration write leaves active gateway process running');
const init=await rpc('initialize',{protocolVersion:'2025-03-26',capabilities:{},clientInfo:{name:'smoke',version:'1'}});assert.equal(init.status,200);assert.ok(init.data.result.serverInfo);console.log('PASS HTTP MCP initialize');
const list=await rpc('tools/list');assert.equal(list.status,200);assert.equal(list.data.result.tools.length,1);const alias=list.data.result.tools[0].name;assert.notEqual(alias,'echo');console.log('PASS aggregate catalogue + allowlist + public alias');
const result=await rpc('tools/call',{name:alias,arguments:{text:'local-only'}});assert.equal(result.data.result.content[0].text,'local-only');console.log('PASS aggregate read-only tool call');
const individual=await rpc('tools/call',{name:'echo',arguments:{text:'direct'}},'/servers/fixture/mcp');assert.equal(individual.data.result.content[0].text,'direct');console.log('PASS per-server endpoint');
const denied=await rpc('tools/call',{name:'hidden'},'/servers/fixture/mcp');assert.ok(denied.data.error);console.log('PASS disabled tool denied');
const origin=await rpc('tools/list',{},'/mcp',{origin:'https://untrusted.example'});assert.equal(origin.status,403);console.log('PASS browser Origin denied');
child.stdin.write(JSON.stringify({id:'stop',method:'stopServer',params:{serverId:'fixture'}})+'\n');assert.equal((await wait(e=>e.type==='response'&&e.id==='stop')).ok,true);console.log('PASS managed server stop');
child.stdin.write(JSON.stringify({id:'shutdown',method:'shutdown'})+'\n');assert.equal((await wait(e=>e.type==='response'&&e.id==='shutdown')).ok,true);
await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('gateway exit timeout')),10000);child.once('exit',code=>{clearTimeout(timer);code===0?resolve():reject(Error(`exit ${code}`));});});console.log('PASS clean gateway shutdown');
}catch(e){process.exitCode=1;console.error(e.stack);}finally{if(child.exitCode===null)child.kill('SIGTERM');await fs.rm(configRoot,{recursive:true,force:true});}
