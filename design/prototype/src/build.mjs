import fs from 'node:fs';
const d=new URL('.',import.meta.url).pathname;
let t=fs.readFileSync(d+'template.html','utf8');
const b64=p=>fs.readFileSync(p).toString('base64');
const sub={FONT_ROMAN:b64(d+'fonts/nr-roman.woff2'),FONT_ITALIC:b64(d+'fonts/nr-italic.woff2'),STARS:fs.readFileSync(d+'stars.b64','utf8'),NAMED:fs.readFileSync(d+'stars.b64.named.json','utf8'),CONST:fs.readFileSync(d+'constellations.json','utf8'),MW:b64(d+(process.env.MW||'mw8k_c.jpg')),APP:fs.readFileSync(d+'app.js','utf8')};
t=t.replace(/@@([A-Z_]+)@@/g,(m,k)=>{if(!(k in sub))throw new Error(k);return sub[k]});
const out=d+'../index.html';
fs.writeFileSync(out,t);console.log('built',(t.length/1e6).toFixed(2)+' MB');
