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
