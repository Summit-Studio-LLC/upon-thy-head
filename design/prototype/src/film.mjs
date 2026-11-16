import { chromium } from '/Users/noahanderson/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
const OUT=process.argv[2];
const FILE=new URL('../index.html',import.meta.url).href;
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--use-angle=metal','--enable-gpu','--ignore-gpu-blocklist']});
const ctx=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:2});
const page=await ctx.newPage();
page.on('pageerror',e=>console.log('PAGEERROR',e.message));page.on('console',m=>{if(m.type()==='error')console.log('CONSOLE',m.text())});
await page.goto(FILE+'#record&live&rt=20&bare&shot&manual');
await page.waitForSelector('html[data-ready="1"]');
await page.evaluate(()=>{__sky.setClock(0);window.__fade=(a,b,u)=>{const A=document.getElementById('s-'+a),B=document.getElementById('s-'+b);const e=u*u*(3-2*u);if(u>=1){A.style.visibility='';A.style.opacity='';B.style.opacity='';}else{A.style.visibility='visible';A.style.opacity=1-e;B.style.opacity=e;}}});
const FPS=30;let n=0;
const ev=[[5.6,()=>page.evaluate(()=>__sky.go('after'))],[9.0,()=>page.evaluate(()=>__sky.go('sky'))],[10.0,()=>page.evaluate(()=>__sky.focus(4))],[12.0,()=>page.evaluate(()=>__sky.focus(0))]];
const fades=[[5.6,6.5,'record','after'],[9.0,9.7,'after','sky']];
const total=15*FPS;
for(let f=0;f<total;f++){
  const t=f/FPS;
  while(ev.length&&t>=ev[0][0]){await ev.shift()[1]()}
  for(const [a,b,x,y] of fades){if(t>=a&&t<=b+1/FPS){await page.evaluate(([x,y,u])=>__fade(x,y,u),[x,y,Math.min(1,(t-a)/(b-a))])}}
  await page.evaluate(dt=>__sky.step(dt),1/FPS);
  await page.screenshot({path:`${OUT}/f${String(n++).padStart(4,'0')}.png`});
}
await browser.close();console.log('frames',n);
