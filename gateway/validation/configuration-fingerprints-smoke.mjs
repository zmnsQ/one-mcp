import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, execFileSync } from 'node:child_process';
import { createServer } from 'node:net';
import { createInterface } from 'node:readline';
import { configurationFingerprint, serverConfigurationFingerprints, tunnelConfigurationFingerprints, gatewayConfigurationFingerprints } from '../dist/configuration-fingerprints.js';
import { defaults, workspace, writeConfiguration } from '../dist/configuration.js';

const fixture = JSON.parse(await fs.readFile(new URL('./configuration-fingerprint-vectors.json', import.meta.url), 'utf8'));
for (const vector of fixture.vectors) assert.equal(configurationFingerprint(vector.values), vector.sha256, vector.label);
assert.notEqual(configurationFingerprint([]), configurationFingerprint(['']));
assert.notEqual(configurationFingerprint(['a', 'bc']), configurationFingerprint(['ab', 'c']));

const server = {name:'工具🧪',executable:'/usr/bin/node',arguments:['/tmp/mock.mjs','a:b'],environment:{B:'first-secret',A:'second-secret'},allowedTools:['é','e\u0301','🧪','\ue000','a']};
const serverPrints = serverConfigurationFingerprints(server);
assert.equal(serverPrints.allowedTools, fixture.vectors.find(v => v.label === 'utf8-sorted-set').sha256);
assert.deepEqual(serverConfigurationFingerprints({...server,workingDirectory:'',environment:{A:'new-value',B:'different-value'},allowedTools:[...server.allowedTools].reverse().concat('a')}),serverPrints);
assert.notEqual(serverConfigurationFingerprints({...server,arguments:[...server.arguments].reverse()}).arguments,serverPrints.arguments);
for (const [key,value] of Object.entries({name:'Renamed',executable:'/different/node',arguments:['different'],workingDirectory:'/different',allowedTools:['different']})) {
    const changed = serverConfigurationFingerprints({...server,[key]:value});
    assert.deepEqual(Object.keys(changed).filter(k => changed[k] !== serverPrints[k]), [key]);
}
assert.deepEqual(Object.keys(serverConfigurationFingerprints({...server,environment:{C:'secret'}})).filter(k => serverConfigurationFingerprints({...server,environment:{C:'secret'}})[k] !== serverPrints[k]), ['environmentKeys']);
assert.deepEqual(serverConfigurationFingerprints({...server,id:'another-id',profile:'another-profile',tunnelID:'tunnel_other'}),serverPrints);

const target = {executable:'/tmp/client',profile:'named',tunnelID:'tunnel_fixture'};
const endpoint = 'http://127.0.0.1:8787/mcp';
assert.deepEqual(tunnelConfigurationFingerprints(target,endpoint),tunnelConfigurationFingerprints({...target,profileFile:' \n\t'},endpoint));
assert.deepEqual(tunnelConfigurationFingerprints({...target,profileFile:'/tmp/existing.yaml'},endpoint),tunnelConfigurationFingerprints({...target,profile:'ignored-name',profileFile:'/tmp/existing.yaml',runtimeKey:'different-secret'},endpoint));
for (const [key,value] of Object.entries({executable:'/other/client',profile:'other',tunnelID:'tunnel_other',profileFile:'/tmp/file'})) {
    assert.notDeepEqual(tunnelConfigurationFingerprints({...target,[key]:value},endpoint),tunnelConfigurationFingerprints(target,endpoint));
}
assert.notEqual(tunnelConfigurationFingerprints(target,endpoint).endpoint,tunnelConfigurationFingerprints(target,endpoint+'/changed').endpoint);
console.log('PASS stable cross-language fingerprints, Unicode/escaping, field isolation, set ordering, effective defaults, ignored fields and no credential-value hashes');

if (process.argv.includes('--pure')) process.exit(0);

