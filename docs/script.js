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

  const PEN_COLORS = [
    { id: "white",  label: "White",  hex: "#FAFAFC" },
    { id: "yellow", label: "Yellow", hex: "#FFDB40" },
    { id: "blue",   label: "Blue",   hex: "#5CB8FF" },
    { id: "green",  label: "Green",  hex: "#59E085" },
    { id: "pink",   label: "Pink",   hex: "#FF73A3" },
    { id: "orange", label: "Orange", hex: "#FF9E3D" },
    { id: "purple", label: "Purple", hex: "#B88FFF" },
    { id: "black",  label: "Black",  hex: "#1F1F24" }
  ];

  // Crisp inline SVG artwork for the sample picture sticky (zero extra network requests)
  const SAMPLE_PICTURE_SVG = "data:image/svg+xml;utf8," + encodeURIComponent(`
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 190">
      <defs>
        <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#141b33"/>
          <stop offset="52%" stop-color="#4e3068"/>
          <stop offset="100%" stop-color="#f28d57"/>
        </linearGradient>
        <radialGradient id="sun" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stop-color="#fff5b8"/>
          <stop offset="65%" stop-color="#ffbe5c"/>
          <stop offset="100%" stop-color="#ff7a45" stop-opacity="0"/>
        </radialGradient>
      </defs>
      <rect width="320" height="190" fill="url(#sky)"/>
      <circle cx="220" cy="78" r="36" fill="url(#sun)"/>
      <circle cx="220" cy="78" r="18" fill="#fff3b0"/>
      <circle cx="52" cy="34" r="1.5" fill="#fff" opacity="0.8"/>
      <circle cx="110" cy="24" r="1.2" fill="#fff" opacity="0.6"/>
      <circle cx="164" cy="40" r="1.4" fill="#fff" opacity="0.7"/>
      <path d="M0 150 L68 96 L128 138 L194 86 L268 142 L320 112 L320 190 L0 190 Z" fill="#231c3a"/>
      <path d="M0 166 L92 122 L176 164 L250 128 L320 158 L320 190 L0 190 Z" fill="#131024"/>
    </svg>
  `);

  const canvas = document.getElementById("wallpaper-canvas");
  const mockWindow = document.getElementById("mock-app-window");
  const drawCanvas = document.getElementById("draw-layer");
  const drawCtx = drawCanvas.getContext("2d");
  const drawHud = document.getElementById("draw-hud");
  const toggleDrawBtn = document.getElementById("demo-toggle-draw");
  const pictureInput = document.getElementById("demo-picture-input");

  let zCounter = 10;

  // Drawing state
  let isDrawingMode = false;
  let activeTool = "pen"; // "pen" | "eraser"
  let activePenColor = PEN_COLORS[1].hex; // yellow
  let activeLineWidth = 4;
  let strokes = [];
  let undoStack = [];
  let currentStroke = null;
  let isPointerDown = false;
  let didSnapshotErase = false;

  const INITIAL_NOTES = [
    { title: "Personal", body: "Hobbies are best!\n• Weekend hike\n• Read 20 pages", color: "yellow", x: 48, y: 36, w: 220, h: 155, done: false },
    { title: "Work", body: "Ship v0.3 release\n• Wallpaper pen\n• Picture stickies", color: "blue", x: 324, y: 42, w: 230, h: 158, done: false },
    { title: "Weekend Trip", color: "purple", x: 64, y: 242, w: 225, h: 175, imageSrc: SAMPLE_PICTURE_SVG, aspectRatio: 320 / 190 },
    { title: "Errands", body: "Buy coffee beans\nPick up dry cleaning", color: "green", x: 610, y: 218, w: 215, h: 148, done: true }
  ];

  // Sample hand-drawn arrow connecting Personal -> Weekend Trip (stored in normalized 0..1 coords)
  const INITIAL_STROKES_NORMALIZED = [
    {
      color: "#FFDB40",
      lineWidth: 3.5,
      points: [
        { nx: 0.045, ny: 0.25 },
        { nx: 0.025, ny: 0.34 },
        { nx: 0.028, ny: 0.44 },
        { nx: 0.055, ny: 0.51 }
      ]
    },
    {
      color: "#FFDB40",
      lineWidth: 3.5,
      points: [
        { nx: 0.040, ny: 0.49 },
        { nx: 0.056, ny: 0.515 },
        { nx: 0.062, ny: 0.475 }
      ]
    }
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

  function createSticky({
    title,
    body = "",
    color = "yellow",
    x,
    y,
    w = 230,
    h = 175,
    done = false,
    imageSrc = null,
    aspectRatio = null
  }) {
    const isImage = Boolean(imageSrc);
    const el = document.createElement("div");
    el.className = "sticky" + (done && !isImage ? " done" : "");
    applyPalette(el, color);

    const pos = clampPosition(x, y, w, h);
    el.style.left = `${pos.x}px`;
    el.style.top = `${pos.y}px`;
    el.style.width = `${w}px`;
    el.style.height = `${h}px`;
    el.style.zIndex = String(++zCounter);

    const safeTitle = title.replace(/"/g, "&quot;");
    const doneBtnHtml = isImage
      ? ""
      : `<button type="button" class="sticky-btn sticky-done-btn" title="Mark as done">${done ? "●" : "✓"}</button>`;
    const bodyHtml = isImage
      ? `<div class="sticky-image-wrap"><img src="${imageSrc}" alt="${safeTitle}" draggable="false" /></div>`
      : `<textarea class="sticky-body" placeholder="Write a to-do...">${body}</textarea>`;

    el.innerHTML = `
      <div class="sticky-grab" title="Drag to move"><span class="sticky-grab-pill"></span></div>
      <div class="sticky-header">
        ${doneBtnHtml}
        <input type="text" class="sticky-title" value="${safeTitle}" placeholder="Title..." />
        <button type="button" class="sticky-color-btn" title="Cycle color"></button>
        <button type="button" class="sticky-btn sticky-add-btn" title="New sticky">+</button>
        <button type="button" class="sticky-btn sticky-del-btn" title="Delete sticky">&times;</button>
      </div>
      ${bodyHtml}
      <div class="sticky-resize" title="Drag to resize"></div>
    `;

    el.addEventListener("pointerdown", () => {
      if (!isDrawingMode) {
        el.style.zIndex = String(++zCounter);
      }
    });

    // Done toggle (text stickies)
    const doneBtn = el.querySelector(".sticky-done-btn");
    if (doneBtn) {
      doneBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        const isNowDone = el.classList.toggle("done");
        doneBtn.textContent = isNowDone ? "●" : "✓";
      });
    }

    // Cycle color
    el.querySelector(".sticky-color-btn").addEventListener("click", (e) => {
      e.stopPropagation();
      const idx = COLOR_ORDER.indexOf(el.dataset.color);
      const next = COLOR_ORDER[(idx + 1) % COLOR_ORDER.length];
      applyPalette(el, next);
    });

    // Duplicate nearby
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

    // Resizing via bottom-right grip (locks aspect ratio for picture stickies)
    el.querySelector(".sticky-resize").addEventListener("pointerdown", (e) => {
      e.preventDefault();
      e.stopPropagation();
      const startX = e.clientX;
      const startY = e.clientY;
      const origW = el.offsetWidth;
      const origH = el.offsetHeight;
      const chromeH = 44;
      const canvasRect = canvas.getBoundingClientRect();

      function onMove(ev) {
        const maxW = canvasRect.width - el.offsetLeft - 8;
        const maxH = canvasRect.height - el.offsetTop - 8;
        let w = Math.min(Math.max(175, origW + (ev.clientX - startX)), maxW);
        let h;
        if (isImage && aspectRatio && aspectRatio > 0.05) {
          h = Math.min(Math.max(130, (w / aspectRatio) + chromeH), maxH);
          w = Math.min(Math.max(175, (h - chromeH) * aspectRatio), maxW);
        } else {
          h = Math.min(Math.max(130, origH + (ev.clientY - startY)), maxH);
        }
        el.style.width = `${Math.round(w)}px`;
        el.style.height = `${Math.round(h)}px`;
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

  // MARK: - Freehand Wallpaper Drawing

  function resizeDrawCanvas() {
    const rect = canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    drawCanvas.width = Math.max(1, Math.round(rect.width * dpr));
    drawCanvas.height = Math.max(1, Math.round(rect.height * dpr));
    drawCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    renderDrawings();
  }

  function renderDrawings() {
    const rect = canvas.getBoundingClientRect();
    drawCtx.clearRect(0, 0, rect.width, rect.height);
    for (const stroke of strokes) {
      drawStroke(stroke);
    }
    if (currentStroke) {
      drawStroke(currentStroke);
    }
  }

  function drawStroke(stroke) {
    const pts = stroke.points;
    if (!pts || pts.length === 0) return;

    drawCtx.save();
    drawCtx.lineCap = "round";
    drawCtx.lineJoin = "round";
    drawCtx.strokeStyle = stroke.color;
    drawCtx.fillStyle = stroke.color;
    drawCtx.lineWidth = stroke.lineWidth;

    if (pts.length === 1) {
      drawCtx.beginPath();
      drawCtx.arc(pts[0].x, pts[0].y, stroke.lineWidth / 2, 0, Math.PI * 2);
      drawCtx.fill();
      drawCtx.restore();
      return;
    }

    drawCtx.beginPath();
    drawCtx.moveTo(pts[0].x, pts[0].y);
    if (pts.length === 2) {
      drawCtx.lineTo(pts[1].x, pts[1].y);
    } else {
      for (let i = 1; i < pts.length - 1; i++) {
        const midX = (pts[i].x + pts[i + 1].x) * 0.5;
        const midY = (pts[i].y + pts[i + 1].y) * 0.5;
        drawCtx.quadraticCurveTo(pts[i].x, pts[i].y, midX, midY);
      }
      const last = pts[pts.length - 1];
      drawCtx.lineTo(last.x, last.y);
    }
    drawCtx.stroke();
    drawCtx.restore();
  }

  function distSqToSegment(p, a, b) {
    const abX = b.x - a.x;
    const abY = b.y - a.y;
    const lenSq = abX * abX + abY * abY;
    if (lenSq <= 0.0001) {
      const dx = p.x - a.x;
      const dy = p.y - a.y;
      return dx * dx + dy * dy;
    }
    const t = Math.max(0, Math.min(1, ((p.x - a.x) * abX + (p.y - a.y) * abY) / lenSq));
    const dx = p.x - (a.x + t * abX);
    const dy = p.y - (a.y + t * abY);
    return dx * dx + dy * dy;
  }

  function strokeIntersectsPoint(stroke, pt, radius) {
    const threshold = radius + stroke.lineWidth * 0.5;
    const thresholdSq = threshold * threshold;
    const pts = stroke.points;
    if (pts.length === 1) {
      const dx = pt.x - pts[0].x;
      const dy = pt.y - pts[0].y;
      return dx * dx + dy * dy <= thresholdSq;
    }
    for (let i = 0; i < pts.length - 1; i++) {
      if (distSqToSegment(pt, pts[i], pts[i + 1]) <= thresholdSq) {
        return true;
      }
    }
    return false;
  }

  function pushUndo() {
    undoStack.push(strokes.map((s) => ({ ...s, points: s.points.slice() })));
    if (undoStack.length > 30) undoStack.shift();
  }

  function getCanvasPoint(e) {
    const rect = drawCanvas.getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  }

  drawCanvas.addEventListener("pointerdown", (e) => {
    if (!isDrawingMode) return;
    e.preventDefault();
    drawCanvas.setPointerCapture(e.pointerId);
    isPointerDown = true;
    const pt = getCanvasPoint(e);

    if (activeTool === "pen") {
      currentStroke = { color: activePenColor, lineWidth: activeLineWidth, points: [pt] };
      renderDrawings();
    } else {
      didSnapshotErase = false;
      eraseAt(pt);
    }
  });

  drawCanvas.addEventListener("pointermove", (e) => {
    if (!isDrawingMode || !isPointerDown) return;
    const pt = getCanvasPoint(e);

    if (activeTool === "pen" && currentStroke) {
      const last = currentStroke.points[currentStroke.points.length - 1];
      const dx = pt.x - last.x;
      const dy = pt.y - last.y;
      if (dx * dx + dy * dy >= 2.25) {
        currentStroke.points.push(pt);
        renderDrawings();
      }
    } else if (activeTool === "eraser") {
      eraseAt(pt);
    }
  });

  function finishPointer() {
    if (!isPointerDown) return;
    isPointerDown = false;
    if (activeTool === "pen" && currentStroke) {
      pushUndo();
      strokes.push(currentStroke);
      currentStroke = null;
      renderDrawings();
      syncHudUI();
    }
    didSnapshotErase = false;
  }

  drawCanvas.addEventListener("pointerup", finishPointer);
  drawCanvas.addEventListener("pointercancel", finishPointer);

  function eraseAt(pt) {
    const radius = Math.max(12, activeLineWidth * 1.4);
    const remaining = strokes.filter((s) => !strokeIntersectsPoint(s, pt, radius));
    if (remaining.length !== strokes.length) {
      if (!didSnapshotErase) {
        pushUndo();
        didSnapshotErase = true;
      }
      strokes = remaining;
      renderDrawings();
      syncHudUI();
    }
  }

  // HUD Controls
  const hudPenBtn = document.getElementById("hud-pen-btn");
  const hudEraserBtn = document.getElementById("hud-eraser-btn");
  const hudColorsWrap = document.getElementById("hud-colors");
  const hudSizeDot = document.getElementById("hud-size-dot");
  const hudSizeSlider = document.getElementById("hud-size-slider");
  const hudUndoBtn = document.getElementById("hud-undo-btn");
  const hudClearBtn = document.getElementById("hud-clear-btn");
  const hudDoneBtn = document.getElementById("hud-done-btn");

  PEN_COLORS.forEach((c) => {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "hud-swatch";
    btn.style.background = c.hex;
    btn.title = c.label;
    btn.dataset.hex = c.hex;
    btn.addEventListener("click", () => {
      activePenColor = c.hex;
      activeTool = "pen";
      syncHudUI();
    });
    hudColorsWrap.appendChild(btn);
  });

  function setDrawingMode(enabled) {
    isDrawingMode = enabled;
    drawCanvas.classList.toggle("active", enabled);
    drawHud.classList.toggle("hidden", !enabled);
    toggleDrawBtn.classList.toggle("is-active", enabled);
    syncHudUI();
  }

  function syncHudUI() {
    hudPenBtn.classList.toggle("active", activeTool === "pen");
    hudEraserBtn.classList.toggle("active", activeTool === "eraser");
    drawCanvas.classList.toggle("eraser", isDrawingMode && activeTool === "eraser");
    hudColorsWrap.querySelectorAll(".hud-swatch").forEach((btn) => {
      btn.classList.toggle("selected", activeTool === "pen" && btn.dataset.hex === activePenColor);
    });
    const dotSize = Math.min(Math.max(activeLineWidth, 4), 16);
    hudSizeDot.style.width = `${dotSize}px`;
    hudSizeDot.style.height = `${dotSize}px`;
    hudSizeDot.style.background = activeTool === "eraser" ? "rgba(255,255,255,0.75)" : activePenColor;
    hudSizeSlider.value = String(activeLineWidth);
    hudUndoBtn.disabled = undoStack.length === 0;
    hudClearBtn.disabled = strokes.length === 0;
  }

  hudPenBtn.addEventListener("click", () => { activeTool = "pen"; syncHudUI(); });
  hudEraserBtn.addEventListener("click", () => { activeTool = "eraser"; syncHudUI(); });
  hudSizeSlider.addEventListener("input", () => {
    activeLineWidth = Number(hudSizeSlider.value);
    syncHudUI();
  });
  hudUndoBtn.addEventListener("click", () => {
    if (undoStack.length === 0) return;
    strokes = undoStack.pop();
    renderDrawings();
    syncHudUI();
  });
  hudClearBtn.addEventListener("click", () => {
    if (strokes.length === 0) return;
    pushUndo();
    strokes = [];
    renderDrawings();
    syncHudUI();
  });
  hudDoneBtn.addEventListener("click", () => setDrawingMode(false));

  window.addEventListener("keydown", (e) => {
    if (!isDrawingMode) return;
    if (e.key === "Escape") {
      setDrawingMode(false);
    } else if (e.key.toLowerCase() === "p") {
      activeTool = "pen";
      syncHudUI();
    } else if (e.key.toLowerCase() === "e") {
      activeTool = "eraser";
      syncHudUI();
    } else if (e.key === "[") {
      activeLineWidth = Math.max(2, activeLineWidth - 2);
      syncHudUI();
    } else if (e.key === "]") {
      activeLineWidth = Math.min(20, activeLineWidth + 2);
      syncHudUI();
    }
  });

  // MARK: - Demo Toolbar Actions

  function resetDemo() {
    canvas.querySelectorAll(".sticky").forEach((n) => n.remove());
    mockWindow.classList.add("hidden");
    setDrawingMode(false);
    undoStack = [];

    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    INITIAL_NOTES.forEach((note, i) => {
      const scaledX = width < 700 ? 16 + i * 24 : note.x;
      const scaledY = width < 700 ? 18 + i * 64 : note.y;
      createSticky({ ...note, x: scaledX, y: scaledY });
    });

    // Seed sample connector arrow on wider screens
    if (width >= 700) {
      strokes = INITIAL_STROKES_NORMALIZED.map((s) => ({
        color: s.color,
        lineWidth: s.lineWidth,
        points: s.points.map((p) => ({ x: p.nx * width, y: p.ny * height }))
      }));
    } else {
      strokes = [];
    }
    resizeDrawCanvas();
    syncHudUI();
  }

  document.getElementById("demo-add-work").addEventListener("click", () => {
    setDrawingMode(false);
    createSticky({ title: "Work", body: "• New work task", color: "blue", x: 120, y: 70 });
  });

  document.getElementById("demo-add-personal").addEventListener("click", () => {
    setDrawingMode(false);
    createSticky({ title: "Personal", body: "• New personal note", color: "yellow", x: 160, y: 100 });
  });

  document.getElementById("demo-add-ideas").addEventListener("click", () => {
    setDrawingMode(false);
    createSticky({ title: "Ideas", body: "• Next feature idea", color: "purple", x: 200, y: 130 });
  });

  document.getElementById("demo-add-picture").addEventListener("click", () => {
    setDrawingMode(false);
    pictureInput.value = "";
    pictureInput.click();
  });

  pictureInput.addEventListener("change", () => {
    const file = pictureInput.files && pictureInput.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      const dataUrl = reader.result;
      const probe = new Image();
      probe.onload = () => {
        const aspect = probe.width / Math.max(1, probe.height);
        const chromeH = 44;
        let bodyW = aspect >= 1 ? 230 : Math.max(175, Math.round(180 * aspect));
        let bodyH = Math.round(bodyW / aspect);
        if (bodyH > 220) {
          bodyH = 220;
          bodyW = Math.max(175, Math.round(bodyH * aspect));
        }
        const cleanTitle = file.name.replace(/\.[^.]+$/, "") || "Picture";
        createSticky({
          title: cleanTitle,
          color: "purple",
          x: 220,
          y: 90,
          w: bodyW,
          h: bodyH + chromeH,
          imageSrc: dataUrl,
          aspectRatio: aspect
        });
      };
      probe.src = dataUrl;
    };
    reader.readAsDataURL(file);
  });

  toggleDrawBtn.addEventListener("click", () => {
    setDrawingMode(!isDrawingMode);
  });

  document.getElementById("demo-toggle-window").addEventListener("click", () => {
    mockWindow.classList.toggle("hidden");
  });

  document.getElementById("demo-reset").addEventListener("click", resetDemo);
  window.addEventListener("resize", resizeDrawCanvas);

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
