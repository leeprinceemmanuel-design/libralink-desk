/* LibraLink Desk: replaces any leftover "LibreChat" product name shown in the page
   with "LibraLink Desk". The LibreChat licence notice and credits stay in the
   repository, the footer and the project website. Injected by nginx. */
(function () {
  var FROM = /LibreChat/g;
  var TO = "LibraLink Desk";

  function fixNode(node) {
    if (node.nodeType === 3) { // text node
      if (FROM.test(node.nodeValue) && !isCredit(node)) node.nodeValue = node.nodeValue.replace(FROM, TO);
      FROM.lastIndex = 0;
      return;
    }
    if (node.nodeType !== 1 || /^(SCRIPT|STYLE|TEXTAREA|INPUT|CODE|PRE)$/.test(node.tagName)) return;
    ["placeholder", "title", "aria-label", "alt"].forEach(function (a) {
      var v = node.getAttribute && node.getAttribute(a);
      if (v && v.indexOf("LibreChat") !== -1) node.setAttribute(a, v.replace(FROM, TO));
    });
    for (var c = node.firstChild; c; c = c.nextSibling) fixNode(c);
  }

  // Keep the footer credit ("Built on LibreChat (MIT)") as it is: crediting the source is required.
  function isCredit(textNode) {
    return /Built on LibreChat/.test(textNode.nodeValue);
  }

  function run() {
    if (document.title.indexOf("LibreChat") !== -1) document.title = document.title.replace(FROM, TO);
    fixNode(document.body);
  }

  var pending = false;
  function schedule() {
    if (pending) return;
    pending = true;
    setTimeout(function () { pending = false; run(); }, 150);
  }

  document.addEventListener("DOMContentLoaded", function () {
    run();
    new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true, characterData: true });
  });
})();
