#!/usr/bin/env node
// Read-only packaging check. Does not start listeners, MCP servers, or a tunnel.
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {execFileSync} from 'node:child_process';
const root=path.resolve(process.argv[2]||'gateway');
for(const file of ['dist/tunnel-errors.js','dist/takeover-command.js','dist/takeover.js','dist/runtime-bridge.js','dist/runtime-client.js','dist/index.js','dist/cli.js','package.json','node_modules/@modelcontextprotocol/sdk/package.json','node_modules/zod/package.json']){
 if(!fs.statSync(path.join(root,file)).isFile())throw Error(`Missing gateway component: ${file}`);
}
const require=createRequire(pathToFileURL(path.join(root,'dist/index.js')));
for(const module of ['@modelcontextprotocol/sdk/client/index.js','@modelcontextprotocol/sdk/server/index.js','zod'])require.resolve(module);
const help=JSON.parse(execFileSync(process.execPath,[path.join(root,'dist/cli.js'),'help','--json'],{encoding:'utf8',timeout:10000,maxBuffer:1048576}));
if(help.ok!==true)throw Error('Packaged CLI did not pass help self-check');
console.log('PASS packaged gateway entries, dependencies and CLI help');
