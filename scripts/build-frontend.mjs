import { copyFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const srcDir = path.join(rootDir, 'src');
const distDir = path.join(rootDir, 'dist');
const files = ['index.html', 'app.js', 'styles.css'];

await mkdir(distDir, { recursive: true });

await Promise.all(
  files.map((fileName) => copyFile(path.join(srcDir, fileName), path.join(distDir, fileName)))
);

console.log(`Copied ${files.length} frontend files into dist/`);