/** Explicit-start preflight. Caller must hold the shared configuration/startup lease. */
import fs from 'node:fs/promises';
import net from 'node:net';
import {randomUUID} from 'node:crypto';
import {checkSocket} from './control.js';
type SocketIdentity={dev:number;ino:number};
export type RuntimeSocketIO={
  stat:()=>Promise<SocketIdentity>;check:()=>Promise<void>;
  reachable:()=>Promise<boolean>;preserve:(destination:string)=>Promise<void>;
};
export async function prepareRuntimeSocket(path:string, injected?:RuntimeSocketIO):Promise<'available'|'existing'> {
  const io:RuntimeSocketIO=injected??{
    stat:()=>fs.lstat(path),check:()=>checkSocket(path),preserve:destination=>fs.rename(path,destination),
    reachable:()=>new Promise<boolean>((resolve,reject)=>{
      const socket=net.createConnection(path);let settled=false;
      const done=(error?:Error,result=false)=>{if(settled)return;settled=true;socket.destroy();error?reject(error):resolve(result);};
      socket.once('connect',()=>done(undefined,true));
      socket.once('error',error=>{
        if((error as NodeJS.ErrnoException).code==='ECONNREFUSED')done(undefined,false);
        else done(error);
      });
      socket.setTimeout(1500,()=>done(new Error('Gateway socket probe timed out; no recovery performed')));
    })
  };
  try { await io.stat(); } catch(error) {
    if((error as NodeJS.ErrnoException).code==='ENOENT') return 'available';
    throw error;
  }
  // Never rename regular files, symlinks, or another user's/socket's unsafe directory.
  await io.check();
  const before=await io.stat();
  if(await io.reachable())return 'existing';
  await io.check();
  const after=await io.stat();
  if(before.dev!==after.dev || before.ino!==after.ino)throw new Error('Gateway socket changed; no recovery performed');
  // Preserve the dead socket for inspection. A listening or uncertain socket is never moved.
  // Cooperative launchers hold the same lease, and serveControl never replaces an existing path.
  await io.preserve(`${path}.stale-${randomUUID()}`);
  return 'available';
}
