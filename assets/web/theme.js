(function (root) {
  'use strict';
  // Accent comes from the app's canonical tokens, which also use blue regardless
  // of the legacy saved seed. Theme mode alone follows the active host setting.
  function apply(mode, documentRef) {
    const target = (documentRef || root.document).documentElement;
    if (mode === 'light' || mode === 'dark') target.setAttribute('data-theme', mode);
    else target.removeAttribute('data-theme');
  }
  root.CloudPocketTheme = { apply };
  if (typeof module !== 'undefined') module.exports = { apply };
})(typeof window === 'undefined' ? globalThis : window);
