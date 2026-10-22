import {Server} from '@modelcontextprotocol/sdk/server/index.js';
import {StdioServerTransport} from '@modelcontextprotocol/sdk/server/stdio.js';
import {ListToolsRequestSchema,CallToolRequestSchema} from '@modelcontextprotocol/sdk/types.js';
const server=new Server({name:'log-fixture',version:'1'},{capabilities:{tools:{}}});
server.setRequestHandler(ListToolsRequestSchema,async()=>({tools:['echo','fail','throw'].map(name=>({name,inputSchema:{type:'object'}}))}));
server.setRequestHandler(CallToolRequestSchema,async req=>{
  process.stderr.write('Authorization: Basic PRIVATE_BASIC https://example.test/?token=PRIVATE_URL '+JSON.stringify(req.params.arguments)+'\n');
  if(req.params.name==='throw')throw Error('PRIVATE_ERROR');
  return {isError:req.params.name==='fail',content:[{type:'text',text:'PRIVATE_RESULT'}]};
});
await server.connect(new StdioServerTransport());
