/** Read-only loopback protocol probe. No tools/call, credentials or local config in exported reports. */
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StreamableHTTPClientTransport} from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import {createHash} from 'node:crypto';
const MAX_BYTES=4*1024*1024;
export function safeDiagnosticValue(value:unknown,depth=0):unknown {
 if(depth>30)return '[depth limit]';
 if(typeof value==='string')return /Bearer\s|sk-[A-Za-z0-9]|(?:api[_-]?key|token|password|secret)[=:]|\/Users\/|\/home\/|file:\/\/|[A-Z]:\\Users\\|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i.test(value)?'[redacted]':value.slice(0,16384);
 if(Array.isArray(value))return value.slice(0,1000).map(x=>safeDiagnosticValue(x,depth+1));
 if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).filter(([k])=>!['description','default','examples','$comment','_meta'].includes(k)).slice(0,1000).map(([k,v])=>[k,/(?:token|password|secret|api[_-]?key|authorization)/i.test(k)&&(!v||typeof v!=='object')?'[redacted]':safeDiagnosticValue(v,depth+1)]));
 return value;
}
export async function diagnoseMCP(endpoint:string) {
 const url=new URL(endpoint);
 if(url.protocol!=='http:'||!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.username||url.password||url.search||url.hash||!/^\/(?:mcp|servers\/[A-Za-z0-9_-]{1,64}\/mcp)$/.test(url.pathname))throw Error('Diagnostics require a credential-free loopback MCP endpoint');
 const report:Record<string,any>={diagnosticVersion:1,time:new Date().toISOString(),readOnly:true,toolCalls:0,http:[],tools:[],redaction:'Descriptions, defaults, examples, metadata and recognized sensitive values omitted. Review before sharing; arbitrary schema text cannot be guaranteed secret-free. Schemas are diagnostic copies, not replacement definitions.'};
 let stage='initialize',total=0;const deadline=AbortSignal.timeout(60000);
 const client=new Client({name:'onemcp-readonly-diagnostic',version:'1'},{capabilities:{}});
 const transport=new StreamableHTTPClientTransport(url,{fetch:async(input,init)=>{
  let method='unknown';try{method=JSON.parse(typeof init?.body==='string'?init.body:'{}').method??'GET';}catch{}
  const headers=new Headers(init?.headers);headers.set('x-onemcp-local-diagnostic','1');
  const response=await fetch(input,{...init,headers,redirect:'error',signal:AbortSignal.any([deadline,...(init?.signal?[init.signal]:[]),AbortSignal.timeout(15000)])});
  report.http.push({method,status:response.status,contentType:response.headers.get('content-type')?.split(';')[0]?.slice(0,80),hasSessionID:response.headers.has('mcp-session-id')});
  if(response.headers.get('content-type')?.includes('text/event-stream')){await response.body?.cancel();throw Error('Diagnostic JSON-only scope');}
  const reader=response.body?.getReader();let size=0;const chunks:Uint8Array[]=[];
  if(reader)try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;total+=value.length;if(size>MAX_BYTES||total>MAX_BYTES)throw Error('Diagnostic response limit');chunks.push(value);}}finally{await reader.cancel().catch(()=>{});}
  if(response.status===204||response.status===202&&!size)return new Response(null,{status:response.status,headers:response.headers});
  const bytes=Buffer.concat(chunks);
  if(method==='initialize')try {const parsed=JSON.parse(bytes.toString('utf8'));report.protocolVersion=typeof parsed.result?.protocolVersion==='string'?safeDiagnosticValue(parsed.result.protocolVersion):null;if(parsed.error)report.rpcErrorCode=typeof parsed.error.code==='number'?parsed.error.code:null;}catch{}
  return new Response(bytes,{status:response.status,headers:response.headers});
 }});
 try {
  await client.connect(transport,{timeout:15000});report.initialize='passed';report.serverInfo=safeDiagnosticValue(client.getServerVersion());report.capabilities=safeDiagnosticValue(client.getServerCapabilities());
  stage='tools/list';let cursor:string|undefined;const cursors=new Set<string>(),names=new Set<string>();
  do {const result=await client.listTools(cursor?{cursor}:{},{timeout:15000});for(const tool of result.tools){if(names.has(tool.name))throw Error('Duplicate tool');names.add(tool.name);const raw=JSON.stringify(tool);report.tools.push({name:tool.name,nameLength:tool.name.length,portableName:/^[A-Za-z0-9_-]{1,64}$/.test(tool.name),inputSchema:safeDiagnosticValue(tool.inputSchema),outputSchema:safeDiagnosticValue(tool.outputSchema),annotations:safeDiagnosticValue(tool.annotations),definitionBytes:Buffer.byteLength(raw),definitionSHA256:createHash('sha256').update(raw).digest('hex')});}cursor=result.nextCursor;if(cursor&&cursors.has(cursor))throw Error('Repeated cursor');if(cursor)cursors.add(cursor);if(cursors.size>20||names.size>1000)throw Error('Catalogue limit');}while(cursor);
  report.toolsList='passed';report.toolCount=names.size;report.ok=true;
 }catch(error){report.ok=false;report.failedStage=stage;const e=error as {message?:string;issues?:Array<{code?:string;path?:unknown[]}>;code?:number};report.failureCode=['Duplicate tool','Repeated cursor','Catalogue limit','Diagnostic response limit','Diagnostic JSON-only scope'].includes(e?.message??'')?e.message:'PROTOCOL_REQUEST_FAILED';if(Array.isArray(e?.issues))report.validationIssues=e.issues.slice(0,50).map(x=>({code:x.code,path:safeDiagnosticValue(x.path)}));if(typeof e?.code==='number')report.rpcErrorCode=e.code;report.message='MCP 协议检查未通过。请检查 HTTP 状态和失败阶段；原始错误已隐藏，避免泄露私人数据。';}
 finally{await client.close().catch(()=>{});}
 report.responseBytes=total;return report;
}

