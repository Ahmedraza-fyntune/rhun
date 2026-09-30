(() => {
  "use strict";

  const descriptions = {
    hero: ["Just open it and start.", "rhun with a file explorer, syntax highlighting, and a live coding agent session"],
    terminal: ["Your terminal, right here.", "The built-in terminal in rhun, showing a build and Git log below the editor"],
    git: ["Every branch. Every change.", "Git history in rhun with a commit graph, tags, and uncommitted changes"],
    agents: ["Claude Code and Codex, alongside your code.", "The agents panel in rhun following a live Codex session"]
  };
  let selectedTheme = "hero";
  let selectedThemeLabel = "Rhun Dark";

  function setScreenshot(image, link, name, alt) {
    image.srcset = `img/${name}-800.webp 800w, img/${name}.webp 1600w`;
    image.src = `img/${name}.webp`;
    image.alt = alt;
    link.href = `img/${name}.webp`;
  }

  const viewButtons = document.querySelectorAll("[data-view]");
  viewButtons.forEach(button => {
    button.addEventListener("click", () => {
      const name = button.dataset.view;
      viewButtons.forEach(item => item.setAttribute("aria-pressed", String(item === button)));
      document.querySelector(".theme-controls").hidden = name !== "themes";
      if (name === "themes") {
        setScreenshot(document.querySelector("#editor-image"), document.querySelector("#editor-link"), selectedTheme, `rhun in the ${selectedThemeLabel} theme`);
        document.querySelector("#view-description").textContent = "Find your colors.";
        return;
      }
      setScreenshot(document.querySelector("#editor-image"), document.querySelector("#editor-link"), name, descriptions[name][1]);
      document.querySelector("#view-description").textContent = descriptions[name][0];
    });
  });

  const themeButtons = document.querySelectorAll("[data-theme]");
  themeButtons.forEach(button => {
    button.addEventListener("click", () => {
      const label = button.getAttribute("aria-label");
      themeButtons.forEach(item => item.setAttribute("aria-pressed", String(item === button)));
      selectedTheme = button.dataset.theme;
      selectedThemeLabel = label;
      setScreenshot(document.querySelector("#editor-image"), document.querySelector("#editor-link"), selectedTheme, `rhun in the ${label} theme`);
      document.querySelector("#theme-name").textContent = label;
    });
  });

  document.querySelectorAll("[data-copy]").forEach(button => {
    let resetTimer;
    button.addEventListener("click", async () => {
      const status = button.parentElement.querySelector(".copy-status");
      clearTimeout(resetTimer);
      try {
        await navigator.clipboard.writeText(button.dataset.copy);
        status.textContent = "Copied. Paste it into your terminal to install.";
        button.textContent = "Copied ✓";
        resetTimer = setTimeout(() => { button.textContent = "Copy command ↗"; }, 2200);
      } catch {
        status.textContent = "Select and copy the command above to install.";
        const selection = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(document.querySelector("#install-command"));
        selection.removeAllRanges();
        selection.addRange(range);
      }
    });
  });

  // A solid wordmark made of small blocks, with a slow pass of light.
  const canvas = document.querySelector("#code-field");
  const context = canvas.getContext("2d");
  if (!context) return;
  const container = canvas.parentElement;
  const toggle = document.querySelector(".motion-toggle");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  let width = 0;
  let height = 0;
  let blocks = [];
  let bounds = { width: 1, height: 1 };
  let phase = 0;
  let frame = 0;
  let previous = 0;
  let visible = true;
  let paused = reducedMotion.matches;
  let pointerX = 0;
  let pointerY = 0;
  let tiltX = 0;
  let tiltY = 0;

  function prepare() {
    const mask = document.createElement("canvas");
    mask.width = 1000;
    mask.height = 380;
    const ink = mask.getContext("2d", { willReadFrequently: true });
    if (!ink) return;
    ink.fillStyle = "white";
    ink.font = '700 360px "Instrument Sans", Arial, sans-serif';
    ink.textAlign = "center";
    ink.textBaseline = "alphabetic";
    ink.fillText("rhun", 500, 320);
    const pixels = ink.getImageData(0, 0, mask.width, mask.height).data;
    const step = 12;
    const points = [];
    for (let y = 6; y < mask.height; y += step) {
      for (let x = 6; x < mask.width; x += step) {
        if (pixels[(y * mask.width + x) * 4 + 3] > 160) points.push({ x, y });
      }
    }
    const minX = Math.min(...points.map(point => point.x));
    const minY = Math.min(...points.map(point => point.y));
    bounds = {
      width: Math.max(...points.map(point => point.x)) - minX + step,
      height: Math.max(...points.map(point => point.y)) - minY + step
    };
    blocks = points.map(point => ({ x: point.x - minX, y: point.y - minY }));
  }

  function polygon(points, fill) {
    context.fillStyle = fill;
    context.beginPath();
    context.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i++) context.lineTo(points[i][0], points[i][1]);
    context.closePath();
    context.fill();
  }

  function draw() {
    context.clearRect(0, 0, width, height);
    const scale = Math.min(width * 0.83 / bounds.width, height * 0.71 / bounds.height, 1.4);
    const left = (width - bounds.width * scale) / 2;
    const top = (height - bounds.height * scale) / 2;
    const lightPosition = (phase * 0.055) % 2.6 - 0.7;
    context.save();
    context.translate(left + tiltX * 5, top + tiltY * 3);
    context.scale(scale, scale);
    for (const block of blocks) {
      const relativeX = block.x / bounds.width;
      const relativeY = block.y / bounds.height;
      const light = Math.max(0, 1 - Math.abs(relativeX + relativeY * 0.18 - lightPosition) * 3);
      const depth = 14 + Math.sin(relativeX * 5 + relativeY * 2 + phase * 0.3) * 3;
      const dx = depth * (0.48 + tiltX * 0.06);
      const dy = -depth * (0.6 + tiltY * 0.05);
      const x = block.x;
      const y = block.y - block.x * 0.028;
      const size = 10.4;
      const brightness = 0.58 + relativeX * 0.22 + light * 0.2;
      const r = Math.round(138 * brightness);
      const g = Math.round(164 * brightness);
      const b = Math.round(255 * brightness);
      polygon([[x, y], [x + dx, y + dy], [x + size + dx, y + dy], [x + size, y]], `rgb(${r + 24},${g + 24},${Math.min(255, b + 24)})`);
      polygon([[x + size, y], [x + size + dx, y + dy], [x + size + dx, y + size + dy], [x + size, y + size]], `rgb(${Math.round(r * 0.45)},${Math.round(g * 0.45)},${Math.round(b * 0.52)})`);
      context.fillStyle = `rgb(${r},${g},${b})`;
      context.fillRect(x, y, size, size);
    }
    context.restore();
  }

  function resize() {
    const rect = canvas.getBoundingClientRect();
    width = rect.width;
    height = rect.height;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    context.setTransform(dpr, 0, 0, dpr, 0, 0);
    draw();
  }

  function animate(now) {
    frame = 0;
    if (paused || !visible || document.hidden) return;
    const elapsed = previous ? Math.min(now - previous, 64) : 0;
    if (elapsed >= 32 || !previous) {
      phase += elapsed / 1000;
      tiltX += (pointerX - tiltX) * 0.06;
      tiltY += (pointerY - tiltY) * 0.06;
      previous = now;
      draw();
    }
    frame = requestAnimationFrame(animate);
  }

  function sync() {
    if (frame) cancelAnimationFrame(frame);
    frame = 0;
    previous = 0;
    toggle.setAttribute("aria-pressed", String(paused));
    toggle.textContent = paused ? "▷ Resume motion" : "Ⅱ Pause motion";
    if (!paused && visible && !document.hidden) frame = requestAnimationFrame(animate);
  }

  async function initialize() {
    await document.fonts.load('700 360px "Instrument Sans"').catch(() => {});
    prepare();
    if (!blocks.length) return;
    resize();
    container.classList.add("is-ready");
    toggle.hidden = false;
    toggle.addEventListener("click", () => { paused = !paused; sync(); });
    reducedMotion.addEventListener("change", event => {
      paused = event.matches;
      if (paused) { phase = 0; tiltX = 0; tiltY = 0; }
      sync();
      draw();
    });
    document.addEventListener("visibilitychange", sync);
    container.addEventListener("pointermove", event => {
      if (event.pointerType === "touch" || paused) return;
      const rect = container.getBoundingClientRect();
      pointerX = ((event.clientX - rect.left) / rect.width - 0.5) * 2;
      pointerY = ((event.clientY - rect.top) / rect.height - 0.5) * 2;
    });
    container.addEventListener("pointerleave", () => { pointerX = 0; pointerY = 0; });
    new IntersectionObserver(entries => {
      visible = entries[0].isIntersecting;
      sync();
    }).observe(container);
    new ResizeObserver(resize).observe(container);
    sync();
  }
  initialize();
})();
