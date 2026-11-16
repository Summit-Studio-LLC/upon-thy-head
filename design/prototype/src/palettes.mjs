// Captures each palette on the real prototype. Usage: node palettes.mjs <outDir>
import { chromium } from '/Users/noahanderson/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
const OUT=process.argv[2];
const FILE=new URL('../index.html',import.meta.url).href;
const PALS=['vigil','lamplight','daybreak','starlight'], SCREENS=[['sky','sky'],['after','after'],['read','read'],['review','review']];
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--use-angle=metal','--enable-gpu','--ignore-gpu-blocklist']});
const ctx=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:2});
let errs=0;
for(const pal of PALS)for(const [name,hash] of SCREENS){
  const page=await ctx.newPage();
  page.on('console',m=>{if(m.type()==='error'||m.type()==='warning'){errs++;console.log('CONSOLE',m.type(),m.text())}});
  page.on('pageerror',e=>{errs++;console.log('PAGEERROR',e.message)});
  await page.goto(FILE+'#'+hash+'&bare&shot&pal='+pal);
  await page.waitForSelector('html[data-ready="1"]',{timeout:30000});
  const got=await page.evaluate(()=>document.documentElement.getAttribute('data-pal'));
  if(got!==pal){errs++;console.log('PALETTE NOT APPLIED',pal,got)}
  await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
  await page.waitForTimeout(250);
  await page.screenshot({path:`${OUT}/${pal}-${name}.png`});
  await page.close();
}
console.log('errors',errs);
await browser.close();
