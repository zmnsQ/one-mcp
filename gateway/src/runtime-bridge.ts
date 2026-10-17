/** Private stdin/stdout GUI adapter. Closing this process never stops the gateway. */
import {safeTunnelError} from './tunnel-errors.js';
import {realpath} from 'node:fs/promises';
import {join} from 'node:path';
import {controlRequest,parseRequest} from './control.js';
import {inspectLegacy} from './takeover.js';
import {RuntimeClient,sharedDisconnectReason} from './runtime-client.js';
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
  catch (error) {
    try {emit({type:'legacyGatewayAvailable',candidate:await inspectLegacy(root,workspace!)});}catch{}
    const reason=sharedDisconnectReason(error);
    const messages:Record<string,string>={
      'identity-mismatch':'现有网关协议或工作空间不匹配。若它由旧版本启动，请明确停止旧实例后用新版启动；本应用不会强制接管。',
      'socket-unavailable':'共享网关连接端点不可用。点击重新连接 / 启动检查并恢复；不会自动重启 MCP 或隧道。',
      'snapshot-too-large':'共享网关状态超过传输上限，界面已断开；这不代表网关停止。请使用新版网关后重新连接。',
      'timeout':'共享网关状态查询超时，无法确认它是否仍在运行。请重新连接检查；未重发任何操作。',
      'unsafe-socket':'共享网关端点的权限或所有者检查未通过，未接管该实例。'
    };
    emit({type:'sharedDisconnected',reason,message:messages[reason]??'共享连接已断开，无法确认网关是否仍在运行。点击重新连接 / 启动检查；不会自动重发操作。'});
    closing=true; process.exitCode=1; process.stdin.destroy(); clearInterval(timer);
  }
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
