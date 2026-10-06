document.querySelectorAll('.copy').forEach(function (btn) {
  btn.addEventListener('click', function () {
    var src = document.getElementById(btn.dataset.src);
    var text = src ? src.value : '';
    var label = btn.dataset.label || 'Copy';
    var done = function () {
      btn.classList.add('done');
      btn.textContent = 'Copied';
      setTimeout(function () { btn.classList.remove('done'); btn.textContent = label; }, 1800);
    };
    var fallback = function () {
      // Clipboard refused: show the text selected so it can be copied by hand.
      src.classList.add('show');
      src.removeAttribute('aria-hidden');
      src.focus();
      src.select();
      btn.textContent = 'Selected: press Copy';
    };
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, fallback);
      } else { fallback(); }
    } catch (e) { fallback(); }
  });
});
