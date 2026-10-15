import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {createInterface} from 'node:readline';
import {resolve} from 'node:path';
import {request as httpRequest} from 'node:http';
import assert from 'node:assert/strict';
const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r));
const child=spawn(process.execPath,['dist/index.js','--port',String(port)],{stdio:['pipe','pipe','pipe']});
const events=[];const waiters=new Set();
createInterface({input:child.stdout}).on('line',s=>{const e=JSON.parse(s);events.push(e);for(const f of waiters)f(e);});child.stderr.on('data',b=>process.stderr.write(b));
function wait(fn){const old=events.find(fn);if(old)return Promise.resolve(old);return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{waiters.delete(listener);reject(Error('timeout'));},10000);function listener(e){if(fn(e)){clearTimeout(timer);waiters.delete(listener);resolve(e)}}waiters.add(listener);});}
let id=0;async function cmd(method,params){const key=String(++id);child.stdin.write(JSON.stringify({id:key,method,params})+'\n');return wait(e=>e.type==='response'&&e.id===key);}
async function rpc(method,params={},path='/mcp',headers={}){const r=await fetch(`http://127.0.0.1:${port}${path}`,{method:'POST',headers:{'content-type':'application/json',accept:'application/json, text/event-stream',...headers},body:JSON.stringify({jsonrpc:'2.0',id:++id,method,params}),signal:AbortSignal.timeout(10000)});return {status:r.status,body:await r.json()};}
function config(name,allowedTools){return{id:name,name,executable:process.execPath,arguments:[resolve('validation/mock-server.mjs')],environment:{},allowedTools};}
try {
await wait(e=>e.type==='ready');
assert.equal((await rpc('tools/list')).body.result.tools.length,0);console.log('PASS startup has no automatically started servers or exposed tools');
assert.equal((await cmd('startServer',{server:config('empty',[])})).ok,true);
assert.equal((await rpc('tools/list')).body.result.tools.length,0);
assert.ok((await rpc('tools/call',{name:'echo',arguments:{text:'blocked'}},'/servers/empty/mcp')).body.error);
console.log('PASS empty allowlist denies list and direct call');
assert.equal((await cmd('startServer',{server:config('alpha',['echo'])})).ok,true);
assert.equal((await cmd('startServer',{server:config('beta',['echo'])})).ok,true);
const listed=(await rpc('tools/list')).body.result.tools;assert.equal(listed.length,2);assert.equal(new Set(listed.map(x=>x.name)).size,2);
for(const tool of listed){assert.ok(tool.name.length<=64);assert.equal((await rpc('tools/call',{name:tool.name,arguments:{text:tool.name}})).body.result.content[0].text,tool.name);}
console.log('PASS same-name tools receive distinct bounded aliases and invoke successfully');
const toolEvent=events.find(e=>e.type==='tools'&&e.serverId==='alpha');assert.ok(toolEvent.tools[0].inputSchema);assert.ok(toolEvent.tools[0].publicName);console.log('PASS native IPC exports tool schema and public alias');
const bad=config('invalid',[]);bad.executable='relative-command';assert.equal((await cmd('startServer',{server:bad})).ok,false);assert.ok(events.find(e=>e.type==='serverStatus'&&e.serverId==='invalid'&&e.status==='error'));console.log('PASS invalid executable returns error status for native recovery');
const hostStatus=await new Promise((resolve,reject)=>{const request=httpRequest({host:'127.0.0.1',port,path:'/health',method:'GET',headers:{Host:'untrusted.example'}},response=>{response.resume();resolve(response.statusCode);});request.once('error',reject);request.end();});
assert.equal(hostStatus,403);console.log('PASS nonlocal Host rejected');
assert.equal((await cmd('stopServer',{serverId:'alpha'})).ok,true);assert.equal((await rpc('tools/list',{},'/servers/alpha/mcp')).status,404);console.log('PASS stopped endpoint removed immediately');
const exited=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('exit timeout')),10000);child.once('exit',code=>{clearTimeout(timer);code===0?resolve():reject(Error(`exit ${code}`));});});
assert.equal((await cmd('shutdown',{})).ok,true);await exited;console.log('PASS shutdown cleans up multiple managed MCP processes');
}catch(e){process.exitCode=1;console.error(e.stack);}finally{if(child.exitCode===null)child.kill('SIGTERM');}
