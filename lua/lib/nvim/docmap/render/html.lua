---@module 'lib.nvim.docmap.render.html'
--- Renders the docmap IR as a single self-contained HTML page.
---
--- Self-contained is a hard requirement, not a preference: the artifact has to
--- work from a `file://` URL and from a `gh-pages` branch with no build step,
--- and a documentation page that breaks without network access is a bad
--- documentation page. Everything — CSS, JS, the IR itself — is inlined.
---
--- The IR is embedded as JSON in a `<script type="application/json">` block
--- rather than being expanded into markup at generation time, so the same file
--- powers the tree, the filter and the detail pane without duplicating data.

local json = require("lib.nvim.docmap.json")

local M = {}

---HTML-escape text destined for markup.
---@param s string?
---@return string
local function esc(s)
  if not s or s == "" then
    return ""
  end
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local CSS = [[
:root{
  --bg:#fbfbfa; --panel:#fff; --ink:#1a1a19; --muted:#6b6b68; --line:#e4e4e1;
  --accent:#3b6ea8; --accent-soft:#eaf1f9;
  --error:#b3261e; --warn:#8a5a00; --info:#4a4a48;
  --mod:#3b6ea8; --ns:#7a7a76; --file:#5c8a5c;
  --dep:#a35a2a; --call:#6b4c9a; --fn:#8a5a00; --ext:#2a7a6f;
  --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
}
@media (prefers-color-scheme:dark){
  :root{
    --bg:#16171a; --panel:#1d1f23; --ink:#e6e6e3; --muted:#9a9a95; --line:#2e3136;
    --accent:#7aa9dd; --accent-soft:#22303f;
    --error:#f2837b; --warn:#e0b060; --info:#a8a8a3;
    --mod:#7aa9dd; --ns:#9a9a95; --file:#8fbf8f;
    --dep:#d99b6a; --call:#b09ada; --fn:#e0b060; --ext:#6fc0b3;
  }
}
:root[data-theme="light"]{
  --bg:#fbfbfa; --panel:#fff; --ink:#1a1a19; --muted:#6b6b68; --line:#e4e4e1;
  --accent:#3b6ea8; --accent-soft:#eaf1f9;
  --error:#b3261e; --warn:#8a5a00; --info:#4a4a48;
  --mod:#3b6ea8; --ns:#7a7a76; --file:#5c8a5c;
  --dep:#a35a2a; --call:#6b4c9a; --fn:#8a5a00; --ext:#2a7a6f;
}
:root[data-theme="dark"]{
  --bg:#16171a; --panel:#1d1f23; --ink:#e6e6e3; --muted:#9a9a95; --line:#2e3136;
  --accent:#7aa9dd; --accent-soft:#22303f;
  --error:#f2837b; --warn:#e0b060; --info:#a8a8a3;
  --mod:#7aa9dd; --ns:#9a9a95; --file:#8fbf8f;
  --dep:#d99b6a; --call:#b09ada; --fn:#e0b060; --ext:#6fc0b3;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
  font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
header{padding:20px 24px 14px;border-bottom:1px solid var(--line);
  display:flex;flex-wrap:wrap;gap:14px;align-items:baseline}
h1{margin:0;font-size:20px;font-weight:650;letter-spacing:-.01em}
h1 .sub{color:var(--muted);font-weight:400;font-size:14px;margin-left:8px}
.stats{margin-left:auto;display:flex;gap:14px;font-size:12.5px;color:var(--muted);flex-wrap:wrap}
.stats b{color:var(--ink);font-weight:600}
.toolbar{padding:12px 24px;display:flex;gap:10px;align-items:center;flex-wrap:wrap;
  border-bottom:1px solid var(--line)}
#q{flex:1;min-width:200px;max-width:440px;padding:7px 11px;border:1px solid var(--line);
  border-radius:7px;background:var(--panel);color:var(--ink);font-size:14px}
#q:focus{outline:2px solid var(--accent-soft);border-color:var(--accent)}
button{padding:6px 11px;border:1px solid var(--line);border-radius:7px;background:var(--panel);
  color:var(--ink);font-size:13px;cursor:pointer}
button:hover{border-color:var(--accent);color:var(--accent)}
.tabs{display:flex;gap:2px;padding:0 24px;border-bottom:1px solid var(--line)}
.tab-btn{padding:9px 13px;border:none;background:none;color:var(--muted);font-size:13px;
  cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-1px}
.tab-btn:hover{color:var(--ink)}
.tab-btn.active{color:var(--accent);border-bottom-color:var(--accent);font-weight:600}
.view{display:none}
.view.active{display:block}
main.view.active{display:grid}
main{grid-template-columns:minmax(300px,1.1fr) minmax(0,1.4fr);gap:0;align-items:start}
@media (max-width:860px){main{grid-template-columns:1fr}}
#tree{padding:12px 8px 60px 16px;border-right:1px solid var(--line);
  max-height:calc(100vh - 132px);overflow:auto}
@media (max-width:860px){#tree{max-height:none;border-right:0;border-bottom:1px solid var(--line)}}
.row{display:flex;align-items:baseline;gap:7px;padding:3px 8px;border-radius:6px;cursor:pointer;
  white-space:nowrap}
.row:hover{background:var(--accent-soft)}
.row.sel{background:var(--accent-soft);box-shadow:inset 2px 0 0 var(--accent)}
.tw{width:14px;flex:none;color:var(--muted);font-size:11px;user-select:none}
.nm{font-family:var(--mono);font-size:13px}
.k-module .nm{color:var(--mod)} .k-namespace .nm{color:var(--ns)} .k-file .nm{color:var(--file)}
.sm{color:var(--muted);font-size:12px;overflow:hidden;text-overflow:ellipsis;flex:1;min-width:0}
.badges{display:flex;gap:4px;flex:none}
.bd{font-size:9.5px;letter-spacing:.04em;text-transform:uppercase;padding:1px 5px;
  border-radius:4px;border:1px solid var(--line);color:var(--muted)}
.bd.rd{color:var(--accent);border-color:var(--accent)}
.bd.dep{color:var(--error);border-color:var(--error)}
.bd.tested{color:var(--accent);border-color:var(--accent)}
.kids{margin-left:15px;border-left:1px solid var(--line);padding-left:3px}
.kids.hide{display:none}
#detail{padding:22px 26px 60px;max-height:calc(100vh - 132px);overflow:auto}
@media (max-width:860px){#detail{max-height:none}}
#detail h2{margin:0 0 3px;font-size:17px;font-family:var(--mono);font-weight:600}
.mp{font-family:var(--mono);font-size:12.5px;color:var(--muted);margin-bottom:16px;
  word-break:break-all}
.links{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 18px}
.links a{font-size:12.5px;padding:4px 10px;border:1px solid var(--line);border-radius:6px;
  text-decoration:none;color:var(--accent);background:var(--panel)}
.links a:hover{border-color:var(--accent)}
.prose{white-space:pre-wrap;font-size:13.5px;color:var(--ink);
  background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:13px 15px;
  margin-bottom:18px;overflow-x:auto}
.sec{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);
  margin:18px 0 7px;font-weight:600}
.lst{list-style:none;margin:0;padding:0}
.lst li{font-family:var(--mono);font-size:12.5px;padding:2px 0;color:var(--muted)}
.empty{color:var(--muted);font-size:13.5px;font-style:italic}
.fn{margin-bottom:14px;padding-bottom:12px;border-bottom:1px dashed var(--line)}
.fn:last-child{border-bottom:0;padding-bottom:0;margin-bottom:0}
.fn-sig{font-family:var(--mono);font-size:12.5px;color:var(--ink);font-weight:600}
.fn-badges{display:inline-flex;gap:4px;margin-left:8px;vertical-align:middle}
.fn-desc{font-size:12.5px;color:var(--muted);margin:4px 0}
.fn-dep{color:var(--error);font-size:11.5px;font-weight:600;margin:4px 0}
.fn-plist{list-style:none;margin:4px 0;padding:0;font-size:11.5px}
.fn-plist li{padding:1px 0}
.fn-plist code{background:none;padding:0;color:var(--accent)}
.fn-ex{font-family:var(--mono);font-size:11.5px;white-space:pre-wrap;background:var(--accent-soft);
  border-radius:6px;padding:8px 10px;margin-top:6px;overflow-x:auto}
.fn-see a{color:var(--accent);text-decoration:none}
.fn-see a:hover{text-decoration:underline}
code{font-family:var(--mono);font-size:.92em;background:var(--accent-soft);
  padding:1px 4px;border-radius:4px}
#findings{padding:0 24px 50px}
#findings table{border-collapse:collapse;width:100%;font-size:12.5px}
#findings th{text-align:left;padding:6px 9px;border-bottom:1px solid var(--line);
  color:var(--muted);font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:.05em}
#findings td{padding:5px 9px;border-bottom:1px solid var(--line);vertical-align:top}
#findings td.msg{font-family:var(--mono);font-size:11.5px;word-break:break-word}
.sev{font-weight:650;text-transform:uppercase;font-size:10px;letter-spacing:.05em}
.sev.error{color:var(--error)} .sev.warn{color:var(--warn)} .sev.info{color:var(--info)}
details>summary{cursor:pointer;font-size:13px;color:var(--muted);padding:8px 0}
.wrap{overflow-x:auto}
#view-notes{padding:22px 26px 60px}
#view-notes h3{margin:26px 0 4px;font-size:13px;font-weight:600;color:var(--ink)}
#view-notes h3:first-child{margin-top:0}
#view-notes .nsub,#view-index .nsub,#view-analysis .nsub{font-size:12px;color:var(--muted);
  margin:0 0 10px}
#view-notes .ncount,#view-index .ncount{color:var(--muted);font-weight:400;font-size:11.5px;
  margin-left:6px}
.nlist{list-style:none;margin:0;padding:0}
.nlist li{padding:7px 0;border-bottom:1px dashed var(--line)}
.nlist li:last-child{border-bottom:0}
.nlist .nfn{font-family:var(--mono);font-size:12.5px;color:var(--accent);
  text-decoration:none;font-weight:600;cursor:pointer}
.nlist .nfn:hover{text-decoration:underline}
.nlist .nwhere{font-family:var(--mono);font-size:11px;color:var(--muted);margin-left:8px}
.nlist .ntext{font-size:12.5px;color:var(--ink);margin-top:2px}
.nlist .ntext.none{color:var(--muted);font-style:italic}
#view-index{padding:22px 26px 60px}
#ixtoggle{margin-bottom:14px}
#view-analysis{padding:22px 26px 60px}
#antoggle{margin-bottom:14px}
.antable{width:100%;border-collapse:collapse;font-size:12.5px}
.antable th{text-align:left;font-weight:600;color:var(--muted);font-size:11px;
  text-transform:uppercase;letter-spacing:.03em;padding:4px 8px;border-bottom:1px solid var(--line)}
.antable td{padding:5px 8px;border-bottom:1px dashed var(--line);font-family:var(--mono)}
.anrow{cursor:pointer}
.anrow:hover td{background:var(--accent-soft)}
.anbar{width:120px;height:8px;background:var(--line);border-radius:4px;overflow:hidden}
.anfill{height:100%;background:var(--accent)}
#view-index h3{margin:22px 0 6px;font-size:15px;font-weight:700;color:var(--accent);
  font-family:var(--mono);border-bottom:1px solid var(--line);padding-bottom:3px}
.ixjump{display:flex;flex-wrap:wrap;gap:3px;margin:0 0 6px;position:sticky;top:0;
  background:var(--bg);padding:6px 0;z-index:2}
.ixjump a{font-family:var(--mono);font-size:12px;padding:2px 7px;border-radius:5px;
  border:1px solid var(--line);color:var(--accent);cursor:pointer;text-decoration:none}
.ixjump a:hover{border-color:var(--accent);background:var(--accent-soft)}
.ixlist li{display:flex;align-items:baseline;gap:8px;flex-wrap:wrap;padding:3px 0}
.ixtag{font-size:9.5px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);
  border:1px solid var(--line);border-radius:4px;padding:0 4px}
.ixtag.dep{color:var(--error);border-color:var(--error)}
.ixtag.tested{color:var(--accent);border-color:var(--accent)}
#view-hierarchy{padding:16px 24px 60px}
.hctl{display:flex;gap:8px;align-items:center;margin-bottom:14px;flex-wrap:wrap}
.hctl .hpath{font-family:var(--mono);font-size:12.5px;color:var(--muted);word-break:break-all}
.hctl button{padding:4px 9px;font-size:12px}
#hgraph-wrap{overflow:auto;border:1px solid var(--line);border-radius:8px;background:var(--panel)}
#hgraph{position:relative}
/* The zoom lives on its own layer. #hstage carries the transform and keeps the
   analytic pixel layout; #hgraph is sized to the *scaled* extent, because a
   transform does not change layout size and the scroll area would otherwise
   not grow when zooming in. */
#hstage{position:absolute;top:0;left:0;transform-origin:0 0;will-change:transform}
#hstage.zooming{transition:none}
#hstage.jumping{transition:transform .34s cubic-bezier(.2,.7,.2,1)}
/* Level of detail: below ~0.65 the secondary line is unreadable grey noise,
   so it goes away rather than being rendered illegibly. Pure CSS — no redraw. */
#hstage.lod-min .hsm,#hstage.lod-min .hline,#hstage.lod-min .hkind{display:none}
#hstage.lod-min .hnode{padding:4px 8px}
.hzoom{font-family:var(--mono);font-size:11.5px;color:var(--muted);min-width:44px;
  text-align:right}
@media (prefers-reduced-motion:reduce){#hstage.jumping{transition:none}}
.hnode{position:absolute;box-sizing:border-box;padding:7px 10px;border:1px solid var(--line);
  border-radius:7px;background:var(--panel);cursor:pointer;overflow:hidden}
.hnode:hover{border-color:var(--accent);z-index:1}
.hnode .hnm{font-family:var(--mono);font-size:12px;font-weight:600;white-space:nowrap;
  overflow:hidden;text-overflow:ellipsis}
.hnode .hsm{font-size:10.5px;color:var(--muted);margin-top:2px;max-height:2.6em;overflow:hidden}
.hnode.k-module .hnm{color:var(--mod)} .hnode.k-namespace .hnm{color:var(--ns)} .hnode.k-file .hnm{color:var(--file)}
#hsvg{position:absolute;top:0;left:0;pointer-events:none}
.hedge{fill:none;stroke:var(--muted);stroke-width:1.5;opacity:.6}
.hedge-type{stroke:var(--accent);stroke-dasharray:4 3;opacity:.75}
.hedge-ext{stroke:var(--ext);stroke-width:2;opacity:.9}
.hmsg{color:var(--muted);font-size:13px;padding:20px;text-align:center}
.htrunc{color:var(--warn);font-size:12px;margin-top:8px}
.hview-toggle{display:flex;gap:0;border:1px solid var(--line);border-radius:7px;overflow:hidden}
.hview-toggle button{border:none;border-radius:0;padding:4px 10px;font-size:12px}
.hview-toggle button+button{border-left:1px solid var(--line)}
.hview-toggle button.active{background:var(--accent-soft);color:var(--accent);font-weight:600}
.hnode.t-class .hnm{color:var(--mod)}
.hnode.t-alias .hnm{color:var(--ns)}
.hnode .hkind{font-size:9px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin-top:1px}
/* --- Stats grid + module-scope symbols in the detail pane --------------- */
.stat-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(96px,1fr));gap:7px;
  margin-bottom:6px}
.stat{border:1px solid var(--line);border-radius:7px;padding:6px 9px;background:var(--panel)}
.stat b{display:block;font-size:15px;font-weight:650;font-family:var(--mono)}
.stat span{font-size:10.5px;color:var(--muted)}
.sec .sub{text-transform:none;letter-spacing:0;font-weight:400;font-size:10.5px}
.lst.syms li{padding:4px 0;color:var(--ink)}
.sdet{color:var(--muted);font-size:11.5px;font-family:var(--mono)}
.bd.sk-table{color:var(--mod);border-color:var(--mod)}
.bd.sk-constant{color:var(--file);border-color:var(--file)}
.bd.sk-binding{color:var(--ns)}
#findings tbody tr[data-node]{cursor:pointer}
#findings tbody tr[data-node]:hover{background:var(--accent-soft)}

/* --- Function rows in the tree ------------------------------------------ */
.row.k-fn .nm{color:var(--fn)}
.row.fnhead .nm{color:var(--muted);font-style:italic}
.fnkids.hide{display:none}

/* --- Graph: edge kinds, arrowheads, legend ------------------------------ */
.hedge-dep{stroke:var(--dep);opacity:.8}
.hedge-dep.deferred{stroke-dasharray:2 4;opacity:.55}
.hedge-dep.external{stroke-dasharray:6 3;opacity:.5}
.hnode.k-external{border-style:dashed;background:none}
.hnode.k-external .hnm{color:var(--muted)}
.hnode.k-external.linked{border-style:solid;border-color:var(--accent)}
.hnode.k-external.linked .hnm{color:var(--accent)}
.hlegend .sw.dep.external{border-top-style:dashed}
#hext.active button{background:var(--accent-soft);color:var(--accent);font-weight:600}
.hedge-call{stroke:var(--call);opacity:.8}
.hedge-call.weak{stroke-dasharray:3 4;opacity:.5}
#hsvg marker path{stroke:none}
#m-tree path{fill:var(--muted)}
#m-type path{fill:var(--accent)}
#m-ext path{fill:var(--ext)}
#m-dep path{fill:var(--dep)}
#m-call path{fill:var(--call)}
.hlegend{display:flex;gap:12px;flex-wrap:wrap;align-items:center;margin:10px 0 0;
  font-size:11.5px;color:var(--muted)}
