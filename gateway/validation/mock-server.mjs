import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { ListToolsRequestSchema, CallToolRequestSchema } from '@modelcontextprotocol/sdk/types.js';
const server = new Server({name:'local-readonly-fixture',version:'1'}, {capabilities:{tools:{}}});
server.setRequestHandler(ListToolsRequestSchema, async()=>({tools:[{name:'echo',description:'Pure in-memory echo',inputSchema:{type:'object',properties:{text:{type:'string'}}}},{name:'hidden',description:'Must not be exposed',inputSchema:{type:'object'}}]}));
server.setRequestHandler(CallToolRequestSchema, async req=>({content:[{type:'text',text:String(req.params.arguments?.text ?? '')}]}));
await server.connect(new StdioServerTransport());
