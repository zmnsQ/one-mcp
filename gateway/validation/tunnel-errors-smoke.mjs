import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {TunnelManager,profileLocationEnvironment,profileSelection} from '../dist/tunnels.js';
import {safeTunnelError,classifyTunnelDiagnostic} from '../dist/tunnel-errors.js';
assert.deepEqual(profileLocationEnvironment({TUNNEL_CLIENT_PROFILE_DIR:'/profiles',XDG_CONFIG_HOME:'/config',CONTROL_PLANE_API_KEY:'SECRET',OPENAI_API_KEY:'SECRET'}),{TUNNEL_CLIENT_PROFILE_DIR:'/profiles',XDG_CONFIG_HOME:'/config'});
assert.deepEqual(profileLocationEnvironment({TUNNEL_CLIENT_PROFILE_DIR:'relative',XDG_CONFIG_HOME:'bad\0'}),{});
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'om-profile-'));
const events=[];const manager=new TunnelManager(19872,e=>events.push(e),()=>false);
const executable=path.join(dir,'fixture'),profileFile=path.join(dir,'existing.yaml');
await fs.writeFile(profileFile,'control_plane:\n  api_key: file:/existing/credential\n');
await fs.writeFile(executable,'#!/bin/sh\n[ "${CONTROL_PLANE_API_KEY+x}" = x ] && exit 9\ncase "$1" in\n doctor) exit 0;;\n run) while true; do sleep 1; done;;\n *) exit 0;;\nesac\n',{mode:0o700});
const target={key:'aggregate',action:'doctor',executable,profile:'existing',profileFile,tunnelID:'tunnel_fixture',runtimeKey:''};
const fails=async(change,code)=>assert.rejects(manager.action({...target,...change}),new RegExp('\\['+code+'\\]'));
try{
 await manager.action(target);
 for(let i=0;i<100&&!events.some(e=>e.exitCode===0);i++)await new Promise(r=>setTimeout(r,10));
 assert.ok(events.some(e=>e.action==='doctor'&&e.exitCode===0));
 await manager.action({...target,action:'run'});assert.equal(manager.snapshot().at(-1).running,true);await manager.stopAll();
 for (const blank of ['', '   ']) {
  const before=events.length;await manager.action({...target,profileFile:blank});
  for(let i=0;i<100&&!events.slice(before).some(e=>e.exitCode===0);i++)await new Promise(r=>setTimeout(r,10));
  assert.ok(events.slice(before).some(e=>e.exitCode===0));assert.ok(events.slice(before).some(e=>e.type==='tunnelProfile'&&e.profileMode==='named'));
 }
 assert.deepEqual(profileSelection('example',undefined,{HOME:'/users/test',XDG_CONFIG_HOME:'/xdg',TUNNEL_CLIENT_PROFILE_DIR:'/profiles'}),{profileMode:'named',profileLocation:'/profiles/example.yaml',profileLocationSource:'TUNNEL_CLIENT_PROFILE_DIR'});
 assert.equal(profileSelection('example',undefined,{HOME:'/users/test',XDG_CONFIG_HOME:'/xdg'}).profileLocation,'/xdg/tunnel-client/example.yaml');
 assert.equal(profileSelection('example',undefined,{HOME:'/users/test'}).profileLocation,'/users/test/.config/tunnel-client/example.yaml');
 assert.equal(classifyTunnelDiagnostic('profile config not found'),'TUNNEL_PROFILE_LOOKUP');
 console.log('PASS empty optional profile-file uses named profile; official profile lookup precedence and error origin separation');
 await fails({tunnelID:''},'TUNNEL_ID');await fails({profileFile:undefined,profile:'bad/name'},'TUNNEL_PROFILE');
 await fails({executable:'/missing/client'},'TUNNEL_EXECUTABLE');await fails({profileFile:'/missing/profile'},'TUNNEL_PROFILE_FILE');
 await fails({runtimeKey:'bad\0'},'TUNNEL_KEY_FORMAT');await fails({key:'backend'},'TUNNEL_BACKEND');await fails({action:'init'},'TUNNEL_EXISTING_INIT');
 const diagnostic=path.join(dir,'diagnostic');await fs.writeFile(diagnostic,'#!/bin/sh\necho "CONTROL_PLANE_API_KEY required SECRET_FIXTURE_VALUE" >&2\nexit 1\n',{mode:0o700});
 await manager.action({...target,executable:diagnostic});
 for(let i=0;i<100&&!events.some(e=>e.errorCode==='TUNNEL_KEY_REQUIRED');i++)await new Promise(r=>setTimeout(r,10));
 assert.ok(events.some(e=>e.errorCode==='TUNNEL_KEY_REQUIRED'));assert.ok(!JSON.stringify(events).includes('SECRET_FIXTURE_VALUE'));
 assert.equal(safeTunnelError(Error('[TUNNEL_ID] secret injected')).includes('secret'),false);
 assert.equal(classifyTunnelDiagnostic('unauthorized status:401'),'TUNNEL_AUTH');
 console.log('PASS existing-profile doctor/run omit empty key env; field-specific preflight; fixed diagnostic classification and secret suppression (official client mocked)');
}finally{await manager.stopAll();await fs.rm(dir,{recursive:true,force:true});}