.hlegend .lg{display:inline-flex;align-items:center;gap:5px}
.hlegend .sw{width:20px;height:0;border-top:2px solid var(--muted)}
.hlegend .sw.type{border-top-style:dashed;border-top-color:var(--accent)}
.hlegend .sw.ext{border-top-color:var(--ext);border-top-width:3px}
.hlegend .sw.dep{border-top-color:var(--dep)}
.hlegend .sw.dep.deferred{border-top-style:dotted}
.hlegend .sw.call{border-top-color:var(--call)}
.hlegend .sw.call.weak{border-top-style:dashed}
.hlegend .bx{width:11px;height:11px;border-radius:3px;border:1px solid currentColor}
.hnode.k-fn .hnm{color:var(--fn)}
.hnode.center{border-color:var(--accent);box-shadow:0 0 0 2px var(--accent-soft)}
.hnode .hline{font-size:9.5px;color:var(--muted);margin-top:1px;font-family:var(--mono)}

/* --- Graph: movement ---------------------------------------------------
   Boxes keep their identity across redraws (see reconcile() in the JS), so a
   re-center animates the boxes that survive from their old position to their
   new one instead of the whole diagram cutting. left/top are transitioned
   rather than transform, because positions are already absolute pixels
   computed from the IR — a transform would need a second coordinate system
   for no gain. */
.hnode{transition:left .34s cubic-bezier(.2,.7,.2,1),top .34s cubic-bezier(.2,.7,.2,1),
  opacity .22s ease,border-color .15s ease}
.hnode.entering{opacity:0;transform:scale(.94)}
.hnode.leaving{opacity:0;pointer-events:none}
#hsvg{transition:opacity .18s ease}
#hsvg.settling{opacity:0}
.hnode.pulse{animation:hpulse .7s ease-out}
@keyframes hpulse{
  0%{box-shadow:0 0 0 0 var(--accent)}
  100%{box-shadow:0 0 0 12px transparent}
}
/* Hover focus: dim everything that is not a direct neighbour. Class-driven so
   it costs no layout recomputation on a graph that can hold 90 boxes. */
#hgraph.focusing .hnode{opacity:.22}
#hgraph.focusing .hnode.near{opacity:1}
#hgraph.focusing .hedge{opacity:.08}
#hgraph.focusing .hedge.near{opacity:1;stroke-width:2}
.hedge{transition:opacity .15s ease}
@media (prefers-reduced-motion:reduce){
  .hnode,#hsvg,.hedge{transition:none}
  .hnode.pulse{animation:none}
}

/* --- Context menu ------------------------------------------------------- */
#ctx{position:fixed;z-index:50;min-width:210px;padding:5px;border:1px solid var(--line);
  border-radius:9px;background:var(--panel);box-shadow:0 8px 28px rgba(0,0,0,.18);display:none}
#ctx.open{display:block}
#ctx .ci{display:flex;align-items:center;gap:8px;padding:6px 10px;border-radius:6px;
  font-size:12.5px;cursor:pointer;white-space:nowrap;color:var(--ink)}
#ctx .ci:hover,#ctx .ci.hi{background:var(--accent-soft);color:var(--accent)}
#ctx .ci.disabled{color:var(--muted);cursor:default;opacity:.6}
#ctx .ci.disabled:hover{background:none;color:var(--muted)}
#ctx .ci .hint{margin-left:auto;font-size:10.5px;color:var(--muted)}
#ctx .sep{height:1px;background:var(--line);margin:4px 6px}
#ctx .hdr{padding:5px 10px 6px;font-family:var(--mono);font-size:11px;color:var(--muted);
  max-width:280px;overflow:hidden;text-overflow:ellipsis}
]]

