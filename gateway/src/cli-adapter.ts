/** Internal stdio adapter. Configuration comes from the parent gateway, never client tool arguments. */
import {Server} from '@modelcontextprotocol/sdk/server/index.js';
import {StdioServerTransport} from '@modelcontextprotocol/sdk/server/stdio.js';
import {CallToolRequestSchema,ListToolsRequestSchema} from '@modelcontextprotocol/sdk/types.js';
import {CLIExecutor,CLIExecutionConfig} from './cli-execution.js';
import {inputSchema} from './cli-descriptor.js';
const raw=process.env.ONEMCP_CLI_DESCRIPTOR;
delete process.env.ONEMCP_CLI_DESCRIPTOR;
if(!raw||raw.length>262144)throw Error('Missing or oversized CLI descriptor');
const descriptor=JSON.parse(raw) as Omit<CLIExecutionConfig,'environment'>&{environmentKeys:string[]};
const environment:Record<string,string>={};
for(const key of descriptor.environmentKeys) {
  if(!/^[_A-Za-z][_A-Za-z0-9]*$/.test(key)||key.startsWith('ONEMCP_'))throw Error('Invalid CLI environment key');
  if(process.env[key]===undefined)throw Error('Missing CLI session environment');
  environment[key]=process.env[key]!;
}
const executor=new CLIExecutor({...descriptor,environment});
const server=new Server({name:'one-mcp-cli',version:'1.0.0'},{capabilities:{tools:{}}});
server.setRequestHandler(ListToolsRequestSchema,async()=>({tools:descriptor.cli.tools.map(t=>({name:t.name,description:t.description,inputSchema:inputSchema(t)}))}));
server.setRequestHandler(CallToolRequestSchema,async(request,extra)=>{
  try {
    const result=await executor.call(request.params.name,request.params.arguments,extra.signal);
    return {isError:result.exitCode!==0||result.truncated,content:[{type:'text',text:JSON.stringify(result)}]};
  } catch(error) {
    // Error messages are fixed adapter diagnostics, never raw subprocess exceptions.
    return {isError:true,content:[{type:'text',text:error instanceof Error?error.message:'CLI call failed'}]};
  }
});
const shutdown=()=>{void executor.close();void server.close();};
process.on('SIGTERM',()=>{shutdown();process.exit(0);});process.on('SIGINT',()=>{shutdown();process.exit(0);});
process.stdin.on('end',shutdown);
await server.connect(new StdioServerTransport());
