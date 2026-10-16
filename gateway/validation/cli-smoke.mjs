import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawn,execFileSync} from 'node:child_process';
import {workspace,writeConfiguration,acquireLease,importCandidates,defaults} from '../dist/configuration.js';
import {controlRequest} from '../dist/control.js';
const home=await fs.mkdtemp(path.join(os.tmpdir(),'omcp-'));
const cli=path.resolve('dist/cli.js');
const run=(...args)=>JSON.parse(execFileSync(process.execPath,[cli,...args,'--home',home,'--json'],{encoding:'utf8'}));
let gateway;
try{
 assert.equal(run('config','validate').result.revision,'missing');
 assert.equal(run('config','init').result.preview,true);
 await assert.rejects(fs.stat(path.join(home,'settings.json')));
 run('config','init','--apply','--expect-revision','missing');
 const w=await workspace(home);assert.equal(w.config.servers.length,0);
 const release=await acquireLease(home);
 assert.throws(()=>run('config','set','--field','port','--value','18978','--apply','--expect-revision',w.revision));await release();
 console.log('PASS preview is non-mutating; cross-process config lock rejects writers');
 await assert.rejects(writeConfiguration(w,w.config,'wrong'));
 const next=await writeConfiguration(w,{...w.config,port:18978},w.revision);
 assert.notEqual(next,w.revision);assert.equal((await fs.stat(w.path)).mode&0o777,0o600);
 console.log('PASS revision conflict and atomic private config write');
 const imported=importCandidates({mcpServers:{test:{command:process.execPath,args:[],env:{MY_SECRET:'never-output'}}}},defaults());
 assert.deepEqual(imported.candidates[0].environmentKeys,['MY_SECRET']);assert.ok(!JSON.stringify(imported).includes('never-output'));
 assert.throws(()=>importCandidates({mcpServers:{bad:{command:process.execPath,args:['--token','secret-value']}}},defaults()));
 console.log('PASS import discards credentials, denies tools, rejects secret arguments');
 if(process.env.ONEMCP_SKIP_SOCKET_TEST==='1'){console.log('SKIP Unix-socket integration: explicitly disabled by sandbox test runner');} else {
 gateway=spawn(process.execPath,[cli,'gateway','run','--apply','--home',home],{stdio:['ignore','pipe','pipe']});
 const socket=path.join(home,'Runtime','control.sock');let status,lastError,spawnError;
 let diagnostics='';
 const capture=chunk=>{diagnostics=(diagnostics+chunk.toString()).slice(-4096);};
 gateway.stdout.on('data',capture);gateway.stderr.on('data',capture);
 gateway.on('error',error=>{spawnError=error;});
 for(let n=0;n<100;n++){
  if(spawnError||gateway.exitCode!==null||gateway.signalCode!==null)break;
  try{status=await controlRequest(socket,'status');break;}catch(error){lastError=error;await new Promise(r=>setTimeout(r,50));}
 }
 assert.ok(status,`Gateway IPC startup failed (exit=${gateway.exitCode}, signal=${gateway.signalCode}): ${spawnError?.message||lastError?.message||'no status response'}. Child output: ${diagnostics.trim()}. If this runner forbids Unix sockets, explicitly set ONEMCP_SKIP_SOCKET_TEST=1 and report IPC as unverified.`);
 assert.equal(status.workspaceID,'default');assert.equal((await fs.stat(socket)).mode&0o777,0o600);
 assert.equal(run('status').result.runtime.workspaceID,'default');
 assert.equal(run('gateway','stop').result.preview,true);
 console.log('PASS CLI and gateway share private IPC; runtime status and stop preview');
 await controlRequest(socket,'shutdown');
 await new Promise((yes,no)=>{gateway.once('exit',code=>code===0?yes():no(Error('exit')));setTimeout(()=>no(Error('shutdown timeout')),10000).unref();});gateway=undefined;
 await assert.rejects(fs.stat(socket));console.log('PASS shared gateway shutdown removes own socket');
 }
}finally{gateway?.kill('SIGTERM');await fs.rm(home,{recursive:true,force:true});}
