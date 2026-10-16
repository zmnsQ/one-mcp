#!/usr/bin/env node
/** Manual loopback-only alternative; the CLI diagnostics mcp command additionally verifies workspace identity. */
import {diagnoseMCP} from '../gateway/dist/mcp-diagnostics.js';
try {const report=await diagnoseMCP(process.argv[2]??'http://127.0.0.1:8787/mcp');console.log(JSON.stringify(report,null,2));if(!report.ok)process.exitCode=1;}catch{console.error('Provide a credential-free loopback MCP URL, e.g. http://127.0.0.1:8787/mcp');process.exitCode=2;}
