const stage = document.querySelector('.editor-stage');
const preview = document.querySelector('.editor-preview');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const pointer = window.matchMedia('(hover: hover) and (pointer: fine)');
const narrow = window.matchMedia('(max-width: 760px)');

if (stage && preview) {
  let frame = 0;
  let previous = 0;
  let x = .5, y = .1, tiltX = 0, tiltY = 0;
  let targetX = .5, targetY = .1, targetTiltX = 0, targetTiltY = 0;

  function paint() {
    preview.style.setProperty('--light-x', `${(x * 100).toFixed(2)}%`);
    preview.style.setProperty('--light-y', `${(y * 100).toFixed(2)}%`);
    preview.style.setProperty('--tilt-x', `${tiltX.toFixed(3)}deg`);
    preview.style.setProperty('--tilt-y', `${tiltY.toFixed(3)}deg`);
  }

  function animate(now) {
    const dt = previous ? Math.min(now - previous, 64) : 16;
    previous = now;
    const easing = 1 - Math.exp(-dt / 160);
    x += (targetX - x) * easing;
    y += (targetY - y) * easing;
    tiltX += (targetTiltX - tiltX) * easing;
    tiltY += (targetTiltY - tiltY) * easing;
    paint();
    const remaining = Math.abs(targetX - x) + Math.abs(targetY - y) + Math.abs(targetTiltX - tiltX) + Math.abs(targetTiltY - tiltY);
    if (remaining > .001) frame = requestAnimationFrame(animate);
    else { frame = previous = 0; }
  }

  function wake() {
    if (!frame && !document.hidden) frame = requestAnimationFrame(animate);
  }

  function reset() {
    targetX = .5;
    targetY = .1;
    targetTiltX = targetTiltY = 0;
    wake();
  }

  function stop() {
    cancelAnimationFrame(frame);
    frame = previous = 0;
    targetX = x = .5;
    targetY = y = .1;
    targetTiltX = targetTiltY = tiltX = tiltY = 0;
    paint();
  }

  stage.addEventListener('pointermove', event => {
    if (reducedMotion.matches || !pointer.matches || narrow.matches || event.pointerType === 'touch') return;
    const rect = stage.getBoundingClientRect();
    targetX = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
    targetY = Math.max(0, Math.min(1, (event.clientY - rect.top) / rect.height));
    targetTiltX = (.5 - targetY) * 1.4;
    targetTiltY = (targetX - .5) * 1.8;
    wake();
  });
  stage.addEventListener('pointerleave', reset);
  window.addEventListener('blur', stop);
  document.addEventListener('visibilitychange', stop);
  reducedMotion.addEventListener('change', stop);
  pointer.addEventListener('change', stop);
  narrow.addEventListener('change', stop);
  new IntersectionObserver(entries => { if (!entries[0].isIntersecting) stop(); }).observe(stage);
}
