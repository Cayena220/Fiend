// Renders Fiend's sigil (the eye from web/favicon.svg) into the app icon and the
// installer artwork. Plain Node, no packages: shapes are rasterized with supersampling,
// PNGs are encoded with zlib, and the ICO is packed by hand.
//   node scripts/make-icon.mjs                 writes app_icon.ico and installer/*.png
//   node scripts/make-icon.mjs --preview DIR   also writes each icon size as a PNG to DIR
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const BG = hex('#0B0A10');
const RIM = hex('#2E2A3B');
const ACCENT = hex('#FF3B4E');

// Geometry from web/favicon.svg, in its 116-unit box (viewBox -8 -22 116 116).
const BOX = { x: -8, y: -22, size: 116, radius: 24 };
const EYE = flatten([[4, 36], [50, -13], [96, 36], [50, 85], [4, 36]]);
const PUPIL = flatten([[50, 10], [64, 36], [50, 62], [36, 36], [50, 10]]);
const EYE_STROKE = 8;

function hex(s) {
  const n = parseInt(s.slice(1), 16);
  return [(n >> 16) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}

// Quadratic Bezier chain (start, control, end, control, end, ...) to a polyline.
function flatten(pts, steps = 48) {
  const out = [pts[0]];
  for (let i = 1; i + 1 < pts.length; i += 2) {
    const [p0, p1, p2] = [pts[i - 1], pts[i], pts[i + 1]];
    for (let s = 1; s <= steps; s++) {
      const t = s / steps, u = 1 - t;
      out.push([u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]]);
    }
  }
  return out;
}

function insidePolygon(poly, x, y) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

function distanceToPolyline(poly, x, y) {
  let best = Infinity;
  for (let i = 1; i < poly.length; i++) {
    const [ax, ay] = poly[i - 1], [bx, by] = poly[i];
    const dx = bx - ax, dy = by - ay;
    const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy || 1)));
    const ex = x - ax - t * dx, ey = y - ay - t * dy;
    best = Math.min(best, ex * ex + ey * ey);
  }
  return Math.sqrt(best);
}

// Signed distance to a rounded rectangle (negative inside).
function roundedRectDistance(r, x, y) {
  const hw = r.w / 2, hh = r.h / 2;
  const qx = Math.abs(x - r.x - hw) - hw + r.radius, qy = Math.abs(y - r.y - hh) - hh + r.radius;
  return Math.min(Math.max(qx, qy), 0) + Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) - r.radius;
}

class Canvas {
  constructor(w, h) {
    this.w = w;
    this.h = h;
    this.px = new Float32Array(w * h * 4); // premultiplied RGBA, 0..1
  }

  // Coverage of `inside(x, y)` (canvas pixel coordinates) over a pixel bounding box.
  mask(inside, bounds, samples = 8) {
    const m = new Float32Array(this.w * this.h);
    const x0 = Math.max(0, Math.floor(bounds[0])), y0 = Math.max(0, Math.floor(bounds[1]));
    const x1 = Math.min(this.w, Math.ceil(bounds[2])), y1 = Math.min(this.h, Math.ceil(bounds[3]));
    for (let py = y0; py < y1; py++) {
      for (let px = x0; px < x1; px++) {
        let hit = 0;
        for (let sy = 0; sy < samples; sy++) {
          for (let sx = 0; sx < samples; sx++) {
            if (inside(px + (sx + 0.5) / samples, py + (sy + 0.5) / samples)) hit++;
          }
        }
        m[py * this.w + px] = hit / (samples * samples);
      }
    }
    return m;
  }

  paint(mask, [r, g, b], alpha = 1) {
    for (let i = 0; i < mask.length; i++) {
      const a = mask[i] * alpha;
      if (!a) continue;
      const p = i * 4;
      this.px[p] = r * a + this.px[p] * (1 - a);
      this.px[p + 1] = g * a + this.px[p + 1] * (1 - a);
      this.px[p + 2] = b * a + this.px[p + 2] * (1 - a);
      this.px[p + 3] = a + this.px[p + 3] * (1 - a);
    }
  }

