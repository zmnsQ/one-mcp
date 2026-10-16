import {createServer} from 'node:http';
import assert from 'node:assert/strict';
import {diagnoseMCP,safeDiagnosticValue} from '../dist/mcp-diagnostics.js';
let mode='pages',calls=0;
const server=createServer(async(req,res)=>{let data='';for await(const chunk of req)data+=chunk;let rpc;try{rpc=JSON.parse(data);}catch{res.writeHead(405).end();return;}
 if(rpc.method==='tools/call')calls++;
 if(rpc.method==='notifications/initialized'){res.writeHead(202).end();return;}
 const tool={name:'phone_status',inputSchema:{type:'object',properties:{value:{type:'string',default:'sk-secret-fixture',description:'/Users/private'}}},annotations:{readOnlyHint:true}};
 let result=rpc.method==='initialize'?{protocolVersion:'2025-11-25',capabilities:{tools:{}},serverInfo:{name:'fixture',version:'1'}}:{tools:[{...tool,name:rpc.params?.cursor?'phone_capabilities':tool.name}],...(mode==='pages'&&!rpc.params?.cursor||mode==='cycle'?{nextCursor:'same'}:{})};
 if(rpc.method==='tools/list'&&mode==='duplicate')result={tools:[tool,tool]};
 if(rpc.method==='tools/list'&&mode==='huge')result={tools:[{...tool,description:'x'.repeat(4*1024*1024)}]};
 if(rpc.method==='tools/list'&&mode==='invalid')result={tools:[{name:'bad',inputSchema:{type:'number'}}]};
 res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({jsonrpc:'2.0',id:rpc.id,result}));
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const endpoint=`http://127.0.0.1:${server.address().port}/mcp`;
try {
 const valid=await diagnoseMCP(endpoint);assert.equal(valid.ok,true);assert.equal(valid.toolCount,2);assert.equal(JSON.stringify(valid).includes('sk-secret-fixture'),false);assert.equal(JSON.stringify(valid).includes('/Users/private'),false);
 for(const bad of ['cycle','duplicate','huge','invalid']){mode=bad;const result=await diagnoseMCP(endpoint);assert.equal(result.ok,false,bad);assert.equal(result.failedStage,'tools/list');}
 assert.equal(calls,0);assert.equal(safeDiagnosticValue('Bearer private-token'),'[redacted]');assert.deepEqual(safeDiagnosticValue({token:'plain-value',const:'person@example.com'}),{token:'[redacted]',const:'[redacted]'});
 await assert.rejects(()=>diagnoseMCP('https://example.com/mcp'));await assert.rejects(()=>diagnoseMCP('http://user:pass@127.0.0.1/mcp'));
 console.log('PASS diagnostic pagination, duplicate/cycle/schema/byte bounds, redaction, loopback-only and zero tool calls');
}finally{server.closeAllConnections();await new Promise(r=>server.close(r));}
const {compareConfiguration}=await import('../dist/mcp-diagnostics.js');
const comparison=compareConfiguration({port:8787,aggregateProfile:'saved',servers:[{id:'phone',allowedTools:['a','b']}]},{port:8888,servers:[{id:'phone',running:true,allowedTools:['a'],tools:[{name:'a',publicName:'phone_a'}]}],tunnels:[{key:'aggregate',ready:true,running:true,signature:'/private/path\nlive\ntunnel_test\nhttp://127.0.0.1:8888/mcp'}]},['phone_a']);
assert.equal(comparison.portMatches,false);assert.equal(comparison.servers[0].allowlistMatches,false);assert.equal(comparison.aggregateTunnel.profileMatchesSaved,false);assert.equal(comparison.aggregateTunnel.endpointMatchesRuntime,true);assert.equal(comparison.publishedNamesMatchSnapshot,true);assert.equal(JSON.stringify(comparison).includes('/private/path'),false);assert.equal(comparison.chatGPTVerified,false);
console.log('PASS saved/live allowlists, port, actual published aliases and tunnel target comparison without paths/credentials');
