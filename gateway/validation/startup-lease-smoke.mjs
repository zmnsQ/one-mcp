// Protocol fixture, not Unix-socket or native GUI integration.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {workspace,writeConfiguration,defaults,lockInfo,acquireLease} from '../dist/configuration.js';
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'onemcp-startup-'));
let child;
try {
 const root=path.join(dir,'home');await fs.mkdir(root,{mode:0o700});let w=await workspace(root);await writeConfiguration(w,defaults(),'missing');
 await fs.cp(path.resolve('dist'),path.join(dir,'dist'),{recursive:true});await fs.symlink(path.resolve('node_modules'),path.join(dir,'node_modules'));await fs.writeFile(path.join(dir,'package.json'),'{"type":"module"}');
 await fs.writeFile(path.join(dir,'dist/index.js'),`import fs from 'node:fs';const marker=process.argv[process.argv.indexOf('--control-socket')+1];fs.writeFileSync(${JSON.stringify(path.join(dir,'started'))},'yes');setTimeout(()=>{fs.writeFileSync(marker,'protocol-fixture');console.log(JSON.stringify({type:'ready'}))},500);process.stdin.once('data',()=>{fs.unlinkSync(marker);process.exit(0)});`);
 child=spawn(process.execPath,[path.join(dir,'dist/cli.js'),'gateway','run','--apply','--home',root,'--json'],{stdio:['ignore','pipe','pipe']});child.stdout.resume();child.stderr.resume();
 const wait=async check=>{for(let i=0;i<200;i++){if(await check())return;await new Promise(r=>setTimeout(r,10));}throw Error('fixture timeout');};
 await wait(async()=>fs.stat(path.join(dir,'started')).then(()=>true,()=>false));
 assert.equal((await lockInfo(root)).locked,true);await assert.rejects(acquireLease(root),/busy/);
 await wait(async()=>!(await lockInfo(root)).locked);assert.equal(child.exitCode,null);
 w=await workspace(root);await writeConfiguration(w,{...w.config,port:19994},w.revision);
 const exited=new Promise(yes=>child.once('exit',yes));child.kill('SIGTERM');assert.equal(await exited,0);
 console.log('PASS startup transaction excludes other writers until ready, then releases during live child (protocol mock only)');
}finally{child?.kill('SIGKILL');await fs.rm(dir,{recursive:true,force:true});}
