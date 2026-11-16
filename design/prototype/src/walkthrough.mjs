/* Full walkthrough film of the prototype, stepped frame by frame so every transition is exact.
   node walkthrough.mjs ../walkthrough.mp4            full render, piped straight into ffmpeg
   EVERY=15 node walkthrough.mjs <dir>                preview: saves every 15th frame as PNG, no video
   ONLY=record REC=rose node walkthrough.mjs out.mp4  just the recording screen, with the rosette instead of constellations */
import { chromium } from '/Users/noahanderson/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { spawn } from 'node:child_process';
import fs from 'node:fs';

const OUT=process.argv[2], EVERY=+(process.env.EVERY||0), CRF=process.env.CRF||'18', ONLY=process.env.ONLY||'', REC=process.env.REC==='rose'?'rose':'stars';
const FPS=30, DT=1000/FPS, VW=450, VH=996;
const BURST=(process.env.BURST||'').split(',').map(Number);          // preview only: also save every frame between these two seconds
const FILE=new URL('../index.html',import.meta.url).href;

const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--use-angle=metal','--enable-gpu','--ignore-gpu-blocklist']});
const ctx=await browser.newContext({viewport:{width:VW,height:VH},deviceScaleFactor:2});
const page=await ctx.newPage();
let errs=0;
page.on('pageerror',e=>{errs++;console.log('PAGEERROR',e.message)});
page.on('console',m=>{if(m.type()==='error'){errs++;console.log('CONSOLE',m.text())}});

/* virtual time: timers and performance.now() only move when the film advances a frame */
await page.addInitScript(()=>{
  let now=0,id=1;const q=[];
  window.__vt={advance(ms){const end=now+ms;for(;;){q.sort((a,b)=>a.t-b.t||a.id-b.id);const n=q[0];if(!n||n.t>end)break;q.shift();now=n.t;try{n.fn()}catch(e){console.error(e)}}now=end}};
  window.setTimeout=(fn,ms=0,...a)=>{const i=id++;q.push({id:i,t:now+(+ms||0),fn:()=>fn(...a)});return i};
  window.clearTimeout=i=>{const k=q.findIndex(x=>x.id===i);if(k>=0)q.splice(k,1)};
  performance.now=()=>now;
});
await page.goto(FILE+'#record&shot&manual&rec='+REC);
await page.waitForSelector('html[data-ready="1"]',{timeout:30000});

await page.evaluate(()=>{
  const css=document.createElement('style');css.textContent=`
  body{background:#100F0E!important}
  .stage{align-items:start!important;padding:22px 0 0!important}
  .rail,.notes{display:none!important}
  #fcap{position:fixed;left:30px;right:30px;top:908px;transition:opacity .26s ease}
  #fcap.out{opacity:0}
  #fcap h3{font:400 21px/26px var(--serif);color:#EFE6D4;letter-spacing:-.005em}
  #fcap p{margin-top:4px;font:400 13.5px/20px var(--sans);color:#9A9388}
  .fdot{position:fixed;left:0;top:0;width:46px;height:46px;margin:-23px 0 0 -23px;border-radius:50%;background:rgba(255,246,228,.20);box-shadow:inset 0 0 0 1.5px rgba(255,246,228,.55);opacity:0;transform:scale(1.4);transition:opacity .16s ease-out,transform .16s ease-out,background-color .16s;pointer-events:none;z-index:999}
  .fdot.on{opacity:1;transform:scale(1)}
  .fdot.down{transform:scale(.8);background:rgba(255,246,228,.42)}
  #ffade{position:fixed;inset:0;background:#000;opacity:1;transition:opacity .7s ease;pointer-events:none;z-index:1000}
  #ffade.clear{opacity:0}`;
  document.head.appendChild(css);
  document.body.insertAdjacentHTML('beforeend','<div id="fcap" class="out"><h3></h3><p></p></div><div class="fdot" id="fd0"></div><div class="fdot" id="fd1"></div><div id="ffade"></div>');
  document.documentElement.classList.remove('notrans');
  const tracked=new WeakSet();
  window.__anim=dt=>{for(const a of document.getAnimations()){
    if(!tracked.has(a)){tracked.add(a);a.pause();a.currentTime=0}
    const end=a.effect.getComputedTiming().endTime,t=(+a.currentTime||0)+dt;
    if(t>=end-.01)a.finish();else a.currentTime=t}};
  window.__tick=dt=>{__vt.advance(dt);__sky.step(dt/1000);__anim(dt)};
  window.__cap=(h,p)=>{const c=document.getElementById('fcap');c.classList.add('out');setTimeout(()=>{c.firstChild.textContent=h;c.lastChild.textContent=p;c.classList.remove('out')},270)};
  window.__dot=(i,op,x,y)=>{const d=document.getElementById('fd'+i);
    if(x!==undefined){d.style.left=x+'px';d.style.top=y+'px'}
    if(op==='show'){d.classList.add('on');d.classList.remove('down')}
    if(op==='down'){d.classList.add('on','down')}
    if(op==='hide'){d.classList.remove('on','down')}};
  window.__scroll=(id,top)=>{const s=document.getElementById(id);s.scrollTop=top;s.dispatchEvent(new Event('scroll'));return s.scrollTop};
  __sky.setClock(0);
});

