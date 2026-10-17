import {realpath} from 'node:fs/promises';
import {join} from 'node:path';
import {prepareRuntimeSocket} from './runtime-start.js';
const [home]=process.argv.slice(2);
try {
  if(!home)throw new Error('Missing runtime root');
  const root=await realpath(home);
  const state=await prepareRuntimeSocket(join(root,'Runtime','control.sock'));
  process.stdout.write(JSON.stringify({type:'runtimeStartPrepared',state})+'\n');
} catch {
  process.stdout.write(JSON.stringify({type:'runtimeStartFailed',message:'无法安全确认现有网关状态；未移动或停止运行中的实例。请查看运行日志后重试。'})+'\n');
  process.exitCode=1;
}
