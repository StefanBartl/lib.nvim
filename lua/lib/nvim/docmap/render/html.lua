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
  --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
}
@media (prefers-color-scheme:dark){
  :root{
    --bg:#16171a; --panel:#1d1f23; --ink:#e6e6e3; --muted:#9a9a95; --line:#2e3136;
    --accent:#7aa9dd; --accent-soft:#22303f;
    --error:#f2837b; --warn:#e0b060; --info:#a8a8a3;
    --mod:#7aa9dd; --ns:#9a9a95; --file:#8fbf8f;
  }
}
:root[data-theme="light"]{
  --bg:#fbfbfa; --panel:#fff; --ink:#1a1a19; --muted:#6b6b68; --line:#e4e4e1;
  --accent:#3b6ea8; --accent-soft:#eaf1f9;
  --error:#b3261e; --warn:#8a5a00; --info:#4a4a48;
  --mod:#3b6ea8; --ns:#7a7a76; --file:#5c8a5c;
}
:root[data-theme="dark"]{
  --bg:#16171a; --panel:#1d1f23; --ink:#e6e6e3; --muted:#9a9a95; --line:#2e3136;
  --accent:#7aa9dd; --accent-soft:#22303f;
  --error:#f2837b; --warn:#e0b060; --info:#a8a8a3;
  --mod:#7aa9dd; --ns:#9a9a95; --file:#8fbf8f;
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
#view-hierarchy{padding:16px 24px 60px}
.hctl{display:flex;gap:8px;align-items:center;margin-bottom:14px;flex-wrap:wrap}
.hctl .hpath{font-family:var(--mono);font-size:12.5px;color:var(--muted);word-break:break-all}
.hctl button{padding:4px 9px;font-size:12px}
#hgraph-wrap{overflow:auto;border:1px solid var(--line);border-radius:8px;background:var(--panel)}
#hgraph{position:relative}
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
.hmsg{color:var(--muted);font-size:13px;padding:20px;text-align:center}
.htrunc{color:var(--warn);font-size:12px;margin-top:8px}
]]

