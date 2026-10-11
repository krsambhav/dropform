import { build } from 'esbuild'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { execFileSync } from 'node:child_process'
await mkdir('dist', { recursive: true })
await build({ entryPoints: ['src/main.tsx'], bundle: true, minify: true, format: 'iife', target: 'safari16', outfile: 'dist/app.js', jsx: 'automatic' })
execFileSync('./node_modules/.bin/tailwindcss', ['-i', 'src/styles.css', '-o', 'dist/app.css', '--minify'], { stdio: 'inherit' })
const js = (await readFile('dist/app.js','utf8')).replaceAll('</script', '<\\/script')
const css = await readFile('dist/app.css','utf8')
await writeFile('dist/index.html', `<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src 'self'; connect-src 'none'"><title>Dropform</title><style>${css}</style></head><body><div id="root"></div><script>${js}</script></body></html>`)
console.log('Built offline workbench: ui/dist/index.html')
