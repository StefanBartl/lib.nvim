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
.bd.dep{color:var(--error);border-color:var(--error)}
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
.hview-toggle{display:flex;gap:0;border:1px solid var(--line);border-radius:7px;overflow:hidden}
.hview-toggle button{border:none;border-radius:0;padding:4px 10px;font-size:12px}
.hview-toggle button+button{border-left:1px solid var(--line)}
.hview-toggle button.active{background:var(--accent-soft);color:var(--accent);font-weight:600}
.hnode.t-class .hnm{color:var(--mod)}
.hnode.t-alias .hnm{color:var(--ns)}
.hnode .hkind{font-size:9px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin-top:1px}
#findings tbody tr[data-node]{cursor:pointer}
#findings tbody tr[data-node]:hover{background:var(--accent-soft)}
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
  //     center: <hierarchy centered node>, view: "modules"|"types" }
  // navigate(patch) is the single entry point every discrete click handler
  // calls; it merges the patch into current state, updates the DOM, and
  // pushes a real history entry so the browser Back/Forward buttons step
  // through actual states instead of only reacting to a directly-edited
  // hash. Live preview while typing in the Hierarchy search box does not go
  // through navigate() at all — see the "input" listener below for why
  // going through history.replaceState there was a real bug, not just an
  // unnecessary one.
  // =====================================================================
  var state = { tab: "tree", id: null, center: null, view: "modules" };
  // Tracks only the hash of the last *pushed* entry — deliberately never
  // touched by a replace. Search-as-you-type replaces the current entry on
  // every keystroke; without this separation, typing to a match and then
  // pressing Enter to commit it would compute the same resulting hash the
  // last replace already wrote, and a single "skip if hash unchanged" guard
  // would then suppress the deliberate push entirely — Enter would silently
  // do nothing. Keeping the two trackers apart means a push always executes
  // unless the *previous push* (not the previous replace) had that hash.
  var lastPushedHash = null;

  function serializeState(s){
    var parts = ["tab=" + encodeURIComponent(s.tab)];
    if(s.tab === "tree"){
      if(s.id) parts.push("id=" + encodeURIComponent(s.id));
    } else {
      if(s.center) parts.push("center=" + encodeURIComponent(s.center));
      parts.push("view=" + encodeURIComponent(s.view || "modules"));
    }
    return "#" + parts.join("&");
  }

  function parseState(hash){
    var s = { tab: "tree", id: null, center: null, view: "modules" };
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

    if(s.tab === "tree" && s.id && byId[s.id]) selectRow(s.id);
    if(s.tab === "hierarchy") drawHierarchy(s.center || IR.root, s.view || "modules");

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
        h.push('<div class="fn">');
        var badges = [];
        if(fn.deprecated !== undefined) badges.push('<span class="bd dep">deprecated</span>');
        if(fn.async) badges.push('<span class="bd">async</span>');
        if(fn.nodiscard) badges.push('<span class="bd">nodiscard</span>');
        if(fn.since) badges.push('<span class="bd">since '+esc(fn.since)+'</span>');
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
        h.push('</div>');
      });
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
        navigate({ tab: "hierarchy", center: n.id });
      });
    }

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

  // BFS over node.children from `startId`. Files count the same as modules/
  // namespaces — an earlier version excluded them as "just noise", which was
  // wrong in practice: centering on a module implemented as flat files with
  // no further subdirectories then drew almost nothing. MAX_HNODES already
  // bounds noise at any scope.
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
    return { layers: layers, included: included, count: count, truncated: truncated };
  }

  // BFS over ir.edges' from_class/to_class, seeded from the centered node's
  // own types_detail. A field can reference a class owned by any node in the
  // whole map, which is exactly the point of this view — unlike the Modules
  // view, edges are not required to stay within the laid-out subtree, they
  // define it.
  function layoutTypes(startId){
    var center = byId[startId];
    var seeds = (center.types_detail || []).map(function(t){ return t.name; });
    if(seeds.length === 0) return { layers: [], included: {}, count: 0, truncated: false };

    var adj = {};
    (IR.edges || []).forEach(function(e){
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
    return { layers: layers, included: included, count: count, truncated: truncated, adj: adj };
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

  function drawHierarchy(centerId, view){
    view = view === "types" ? "types" : "modules";
    hcenter = (centerId && byId[centerId]) ? centerId : (hcenter && byId[hcenter] ? hcenter : IR.root);
    var center = byId[hcenter];

    document.querySelectorAll(".hview-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.view === view);
    });

    hgraph.innerHTML = "";
    var oldNote = hgraphWrap.parentNode.querySelector(".htrunc");
    if(oldNote) oldNote.remove();

    var built = view === "types" ? layoutTypes(hcenter) : layoutModules(hcenter);

    if(built.count === 0){
      hpathEl.textContent = center.module || center.path;
      if(view === "types"){
        hgraph.innerHTML = IR.edges && IR.edges.length
          ? '<p class="hmsg">'+esc(center.name)+' has no <code>@class</code>/<code>@alias</code> of its own — pick a module with type definitions, or switch back to Modules.</p>'
          : '<p class="hmsg">No type data in this map — regenerate with <code>:LibMap full</code> (or <code>--full</code>) to include lua-language-server class/alias detail.</p>';
      } else {
        hgraph.innerHTML = '<p class="hmsg">Nothing to draw here.</p>';
      }
      return;
    }

    hpathEl.textContent = (center.module || center.path) + (view === "types" ? " · types" : "");

    var laid = layerPositions(built.layers);
    var positions = laid.positions;
    var frag = document.createDocumentFragment();

    if(view === "modules"){
      Object.keys(positions).forEach(function(id){
        var pos = positions[id], n = byId[id];
        var box = document.createElement("div");
        box.className = "hnode k-" + n.kind;
        box.style.left = pos.x + "px"; box.style.top = pos.y + "px"; box.style.width = BOX_W + "px";
        box.title = n.summary || n.name;
        box.innerHTML = '<div class="hnm">' + esc(n.name) + '</div>' +
          (n.summary ? '<div class="hsm">' + esc(n.summary) + '</div>' : '');
        box.addEventListener("click", function(){ navigate({ tab: "tree", id: id }); });
        box.addEventListener("dblclick", function(ev){ ev.stopPropagation(); navigate({ center: id }); });
        frag.appendChild(box);
      });
    } else {
      Object.keys(positions).forEach(function(name){
        var pos = positions[name], cls = classByName[name];
        var box = document.createElement("div");
        box.className = "hnode t-" + cls.info.kind;
        box.style.left = pos.x + "px"; box.style.top = pos.y + "px"; box.style.width = BOX_W + "px";
        box.title = cls.info.desc || name;
        box.innerHTML = '<div class="hnm">' + esc(name) + '</div>' +
          '<div class="hkind">' + cls.info.kind + '</div>';
        box.addEventListener("click", function(){ navigate({ tab: "tree", id: cls.nodeId }); });
        box.addEventListener("dblclick", function(ev){ ev.stopPropagation(); navigate({ center: cls.nodeId }); });
        frag.appendChild(box);
      });
    }

    var totalW = laid.maxRowWidth + PAD * 2;
    var totalH = PAD * 2 + built.layers.length * BOX_H + Math.max(0, built.layers.length - 1) * GAP_Y;

    var svgNS = "http://www.w3.org/2000/svg";
    var svg = document.createElementNS(svgNS, "svg");
    svg.id = "hsvg";
    svg.setAttribute("width", totalW);
    svg.setAttribute("height", totalH);

    if(view === "modules"){
      Object.keys(built.included).forEach(function(id){
        (byId[id].children || []).forEach(function(c){
          if(positions[id] && positions[c]){
            var p = document.createElementNS(svgNS, "path");
            p.setAttribute("d", edgePath(positions[id], positions[c]));
            p.setAttribute("class", "hedge");
            svg.appendChild(p);
          }
        });
      });
      // Type-reference edges layered on top (dashed), node-granularity,
      // self-loops skipped — only meaningful when both endpoints are
      // laid-out nodes; a field can reference a class anywhere in the whole
      // map, and pulling in out-of-view targets would break "scoped to one
      // subtree".
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
    } else {
      Object.keys(built.included).forEach(function(name){
        (built.adj[name] || []).forEach(function(e){
          if(positions[name] && positions[e.to_class]){
            var p = document.createElementNS(svgNS, "path");
            p.setAttribute("d", edgePath(positions[name], positions[e.to_class]));
            p.setAttribute("class", "hedge hedge-type");
            var title = document.createElementNS(svgNS, "title");
            title.textContent = "." + e.via;
            p.appendChild(title);
            svg.appendChild(p);
          }
        });
      });
    }

    hgraph.style.width = totalW + "px";
    hgraph.style.height = totalH + "px";
    hgraph.appendChild(svg);
    hgraph.appendChild(frag);

    // Rows are centered on the widest layer, so the centered box can sit
    // thousands of pixels from the left edge on a wide map — without this,
    // opening the tab scrolls to (0,0) and shows an arbitrary fragment of
    // whichever layer is widest, not the node/class actually centered on.
    var selfPos = view === "modules" ? positions[hcenter] : null;
    if(selfPos){
      hgraphWrap.scrollLeft = Math.max(0, selfPos.x + BOX_W / 2 - hgraphWrap.clientWidth / 2);
      hgraphWrap.scrollTop = 0;
    } else {
      // Types view centers on a set of seed classes, not a single box —
      // scroll to the first seed instead of (0,0).
      var firstLayer = built.layers[0];
      var firstSeedKey = firstLayer ? firstLayer[0] : null;
      var firstSeedPos = firstSeedKey ? positions[firstSeedKey] : null;
      if(firstSeedPos){
        hgraphWrap.scrollLeft = Math.max(0, firstSeedPos.x + BOX_W / 2 - hgraphWrap.clientWidth / 2);
      }
      hgraphWrap.scrollTop = 0;
    }

    if(built.truncated){
      var note = document.createElement("div");
      note.className = "htrunc";
      note.textContent = "Showing the first " + MAX_HNODES + " nodes — double-click a box to re-center on a smaller subtree.";
      hgraphWrap.parentNode.insertBefore(note, hgraphWrap.nextSibling);
    }
  }

  document.getElementById("hup").addEventListener("click", function(){
    var center = byId[hcenter || IR.root];
    if(center && center.parent) navigate({ center: center.parent });
  });
  document.getElementById("hroot").addEventListener("click", function(){
    navigate({ center: IR.root });
  });
  document.querySelectorAll(".hview-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ view: b.dataset.view }); });
  });

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
      var n = byId[r.dataset.id];
      var hit = !v || (n.name+" "+(n.module||"")+" "+(n.summary||"")).toLowerCase().indexOf(v) >= 0;
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
    -- data-node drives the click-to-select wiring in JS. Left off entirely
    -- (rather than set to an empty string) when the finding has no node, or
    -- points at something that isn't a real IR node id (config.lua's
    -- aggregator check reports against a synthetic "lua/lib/@types" path
    -- that was never a scanned node) — the click handler only wires up rows
    -- that actually carry the attribute, so an unresolvable target silently
    -- stays inert instead of being a dead click.
    local node_attr = f.node and (' data-node="%s"'):format(esc(f.node)) or ""
    rows[#rows + 1] = ([[<tr%s><td><span class="sev %s">%s</span></td><td class="msg">%s</td><td class="msg">%s</td></tr>]])
      :format(node_attr, f.severity, f.severity, esc(f.check), esc(f.message))
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
    '<div class="hview-toggle">',
    '<button class="hview-btn active" data-view="modules">Modules</button>',
    '<button class="hview-btn" data-view="types">Types</button>',
    "</div>",
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
