import {z} from 'zod';
const text = (max:number) => z.string().max(max).regex(/^[^\0]*$/);
const name = z.string().regex(/^[A-Za-z][A-Za-z0-9_]{0,63}$/).refine(v => !['__proto__','constructor','prototype'].includes(v));
export const cliArgumentSchema = z.object({
  name, type:z.enum(['string','number','boolean']), flag:z.string().regex(/^--[A-Za-z][A-Za-z0-9-]{0,63}$/).optional(),
  required:z.boolean(), enumValues:z.array(text(8192).min(1).refine(v => !v.startsWith('-'))).min(1).max(100).refine(v => new Set(v).size === v.length).optional()
}).strict().refine(a => a.type !== 'boolean' || !!a.flag, 'Boolean parameters require a flag')
  .refine(a => !a.enumValues || a.type === 'string', 'Only string parameters support choices');
export const cliToolSchema = z.object({name, description:text(1000), arguments:z.array(cliArgumentSchema).max(32) }).strict()
  .refine(t => new Set(t.arguments.map(a=>a.name)).size === t.arguments.length, 'Duplicate parameter')
  .refine(t => new Set(t.arguments.filter(a=>a.flag).map(a=>a.flag)).size === t.arguments.filter(a=>a.flag).length, 'Duplicate flag');
export const cliServiceSchema = z.object({ tools:z.array(cliToolSchema).max(32),
  timeoutMs:z.number().int().min(100).max(120000), maxOutputBytes:z.number().int().min(1024).max(1048576),
  maxConcurrent:z.number().int().min(1).max(4)
}).strict().refine(c => new Set(c.tools.map(t=>t.name)).size === c.tools.length, 'Duplicate tool');
export type CLIServiceConfiguration = z.infer<typeof cliServiceSchema>;
export type CLITool = CLIServiceConfiguration['tools'][number];
export function inputSchema(tool:CLITool) {
  return {type:'object' as const, properties:Object.fromEntries(tool.arguments.map(a=>[a.name,{type:a.type,...(a.enumValues?{enum:a.enumValues}:{})}])),
    required:tool.arguments.filter(a=>a.required).map(a=>a.name), additionalProperties:false};
}
/** Validate at the execution boundary, not merely in the published MCP schema. */
export function invocationArguments(tool:CLITool, raw:unknown):string[] {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw Error('Expected parameter object');
  const input=raw as Record<string,unknown>;
  if(Object.keys(input).some(k=>!tool.arguments.some(a=>a.name===k))) throw Error('Unknown parameter');
  const argv:string[]=[];
  for(const spec of tool.arguments) {
    const value=Object.prototype.hasOwnProperty.call(input,spec.name)?input[spec.name]:undefined;
    if(value===undefined) {if(spec.required) throw Error('Required parameter missing'); continue;}
    if(typeof value!==spec.type || (typeof value==='number'&&!Number.isFinite(value))) throw Error('Invalid parameter type');
    if(spec.enumValues&&!spec.enumValues.includes(value as string)) throw Error('Invalid parameter choice');
    if(typeof value==='boolean') {if(value) argv.push(spec.flag!);continue;}
    const str=String(value);
    // In addition to no shell, prevent user values from becoming CLI option switches.
    if(str.includes('\0')||str.length>8192||str.startsWith('-')) throw Error('Invalid parameter value');
    if(spec.flag) argv.push(spec.flag);
    argv.push(str);
  }
  return argv;
}