local JS = [[
(function(){
  var IR = JSON.parse(document.getElementById("ir").textContent);
  var FIND = JSON.parse(document.getElementById("findings-data").textContent);
  var byId = {}; IR.nodes.forEach(function(n){ byId[n.id] = n; });

  var findByNode = {};
  FIND.forEach(function(f){ if(!f.node) return;
    (findByNode[f.node] = findByNode[f.node] || []).push(f); });

  // className -> { info: Lib.Docmap.TypeInfo, nodeId: owning node id }. Built
  // once so the Types hierarchy view and any class lookup can go straight to
  // a class by name instead of re-scanning every node's types_detail.
  var classByName = {};
  IR.nodes.forEach(function(n){
    (n.types_detail || []).forEach(function(t){ classByName[t.name] = { info: t, nodeId: n.id }; });
  });

  // ---------------------------------------------------------------------
  // Functions as first-class, addressable objects.
  //
  // "<node id>#<declared name>" — derivable from data already in the IR, so
  // no id has to be generated and serialized, and stable across regenerations
  // as long as the function keeps its name. This is what makes a function
  // something the URL can point at, the Calls view can center on, and the
  // context menu can act on; before it, a function existed only as a block of
  // text inside one node's detail pane.
  // ---------------------------------------------------------------------
  function fnKey(nodeId, name){ return nodeId + "#" + name; }

  var fnByKey = {};
  IR.nodes.forEach(function(n){
    (n.functions || []).forEach(function(fn){
      fnByKey[fnKey(n.id, fn.name)] = { node: n, fn: fn, key: fnKey(n.id, fn.name) };
    });
  });

  // Blast radius: the transitive closure of `required_by`. Already implied
  // by the edges and visible nowhere, and it is the number that says how
  // risky a change to a module is — the same measurement before and after a
  // refactor is evidence that the refactor decoupled something.
  var impactCache = {};
  function impactOf(id){
    if(impactCache[id]) return impactCache[id];
    var seen = {}, queue = [id], qi = 0, out = [];
    seen[id] = true;
    while(qi < queue.length){
      var cur = queue[qi++];
      ((byId[cur] || {}).required_by || []).forEach(function(dep){
        if(seen[dep]) return;
        seen[dep] = true;
        out.push(dep);
        queue.push(dep);
      });
    }
    impactCache[id] = out;
    return out;
  }

  // Edges arrive as one array with a `kind` discriminator; every consumer
  // wants one kind at a time, and both directions of it. Built once here
  // rather than filtered per redraw — a re-center at depth 3 would otherwise
  // walk all ~1300 edges once per layer.
  var depOut = {}, depIn = {}, callOut = {}, callIn = {}, typeEdges = [];
  // Inheritance, keyed both ways by class name: `extUp` answers "who are my
  // parents", `extDown` "who inherits me". An edge is stored as written
  // (from_class = the child, to_class = the parent), so which end is "next"
  // depends on which map you came in through — see layoutInheritance.
  var extUp = {}, extDown = {}, extendsEdges = [];
  function push(map, key, val){ (map[key] = map[key] || []).push(val); }
  (IR.edges || []).forEach(function(e){
    if(e.kind === "require"){
      push(depOut, e.from, e); push(depIn, e.to, e);
    } else if(e.kind === "call"){
      push(callOut, fnKey(e.from, e.from_fn), e);
      push(callIn, fnKey(e.to, e.to_fn), e);
    } else if(e.kind === "type"){
      typeEdges.push(e);
    } else if(e.kind === "extends"){
      extendsEdges.push(e);
      push(extUp, e.from_class, e);
      push(extDown, e.to_class, e);
    }
  });

  // Classes that take part in at least one inheritance relation. The
  // Inheritance view seeds from these rather than from every class the
  // centered node declares: a class with no parent and no subclass is an
  // isolated box in a view that exists to show relationships, and most nodes
  // declare several of those — they would crowd out the handful of boxes that
  // actually connect.
  var inInheritance = {};
  extendsEdges.forEach(function(e){
    inInheritance[e.from_class] = true;
    inInheritance[e.to_class] = true;
  });

  // @see target -> owning node id. Same three resolution shapes as
  // docmap.check's check_see_targets, kept in sync deliberately: a bare
  // module path, "module.bareName" (the qualified form a reader would
  // actually write), and the raw declared name (e.g. "M.scan_full") as a
  // fallback for targets copy-pasted straight from source.
  var seeIndex = {};
  IR.nodes.forEach(function(n){
    if(n.module) seeIndex[n.module] = n.id;
    (n.functions || []).forEach(function(fn){
      seeIndex[fn.name] = n.id;
      if(n.module){
        var bare = fn.name.replace(/^[A-Z][\w]*\./, "");
        seeIndex[n.module + "." + bare] = n.id;
      }
    });
  });

  var repo = IR.meta.repo_url, branch = IR.meta.branch || "main";
  function srcUrl(p){ return repo ? repo + "/blob/" + branch + "/" + p : null; }

  function esc(s){ return (s||"").replace(/[&<>"]/g, function(c){
    return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]; }); }

  // Artifact lives in out_dir; repo-relative paths need to climb back out.
  function rel(p){ return (IR.meta.out_depth ? "../".repeat(IR.meta.out_depth) : "") + p; }

  // =====================================================================
  // State + history
  //
  // One object describes everything the page can be showing:
  //   { tab: "tree"|"hierarchy", id: <selected tree node>,
  //     center: <hierarchy centered node>,
  //     view: "modules"|"types"|"deps"|"calls",
  //     dir: "out"|"in"|"both",   — deps/calls only: follow edges forwards
  //                                 (what this needs), backwards (what needs
  //                                 this), or both around the center
  //     depth: 1|2|3|0,           — 0 means unbounded, still capped by MAX_HNODES
  //     fn: "<node id>#<name>" }  — calls view centered on one function
  //
  // Direction is an axis rather than two more views on purpose: "callers of X"
  // and "callees of X" are the same diagram walked the other way, and making
  // them separate views would have doubled the view list to four buttons
  // saying almost the same thing.
  //
  // navigate(patch) is the single entry point every discrete click handler
  // calls; it merges the patch into current state, updates the DOM, and
  // pushes a real history entry so the browser Back/Forward buttons step
  // through actual states instead of only reacting to a directly-edited
  // hash. Every axis above goes through it — a control that set `dir` or
  // `depth` behind its back would produce a diagram the Back button cannot
  // return from. Live preview while typing in the Hierarchy search box is the
  // one deliberate exception — see the "input" listener below for why going
  // through history.replaceState there was a real bug, not just an
  // unnecessary one.
  // =====================================================================
  var DEFAULT_STATE = {
    tab: "tree", id: null, center: null, view: "modules",
    dir: "out", depth: 2, fn: null, ext: false, iview: "functions", atool: "test"
  };
  function freshState(){ return Object.assign({}, DEFAULT_STATE); }

  var state = freshState();
  // Tracks only the hash of the last *pushed* entry — deliberately never
  // touched by a replace. Search-as-you-type replaces the current entry on
  // every keystroke; without this separation, typing to a match and then
  // pressing Enter to commit it would compute the same resulting hash the
  // last replace already wrote, and a single "skip if hash unchanged" guard
  // would then suppress the deliberate push entirely — Enter would silently
  // do nothing. Keeping the two trackers apart means a push always executes
  // unless the *previous push* (not the previous replace) had that hash.
  var lastPushedHash = null;

  // Only axes that matter for the current view are serialized: a Tree-tab URL
  // carrying dir/depth/view would be three pieces of noise in every link
  // anyone shares, and a Modules-view URL carrying `dir` would suggest a
  // control that view does not have.
  function isGraphView(v){ return v === "deps" || v === "calls"; }

  function serializeState(s){
    var parts = ["tab=" + encodeURIComponent(s.tab)];
    if(s.tab === "tree"){
      if(s.id) parts.push("id=" + encodeURIComponent(s.id));
    } else if(s.tab === "notes"){
      // Nothing else to carry: a flat aggregate over the whole map, with no
      // center, view or direction to remember. Falling through to the
      // hierarchy branch would put a `view=modules` in every shared link that
      // means nothing there.
      void 0;
    } else if(s.tab === "index"){
      // One axis, not the hierarchy branch's whole set: R3's Functions/
      // Modules toggle, omitted when it is the default so the common case
      // stays a bare `#tab=index` link.
      if(s.iview === "modules") parts.push("iview=modules");
    } else if(s.tab === "analysis"){
      // Same rule, Analysis's own one axis: which tool panel is open.
      if(s.atool !== "test") parts.push("atool=" + encodeURIComponent(s.atool));
    } else {
      if(s.center) parts.push("center=" + encodeURIComponent(s.center));
      parts.push("view=" + encodeURIComponent(s.view || "modules"));
      if(isGraphView(s.view)){
        parts.push("dir=" + encodeURIComponent(s.dir || "out"));
        parts.push("depth=" + encodeURIComponent(String(s.depth === 0 ? 0 : (s.depth || 2))));
      }
      // Only when on, and only where it applies: an "ext=0" in every Deps
      // link would be noise in the common case.
      if(s.view === "deps" && s.ext) parts.push("ext=1");
      if(s.view === "calls" && s.fn) parts.push("fn=" + encodeURIComponent(s.fn));
    }
    return "#" + parts.join("&");
  }

  function parseState(hash){
    var s = freshState();
    var raw = (hash || "").replace(/^#/, "");
    if(!raw) return s;
    // A bare node id with no "=" is the pre-existing #<id> scheme (also what
    // a hand-typed or externally shared link looks like) — treat it as
    // "select this node in the Tree tab".
    if(raw.indexOf("=") === -1){
      s.id = decodeURIComponent(raw);
      return s;
    }
    raw.split("&").forEach(function(kv){
      var i = kv.indexOf("=");
      if(i < 0) return;
      var k = kv.slice(0, i), v = decodeURIComponent(kv.slice(i + 1));
      if(k === "tab") s.tab = v;
      else if(k === "id") s.id = v;
      else if(k === "center") s.center = v;
      else if(k === "view") s.view = v;
      else if(k === "dir") s.dir = (v === "in" || v === "both") ? v : "out";
      // Anything unparseable falls back to the default rather than to NaN,
      // which would make every BFS below terminate immediately and draw an
      // empty diagram for a URL that merely had a typo in it.
      else if(k === "depth"){ var d = parseInt(v, 10); s.depth = isNaN(d) ? 2 : d; }
      else if(k === "fn") s.fn = v;
      else if(k === "ext") s.ext = (v === "1" || v === "true");
      else if(k === "iview") s.iview = (v === "modules") ? "modules" : "functions";
      else if(k === "atool") s.atool = (v === "doc" || v === "deps" || v === "complexity") ? v : "test";
    });
    return s;
  }

  // Applies `s` to the DOM. `push` controls history: true adds a Back-stack
  // entry (every discrete navigate() call), false replaces the current entry
  // in place (restoring state after a popstate, and the very first load —
  // neither should itself create a Back-stack entry). Never mutates `state`
  // directly outside this function, so `state` always reflects exactly what
  // is on screen.
  function applyState(s, push){
    state = s;

    document.querySelectorAll(".tab-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.tab === s.tab);
    });
    document.getElementById("view-tree").classList.toggle("active", s.tab === "tree");
    document.getElementById("view-hierarchy").classList.toggle("active", s.tab === "hierarchy");
    document.getElementById("view-notes").classList.toggle("active", s.tab === "notes");
    document.getElementById("view-index").classList.toggle("active", s.tab === "index");
    document.getElementById("view-analysis").classList.toggle("active", s.tab === "analysis");

    if(s.tab === "tree" && s.id && byId[s.id]) selectRow(s.id);
    if(s.tab === "hierarchy") drawHierarchy(s.center || IR.root, s.view || "modules");
    if(s.tab === "notes") drawNotes();
    if(s.tab === "index") drawIndex();
    if(s.tab === "analysis") drawAnalysis();
    syncGraphControls(s);

    var hash = serializeState(s);
    if(push){
      if(hash !== lastPushedHash){
        history.pushState(s, "", hash);
        lastPushedHash = hash;
      }
    } else {
      history.replaceState(s, "", hash);
    }
  }

  function navigate(patch){
    applyState(Object.assign({}, state, patch), true);
  }

  window.addEventListener("popstate", function(ev){
    applyState(ev.state || parseState(location.hash), false);
  });

  // =====================================================================
  // Tree tab
  // =====================================================================
  var treeEl = document.getElementById("tree");
  var detailEl = document.getElementById("detail");
  var selectedRowId = null;

  function badges(n){
    var b = [];
    if(n.readme) b.push('<span class="bd rd">readme</span>');
    if(n.types && n.types.length) b.push('<span class="bd">types</span>');
    var f = findByNode[n.id] || [];
    if(f.some(function(x){return x.severity==="error";})) b.push('<span class="bd" style="color:var(--error);border-color:var(--error)">drift</span>');
    return b.length ? '<span class="badges">'+b.join("")+'</span>' : "";
  }

  // Functions hang under their node behind their own collapsed group rather
  // than being mixed into `children`. Two reasons: `children` is IR structure
  // and functions are not part of it, and this tree renders eagerly — folding
  // ~1500 function rows into the always-expanded default would bury the
  // module structure the tree exists to show. One extra row per node, opened
  // on demand, costs nothing until asked for.
  function renderFunctionGroup(n){
    var group = document.createElement("div");

    var head = document.createElement("div");
    head.className = "row fnhead";
    head.innerHTML = '<span class="tw">▸</span>' +
      '<span class="nm">ƒ ' + n.functions.length + ' function' +
      (n.functions.length === 1 ? '' : 's') + '</span>';

    var list = document.createElement("div");
    list.className = "kids fnkids hide";

    n.functions.forEach(function(fn){
      var key = fnKey(n.id, fn.name);
      var r = document.createElement("div");
      r.className = "row k-fn";
      r.dataset.fn = key;
      r.dataset.id = n.id;
      r.innerHTML = '<span class="tw"></span>' +
        '<span class="nm">' + esc(fn.signature) + '</span>' +
        '<span class="sm">' + esc(fn.summary || "") + '</span>';
      r.addEventListener("click", function(){
        navigate({ tab: "tree", id: n.id });
      });
      list.appendChild(r);
    });

    head.addEventListener("click", function(ev){
      ev.stopPropagation();
      list.classList.toggle("hide");
      head.querySelector(".tw").textContent = list.classList.contains("hide") ? "▸" : "▾";
    });

    group.appendChild(head);
    group.appendChild(list);
    return group;
  }

  function renderNode(n){
    var kids = (n.children||[]).map(function(id){ return byId[id]; }).filter(Boolean);
    var hasFns = (n.functions || []).length > 0;
    var hasKids = kids.length > 0 || hasFns;
    var row = document.createElement("div");
    row.className = "row k-" + n.kind;
    row.dataset.id = n.id;
    row.innerHTML =
      '<span class="tw">' + (hasKids ? "▾" : "") + '</span>' +
      '<span class="nm">' + esc(n.name) + '</span>' +
      badges(n) +
      '<span class="sm">' + esc(n.summary || "") + '</span>';

    var box = document.createElement("div");
    box.appendChild(row);

    if(hasKids){
      var kidsEl = document.createElement("div");
      kidsEl.className = "kids";
      kids.forEach(function(k){ kidsEl.appendChild(renderNode(k)); });
      if(hasFns) kidsEl.appendChild(renderFunctionGroup(n));
      box.appendChild(kidsEl);
      row.querySelector(".tw").addEventListener("click", function(ev){
        ev.stopPropagation();
        kidsEl.classList.toggle("hide");
        this.textContent = kidsEl.classList.contains("hide") ? "▸" : "▾";
      });
    }
    row.addEventListener("click", function(){ navigate({ tab: "tree", id: n.id }); });
    return box;
  }

  // DOM-only: row highlight + detail pane. No history side effects — that is
  // applyState's job, so this can be called from anywhere (including a
  // popstate restore) without ever touching the URL itself.
  function selectRow(id){
    var n = byId[id]; if(!n) return;
    if(selectedRowId){ var p = treeEl.querySelector('.row[data-id="'+CSS.escape(selectedRowId)+'"]');
      if(p) p.classList.remove("sel"); }
    selectedRowId = id;
    var cur = treeEl.querySelector('.row[data-id="'+CSS.escape(id)+'"]');
    if(cur) cur.classList.add("sel");
    renderDetail(n);
  }

  function renderDetail(n){
    var h = [];
    h.push('<h2>'+esc(n.name)+'</h2>');
    h.push('<div class="mp">'+esc(n.module || n.path)+'</div>');

    var links = [];
    if(n.readme) links.push('<a href="'+esc(rel(n.readme))+'">README</a>');
    if(n.source){ var u = srcUrl(n.source);
      links.push(u ? '<a href="'+esc(u)+'">source ↗</a>' : '<a href="'+esc(rel(n.source))+'">source</a>'); }
    (n.types||[]).forEach(function(t){
      var u2 = srcUrl(t);
      links.push(u2 ? '<a href="'+esc(u2)+'">types ↗</a>' : '<a href="'+esc(rel(t))+'">types</a>');
    });
    if(n.kind !== "file"){
      links.push('<a href="#" data-goto="hierarchy">Hierarchy ↳</a>');
    }
    if((n.requires||[]).length || (n.required_by||[]).length){
      links.push('<a href="#" data-goto="deps">Dependencies ↳</a>');
    }
    if((n.functions||[]).length){
      links.push('<a href="#" data-goto="calls">Calls ↳</a>');
    }
    if(links.length) h.push('<div class="links">'+links.join("")+'</div>');

    if(n.summary || n.body){
      h.push('<div class="prose">'+esc([n.summary, n.body].filter(Boolean).join("\n\n"))+'</div>');
    } else {
      h.push('<p class="empty">No description — this module has an @module tag but no prose.</p>');
    }

    var f = findByNode[n.id] || [];
    if(f.length){
      h.push('<div class="sec">Drift</div><ul class="lst">');
      f.forEach(function(x){ h.push('<li><span class="sev '+x.severity+'">'+x.severity+'</span> '+esc(x.message)+'</li>'); });
      h.push('</ul>');
    }

    // Stats before anything else in the body: "how big is this and what is in
    // it" is the question asked on arrival, and it is the one thing that was
    // impossible to answer from the map at all. Zero-valued entries are
    // dropped rather than shown as "0 markdown", which would be five sixths
    // noise on a leaf file.
    var st = n.stats || {};
    var cells = [
      ["modules", st.modules], ["namespaces", st.namespaces],
      ["lua files", st.files_lua], ["markdown", st.files_md],
      ["other files", st.files_other], ["lines of lua", st.lines],
      ["functions", st.functions], ["tables & values", st.symbols],
      ["types", st.types]
    ].filter(function(c){ return c[1]; });
    if(cells.length){
      h.push('<div class="sec">Stats' +
        (n.kind === "file" ? '' : ' <span class="sub">(this and everything below)</span>') +
        '</div><div class="stat-grid">');
      cells.forEach(function(c){
        h.push('<div class="stat"><b>' + c[1].toLocaleString() + '</b><span>' + esc(c[0]) + '</span></div>');
      });
      h.push('</div>');
    }

    // Dependencies as text, next to the diagram that draws the same thing:
    // the graph answers "what does this sit in the middle of", a list answers
    // "is X in there", and the second question is the more common one.
    function depList(title, ids){
      if(!ids || !ids.length) return;
      h.push('<div class="sec">'+title+' ('+ids.length+')</div><ul class="lst">');
      ids.forEach(function(id){
        var t = byId[id];
        if(!t) return;
        h.push('<li><a href="#" data-node-link="'+esc(id)+'">'+esc(t.module || t.path)+'</a></li>');
      });
      h.push('</ul>');
    }
    depList("Requires", n.requires);
    depList("Required by", n.required_by);

    // Stated even when it is zero: "nothing depends on this" is itself the
    // answer to "is this safe to change".
    if((n.requires || []).length || (n.required_by || []).length){
      var hull = impactOf(n.id);
      h.push('<div class="sec">Impact</div><ul class="lst"><li>' +
        '<b>' + hull.length + '</b> module' + (hull.length === 1 ? '' : 's') +
        ' would be affected by changing this — ' + (n.required_by || []).length +
        ' directly.</li></ul>');
    }

    if(n.types_detail && n.types_detail.length){
      h.push('<div class="sec">Types ('+n.types_detail.length+')</div><ul class="lst">');
      n.types_detail.forEach(function(t){
        h.push('<li>'+t.kind+' <code>'+esc(t.name)+'</code>'+(t.fields.length?' — '+t.fields.length+' field'+(t.fields.length===1?'':'s'):'')+'</li>');
      });
      h.push('</ul>');
    }

    if(n.functions && n.functions.length){
      h.push('<div class="sec">Functions ('+n.functions.length+')</div>');
      n.functions.forEach(function(fn){
        var key = fnKey(n.id, fn.name);
        h.push('<div class="fn" data-fn="'+esc(key)+'">');
        var badges = [];
        if(fn.deprecated !== undefined) badges.push('<span class="bd dep">deprecated</span>');
        if(fn.async) badges.push('<span class="bd">async</span>');
        if(fn.nodiscard) badges.push('<span class="bd">nodiscard</span>');
        if(fn.internal) badges.push('<span class="bd sk-binding">internal</span>');
        if(fn.since) badges.push('<span class="bd">since '+esc(fn.since)+'</span>');
        // R2 — auto-derived, coarse and safe in the "tested" direction (see
        // coverage.lua). No badge for the false case: this is a "not found
        // by name in a spec" signal, not "definitely untested", and a
        // warning-shaped badge on the majority of functions would be noise,
        // not information.
        if(fn.tested) badges.push('<span class="bd tested">tested</span>');
        h.push('<div class="fn-sig">'+esc(fn.signature)
          +(badges.length?'<span class="fn-badges">'+badges.join("")+'</span>':'')+'</div>');
        if(fn.deprecated){ h.push('<div class="fn-dep">⚠ Deprecated: '+esc(fn.deprecated)+'</div>'); }
        if(fn.summary){ h.push('<div class="fn-desc">'+esc(fn.summary)+'</div>'); }
        if(fn.params && fn.params.length){
          h.push('<ul class="fn-plist">');
          fn.params.forEach(function(p){
            h.push('<li><code>'+esc(p.name)+(p.optional?'?':'')+'</code> '+esc(p.type)
              +(p.desc?' — '+esc(p.desc):'')+'</li>');
          });
          h.push('</ul>');
        }
        if(fn.returns && fn.returns.length){
          h.push('<ul class="fn-plist">');
          fn.returns.forEach(function(r){
            h.push('<li>→ <code>'+esc(r.type)+'</code>'+(r.name?' '+esc(r.name):'')
              +(r.desc?' — '+esc(r.desc):'')+'</li>');
          });
          h.push('</ul>');
        }
        if(fn.see && fn.see.length){
          var seeLinks = fn.see.map(function(target){
            var targetId = seeIndex[target];
            return targetId
              ? '<a href="#" data-see-target="'+esc(targetId)+'">'+esc(target)+'</a>'
              : '<span title="unresolved">'+esc(target)+'</span>';
          });
          h.push('<div class="fn-desc fn-see">See also: '+seeLinks.join(", ")+'</div>');
        }
        if(fn.example){ h.push('<div class="fn-ex">'+esc(fn.example)+'</div>'); }

        // The per-function entry into the Calls view. Counts are shown up
        // front so a function with no edges either way does not offer a link
        // to an empty diagram — with no call data in the map at all (the
        // common case before `:LibMap` is re-run), this section simply is not
        // rendered, rather than every function sprouting two dead links.
        var outN = (callOut[key] || []).length, inN = (callIn[key] || []).length;
        if(outN || inN){
          var cl = [];
          if(outN) cl.push('<a href="#" data-calls="'+esc(key)+'" data-dir="out">calls '+outN+' ↓</a>');
          if(inN) cl.push('<a href="#" data-calls="'+esc(key)+'" data-dir="in">callers '+inN+' ↑</a>');
          h.push('<div class="fn-desc fn-see">'+cl.join(" · ")+'</div>');
        }
        h.push('</div>');
      });
    }

    // The half of a module's surface that is not callable: the lookup tables
    // it dispatches through, the constants that encode its thresholds, the
    // things it computes once at load time. Reading a module's source these
    // are usually the first thing you go looking for, and nothing generated
    // showed them before.
    if(n.symbols && n.symbols.length){
      h.push('<div class="sec">Tables &amp; values ('+n.symbols.length+')</div><ul class="lst syms">');
      n.symbols.forEach(function(sy){
        h.push('<li><span class="bd sk-'+sy.kind+'">'+sy.kind+'</span> <code>'+esc(sy.name)+'</code>'
          + (sy.detail ? ' <span class="sdet">'+esc(sy.detail)+'</span>' : '')
          + (sy.summary ? '<div class="fn-desc">'+esc(sy.summary)+'</div>' : '')
          + '</li>');
      });
      h.push('</ul>');
    }

    var kids = (n.children||[]).map(function(i){return byId[i];}).filter(Boolean);
    if(kids.length){
      h.push('<div class="sec">Contains ('+kids.length+')</div><ul class="lst">');
      kids.forEach(function(k){
        h.push('<li>'+esc(k.name)+(k.summary?' — <span style="font-family:inherit">'+esc(k.summary)+'</span>':'')+'</li>');
      });
      h.push('</ul>');
    }

    var meta = [];
    if(n.export) meta.push("exports: " + n.export);
    meta.push("kind: " + n.kind);
    h.push('<div class="sec">Meta</div><ul class="lst"><li>'+esc(meta.join("  ·  "))+'</li></ul>');

    detailEl.innerHTML = h.join("");

    // One handler per link family. `fn: null` on the Deps/Hierarchy hops is
    // not redundant: leaving a stale function centered would make a later
    // switch back to Calls open on whatever function was last looked at
    // several nodes ago, rather than on this node.
    detailEl.querySelectorAll("a[data-goto]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        var to = a.dataset.goto;
        if(to === "hierarchy") navigate({ tab: "hierarchy", view: "modules", center: n.id, fn: null });
        else if(to === "deps") navigate({ tab: "hierarchy", view: "deps", center: n.id, fn: null });
        else navigate({ tab: "hierarchy", view: "calls", center: n.id, fn: null });
      });
    });

    detailEl.querySelectorAll("a[data-calls]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        navigate({ tab: "hierarchy", view: "calls", center: n.id,
                   fn: a.dataset.calls, dir: a.dataset.dir });
      });
    });

    detailEl.querySelectorAll("a[data-node-link]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        navigate({ tab: "tree", id: a.dataset.nodeLink });
      });
    });

    detailEl.querySelectorAll("a[data-see-target]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        navigate({ tab: "tree", id: a.dataset.seeTarget });
      });
    });
  }

  treeEl.appendChild(renderNode(byId[IR.root]));

  document.getElementById("expand").addEventListener("click", function(){
    treeEl.querySelectorAll(".kids").forEach(function(k){ k.classList.remove("hide"); });
    treeEl.querySelectorAll(".tw").forEach(function(t){ if(t.textContent) t.textContent = "▾"; });
  });
  document.getElementById("collapse").addEventListener("click", function(){
    treeEl.querySelectorAll(".kids").forEach(function(k, i){ if(i) k.classList.add("hide"); });
    treeEl.querySelectorAll(".row").forEach(function(r){
      // The function-group header carries no node id, so the depth test below
      // skipped it and left a ▾ twisty over a collapsed group. It is always
      // collapsed by this button, so its arrow is unconditional.
      if(r.classList.contains("fnhead")){
        var ft = r.querySelector(".tw");
        if(ft) ft.textContent = "▸";
        return;
      }
      var n = byId[r.dataset.id];
      if(n && n.depth >= 1){ var t = r.querySelector(".tw"); if(t && t.textContent) t.textContent = "▸"; }
    });
  });

  // =====================================================================
  // Findings: clicking a row with a resolvable node id selects it. Rows for
  // findings whose node isn't a real IR node (a couple of repo-specific
  // checks report against synthetic paths) simply have no data-node
  // attribute and stay inert — see render/html.lua for why.
  // =====================================================================
  document.querySelectorAll("#findings tbody tr[data-node]").forEach(function(tr){
    var target = tr.dataset.node;
    if(!byId[target]) return;
    tr.addEventListener("click", function(){ navigate({ tab: "tree", id: target }); });
  });

  // =====================================================================
  // Tabs
  // =====================================================================
  document.querySelectorAll(".tab-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ tab: b.dataset.tab }); });
  });

  // =====================================================================
  // Hierarchy view
  //
  // Two "aufbereitungen" of the same annotation data, toggled via
  // .hview-btn: "modules" draws the directory/module hierarchy (unchanged
  // from before); "types" draws the class/alias graph from LuaLS
  // enrichment — a materially different view of the same map, not just a
  // relabeling, since it walks ir.edges' from_class/to_class rather than
  // node.children.
  //
  // Node/class positions are computed analytically from IR data (layer =
  // BFS depth, position = index within the layer), not measured off the
  // DOM — this sidesteps "a box inside display:none has zero size" entirely
  // rather than working around it with a re-layout-on-show step, since the
  // math produces correct pixel coordinates regardless of visibility.
  // =====================================================================
  var hgraphWrap = document.getElementById("hgraph-wrap");
  var hgraph = document.getElementById("hgraph");
  var hstage = document.getElementById("hstage");
  var hpathEl = document.getElementById("hpath");
  var hlegendEl = document.getElementById("hlegend");
  var hcenter = null;
  var MAX_HNODES = 90;
  var BOX_W = 168, BOX_H = 52, GAP_X = 16, GAP_Y = 44, PAD = 20;

  // Downward edges keep the original S-curve between the boxes' facing sides.
  // Backedges — an edge to a box on the same layer or above — are a new
  // problem the tree views never had: a require or call graph has cycles, so
  // the BFS assigns a target its *first-seen* depth and any later edge into it
  // points sideways or up. Drawn with the same curve, those run straight
  // through every box in between; routed out of the side and back in, they
  // read as the loop they are.
  function edgePath(a, b){
    var x1 = a.x + BOX_W/2, x2 = b.x + BOX_W/2;
    if(b.y > a.y){
      var y1 = a.y + BOX_H, y2 = b.y;
      var midY = (y1 + y2) / 2;
      return "M" + x1 + "," + y1 + " C" + x1 + "," + midY + " " + x2 + "," + midY + " " + x2 + "," + y2;
    }
    var leftward = x2 <= x1;
    var sx = leftward ? a.x : a.x + BOX_W;
    var ex = leftward ? b.x + BOX_W : b.x;
    var sy = a.y + BOX_H/2, ey = b.y + BOX_H/2;
    var bulge = (leftward ? -1 : 1) * Math.max(38, Math.abs(sy - ey) * 0.45);
    return "M" + sx + "," + sy + " C" + (sx + bulge) + "," + sy + " " +
      (ex + bulge) + "," + ey + " " + ex + "," + ey;
  }

  // BFS over node.children from `startId`. Files count the same as modules/
  // namespaces — an earlier version excluded them as "just noise", which was
  // wrong in practice: centering on a module implemented as flat files with
  // no further subdirectories then drew almost nothing. MAX_HNODES already
  // bounds noise at any scope.
  // Every layout below returns the same shape, so drawHierarchy never asks
  // which view it is drawing:
  //   { layers: [[key,…],…], included: {key: layerIndex}, count, truncated,
  //     edges: [{from, to, cls, label}] }
  // Producing the edges here rather than in the drawing code is what keeps
  // four structurally different graphs — a tree, a class graph, a require
  // graph and a call graph — behind one renderer.
  function layoutModules(startId){
    var layers = [], included = {}, count = 0, truncated = false;
    var queue = [ { id: startId, d: 0 } ];
    while(queue.length){
      var item = queue.shift();
      if(included[item.id] !== undefined) continue;
      if(count >= MAX_HNODES){ truncated = true; break; }
      var node = byId[item.id];
      if(!node) continue;
      included[item.id] = item.d;
      count++;
      layers[item.d] = layers[item.d] || [];
      layers[item.d].push(item.id);
      (node.children || []).forEach(function(c){
        if(byId[c]) queue.push({ id: c, d: item.d + 1 });
      });
    }

    var edges = [];
    Object.keys(included).forEach(function(id){
      (byId[id].children || []).forEach(function(c){
        if(included[c] !== undefined) edges.push({ from: id, to: c, cls: "hedge", marker: "tree" });
      });
    });
    // Type-reference edges layered on top (dashed), node-granularity,
    // self-loops skipped — a field can reference a class anywhere in the whole
    // map, and pulling in out-of-view targets would break "scoped to one
    // subtree".
    typeEdges.forEach(function(e){
      if(e.from !== e.to && included[e.from] !== undefined && included[e.to] !== undefined){
        edges.push({ from: e.from, to: e.to, cls: "hedge hedge-type",
                     marker: "type", label: "." + e.via });
      }
    });

    return { layers: layers, included: included, count: count, truncated: truncated, edges: edges };
  }

  // BFS over ir.edges' from_class/to_class, seeded from the centered node's
  // own types_detail. A field can reference a class owned by any node in the
  // whole map, which is exactly the point of this view — unlike the Modules
  // view, edges are not required to stay within the laid-out subtree, they
  // define it.
  function layoutTypes(startId){
    var center = byId[startId];
    var seeds = (center.types_detail || []).map(function(t){ return t.name; });
    if(seeds.length === 0) return { layers: [], included: {}, count: 0, truncated: false, edges: [] };

    // `typeEdges`, not `IR.edges`: that array now also carries require and
    // call edges, whose `from_class` is undefined — keying an adjacency map on
    // it would file every one of them under the same bogus key.
    var adj = {};
    typeEdges.forEach(function(e){
      (adj[e.from_class] = adj[e.from_class] || []).push(e);
    });

    var layers = [], included = {}, count = 0, truncated = false;
    var queue = seeds.map(function(name){ return { name: name, d: 0 }; });
    while(queue.length){
      var item = queue.shift();
      if(included[item.name] !== undefined) continue;
      if(!classByName[item.name]) continue;
      if(count >= MAX_HNODES){ truncated = true; break; }
      included[item.name] = item.d;
      count++;
      layers[item.d] = layers[item.d] || [];
      layers[item.d].push(item.name);
      (adj[item.name] || []).forEach(function(e){
        if(classByName[e.to_class]) queue.push({ name: e.to_class, d: item.d + 1 });
      });
    }

    var edges = [];
    Object.keys(included).forEach(function(name){
      (adj[name] || []).forEach(function(e){
        if(included[e.to_class] !== undefined){
          edges.push({ from: name, to: e.to_class, cls: "hedge hedge-type",
                       marker: "type", label: "." + e.via });
        }
      });
    });

    return { layers: layers, included: included, count: count, truncated: truncated, edges: edges };
  }

  // Inheritance: Doxygen's class-hierarchy diagram, centered the way every
  // other view here is centered rather than drawn as one global root-to-leaf
  // tree. Both directions at once, because for a class "what am I" and "who
  // inherits me" are equally the question.
  //
  // Deliberately *not* built on `walk()`, which the two directed views share.
  // `walk` puts every seed on layer 0 and measures distance from there — but a
  // module normally declares a base class and its subclasses together, so all
  // of them are seeds, and the whole hierarchy collapsed onto one row
  // (observed: Lib.Cache.Opts sat beside its own LoadOpts/SaveOpts). Depth
  // here has to come from the inheritance relation itself, not from distance
  // to whatever the reader happened to center on.
  //
  // So: take the connected component around the seeds, then layer it by
  // longest path from a root — depth(c) = 0 when c has no parent in the
  // component, else 1 + max(depth(parents)). Longest rather than shortest is
  // what guarantees a class always renders strictly below *every* one of its
  // parents, including in a diamond where one path is shorter than the other.
  function layoutInheritance(startId){
    var center = byId[startId];
    var seeds = (center.types_detail || [])
      .filter(function(t){ return inInheritance[t.name]; })
      .map(function(t){ return t.name; });
    if(seeds.length === 0) return { layers: [], included: {}, count: 0, truncated: false, edges: [] };

    // Connected component, walking parents and children alike.
    var inComp = {}, queue = seeds.slice(), qi = 0, truncated = false;
    seeds.forEach(function(s){ inComp[s] = true; });
    while(qi < queue.length){
      var cur = queue[qi++];
      var step = function(e, other){
        if(!classByName[other] || inComp[other]) return;
        if(Object.keys(inComp).length >= MAX_HNODES){ truncated = true; return; }
        inComp[other] = true;
        queue.push(other);
      };
      (extUp[cur] || []).forEach(function(e){ step(e, e.to_class); });
      (extDown[cur] || []).forEach(function(e){ step(e, e.from_class); });
    }

    // Longest-path depth, memoized. `state` also guards against a cycle:
    // `---@class A : B` plus `---@class B : A` is nonsense LuaLS would still
    // hand over, and without the guard this recursion would not terminate.
    var depth = {}, state = {};
    function depthOf(name){
      if(state[name] === 2) return depth[name];
      if(state[name] === 1) return 0; // cycle: stop contributing
      state[name] = 1;
      var d = 0;
      (extUp[name] || []).forEach(function(e){
        if(inComp[e.to_class]) d = Math.max(d, depthOf(e.to_class) + 1);
      });
      depth[name] = d; state[name] = 2;
      return d;
    }
    Object.keys(inComp).forEach(depthOf);

    var layers = [], included = {}, count = 0;
    Object.keys(inComp).sort().forEach(function(name){
      var d = depth[name];
      included[name] = d;
      (layers[d] = layers[d] || []).push(name);
      count++;
    });
    for(var i = 0; i < layers.length; i++){ layers[i] = layers[i] || []; }

    var edges = [];
    extendsEdges.forEach(function(e){
      if(included[e.from_class] !== undefined && included[e.to_class] !== undefined){
        edges.push({ from: e.from_class, to: e.to_class, cls: "hedge hedge-ext",
                     marker: "ext", label: "extends " + e.to_class });
      }
    });

    // Named explicitly rather than left to "first box of the first layer":
    // base classes occupy layer 0, so that shortcut (which the Types view can
    // rely on) would ring a parent instead of the class being looked at.
    return { layers: layers, included: included, count: count,
             truncated: truncated, edges: edges, centerKey: seeds[0] };
  }

  // =====================================================================
  // Deps and Calls: the two directed views.
  //
  // Both are the same walk over different adjacency, so it is written once.
  // `dir` decides which way the walk runs: "out" follows edges forwards
  // (what this needs / calls), "in" follows them backwards (what needs /
  // calls this), "both" runs each independently from the same seeds and
  // places the results above and below the center.
  //
  // Running the two sides separately for "both" is not an optimisation, it is
  // the correct semantics: once a walk has gone *up* into callers, continuing
  // it downwards through those callers' other callees would fill the diagram
  // with functions that have nothing to do with the center. Doxygen's caller
  // graph makes the same choice.
  // =====================================================================
  function walk(seeds, adj, keyOf, dir, maxDepth, exists){
    var depth = {}, count = 0, truncated = false;

    seeds.forEach(function(k){
      if(exists(k) && depth[k] === undefined && count < MAX_HNODES){
        depth[k] = 0; count++;
      }
    });

    function side(sign, adjMap, pick){
      var queue = Object.keys(depth).filter(function(k){ return depth[k] === 0; })
        .map(function(k){ return { key: k, d: 0 }; });
      while(queue.length){
        var it = queue.shift();
        if(maxDepth > 0 && Math.abs(it.d) >= maxDepth) continue;
        var list = adjMap[it.key] || [];
        for(var i = 0; i < list.length; i++){
          var nxt = pick(list[i]);
          if(!exists(nxt) || depth[nxt] !== undefined) continue;
          if(count >= MAX_HNODES){ truncated = true; return; }
          depth[nxt] = it.d + sign;
          count++;
          queue.push({ key: nxt, d: it.d + sign });
        }
      }
    }

    if(dir === "out" || dir === "both") side(1, adj.out, keyOf.to);
    if(dir === "in" || dir === "both") side(-1, adj.in, keyOf.from);

    // Depths can be negative in "both" mode; layers is a dense array, so the
    // whole thing is shifted down by the deepest caller level.
    var min = 0;
    Object.keys(depth).forEach(function(k){ if(depth[k] < min) min = depth[k]; });

    var layers = [], included = {};
    Object.keys(depth).sort().forEach(function(k){
      var idx = depth[k] - min;
      included[k] = idx;
      (layers[idx] = layers[idx] || []).push(k);
    });
    for(var i = 0; i < layers.length; i++){ layers[i] = layers[i] || []; }

    return { layers: layers, included: included, count: count, truncated: truncated };
  }

  // Requires that resolve to nothing in the scanned tree, materialized into
  // boxes on demand. One box per module however many nodes reach for it —
  // "these four all pull in plenary" is the thing worth seeing, and four
  // separate boxes would hide exactly that. Keyed "ext:<module>" so they can
  // never collide with a node id, and given no `nodeId`, which is what stops
  // click, double-click and the context menu from offering to navigate into
  // something the map knows nothing about.
  function addExternals(built, maxDepth){
    var depthOf = {};
    Object.keys(built.included).forEach(function(id){
      ((byId[id] || {}).requires_external || []).forEach(function(mod){
        var key = "ext:" + mod;
        var d = built.included[id] + 1;
        if(maxDepth > 0 && d > maxDepth) return;
        if(depthOf[key] === undefined || d > depthOf[key]) depthOf[key] = d;
      });
    });

    Object.keys(depthOf).sort().forEach(function(key){
      if(built.count >= MAX_HNODES){ built.truncated = true; return; }
      var d = depthOf[key];
      while(built.layers.length <= d) built.layers.push([]);
      built.layers[d].push(key);
      built.included[key] = d;
      built.count++;
    });

    Object.keys(built.included).forEach(function(id){
      if(id.indexOf("ext:") === 0) return;
      ((byId[id] || {}).requires_external || []).forEach(function(mod){
        var key = "ext:" + mod;
        if(built.included[key] === undefined) return;
        built.edges.push({
          from: id, to: key,
          cls: "hedge hedge-dep external",
          marker: "dep",
          label: "requires " + mod + " (outside this map)"
        });
      });
    });
  }

  function layoutDeps(startId, dir, maxDepth, showExternal){
    var keyOf = { from: function(e){ return e.from; }, to: function(e){ return e.to; } };
    var built = walk([startId], { out: depOut, in: depIn }, keyOf, dir, maxDepth,
      function(k){ return !!byId[k]; });

    var edges = [];
    (IR.edges || []).forEach(function(e){
      if(e.kind !== "require") return;
      if(built.included[e.from] === undefined || built.included[e.to] === undefined) return;
      edges.push({
        from: e.from, to: e.to,
        cls: "hedge hedge-dep" + (e.deferred ? " deferred" : ""),
        marker: "dep",
        label: (e.deferred ? "lazy require " : "require ") + e.to_module + ":" + e.line
      });
    });
    built.edges = edges;
    if(showExternal) addExternals(built, maxDepth);
    return built;
  }

  function layoutCalls(startId, startFn, dir, maxDepth){
    var keyOf = {
      from: function(e){ return fnKey(e.from, e.from_fn); },
      to: function(e){ return fnKey(e.to, e.to_fn); }
    };
    // Centering on a node rather than a single function seeds every function
    // it declares: "what does this module call" is the question asked from
    // the node's own detail pane, and answering it one function at a time
    // would mean opening the view once per function.
    var seeds;
    if(startFn && fnByKey[startFn]){
      seeds = [startFn];
    } else {
      var n = byId[startId];
      seeds = ((n && n.functions) || []).map(function(fn){ return fnKey(startId, fn.name); });
    }

    var built = walk(seeds, { out: callOut, in: callIn }, keyOf, dir, maxDepth,
      function(k){ return !!fnByKey[k]; });

    var edges = [];
    (IR.edges || []).forEach(function(e){
      if(e.kind !== "call") return;
      var a = keyOf.from(e), b = keyOf.to(e);
      if(built.included[a] === undefined || built.included[b] === undefined) return;
      edges.push({
        from: a, to: b,
        cls: "hedge hedge-call" + (e.confidence === "heuristic" ? " weak" : ""),
        marker: "call",
        label: (e.confidence === "heuristic" ? "guessed call, line " : "call, line ") + e.line
      });
    });
    built.edges = edges;
    return built;
  }

  function layerPositions(layers){
    var maxRowWidth = 0;
    layers.forEach(function(layer){
      if(!layer) return;
      maxRowWidth = Math.max(maxRowWidth, layer.length * BOX_W + (layer.length - 1) * GAP_X);
    });
    var positions = {};
    layers.forEach(function(layer, d){
      if(!layer) return;
      var rowWidth = layer.length * BOX_W + (layer.length - 1) * GAP_X;
      var startX = PAD + (maxRowWidth - rowWidth) / 2;
      layer.forEach(function(key, i){
        positions[key] = { x: startX + i * (BOX_W + GAP_X), y: PAD + d * (BOX_H + GAP_Y) };
      });
    });
    return { positions: positions, maxRowWidth: maxRowWidth };
  }

  // =====================================================================
  // Box specs: one place that knows what a box in each view says. Returns a
  // class, its markup, a tooltip and the node the box ultimately belongs to
  // (a class box and a function box both resolve back to a node, which is
  // what click-to-select and the context menu act on).
  // =====================================================================
  function boxSpec(key, view){
    if(key.indexOf("ext:") === 0){
      var mod = key.slice(4);
      // Resolved through opts.tag_files (Doxygen TAGFILES equivalent): a box
      // that isn't part of *this* map but is part of another project's own
      // generated one stops being an inert dead end and opens that page.
      var link = (IR.tag_links || {})[mod];
      return {
        cls: "hnode k-external" + (link ? " linked" : ""),
        title: link
          ? mod + " — open " + link.title + " in its own map"
          : mod + " — required here but not part of this map",
        html: '<div class="hnm">' + esc(mod) + '</div>' +
              '<div class="hkind">external' + (link ? " ↗" : "") + '</div>',
        nodeId: null, recenter: null, externalHtml: link && link.html
      };
    }
    // Both class-keyed views. Inheritance boxes carry the parent list as the
    // second line instead of the bare kind: in a diagram *about* inheritance,
    // "class" on every box says nothing, and the declared `: A, B` is exactly
    // what the reader is checking the arrows against.
    if(view === "types" || view === "inheritance"){
      var cls = classByName[key];
      if(!cls) return null;
      var sub = cls.info.kind;
      if(view === "inheritance"){
        var ps = cls.info.extends || [];
        sub = ps.length ? ": " + ps.join(", ") : "base";
      }
      return {
        cls: "hnode t-" + cls.info.kind,
        title: cls.info.desc || key,
        html: '<div class="hnm">' + esc(key) + '</div>' +
              '<div class="hkind">' + esc(sub) + '</div>',
        nodeId: cls.nodeId, recenter: cls.nodeId
      };
    }
    if(view === "calls"){
      var entry = fnByKey[key];
      if(!entry) return null;
      return {
        cls: "hnode k-fn",
        title: (entry.fn.summary || entry.fn.signature) + "\n" +
               (entry.node.module || entry.node.path),
        html: '<div class="hnm">' + esc(entry.fn.signature) + '</div>' +
              '<div class="hline">' + esc(entry.node.name) + ':' + entry.fn.line + '</div>',
        nodeId: entry.node.id, recenter: entry.node.id, fnKey: key
      };
    }
    var n = byId[key];
    if(!n) return null;
    // The Deps view labels boxes by module path rather than directory name:
    // a require graph is read in module terms, and half this tree's
    // directories are called `init`-shaped things that are ambiguous alone.
    var label = view === "deps" ? (n.module || n.name) : n.name;
    return {
      cls: "hnode k-" + n.kind,
      title: n.summary || n.name,
      html: '<div class="hnm">' + esc(label) + '</div>' +
            (n.summary ? '<div class="hsm">' + esc(n.summary) + '</div>' : ''),
      nodeId: n.id, recenter: n.id
    };
  }

  // =====================================================================
  // Keyed reconcile — the reason re-centering moves instead of cutting.
  //
  // Boxes are held in `hboxes` by key and reused across redraws, so a box
  // present before and after a re-center is the *same element* at a new
  // left/top, and the CSS transition on .hnode animates it there. Rebuilding
  // the subtree with innerHTML = "" (what this used to do) threw that
  // identity away every time, which is why every navigation was a hard cut
  // even though the two layouts often shared most of their boxes.
  //
  // Positions are still computed analytically from the IR, never measured off
  // the DOM — that is what lets the diagram be correct while the pane is
  // display:none, and animating does not change it.
  // =====================================================================
  var hboxes = {};
  var hpending = {};
  var ANIM_MS = 340;

  function reconcile(positions, view, centerKey){
    var moved = false;

    Object.keys(positions).forEach(function(key){
      var spec = boxSpec(key, view);
      if(!spec) return;
      var pos = positions[key];
      var el = hboxes[key];

      if(el){
        // A box that was mid-exit and is wanted again: cancel the removal
        // rather than let the timer delete a live element out from under us.
        if(hpending[key]){ clearTimeout(hpending[key]); delete hpending[key]; }
        if(parseFloat(el.style.left) !== pos.x || parseFloat(el.style.top) !== pos.y) moved = true;
      } else {
        el = document.createElement("div");
        el.dataset.key = key;
        el.style.left = pos.x + "px";
        el.style.top = pos.y + "px";
        el.classList.add("entering");
        hstage.appendChild(el);
        hboxes[key] = el;
      }

      var entering = el.classList.contains("entering");
      el.className = spec.cls + (key === centerKey ? " center" : "") + (entering ? " entering" : "");
      el.style.left = pos.x + "px";
      el.style.top = pos.y + "px";
      el.style.width = BOX_W + "px";
      el.title = spec.title;
      el.innerHTML = spec.html;
      el._spec = spec;
    });

    Object.keys(hboxes).forEach(function(key){
      if(positions[key] !== undefined || hpending[key]) return;
      var el = hboxes[key];
      el.classList.add("leaving");
      hpending[key] = setTimeout(function(){
        delete hpending[key];
        if(hboxes[key] === el){ delete hboxes[key]; }
        if(el.parentNode) el.parentNode.removeChild(el);
      }, ANIM_MS);
    });

    // Entering boxes need one frame at opacity 0 before the class comes off,
    // or the browser coalesces both styles into the final one and there is no
    // transition to run.
    requestAnimationFrame(function(){
      Object.keys(hboxes).forEach(function(key){
        hboxes[key].classList.remove("entering");
      });
    });

    return moved;
  }

  // Arrowheads: a tree needs none (the layout says which way is down), a
  // directed graph does — an edge between two boxes on the same layer, or a
  // backedge, is otherwise unreadable. One marker per edge colour, coloured
  // from CSS so the dark-mode palette applies to them too.
  function buildDefs(svgNS){
    var defs = document.createElementNS(svgNS, "defs");
    ["tree", "type", "ext", "dep", "call"].forEach(function(name){
      var m = document.createElementNS(svgNS, "marker");
      m.id = "m-" + name;
      m.setAttribute("viewBox", "0 0 8 8");
      m.setAttribute("refX", "7"); m.setAttribute("refY", "4");
      m.setAttribute("markerWidth", "7"); m.setAttribute("markerHeight", "7");
      m.setAttribute("orient", "auto-start-reverse");
      var p = document.createElementNS(svgNS, "path");
      p.setAttribute("d", "M0,0 L8,4 L0,8 z");
      m.appendChild(p);
      defs.appendChild(m);
    });
    return defs;
  }

  // Written as objects rather than nested arrays for a mundane reason worth
  // knowing before editing this file: the whole script lives inside a Lua
  // long string, and two adjacent closing square brackets terminate it —
  // which is exactly what an array of arrays ends with. The rest of the
  // script then parses as Lua source. Avoid that pair anywhere in here.
  function sw(mod, text){ return { sw: mod, text: text }; }
  var LEGEND = {
    modules: [ sw("", "contains"), sw("type", "type reference") ],
    types:   [ sw("type", "field references class") ],
    inheritance: [ sw("ext", "inherits from (arrow points at the base class)") ],
    deps:    [ sw("dep", "requires at load time"),
               sw("dep deferred", "lazy require (inside a function)") ],
    depsExt: [ sw("dep external", "requires something outside this map") ],
    calls:   [ sw("call", "calls"),
               sw("call weak", "guessed call (--calls-heuristic)") ]
  };

  function drawLegend(view){
    var entries = (LEGEND[view] || []).slice();
    if(view === "deps" && state.ext) entries = entries.concat(LEGEND.depsExt);
    var items = entries.map(function(it){
      return '<span class="lg"><span class="sw ' + it.sw + '"></span>' + esc(it.text) + '</span>';
    });
    items.push('<span class="lg">wheel zooms · shift+wheel pans · ' +
      (isGraphView(view) ? 'zoom past the edge changes depth' : 'zoom right in to open a module') +
      ' · right-click for more</span>');
    hlegendEl.innerHTML = items.join("");
  }

  function emptyMessage(view, center){
    if(view === "types"){
      return typeEdges.length
        ? '<p class="hmsg">' + esc(center.name) + ' has no <code>@class</code>/<code>@alias</code> of its own — pick a module with type definitions, or switch back to Modules.</p>'
        : '<p class="hmsg">No type data in this map — regenerate with <code>:LibMap full</code> (or <code>--full</code>) to include lua-language-server class/alias detail.</p>';
    }
    if(view === "inheritance"){
      if(!typeEdges.length && !extendsEdges.length){
        return '<p class="hmsg">No type data in this map — regenerate with <code>:LibMap full</code> (or <code>--full</code>) to include lua-language-server class detail.</p>';
      }
      return extendsEdges.length
        ? '<p class="hmsg">None of ' + esc(center.name) + '’s classes take part in an inheritance relation (<code>---@class Child : Parent</code>).</p>'
        : '<p class="hmsg">No class in this map declares a parent — nothing to draw an inheritance tree from.</p>';
    }
    if(view === "deps"){
      return '<p class="hmsg">' + esc(center.name) + ' neither requires nor is required by anything in this map.</p>';
    }
    if(view === "calls"){
      return (center.functions || []).length
        ? '<p class="hmsg">None of ' + esc(center.name) + '’s functions call — or are called by — anything the scanner could resolve. Dynamic dispatch is invisible to it; see the module README.</p>'
        : '<p class="hmsg">' + esc(center.name) + ' declares no functions.</p>';
    }
    return '<p class="hmsg">Nothing to draw here.</p>';
  }

  function clearGraph(){
    Object.keys(hpending).forEach(function(k){ clearTimeout(hpending[k]); });
    hpending = {};
    hboxes = {};
    hstage.innerHTML = "";
    // The empty-state message hangs off #hgraph, outside the stage, so
    // clearing the stage alone would stack a second copy on the next empty
    // draw instead of replacing the first.
    var msg = hgraph.querySelector(".hmsg");
    if(msg) msg.remove();
  }

  var VIEWS = { modules: 1, types: 1, inheritance: 1, deps: 1, calls: 1 };

  // =====================================================================
  // Notes tab: Doxygen's Deprecated / Todo / Bug / Test lists.
  //
  // Four aggregates over data the scan already has, in one tab rather than
  // four pages: three of these tags are usually unused in a given tree, and
  // four tabs that are empty most of the time would be four tabs of noise.
  // Sections with no entries say so instead of vanishing, so "nothing is
  // deprecated" is distinguishable from "this build forgot to collect it".
  //
  // Not a `check` finding, deliberately: none of these is drift or an error,
  // and routing them through findings would put author to-dos into an exit
  // code that CI fails on.
  // =====================================================================
  var NOTE_KINDS = [
    { key: "deprecated", title: "Deprecated", scalar: true,
      sub: "Functions marked ---@deprecated. The text is the migration hint the author left." },
    { key: "todo", title: "Todo",
      sub: "Open ---@todo entries, one line per occurrence." },
    { key: "bug", title: "Bug",
      sub: "Known defects recorded with ---@bug, still present in the code." },
    { key: "test", title: "Test",
      sub: "---@test notes: what covers this function, or what still needs covering." }
  ];

  function collectNotes(kind){
    var out = [];
    IR.nodes.forEach(function(n){
      (n.functions || []).forEach(function(fn){
        var v = fn[kind.key];
        if(kind.scalar){
          if(v) out.push({ node: n, fn: fn, text: v });
          return;
        }
        (v || []).forEach(function(entry){ out.push({ node: n, fn: fn, text: entry }); });
      });
    });
    // By where it lives, then by line: reading a list of todos is reading a
    // to-do list per module, not an alphabet of function names.
    out.sort(function(a, b){
      var am = a.node.module || a.node.path, bm = b.node.module || b.node.path;
      if(am !== bm) return am < bm ? -1 : 1;
      return a.fn.line - b.fn.line;
    });
    return out;
  }

  var notesDrawn = false;
  function drawNotes(){
    if(notesDrawn) return; // static over one IR; nothing invalidates it
    notesDrawn = true;

    var host = document.getElementById("view-notes");
    var parts = [];
    NOTE_KINDS.forEach(function(kind){
      var items = collectNotes(kind);
      parts.push('<h3>' + esc(kind.title) +
        '<span class="ncount">' + items.length + '</span></h3>');
      parts.push('<p class="nsub">' + esc(kind.sub) + '</p>');
      if(items.length === 0){
        parts.push('<p class="ntext none">Nothing carries <code>---@' +
          esc(kind.key) + '</code> in this map.</p>');
        return;
      }
      parts.push('<ul class="nlist">');
      items.forEach(function(it){
        parts.push('<li><a class="nfn" data-node="' + esc(it.node.id) + '">' +
          esc(it.fn.signature) + '</a>' +
          '<span class="nwhere">' + esc(it.node.module || it.node.path) +
          ':' + it.fn.line + '</span>' +
          '<div class="ntext">' + (it.text ? esc(it.text) : "&mdash;") + '</div></li>');
      });
      parts.push("</ul>");
    });
    host.innerHTML = parts.join("");

    host.querySelectorAll(".nfn").forEach(function(a){
      a.addEventListener("click", function(){
        navigate({ tab: "tree", id: a.dataset.node });
      });
    });
  }

  // =====================================================================
  // Index tab: Doxygen's "File Members" — every documented function in the
  // tree, A–Z, without walking the module hierarchy to find it.
  //
  // Sorted on the *bare* name (`M.read` files under R, not M), because the
  // `M.` is this repo's local-table convention rather than part of what the
  // function is called — filing 900 functions under "M" would be an index in
  // name only. `calls.lua` needed the same reduction and its `bare()` is the
  // model here.
  //
  // The Tree tab already filters and the picker already fuzzy-matches; what
  // neither gives you is the flat alphabet, which is the one way to find
  // something whose module you do not know.
  // =====================================================================
  function bareName(name){ return (name.match(/[\w]+$/) || [name])[0]; }

  // Shared by both index views: letter buckets plus a jump bar, filed on
  // `entry.bare`. Ties broken by `entry.tie` so two entries with the same
  // bare name (`M.setup` everywhere; two modules named `init`) sort
  // deterministically instead of leaving it to the engine's discretion.
  function buildIndexBuckets(entries){
    entries.sort(function(a, b){
      var ab = a.bare.toLowerCase(), bb = b.bare.toLowerCase();
      if(ab !== bb) return ab < bb ? -1 : 1;
      return a.tie < b.tie ? -1 : (a.tie > b.tie ? 1 : 0);
    });
    var buckets = {}, order = [];
    entries.forEach(function(e){
      var c = e.bare.charAt(0).toUpperCase();
      if(!/[A-Z]/.test(c)) c = "#";
      if(!buckets[c]){ buckets[c] = []; order.push(c); }
      buckets[c].push(e);
    });
    order.sort();
    return { buckets: buckets, order: order };
  }

  function indexJumpBar(order){
    return '<div class="ixjump">' + order.map(function(c){
      return '<a data-jump="' + esc(c) + '">' + esc(c) + '</a>';
    }).join("") + "</div>";
  }

  function wireIndexBody(host){
    host.querySelectorAll(".nfn").forEach(function(a){
      a.addEventListener("click", function(){
        navigate({ tab: "tree", id: a.dataset.node });
      });
    });
    host.querySelectorAll("[data-jump]").forEach(function(a){
      a.addEventListener("click", function(){
        var h = host.querySelector("#ix-" + CSS.escape(a.dataset.jump));
        if(h) h.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    });
  }

  // Doxygen's "File Members" — every documented function in the tree, A-Z,
  // without walking the module hierarchy to find it. Sorted on the *bare*
  // name (`M.read` files under R, not M): the `M.` is this repo's
  // local-table convention rather than part of what the function is
  // called, and filing 900 functions under "M" would be an index in name
  // only — `calls.lua` needed the same reduction and its `bare()` is the
  // model. The Tree tab already filters and the picker already
  // fuzzy-matches; what neither gives you is the flat alphabet, the one way
  // to find something whose module you do not already know.
  var indexFnHTML = null;
  function renderIndexFunctions(){
    if(indexFnHTML !== null) return indexFnHTML;

    var entries = [];
    IR.nodes.forEach(function(n){
      (n.functions || []).forEach(function(fn){
        entries.push({ node: n, fn: fn, bare: bareName(fn.name), tie: n.module || n.path });
      });
    });

    if(entries.length === 0){
      indexFnHTML = '<p class="ntext none">This map contains no documented functions.</p>';
      return indexFnHTML;
    }

    var built = buildIndexBuckets(entries);
    var parts = [];
    parts.push('<p class="nsub">' + entries.length +
      ' documented functions, filed under the last segment of the declared name' +
      ' (<code>M.read</code> sorts under R).</p>');
    parts.push(indexJumpBar(built.order));

    built.order.forEach(function(c){
      parts.push('<h3 id="ix-' + esc(c) + '">' + esc(c) +
        '<span class="ncount">' + built.buckets[c].length + '</span></h3>');
      parts.push('<ul class="nlist ixlist">');
      built.buckets[c].forEach(function(e){
        parts.push('<li><a class="nfn" data-node="' + esc(e.node.id) + '">' +
          esc(e.fn.signature) + '</a>' +
          (e.fn.internal ? '<span class="ixtag">internal</span>' : '') +
          (e.fn.deprecated ? '<span class="ixtag dep">deprecated</span>' : '') +
          (e.fn.tested ? '<span class="ixtag tested">tested</span>' : '') +
          '<span class="nwhere">' + esc(e.node.module || e.node.path) +
          ':' + e.fn.line + '</span></li>');
      });
      parts.push("</ul>");
    });
    indexFnHTML = parts.join("");
    return indexFnHTML;
  }

  // R3: the same flat alphabet, one level up — every *module and namespace*
  // (not function, and deliberately not `file` nodes: a file is reached
  // through its module in the Tree, and this index exists for "I know the
  // module name, not where it lives", which a leaf file rarely is). Doxygen
  // keeps its File Index and Class Index as separate pages for the same
  // reason a flat function alphabet and a flat module alphabet answer two
  // different "I know the name, not the location" questions.
  var indexModHTML = null;
  function renderIndexModules(){
    if(indexModHTML !== null) return indexModHTML;

    var entries = [];
    IR.nodes.forEach(function(n){
      if(n.kind !== "module" && n.kind !== "namespace") return;
      var label = n.module || n.path;
      entries.push({ node: n, bare: bareName(label), label: label, tie: label });
    });

    if(entries.length === 0){
      indexModHTML = '<p class="ntext none">This map contains no modules.</p>';
      return indexModHTML;
    }

    var built = buildIndexBuckets(entries);
    var parts = [];
    parts.push('<p class="nsub">' + entries.length +
      ' modules and namespaces, filed under the last segment of the module path' +
      ' (<code>lib.nvim.fs</code> sorts under F).</p>');
    parts.push(indexJumpBar(built.order));

    built.order.forEach(function(c){
      parts.push('<h3 id="ix-' + esc(c) + '">' + esc(c) +
        '<span class="ncount">' + built.buckets[c].length + '</span></h3>');
      parts.push('<ul class="nlist ixlist">');
      built.buckets[c].forEach(function(e){
        var fnCount = (e.node.functions || []).length;
        parts.push('<li><a class="nfn" data-node="' + esc(e.node.id) + '">' +
          esc(e.label) + '</a>' +
          '<span class="ixtag">' + esc(e.node.kind) + '</span>' +
          '<span class="nwhere">' + fnCount + (fnCount === 1 ? " function" : " functions") +
          '</span></li>');
      });
      parts.push("</ul>");
    });
    indexModHTML = parts.join("");
    return indexModHTML;
  }

  function drawIndex(){
    var host = document.getElementById("ixbody");
    var iview = state.iview === "modules" ? "modules" : "functions";
    host.innerHTML = iview === "modules" ? renderIndexModules() : renderIndexFunctions();
    wireIndexBody(host);

    document.querySelectorAll("#ixtoggle .ixview-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.iview === iview);
    });
  }

  // =====================================================================
  // Analysis tab: a tool palette, not a diagram — the same "toolbar
  // switches what a shared panel shows" shape the Hierarchy view buttons
  // and the Index Functions/Modules toggle already use, applied to
  // aggregate numbers instead of boxes or a flat alphabet.
  //
  // Each tool reads a boolean docmap already stamped onto every function
  // during scan_full() (`fn.tested`, R2; `fn.documented`, R4) rather than
  // recomputing anything here — `doccoverage.is_documented`'s param-name
  // comparison in particular is not something this file should ever
  // reimplement in JS, where it would inevitably drift from check.lua's
  // own logic the moment either side changed.
  //
  // First two tools only, deliberately: R6 (fan-in/fan-out hotspots) and
  // beyond are real candidates but have no data stamped into the IR yet —
  // adding their buttons here before their data exists would be a menu
  // entry that opens an empty panel, exactly what the context menu's
  // "disabled with count shown" rule exists to avoid elsewhere.
  // =====================================================================

  // `excludeInternal` matters for the Documentation panel specifically:
  // `doccoverage.summary`'s own definition of "total" already excludes
  // `@internal` functions (an internal function's documentation bar is the
  // author's own, not part of a "published API" number), and this panel
  // must count the same way or its 65% would quietly disagree with the
  // number `:LibMap`/the CLI prints for the same tree. The Test-coverage
  // panel passes false: `coverage.resolve` stamps `fn.tested` on every
  // function regardless of `@internal`, so its total is every function.
  function renderAnalysisPanel(label, sub, pick, excludeInternal){
    var rows = [];
    IR.nodes.forEach(function(n){
      var fns = (n.functions || []).filter(function(fn){
        return !(excludeInternal && fn.internal);
      });
      if(fns.length === 0) return;
      var hit = 0;
      fns.forEach(function(fn){ if(pick(fn)) hit++; });
      rows.push({ node: n, hit: hit, total: fns.length, pct: hit / fns.length });
    });

    var totalHit = 0, totalAll = 0;
    rows.forEach(function(r){ totalHit += r.hit; totalAll += r.total; });
    var overallPct = totalAll > 0 ? Math.round(100 * totalHit / totalAll) : 0;

    if(rows.length === 0){
      return '<p class="ntext none">This map contains no documented functions.</p>';
    }

    // Worst-first: the module that needs attention most belongs at the top
    // of a panel meant to answer "where should I look", not filed
    // alphabetically where that answer is buried. Fewer functions is not
    // itself worse, so the tiebreak is functions-affected (a 0% module with
    // 20 functions matters more than one with 1), then module id for a
    // stable order once both numbers tie exactly.
    rows.sort(function(a, b){
      if(a.pct !== b.pct) return a.pct - b.pct;
      if(a.total !== b.total) return b.total - a.total;
      return a.node.id < b.node.id ? -1 : (a.node.id > b.node.id ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + label + ': <strong>' + totalHit + '/' + totalAll +
      '</strong> functions (' + overallPct + '%). ' + sub + '</p>');
    parts.push('<table class="antable"><thead><tr><th>Module</th><th>' + label +
      '</th><th></th></tr></thead><tbody>');
    rows.forEach(function(r){
      var pct = Math.round(r.pct * 100);
      var label2 = r.node.module || r.node.path;
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(label2) + '</td>' +
        '<td>' + r.hit + '/' + r.total + ' (' + pct + '%)</td>' +
        '<td><div class="anbar"><div class="anfill" style="width:' + pct + '%"></div></div></td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // R6: fan-in/fan-out per module, read straight off `n.requires`/
  // `n.required_by` — both already sorted, deduplicated indexes into
  // `ir.edges`'s require edges (see `Lib.Docmap.Node` in @types/init.lua),
  // so this is JS-side aggregation only, no new Lua extraction. Distinct
  // from `renderAnalysisPanel`: that one counts a boolean over a node's
  // *functions*, this counts edges over the *node itself*, so it is its
  // own small render function rather than a third `pick` callback bent
  // into the same shape.
  function renderAnalysisDeps(){
    var rows = [];
    IR.nodes.forEach(function(n){
      var fanIn = (n.required_by || []).length;
      var fanOut = (n.requires || []).length;
      if(fanIn === 0 && fanOut === 0) return;
      rows.push({ node: n, fanIn: fanIn, fanOut: fanOut });
    });

    if(rows.length === 0){
      return '<p class="ntext none">This map contains no require edges.</p>';
    }

    // Highest fan-in first: the module most other modules depend on is the
    // one whose blast radius matters most, the same "most consequential
    // first" rule the coverage panels already follow with their pct sort.
    // Fan-out is the tiebreak, not an equal-weight second key — a module
    // nothing depends on but that itself pulls in a lot is a different
    // smell (the roadmap's "God module" idea), worth seeing but not at the
    // cost of burying real fan-in leaders under it.
    rows.sort(function(a, b){
      if(a.fanIn !== b.fanIn) return b.fanIn - a.fanIn;
      if(a.fanOut !== b.fanOut) return b.fanOut - a.fanOut;
      return a.node.id < b.node.id ? -1 : (a.node.id > b.node.id ? 1 : 0);
    });

    var maxFanIn = rows.reduce(function(m, r){ return Math.max(m, r.fanIn); }, 0);

    var parts = [];
    parts.push('<p class="nsub">' + rows.length + ' modules with at least one require ' +
      'edge. Fan-in is how many other modules require this one — the blast radius if it ' +
      'changes. Fan-out is how many modules it requires itself.</p>');
    parts.push('<table class="antable"><thead><tr><th>Module</th><th>Fan-in</th>' +
      '<th>Fan-out</th><th></th></tr></thead><tbody>');
    rows.forEach(function(r){
      var barPct = maxFanIn > 0 ? Math.round(100 * r.fanIn / maxFanIn) : 0;
      var label = r.node.module || r.node.path;
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(label) + '</td>' +
        '<td>' + r.fanIn + '</td>' +
        '<td>' + r.fanOut + '</td>' +
        '<td><div class="anbar"><div class="anfill" style="width:' + barPct + '%"></div></div></td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // Cyclomatic complexity (McCabe): `fn.complexity`, computed unconditionally
  // by docmap.functions during the scan itself (unlike tested/documented,
  // there is no IR-only "resolve" step that could derive it later — it
  // needs the treesitter node, which only exists during that same pass).
  // Ranked by function, not rolled up per module: "longest/most tangled
  // function" is a property of one function, and averaging it into a
  // per-module score would bury the one function that actually needs
  // attention under a healthy module's mean.
  function renderAnalysisComplexity(){
    var rows = [];
    IR.nodes.forEach(function(n){
      (n.functions || []).forEach(function(fn){
        rows.push({ node: n, fn: fn, complexity: fn.complexity || 1 });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">This map contains no documented functions.</p>';
    }

    rows.sort(function(a, b){
      if(a.complexity !== b.complexity) return b.complexity - a.complexity;
      return a.fn.signature < b.fn.signature ? -1 : 1;
    });
    var maxC = rows.reduce(function(m, r){ return Math.max(m, r.complexity); }, 1);

    var parts = [];
    parts.push('<p class="nsub">' + rows.length + ' documented functions, ranked by ' +
      'cyclomatic complexity (McCabe) — one point per if/elseif/while/for/repeat/and/or, ' +
      'plus a base of 1. Highest first.</p>');
    parts.push('<table class="antable"><thead><tr><th>Function</th><th>Module</th>' +
      '<th>Complexity</th><th></th></tr></thead><tbody>');
    rows.forEach(function(r){
      var barPct = Math.round(100 * r.complexity / maxC);
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.fn.signature) + '</td>' +
        '<td>' + esc(r.node.module || r.node.path) + '</td>' +
        '<td>' + r.complexity + '</td>' +
        '<td><div class="anbar"><div class="anfill" style="width:' + barPct + '%"></div></div></td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  var analysisTestHTML = null, analysisDocHTML = null, analysisDepsHTML = null,
    analysisComplexityHTML = null;
  function drawAnalysis(){
    var host = document.getElementById("anbody");
    var atool = (state.atool === "doc" || state.atool === "deps" || state.atool === "complexity")
      ? state.atool : "test";

    if(atool === "test"){
      if(analysisTestHTML === null){
        analysisTestHTML = renderAnalysisPanel(
          "Tested",
          "A function counts as tested when its bare name is found somewhere " +
          "under the configured tests directory — see docmap's coverage.lua " +
          "for what that heuristic can and cannot see.",
          function(fn){ return !!fn.tested; },
          false
        );
      }
      host.innerHTML = analysisTestHTML;
    } else if(atool === "doc"){
      if(analysisDocHTML === null){
        analysisDocHTML = renderAnalysisPanel(
          "Documented",
          "A function counts as documented when it has a summary and its " +
          "parameters are fully and correctly named — @internal functions " +
          "are excluded entirely, not counted as undocumented.",
          function(fn){ return !!fn.documented; },
          true
        );
      }
      host.innerHTML = analysisDocHTML;
    } else if(atool === "deps"){
      if(analysisDepsHTML === null) analysisDepsHTML = renderAnalysisDeps();
      host.innerHTML = analysisDepsHTML;
    } else {
      if(analysisComplexityHTML === null) analysisComplexityHTML = renderAnalysisComplexity();
      host.innerHTML = analysisComplexityHTML;
    }

    host.querySelectorAll(".anrow").forEach(function(tr){
      tr.addEventListener("click", function(){
        navigate({ tab: "tree", id: tr.dataset.node });
      });
    });
    document.querySelectorAll("#antoggle .anview-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.atool === atool);
    });
  }

  function drawHierarchy(centerId, view){
    view = VIEWS[view] ? view : "modules";
    hcenter = (centerId && byId[centerId]) ? centerId : (hcenter && byId[hcenter] ? hcenter : IR.root);
    var center = byId[hcenter];

    var oldNote = hgraphWrap.parentNode.querySelector(".htrunc");
    if(oldNote) oldNote.remove();
    drawLegend(view);

    var depth = state.depth === 0 ? 0 : (state.depth || 2);

    // A centered function only applies while the center is still its own
    // node. The search box re-centers live as you type without touching the
    // rest of the state, so without this the Calls view would keep drawing
    // the previously focused function and quietly ignore what was typed.
    var wantFn = (state.fn && fnByKey[state.fn] && fnByKey[state.fn].node.id === hcenter)
      ? state.fn : null;

    var built;
    if(view === "types") built = layoutTypes(hcenter);
    else if(view === "inheritance") built = layoutInheritance(hcenter);
    else if(view === "deps") built = layoutDeps(hcenter, state.dir || "out", depth, !!state.ext);
    else if(view === "calls") built = layoutCalls(hcenter, wantFn, state.dir || "out", depth);
    else built = layoutModules(hcenter);

    if(built.count === 0){
      clearGraph();
      hpathEl.textContent = center.module || center.path;
      hgraph.style.width = ""; hgraph.style.height = "";
      hstage.style.width = ""; hstage.style.height = "";
      // Cleared, not just left behind: applyZoom() multiplies this by the
      // scale, so a stale extent would give an empty message a scroll area
      // thousands of pixels wide the moment the wheel is touched.
      stageExtent = { w: 0, h: 0 };
      // Into #hgraph, not #hstage: the stage is position:absolute (it carries
      // the zoom transform), so it contributes no height to its parent, and
      // #hgraph's explicit height was just cleared above — a message parented
      // to the stage therefore renders into a 0px-tall box and is clipped away
      // by #hgraph-wrap's overflow. Every empty state in this tab was
      // invisible for that reason; a normal-flow child of the relative #hgraph
      // gives it height on its own, with nothing measured off the DOM (which
      // would read 0 anyway while the pane is display:none).
      hgraph.insertAdjacentHTML("beforeend", emptyMessage(view, center));
      return;
    }

    var suffix = { types: " · types", inheritance: " · inheritance",
                   deps: " · deps", calls: " · calls" }[view] || "";
    var focusFn = view === "calls" && wantFn;
    hpathEl.textContent = (focusFn ? wantFn.split("#")[1] + "  in  " : "") +
      (center.module || center.path) + suffix +
      (isGraphView(view) ? "  ·  " + (state.dir || "out") + ", depth " + (depth === 0 ? "∞" : depth) : "");

    // The empty branch above writes its explanation straight into #hgraph;
    // nothing else removes it, because reconcile() only ever adds and removes
    // boxes it knows about. Without this, going Calls-on-a-namespace (empty)
    // → Modules left "lib.nvim declares no functions." sitting above a
    // ninety-box diagram.
    var stale = hgraph.querySelector(".hmsg");
    if(stale) stale.remove();

    var laid = layerPositions(built.layers);
    var positions = laid.positions;

    // The key the view considers "the middle": a node id in three views, a
    // function id in Calls. Used for the highlight ring and the scroll
    // target, so both follow whatever the view is actually about.
    var centerKey = hcenter;
    if(view === "types") centerKey = built.layers[0] && built.layers[0][0];
    else if(view === "inheritance") centerKey = built.centerKey;
    else if(view === "calls") centerKey = wantFn || (built.layers[0] && built.layers[0][0]);

    var moved = reconcile(positions, view, centerKey);

    var totalW = laid.maxRowWidth + PAD * 2;
    var totalH = PAD * 2 + built.layers.length * BOX_H + Math.max(0, built.layers.length - 1) * GAP_Y;

    var svgNS = "http://www.w3.org/2000/svg";
    var old = document.getElementById("hsvg");
    if(old) old.remove();
    var svg = document.createElementNS(svgNS, "svg");
    svg.id = "hsvg";
    svg.setAttribute("width", totalW);
    svg.setAttribute("height", totalH);
    svg.appendChild(buildDefs(svgNS));

    // Edge geometry cannot be interpolated the way a box position can — `d`
    // is not an animatable CSS property, and a per-frame path interpolator
    // for up to 90 edges buys very little over simply not drawing lines that
    // would be pointing at boxes still in motion. So: hidden while the boxes
    // move, faded in once they have arrived.
    var neighbours = {};
    built.edges.forEach(function(e){
      var a = positions[e.from], b = positions[e.to];
      if(!a || !b || e.from === e.to) return;
      var p = document.createElementNS(svgNS, "path");
      p.setAttribute("d", edgePath(a, b));
      p.setAttribute("class", e.cls);
      p.setAttribute("marker-end", "url(#m-" + (e.marker || "tree") + ")");
      p.dataset.from = e.from;
      p.dataset.to = e.to;
      if(e.label){
        var title = document.createElementNS(svgNS, "title");
        title.textContent = e.label;
        p.appendChild(title);
      }
      svg.appendChild(p);
      (neighbours[e.from] = neighbours[e.from] || {})[e.to] = true;
      (neighbours[e.to] = neighbours[e.to] || {})[e.from] = true;
    });

    hstage.style.width = totalW + "px";
    hstage.style.height = totalH + "px";
    hstage.insertBefore(svg, hstage.firstChild);
    stageExtent = { w: totalW, h: totalH };
    applyZoom();

    if(moved){
      svg.classList.add("settling");
      setTimeout(function(){ svg.classList.remove("settling"); }, ANIM_MS);
    }

    hgraphNeighbours = neighbours;

    // Rows are centered on the widest layer, so the centered box can sit
    // thousands of pixels from the left edge on a wide map — without this,
    // opening the tab scrolls to (0,0) and shows an arbitrary fragment of
    // whichever layer is widest, not the node the view is actually about.
    // After a zoom-driven jump the cursor is the anchor: re-centering the
    // view here would yank the diagram out from under the pointer the gesture
    // is still on. The flag is consumed once, so ordinary navigation keeps
    // its centering.
    var selfPos = (centerKey && !suppressAutoScroll) ? positions[centerKey] : null;
    if(suppressAutoScroll){ suppressAutoScroll = false; }
    if(selfPos){
      var targetLeft = Math.max(0, selfPos.x + BOX_W / 2 - hgraphWrap.clientWidth / 2);
      var targetTop = Math.max(0, selfPos.y - hgraphWrap.clientHeight / 2 + BOX_H);
      if(moved && !reducedMotion()){
        hgraphWrap.scrollTo({ left: targetLeft, top: targetTop, behavior: "smooth" });
      } else {
        hgraphWrap.scrollLeft = targetLeft;
        hgraphWrap.scrollTop = targetTop;
      }
      var centerEl = hboxes[centerKey];
      if(centerEl && !reducedMotion()){
        centerEl.classList.remove("pulse");
        void centerEl.offsetWidth;
        centerEl.classList.add("pulse");
      }
    }

    if(built.truncated){
      var note = document.createElement("div");
      note.className = "htrunc";
      note.textContent = "Showing the first " + MAX_HNODES + " boxes — narrow the depth, or double-click a box to re-center on a smaller neighbourhood.";
      hgraphWrap.parentNode.insertBefore(note, hgraphWrap.nextSibling);
    }
  }

  function reducedMotion(){
    return window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }

  // =====================================================================
  // Zoom — two mechanisms that must stay separate in the code, or both end
  // up half-done:
  //
  //   geometric  the same diagram, larger. A CSS transform on #hstage.
  //              No relayout, no redraw, nothing in the URL — it is comfort,
  //              not state.
  //   semantic   past a threshold, a *different* excerpt: one level down into
  //              the module under the cursor, or one level up. That is
  //              exactly the navigate({center}) double-click already does.
  //
  // The geometric zoom is the feel between two levels; the semantic one is
  // the jump. Only the jump touches history — the same rule the search
  // preview had to learn, for the same reason.
  //
  // Positions stay analytic. The transform sits on a layer *above* the
  // computed pixel coordinates, so `positions`, reconcile() and the SVG paths
  // are all unaware a zoom exists.
  // =====================================================================
  var Z_MIN = 0.35, Z_MAX = 2.40;
  var DRILL_IN = 1.80, DRILL_OUT = 0.55;
  var AFTER_IN = 0.90, AFTER_OUT = 1.15;
  var COOLDOWN_MS = 260;
  var LOD_MIN = 0.65;

  var hzoom = 1;
  var stageExtent = { w: 0, h: 0 };
  var lastJump = 0;
  var suppressAutoScroll = false;
  var zoomLabel;

  function clampZoom(z){ return Math.min(Z_MAX, Math.max(Z_MIN, z)); }

  // #hgraph is sized to the scaled extent because a transform leaves layout
  // size alone; without this the scroll area would not grow on zoom-in and
  // half the diagram would be unreachable.
  function applyZoom(){
    hstage.style.transform = "scale(" + hzoom + ")";
    hgraph.style.width = Math.round(stageExtent.w * hzoom) + "px";
    hgraph.style.height = Math.round(stageExtent.h * hzoom) + "px";
    hstage.classList.toggle("lod-min", hzoom < LOD_MIN);
    if(zoomLabel) zoomLabel.textContent = Math.round(hzoom * 100) + "%";
  }

  // Keeps the graph point under the cursor fixed while scaling around it —
  // without this the diagram slides out from under the pointer and zooming
  // feels like it is fighting you.
  function zoomAt(clientX, clientY, factor){
    var r = hgraphWrap.getBoundingClientRect();
    var gx = (hgraphWrap.scrollLeft + clientX - r.left) / hzoom;
    var gy = (hgraphWrap.scrollTop + clientY - r.top) / hzoom;
    var before = hzoom;
    hzoom = clampZoom(hzoom * factor);
    if(hzoom === before) return false;
    applyZoom();
    hgraphWrap.scrollLeft = gx * hzoom - (clientX - r.left);
    hgraphWrap.scrollTop = gy * hzoom - (clientY - r.top);
    return true;
  }

  function setZoom(z){
    hzoom = clampZoom(z);
    applyZoom();
  }

  // The box under the cursor, or — when the pointer sits in empty space —
  // the nearest one, measured from `positions` rather than from the DOM, so
  // this keeps working at any scale and never triggers a layout read.
  function boxNear(clientX, clientY){
    var direct = boxOf(document.elementFromPoint(clientX, clientY));
    if(direct) return direct;

    var r = hgraphWrap.getBoundingClientRect();
    var gx = (hgraphWrap.scrollLeft + clientX - r.left) / hzoom;
    var gy = (hgraphWrap.scrollTop + clientY - r.top) / hzoom;
    var best = null, bestD = Infinity;
    Object.keys(hboxes).forEach(function(k){
      var el = hboxes[k];
      if(el.classList.contains("leaving")) return;
      var dx = parseFloat(el.style.left) + BOX_W / 2 - gx;
      var dy = parseFloat(el.style.top) + BOX_H / 2 - gy;
      var d = dx * dx + dy * dy;
      if(d < bestD){ bestD = d; best = el; }
    });
    return best;
  }

  // A jump that cannot happen — a leaf with no children, the root on the way
  // out, an external box that stands for nothing — pulses the box instead of
  // silently doing nothing, which reads as a bug. The zoom is deliberately
  // left where it is: on a leaf, zooming further in to read the box is a
  // reasonable thing to want, and crossing-based triggering means it will not
  // re-fire on every further notch.
  function refuseJump(box){
    if(box && !reducedMotion()){
      box.classList.remove("pulse");
      void box.offsetWidth;
      box.classList.add("pulse");
    }
  }

  // In Deps and Calls "one level deeper" is not defined — a require graph is
  // not a containment hierarchy. Depth is the axis that means "show more"
  // there, and it already exists as state and as a toolbar control, so the
  // threshold binds to it instead.
  function drill(dir, clientX, clientY){
    var now = Date.now();
    // One flick of the wheel must not fall three levels. Blocked by the
    // cooldown, the zoom is pulled back just inside the threshold so the next
    // notch crosses it again — left where it was, the gesture would have to
    // be wound all the way back before it could retry.
    if(now - lastJump < COOLDOWN_MS){
      setZoom(dir > 0 ? DRILL_IN - 0.02 : DRILL_OUT + 0.02);
      return;
    }

    if(isGraphView(state.view)){
      var d = state.depth === 0 ? 0 : (state.depth || 2);
      var next = dir > 0 ? (d === 0 ? 0 : d + 1) : (d <= 1 ? 1 : d - 1);
      if(next === d){ refuseJump(null); return; }
      lastJump = now;
      suppressAutoScroll = true;
      setZoom(dir > 0 ? AFTER_IN : AFTER_OUT);
      navigate({ depth: next });
      return;
    }

    if(dir > 0){
      var box = boxNear(clientX, clientY);
      var target = box && box._spec && box._spec.recenter;
      // Three refusals, all of which would otherwise reset the zoom for no
      // visible reason: nothing under the cursor, a leaf with no level below
      // it, and — the easy one to miss — the box that is *already* the
      // center, whose children are what the view is showing right now.
      if(!target || target === hcenter || !((byId[target] || {}).children || []).length){
        refuseJump(box);
        return;
      }
      lastJump = now;
      suppressAutoScroll = true;
      setZoom(AFTER_IN);
      navigate({ center: target, fn: null });
    } else {
      var parent = (byId[hcenter] || {}).parent;
      if(!parent){ refuseJump(null); return; }
      lastJump = now;
      suppressAutoScroll = true;
      setZoom(AFTER_OUT);
      navigate({ center: parent, fn: null });
    }
  }

  hgraphWrap.addEventListener("wheel", function(ev){
    // Shift keeps a way to pan horizontally, which is what the wheel would
    // otherwise have done here.
    if(ev.shiftKey){
      ev.preventDefault();
      hgraphWrap.scrollLeft += ev.deltaY;
      return;
    }
    ev.preventDefault();

    // Exponential so each notch feels the same at any scale, and so a
    // trackpad's small deltas do not crawl. ctrl+wheel is what a pinch
    // gesture arrives as, and it means the same thing here.
    var before = hzoom;
    var factor = Math.exp(-ev.deltaY * 0.0015);
    zoomAt(ev.clientX, ev.clientY, factor);

    // Fires on *crossing* the threshold, not on being past it. Two things
    // depend on that: a refused jump (a leaf, the root) leaves the zoom above
    // the line without re-firing on every further notch, and — the bug this
    // replaced — a zoom that came to rest above DRILL_IN no longer drills
    // *in* when the next notch is a zoom-*out*.
    if(before < DRILL_IN && hzoom >= DRILL_IN) drill(1, ev.clientX, ev.clientY);
    else if(before > DRILL_OUT && hzoom <= DRILL_OUT) drill(-1, ev.clientX, ev.clientY);
  }, { passive: false });

  // Keyboard equivalents, so the view is not mouse-only.
  document.addEventListener("keydown", function(ev){
    if(state.tab !== "hierarchy") return;
    if(ev.target && /^(INPUT|TEXTAREA)$/.test(ev.target.tagName)) return;
    if(ev.ctrlKey || ev.metaKey || ev.altKey) return;
    if(ev.key === "+" || ev.key === "="){ ev.preventDefault(); setZoom(hzoom * 1.2); }
    else if(ev.key === "-"){ ev.preventDefault(); setZoom(hzoom / 1.2); }
    else if(ev.key === "0"){ ev.preventDefault(); setZoom(1); }
  });

  // =====================================================================
  // Graph interaction. Delegated from #hgraph rather than bound per box:
  // reconcile() reuses boxes across redraws, and re-adding listeners on every
  // draw would stack duplicates on exactly the boxes that survive longest.
  // =====================================================================
  var hgraphNeighbours = {};

  function boxOf(target){
    var el = target;
    while(el && el !== hgraph){
      if(el.classList && el.classList.contains("hnode")) return el;
      el = el.parentNode;
    }
    return null;
  }

  hgraph.addEventListener("click", function(ev){
    var box = boxOf(ev.target);
    if(!box || !box._spec) return;
    // A tag_files-resolved external box has no node in *this* map — nothing
    // to navigate to here — but does have another project's own generated
    // page to open, in a new tab so the current map's state is not lost.
    if(box._spec.externalHtml){ window.open(box._spec.externalHtml, "_blank"); return; }
    // An unresolved external box has no node behind it at all — no id to
    // select, nothing to re-center on. Inert rather than navigating
    // somewhere arbitrary.
    if(!box._spec.nodeId) return;
    navigate({ tab: "tree", id: box._spec.nodeId });
  });

  hgraph.addEventListener("dblclick", function(ev){
    var box = boxOf(ev.target);
    if(!box || !box._spec || !box._spec.recenter) return;
    ev.stopPropagation();
    // In the Calls view a double-click re-centers on the function itself,
    // which is the whole point of the view; elsewhere there is no finer
    // object than the node.
    if(box._spec.fnKey) navigate({ center: box._spec.recenter, fn: box._spec.fnKey });
    else navigate({ center: box._spec.recenter, fn: null });
  });

  // Hover focus: dim everything that is not a direct neighbour of the box
  // under the cursor. Pure class toggling — on a dense require graph this is
  // the difference between a readable diagram and a spider's web, and it
  // costs no relayout.
  function clearFocus(){ hgraph.classList.remove("focusing"); }

  hgraph.addEventListener("mouseover", function(ev){
    var box = boxOf(ev.target);
    // Moving off a box onto the graph's own background has to un-focus:
    // mouseleave only fires when the pointer leaves #hgraph entirely, so
    // without this the last box hovered stayed lit while the cursor sat in
    // empty space next to it.
    if(!box){ clearFocus(); return; }
    var key = box.dataset.key;
    var near = hgraphNeighbours[key] || {};
    hgraph.classList.add("focusing");
    Object.keys(hboxes).forEach(function(k){
      hboxes[k].classList.toggle("near", k === key || near[k]);
    });
    var svg = document.getElementById("hsvg");
    if(svg) svg.querySelectorAll(".hedge").forEach(function(p){
      p.classList.toggle("near", p.dataset.from === key || p.dataset.to === key);
    });
  });

  hgraph.addEventListener("mouseleave", clearFocus);

  // =====================================================================
  // Graph toolbar. Direction and depth only apply to the directed views, so
  // their controls are hidden elsewhere rather than sitting there inert.
  // =====================================================================
  function syncGraphControls(s){
    document.querySelectorAll(".hview-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.view === (s.view || "modules"));
    });
    document.querySelectorAll(".hdir-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.dir === (s.dir || "out"));
    });
    document.querySelectorAll(".hdepth-btn").forEach(function(b){
      b.classList.toggle("active", parseInt(b.dataset.depth, 10) === (s.depth === 0 ? 0 : (s.depth || 2)));
    });
    var show = isGraphView(s.view) ? "" : "none";
    document.getElementById("hdir").style.display = show;
    document.getElementById("hdepth").style.display = show;
    // External requires exist only in the Deps view; the Calls view has no
    // equivalent, since a call into a module the map never scanned leaves no
    // resolvable name behind to draw.
    var hext = document.getElementById("hext");
    hext.style.display = s.view === "deps" ? "" : "none";
    hext.classList.toggle("active", !!s.ext);
  }

  document.getElementById("hup").addEventListener("click", function(){
    var center = byId[hcenter || IR.root];
    if(center && center.parent) navigate({ center: center.parent, fn: null });
  });
  document.getElementById("hroot").addEventListener("click", function(){
    navigate({ center: IR.root, fn: null });
  });
  document.querySelectorAll(".hview-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ view: b.dataset.view }); });
  });
  document.querySelectorAll(".ixview-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ tab: "index", iview: b.dataset.iview }); });
  });
  document.querySelectorAll(".anview-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ tab: "analysis", atool: b.dataset.atool }); });
  });
  document.querySelectorAll(".hdir-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ dir: b.dataset.dir }); });
  });
  document.querySelectorAll(".hdepth-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ depth: parseInt(b.dataset.depth, 10) }); });
  });
  document.getElementById("hext").addEventListener("click", function(){
    navigate({ ext: !state.ext });
  });

  // =====================================================================
  // SVG export
  //
  // The diagram on screen is half SVG (the edges) and half absolutely
  // positioned HTML (the boxes), which is the right trade for an interactive
  // page and useless as a file. Rather than wrapping the boxes in
  // <foreignObject> — which Inkscape and most converters do not render — the
  // export redraws them as plain <rect>/<text>, so the result opens anywhere.
  //
  // Colours are read back off the live DOM instead of being hardcoded, so the
  // exported file matches the theme it was exported from rather than always
  // being the light one.
  // =====================================================================
  function exportSvg(){
    var svg = document.getElementById("hsvg");
    if(!svg) return;
    var w = svg.getAttribute("width"), h = svg.getAttribute("height");
    var cs = getComputedStyle(document.body);
    var parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="'+w+'" height="'+h+'" '+
      'viewBox="0 0 '+w+' '+h+'" font-family="monospace">'];
    parts.push('<rect width="100%" height="100%" fill="'+cs.backgroundColor+'"/>');

    // Markers first: the paths below reference them by id.
    parts.push('<defs>');
    ["tree","type","ext","dep","call"].forEach(function(name){
      var probe = document.querySelector("#m-" + name + " path");
      var fill = probe ? getComputedStyle(probe).fill : cs.color;
      parts.push('<marker id="x-'+name+'" viewBox="0 0 8 8" refX="7" refY="4" '+
        'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'+
        '<path d="M0,0 L8,4 L0,8 z" fill="'+fill+'"/></marker>');
    });
    parts.push('</defs>');

    svg.querySelectorAll(".hedge").forEach(function(p){
      var st = getComputedStyle(p);
      var marker = (p.getAttribute("marker-end") || "").replace("url(#m-", "").replace(")", "");
      parts.push('<path d="'+esc(p.getAttribute("d"))+'" fill="none" stroke="'+st.stroke+'" '+
        'stroke-width="'+st.strokeWidth+'" stroke-dasharray="'+
        (st.strokeDasharray === "none" ? "" : st.strokeDasharray)+'" opacity="'+st.opacity+'" '+
        'marker-end="url(#x-'+marker+')"/>');
    });

    Object.keys(hboxes).forEach(function(key){
      var el = hboxes[key];
      if(el.classList.contains("leaving")) return;
      var x = parseFloat(el.style.left), y = parseFloat(el.style.top);
      var st = getComputedStyle(el);
      parts.push('<rect x="'+x+'" y="'+y+'" width="'+BOX_W+'" height="'+BOX_H+'" rx="7" '+
        'fill="'+st.backgroundColor+'" stroke="'+st.borderTopColor+'"/>');
      var nm = el.querySelector(".hnm"), sub = el.querySelector(".hsm, .hkind, .hline");
      if(nm){
        parts.push('<text x="'+(x+9)+'" y="'+(y+19)+'" font-size="11" font-weight="600" '+
          'fill="'+getComputedStyle(nm).color+'">'+esc(clip(nm.textContent, 22))+'</text>');
      }
      if(sub){
        parts.push('<text x="'+(x+9)+'" y="'+(y+35)+'" font-size="9.5" '+
          'fill="'+getComputedStyle(sub).color+'">'+esc(clip(sub.textContent, 26))+'</text>');
      }
    });

    parts.push('</svg>');

    var blob = new Blob([parts.join("\n")], { type: "image/svg+xml" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = (state.view || "modules") + "-" +
      (hcenter || "map").replace(/[^\w.-]+/g, "_") + ".svg";
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function(){ URL.revokeObjectURL(a.href); }, 1000);
  }

  // SVG <text> does not wrap or ellipsize; the HTML boxes rely on CSS
  // overflow for that, so the export has to truncate itself.
  function clip(s, n){
    s = (s || "").trim();
    return s.length > n ? s.slice(0, n - 1) + "…" : s;
  }

  document.getElementById("hexport").addEventListener("click", exportSvg);

  zoomLabel = document.getElementById("hzoomlabel");
  document.getElementById("hzoomreset").addEventListener("click", function(){ setZoom(1); });
  applyZoom();


  // =====================================================================
  // Search — one input, two behaviors depending on the active tab: filters
  // visible rows in the Tree tab (unchanged), re-centers the Hierarchy view
  // on the best-matching node as you type in the Hierarchy tab. Typing
  // updates live via a replaced (not pushed) history entry — five keystrokes
  // finding the same module should not become five Back-button stops — and
  // Enter commits the current match as a real, pushed navigation.
  // =====================================================================
  function findBestMatch(query){
    var q = query.toLowerCase().trim();
    if(!q) return null;
    var starts = null, contains = null;
    for(var i = 0; i < IR.nodes.length; i++){
      var n = IR.nodes[i];
      var name = (n.name || "").toLowerCase();
      var mod = (n.module || "").toLowerCase();
      if(name === q || mod === q) return n.id;
      if(!starts && (name.indexOf(q) === 0 || mod.indexOf(q) === 0)) starts = n.id;
      if(!contains && (name.indexOf(q) >= 0 || mod.indexOf(q) >= 0 || (n.summary||"").toLowerCase().indexOf(q) >= 0)) contains = n.id;
    }
    return starts || contains;
  }

  var q = document.getElementById("q");
  q.addEventListener("input", function(){
    var v = this.value.toLowerCase().trim();
    if(state.tab === "hierarchy"){
      // Live preview only — draws directly, deliberately bypassing
      // navigate()/history entirely rather than replacing on every
      // keystroke. An earlier version used navigate(patch, {push:false}),
      // which calls history.replaceState on the *current top entry* — right
      // after switching to the Hierarchy tab, that entry is the tab-switch
      // itself, so the first keystroke overwrote it. Enter's subsequent
      // pushState then pushed a duplicate of that already-overwritten entry
      // instead of a distinct new stop, so Back from the committed search
      // landed on an indistinguishable copy of itself instead of the
      // pre-search tab state. Not writing to history at all while typing
      // avoids the clobber; drawHierarchy still keeps its own `hcenter`
      // current, so Up/Root/double-click after a preview (without ever
      // pressing Enter) act on what's actually on screen.
      var match = findBestMatch(this.value);
      if(match) drawHierarchy(match, state.view);
      return;
    }
    treeEl.querySelectorAll(".row").forEach(function(r){
      // Three row shapes now share this list: node rows, function rows (which
      // carry data-fn and match on their own signature, not their module's
      // summary), and the function-group header, which has no data at all and
      // would have thrown on `n.name` before this branch existed.
      var hit;
      if(r.dataset.fn){
        var entry = fnByKey[r.dataset.fn];
        hit = !v || !entry ||
          (entry.fn.signature + " " + (entry.fn.summary || "")).toLowerCase().indexOf(v) >= 0;
      } else if(r.classList.contains("fnhead")){
        hit = !v;
      } else {
        var n = byId[r.dataset.id];
        hit = !v || !n ||
          (n.name+" "+(n.module||"")+" "+(n.summary||"")).toLowerCase().indexOf(v) >= 0;
      }
      r.style.display = hit ? "" : "none";
    });
    if(v) treeEl.querySelectorAll(".kids").forEach(function(k){ k.classList.remove("hide"); });
  });
  q.addEventListener("keydown", function(ev){
    if(ev.key === "Enter" && state.tab === "hierarchy"){
      var match = findBestMatch(this.value);
      if(match) navigate({ center: match });
    }
  });

  // =====================================================================
  // Context menu
  //
  // Every clickable object in the page — a tree row, a function row, a graph
  // box, a type or function entry in the detail pane — resolves through one
  // describeTarget() into { kind, nodeId, fnKey, className, label }, and the
  // menu is built from that. One resolver instead of four menus is what keeps
  // "right-click anything, get the same verbs" true as views are added.
  //
  // preventDefault only fires when the target actually resolves: selecting a
  // paragraph of documentation and reaching for the browser's own Copy has to
  // keep working, so unrecognised targets are left entirely alone.
  // =====================================================================
  var ctx = document.getElementById("ctx");
  var ctxItems = [];
  var ctxHi = -1;

  function describeTarget(el){
    while(el && el !== document.body){
      if(el.dataset){
        if(el.classList.contains("hnode") && el._spec){
          return { kind: el._spec.fnKey ? "function" : (classByName[el.dataset.key] ? "class" : "node"),
                   nodeId: el._spec.nodeId, fnKey: el._spec.fnKey,
                   className: classByName[el.dataset.key] ? el.dataset.key : null,
                   label: el.dataset.key };
        }
        if(el.dataset.fn && fnByKey[el.dataset.fn]){
          var e = fnByKey[el.dataset.fn];
          return { kind: "function", nodeId: e.node.id, fnKey: el.dataset.fn, label: e.fn.signature };
        }
        if(el.dataset.id && byId[el.dataset.id]){
          var n = byId[el.dataset.id];
          return { kind: "node", nodeId: n.id, label: n.module || n.path };
        }
      }
      el = el.parentNode;
    }
    return null;
  }

  function ctxClose(){ ctx.classList.remove("open"); ctxItems = []; ctxHi = -1; }

  function buildMenu(t){
    var n = byId[t.nodeId];
    var items = [];
    var fnEntry = t.fnKey ? fnByKey[t.fnKey] : null;

    items.push({ label: "Show in tree", run: function(){ navigate({ tab: "tree", id: t.nodeId }); } });
    items.push({ sep: true });

    items.push({ label: "Hierarchy", hint: "structure",
      run: function(){ navigate({ tab: "hierarchy", view: "modules", center: t.nodeId, fn: null }); } });

    var hasDeps = ((n.requires || []).length + (n.required_by || []).length) > 0;
    items.push({ label: "Dependencies — needs", hint: (n.requires || []).length || "0",
      disabled: !(n.requires || []).length,
      run: function(){ navigate({ tab: "hierarchy", view: "deps", center: t.nodeId, dir: "out", fn: null }); } });
    items.push({ label: "Dependencies — needed by", hint: (n.required_by || []).length || "0",
      disabled: !(n.required_by || []).length,
      run: function(){ navigate({ tab: "hierarchy", view: "deps", center: t.nodeId, dir: "in", fn: null }); } });
    items.push({ label: "Dependencies — both ways", disabled: !hasDeps,
      run: function(){ navigate({ tab: "hierarchy", view: "deps", center: t.nodeId, dir: "both", fn: null }); } });

    // Counts come from the same adjacency the view walks, so a menu entry is
    // only offered when it leads somewhere — an enabled item that opens an
    // empty diagram teaches people to distrust the menu.
    var outN = fnEntry ? (callOut[t.fnKey] || []).length
      : (n.functions || []).reduce(function(a, f){ return a + (callOut[fnKey(n.id, f.name)] || []).length; }, 0);
    var inN = fnEntry ? (callIn[t.fnKey] || []).length
      : (n.functions || []).reduce(function(a, f){ return a + (callIn[fnKey(n.id, f.name)] || []).length; }, 0);

    items.push({ sep: true });
    items.push({ label: fnEntry ? "Calls — callees" : "Calls — what it calls", hint: outN || "0",
      disabled: !outN,
      run: function(){ navigate({ tab: "hierarchy", view: "calls", center: t.nodeId, fn: t.fnKey || null, dir: "out" }); } });
    items.push({ label: fnEntry ? "Calls — callers" : "Calls — what calls it", hint: inN || "0",
      disabled: !inN,
      run: function(){ navigate({ tab: "hierarchy", view: "calls", center: t.nodeId, fn: t.fnKey || null, dir: "in" }); } });
    items.push({ label: "Calls — both ways", disabled: !(outN || inN),
      run: function(){ navigate({ tab: "hierarchy", view: "calls", center: t.nodeId, fn: t.fnKey || null, dir: "both" }); } });

    items.push({ label: "Types", disabled: !(n.types_detail || []).length,
      run: function(){ navigate({ tab: "hierarchy", view: "types", center: t.nodeId, fn: null }); } });

    // Enabled only when this node actually owns a class that inherits or is
    // inherited from — the view would otherwise open on its own empty state,
    // and "greyed out with a reason" beats "opens and says nothing here".
    var inhN = (n.types_detail || []).filter(function(ty){ return inInheritance[ty.name]; }).length;
    items.push({ label: "Inheritance", hint: inhN || "0", disabled: !inhN,
      run: function(){ navigate({ tab: "hierarchy", view: "inheritance", center: t.nodeId, fn: null }); } });

    items.push({ sep: true });
    if(n.source){
      var u = srcUrl(n.source);
      var frag = fnEntry ? "#L" + fnEntry.fn.line : "";
      items.push({ label: u ? "Open source ↗" : "Open source",
        run: function(){ window.open(u ? u + frag : rel(n.source), u ? "_blank" : "_self"); } });
    }
    if(n.readme){
      items.push({ label: "Open README", run: function(){ window.open(rel(n.readme), "_self"); } });
    }

    items.push({ sep: true });
    items.push({ label: "Copy module path", run: function(){ copy(n.module || n.path); } });
    items.push({ label: "Copy link to this view", run: function(){
      copy(location.origin + location.pathname + serializeState(state));
    } });

    return items;
  }

  // clipboard.writeText is unavailable on a file:// page in some browsers,
  // which is exactly how this artifact is most often opened. The textarea
  // fallback is not legacy cruft here, it is the primary path.
  function copy(text){
    if(navigator.clipboard && window.isSecureContext){
      navigator.clipboard.writeText(text);
      return;
    }
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand("copy"); } catch(e) {}
    document.body.removeChild(ta);
  }

  function openMenu(x, y, t){
    var items = buildMenu(t);
    var html = ['<div class="hdr">' + esc(t.label || "") + '</div>'];
    items.forEach(function(it, i){
      if(it.sep){ html.push('<div class="sep"></div>'); return; }
      html.push('<div class="ci' + (it.disabled ? " disabled" : "") + '" data-i="' + i + '">' +
        esc(it.label) + (it.hint !== undefined ? '<span class="hint">' + esc(String(it.hint)) + '</span>' : '') +
        '</div>');
    });
    ctx.innerHTML = html.join("");
    ctxItems = items;
    ctxHi = -1;
    ctx.classList.add("open");

    // Positioned after the menu is measurable, clamped so a right-click near
    // the bottom or right edge does not open a menu that runs off-screen.
    var r = ctx.getBoundingClientRect();
    ctx.style.left = Math.min(x, window.innerWidth - r.width - 8) + "px";
    ctx.style.top = Math.min(y, window.innerHeight - r.height - 8) + "px";

    ctx.querySelectorAll(".ci").forEach(function(el){
      el.addEventListener("click", function(){
        var it = ctxItems[parseInt(el.dataset.i, 10)];
        if(!it || it.disabled) return;
        ctxClose();
        it.run();
      });
    });
  }

  document.addEventListener("contextmenu", function(ev){
    var t = describeTarget(ev.target);
    if(!t || !byId[t.nodeId]) return;
    ev.preventDefault();
    openMenu(ev.clientX, ev.clientY, t);
  });

  document.addEventListener("click", function(ev){
    if(ctx.classList.contains("open") && !ctx.contains(ev.target)) ctxClose();
  });
  window.addEventListener("blur", ctxClose);
  window.addEventListener("resize", ctxClose);
  document.addEventListener("scroll", ctxClose, true);

  document.addEventListener("keydown", function(ev){
    if(!ctx.classList.contains("open")) return;
    if(ev.key === "Escape"){ ctxClose(); return; }
    if(ev.key !== "ArrowDown" && ev.key !== "ArrowUp" && ev.key !== "Enter") return;
    ev.preventDefault();
    var els = Array.prototype.slice.call(ctx.querySelectorAll(".ci:not(.disabled)"));
    if(!els.length) return;
    if(ev.key === "Enter"){
      if(ctxHi >= 0) els[ctxHi].click();
      return;
    }
    els.forEach(function(e){ e.classList.remove("hi"); });
    ctxHi = ev.key === "ArrowDown"
      ? (ctxHi + 1) % els.length
      : (ctxHi <= 0 ? els.length - 1 : ctxHi - 1);
    els[ctxHi].classList.add("hi");
  });

  // =====================================================================
  // Initial load: parse whatever hash the page was opened with (a bare
  // #<id> from an old-style/shared link, a full serialized state from
  // Back/Forward, or nothing) and apply it as a *replace*, not a push — the
  // very first state should not itself create a Back-stack entry.
  // =====================================================================
  var initial = parseState(location.hash);
  if(!initial.id && !initial.center) initial.id = IR.root;
  applyState(initial, false);
})();
]]

---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
---@param opts Lib.Docmap.Opts
---@return string
function M.render(ir, findings, opts)
  -- How far the artifact sits below the repo root, so relative links back to
  -- README files resolve from wherever it was written.
  local out_dir = opts.out_dir or "docs/map"
  local depth = select(2, out_dir:gsub("[^/]+", "")) or 0

  local meta = vim.deepcopy(ir.meta)
  meta.out_depth = depth

  local nodes = {}
  for _, id in ipairs(ir.order) do
    nodes[#nodes + 1] = ir.nodes[id]
  end

  local payload = json.encode({
    meta = meta,
    root = ir.root,
    nodes = nodes,
    edges = ir.edges or {},
    tag_links = ir.tag_links or {},
  })
  -- `</script>` inside JSON would terminate the block early.
  payload = payload:gsub("</", "<\\/")

  local findings_json = json.encode(findings):gsub("</", "<\\/")

  local c = ir.meta.counts
  local t = { error = 0, warn = 0, info = 0 }
  for _, f in ipairs(findings) do
    t[f.severity] = (t[f.severity] or 0) + 1
  end

  local rows = {}
  for _, f in ipairs(findings) do
    -- data-node drives the click-to-select wiring in JS. Left off entirely
    -- (rather than set to an empty string) when the finding has no node, or
    -- points at something that isn't a real IR node id (config.lua's
    -- aggregator check reports against a synthetic "lua/lib/@types" path
    -- that was never a scanned node) — the click handler only wires up rows
    -- that actually carry the attribute, so an unresolvable target silently
    -- stays inert instead of being a dead click.
    local node_attr = f.node and (' data-node="%s"'):format(esc(f.node)) or ""
    rows[#rows + 1] = ([[<tr%s><td><span class="sev %s">%s</span></td><td class="msg">%s</td><td class="msg">%s</td></tr>]]):format(
      node_attr,
      f.severity,
      f.severity,
      esc(f.check),
      esc(f.message)
    )
  end

  return table.concat({
    "<!doctype html>",
    '<html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
    "<title>",
    esc(ir.meta.title),
    " — module map</title>",
    "<style>",
    CSS,
    "</style></head><body>",

    "<header><h1>",
    esc(ir.meta.title),
    '<span class="sub">module map</span></h1>',
    '<div class="stats">',
    "<span><b>",
    tostring(c.module or 0),
    "</b> modules</span>",
    "<span><b>",
    tostring(c.namespace or 0),
    "</b> namespaces</span>",
    "<span><b>",
    tostring(c.file or 0),
    "</b> files</span>",
    '<span><b class="sev error">',
    tostring(t.error),
    "</b> errors</span>",
    '<span><b class="sev warn">',
    tostring(t.warn),
    "</b> warnings</span>",
    "</div></header>",

    '<div class="tabs">',
    '<button class="tab-btn active" data-tab="tree">Tree</button>',
    '<button class="tab-btn" data-tab="hierarchy">Hierarchy</button>',
    '<button class="tab-btn" data-tab="notes">Notes</button>',
    '<button class="tab-btn" data-tab="index">Index</button>',
    '<button class="tab-btn" data-tab="analysis">Analysis</button>',
    "</div>",

    '<div class="toolbar">',
    '<input id="q" type="search" placeholder="Filter modules, paths, descriptions…" autocomplete="off">',
    '<button id="expand">Expand all</button><button id="collapse">Collapse</button>',
    "</div>",

    '<main id="view-tree" class="view active"><div id="tree"></div><div id="detail"></div></main>',

    '<div id="view-hierarchy" class="view">',
    '<div class="hctl">',
    '<button id="hup">▲ Up</button><button id="hroot">⌂ Root</button>',
    '<div class="hview-toggle">',
    '<button class="hview-btn active" data-view="modules">Modules</button>',
    '<button class="hview-btn" data-view="deps">Deps</button>',
    '<button class="hview-btn" data-view="calls">Calls</button>',
    '<button class="hview-btn" data-view="types">Types</button>',
    '<button class="hview-btn" data-view="inheritance">Inheritance</button>',
    "</div>",
    -- Direction and depth belong to the directed views only; `syncGraphControls`
    -- hides them in Modules/Types rather than leaving two control groups that
    -- do nothing.
    '<div class="hview-toggle" id="hdir">',
    '<button class="hdir-btn" data-dir="in" title="What depends on / calls this">← In</button>',
    '<button class="hdir-btn" data-dir="both" title="Both directions around the center">⇄ Both</button>',
    '<button class="hdir-btn active" data-dir="out" title="What this depends on / calls">Out →</button>',
    "</div>",
    '<div class="hview-toggle" id="hdepth">',
    '<button class="hdepth-btn" data-depth="1">1</button>',
    '<button class="hdepth-btn active" data-depth="2">2</button>',
    '<button class="hdepth-btn" data-depth="3">3</button>',
    '<button class="hdepth-btn" data-depth="0" title="Unbounded, still capped at 90 boxes">∞</button>',
    "</div>",
    '<div class="hview-toggle" id="hext">',
    '<button class="hext-btn" title="Also draw requires that resolve outside this map">+ external</button>',
    "</div>",
    '<button id="hzoomreset" title="Reset zoom to 100% (or press 0)">⌕ 100%</button>',
    '<span class="hzoom" id="hzoomlabel">100%</span>',
    '<button id="hexport" title="Download the current diagram as a standalone SVG">↓ SVG</button>',
    '<span class="hpath" id="hpath"></span>',
    "</div>",
    '<div id="hgraph-wrap"><div id="hgraph"><div id="hstage"></div></div></div>',
    '<div class="hlegend" id="hlegend"></div>',
    "</div>",

    '<div id="view-notes" class="view"></div>',

    '<div id="view-index" class="view">',
    '<div class="hview-toggle" id="ixtoggle">',
    '<button class="ixview-btn active" data-iview="functions">Functions</button>',
    '<button class="ixview-btn" data-iview="modules">Modules</button>',
    "</div>",
    '<div id="ixbody"></div>',
    "</div>",

    '<div id="view-analysis" class="view">',
    '<div class="hview-toggle" id="antoggle">',
    '<button class="anview-btn active" data-atool="test">Test coverage</button>',
    '<button class="anview-btn" data-atool="doc">Documentation</button>',
    '<button class="anview-btn" data-atool="deps">Dependencies</button>',
    '<button class="anview-btn" data-atool="complexity">Complexity</button>',
    "</div>",
    '<div id="anbody"></div>',
    "</div>",

    '<div id="findings"><details><summary>Drift findings (',
    tostring(#findings),
    ')</summary><div class="wrap"><table>',
    "<thead><tr><th>Severity</th><th>Check</th><th>Message</th></tr></thead><tbody>",
    table.concat(rows),
    "</tbody></table></div></details></div>",

    '<div id="ctx" role="menu"></div>',

    '<script type="application/json" id="ir">',
    payload,
    "</script>",
    '<script type="application/json" id="findings-data">',
    findings_json,
    "</script>",
    "<script>",
    JS,
    "</script>",
    "</body></html>",
  })
end

return setmetatable(M, {
  __call = function(_, ...)
    return M.render(...)
  end,
})
