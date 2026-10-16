import {randomUUID} from 'node:crypto';
import {tunnelErrors} from './tunnel-errors.js';
export type ConnectionEvent={id:string;time:string;category:string;level:string;code:string;message:string;action?:string;running?:boolean;ready?:boolean;exitCode?:number;toolCount?:number};
// Explicit projection: arbitrary subprocess strings, identifiers and config never enter this journal.
export class ConnectionJournal {
 private records:ConnectionEvent[]=[];
 private previous=new Map<string,string>();
 snapshot(){return this.records.map(r=>({...r}));}
 record(value:unknown):ConnectionEvent|undefined {
  if(!value||typeof value!=='object')return;const e=value as Record<string,unknown>;
  let row:Omit<ConnectionEvent,'id'|'time'>|undefined;
  if(e.type==='ready')row={category:'gateway',level:'info',code:'GATEWAY_READY',message:'本地网关已启动；远端连接尚需验证。'};
  if(e.type==='tools'&&Array.isArray(e.tools))row={category:'discovery',level:'info',code:'TOOLS_DISCOVERED',message:'已获取上游工具目录；发布范围仍由白名单决定。',toolCount:e.tools.length};
  if(e.type==='serverStatus'&&typeof e.status==='string'&&['starting','running','stopped','error','ready'].includes(e.status))row={category:'server',level:e.status==='error'?'error':'info',code:'SERVER_'+e.status.toUpperCase(),message:({starting:'MCP 服务正在启动。',running:'MCP 服务正在运行。',ready:'MCP 服务已就绪。',stopped:'MCP 服务已停止。',error:'MCP 服务发生错误，请检查服务配置。'} as Record<string,string>)[e.status] ?? 'MCP 状态已更新。'};
  if(e.type==='tunnelStatus'){
   const code=typeof e.errorCode==='string'&&Object.hasOwn(tunnelErrors,e.errorCode)?e.errorCode:undefined;
   row={category:'tunnel',level:code||(typeof e.exitCode==='number'&&e.exitCode!==0)?'error':'info',code:code??'TUNNEL_STATE',message:code?tunnelErrors[code as keyof typeof tunnelErrors]:'官方隧道操作状态已更新。'};
   if(['init','doctor','run'].includes(String(e.action)))row.action=String(e.action);
   if(typeof e.running==='boolean')row.running=e.running;
   if(typeof e.ready==='boolean')row.ready=e.ready;
   if(Number.isSafeInteger(e.exitCode))row.exitCode=e.exitCode as number;
  }
  if(e.type==='response'&&e.ok===false){
   const code=typeof e.error==='string'?e.error.match(/^\[(TUNNEL_[A-Z_]+)\]/)?.[1]:undefined;
   row=code&&Object.hasOwn(tunnelErrors,code)?{category:'tunnel',level:'error',code,message:tunnelErrors[code as keyof typeof tunnelErrors]}:{category:'gateway',level:'error',code:'CONTROL_OPERATION_FAILED',message:'管理操作未完成，请检查当前配置与进程状态。'};
  }
  if(!row)return;
  const signature=JSON.stringify(row);const scope=String(e.type)+':'+String(e.key??e.serverId??'');
  if(e.type!=='response'&&this.previous.get(scope)===signature)return;
  if(this.previous.size>=128)this.previous.clear();this.previous.set(scope,signature);
  const record={id:randomUUID(),time:new Date().toISOString(),...row};this.records.push(record);if(this.records.length>200)this.records.shift();return {...record};
 }
}
