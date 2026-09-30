import * as THREE from "./vendor/three-0.180.0.min.js";

const TAU = Math.PI * 2;

function studio(renderer) {
  const room = new THREE.Scene();
  room.add(new THREE.Mesh(new THREE.BoxGeometry(18,18,18), new THREE.MeshBasicMaterial({color:0x141722,side:THREE.BackSide})));
  function panel(w,h,x,y,z,r,g,b) {
    const material = new THREE.MeshBasicMaterial(); material.color.setRGB(r,g,b);
    const plane = new THREE.Mesh(new THREE.PlaneGeometry(w,h),material);
    plane.position.set(x,y,z); plane.lookAt(0,0,0); room.add(plane);
  }
  panel(2.2,7,-4,2,4,7,8,11);
  panel(1.1,8,4,1,2,3,4.5,10);
  panel(6,2,-1,6,-2,5,6,10);
  panel(3,3,0,-4,3,0.6,1,3);
  panel(.35,7,1,2,-5,4,5,9);
  const generator = new THREE.PMREMGenerator(renderer);
  const texture = generator.fromScene(room,.025).texture;
  generator.dispose();
  room.traverse(o=> { if(o.geometry)o.geometry.dispose(); if(o.material)o.material.dispose(); });
  return texture;
}

function foldedBand() {
  const path = new THREE.CatmullRomCurve3([
    new THREE.Vector3(0,1.37,.10),new THREE.Vector3(-.35,1.13,.26),new THREE.Vector3(-1.26,-.48,.40),
    new THREE.Vector3(-1.32,-.84,.24),new THREE.Vector3(-.94,-1.03,.02),new THREE.Vector3(.99,-1.03,-.20),
    new THREE.Vector3(1.34,-.78,-.28),new THREE.Vector3(1.22,-.39,-.24),new THREE.Vector3(.34,1.16,-.05)
  ],true,'catmullrom',.23);
  const n=240, m=12, frames=path.computeFrenetFrames(n,true), positions=new Float32Array((n+1)*(m+1)*3), indices=[];
  const centers=[], normals=[], binormals=[];
  for(let i=0;i<=n;i++){centers.push(path.getPointAt(i/n));normals.push(frames.normals[i]);binormals.push(frames.binormals[i]);}
  const geometry=new THREE.BufferGeometry(); geometry.setAttribute('position',new THREE.BufferAttribute(positions,3));
  for(let i=0;i<n;i++)for(let j=0;j<m;j++){const a=i*(m+1)+j,b=a+m+1;indices.push(a,b,a+1,b,b+1,a+1);}
  geometry.setIndex(indices);
  const cross=[];
  for(let j=0;j<=m;j++) {
    const angle=j/m*TAU, c=Math.cos(angle),s=Math.sin(angle);
    cross.push([Math.sign(c)*Math.pow(Math.abs(c),.32)*.37,Math.sign(s)*Math.pow(Math.abs(s),.32)*.058]);
  }
  function deform(amount) {
    for(let i=0;i<=n;i++){
      const t=i/n, angle=.75+Math.sin(t*TAU*3+.6)*.55+amount*Math.sin(t*TAU)*.8;
      const co=Math.cos(angle),si=Math.sin(angle),p=centers[i],normal=normals[i],binormal=binormals[i];
      for(let j=0;j<=m;j++){
        const [a,b]=cross[j],u=a*co-b*si,v=a*si+b*co,k=(i*(m+1)+j)*3;
        positions[k]=p.x+normal.x*u+binormal.x*v;
        positions[k+1]=p.y+normal.y*u+binormal.y*v;
        positions[k+2]=p.z+normal.z*u+binormal.z*v+amount*Math.sin(t*TAU)*.16;
      }
    }
    geometry.attributes.position.needsUpdate=true;geometry.computeVertexNormals();
  }
  deform(0); return {geometry,deform};
}

