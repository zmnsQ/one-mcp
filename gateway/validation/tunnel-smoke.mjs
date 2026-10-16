import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {TunnelManager} from '../dist/tunnels.js';
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'om-tunnel-'));
const events=[];const manager=new TunnelManager(19871,e=>events.push(e),()=>false);
const executable=path.join(dir,'fixture');
await fs.writeFile(executable,'#!/bin/sh\ncase "$1" in\n doctor) exit 0;;\n run) while true; do sleep 1; done;;\n *) exit 2;;\nesac\n',{mode:0o700});
const target={key:'aggregate',action:'doctor',executable,profile:'fixture',tunnelID:'tunnel_fixture',runtimeKey:'secret-test-value'};
try {
 await manager.action(target);
 for(let i=0;i<100&&!events.some(e=>e.exitCode===0);i++)await new Promise(r=>setTimeout(r,20));
 assert.ok(events.some(e=>e.action==='doctor'&&e.exitCode===0));assert.ok(!JSON.stringify(events).includes(target.runtimeKey));
 const capture=path.join(dir,'argv.json');
 await fs.writeFile(path.join(dir,'foo.prod.yaml'),'control_plane: {}\n');
 const fileFixture=path.join(dir,'file-fixture');
 await fs.writeFile(fileFixture,`#!/bin/sh\nprintf '%s\\n' "$@" > '${capture}'\nexit 0\n`,{mode:0o700});
 await manager.action({...target,executable:fileFixture,profile:'foo.prod',profileFile:path.join(dir,'foo.prod.yaml')});
 for(let i=0;i<100;i++){try{if((await fs.readFile(capture,'utf8')).includes('--profile-file'))break;}catch{}await new Promise(r=>setTimeout(r,20));}
 assert.ok((await fs.readFile(capture,'utf8')).includes('--profile-file\n'+path.join(dir,'foo.prod.yaml')));
 await manager.stopAll();
 await assert.rejects(manager.action({...target,key:'backend',action:'run'}));
 await assert.rejects(manager.action({...target,action:'init',profileFile:'/tmp/existing-profile.yaml'}));
 await manager.action({...target,action:'run'});await assert.rejects(manager.action({...target,action:'run'}));
 assert.equal(manager.snapshot().at(-1).ready,false);
 await manager.stopAll();assert.equal(manager.snapshot().at(-1).running,false);
 console.log('PASS tunnel subprocess doctor completion, secret suppression, backend guard, existing-profile init refusal, duplicate start refusal and stop');
}finally{await manager.stopAll();await fs.rm(dir,{recursive:true,force:true});}
