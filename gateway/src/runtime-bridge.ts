/** Private stdin/stdout GUI adapter. Closing this process never stops the gateway. */
import {safeTunnelError} from './tunnel-errors.js';
import {realpath} from 'node:fs/promises';
import {join} from 'node:path';
import {controlRequest,parseRequest} from './control.js';
import {inspectLegacy} from './takeover.js';
import {RuntimeClient} from './runtime-client.js';
const [home,workspace] = process.argv.slice(2);
if (!home || !/^[A-Za-z0-9_-]{1,64}$/.test(workspace ?? '')) throw new Error('Invalid runtime context');
const root = await realpath(home);
const client = new RuntimeClient(root,workspace!,(method,params)=>controlRequest(join(root,'Runtime','control.sock'),method,params));
const emit = (value:object) => process.stdout.write(JSON.stringify(value)+'\n');
let polling=false,closing=false,pending=0;
async function poll() {
  if (polling || closing) return;
  polling=true;
  try { emit({type:'sharedSnapshot',snapshot:await client.snapshot()}); }
  catch (error) { try {emit({type:'legacyGatewayAvailable',candidate:await inspectLegacy(root,workspace!)});}catch{} const incompatible = error instanceof Error && /identity|Unsupported|Unknown management/.test(error.message); emit({type:'sharedDisconnected',message:incompatible?'现有网关协议或工作空间不匹配。若它由旧版本启动，请明确停止旧实例后用新版启动；本应用不会强制接管。':'共享网关连接已断开，请检查状态后重新连接。'}); closing=true; process.exitCode=1; process.stdin.destroy(); clearInterval(timer); }
  finally { polling=false; }
}
const timer=setInterval(()=>void poll(),2000);
await poll();
let buffer='';
process.stdin.setEncoding('utf8');
process.stdin.on('data',(chunk:string)=>{
  buffer+=chunk;
  if(Buffer.byteLength(buffer)>1_048_576){closing=true;clearInterval(timer);process.stdin.destroy();process.exitCode=1;return;}
  let end:number;
  while((end=buffer.indexOf('\n'))>=0){
    const line=buffer.slice(0,end);buffer=buffer.slice(end+1);
    void (async()=>{
      let id='invalid';
      try {
        const c=parseRequest(JSON.parse(line));id=c.id;
        if(closing || pending>=8)throw new Error('Busy');
        pending++;
        try {const result=await client.command(c.method,c.params);emit({type:'response',id,ok:true,result});}
        finally {pending--;}
      }catch(error){emit({type:'response',id,ok:false,error:safeTunnelError(error) ?? '共享网关操作未完成；请检查状态，勿盲目重复提交。'});}
    })();
  }
});
process.stdin.on('end',()=>{closing=true;clearInterval(timer);});
process.once('SIGTERM',()=>{closing=true;clearInterval(timer);process.exit(0);});
