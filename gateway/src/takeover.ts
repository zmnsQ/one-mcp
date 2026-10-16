import fs from 'node:fs/promises';
import {join} from 'node:path';
import {checkSocket,controlRequest} from './control.js';
export type LegacyCandidate={pid:number;port:number;workspaceID:string;dev:number;ino:number};
export function validLegacy(s:unknown,workspace:string):s is LegacyCandidate {
 const x=s as LegacyCandidate & {protocolVersion?:unknown;servers?:unknown;tunnels?:unknown};
 return !!x && x.protocolVersion===undefined && x.workspaceID===workspace && Number.isInteger(x.pid)&&x.pid>1&&Number.isInteger(x.port)&&x.port>=1024&&x.port<=65535&&Array.isArray(x.servers)&&Array.isArray(x.tunnels);
}
export async function inspectLegacy(root:string,workspace:string):Promise<LegacyCandidate>{
 const path=join(root,'Runtime','control.sock');await checkSocket(path);const before=await fs.lstat(path);
 const s=await controlRequest(path,'status',{},before);
 const after=await fs.lstat(path);
 if(before.dev!==after.dev||before.ino!==after.ino||!validLegacy(s,workspace))throw new Error('Not a verified legacy gateway');
 process.kill(s.pid,0); // No signal is sent; unknown/permission-denied owners fail closed.
 return {pid:s.pid,port:s.port,workspaceID:s.workspaceID,dev:before.dev,ino:before.ino};
}
export type TakeoverIO={inspect:()=>Promise<LegacyCandidate>;shutdown:(c:LegacyCandidate)=>Promise<void>;socketAbsent:()=>Promise<boolean>;processDead:(pid:number)=>boolean;wait:()=>Promise<void>};
export async function stopLegacy(root:string,workspace:string,expected:LegacyCandidate, testIO?:TakeoverIO){
 const path=join(root,'Runtime','control.sock');
 const io:TakeoverIO=testIO??{
  inspect:()=>inspectLegacy(root,workspace),shutdown:async c=>{await controlRequest(path,'shutdown',{},c);},
  socketAbsent:async()=>{try{await fs.lstat(path);return false;}catch(e){return (e as NodeJS.ErrnoException).code==='ENOENT';}},
  processDead:pid=>{try{process.kill(pid,0);return false;}catch(e){return (e as NodeJS.ErrnoException).code==='ESRCH';}},
  wait:()=>new Promise(r=>setTimeout(r,100))
 };
 const current=await io.inspect();
 if(!expected || (['pid','port','workspaceID','dev','ino'] as const).some(k=>current[k]!==expected[k]))throw new Error('Legacy gateway changed; inspect again');
 await io.shutdown(current);
 for(let i=0;i<100;i++){
  if(await io.socketAbsent() && io.processDead(current.pid))return;
  await io.wait();
 }
 throw new Error('Old gateway exit was not confirmed; no replacement started');
}
