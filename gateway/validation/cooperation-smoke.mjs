import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawn,execFileSync} from 'node:child_process';
import {createInterface} from 'node:readline';
import {pathToFileURL} from 'node:url';
import {workspace,writeConfiguration,defaults,acquireLease,lockInfo,recoverLock} from '../dist/configuration.js';
const root=await fs.mkdtemp(path.join(os.tmpdir(),'onemcp-cooperate-'));
const moduleURL=pathToFileURL(path.resolve('dist/configuration.js')).href;
let peer;
try {
 let w=await workspace(root);await writeConfiguration(w,defaults(),'missing');w=await workspace(root);
 // Simulates a GUI's long-lived open editor, using the actual shared writer in another process.
 peer=spawn(process.execPath,['--input-type=module','-e',`import {workspace,writeConfiguration} from ${JSON.stringify(moduleURL)};const w=await workspace(process.argv[1]);console.log('OPEN');process.stdin.once('data',async()=>{try{await writeConfiguration(w,{...w.config,port:19992},w.revision);console.log('BAD_WRITE')}catch(e){console.log('CONFLICT:'+e.message)}process.exit()});`,root],{stdio:['pipe','pipe','pipe']});
 const lines=createInterface({input:peer.stdout});const iterator=lines[Symbol.asyncIterator]();
 assert.equal((await iterator.next()).value,'OPEN');
 assert.equal((await lockInfo(root)).locked,false);
 const result=JSON.parse(execFileSync(process.execPath,['dist/cli.js','config','set','--field','port','--value','19991','--expect-revision',w.revision,'--apply','--home',root,'--json'],{encoding:'utf8'}));
 assert.equal(result.result.effect,'saved-only');assert.equal(result.result.runtimeChanged,false);
 peer.stdin.write('save');assert.match((await iterator.next()).value,/^CONFLICT:Configuration changed/);
 assert.equal((await workspace(root)).config.port,19991);console.log('PASS open editor permits CLI transaction; stale editor cannot overwrite external changes');
 const release=await acquireLease(root);await assert.rejects(acquireLease(root),/busy/);const live=await lockInfo(root);await assert.rejects(recoverLock(root,live.token),/alive/);await release();
 console.log('PASS concurrent writer exclusion and live-lock recovery refusal');
 await fs.mkdir(path.join(root,'.configuration-lock'),{mode:0o700});await fs.writeFile(path.join(root,'.configuration-lock','owner.json'),JSON.stringify({pid:2147483647,token:'dead-fixture-owner'}),{mode:0o600});
 await assert.rejects(recoverLock(root,'wrong-token'),/changed/);await recoverLock(root,'dead-fixture-owner');assert.equal((await lockInfo(root)).locked,false);
 console.log('PASS dead-owner recovery requires matching token');
 // Existing runtime marker is not deleted or contacted by a saved-only configuration operation.
 await fs.mkdir(path.join(root,'Runtime'),{mode:0o700});const marker=path.join(root,'Runtime','control.sock');await fs.writeFile(marker,'fixture-not-a-real-socket');
 w=await workspace(root);await writeConfiguration(w,{...w.config,port:19993},w.revision);
 assert.equal(await fs.readFile(marker,'utf8'),'fixture-not-a-real-socket');assert.equal((await lockInfo(root)).locked,false);
 console.log('PASS saved-only write retains runtime marker and releases transaction lease (not a socket integration test)');
} finally {peer?.kill();await fs.rm(root,{recursive:true,force:true});}
