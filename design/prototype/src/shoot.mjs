import { chromium } from '/Users/noahanderson/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
const OUT=process.argv[2], which=(process.argv[3]||'').split(',').filter(Boolean);
const FILE=new URL('../index.html',import.meta.url).href;
const SHOTS=[
 ['01-begin','record'],
 ['01-recording','record&live&rt=23.6'],
 ['01-recording-first-seconds','record&live&rt=3.6'],
 ['01-recording-discard','record&live&rt=23.6',async p=>{await p.evaluate(()=>document.getElementById('rec-x').click())}],
 ['02-after-amen','after'],
 ['03-for-me','sky'],
 ['04-reading','read'],
 ['05-review-changes','review'],
 ['06-for-me-newest','sky&focus=job'],
 ['07-reading-end','read',async p=>{await p.evaluate(()=>{const s=document.getElementById('readscroll');s.scrollTop=s.scrollHeight})}],
 ['08-for-me-list','sky&list'],
 ['09-for-me-list-scrolled','sky&list',async p=>{await p.evaluate(()=>{const s=document.getElementById('list');s.scrollTop=230;s.dispatchEvent(new Event('scroll'))})}],
];
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--use-angle=metal','--enable-gpu','--ignore-gpu-blocklist']});
const ctx=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:3});
let errs=0;
for(const [name,hash,after] of SHOTS){
  if(which.length&&!which.some(w=>name.includes(w)))continue;
  const page=await ctx.newPage();
  page.on('console',m=>{if(m.type()==='error'||m.type()==='warning'){errs++;console.log('CONSOLE',m.type(),m.text())}});
  page.on('pageerror',e=>{errs++;console.log('PAGEERROR',e.message)});
  await page.goto(FILE+'#'+hash+'&bare&shot');
  await page.waitForSelector('html[data-ready="1"]',{timeout:30000});
  if(after)await after(page);
  await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
  await page.waitForTimeout(250);
  await page.screenshot({path:`${OUT}/${name}.png`});
  if(name==='01-begin'){const info=await page.evaluate(()=>{const c=document.createElement('canvas').getContext('webgl');const e=c.getExtension('WEBGL_debug_renderer_info');return e?c.getParameter(e.UNMASKED_RENDERER_WEBGL):'n/a'});console.log('RENDERER',info)}
  await page.close();console.log('shot',name);
}
if(!which.length||which.includes('shell')){const c2=await browser.newContext({viewport:{width:1440,height:860},deviceScaleFactor:2});const p=await c2.newPage();p.on('console',m=>{if(m.type()==='error'){errs++;console.log('CONSOLE',m.text())}});p.on('pageerror',e=>{errs++;console.log('PAGEERROR',e.message)});await p.goto(FILE+'#sky&shot');await p.waitForSelector('html[data-ready="1"]');await p.waitForTimeout(600);await p.screenshot({path:`${OUT}/00-shell.png`});console.log('shot shell')}
console.log('errors',errs);
await browser.close();
