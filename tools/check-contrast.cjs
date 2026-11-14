#!/usr/bin/env node
/* check-contrast.cjs — fail the build when a button label cannot be read.
 *
 * THE DEFECT THIS GUARDS. A filled button took its surface from a token that
 * flips with the theme (Primary: #222222 light, #eeeeee dark) and its label from
 * a colour that does not (TextLightSolid: #ffffff in both). Correct in light,
 * 1.16:1 in dark: the label is present and invisible. Eighteen pages in this
 * fleet had it, arrived at independently, because nothing checked.
 *
 * It measures the RENDERED page, not the stylesheet. A rule that no element
 * matches is not a defect, and a rule that another rule overrides is not one
 * either — static readers get both wrong, in both directions. So: real Chromium,
 * both theme modes, every button-ish element, and the worst gradient stop wins.
 *
 * No dependencies. Needs a `chromium` (or `google-chrome`) binary on PATH:
 *   Ubuntu   sudo apt-get install -y chromium
 *   Debian   sudo apt-get install -y chromium
 *   macOS    brew install --cask chromium
 *
 *   node tools/check-contrast.cjs            # scans every page in the repo
 *   node tools/check-contrast.cjs --list     # names the pages it will scan
 *
 * Exit 0 = every button passes 4.5:1 in both modes. Exit 1 = something does not.
 */
"use strict";

const { execFileSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const MIN = 4.5;
const LIST = process.argv.includes("--list");

const CHROME = ["chromium", "chromium-browser", "google-chrome", "chrome"].find((bin) => {
  try { execFileSync("which", [bin], { stdio: "ignore" }); return true; } catch { return false; }
});

function pages(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === ".git" || entry.name === "node_modules" || entry.name === "tools") continue;
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) pages(p, out);
    else if (/\.html$/i.test(entry.name) && !/404\.html$/i.test(entry.name)) out.push(p);
  }
  return out;
}

const targets = pages(ROOT, []).sort();

if (LIST) {
  console.log(targets.map((f) => path.relative(ROOT, f)).join("\n"));
  process.exit(0);
}

if (!CHROME) {
  console.error("check-contrast: no chromium on PATH. Install it (see the header of this file).");
  process.exit(2);
}

if (!targets.length) {
  console.log("contrast: no pages to scan");
  process.exit(0);
}

