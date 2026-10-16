import {realpath} from 'node:fs/promises';
import {stopLegacy} from './takeover.js';
const [home,workspace,candidate]=process.argv.slice(2);
try{
 if(!home||!workspace||!candidate||candidate.length>4096)throw new Error('Invalid context');
 await stopLegacy(await realpath(home),workspace,JSON.parse(candidate));
 process.stdout.write(JSON.stringify({type:'takeoverStopped'})+'\n');
}catch{process.stdout.write(JSON.stringify({type:'takeoverFailed',message:'未能确认旧网关已安全退出，没有启动新实例。请重新检查状态。'})+'\n');process.exitCode=1;}