/* ---------- capture ---------- */
const cdp=await ctx.newCDPSession(page);
let ff=null,n=0,saved=0;const marks=[];
if(!EVERY){
  ff=spawn('ffmpeg',['-y','-loglevel','error','-f','image2pipe','-framerate',String(FPS),'-c:v','png','-i','-','-c:v','libx264','-preset','slow','-crf',CRF,'-pix_fmt','yuv420p','-movflags','+faststart',OUT],{stdio:['pipe','inherit','inherit']});
}else fs.mkdirSync(OUT,{recursive:true});
async function frame(){
  await page.evaluate(dt=>__tick(dt),DT);
  if(!EVERY||n%EVERY===0||(BURST.length===2&&n/FPS>=BURST[0]&&n/FPS<=BURST[1])){
    const {data}=await cdp.send('Page.captureScreenshot',{format:'png',optimizeForSpeed:process.env.FAST==='1',clip:{x:0,y:0,width:VW,height:VH,scale:2}});
    const buf=Buffer.from(data,'base64');
    if(ff){if(!ff.stdin.write(buf))await new Promise(r=>ff.stdin.once('drain',r))}
    else{fs.writeFileSync(`${OUT}/f${String(n).padStart(5,'0')}.png`,buf);saved++}
  }
  n++;
}
const wait=async s=>{for(let i=0,k=Math.round(s*FPS);i<k;i++)await frame()};
const mark=name=>{marks.push([name,(n/FPS).toFixed(2)]);console.log('@',(n/FPS).toFixed(2),name)};
const cap=(h,p)=>page.evaluate(([h,p])=>__cap(h,p),[h,p]);
const dot=(i,op,x,y)=>page.evaluate(a=>__dot(...a),[i,op,x,y]);
const PARK={x:4,y:990};
const ph=await page.locator('#phone').boundingBox();           // phone origin on the page
const P=(x,y)=>({x:ph.x+x,y:ph.y+y});
async function centre(sel){
  const r=await page.evaluate(s=>{const e=document.querySelector(s);if(!e)return null;const c=e.getClientRects()[0];return {x:c.left+c.width/2,y:c.top+c.height/2}},sel);
  if(!r)throw new Error('missing '+sel);return r;
}
async function tap(pt,{hold=.14,pre=.24,post=.08}={}){
  await dot(0,'show',pt.x,pt.y);await wait(pre);
  await page.mouse.move(pt.x,pt.y);await page.mouse.down();await dot(0,'down');
  await wait(hold);
  await page.mouse.up();await dot(0,'hide');await page.mouse.move(PARK.x,PARK.y);
  await wait(post);
}
const tapEl=async(sel,o)=>tap(await centre(sel),o);
async function drag(a,b,dur){
  await dot(0,'show',a.x,a.y);await wait(.22);
  await page.mouse.move(a.x,a.y);await page.mouse.down();await dot(0,'down');await frame();
  const k=Math.round(dur*FPS);
  for(let i=1;i<=k;i++){const t=i/k,u=.5-.5*Math.cos(Math.PI*Math.pow(t,.85)*.86)/1, e=u/(.5-.5*Math.cos(Math.PI*.86));
    const x=a.x+(b.x-a.x)*e,y=a.y+(b.y-a.y)*e;
    await page.mouse.move(x,y);await dot(0,'down',x,y);
    if(i===k){await page.mouse.up();await dot(0,'hide');await page.mouse.move(PARK.x,PARK.y)}
    await frame()}
}
async function pinch(c,r0,r1,fov0,fov1,dur){
  const ang=-.62,ux=Math.cos(ang),uy=Math.sin(ang);
  const at=r=>[{x:c.x+ux*r,y:c.y+uy*r},{x:c.x-ux*r,y:c.y-uy*r}];
  let [p,q]=at(r0);await dot(0,'show',p.x,p.y);await dot(1,'show',q.x,q.y);await wait(.24);
  await dot(0,'down');await dot(1,'down');await frame();
  const k=Math.round(dur*FPS);
  for(let i=1;i<=k;i++){const t=i/k,e=t*t*(3-2*t);[p,q]=at(r0+(r1-r0)*e);
    await dot(0,'down',p.x,p.y);await dot(1,'down',q.x,q.y);
    await page.evaluate(f=>{__sky.goal.fov=f},fov0*Math.pow(fov1/fov0,e));
    await frame()}
  await dot(0,'hide');await dot(1,'hide');
}
async function swipe(id,dy,{x=195,y0=610,dur=.44,coast=.7,extra=.5}={}){
  const start=await page.evaluate(i=>document.getElementById(i).scrollTop,id);
  const a=P(x,y0);await dot(0,'show',a.x,a.y);await wait(.22);await dot(0,'down');await frame();
  const k=Math.round(dur*FPS);let top=start;
  for(let i=1;i<=k;i++){const t=i/k,e=Math.pow(t,1.5);top=start+dy*e;
    await dot(0,i===k?'hide':'down',a.x,a.y-dy*e);await page.evaluate(a=>__scroll(...a),[id,top]);await frame()}
  const c=Math.round(coast*FPS);
  for(let i=1;i<=c;i++){const t=i/c;await page.evaluate(a=>__scroll(...a),[id,top+dy*extra*(1-Math.pow(1-t,3))]);await frame()}
}

