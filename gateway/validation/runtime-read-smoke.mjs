import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {createInterface} from 'node:readline';
import {once} from 'node:events';
const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r));
const child=spawn(process.execPath,['dist/index.js','--port',String(port)],{stdio:['pipe','pipe','pipe']});
const pending=new Map();let id=0,ready;const started=new Promise(r=>ready=r);
createInterface({input:child.stdout}).on('line',line=>{const e=JSON.parse(line);if(e.type==='ready')ready();if(e.type==='response')pending.get(e.id)?.(e);});child.stderr.resume();
const rpc=(method,params={})=>new Promise((resolve,reject)=>{const key=String(++id),timer=setTimeout(()=>reject(Error('test timeout')),12000);pending.set(key,e=>{pending.delete(key);clearTimeout(timer);e.ok?resolve(e.result):reject(Error(e.error));});child.stdin.write(JSON.stringify({id:key,method,params})+'\n');});
try {
 await started;
 // Long initialization occupies the mutation queue, but the gateway is alive.
 const slow=rpc('startServer',{server:{id:'slow',name:'slow fixture',executable:process.execPath,arguments:['--input-type=module','-e',"setTimeout(()=>process.exit(0),3000);process.stdin.resume()"],environment:{},allowedTools:[]}}).catch(()=>{});
 await new Promise(r=>setTimeout(r,150));
 const result=await Promise.race([rpc('snapshot'),new Promise((_,reject)=>setTimeout(()=>reject(Error('snapshot blocked behind mutation')),1000))]);
 assert.equal(result.port,port);assert.equal((await rpc('status')).instanceID,result.instanceID);
 await slow;const exited=once(child,'exit');await rpc('shutdown');await exited;
 console.log('PASS status/snapshot stay responsive during a slow mutation; mutation remains serialized (real gateway subprocess)');
}finally{if(child.exitCode===null)child.kill('SIGTERM');}