function wrapper(file, theme) {
  const url = "file://" + path.resolve(file);
  return `<!doctype html><meta charset="utf-8"><body><iframe id="f" src="${url}" style="width:1280px;height:900px;border:0"></iframe>
<script>
function lum(c){const f=x=>{x/=255;return x<=0.03928?x/12.92:Math.pow((x+0.055)/1.055,2.4)};return .2126*f(c[0])+.7152*f(c[1])+.0722*f(c[2])}
function cr(a,b){const l1=lum(a),l2=lum(b);const hi=Math.max(l1,l2),lo=Math.min(l1,l2);return (hi+.05)/(lo+.05)}
function parse(s){const m=String(s).match(/rgba?\\(([^)]+)\\)/);if(!m)return null;const p=m[1].split(/[,\\s\\/]+/).filter(Boolean).map(Number);return {r:p[0],g:p[1],b:p[2],a:p.length>3?p[3]:1}}
function gradStops(bi){const out=[];
  for(const chunk of bi.split(')')){
    const hx=chunk.match(/#[0-9a-fA-F]{6}|#[0-9a-fA-F]{3}/g);
    if(hx)for(const h of hx){const c=parse(h);if(c)out.push(c);}
    const at=Math.max(chunk.lastIndexOf('rgba'),chunk.lastIndexOf('rgb'));
    if(at>=0){const n=chunk.slice(at).match(/[0-9.]+/g);
      if(n&&n.length>=3){const a=n.length>3?parseFloat(n[3]):1;if(a>0.9)out.push({r:+n[0],g:+n[1],b:+n[2],a:1});}}
  } return out;}
function surfaces(el,w){
  let n=el;
  while(n&&n.nodeType===1){
    const cs=w.getComputedStyle(n);
    const bi=cs.backgroundImage||'';
    if(bi.includes('gradient')&&!bi.includes('repeating')){
      const st=gradStops(bi); if(st.length)return st;
    }
    const c=parse(cs.backgroundColor);
    if(c&&c.a>0.999)return [c];
    n=n.parentElement;
  }
  const b=parse(w.getComputedStyle(el.ownerDocument.body).backgroundColor);
  return [b&&b.a>0.999?b:[255,255,255,1]];
}
const f=document.getElementById('f');
f.addEventListener('load',()=>{
  const w=f.contentWindow,d=f.contentDocument;
  const st=d.createElement('style');
  st.textContent='*,*::before,*::after{transition:none!important;animation:none!important}';
  (d.head||d.documentElement).appendChild(st);
  const root=d.documentElement;
  root.setAttribute('data-theme','${theme}');
  root.setAttribute('data-mode','${theme}');
  root.classList.toggle('dark','${theme}'==='dark');
  root.classList.toggle('light','${theme}'==='light');
  if(d.body){d.body.setAttribute('data-theme','${theme}');d.body.setAttribute('data-mode','${theme}');}
  setTimeout(()=>{
    const out=[];
    const els=[...d.querySelectorAll('button, a.btn, .btn, .button, [class*="btn"], [class*="button"], [role="button"]')];
    const seen=new Set();
    for(const el of els){
      if(el.disabled)continue;
      const cs=w.getComputedStyle(el);
      if(cs.display==='none'||cs.visibility==='hidden'||el.getClientRects().length===0)continue;
      let fgEl=el;
      const kids=[...el.querySelectorAll('span,label,b,strong,i,em,small')].filter(k=>k.textContent.trim().length);
      if(kids.length)fgEl=kids[kids.length-1];
      const fg=parse(w.getComputedStyle(fgEl).color);
      if(!fg||fg.a<0.999)continue;
      const surfs=surfaces(el,w);
      let worst=Infinity,worstBg=null;
      for(const s of surfs){const c=cr([fg.r,fg.g,fg.b],[s.r,s.g,s.b]);if(c<worst){worst=c;worstBg=s;}}
      if(!isFinite(worst))continue;
      const key=el.tagName+'|'+String(el.className||'')+'|'+cs.color+'|'+worstBg.r+','+worstBg.g+','+worstBg.b;
      if(seen.has(key))continue;seen.add(key);
      out.push({tag:el.tagName.toLowerCase(),cls:String(el.className||'').slice(0,50),
        text:(el.textContent||'').trim().slice(0,24),
        fg:'rgb('+fg.r+','+fg.g+','+fg.b+')',bg:'rgb('+worstBg.r+','+worstBg.g+','+worstBg.b+')',
        ratio:Math.round(worst*100)/100});
    }
    document.body.setAttribute('data-out',JSON.stringify(out));
  },60);
});
</script></body>`;
}

const findings = [];
let measured = 0;

for (const file of targets) {
  for (const theme of ["light", "dark"]) {
    const tmp = path.join(os.tmpdir(), `contrast_${process.pid}_${theme}.html`);
    fs.writeFileSync(tmp, wrapper(file, theme));
    let dom = "";
    try {
      dom = execFileSync(CHROME, ["--headless=new", "--disable-gpu", "--no-sandbox",
        "--allow-file-access-from-files", "--hide-scrollbars", "--window-size=1280,900",
        "--virtual-time-budget=8000", "--dump-dom", tmp],
        { encoding: "utf8", maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "pipe", "ignore"] });
    } catch (e) { dom = String(e.stdout || ""); }
    const m = dom.match(/data-out="([^"]*)"/);
    if (!m) { findings.push({ file, theme, ratio: 0, selector: "(page did not render)", fg: "", bg: "" }); continue; }
    const decoded = m[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#39;/g, "'");
    let rows = [];
    try { rows = JSON.parse(decoded); } catch { rows = []; }
    measured += rows.length;
    for (const row of rows) {
      if (row.ratio < MIN) {
        findings.push({ file, theme, ratio: row.ratio, selector: `${row.tag}.${row.cls}`.slice(0, 70), text: row.text, fg: row.fg, bg: row.bg });
      }
    }
  }
}

if (!findings.length) {
  console.log(`contrast: ${measured} buttons measured across ${targets.length} pages in both themes, none under ${MIN}:1`);
  process.exit(0);
}

console.error(`contrast: ${findings.length} button label(s) under ${MIN}:1\n`);
for (const f of findings) {
  console.error(`  ${f.ratio}:1  [${f.theme}]  ${path.relative(ROOT, f.file)}`);
  console.error(`      ${f.selector}${f.text ? `  "${f.text}"` : ""}`);
  console.error(`      label ${f.fg} on ${f.bg}`);
}
console.error(`
A label this close to its own surface is not a style choice, it is a defect: one
theme renders it invisible. Pair the surface with its own foreground instead of a
fixed white — Tokens.on(surface, mode) in tokens-kit, W.buttonCss() in
widgets-kit.`);
process.exit(1);
