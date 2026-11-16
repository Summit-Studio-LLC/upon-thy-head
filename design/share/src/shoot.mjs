// Screenshots at 3x into ../shots, then ../compare.png. Usage: node shoot.mjs [filter]
import { chromium } from '/Users/noahanderson/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import fs from 'node:fs';
const D=new URL('..',import.meta.url).pathname, FILE='file://'+D+'index.html', OUT=D+'shots/';
const only=process.argv[2]||'';
const S=[
 ['01-s1-share-sheet','step=sheet&layout=s1'],
 ['02-s2-share-sheet','step=sheet&layout=s2'],
 ['03-s3-share-sheet','step=sheet&layout=s3'],
 ['04-v1-system-sheet-file','step=sys-file&way=v1'],
 ['05-v1-has-app-messages','step=msg&way=v1&rcv=app'],
 ['06-v1-has-app-keep','step=keep&way=v1&rcv=app'],
 ['07-v1-has-app-kept','step=reading&way=v1&rcv=app'],
 ['08-v1-iphone-messages','step=msg&way=v1&rcv=none'],
 ['09-v1-iphone-file-dead-end','step=ql&way=v1&rcv=none'],
 ['10-v1-iphone-page','step=page1&way=v1&rcv=none'],
 ['11-v1-android-messages','step=amsg&way=v1&rcv=other'],
 ['12-v1-android-file-dead-end','step=toast&way=v1&rcv=other'],
 ['13-v1-android-page','step=page1&way=v1&rcv=other'],
 ['14-v2-share-sheet','step=sheet&layout=s1&way=v2'],
 ['15-v2-link-made','step=linkmade&way=v2'],
 ['16-v2-system-sheet-link','step=sys-link&way=v2'],
 ['17-v2-has-app-messages','step=msg&way=v2&rcv=app'],
 ['18-v2-has-app-keep','step=keep&way=v2&rcv=app'],
 ['19-v2-iphone-page','step=page2&way=v2&rcv=none'],
 ['20-v2-android-messages','step=amsg&way=v2&rcv=other'],
 ['21-v2-android-page','step=page2&way=v2&rcv=other'],
 ['22-v2-offline','step=offline&way=v2'],
 ['23-v2-your-links','step=links&way=v2'],
 ['24-v2-stop-a-link','step=links-stop&way=v2'],
 ['25-v2-link-stopped','step=expired&way=v2&rcv=none'],
 ['es-01-s1-share-sheet','step=sheet&layout=s1&lang=es'],
 ['es-02-s2-share-sheet','step=sheet&layout=s2&lang=es'],
 ['es-03-s3-share-sheet','step=sheet&layout=s3&lang=es'],
 ['es-15-v2-link-made','step=linkmade&way=v2&lang=es'],
 ['es-19-v2-iphone-page','step=page2&way=v2&rcv=none&lang=es'],
 ['es-22-v2-offline','step=offline&way=v2&lang=es'],
 ['es-24-v2-stop-a-link','step=links-stop&way=v2&lang=es'],
 ['big-01-s1-share-sheet','step=sheet&layout=s1&big'],
 ['big-es-01-s1-share-sheet','step=sheet&layout=s1&big&lang=es'],
 ['big-es-02-s2-share-sheet','step=sheet&layout=s2&big&lang=es'],
 ['big-es-03-s3-share-sheet','step=sheet&layout=s3&big&lang=es'],
 ['big-es-15-v2-link-made','step=linkmade&way=v2&big&lang=es'],
 ['big-es-23-v2-your-links','step=links&way=v2&big&lang=es'],
];
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--use-angle=metal','--enable-gpu','--ignore-gpu-blocklist']});
const ctx=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:3});
let errs=0;
for(const [name,hash] of S){
  if(only&&!name.includes(only)&&only!=='compare')continue;
  if(only==='compare')break;
  const page=await ctx.newPage();
  page.on('console',m=>{if(m.type()==='error'){errs++;console.log('CONSOLE',m.text())}});
  page.on('pageerror',e=>{errs++;console.log('PAGEERROR',e.message)});
  await page.goto(FILE+'#'+hash+'&bare&shot');
  await page.waitForSelector('html[data-ready="1"]',{timeout:60000});
  await page.waitForTimeout(400);
  await page.screenshot({path:OUT+name+'.png'});
  await page.close();console.log('shot',name);
}
if(!only||only==='compare'){
  const W=170,H=Math.round(W*844/390),G=14;
  const rows=[
    ['The share sheet',[['01-s1-share-sheet','S1 One main action'],['02-s2-share-sheet','S2 Three in a row'],['03-s3-share-sheet','S3 The blessing, handed over']]],
    ['V1 The file: who receives it',[['05-v1-has-app-messages','Has the app: Messages'],['06-v1-has-app-keep','Has the app: keep it?'],['08-v1-iphone-messages','iPhone, no app: Messages'],['09-v1-iphone-file-dead-end','iPhone, no app: taps the file'],['10-v1-iphone-page','iPhone, no app: the address'],['12-v1-android-file-dead-end','Android: taps the file'],['13-v1-android-page','Android: the address']]],
    ['V2 A link: who receives it',[['17-v2-has-app-messages','Messages, any iPhone'],['18-v2-has-app-keep','Has the app: keep it?'],['19-v2-iphone-page','iPhone, no app: the page'],['20-v2-android-messages','Android: Messages'],['21-v2-android-page','Android or computer: the page'],['25-v2-link-stopped','After 30 days']]],
  ];
  const html=`<html><body style="margin:0;background:#16171C;font:13px -apple-system,system-ui;color:#B9BCC6;padding:28px 28px 8px">`+rows.map(([h,items])=>`<div style="color:#EEE7D8;font-size:15px;margin:0 0 10px">${h}</div><div style="display:flex;gap:${G}px;margin-bottom:26px">`+items.map(([n,l])=>`<div style="width:${W}px;flex:none"><img src="file://${OUT}${n}.png" style="width:${W}px;height:${H}px;border-radius:14px;display:block"><div style="margin-top:7px;font-size:11.5px;line-height:15px;color:#8E919C">${l}</div></div>`).join('')+`</div>`).join('')+`</body></html>`;
  fs.writeFileSync(D+'src/.compare.html',html);
  const c2=await browser.newContext({viewport:{width:56+7*W+6*G,height:400},deviceScaleFactor:2});
  const p=await c2.newPage();await p.goto('file://'+D+'src/.compare.html');await p.waitForTimeout(800);
  await p.screenshot({path:D+'compare.png',fullPage:true});fs.unlinkSync(D+'src/.compare.html');console.log('compare.png');
}
console.log('errors',errs);
await browser.close();