export function compareConfiguration(saved:{port:number;servers:Array<{id:string;allowedTools:string[]}>;aggregateProfile:string},snapshot:any,published:string[]) {
 const running=Array.isArray(snapshot?.servers)?snapshot.servers:[];
 const names=(values:unknown)=>Array.isArray(values)?values.filter((x):x is string=>typeof x==='string').sort():[];
 const digest=(value:unknown)=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
 const rows=[...new Set([...saved.servers.map(s=>s.id),...running.map((s:any)=>s.id as string)])].sort().map(id=>{
  const disk=saved.servers.find(s=>s.id===id),live=running.find((s:any)=>s.id===id);
  const expected=live?.running&&Array.isArray(live.tools)?live.tools.filter((t:any)=>names(live.allowedTools).includes(t.name)).map((t:any)=>t.publicName).filter((x:unknown)=>typeof x==='string').sort():[];
  return {id,inSavedConfiguration:!!disk,running:live?.running===true,savedAllowedCount:disk?.allowedTools.length??0,runtimeAllowedCount:names(live?.allowedTools).length,allowlistMatches:!!disk&&!!live&&digest(names(disk.allowedTools))===digest(names(live.allowedTools)),runtimePublishedNames:expected};
 });
 const expected=rows.flatMap(r=>r.runtimePublishedNames).sort();
 const tunnel=Array.isArray(snapshot?.tunnels)?snapshot.tunnels.find((t:any)=>t.key==='aggregate'):undefined;
 const signature=typeof tunnel?.signature==='string'?tunnel.signature.split('\n'):[];
 return {savedPort:saved.port,runtimePort:snapshot?.port,portMatches:saved.port===snapshot?.port,servers:rows,publishedNamesMatchSnapshot:digest(expected)===digest([...published].sort()),publishedNamesSHA256:digest([...published].sort()),snapshotPublishedNamesSHA256:digest(expected),aggregateTunnel: tunnel?{running:tunnel.running===true,localReady:tunnel.ready===true,profileMatchesSaved:signature[1]===saved.aggregateProfile,endpointMatchesRuntime:signature[3]===`http://127.0.0.1:${snapshot.port}/mcp`}:null,chatGPTVerified:false};
}
