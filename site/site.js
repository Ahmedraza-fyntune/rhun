(() => {
  "use strict";

  const descriptions = {
    hero: "rhun with a file explorer, syntax highlighting, and a live coding agent session",
    terminal: "The built-in terminal in rhun, showing a build and Git log below the editor",
    git: "Git history in rhun with a commit graph, tags, and uncommitted changes",
    agents: "The agents panel in rhun following a live Codex session"
  };
  let selectedTheme = "hero";
  let selectedThemeLabel = "Rhun Dark";

  function setScreenshot(image, name, alt) {
    image.srcset = `img/${name}-800.webp 800w, img/${name}.webp 1600w`;
    image.src = `img/${name}.webp`;
    image.alt = alt;
  }

  const viewButtons = document.querySelectorAll("[data-view]");
  viewButtons.forEach(button => {
    button.addEventListener("click", () => {
      const name = button.dataset.view;
      viewButtons.forEach(item => item.setAttribute("aria-pressed", String(item === button)));
      document.querySelector(".theme-controls").hidden = name !== "themes";
      if (name === "themes") {
        setScreenshot(document.querySelector("#editor-image"), selectedTheme, `rhun in the ${selectedThemeLabel} theme`);
        return;
      }
      setScreenshot(document.querySelector("#editor-image"), name, descriptions[name]);
    });
  });

  const themeButtons = document.querySelectorAll("[data-theme]");
  themeButtons.forEach(button => {
    button.addEventListener("click", () => {
      const label = button.getAttribute("aria-label");
      themeButtons.forEach(item => item.setAttribute("aria-pressed", String(item === button)));
      selectedTheme = button.dataset.theme;
      selectedThemeLabel = label;
      setScreenshot(document.querySelector("#editor-image"), selectedTheme, `rhun in the ${label} theme`);
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

  // The editor preview remains usable without its optional lighting effect.
  import("./hero.js?v=@ASSET_VERSION@").catch(() => {});
})();