/* ---------- the walkthrough ---------- */
// 1. A press to begin, then recording
async function finish(){
  await page.evaluate(()=>document.getElementById('ffade').classList.remove('clear'));
  await wait(.9);
  console.log('frames',n,'seconds',(n/FPS).toFixed(2),'saved',saved,'errors',errs);
  await browser.close();
  if(ff){ff.stdin.end();await new Promise(r=>ff.on('close',r))}
}
mark('begin');
await cap('New blessing','Nothing is recorded until you press Begin.');
await page.evaluate(()=>document.getElementById('ffade').classList.add('clear'));
await wait(ONLY?1.6:3.0);
await tapEl('#begin');
mark('recording');
if(ONLY){
  await cap(REC==='rose'?'Rosette':'Constellations',REC==='rose'?'A rose of twelve circles opens and closes with the breath, and turns a little.':'The constellations overhead are drawn star to star, rest, and are taken up again.');
  await wait(26);
  await finish();process.exit(0);
}
await cap('Recording','For the first ten seconds the button is Discard, in case it was started by accident.');
await wait(3.4);
await tapEl('#hold');                              // inside the window: one tap takes it back
await cap('New blessing','One tap, and nothing was kept.');
await wait(2.6);
await tapEl('#begin');
await cap('Recording','Left alone, the ring runs down and Discard gives way to Amen.');
await wait(11.8);
await cap('Recording','The light breathes. Behind it, the constellations overhead are drawn in, star to star.');
await wait(5.4);
await cap('Recording','From then on Discard waits at the top right. It asks first, and keeps listening while you decide.');
await wait(.8);
await tapEl('#rec-x');await wait(2.8);
await tapEl('#rec-keep');await wait(1.3);
await cap('Recording','A tap does not end it. Holding Amen does.');
await wait(.9);
const amen=await centre('#hold');
await tap(amen,{hold:.2});                       // a tap only nudges the hint
await wait(1.5);
await dot(0,'show',amen.x,amen.y);await wait(.24);
await page.mouse.move(amen.x,amen.y);await page.mouse.down();await dot(0,'down');
await wait(1.02);                                 // ring fills in .9 s, then the screen changes
await page.mouse.up();await dot(0,'hide');await page.mouse.move(PARK.x,PARK.y);

