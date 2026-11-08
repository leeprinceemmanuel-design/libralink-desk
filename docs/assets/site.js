// Shared header, navigation and footer for every page, plus evidence-image handling.
(function () {
  var pages = [
    ["index.html", "Summary"],
    ["infrastructure.html", "AWS design"],
    ["system.html", "System card"],
    ["baseline.html", "Baseline"],
    ["well-architected.html", "Well-Architected"],
    ["operations.html", "Monitor · Backup · Security"],
    ["automation.html", "Automation · Incident"],
    ["results.html", "Results"],
    ["about.html", "Next · Declaration"]
  ];
  var here = location.pathname.split("/").pop() || "index.html";

  var nav = pages.map(function (p) {
    return '<a href="' + p[0] + '"' + (p[0] === here ? ' class="on" aria-current="page"' : "") + ">" + p[1] + "</a>";
  }).join("");
  var header = document.createElement("header");
  header.className = "top";
  header.innerHTML = '<div class="top-inner"><a class="brand" href="index.html"><img src="assets/logo.svg" alt="">' +
    '<span>LibraLink Desk<small>SAM10 final project</small></span></a><nav aria-label="Project pages">' + nav + "</nav></div>";
  document.body.insertBefore(header, document.body.firstChild);

  var i = pages.findIndex(function (p) { return p[0] === here; });
  var main = document.querySelector("main");
  if (main && i >= 0) {
    var pager = document.createElement("div");
    pager.className = "pager";
    pager.innerHTML = (i > 0 ? '<a href="' + pages[i - 1][0] + '">← ' + pages[i - 1][1] + "</a>" : "<span></span>") +
      (i < pages.length - 1 ? '<a href="' + pages[i + 1][0] + '">' + pages[i + 1][1] + " →</a>" : "<span></span>");
    main.appendChild(pager);
  }

  var footer = document.createElement("footer");
  footer.innerHTML = '<div class="inner">LibraLink Desk — SAM10 Systems Administration and Maintenance final project. ' +
    'Built on <a href="https://github.com/danny-avila/LibreChat">LibreChat</a> (MIT licence, by Danny Avila and contributors). ' +
    'The university, library and all data are invented. Yellow highlighted text = still to be filled in with real results.</div>';
  document.body.appendChild(footer);

  // Evidence figures: if the screenshot file is not there yet, show what to capture instead.
  document.querySelectorAll("figure.ev img").forEach(function (img) {
    function missing() { img.closest("figure").classList.add("missing"); }
    if (img.complete && img.naturalWidth === 0) missing();
    img.addEventListener("error", missing);
  });
})();
