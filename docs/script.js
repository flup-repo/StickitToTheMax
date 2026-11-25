(() => {
  const PALETTES = {
    yellow: { body: "#FFF2AD", head: "#F7E073", border: "#CBB44E", swatch: "#F5D140" },
    blue:   { body: "#C7E6FF", head: "#9ECFFA", border: "#76A9D6", swatch: "#59ABF5" },
    green:  { body: "#CCF5CC", head: "#9EE3A3", border: "#76BD7B", swatch: "#5CC770" },
    pink:   { body: "#FFD4E0", head: "#FAB0C7", border: "#D1859D", swatch: "#F27DA3" },
    purple: { body: "#E3D6FF", head: "#C4B0F7", border: "#9A85CF", swatch: "#A180F0" },
    orange: { body: "#FFDEB8", head: "#FABF80", border: "#CF9457", swatch: "#F59940" }
  };
  const COLOR_ORDER = Object.keys(PALETTES);

  const canvas = document.getElementById("wallpaper-canvas");
  const mockWindow = document.getElementById("mock-app-window");
  let zCounter = 10;

  const INITIAL_NOTES = [
    { title: "Personal", body: "Hobbies are best!\n• Weekend hike\n• Read 20 pages", color: "yellow", x: 56, y: 42, w: 230, h: 175, done: false },
    { title: "Work", body: "Ship v0.2 release\n• Review PRs\n• Prep demo", color: "blue", x: 320, y: 58, w: 245, h: 185, done: false },
    { title: "Errands", body: "Buy coffee beans\nPick up dry cleaning", color: "green", x: 605, y: 120, w: 220, h: 160, done: true }
  ];

  function applyPalette(el, colorKey) {
    const p = PALETTES[colorKey] || PALETTES.yellow;
    el.dataset.color = colorKey;
    el.style.setProperty("--s-body", p.body);
    el.style.setProperty("--s-head", p.head);
    el.style.setProperty("--s-border", p.border);
    el.style.setProperty("--s-swatch", p.swatch);
  }

  function clampPosition(x, y, w, h) {
    const rect = canvas.getBoundingClientRect();
    const maxX = Math.max(8, rect.width - w - 8);
    const maxY = Math.max(8, rect.height - h - 8);
    return {
      x: Math.min(Math.max(8, x), maxX),
      y: Math.min(Math.max(8, y), maxY)
    };
  }

  function createSticky({ title, body, color, x, y, w = 230, h = 175, done = false }) {
    const el = document.createElement("div");
    el.className = "sticky" + (done ? " done" : "");
    applyPalette(el, color);

    const pos = clampPosition(x, y, w, h);
    el.style.left = `${pos.x}px`;
    el.style.top = `${pos.y}px`;
    el.style.width = `${w}px`;
    el.style.height = `${h}px`;
    el.style.zIndex = String(++zCounter);

    el.innerHTML = `
      <div class="sticky-grab" title="Drag to move"><span class="sticky-grab-pill"></span></div>
      <div class="sticky-header">
        <button type="button" class="sticky-btn sticky-done-btn" title="Mark as done">${done ? "●" : "✓"}</button>
        <input type="text" class="sticky-title" value="${title.replace(/"/g, "&quot;")}" placeholder="Title..." />
        <button type="button" class="sticky-color-btn" title="Cycle color"></button>
        <button type="button" class="sticky-btn sticky-add-btn" title="New sticky">+</button>
        <button type="button" class="sticky-btn sticky-del-btn" title="Delete sticky">&times;</button>
      </div>
      <textarea class="sticky-body" placeholder="Write a to-do...">${body}</textarea>
      <div class="sticky-resize" title="Drag to resize"></div>
    `;

    el.addEventListener("pointerdown", () => {
      el.style.zIndex = String(++zCounter);
    });

    // Done toggle
    const doneBtn = el.querySelector(".sticky-done-btn");
    doneBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      const isNowDone = el.classList.toggle("done");
      doneBtn.textContent = isNowDone ? "●" : "✓";
    });

    // Cycle color
    el.querySelector(".sticky-color-btn").addEventListener("click", (e) => {
      e.stopPropagation();
      const idx = COLOR_ORDER.indexOf(el.dataset.color);
      const next = COLOR_ORDER[(idx + 1) % COLOR_ORDER.length];
      applyPalette(el, next);
    });

    // Duplicate category nearby
    el.querySelector(".sticky-add-btn").addEventListener("click", (e) => {
      e.stopPropagation();
      const titleVal = el.querySelector(".sticky-title").value;
      createSticky({
        title: titleVal,
        body: "",
        color: el.dataset.color,
        x: el.offsetLeft + 26,
        y: el.offsetTop + 26
      });
    });

    // Delete
    el.querySelector(".sticky-del-btn").addEventListener("click", (e) => {
      e.stopPropagation();
      el.remove();
    });

    // Dragging via top grab bar or header background
    function startDrag(e) {
      if (e.target.closest("button, input")) return;
      e.preventDefault();
      const startX = e.clientX;
      const startY = e.clientY;
      const origX = el.offsetLeft;
      const origY = el.offsetTop;

      function onMove(ev) {
        const next = clampPosition(
          origX + (ev.clientX - startX),
          origY + (ev.clientY - startY),
          el.offsetWidth,
          el.offsetHeight
        );
        el.style.left = `${next.x}px`;
        el.style.top = `${next.y}px`;
      }

      function onUp() {
        window.removeEventListener("pointermove", onMove);
        window.removeEventListener("pointerup", onUp);
      }

      window.addEventListener("pointermove", onMove);
      window.addEventListener("pointerup", onUp);
    }

    el.querySelector(".sticky-grab").addEventListener("pointerdown", startDrag);
    el.querySelector(".sticky-header").addEventListener("pointerdown", startDrag);

    // Resizing via bottom-right grip
    el.querySelector(".sticky-resize").addEventListener("pointerdown", (e) => {
      e.preventDefault();
      e.stopPropagation();
      const startX = e.clientX;
      const startY = e.clientY;
      const origW = el.offsetWidth;
      const origH = el.offsetHeight;
      const canvasRect = canvas.getBoundingClientRect();

      function onMove(ev) {
        const maxW = canvasRect.width - el.offsetLeft - 8;
        const maxH = canvasRect.height - el.offsetTop - 8;
        const w = Math.min(Math.max(175, origW + (ev.clientX - startX)), maxW);
        const h = Math.min(Math.max(130, origH + (ev.clientY - startY)), maxH);
        el.style.width = `${w}px`;
        el.style.height = `${h}px`;
      }

      function onUp() {
        window.removeEventListener("pointermove", onMove);
        window.removeEventListener("pointerup", onUp);
      }

      window.addEventListener("pointermove", onMove);
      window.addEventListener("pointerup", onUp);
    });

    canvas.appendChild(el);
  }

  function resetDemo() {
    canvas.querySelectorAll(".sticky").forEach((n) => n.remove());
    mockWindow.classList.add("hidden");
    const width = canvas.clientWidth;
    INITIAL_NOTES.forEach((note, i) => {
      const scaledX = width < 700 ? 18 + i * 28 : note.x;
      const scaledY = width < 700 ? 20 + i * 70 : note.y;
      createSticky({ ...note, x: scaledX, y: scaledY });
    });
  }

  document.getElementById("demo-add-work").addEventListener("click", () => {
    createSticky({ title: "Work", body: "• New work task", color: "blue", x: 120, y: 70 });
  });

  document.getElementById("demo-add-personal").addEventListener("click", () => {
    createSticky({ title: "Personal", body: "• New personal note", color: "yellow", x: 160, y: 100 });
  });

  document.getElementById("demo-add-ideas").addEventListener("click", () => {
    createSticky({ title: "Ideas", body: "• Next feature idea", color: "purple", x: 200, y: 130 });
  });

  document.getElementById("demo-toggle-window").addEventListener("click", () => {
    mockWindow.classList.toggle("hidden");
  });

  document.getElementById("demo-reset").addEventListener("click", resetDemo);

  // Copy install snippet
  const copyBtn = document.getElementById("copy-install-btn");
  copyBtn.addEventListener("click", async () => {
    const text = document.getElementById("install-code").textContent;
    try {
      await navigator.clipboard.writeText(text);
      copyBtn.textContent = "Copied!";
      setTimeout(() => { copyBtn.textContent = "Copy"; }, 1800);
    } catch {
      copyBtn.textContent = "Select & Copy";
    }
  });

  resetDemo();
})();
