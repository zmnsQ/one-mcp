import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {createServer} from 'node:net';
import http from 'node:http';
const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r));
const child=spawn(process.execPath,['dist/index.js','--port',String(port)],{stdio:['pipe','pipe','pipe']});
const events=[];createInterface({input:child.stdout}).on('line',s=>{try{events.push(JSON.parse(s));}catch{}});child.stderr.on('data',()=>{});
async function wait(fn){for(let i=0;i<200;i++){const x=events.find(fn);if(x)return x;await new Promise(r=>setTimeout(r,20));}throw Error('Timed out');}
const endpoint=`http://127.0.0.1:${port}/mcp`;
async function request(headers={},method='initialize',params={protocolVersion:'2025-11-25',capabilities:{},clientInfo:{name:'private-secret-name',version:'1'}}){const res=await fetch(endpoint,{method:'POST',headers:{'content-type':'application/json',accept:'application/json, text/event-stream',...headers},body:JSON.stringify({jsonrpc:'2.0',id:'private-secret-id',method,params})});await res.text();await new Promise(r=>setTimeout(r,10));return events.filter(e=>e.type==='httpRequest').at(-1).request;}
try{await wait(e=>e.type==='ready');
await new Promise((resolve,reject)=>{const q=http.request(endpoint,{method:'POST',headers:{host:'private-secret-host'}},res=>{res.resume();res.on('end',resolve);});q.on('error',reject);q.end();});
await new Promise(r=>setTimeout(r,20));let hostRecord=events.filter(e=>e.type==='httpRequest').at(-1).request;assert.equal(hostRecord.stage,'host');assert.equal(hostRecord.httpStatus,403);assert.equal(hostRecord.hostAccepted,false);
let r=await request({origin:'private-secret-origin'});assert.equal(r.stage,'origin');assert.equal(r.httpStatus,403);assert.equal(r.originPresent,true);
r=await request({accept:'application/json'});assert.equal(r.stage,'sdk');assert.equal(r.httpStatus,406);assert.equal(r.rpcErrorCode,-32000);assert.equal(r.acceptSSE,false);
r=await request({'mcp-protocol-version':'2099-01-01'},'tools/list',{});assert.equal(r.httpStatus,400);assert.equal(r.protocolHeader,'2099-01-01');assert.equal(r.rpcErrorCode,-32000);
r=await request({'x-onemcp-local-diagnostic':'1'});assert.equal(r.httpStatus,200);assert.equal(r.negotiatedProtocol,'2025-11-25');assert.equal(r.diagnosticMarkerMatched,true);
r=await request({},'tools/list',{});assert.equal(r.toolCount,0);
for(const method of ['prompts/list','prompts/get','resources/list','resources/templates/list','resources/read','resources/subscribe','resources/unsubscribe','logging/setLevel','completion/complete','ping']){r=await request({},method,{});assert.equal(r.rpcMethod,method);}
r=await request({},'private-secret-method',{secret:'private-secret-body'});assert.equal(r.rpcMethod,'other');assert.equal(JSON.stringify(events.filter(e=>e.type==='httpRequest')).includes('private-secret'),false);
for(let i=0;i<85;i++)await request({'content-type':'text/plain'});
const beforeHealth=events.filter(e=>e.type==='httpRequest').length;for(let i=0;i<3;i++){const health=await fetch(`http://127.0.0.1:${port}/health`);await health.text();}await new Promise(r=>setTimeout(r,20));assert.equal(events.filter(e=>e.type==='httpRequest').length,beforeHealth);
child.stdin.write(JSON.stringify({id:'invalid-control',method:'unknown-private-secret'})+'\n');await wait(e=>e.type==='response'&&e.id==='invalid-control');
child.stdin.write(JSON.stringify({id:'snapshot',method:'snapshot'})+'\n');const snapshot=(await wait(e=>e.type==='response'&&e.id==='snapshot')).result;
assert.ok(snapshot.connectionEvents.some(e=>e.code==='GATEWAY_READY'));assert.ok(snapshot.connectionEvents.some(e=>e.code==='CONTROL_OPERATION_FAILED'));assert.equal(JSON.stringify(snapshot.connectionEvents).includes('private-secret'),false);
assert.equal(snapshot.requests.length,80);assert.equal(JSON.stringify(snapshot.requests).includes('private-secret'),false);
console.log('PASS actual HTTP journal: Origin/Accept/protocol rejection, negotiated protocol, list count, diagnostic marker, 80-entry bound, no raw values');
}finally{child.stdin.write(JSON.stringify({id:'shutdown',method:'shutdown'})+'\n');await wait(e=>e.type==='response'&&e.id==='shutdown').catch(()=>{});if(child.exitCode===null)child.kill('SIGTERM');}