const root = await fs.mkdtemp(path.join(os.tmpdir(),'onemcp-applied-config-'));
let child;
let lines;
const requests = new Map();
const events = [];
let seq = 0;
try {
    await fs.symlink(process.execPath,path.join(root,'node-alias'));
    assert.deepEqual(gatewayConfigurationFingerprints(process.execPath,path.resolve('dist/index.js'),8787),gatewayConfigurationFingerprints(path.join(root,'node-alias'),path.resolve('dist/../dist/index.js'),8787));
    const probe = createServer();
    await new Promise(resolve => probe.listen(0,'127.0.0.1',resolve));
    const port = probe.address().port;
    await new Promise(resolve => probe.close(resolve));
    const executable = path.join(root,'tunnel-fixture');
    await fs.writeFile(executable,'#!/bin/sh\nwhile true; do sleep 1; done\n',{mode:0o700});
    const savedServer = {id:'applied',name:'Applied',executable:process.execPath,arguments:[path.resolve('validation/mock-server.mjs')],workingDirectory:'',environmentKeys:['EXPLICIT_FIXTURE_KEY'],allowedTools:['echo'],tunnelID:'',profile:''};
    const saved = {...defaults(),gatewayScript:path.resolve('dist/index.js'),port,tunnelClientPath:executable,aggregateProfile:'fixture',aggregateTunnelID:'tunnel_fixture',servers:[savedServer]};
    await writeConfiguration(await workspace(root),saved,'missing');
    child = spawn(process.execPath,['dist/index.js','--port',String(port)],{stdio:['pipe','pipe','pipe'],env:{...process.env,INHERITED_FIXTURE_KEY:'inherited-private-value'}});
    const exited = new Promise(resolve => child.once('exit',resolve));
    let ready;
    const readyPromise = new Promise(resolve => {ready = resolve;});
    lines = createInterface({input:child.stdout});
    lines.on('line',line => {
        const event = JSON.parse(line);
        events.push(event);
        if (event.type === 'ready') ready(event);
        if (event.type === 'response') requests.get(event.id)?.(event);
    });
    let stderr = '';
    child.stderr.on('data',chunk => {stderr = (stderr+chunk).slice(-2000);});
    const timeout = setTimeout(() => ready({failed:true}),15000);
    const readyEvent = await Promise.race([readyPromise,exited.then(code => ({failed:true,code}))]);
    clearTimeout(timeout);
    assert.equal(readyEvent.failed,undefined,`Gateway failed to start: ${stderr}`);
    const rpc = (method,params={}) => new Promise((resolve,reject) => {
        const id = 'fingerprints-'+(++seq);
        const timer = setTimeout(() => {requests.delete(id);reject(Error('RPC timeout: '+method));},20000);
        requests.set(id,event => {clearTimeout(timer);requests.delete(id);event.ok?resolve(event.result):reject(Error(event.error));});
        child.stdin.write(JSON.stringify({id,method,params})+'\n');
    });
    const serverPayload = config => ({...config,environment:{EXPLICIT_FIXTURE_KEY:'explicit-private-value'}});
    const tunnelPayload = config => ({key:'aggregate',action:'run',executable:config.tunnelClientPath,profile:config.aggregateProfile,tunnelID:config.aggregateTunnelID,runtimeKey:'tunnel-private-value'});
    await rpc('startServer',{server:serverPayload(savedServer)});
    await rpc('tunnelAction',tunnelPayload(saved));
    const initial = await rpc('snapshot');
    assert.deepEqual(initial.configurationFingerprints,readyEvent.configurationFingerprints);
    assert.equal(initial.configurationFingerprintVersion,1);
    assert.deepEqual(initial.servers[0].configurationFingerprints,serverConfigurationFingerprints(serverPayload(savedServer)));
    assert.deepEqual(events.find(e => e.type === 'serverStatus' && e.status === 'running').configurationFingerprints,initial.servers[0].configurationFingerprints);
    assert.equal(events.find(e => e.type === 'serverStatus' && e.status === 'running').name,savedServer.name);
    assert.deepEqual(events.find(e => e.type === 'serverStatus' && e.status === 'running').allowedTools,savedServer.allowedTools);
    assert.equal(initial.servers[0].configurationFingerprints.environmentKeys,configurationFingerprint(['EXPLICIT_FIXTURE_KEY']));
    assert.equal(initial.tunnels[0].running,true);
    assert.deepEqual(initial.tunnels[0].configurationFingerprints,tunnelConfigurationFingerprints(tunnelPayload(saved),`http://127.0.0.1:${port}/mcp`));
    const marker = events.length;
    const saveCLI = async (...args) => {
        const current = await workspace(root);
        const output = JSON.parse(execFileSync(process.execPath,['dist/cli.js','config',...args,'--home',root,'--expect-revision',current.revision,'--apply','--json'],{encoding:'utf8'}));
        assert.equal(output.result.effect,'saved-only');
        assert.equal(output.result.runtimeChanged,false);
    };
    await saveCLI('allow-tools','--id','applied','--names','none');
    await saveCLI('set','--field','aggregateProfile','--value','updated-fixture');
    await saveCLI('set','--field','port','--value',String(port === 65535 ? port-1 : port+1));
    await saveCLI('set','--field','mode','--value','individual');
    const current = (await workspace(root)).config;
    const unchanged = await rpc('snapshot');
    assert.equal(unchanged.pid,initial.pid);
    assert.equal(unchanged.instanceID,initial.instanceID);
    assert.equal(unchanged.port,port);
    assert.deepEqual(unchanged.configurationFingerprints,initial.configurationFingerprints);
    assert.deepEqual(unchanged.servers[0].configurationFingerprints,initial.servers[0].configurationFingerprints);
    assert.deepEqual(unchanged.servers[0].allowedTools,['echo']);
    assert.deepEqual(unchanged.tunnels[0].configurationFingerprints,initial.tunnels[0].configurationFingerprints);
    assert.equal(unchanged.servers[0].running,true);
    assert.equal(unchanged.tunnels[0].running,true);
    assert.equal(events.slice(marker).some(e => e.type === 'serverStatus' || (e.type === 'tunnelStatus' && !e.running)),false);
    assert.notEqual(serverConfigurationFingerprints(serverPayload(current.servers[0])).allowedTools,unchanged.servers[0].configurationFingerprints.allowedTools);
    assert.notEqual(tunnelConfigurationFingerprints(tunnelPayload(current),`http://127.0.0.1:${port}/mcp`).profile,unchanged.tunnels[0].configurationFingerprints.profile);
    assert.notEqual(gatewayConfigurationFingerprints(current.nodePath,current.gatewayScript,current.port).port,unchanged.configurationFingerprints.port);
    assert.doesNotMatch(JSON.stringify(unchanged),/explicit-private-value|inherited-private-value|tunnel-private-value/);
    console.log('PASS real CLI saved changes preserve running gateway PID, server allowlist, tunnel and frozen applied fingerprints; only desired values differ');
    await rpc('stopServer',{serverId:'applied'});
    await rpc('startServer',{server:serverPayload(current.servers[0])});
    await rpc('tunnelAction',tunnelPayload(current));
    const restarted = await rpc('snapshot');
    assert.deepEqual(restarted.servers[0].configurationFingerprints,serverConfigurationFingerprints(serverPayload(current.servers[0])));
    assert.deepEqual(restarted.servers[0].allowedTools,[]);
    assert.deepEqual(restarted.tunnels[0].configurationFingerprints,tunnelConfigurationFingerprints(tunnelPayload(current),`http://127.0.0.1:${port}/mcp`));
    assert.deepEqual(restarted.configurationFingerprints,initial.configurationFingerprints,'server/tunnel restart must not change gateway startup settings');
    await rpc('shutdown');
    assert.equal(await exited,0);
    console.log('PASS explicit server/tunnel restart adopts changed settings while gateway startup port stays unchanged (real stdin transport)');
} finally {
    lines?.close();
    if (child?.exitCode === null) child.kill('SIGTERM');
    await fs.rm(root,{recursive:true,force:true});
}
