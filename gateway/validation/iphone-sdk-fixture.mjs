import {Server} from '@modelcontextprotocol/sdk/server/index.js';
import {StdioServerTransport} from '@modelcontextprotocol/sdk/server/stdio.js';
import {ListToolsRequestSchema,CallToolRequestSchema} from '@modelcontextprotocol/sdk/types.js';
export const names=['phone_status','phone_capabilities','phone.screenshot','phone-tap',...Array.from({length:33},(_,i)=>`phone_tool_${i}`)];
const server=new Server({name:'synthetic-iphone',version:'1'},{capabilities:{tools:{}}});
server.setRequestHandler(ListToolsRequestSchema,async()=>({tools:names.map(name=>({name,description:'Synthetic read-only fixture',inputSchema:{type:'object',properties:{options:{type:'object',properties:{items:{type:'array',items:{type:'object',properties:{label:{type:'string'}},required:['label']}}}}},additionalProperties:false},annotations:{readOnlyHint:true,destructiveHint:false,openWorldHint:false}}))}));
server.setRequestHandler(CallToolRequestSchema,async request=>({content:[{type:'text',text:JSON.stringify({name:request.params.name,fixture:true})},...(request.params.name==='phone.screenshot'?[{type:'image',mimeType:'image/png',data:'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII='}]:[])]}));
await server.connect(new StdioServerTransport());
