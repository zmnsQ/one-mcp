import {spawn} from 'node:child_process';
// Test-owned harmless child; no external programs or user files.
const mode=process.argv[2];
if(mode==='echo')console.log(JSON.stringify({argv:process.argv.slice(3),ambient:process.env.UNAPPROVED_TEST_SECRET??null,approved:process.env.APPROVED_TEST_SECRET??null}));
else if(mode==='noisy')process.stdout.write('x'.repeat(100000));
else if(mode==='wait')setTimeout(()=>console.log('done'),10000);
else if(mode==='fail'){console.error('fixture failure');process.exitCode=2;}

else if(mode==='background'){spawn(process.execPath,['-e','setTimeout(()=>{},10000)'],{stdio:['ignore','inherit','inherit']});process.exit(0);}
