import {randomUUID} from 'node:crypto';
import type {IncomingMessage,ServerResponse} from 'node:http';
const knownMethods=new Set(['initialize','notifications/initialized','tools/list','tools/call','ping','server/discover','prompts/list','prompts/get','resources/list','resources/templates/list','resources/read','resources/subscribe','resources/unsubscribe','logging/setLevel','completion/complete']);
const protocol=(v:unknown)=>typeof v==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(v)?v:undefined;
export type RequestRecord={id:string;time:string;stage:string;route:string;httpMethod:string;hostAccepted:boolean;originPresent:boolean;acceptJSON:boolean;acceptSSE:boolean;diagnosticMarkerMatched:boolean;protocolHeader?:string;rpcMethod?:string;requestedProtocol?:string;negotiatedProtocol?:string;rpcErrorCode?:number;toolCount?:number;httpStatus?:number;completed?:boolean};
export class RequestJournal {
 private records:RequestRecord[]=[];
 constructor(private emit:(event:object)=>void){}
 snapshot(){return this.records.map(r=>({...r}));}
 begin(req:IncomingMessage,res:ServerResponse,hostAccepted:boolean){
  const accept=typeof req.headers.accept==='string'?req.headers.accept.toLowerCase():'';
  const r:RequestRecord={id:randomUUID(),time:new Date().toISOString(),stage:'entry',route:'unclassified',httpMethod:['GET','POST','DELETE','OPTIONS'].includes(req.method??'')?req.method!:'other',hostAccepted,originPresent:req.headers.origin!==undefined,acceptJSON:accept.includes('application/json'),acceptSSE:accept.includes('text/event-stream'),diagnosticMarkerMatched:req.headers['x-onemcp-local-diagnostic']==='1',protocolHeader:req.headers['mcp-protocol-version']===undefined?undefined:(protocol(req.headers['mcp-protocol-version'])??'other')};
  // Only inspect small final JSON responses transiently, then retain numeric code
  // and date-shaped protocol. Never retain response body or client-provided IDs.
  const end=res.end.bind(res),write=res.write.bind(res);
  let responseText='',responseBytes=0;
  const capture=(chunk:unknown)=>{if(typeof chunk!=='string'&&!ArrayBuffer.isView(chunk))return;const value=typeof chunk==='string'?chunk:Buffer.from(chunk.buffer,chunk.byteOffset,chunk.byteLength);responseBytes+=Buffer.byteLength(value);if(responseBytes<=8192)responseText+=value.toString();else responseText='';};
  res.write=((...args:any[])=>{capture(args[0]);return (write as any)(...args);}) as typeof res.write;
  res.end=((...args:any[])=>{capture(args[0]);if(responseText){try{const value=JSON.parse(responseText);if(Number.isSafeInteger(value?.error?.code))r.rpcErrorCode=value.error.code;if(r.rpcMethod==='initialize')r.negotiatedProtocol=protocol(value?.result?.protocolVersion);}catch{}}responseText='';return (end as any)(...args);}) as typeof res.end;
  let ignored=false;
  let done=false;const finish=()=>{if(done)return;done=true;responseText='';if(ignored)return;r.httpStatus=res.statusCode;r.completed=res.writableFinished;this.records.push({...r});if(this.records.length>80)this.records.shift();this.emit({type:'httpRequest',request:{...r}});};
  res.once('finish',finish);res.once('close',finish);
  return {ignore:()=>{ignored=true;},stage:(stage:string)=>{r.stage=stage;},route:(individual:boolean)=>{r.route=individual?'individual-mcp':'aggregate-mcp';},payload:(value:any)=>{r.rpcMethod=knownMethods.has(value?.method)?value.method:'other';if(value?.method==='initialize')r.requestedProtocol=protocol(value?.params?.protocolVersion);},tools:(count:number)=>{if(Number.isSafeInteger(count)&&count>=0)r.toolCount=count;}};
 }
}
