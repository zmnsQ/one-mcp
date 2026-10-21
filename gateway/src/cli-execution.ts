import {spawn,ChildProcess} from 'node:child_process';
import {isAbsolute} from 'node:path';
import {cliServiceSchema,CLIServiceConfiguration,invocationArguments} from './cli-descriptor.js';
export type CLIExecutionConfig={executable:string; arguments:string[]; workingDirectory?:string; environment:Record<string,string>; cli:CLIServiceConfiguration};
export class CLIExecutor {
  private active=new Set<ChildProcess>(); private closed=false;
  constructor(private config:CLIExecutionConfig) {
    config.cli=cliServiceSchema.parse(config.cli);
    if(!config.cli.tools.length)throw Error('Configure at least one CLI tool');
    if(!isAbsolute(config.executable)||config.executable.includes('\0')) throw Error('Invalid executable');
    if(config.workingDirectory&&!isAbsolute(config.workingDirectory)) throw Error('Invalid working directory');
    if(!Array.isArray(config.arguments)||config.arguments.length>128||config.arguments.some(a=>typeof a!=='string'||a.includes('\0')||a.length>8192)) throw Error('Invalid fixed arguments');
    if(Object.entries(config.environment).some(([k,v])=>!/^[_A-Za-z][_A-Za-z0-9]*$/.test(k)||typeof v!=='string'||v.includes('\0')||v.length>65536)) throw Error('Invalid environment');
  }
  async close() {this.closed=true;for(const child of this.active)this.kill(child,'SIGKILL');}
  private kill(child:ChildProcess,signal:NodeJS.Signals) {
    try {if(process.platform!=='win32'&&child.pid) process.kill(-child.pid,signal);else child.kill(signal);} catch {/* Already exited. */}
  }
  async call(name:string,raw:unknown,signal?:AbortSignal) {
    const tool=this.config.cli.tools.find(t=>t.name===name);
    if(!tool)throw Error('Unknown CLI tool');
    const args=[...this.config.arguments,...invocationArguments(tool,raw??{})];
    if(this.closed||signal?.aborted)throw Error('CLI call cancelled');
    if(this.active.size>=this.config.cli.maxConcurrent)throw Error('CLI concurrency limit reached');
    const child=spawn(this.config.executable,args,{cwd:this.config.workingDirectory||undefined,
      env:{LANG:'C.UTF-8',...this.config.environment},shell:false,detached:process.platform!=='win32',stdio:['ignore','pipe','pipe']});
    this.active.add(child);
    return await new Promise<{stdout:string;stderr:string;exitCode:number|null;truncated:boolean}>((resolve,reject)=>{
      let stdout=Buffer.alloc(0),stderr=Buffer.alloc(0),bytes=0,truncated=false,reason='';
      const limit=this.config.cli.maxOutputBytes;
      const stop=(why:string)=>{if(!reason)reason=why;this.kill(child,'SIGKILL');};
      const timer=setTimeout(()=>stop('CLI execution timed out'),this.config.cli.timeoutMs);
      const abort=()=>stop('CLI call cancelled');signal?.addEventListener('abort',abort,{once:true});
      const collect=(data:Buffer,target:'stdout'|'stderr')=>{
        const slice=data.subarray(0,Math.max(0,limit-bytes));bytes+=slice.length;
        if(target==='stdout')stdout=Buffer.concat([stdout,slice]);else stderr=Buffer.concat([stderr,slice]);
        if(slice.length<data.length){truncated=true;stop('CLI output limit exceeded');}
      };
      child.stdout!.on('data',(data:Buffer)=>collect(data,'stdout'));child.stderr!.on('data',(data:Buffer)=>collect(data,'stderr'));
      const cleanup=()=>{clearTimeout(timer);signal?.removeEventListener('abort',abort);this.active.delete(child);};
      child.on('error',()=>{cleanup();reject(Error('CLI could not start'));});
      child.on('exit',()=>this.kill(child,'SIGKILL'));
      child.on('close',code=>{
        cleanup();this.kill(child,'SIGKILL'); // Also reap descendants retaining pipes or background work.
        if(reason&&!truncated){reject(Error(reason));return;}
        // A raw stream cut may bisect a secret; do not return its partial prefix.
        if(truncated){stdout=Buffer.alloc(0);stderr=Buffer.alloc(0);}
        const redact=(value:string)=>{for(const secret of Object.values(this.config.environment).filter(Boolean).sort((a,b)=>b.length-a.length))value=value.split(secret).join('[redacted]');return value.replace(/Bearer\s+\S+/gi,'Bearer [redacted]').replace(/(api[_-]?key|token|password|secret)([=:]\s*)\S+/gi,'$1$2[redacted]');};
        // Redaction can expand output; JSON escaping can expand it again. Bound the
        // encoded result, not only the raw child stream (also protects MCP framing).
        let budget=Math.max(0,limit-128);
        const bounded=(value:string)=>{
          if(Buffer.byteLength(JSON.stringify(value))>budget){
            truncated=true;let lo=0,hi=value.length;
            while(lo<hi){const mid=Math.ceil((lo+hi)/2);if(Buffer.byteLength(JSON.stringify(value.slice(0,mid)))<=budget)lo=mid;else hi=mid-1;}
            value=value.slice(0,lo);
          }
          budget=Math.max(0,budget-Buffer.byteLength(JSON.stringify(value)));return value;
        };
        resolve({stdout:bounded(redact(stdout.toString('utf8'))),stderr:bounded(redact(stderr.toString('utf8'))),exitCode:code,truncated});
      });
      // Catch cancellation between initial check and listener registration.
      if(signal?.aborted)abort();
    });
  }
}