  // Straight-alpha RGBA bytes.
  rgba() {
    const out = Buffer.alloc(this.w * this.h * 4);
    for (let i = 0; i < this.w * this.h; i++) {
      const a = this.px[i * 4 + 3];
      for (let c = 0; c < 3; c++) out[i * 4 + c] = a ? Math.round(Math.min(1, this.px[i * 4 + c] / a) * 255) : 0;
      out[i * 4 + 3] = Math.round(a * 255);
    }
    return out;
  }
}

function blur(mask, w, h, sigma) {
  const radius = Math.ceil(sigma * 3);
  const kernel = [];
  for (let i = -radius; i <= radius; i++) kernel.push(Math.exp((-i * i) / (2 * sigma * sigma)));
  const sum = kernel.reduce((a, b) => a + b);
  const pass = (src, horizontal) => {
    const dst = new Float32Array(src.length);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let v = 0;
        for (let k = -radius; k <= radius; k++) {
          const sx = horizontal ? x + k : x, sy = horizontal ? y : y + k;
          if (sx >= 0 && sx < w && sy >= 0 && sy < h) v += src[sy * w + sx] * kernel[k + radius];
        }
        dst[y * w + x] = v / sum;
      }
    }
    return dst;
  };
  return pass(pass(mask, true), false);
}

// Draws the eye with its pupil centred on (cx, cy); `scale` is pixels per favicon unit.
function drawSigil(canvas, { cx, cy, scale, stroke = EYE_STROKE, glow = 0, samples = 8 }) {
  const map = poly => poly.map(([x, y]) => [cx + (x - 50) * scale, cy + (y - 36) * scale]);
  const eye = map(EYE), pupil = map(PUPIL);
  const hw = (stroke * scale) / 2;
  const box = (poly, pad) => [
    Math.min(...poly.map(p => p[0])) - pad, Math.min(...poly.map(p => p[1])) - pad,
    Math.max(...poly.map(p => p[0])) + pad, Math.max(...poly.map(p => p[1])) + pad,
  ];
  const pupilMask = canvas.mask((x, y) => insidePolygon(pupil, x, y), box(pupil, 1), samples);
  if (glow) canvas.paint(blur(pupilMask, canvas.w, canvas.h, glow * scale), ACCENT, 0.7);
  canvas.paint(canvas.mask((x, y) => distanceToPolyline(eye, x, y) <= hw, box(eye, hw + 1), samples), ACCENT);
  canvas.paint(pupilMask, ACCENT);
}

// One icon size: the dark rounded plate with a hairline rim, and the sigil on top.
// Small sizes get a heavier stroke and less margin so the eye stays readable.
function renderIcon(size) {
  const c = new Canvas(size, size);
  const inset = Math.round(size * 0.03);
  const plate = { x: inset, y: inset, w: size - 2 * inset, h: size - 2 * inset };
  plate.radius = (plate.w * BOX.radius) / BOX.size;
  const samples = size >= 128 ? 5 : 8;
  c.paint(c.mask((x, y) => roundedRectDistance(plate, x, y) <= 0, [0, 0, size, size], samples), BG);
  if (size >= 32) {
    const rim = Math.max(1, size / 128);
    c.paint(c.mask((x, y) => {
      const d = roundedRectDistance(plate, x, y);
      return d <= 0 && d > -rim;
    }, [0, 0, size, size], samples), RIM, size < 64 ? 0.6 : 1);
  }
  const stroke = size <= 16 ? 12 : size <= 24 ? 10.5 : size <= 32 ? 9.5 : EYE_STROKE;
  const fill = size <= 24 ? 1 : 0.94; // eye width as a share of the favicon's box
  drawSigil(c, {
    cx: size / 2,
    cy: size / 2,
    scale: (plate.w / BOX.size) * fill * (size <= 24 ? 1.08 : 1),
    stroke,
    glow: size >= 48 ? 5 : 0,
    samples,
  });
  return c;
}

// Installer artwork: the tall welcome-page panel and the small header mark.
function renderWizardImage(w, h) {
  const c = new Canvas(w, h);
  c.paint(new Float32Array(w * h).fill(1), BG);
  const scale = (w * 0.62) / 100;
  drawSigil(c, { cx: w / 2, cy: h * 0.42, scale, glow: 7, samples: 5 });
  return c;
}