function initialize() {
  const stage = document.querySelector('.hero-stage');
  const art = document.querySelector('.hero-art');
  const toggle = document.querySelector('.motion-toggle');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  if (!stage || !art || !toggle) return;

  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, powerPreference: 'low-power' });
  } catch {
    return;
  }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
  renderer.setClearColor(0x111216, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  art.append(renderer.domElement);

  const scene = new THREE.Scene();
  scene.environment = studio(renderer);
  const camera = new THREE.PerspectiveCamera(34, 1, .1, 100);
  camera.position.set(0, 0, 8);
  const sculpture = new THREE.Group();
  scene.add(sculpture);
  scene.add(new THREE.HemisphereLight(0xcad7ff, 0x11131c, 1.6));
  const key = new THREE.DirectionalLight(0xcbd6ff, 3.3);
  key.position.set(-3, 4, 5);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0x718cff, 3);
  fill.position.set(4, -1, 2);
  scene.add(fill);

  const material = new THREE.MeshPhysicalMaterial({
    color: 0x8aa4ff, metalness: 1, roughness: .19,
    clearcoat: 1, clearcoatRoughness: .15, envMapIntensity: 1.3,
    side: THREE.DoubleSide
  });
  const fold = foldedBand();
  sculpture.add(new THREE.Mesh(fold.geometry, material));

  let width = 1;
  let visible = false;
  let lost = false;
  let frame = 0;
  let last = 0;
  let demoStart = 0;
  let targetX = 0;
  let targetY = 0;
  let targetEnergy = 0;
  let x = 0;
  let y = 0;
  let energy = 0;
  let alternatePose = false;

  function updateToggle() {
    const playing = Boolean(demoStart || alternatePose);
    toggle.setAttribute('aria-pressed', String(playing));
    toggle.textContent = reducedMotion.matches
      ? (alternatePose ? 'Reset sculpture' : 'Rotate sculpture')
      : (demoStart ? 'Pause motion' : 'Play motion');
  }

  function pose() {
    if (lost) return;
    const narrow = window.matchMedia('(max-width: 760px)').matches;
    const viewHeight = 2 * Math.tan(camera.fov * Math.PI / 360) * camera.position.z;
    sculpture.position.set(narrow ? 0 : viewHeight * camera.aspect * .275, narrow ? 0 : .10, 0);
    sculpture.rotation.set(.10 + y * .20, -.34 + x * .42, -.22 + x * .055);
    sculpture.scale.setScalar(narrow ? 1.12 : Math.min(1.13, width / 1000 * 1.1));
    key.position.set(-3 + x * 4, 4 - y * 2, 5);
    fold.deform(energy * .7 + x * .36);
    renderer.render(scene, camera);
  }

  function resize() {
    const rect = art.getBoundingClientRect();
    if (!rect.width || !rect.height || lost) return;
    width = rect.width;
    renderer.setSize(width, rect.height, false);
    camera.aspect = width / rect.height;
    camera.updateProjectionMatrix();
    pose();
    art.classList.add('is-ready');
    toggle.hidden = false;
  }

  function cancelFrame() {
    if (frame) cancelAnimationFrame(frame);
    frame = 0;
    last = 0;
  }

  function reset() {
    demoStart = 0;
    alternatePose = false;
    targetX = targetY = targetEnergy = 0;
    updateToggle();
  }

  function animate(now) {
    frame = 0;
    if (!visible || document.hidden || lost) return;
    const elapsed = Math.min(50, last ? now - last : 16);
    last = now;
    if (demoStart) {
      const time = (now - demoStart) / 1000;
      if (time > 5.6) reset();
      else {
        targetX = Math.sin(time * 1.35) * .8;
        targetY = Math.cos(time * 1.05) * .4;
        targetEnergy = .8;
      }
    }
    const easing = reducedMotion.matches ? 1 : 1 - Math.exp(-elapsed / 150);
    x += (targetX - x) * easing;
    y += (targetY - y) * easing;
    energy += (targetEnergy - energy) * easing;
    pose();
    if (demoStart || Math.abs(targetX - x) + Math.abs(targetY - y) + Math.abs(targetEnergy - energy) > .001) {
      frame = requestAnimationFrame(animate);
    }
  }

  function wake() {
    if (!frame && visible && !document.hidden && !lost) {
      last = 0;
      frame = requestAnimationFrame(animate);
    }
  }

  art.addEventListener('pointermove', event => {
    if (event.pointerType === 'touch' || reducedMotion.matches) return;
    demoStart = 0;
    updateToggle();
    const rect = art.getBoundingClientRect();
    targetX = ((event.clientX - rect.left) / rect.width - .5) * 2;
    targetY = ((event.clientY - rect.top) / rect.height - .5) * 2;
    targetEnergy = 1;
    wake();
  });
  art.addEventListener('pointerleave', () => {
    if (demoStart || reducedMotion.matches) return;
    reset();
    wake();
  });
  toggle.addEventListener('click', () => {
    if (reducedMotion.matches) {
      alternatePose = !alternatePose;
      targetX = alternatePose ? .6 : 0;
      targetY = alternatePose ? -.25 : 0;
      targetEnergy = alternatePose ? 1 : 0;
    } else if (demoStart) {
      reset();
    } else {
      demoStart = performance.now();
    }
    updateToggle();
    wake();
  });

  new ResizeObserver(resize).observe(art);
  new IntersectionObserver(entries => {
    visible = entries[0].isIntersecting;
    if (!visible) {
      cancelFrame();
      reset();
      x = y = energy = 0;
    } else resize();
  }).observe(art);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      cancelFrame();
      reset();
      x = y = energy = 0;
    } else resize();
  });
  reducedMotion.addEventListener('change', () => {
    cancelFrame();
    reset();
    x = y = energy = 0;
    pose();
  });
  renderer.domElement.addEventListener('webglcontextlost', event => {
    event.preventDefault();
    lost = true;
    cancelFrame();
    reset();
    art.classList.remove('is-ready');
    renderer.domElement.hidden = true;
    toggle.hidden = true;
  });
  renderer.domElement.addEventListener('webglcontextrestored', () => {
    lost = false;
    renderer.domElement.hidden = false;
    scene.environment.dispose();
    scene.environment = studio(renderer);
    resize();
  });
  updateToggle();
  resize();
}

initialize();
