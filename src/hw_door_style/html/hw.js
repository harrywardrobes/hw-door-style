// Shared helpers for every HW Door Style window (inlined by ui/dialog.rb).
function $(id){ return document.getElementById(id); }
function esc(s){ return String(s == null ? '' : s).replace(/[&<>"]/g, function(c){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]; }); }
// Busy bar: hwBusy({ text, done, total }) shows / moves it (total 0 = no count yet),
// hwBusy(null) hides it. Buttons can't be pressed while it shows.
function hwBusy(o){
  var el = document.getElementById('hwBusy');
  if (!o) { if (el) el.parentNode.removeChild(el); document.body.classList.remove('hwBusy'); return; }
  if (!el) { el = document.createElement('div'); el.id = 'hwBusy'; el.innerHTML = '<div class="t"><span></span><span></span></div><div class="track"><div class="fill"></div></div>'; document.body.appendChild(el); }
  document.body.classList.add('hwBusy');
  var any = !(o.total > 0);
  el.className = any ? 'any' : '';
  el.querySelector('.t span').textContent = o.text || 'Working...';
  el.querySelector('.t span:last-child').textContent = any ? '' : Math.min(o.done + 1, o.total) + ' of ' + o.total;
  el.querySelector('.fill').style.width = any ? '' : Math.round(100 * o.done / o.total) + '%';
}

// Workshop > Fix this: outline what needs filling in (HW_FOCUS from Dialog.focus_next), scroll to
// it and say what to do in a banner. Waits for the page to draw it (up to 5 s); the outline goes
// once the field is changed.
function hwFocus(f){
  if (!f) return;
  if (f.js) { try { (new Function(f.js))(); } catch(e) {} }
  var tries = 0;
  var t = setInterval(function(){
    var els = [];
    (f.sel || []).forEach(function(s){ try { Array.prototype.forEach.call(document.querySelectorAll(s), function(e){ els.push(e); }); } catch(e) {} });
    if (!els.length && ++tries < 50) return;
    clearInterval(t);
    if (f.js) { try { (new Function(f.js))(); } catch(e) {} }
    els.forEach(function(e){
      e.classList.add('hwFocus');
      var off = function(){ e.classList.remove('hwFocus'); };
      e.addEventListener('change', off); e.addEventListener('input', off);
    });
    if (els[0]) { try { els[0].scrollIntoView({ block: 'center' }); if (els[0].focus) els[0].focus(); } catch(e) {} }
    if (f.note) {
      var b = document.createElement('div');
      b.id = 'hwNote';
      b.innerHTML = '<span>' + esc(f.note) + '</span><button onclick="this.parentNode.parentNode.removeChild(this.parentNode)">OK</button>';
      var tabs = document.getElementById('hwTabs');
      if (tabs) tabs.parentNode.insertBefore(b, tabs.nextSibling); else document.body.insertBefore(b, document.body.firstChild);
    }
  }, 100);
}
window.addEventListener('load', function(){ if (typeof HW_FOCUS !== 'undefined') hwFocus(HW_FOCUS); });

// The job window's tabs: the page is swapped in place (ui/dialog.rb).
function hwTab(id){ if (document.body.classList.contains('hwBusy')) return; document.body.style.opacity = '.4'; sketchup.hwTab(id); }
