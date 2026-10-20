/*
 * Label layout editor.
 *
 * Derived from OpenCutList by L'Air du Bois - https://github.com/lairdubois/lairdubois-opencutlist-sketchup-extension
 * (src/ladb_opencutlist/js/plugins/components/jquery.ladb.editor-label-layout.js and
 * twig/components/_editor-label-element-form.twig, at commit 1ef3e14c), Copyright (c) L'Air du Bois,
 * licensed under the GNU General Public License v3.0.
 *
 * Modified by Gautier Design Ltd, 20 October 2026: rewritten without jQuery, Twig, i18next and
 * bootstrap-select for SketchUp's HtmlDialog; element bindings rewired to HW Door Style's label
 * fields (T number, part number, customer, room, barcode...); page / printer settings and named
 * layouts added. Kept: the label canvas centred on the label, the grid of twelfths of the
 * label's short side, drag with snap to the grid, arrow-key nudge, add / duplicate / remove /
 * rotate, and the element form (field, size, anchor, colour, custom formula).
 *
 * This file is part of HW Door Style and is distributed under the GNU GPL v3.0 (see LICENSE).
 */
(function (global) {
  'use strict';

  var XMLNS = 'http://www.w3.org/2000/svg';
  var GRID_DIVISION = 12;
  var MAX_W = 520, MAX_H = 390;

  // The fields a label element can show (value code -> label in the list).
  var FIELDS = [
    ['part.number', 'T number + part number (T3  12)'],
    ['part.t', 'T number'],
    ['part.no', 'Part number'],
    ['part.t_of', 'T number + qty (T1  1 of 2)'],
    ['part.name', 'Part name'],
    ['part.dims', 'Length x width (grouped: Qty)'],
    ['part.size', 'Length x width'],
    ['part.length', 'Length'],
    ['part.width', 'Width'],
    ['part.thickness', 'Thickness'],
    ['group.material', 'Material / colour'],
    ['part.edging', 'Edging summary'],
    ['part.of', 'Qty (1 of 2)'],
    ['part.ts', 'T numbers (grouped labels)'],
    ['customer', 'Customer (SMITH JA)'],
    ['room_id', 'Room ID'],
    ['room_name', 'Room name'],
    ['customer_room', 'Customer | room ID | room'],
    ['barcode', 'Barcode (Code 128)'],
    ['text', 'Free text'],
    ['hr', 'Horizontal line'],
    ['thumbnail.shape', 'Part outline with edging (own shape)'],
    ['thumbnail.proportional.drawing', 'Part drawing with edging (OpenCutList, to scale)'],
    ['part.edge.ymin', 'Edge - long 1'], ['part.edge.ymax', 'Edge - long 2'], ['part.edge.xmin', 'Edge - short 1'], ['part.edge.xmax', 'Edge - short 2'],
    ['generated_at', 'Date'],
    ['custom', 'Custom formula (OpenCutList)']
  ];
  var SIZES = [0.5, 0.6, 0.7, 0.75, 0.8, 0.9, 1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6];
  var ANCHORS = [['start-top', 'Top left'], ['middle-top', 'Top centre'], ['end-top', 'Top right'], ['start', 'Baseline left'], ['middle', 'Baseline centre'], ['end', 'Baseline right']];

  function el(tag, attrs, parent) {
    var n = document.createElementNS(XMLNS, tag);
    Object.keys(attrs || {}).forEach(function (k) { n.setAttributeNS(null, k, attrs[k]); });
    if (parent) parent.appendChild(n);
    return n;
  }
  function h(html) { var d = document.createElement('div'); d.innerHTML = html; return d.firstElementChild; }
  function opt(list, cur) { return list.map(function (o) { var v = Array.isArray(o) ? o[0] : o, t = Array.isArray(o) ? o[1] : o; return '<option value="' + v + '"' + (String(v) === String(cur) ? ' selected' : '') + '>' + t + '</option>'; }).join(''); }

  // container: element to draw into; layout: a page layout (mm numbers, as the Labels tab uses);
  // entries: sample labels (real data); render(def, entry, index, minUnit, labelWidth) -> svg markup;
  // onChange(layout): called after every change (for the live preview).
  function LabelEditor(container, layout, entries, render, onChange) {
    this.c = container;
    this.o = JSON.parse(JSON.stringify(layout));
    this.entries = entries || [];
    this.render = render;
    this.onChange = onChange || function () {};
    this.sel = null;
    this.build();
  }

  LabelEditor.prototype.size = function () {
    var o = this.o;
    var lw = (o.page_width - o.margin_left - o.margin_right - o.spacing_v * (o.col_count - 1)) / o.col_count;
    var lh = (o.page_height - o.margin_top - o.margin_bottom - o.spacing_h * (o.row_count - 1)) / o.row_count;
    return { w: lw, h: lh, unit: Math.min(lw, lh) / GRID_DIVISION };
  };

  LabelEditor.prototype.changed = function () { this.onChange(this.o); };

  LabelEditor.prototype.build = function () {
    var that = this;
    this.c.innerHTML = '';
    var row = h('<div style="display:flex;gap:14px;align-items:flex-start;flex-wrap:wrap"></div>');
    this.c.appendChild(row);
    var left = h('<div></div>'); row.appendChild(left);
    var right = h('<div style="flex:1;min-width:260px"></div>'); row.appendChild(right);
    this.left = left; this.right = right;
    this.drawCanvas();
    this.drawPage();
  };

  // --- the label canvas (OpenCutList createSvg) -------------------------------------------
  LabelEditor.prototype.drawCanvas = function () {
    var that = this, s = this.size(), o = this.o;
    this.left.innerHTML = '';
    if (!(s.w > 0 && s.h > 0)) { this.left.textContent = 'The label size is not valid - check the page, margins and columns / rows.'; return; }
    this.left.appendChild(h('<div class="hint" style="margin:0 0 4px">Label ' + s.w.toFixed(1) + ' x ' + s.h.toFixed(1) + ' mm - drag an element, or click it and use the arrow keys. Grid = 1/12 of the short side.</div>'));
    var svg = el('svg', { focusable: 'true', tabindex: '-1', viewBox: '0 0 ' + s.w + ' ' + s.h, style: 'background:#fff;border:1px solid #ccc;outline:none' });
    if (s.w / s.h > MAX_W / MAX_H) { svg.setAttribute('width', MAX_W + 'px'); svg.setAttribute('height', (MAX_W / s.w * s.h) + 'px'); } else { svg.setAttribute('height', MAX_H + 'px'); svg.setAttribute('width', (MAX_H / s.h * s.w) + 'px'); }
    this.left.appendChild(svg);
    this.svg = svg;
    var g = el('g', { transform: 'translate(' + s.w / 2 + ' ' + s.h / 2 + ')' }, svg);
    this.g = g;
    var grid = el('g', {}, g);
    var line = function (x1, y1, x2, y2, stroke) { el('line', { x1: x1, y1: y1, x2: x2, y2: y2, stroke: stroke || '#e3e3e3', 'stroke-width': 0.08, 'stroke-dasharray': s.unit / 10 }, grid); };
    for (var y = 0; y < s.h / 2; y += s.unit) { if (y > 0) line(-s.w / 2, -y, s.w / 2, -y); line(-s.w / 2, y, s.w / 2, y, y === 0 ? '#aaa' : null); }
    for (var x = 0; x < s.w / 2; x += s.unit) { if (x > 0) line(-x, -s.h / 2, -x, s.h / 2); line(x, -s.h / 2, x, s.h / 2, x === 0 ? '#aaa' : null); }
    this.items = [];
    o.layout.forEach(function (def) { that.appendDef(def); });

    var pos = function (e) { var m = svg.getScreenCTM(); return { x: (e.clientX - m.e) / m.a, y: (e.clientY - m.f) / m.d }; };
    var dragging = false, start = null, startDef = null;
    svg.addEventListener('mousedown', function (e) {
      var it = e.target.closest ? e.target.closest('.draggable') : null;
      if (it) {
        var def = it.__def;
        that.select(def);
        var p = pos(e);
        start = { x: p.x, y: p.y }; startDef = { x: def.x, y: def.y };
        dragging = true;
        svg.focus();
      } else { that.select(null); }
    });
    svg.addEventListener('mousemove', function (e) {
      if (!dragging || !that.sel) return;
      e.preventDefault();
      var p = pos(e), def = that.sel;
      var gx = Math.round((startDef.x * s.w + p.x - start.x) / s.unit), gy = Math.round((startDef.y * s.h + p.y - start.y) / s.unit);
      def.x = Math.min(Math.max(gx * s.unit / s.w, -0.5), 0.5);
      def.y = Math.min(Math.max(gy * s.unit / s.h, -0.5), 0.5);
      that.place(def);
    });
    var stop = function () { if (dragging) { dragging = false; that.changed(); that.drawForm(); } };
    svg.addEventListener('mouseup', stop);
    svg.addEventListener('mouseleave', stop);
    svg.addEventListener('keydown', function (e) {
      if (!that.sel) return;
      var dx = 0, dy = 0;
      if (e.key === 'ArrowDown') dy = 1; else if (e.key === 'ArrowUp') dy = -1; else if (e.key === 'ArrowLeft') dx = -1; else if (e.key === 'ArrowRight') dx = 1;
      else if (e.key === 'Delete') { that.remove(that.sel); return; } else return;
      e.preventDefault();
      var def = that.sel;
      var gx = Math.round(def.x * s.w / s.unit + dx), gy = Math.round(def.y * s.h / s.unit + dy);
      def.x = Math.min(Math.max(gx * s.unit / s.w, -0.5), 0.5);
      def.y = Math.min(Math.max(gy * s.unit / s.h, -0.5), 0.5);
      that.place(def); that.changed(); that.drawForm();
    });

    var bar = h('<div style="margin:6px 0;display:flex;gap:6px;flex-wrap:wrap"></div>');
    var add = h('<button>+ Add element</button>');
    add.onclick = function () { var def = { formula: 'part.name', x: 0, y: 0, rotation: 0, size: 1, anchor: 'middle', color: '#000000' }; o.layout.push(def); that.appendDef(def); that.select(def); that.changed(); };
    var clear = h('<button>Remove all</button>');
    clear.onclick = function () { if (!clear.dataset.sure) { clear.dataset.sure = '1'; clear.textContent = 'Click again to remove all'; return; } o.layout.length = 0; that.drawCanvas(); that.changed(); };
    bar.appendChild(add); bar.appendChild(clear);
    this.left.appendChild(bar);
    this.form = h('<div></div>');
    this.left.appendChild(this.form);
    this.drawForm();
  };

  // OpenCutList appendElementDef: a draggable group with a red cross at its anchor point.
  LabelEditor.prototype.appendDef = function (def) {
    var s = this.size();
    var g = el('g', { 'class': 'draggable', style: 'cursor:move' }, this.g);
    g.__def = def;
    this.items.push(g);
    this.place(def);
    return g;
  };
  LabelEditor.prototype.groupOf = function (def) { for (var i = 0; i < this.items.length; i++) if (this.items[i].__def === def) return this.items[i]; return null; };
  LabelEditor.prototype.place = function (def) {
    var g = this.groupOf(def); if (!g) return;
    var s = this.size(), idx = this.o.layout.indexOf(def);
    g.setAttribute('transform', 'translate(' + def.x * s.w + ' ' + def.y * s.h + ')');
    var e = this.entries[0] || { kind: 'sheet', t: 'T1', number: 1, name: 'PART', length: '600 mm', width: '400 mm', thickness: '18 mm', count: 1, position: 1, edges: {}, edge_colors: {}, barcode: 'HW-ROOM-1', custom: [] };
    var content = '<g transform="rotate(' + (def.rotation || 0) + ')">' + this.render(def, e, idx, s.unit, s.w) + '</g>';
    var cross = '<line x1="' + (-s.unit / 3) + '" y1="0" x2="' + (s.unit / 3) + '" y2="0" stroke="#f00" stroke-width="0.1"/><line x1="0" y1="' + (-s.unit / 3) + '" x2="0" y2="' + (s.unit / 3) + '" stroke="#f00" stroke-width="0.1"/>';
    g.innerHTML = cross + content;
    try {
      var bb = g.lastChild.getBBox();
      var r = el('rect', { x: bb.x - 0.3, y: bb.y - 0.3, width: Math.max(bb.width + 0.6, s.unit / 2), height: Math.max(bb.height + 0.6, s.unit / 2), fill: 'rgba(0,0,0,0)', stroke: def === this.sel ? '#2a7ae2' : '#bbb', 'stroke-width': 0.12, 'stroke-dasharray': s.unit / 5, rx: 0.3 });
      g.insertBefore(r, g.firstChild);
    } catch (x) { /* not drawn yet */ }
  };
  LabelEditor.prototype.select = function (def) {
    var old = this.sel; this.sel = def;
    if (old) this.place(old);
    if (def) this.place(def);
    this.drawForm();
  };
  LabelEditor.prototype.remove = function (def) {
    var i = this.o.layout.indexOf(def); if (i < 0) return;
    this.o.layout.splice(i, 1);
    var g = this.groupOf(def); if (g) g.parentNode.removeChild(g);
    this.items = this.items.filter(function (x) { return x.__def !== def; });
    this.sel = null; this.drawForm(); this.changed();
  };

  // --- the element form (OpenCutList _editor-label-element-form.twig) -----------------------
  LabelEditor.prototype.drawForm = function () {
    var that = this, def = this.sel, f = this.form;
    if (!f) return;
    if (!def) { f.innerHTML = '<div class="hint">Click an element to change it.</div>'; return; }
    var s = this.size();
    f.innerHTML = '<div style="display:grid;grid-template-columns:90px 1fr;gap:4px 8px;align-items:center;max-width:' + MAX_W + 'px">' +
      '<span>Shows</span><select id="leF">' + opt(FIELDS, def.formula) + '</select>' +
      '<span>Size</span><select id="leS">' + opt(SIZES, def.size) + '</select>' +
      '<span>Anchor</span><select id="leA">' + opt(ANCHORS, def.anchor || 'middle') + '</select>' +
      '<span>Colour</span><input type="color" id="leC" value="' + (def.color || '#000000') + '">' +
      '<span id="leWl">Width</span><input type="number" id="leW" min="0.1" max="1" step="0.05" value="' + (def.width || (def.formula === 'barcode' ? 0.85 : 0.9)) + '" title="Fraction of the label width">' +
      '<span id="leTl">Text</span><input type="text" id="leT" value="' + String(def.text || '').replace(/"/g, '&quot;') + '">' +
      '<span id="leXl">Formula</span><textarea id="leX" rows="2" placeholder="e.g. @number + \' / \' + @batch">' + String(def.custom_formula || '').replace(/</g, '&lt;') + '</textarea>' +
      '<span>Position</span><span class="hint" style="margin:0">x ' + (def.x * s.w).toFixed(1) + ' mm, y ' + (def.y * s.h).toFixed(1) + ' mm from the centre</span>' +
      '</div><div style="margin-top:6px;display:flex;gap:6px"><button id="leDup">Duplicate</button><button id="leRL" title="Rotate left">&#8634;</button><button id="leRR" title="Rotate right">&#8635;</button><button id="leDel">Remove</button></div>';
    var q = function (id) { return document.getElementById(id); };
    var vis = function () {
      var showW = def.formula === 'barcode' || def.formula === 'hr', showT = def.formula === 'text', showX = def.formula.indexOf('custom') === 0;
      q('leW').style.display = q('leWl').style.display = showW ? '' : 'none';
      q('leT').style.display = q('leTl').style.display = showT ? '' : 'none';
      q('leX').style.display = q('leXl').style.display = showX ? '' : 'none';
    };
    vis();
    var upd = function () { that.place(def); that.changed(); };
    q('leF').onchange = function () { def.formula = this.value; vis(); upd(); };
    q('leS').onchange = function () { def.size = parseFloat(this.value); upd(); };
    q('leA').onchange = function () { def.anchor = this.value; upd(); };
    q('leC').onchange = function () { def.color = this.value; upd(); };
    q('leW').onchange = function () { def.width = parseFloat(this.value); upd(); };
    q('leT').onchange = function () { def.text = this.value; upd(); };
    q('leX').onchange = function () { def.custom_formula = this.value; upd(); };
    q('leDup').onclick = function () {
      var n = JSON.parse(JSON.stringify(def)), dx = s.unit / s.w, dy = s.unit / s.h;
      n.x += n.x < 0 ? dx : -dx; n.y += n.y < 0 ? dy : -dy;
      that.o.layout.push(n); that.appendDef(n); that.select(n); that.changed();
    };
    q('leRL').onclick = function () { def.rotation = ((def.rotation || 0) - 90) % 360; upd(); };
    q('leRR').onclick = function () { def.rotation = ((def.rotation || 0) + 90) % 360; upd(); };
    q('leDel').onclick = function () { that.remove(def); };
  };

  // --- page, columns / rows, printer (OpenCutList's label page options) --------------------
  LabelEditor.prototype.drawPage = function () {
    var that = this, o = this.o;
    var num = function (k, label, step) { return '<span>' + label + '</span><input type="number" step="' + (step || 0.5) + '" data-k="' + k + '" value="' + o[k] + '" style="width:80px">'; };
    this.right.innerHTML = '<fieldset style="margin:0"><legend>Page</legend><div style="display:grid;grid-template-columns:auto auto auto auto;gap:4px 8px;align-items:center">' +
      num('page_width', 'Width (mm)') + num('page_height', 'Height (mm)') +
      num('margin_top', 'Margin top') + num('margin_bottom', 'Margin bottom') + num('margin_left', 'Margin left') + num('margin_right', 'Margin right') +
      '</div><div class="hint">Labels print on the Zebra GK420D, one label per page, straight to the printer (the Brother prints the PDFs).</div></fieldset>';
    Array.prototype.forEach.call(this.right.querySelectorAll('[data-k]'), function (i) {
      i.onchange = function () {
        var k = i.getAttribute('data-k');
        o[k] = i.type === 'checkbox' ? i.checked : (k === 'printer' ? i.value : (k === 'col_count' || k === 'row_count' ? Math.max(1, parseInt(i.value, 10) || 1) : parseFloat(i.value) || 0));
        if (k !== 'printer' && k !== 'cutting_marks') that.drawCanvas();
        that.changed();
      };
    });
  };

  LabelEditor.prototype.layout = function () { return JSON.parse(JSON.stringify(this.o)); };

  LabelEditor.FIELDS = FIELDS;
  global.LabelEditor = LabelEditor;
})(window);