local JS = [[
(function(){
  var IR = JSON.parse(document.getElementById("ir").textContent);
  var FIND = JSON.parse(document.getElementById("findings-data").textContent);
  var byId = {}; IR.nodes.forEach(function(n){ byId[n.id] = n; });

  var findByNode = {};
  FIND.forEach(function(f){ if(!f.node) return;
    (findByNode[f.node] = findByNode[f.node] || []).push(f); });

  var repo = IR.meta.repo_url, branch = IR.meta.branch || "main";
  function srcUrl(p){ return repo ? repo + "/blob/" + branch + "/" + p : null; }

  var treeEl = document.getElementById("tree");
  var detailEl = document.getElementById("detail");
  var selected = null;

  function badges(n){
    var b = [];
    if(n.readme) b.push('<span class="bd rd">readme</span>');
    if(n.types && n.types.length) b.push('<span class="bd">types</span>');
    var f = findByNode[n.id] || [];
    if(f.some(function(x){return x.severity==="error";})) b.push('<span class="bd" style="color:var(--error);border-color:var(--error)">drift</span>');
    return b.length ? '<span class="badges">'+b.join("")+'</span>' : "";
  }

  function renderNode(n){
    var kids = (n.children||[]).map(function(id){ return byId[id]; }).filter(Boolean);
    var hasKids = kids.length > 0;
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
      box.appendChild(kidsEl);
      row.querySelector(".tw").addEventListener("click", function(ev){
        ev.stopPropagation();
        kidsEl.classList.toggle("hide");
        this.textContent = kidsEl.classList.contains("hide") ? "▸" : "▾";
      });
    }
    row.addEventListener("click", function(){ select(n.id); });
    return box;
  }

  function esc(s){ return (s||"").replace(/[&<>"]/g, function(c){
    return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]; }); }

  function select(id){
    var n = byId[id]; if(!n) return;
    if(selected) { var p = treeEl.querySelector('.row[data-id="'+CSS.escape(selected)+'"]');
      if(p) p.classList.remove("sel"); }
    selected = id;
    var cur = treeEl.querySelector('.row[data-id="'+CSS.escape(id)+'"]');
    if(cur) cur.classList.add("sel");
    if(location.hash.slice(1) !== id) history.replaceState(null,"","#"+id);

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
      links.push('<a href="#" id="hlink">Hierarchy ↳</a>');
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

    var hlink = document.getElementById("hlink");
    if(hlink){
      hlink.addEventListener("click", function(ev){
        ev.preventDefault();
        activateTab("hierarchy");
        drawHierarchy(n.id);
      });
    }
  }

  // Artifact lives in out_dir; repo-relative paths need to climb back out.
  function rel(p){ return (IR.meta.out_depth ? "../".repeat(IR.meta.out_depth) : "") + p; }

  treeEl.appendChild(renderNode(byId[IR.root]));

  var q = document.getElementById("q");
  q.addEventListener("input", function(){
    var v = this.value.toLowerCase().trim();
    treeEl.querySelectorAll(".row").forEach(function(r){
      var n = byId[r.dataset.id];
      var hit = !v || (n.name+" "+(n.module||"")+" "+(n.summary||"")).toLowerCase().indexOf(v) >= 0;
      r.style.display = hit ? "" : "none";
    });
    if(v) treeEl.querySelectorAll(".kids").forEach(function(k){ k.classList.remove("hide"); });
  });

  document.getElementById("expand").addEventListener("click", function(){
    treeEl.querySelectorAll(".kids").forEach(function(k){ k.classList.remove("hide"); });
    treeEl.querySelectorAll(".tw").forEach(function(t){ if(t.textContent) t.textContent = "▾"; });
  });
  document.getElementById("collapse").addEventListener("click", function(){
    treeEl.querySelectorAll(".kids").forEach(function(k, i){ if(i) k.classList.add("hide"); });
    treeEl.querySelectorAll(".row").forEach(function(r){
      var n = byId[r.dataset.id];
      if(n && n.depth >= 1){ var t = r.querySelector(".tw"); if(t && t.textContent) t.textContent = "▸"; }
    });
  });

  window.addEventListener("hashchange", function(){
    var id = decodeURIComponent(location.hash.slice(1)); if(byId[id]) select(id);
  });

  // ---------------------------------------------------------------- tabs
  function activateTab(name){
    document.querySelectorAll(".tab-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.tab === name);
    });
    document.getElementById("view-tree").classList.toggle("active", name === "tree");
    document.getElementById("view-hierarchy").classList.toggle("active", name === "hierarchy");
    if(name === "hierarchy" && !hgraph.childNodes.length) drawHierarchy();
  }
  document.querySelectorAll(".tab-btn").forEach(function(b){
    b.addEventListener("click", function(){ activateTab(b.dataset.tab); });
  });

  // ------------------------------------------------------- hierarchy view
  // Node positions are computed analytically from IR data (layer = depth
  // from the centered node, position = index within the layer), not measured
  // off the DOM. That sidesteps the usual "a box inside display:none has zero
  // size" problem entirely — drawHierarchy() produces correct absolute pixel
  // coordinates whether or not the pane is currently visible, so there is no
  // separate re-layout-on-show step to get right.
  var hgraphWrap = document.getElementById("hgraph-wrap");
  var hgraph = document.getElementById("hgraph");
  var hpathEl = document.getElementById("hpath");
  var hcenter = null;
  var MAX_HNODES = 90;
  var BOX_W = 168, BOX_H = 52, GAP_X = 16, GAP_Y = 44, PAD = 20;

  function edgePath(a, b){
    var x1 = a.x + BOX_W/2, y1 = a.y + BOX_H;
    var x2 = b.x + BOX_W/2, y2 = b.y;
    var midY = (y1 + y2) / 2;
    return "M" + x1 + "," + y1 + " C" + x1 + "," + midY + " " + x2 + "," + midY + " " + x2 + "," + y2;
  }

  function drawHierarchy(centerId){
    hcenter = (centerId && byId[centerId]) ? centerId : (hcenter && byId[hcenter] ? hcenter : IR.root);
    var center = byId[hcenter];
    hpathEl.textContent = center.module || center.path;

    hgraph.innerHTML = "";

    // BFS from the centered node, layered by depth-from-center. Files count
    // the same as modules/namespaces here — an earlier version excluded them
    // as "just noise", which looked right at the whole-map scope but was
    // wrong in practice: centering on a module implemented as a handful of
    // flat files (no further module directories) then drew almost nothing.
    // MAX_HNODES is what actually bounds noise at any scope, so there is no
    // need for a second, cruder filter on top of it.
    var layers = [];
    var included = {};
    var queue = [ { id: hcenter, d: 0 } ];
    var count = 0;
    var truncated = false;
    while(queue.length){
      var item = queue.shift();
      var id = item.id, d = item.d;
      if(included[id] !== undefined) continue;
      if(count >= MAX_HNODES){ truncated = true; break; }
      var node = byId[id];
      if(!node) continue;
      included[id] = d;
      count++;
      layers[d] = layers[d] || [];
      layers[d].push(id);
      (node.children || []).forEach(function(c){
        if(byId[c]) queue.push({ id: c, d: d + 1 });
      });
    }

    if(count === 0){
      hgraph.innerHTML = '<p class="hmsg">Nothing to draw here.</p>';
      return;
    }

    var maxRowWidth = 0;
    layers.forEach(function(layer){
      if(!layer) return;
      maxRowWidth = Math.max(maxRowWidth, layer.length * BOX_W + (layer.length - 1) * GAP_X);
    });

    var positions = {};
    var frag = document.createDocumentFragment();
    layers.forEach(function(layer, d){
      if(!layer) return;
      var rowWidth = layer.length * BOX_W + (layer.length - 1) * GAP_X;
      var startX = PAD + (maxRowWidth - rowWidth) / 2;
      layer.forEach(function(id, i){
        var x = startX + i * (BOX_W + GAP_X);
        var y = PAD + d * (BOX_H + GAP_Y);
        positions[id] = { x: x, y: y };
        var n = byId[id];
        var box = document.createElement("div");
        box.className = "hnode k-" + n.kind;
        box.style.left = x + "px";
        box.style.top = y + "px";
        box.style.width = BOX_W + "px";
        box.title = n.summary || n.name;
        box.innerHTML = '<div class="hnm">' + esc(n.name) + '</div>' +
          (n.summary ? '<div class="hsm">' + esc(n.summary) + '</div>' : '');
        box.addEventListener("click", function(){ activateTab("tree"); select(id); });
        box.addEventListener("dblclick", function(ev){ ev.stopPropagation(); drawHierarchy(id); });
        frag.appendChild(box);
      });
    });

    var totalW = maxRowWidth + PAD * 2;
    var totalH = PAD * 2 + layers.length * BOX_H + Math.max(0, layers.length - 1) * GAP_Y;

    var svgNS = "http://www.w3.org/2000/svg";
    var svg = document.createElementNS(svgNS, "svg");
    svg.id = "hsvg";
    svg.setAttribute("width", totalW);
    svg.setAttribute("height", totalH);

    Object.keys(included).forEach(function(id){
      (byId[id].children || []).forEach(function(c){
        if(positions[id] && positions[c]){
          var p = document.createElementNS(svgNS, "path");
          p.setAttribute("d", edgePath(positions[id], positions[c]));
          p.setAttribute("class", "hedge");
          svg.appendChild(p);
        }
      });
    });

    // Type-reference edges from LuaLS enrichment (empty array when it didn't
    // run). Only drawn when both endpoints are in the currently laid-out
    // subtree — a field can reference a class anywhere in the whole map, and
    // pulling in out-of-view targets would break the "scoped to one subtree"
    // point of centering on a node at all.
    (IR.edges || []).forEach(function(e){
      if(e.from !== e.to && positions[e.from] && positions[e.to]){
        var p = document.createElementNS(svgNS, "path");
        p.setAttribute("d", edgePath(positions[e.from], positions[e.to]));
        p.setAttribute("class", "hedge hedge-type");
        var title = document.createElementNS(svgNS, "title");
        title.textContent = "." + e.via;
        p.appendChild(title);
        svg.appendChild(p);
      }
    });

    hgraph.style.width = totalW + "px";
    hgraph.style.height = totalH + "px";
    hgraph.appendChild(svg);
    hgraph.appendChild(frag);

    // Rows are centered on the widest layer, so the root box can sit
    // thousands of pixels from the left edge on a wide map — without this,
    // opening the tab scrolls to (0,0) and shows an arbitrary fragment of
    // whichever layer is widest, not the node that was actually centered on.
    var centerPos = positions[hcenter];
    if(centerPos){
      hgraphWrap.scrollLeft = Math.max(0, centerPos.x + BOX_W / 2 - hgraphWrap.clientWidth / 2);
      hgraphWrap.scrollTop = 0;
    }

    if(truncated){
      var note = document.createElement("div");
      note.className = "htrunc";
      note.textContent = "Showing the first " + MAX_HNODES + " nodes — double-click a box to re-center on a smaller subtree.";
      hgraphWrap.parentNode.insertBefore(note, hgraphWrap.nextSibling);
    }
    var existingNote = hgraphWrap.parentNode.querySelector(".htrunc");
    if(existingNote && !truncated) existingNote.remove();
  }

  document.getElementById("hup").addEventListener("click", function(){
    var center = byId[hcenter || IR.root];
    if(center && center.parent) drawHierarchy(center.parent);
  });
  document.getElementById("hroot").addEventListener("click", function(){
    drawHierarchy(IR.root);
  });

  var initial = decodeURIComponent(location.hash.slice(1));
  select(byId[initial] ? initial : IR.root);
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

  local payload = json.encode({ meta = meta, root = ir.root, nodes = nodes, edges = ir.edges or {} })
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
    rows[#rows + 1] = ([[<tr><td><span class="sev %s">%s</span></td><td class="msg">%s</td><td class="msg">%s</td></tr>]])
      :format(f.severity, f.severity, esc(f.check), esc(f.message))
  end

  return table.concat({
    "<!doctype html>",
    '<html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
    "<title>", esc(ir.meta.title), " — module map</title>",
    "<style>", CSS, "</style></head><body>",

    "<header><h1>", esc(ir.meta.title), '<span class="sub">module map</span></h1>',
    '<div class="stats">',
    "<span><b>", tostring(c.module or 0), "</b> modules</span>",
    "<span><b>", tostring(c.namespace or 0), "</b> namespaces</span>",
    "<span><b>", tostring(c.file or 0), "</b> files</span>",
    '<span><b class="sev error">', tostring(t.error), "</b> errors</span>",
    '<span><b class="sev warn">', tostring(t.warn), "</b> warnings</span>",
    "</div></header>",

    '<div class="tabs">',
    '<button class="tab-btn active" data-tab="tree">Tree</button>',
    '<button class="tab-btn" data-tab="hierarchy">Hierarchy</button>',
    "</div>",

    '<div class="toolbar">',
    '<input id="q" type="search" placeholder="Filter modules, paths, descriptions…" autocomplete="off">',
    '<button id="expand">Expand all</button><button id="collapse">Collapse</button>',
    "</div>",

    '<main id="view-tree" class="view active"><div id="tree"></div><div id="detail"></div></main>',

    '<div id="view-hierarchy" class="view">',
    '<div class="hctl">',
    '<button id="hup">▲ Up</button><button id="hroot">⌂ Root</button>',
    '<span class="hpath" id="hpath"></span>',
    "</div>",
    '<div id="hgraph-wrap"><div id="hgraph"></div></div>',
    "</div>",

    '<div id="findings"><details><summary>Drift findings (',
    tostring(#findings), ")</summary><div class=\"wrap\"><table>",
    "<thead><tr><th>Severity</th><th>Check</th><th>Message</th></tr></thead><tbody>",
    table.concat(rows),
    "</tbody></table></div></details></div>",

    '<script type="application/json" id="ir">', payload, "</script>",
    '<script type="application/json" id="findings-data">', findings_json, "</script>",
    "<script>", JS, "</script>",
    "</body></html>",
  })
end

return setmetatable(M, {
  __call = function(_, ...)
    return M.render(...)
  end,
})
