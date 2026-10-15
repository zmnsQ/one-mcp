// Isolated, in-memory adversarial fixture. No external services or user files.
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { ListToolsRequestSchema, CallToolRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { setTimeout as delay } from 'node:timers/promises';
let mode = process.env.FIXTURE_MODE ?? 'normal';
let listCalls = 0, active = 0, cancelled = 0;
const tool = name => ({ name, description: 'In-memory fixture tool', inputSchema: { type: 'object' } });
const result = value => ({ content: [{ type: 'text', text: JSON.stringify(value) }] });
const server = new Server({name:'workflow-fixture',version:'1'}, {capabilities:{tools:{listChanged:true}}});
server.setRequestHandler(ListToolsRequestSchema, async request => {
  listCalls++;
  if (process.env.LIST_DELAY) await delay(Number(process.env.LIST_DELAY));
  if (mode === 'fail') throw new Error(`Discovery failed ${process.env.PRIVATE_SECRET ?? ''}`);
  if (mode === 'duplicate') return { tools: [tool('echo'), tool('echo')] };
  if (mode === 'cursor') return { tools: [tool(`page${listCalls}`)], nextCursor: 'same' };
  if (mode === 'pages') return request.params?.cursor ? {tools:[tool('stats')]} : {tools:[tool('echo')],nextCursor:'second'};
  return {tools:['control','stats','delay',mode === 'changed' ? 'new_echo' : 'echo'].map(tool)};
});
server.setRequestHandler(CallToolRequestSchema, async (req, extra) => {
  const args = req.params.arguments ?? {};
  switch (req.params.name) {
    case 'control':
      if (args.crash) { setTimeout(() => process.exit(7), 50); return result('crashing'); }
      mode = String(args.mode ?? 'normal');
      if (args.notify) await server.notification({method:'notifications/tools/list_changed'});
      return result(mode);
    case 'stats': return result({listCalls,active,cancelled,pid:process.pid,parentSecret:process.env.PARENT_PRIVATE_SECRET ?? null,explicit:process.env.EXPLICIT_VALUE ?? null});
    case 'delay':
      active++;
      try { await delay(Number(args.ms ?? 20000), undefined, {signal:extra.signal}); return result('finished'); }
      catch(error) { if (extra.signal.aborted) cancelled++; throw error; }
      finally { active--; }
    default: return result(args.text ?? 'echo');
  }
});
if (process.env.START_DELAY) await delay(Number(process.env.START_DELAY));
await server.connect(new StdioServerTransport());
