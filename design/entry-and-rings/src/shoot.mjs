// Screenshots at 3x into ../shots, then ../compare-A.png and ../compare-B.png. Usage: node shoot.mjs [filter|compare]
import { chromium } from '/Users/noahanderson/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import fs from 'node:fs';
const D=new URL('..',import.meta.url).pathname, FILE='file://'+D+'index.html', OUT=D+'shots/';
fs.mkdirSync(OUT,{recursive:true});
const only=process.argv[2]||'';
const A=['a-home','a-home2','a-record','a-entry','a-pasted','a-date-day','a-date-month','a-date-year','a-filled','a-saved','a-before','a-after','a-reading','a-reading-end','a-photo'];
const B1=['b1-home','b1-switch','b1-emma','b1-add','b1-clara','b1-record','b1-review','b1-enter','b1-menu','b1-hand','b1-sent','c-open','c-read','c-kept','b1-after','c-second'];
const B2=['b2-home','b2-emma','b2-add','b2-review','b2-hand','b2-after'];
const B3=['b3-home','b3-list','b3-review','b3-hand','b3-sent','b3-after'];
const S=[];
const pad=n=>String(n).padStart(2,'0');
A.forEach((s,i)=>S.push(['A-'+pad(i+1)+'-'+s.slice(2),'step='+s]));
B1.forEach((s,i)=>S.push(['B1-'+pad(i+1)+'-'+s.replace(/^b1-/,''),'step='+s]));
B2.forEach((s,i)=>S.push(['B2-'+pad(i+1)+'-'+s.slice(3),'step='+s]));
B3.forEach((s,i)=>S.push(['B3-'+pad(i+1)+'-'+s.slice(3),'step='+s]));
const ES_A=['a-home','a-record','a-entry','a-pasted','a-date-month','a-date-year','a-filled','a-saved','a-reading-end'];
const ES_B=['b1-switch','b1-emma','b1-add','b1-review','b1-menu','b1-hand','b1-sent','c-open','c-read','c-kept','b1-after','c-second'];
ES_A.forEach(s=>{const i=A.indexOf(s);S.push(['es-A-'+pad(i+1)+'-'+s.slice(2),'step='+s+'&lang=es'])});
ES_B.forEach(s=>{const i=B1.indexOf(s);S.push(['es-B1-'+pad(i+1)+'-'+s.replace(/^b1-/,''),'step='+s+'&lang=es'])});
[['A','a-entry'],['A','a-filled'],['A','a-date-month'],['B1','b1-switch'],['B1','b1-hand'],['B1','b1-sent'],['B1','c-read'],['B1','b1-after']].forEach(([p,s])=>{
  const L=p==='A'?A:B1,i=L.indexOf(s),n=s.replace(/^(a|b1)-/,'');
  S.push(['big-es-'+p+'-'+pad(i+1)+'-'+n,'step='+s+'&lang=es&big']);
});
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--use-angle=metal','--enable-gpu','--ignore-gpu-blocklist']});
const ctx=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:3});
let errs=0;
if(only!=='compare')for(const [name,hash] of S){
  if(only&&!name.includes(only))continue;
  const page=await ctx.newPage();
  page.on('console',m=>{if(m.type()==='error'){errs++;console.log('CONSOLE',name,m.text())}});
  page.on('pageerror',e=>{errs++;console.log('PAGEERROR',name,e.message)});
  await page.goto(FILE+'#'+hash+'&bare&shot');
  await page.waitForSelector('html[data-ready="1"]',{timeout:60000});
  await page.waitForTimeout(350);
  await page.screenshot({path:OUT+name+'.png'});
  await page.close();console.log('shot',name);
}
async function sheet(file,rows,cols){
  const W=170,H=Math.round(W*844/390),G=14,LW=cols?92:0;
  const head=cols?`<div style="display:flex;gap:${G}px;margin:0 0 10px ${LW}px">`+cols.map(c=>`<div style="width:${W}px;font-size:12px;color:#8E919C">${c}</div>`).join('')+`</div>`:'';
  const html=`<html><body style="margin:0;background:#16171C;font:13px -apple-system,system-ui;color:#B9BCC6;padding:28px 28px 8px">`+head+rows.map(([h,items])=>
    `<div style="display:flex;gap:${G}px;margin-bottom:22px;align-items:flex-start">`+(cols?`<div style="width:${LW-G}px;flex:none;color:#EEE7D8;font-size:14px;line-height:19px">${h}</div>`:'')+
    items.map(([n,l])=>`<div style="width:${W}px;flex:none">${n?`<img src="file://${OUT}${n}.png" style="width:${W}px;height:${H}px;border-radius:14px;display:block">`:`<div style="width:${W}px;height:${H}px;border-radius:14px;border:1px dashed #3A3C44;display:grid;place-items:center;color:#5E616B;font-size:11.5px;text-align:center;padding:0 16px;box-sizing:border-box">${l}</div>`}${n&&l?`<div style="margin-top:7px;font-size:11.5px;line-height:15px;color:#8E919C">${l}</div>`:''}</div>`).join('')+`</div>`).join('')+`</body></html>`;
  fs.writeFileSync(D+'src/.compare.html',html);
  const n=Math.max(...rows.map(r=>r[1].length));
  const c2=await browser.newContext({viewport:{width:56+LW+n*W+(n-1)*G,height:400},deviceScaleFactor:2});
  const p=await c2.newPage();await p.goto('file://'+D+'src/.compare.html');await p.waitForTimeout(900);
  await p.screenshot({path:D+file,fullPage:true});fs.unlinkSync(D+'src/.compare.html');await c2.close();console.log(file);
}
if(!only||only==='compare'){
  const nm=s=>S.find(x=>x[1]==='step='+s)[0];
  const lab={'a-home':'Home, as today','a-record':'New blessing: Enter a past one','a-entry':'The entry page','a-pasted':'Pasted in one go','a-date-month':'When: month and year','a-date-year':'When: year only','a-filled':'Filled in','a-saved':'Saved: its light arrives','a-before':'Ring start: before','a-after':'Ring start: after','a-reading-end':'One honest line'};
  await sheet('compare-A.png',[['',Object.keys(lab).map(s=>[nm(s),lab[s]])]]);
  await sheet('compare-B.png',[
    ['B1 A ring for each person',[[nm('b1-emma'),''],[nm('b1-add'),''],[nm('b1-review'),''],[nm('b1-hand'),''],[nm('b1-after'),'']]],
    ['B2 One sky, several rings',[[nm('b2-home'),''],[nm('b2-add'),''],[nm('b2-review'),''],[nm('b2-hand'),''],[nm('b2-after'),'']]],
    ['B3 A list for each child',[[nm('b3-list'),''],[null,'No step: a group forms from the For name'],[nm('b3-review'),''],[nm('b3-hand'),''],[nm('b3-after'),'']]],
  ],['Home','Adding a child','Recording for a child','Handing over','Afterwards']);
}
console.log('errors',errs);
await browser.close();
