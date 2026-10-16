// Read-only projection of the official local health schema. Never retain raw
// details, logs, tool arguments/results, headers, configuration, or credentials.
const components = ['control-plane','mcp','response-delivery','queue','dispatcher','oauth','cloudflared','proxy','harpoon'];
const atom=(x:unknown,max=64)=>typeof x==='string'&&x.length<=max&&/^[A-Za-z0-9_. -]+$/.test(x)?x:undefined;
const time=(x:unknown)=>typeof x==='string'&&x.length<=40&&/^\d{4}-\d\d-\d\dT[\d:.]+Z$/.test(x)?x:undefined;
export function projectTunnelHealth(raw:any) {
 if(!raw||raw.schema_version!==1) return {available:false,reason:'unsupported-schema'};
 return {available:true,live:raw.live===true,ready:raw.ready===true,snapshotAt:time(raw.snapshot_at),
  version:atom(raw.runtime?.version,64), components:components.flatMap(name=>{
   const c=raw.components?.[name]; if(!c||!['ok','degraded','unknown','disabled'].includes(c.status))return [];
   return [{name,status:c.status,state:atom(c.state,32),reasonCode:atom(c.reason_code,64),observedAt:time(c.observed_at)}];
  })};
}
export async function readTunnelHealth(base:URL) {
 const url=new URL('/health?details=true',base);
 if(url.protocol!=='http:'||url.hostname!=='127.0.0.1'||!url.port||url.username||url.password)throw new Error('Invalid local health URL');
 const response=await fetch(url,{redirect:'manual',signal:AbortSignal.timeout(2500)});
 if(response.status!==200){await response.body?.cancel();return {available:false,reason:response.status===404?'unsupported-version':'http-error'};}
 if(!response.headers.get('content-type')?.includes('application/json')){await response.body?.cancel();return {available:false,reason:'invalid-response'};}
 const reader=response.body?.getReader();if(!reader)return {available:false,reason:'empty-response'};
 let size=0;const chunks:Uint8Array[]=[];
 try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>65536)throw new Error('Health response too large');chunks.push(value);}}finally{await reader.cancel();}
 return projectTunnelHealth(JSON.parse(Buffer.concat(chunks).toString('utf8')));
}
