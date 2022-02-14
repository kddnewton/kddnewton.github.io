document.querySelectorAll("h1[id], h2[id], h3[id], h4[id]").forEach((heading) => {
  const anchor = document.createElement("a");

  anchor.className = "link";
  anchor.setAttribute("href", "#" + heading.id);
  anchor.setAttribute("aria-label", heading.id);
  anchor.innerHTML = "🔗";

  heading.prepend(anchor);
});