function renderWizardSmall(size) {
  const c = new Canvas(size, size);
  drawSigil(c, { cx: size / 2, cy: size / 2, scale: (size * 0.86) / 100, stroke: size < 70 ? 9 : EYE_STROKE, glow: 4, samples: 6 });
  return c;
}

const CRC = new Int32Array(256).map((_, n) => {
  for (let k = 0; k < 8; k++) n = n & 1 ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
  return n;
});
function crc32(buf) {
  let c = -1;
  for (const b of buf) c = CRC[(c ^ b) & 255] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function png(canvas) {
  const { w, h } = canvas;
  const rgba = canvas.rgba();
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr.set([8, 6, 0, 0, 0], 8); // 8-bit RGBA
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// 32-bit DIB as stored in an ICO: bottom-up BGRA plus a 1-bit AND mask.
function dib(canvas) {
  const { w, h } = canvas;
  const rgba = canvas.rgba();
  const maskStride = Math.ceil(w / 32) * 4;
  const header = Buffer.alloc(40);
  header.writeUInt32LE(40, 0);
  header.writeInt32LE(w, 4);
  header.writeInt32LE(h * 2, 8);
  header.writeUInt16LE(1, 12);
  header.writeUInt16LE(32, 14);
  header.writeUInt32LE(w * h * 4 + maskStride * h, 20);
  const pixels = Buffer.alloc(w * h * 4);
  const mask = Buffer.alloc(maskStride * h);
  for (let y = 0; y < h; y++) {
    const row = h - 1 - y;
    for (let x = 0; x < w; x++) {
      const s = (y * w + x) * 4, d = (row * w + x) * 4;
      pixels[d] = rgba[s + 2];
      pixels[d + 1] = rgba[s + 1];
      pixels[d + 2] = rgba[s];
      pixels[d + 3] = rgba[s + 3];
      if (!rgba[s + 3]) mask[row * maskStride + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  return Buffer.concat([header, pixels, mask]);
}

function ico(images) {
  const header = Buffer.alloc(6 + 16 * images.length);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(images.length, 4);
  let offset = header.length;
  images.forEach(({ size, data }, i) => {
    const e = 6 + 16 * i;
    header[e] = size >= 256 ? 0 : size;
    header[e + 1] = size >= 256 ? 0 : size;
    header.writeUInt16LE(1, e + 4);
    header.writeUInt16LE(32, e + 6);
    header.writeUInt32LE(data.length, e + 8);
    header.writeUInt32LE(offset, e + 12);
    offset += data.length;
  });
  return Buffer.concat([header, ...images.map(i => i.data)]);
}

const sizes = [16, 24, 32, 48, 64, 128, 256];
const icons = sizes.map(size => ({ size, canvas: renderIcon(size) }));
// 256 is stored as PNG (as Windows' own icons are); smaller sizes as DIBs for older readers.
const iconFile = join(root, 'app', 'windows', 'runner', 'resources', 'app_icon.ico');
writeFileSync(iconFile, ico(icons.map(({ size, canvas }) => ({ size, data: size >= 256 ? png(canvas) : dib(canvas) }))));
console.log(`wrote ${iconFile}`);

// Inno Setup picks the closest size for the display's DPI (100%, 125%, 150%, 200%).
const installer = join(root, 'installer');
mkdirSync(installer, { recursive: true });
for (const [w, h, s] of [[164, 314, 100], [205, 393, 125], [246, 471, 150], [328, 628, 200]]) {
  writeFileSync(join(installer, `wizard-${s}.png`), png(renderWizardImage(w, h)));
}
for (const [size, s] of [[55, 100], [69, 125], [83, 150], [110, 200]]) {
  writeFileSync(join(installer, `wizard-small-${s}.png`), png(renderWizardSmall(size)));
}
console.log(`wrote ${installer}\\wizard-*.png`);

const preview = process.argv.indexOf('--preview');
if (preview > 0) {
  const dir = process.argv[preview + 1];
  mkdirSync(dir, { recursive: true });
  for (const { size, canvas } of icons) writeFileSync(join(dir, `icon-${size}.png`), png(canvas));
  console.log(`wrote previews to ${dir}`);
}