// 2. After amen
mark('after');
await cap('After amen','The recording is erased. Only the words stay, on this phone.');
await wait(4.6);
await tapEl('#s-after .btn.primary');

// 3. Review changes
mark('review');
await cap('Review changes','Every edit is marked twice: by colour and by the style of its line.');
await wait(3.4);
await cap('Review changes','Tap an edit to see what was actually said, and put it back. The page rearranges itself as you watch.');
await wait(.5);
await tapEl('#rv-words [data-e="1"]');await wait(2.3);
await tapEl('#sh-restore');await wait(2.4);
await tapEl('#sh-next');await wait(1.7);
await tapEl('#sh-keep');await wait(1.5);
await tapEl('#rv-words [data-e="0"]');await wait(2.4);
await tapEl('#s-review .txtbtn');

// 4. Reading
mark('reading');
await cap('Reading','The blessing as a page. Its kind links to the General Handbook.');
await wait(3.0);
const max=await page.evaluate(()=>{const s=document.getElementById('readscroll');return s.scrollHeight-s.clientHeight});
console.log('read scroll max',max);
await swipe('readscroll',Math.min(250,max*.5));await wait(1.3);
await swipe('readscroll',Math.min(250,max*.5));await wait(.4);
await cap('Reading','The page says how much was polished, and the original is always one tap away.');
await wait(3.2);
await tapEl('#s-read .topbar .iconbtn');

// 5. For me
mark('sky');
await cap('For me','Each blessing is a light at the point of sky that stood overhead when it was given.');
await wait(3.4);
const mid=P(195,330);
await pinch(mid,34,112,90,46,1.25);await wait(1.9);
await pinch(mid,112,36,46,90,1.05);await wait(.9);
await cap('For me','Drag to look around the real night sky.');
await wait(.4);
await drag(P(120,350),P(300,300),.62);await wait(1.5);
await drag(P(290,280),P(110,380),.62);await wait(1.5);
await cap('For me','The ruler keeps them in order. Step back through the years, or touch a date.');
await wait(.4);
await tapEl('#older');await wait(3.1);
await tapEl('#older');await wait(3.1);
await tapEl('#track em[data-i="4"]');await wait(3.7);

// 6. The list, and back to a page
mark('list');
await cap('For me','The same blessings on one upright line, newest first.');
await wait(.3);
await tapEl('#viewbtn');await wait(2.4);
await cap('For me','Scroll, and the light runs down the line to each blessing in turn.');
await swipe('list',150,{y0:600,extra:.4});await wait(1.1);
await swipe('list',150,{y0:600,extra:.4});await wait(1.6);
await swipe('list',-260,{y0:330,extra:.62,coast:.9});await wait(.9);
await tapEl('#list [data-i="3"]');
await cap('Reading','Any row in the list opens its page.');
await wait(2.9);
await tapEl('#s-read .topbar .iconbtn');
await cap('For me','And the page leads back to its light.');
await wait(2.6);

// 7. A new blessing
mark('new');
await cap('New blessing','And a new one waits for a press to begin.');
await wait(.5);
await tapEl('#s-sky .new');await wait(3.4);
fs.writeFileSync(new URL('./walkthrough.marks.json',import.meta.url),JSON.stringify(marks));
await finish();
