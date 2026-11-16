// Screenshots at 3x into ../shots, then ../flow.png. Usage: node shoot.mjs [filter]
import { chromium } from '/Users/noahanderson/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import fs from 'node:fs';
const D=new URL('..',import.meta.url).pathname, FILE='file://'+D+'index.html', OUT=D+'shots/';
const only=process.argv[2]||'';
const MAIN=[
 ['01-opening-rising','step=opening&t=1.9'],
 ['02-opening','step=opening'],
 ['03-welcome','step=welcome'],
 ['04-microphone','step=mic'],
 ['05-microphone-question','step=mic&dialog'],
 ['06-microphone-refused','step=mic&refused'],
 ['07-speech','step=speech'],
 ['08-speech-question','step=speech&dialog'],
 ['09-location','step=loc'],
 ['10-location-question','step=loc&dialog'],
 ['11-location-refused','step=loc&refused'],
 ['12-face-id','step=face'],
 ['13-face-id-question','step=face&dialog'],
 ['14-4a-their-sky','step=home'],
 ['15-4b-try-a-few-words','step=try&v=b'],
 ['16-4b-practice-begin','step=begin&v=b'],
 ['17-4b-practice-listening','step=listen&v=b'],
 ['18-4b-practice-written','step=written&v=b'],
 ['19-shared-opening','step=s-opening'],
 ['20-shared-one-line','step=s-line'],
 ['21-shared-face-id','step=s-face'],
 ['22-shared-face-id-question','step=s-face&dialog'],
 ['23-shared-keep-it','step=s-keep'],
 ['24-shared-kept','step=s-kept'],
];
const ES=[
 ['es-03-welcome','step=welcome&lang=es'],
 ['es-04-microphone','step=mic&lang=es'],
 ['es-05-microphone-question','step=mic&dialog&lang=es'],
 ['es-06-microphone-refused','step=mic&refused&lang=es'],
 ['es-07-speech','step=speech&lang=es'],
 ['es-08-speech-question','step=speech&dialog&lang=es'],
 ['es-09-location','step=loc&lang=es'],
 ['es-10-location-question','step=loc&dialog&lang=es'],
 ['es-12-face-id','step=face&lang=es'],
 ['es-13-face-id-question','step=face&dialog&lang=es'],
 ['es-14-4a-their-sky','step=home&lang=es'],
 ['es-15-4b-try-a-few-words','step=try&v=b&lang=es'],
 ['es-23-shared-keep-it','step=s-keep&lang=es'],
];
const BIG=[
 ['big-03-welcome','step=welcome&big'],
 ['big-04-microphone','step=mic&big'],
 ['big-10-location-question','step=loc&dialog&big'],
 ['big-es-03-welcome','step=welcome&big&lang=es'],
 ['big-es-23-shared-keep-it','step=s-keep&big&lang=es'],
];
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--use-angle=metal','--enable-gpu','--ignore-gpu-blocklist']});
const ctx=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:3});
let errs=0;
for(const [name,hash] of [...MAIN,...ES,...BIG]){
  if(only&&!name.includes(only))continue;
  const page=await ctx.newPage();
  page.on('console',m=>{if(m.type()==='error'){errs++;console.log('CONSOLE',m.text())}});
  page.on('pageerror',e=>{errs++;console.log('PAGEERROR',e.message)});
  await page.goto(FILE+'#'+hash+'&bare&shot');
  await page.waitForSelector('html[data-ready="1"]',{timeout:60000});
  await page.waitForTimeout(400);
  await page.screenshot({path:OUT+name+'.png'});
  await page.close();console.log('shot',name);
}
// flow.png: every English screen in one row, small
if(!only||only==='flow'){
  const imgs=MAIN.map(([n])=>n);
  const groups={'01':'1 Opening','03':'2 Welcome','04':'3 Permissions','14':'4a Straight in','15':'4b Rehearsal, then 4a','19':'Opened from a shared blessing'};
  const W=150,H=Math.round(W*844/390),G=10;
  const html=`<html><body style="margin:0;background:#16171C;font:13px -apple-system,system-ui;color:#B9BCC6"><div style="display:flex;gap:${G}px;padding:44px 24px 40px;align-items:flex-start">`+
    imgs.map(n=>{const k=n.slice(0,2),g=groups[k];return `<div style="position:relative;width:${W}px;flex:none">${g?`<div style="position:absolute;top:-28px;left:0;white-space:nowrap;color:#EEE7D8;font-size:14px">${g}</div><div style="position:absolute;top:-8px;left:0;width:${W}px;height:1px;background:#4A4C55"></div>`:''}<img src="file://${OUT}${n}.png" style="width:${W}px;height:${H}px;border-radius:14px;display:block"><div style="margin-top:8px;font-size:11px;color:#7E818C">${n.replace(/^\d+-/,'').replace(/-/g,' ')}</div></div>`}).join('')+`</div></body></html>`;
  fs.writeFileSync(D+'src/.flow.html',html);
  const c2=await browser.newContext({viewport:{width:24*2+imgs.length*(W+G),height:H+120},deviceScaleFactor:2});
  const p=await c2.newPage();await p.goto('file://'+D+'src/.flow.html');await p.waitForTimeout(800);
  await p.screenshot({path:D+'flow.png',fullPage:true});fs.unlinkSync(D+'src/.flow.html');console.log('flow.png');
}
console.log('errors',errs);
await browser.close();
