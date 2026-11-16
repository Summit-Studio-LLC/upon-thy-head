// Builds ../index.html: one self-contained file. Sky assets are read (never changed) from ../../prototype/src.
import fs from 'node:fs';
const d=new URL('.',import.meta.url).pathname, p=d+'../../prototype/src/';
let t=fs.readFileSync(d+'template.html','utf8');
const b64=f=>fs.readFileSync(f).toString('base64');
const sub={FONT_ROMAN:b64(p+'fonts/nr-roman.woff2'),FONT_ITALIC:b64(p+'fonts/nr-italic.woff2'),STARS:fs.readFileSync(p+'stars.b64','utf8'),MW:b64(p+'mw8k_c.jpg'),APP:fs.readFileSync(d+'app.js','utf8')};
t=t.replace(/@@([A-Z_]+)@@/g,(m,k)=>{if(!(k in sub))throw new Error(k);return sub[k]});
fs.writeFileSync(d+'../index.html',t);console.log('built',(t.length/1e6).toFixed(2)+' MB');
