export const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

async function decode(file: Blob): Promise<{ img: CanvasImageSource; w: number; h: number; done: () => void }> {
  if ("createImageBitmap" in window) {
    try {
      const bmp = await createImageBitmap(file, { imageOrientation: "from-image" });
      return { img: bmp, w: bmp.width, h: bmp.height, done: () => bmp.close() };
    } catch { /* fall back to <img> */ }
  }
  const url = URL.createObjectURL(file);
  const el = new Image();
  el.src = url;
  await el.decode();
  return { img: el, w: el.naturalWidth, h: el.naturalHeight, done: () => URL.revokeObjectURL(url) };
}

/**
 * Shrink a photo so its longest side is at most `max` px and encode it as WebP.
 * Older Safari can't encode WebP; then it falls back to JPEG (type tells you which).
 */
export async function resizePhoto(file: File, max = 1200): Promise<{ blob: Blob; type: "image/webp" | "image/jpeg"; ext: "webp" | "jpg" }> {
  const { img, w, h, done } = await decode(file);
  try {
    const scale = Math.min(1, max / Math.max(w, h));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(w * scale);
    canvas.height = Math.round(h * scale);
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("no canvas");
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    const toBlob = (type: string) => new Promise<Blob | null>((res) => canvas.toBlob(res, type, 0.82));
    const webp = await toBlob("image/webp");
    if (webp && webp.type === "image/webp") return { blob: webp, type: "image/webp", ext: "webp" };
    const jpg = await toBlob("image/jpeg");
    if (!jpg) throw new Error("encode failed");
    return { blob: jpg, type: "image/jpeg", ext: "jpg" };
  } finally {
    done();
  }
}
