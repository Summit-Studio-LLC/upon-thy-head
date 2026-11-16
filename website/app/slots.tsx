import fs from "node:fs";
import path from "node:path";
import Image from "next/image";
import type { Content, ShotName } from "./content";

// A slot shows its picture if the file exists in public/, and a designed placeholder if not.
// Both fill the same box, so adding a picture changes nothing else on the page.

const EXTENSIONS = ["png", "jpg", "jpeg", "webp", "avif"];

function findPublic(base: string): string | null {
  for (const ext of EXTENSIONS) {
    if (fs.existsSync(path.join(process.cwd(), "public", `${base}.${ext}`))) return `/${base}.${ext}`;
  }
  return null;
}

export function Shot({ name, content, sizes }: { name: ShotName; content: Content; sizes: string }) {
  const src = findPublic(`shots/${name}`);
  const { label, alt } = content.shots[name];
  return (
    <figure className="shot">
      {src ? (
        <Image src={src} alt={alt} fill sizes={sizes} />
      ) : (
        <figcaption className="shot-empty">
          <span className="shot-light" aria-hidden="true" />
          {label}
        </figcaption>
      )}
    </figure>
  );
}

export function AppIcon({ content }: { content: Content }) {
  const src = findPublic("app-icon");
  return (
    <div className="app-icon">
      {src ? <Image src={src} alt="" fill sizes="88px" /> : <span>{content.close.iconLabel}</span>}
    </div>
  );
}
