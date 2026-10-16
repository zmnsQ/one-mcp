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
try {
await wait(e=>e.type==='ready');
const names=['phone_status','phone_capabilities','phone.screenshot','phone-tap',...Array.from({length:33},(_,i)=>`phone_tool_${i}`)];
child.stdin.write(JSON.stringify({id:'start',method:'startServer',params:{server:{id:'iphone-use',name:'iPhone-use',executable:process.execPath,arguments:[resolve('validation/iphone-sdk-fixture.mjs')],environment:{},allowedTools:names}}})+'\n');
assert.equal((await wait(e=>e.type==='response'&&e.id==='start')).ok,true);
const {Client}=await import('@modelcontextprotocol/sdk/client/index.js');
const {StreamableHTTPClientTransport}=await import('@modelcontextprotocol/sdk/client/streamableHttp.js');
for (const endpoint of ['/mcp','/servers/iphone-use/mcp']) {
 const client=new Client({name:'official-sdk-validation',version:'1'},{capabilities:{}});
 const transport=new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${port}${endpoint}`));
 await client.connect(transport);
 const tools=(await client.listTools()).tools;assert.equal(tools.length,37);
 for (const tool of tools) {const result=await client.callTool({name:tool.name,arguments:{}});assert.equal(result.isError,undefined);assert.equal(JSON.parse(result.content[0].text).fixture,true);}
 console.log(`PASS official SDK initialize, initialized notification, list 37 and call all 37 tools: ${endpoint}`);
 await client.close();
}
const {execFile}=await import('node:child_process');
const {promisify}=await import('node:util');
const callCount=()=>events.filter(e=>e.type==='log'&&e.message?.startsWith('Calling enabled tool:')).length;
const callsBeforeDiagnostic=callCount();
const diagnostic=JSON.parse((await promisify(execFile)(process.execPath,['../scripts/diagnose-mcp.mjs',`http://127.0.0.1:${port}/mcp`])).stdout);
assert.equal(callCount(),callsBeforeDiagnostic);assert.equal(diagnostic.protocolVersion,'2025-11-25');assert.equal(diagnostic.ok,true);assert.equal(diagnostic.toolCount,37);assert.equal(diagnostic.toolCalls,0);
console.log('PASS read-only local diagnostic summarizes initialize and catalogue without tool calls');
const stale=await rpc('tools/call',{name:'iphone_use.6c5108a99d__phone_capabilities_51fed1061f',arguments:{}});
assert.match(stale.data.error.message,/Tool is not enabled/);
console.log('PASS connector-prefixed name rejected with gateway-specific error (distinct from -32001 Unknown tool)');
child.stdin.write(JSON.stringify({id:'shutdown',method:'shutdown'})+'\n');
await wait(e=>e.type==='response'&&e.id==='shutdown');
} catch(e){process.exitCode=1;console.error(e.stack);}finally{if(child.exitCode===null)child.kill('SIGTERM');await fs.rm(configRoot,{recursive:true,force:true});}
