import React, { useEffect, useState, useRef } from 'react'
import { createRoot } from 'react-dom/client'
import { ArrowDown, ArrowDownToLine, ArrowRight, ArrowUpRight, Check, CheckCheck, File, FileImage, FileText, Film, Folder, Grid2X2, Info, Layers2, Loader2, LockKeyhole, MoreHorizontal, Music2, Plus, Search, Settings2, ShieldCheck, Sparkles, Trash2, WandSparkles, X } from 'lucide-react'
import { Button } from './components/ui/button'
import { FormatPicker } from './components/ui/format-picker'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from './components/ui/select'
import { Switch } from './components/ui/switch'
import { Slider } from './components/ui/slider'
import { Tabs, TabsList, TabsTrigger } from './components/ui/tabs'
import { Checkbox } from './components/ui/checkbox'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from './components/ui/dropdown-menu'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from './components/ui/tooltip'

type Job = { previewBytes?: number | null; previewState?: string; quality?: number; outputBytes?: number | null; id: string; name: string; extension: string; size: string; format: string; status: string; error: string | null; output: boolean; formats: string[]; family: string; compressionSupported?: boolean }
type Family = { name: string; inputs: string[]; outputs: string[]; available: boolean; engine: string }
type State = { jobs: Job[]; running: boolean; cancelling: boolean; compress: boolean; maxDimension: number; stripMetadata: boolean; automaticBasket: boolean; destination: string; destinationPath: string; toolMessage: string | null; toolRunning: boolean; families: Family[] }
const initial: State = { jobs: [], running: false, cancelling: false, compress: false, maxDimension: 0, stripMetadata: false, automaticBasket: true, destination: 'Downloads', destinationPath: '', toolMessage: null, toolRunning: false, families: [] }
declare global { interface Window { webkit?: { messageHandlers: { dropform: { postMessage: (v: unknown) => void } } }; receiveState: (state: State) => void; setDragging: (value: boolean) => void } }
function send(action: string, values = {}) { window.webkit?.messageHandlers.dropform.postMessage({ action, ...values }) }
const icons: Record<string, React.ElementType> = { Images: FileImage, Video: Film, Audio: Music2, PDF: FileText, Documents: FileText }
const tools = [
  ['Merge PDFs', 'Bring multiple documents together, in filename order.', Layers2],
  ['Split PDF pages', 'Give every page a file of its own.', FileText],
  ['PDF to images', 'Export every page as a crisp PNG.', FileImage],
  ['Extract PDF text', 'Save selectable text as a plain text file.', FileText],
  ['Images to PDF', 'Collect your images in one document.', Grid2X2],
  ['Create ZIP', 'Package files and folders into one archive.', Folder],
] as const
export function App() {
  const [state, setState] = useState(initial)
  const [page, setPage] = useState('convert')
  const [dragging, setDragging] = useState(false)
  const [advanced, setAdvanced] = useState(false)
  const [search, setSearch] = useState('')
  const lastJobCount = useRef(0)
  useEffect(() => {
    if (state.jobs.length > lastJobCount.current) setPage('convert')
    lastJobCount.current = state.jobs.length
  }, [state.jobs.length])
  useEffect(() => {
    window.receiveState = setState; window.setDragging = setDragging; send('ready')
    const handler = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key === 'o') { event.preventDefault(); send('chooseFiles') }
      if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') { event.preventDefault(); send('convert') }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [])
  const setting = (key: string, value: unknown) => { setState(s => ({ ...s, [key]: value })); send('setting', { key, value }) }
  const busy = state.running || state.toolRunning
  const pending = state.jobs.filter(j => !j.output && j.status !== 'Unavailable' && (!state.compress || j.compressionSupported !== false))
  const finished = state.jobs.filter(j => j.output).length
  return <TooltipProvider delayDuration={250}><div className="app-shell">
    <aside className="sidebar">
      <div className="wordmark"><div className="brand-mark"><Layers2 size={19}/></div>dropform</div>
      <div className="sidebar-section-label">YOUR WORKSPACE</div>
      <nav aria-label="Workspace">
        {[['convert', 'Converter', ArrowRight], ['tools', 'File toolkit', WandSparkles], ['formats', 'Format library', Grid2X2]].map(([id, title, Icon]: any) => <button key={id} className={'nav-item ' + (page === id ? 'selected' : '')} onClick={() => setPage(id)}><Icon size={16}/><span>{title}</span>{page === id && <span className="nav-dot"/>}</button>)}
      </nav>
      <div className="sidebar-bottom">
        <div className="basket-setting"><div><span>Drop basket</span><Switch aria-label="Automatic drop basket" checked={state.automaticBasket} onCheckedChange={v => setting('automaticBasket', v)}/></div><p>Ready whenever you drag a file.</p><button className="text-link" onClick={() => send('showBasket')}>Show basket <ArrowUpRight size={12}/></button></div>
        <div className="local-note"><LockKeyhole size={14}/><div>Just you and your Mac.<span>Your files never get uploaded.</span></div></div>
        <div className="version">DROPFORM <span>0.1 · PERSONAL</span></div>
      </div>
    </aside>
    <main>
      <header><div><div className="eyebrow"><span/> ON-DEVICE WORKSPACE</div><h1>{page === 'convert' ? 'A new form for your files.' : page === 'tools' ? 'Small tools. Useful things.' : 'Find the right format.'}</h1><p>{page === 'convert' ? 'Convert, compress, and carry on.' : page === 'tools' ? 'Everyday file jobs, taken care of locally.' : 'Explore the formats your local engines can handle.'}</p></div><div className="header-actions"><Tooltip><TooltipTrigger asChild><Button variant="ghost" size="icon" aria-label="Show drop basket" onClick={() => send('showBasket')}><ArrowDownToLine size={18}/></Button></TooltipTrigger><TooltipContent>Show drop basket</TooltipContent></Tooltip><Button variant="outline" onClick={() => send('chooseFiles')}><Plus size={15}/> Add files</Button></div></header>
      {state.toolMessage && <div className="notice" role="status">{state.toolRunning ? <Loader2 className="animate-spin" size={15}/> : <Info size={15}/>}<span>{state.toolMessage}</span>{!state.toolRunning && <Button variant="ghost" size="icon" aria-label="Dismiss notification" onClick={() => send('dismissTool')}><X size={14}/></Button>}</div>}
      {page === 'convert' && <>
        <div className="mode-row"><Tabs value={state.compress ? 'compress' : 'convert'} onValueChange={v => setting('compress', v === 'compress')}><TabsList><TabsTrigger value="convert" disabled={busy}><ArrowRight size={14}/> Convert</TabsTrigger><TabsTrigger value="compress" disabled={busy}><ArrowDown size={14}/> Compress</TabsTrigger></TabsList></Tabs><span className="mode-hint">{state.compress ? 'Same format. Less baggage.' : 'Different format. New possibilities.'}</span></div>
        <button className={`dropzone ${state.jobs.length ? 'compact' : ''} ${dragging ? 'dragging' : ''}`} onClick={() => send('chooseFiles')} aria-label="Choose files or drop files here">
          {!state.jobs.length && <div className="file-art" aria-hidden="true"><div className="art-file art-one"><FileImage size={20}/><span>JPG</span></div><div className="art-file art-two"><Film size={21}/><span>MOV</span></div><div className="art-file art-three"><FileText size={21}/><span>PDF</span></div><div className="art-arrow"><ArrowDown size={19}/></div></div>}
          <div className="drop-copy">{state.jobs.length > 0 && <Plus size={19}/>}<h2>{dragging ? 'Let go. We’ve got it.' : state.jobs.length ? 'Drop more files here' : 'A little drop goes a long way.'}</h2><p>{state.jobs.length ? 'or click to browse' : 'Drop your files here, or click to browse.'}</p></div>
          {!state.jobs.length && <div className="format-hints"><span>IMAGES</span><span>VIDEO</span><span>AUDIO</span><span>DOCUMENTS</span><span>+ MORE</span></div>}
        </button>
        {state.jobs.length === 0 ? <div className="empty-footer"><span><ShieldCheck size={14}/> Originals stay untouched</span><span><Layers2 size={14}/> One file or a whole batch</span><kbd>⌘ O</kbd></div> : <section className="queue" aria-label="Conversion queue"><div className="queue-heading"><span>{state.jobs.length} FILE{state.jobs.length > 1 ? 'S' : ''} IN YOUR WORKSPACE</span><Button variant="ghost" size="sm" disabled={!finished || busy} onClick={() => send('clearFinished')}><CheckCheck size={13}/> Clear finished</Button></div><div className="queue-scroll">{state.jobs.map(job => {
          const Icon = icons[job.family] || File
          return <div className="file-card" key={job.id}><div className="file-row"><div className={'file-badge ' + (job.output ? 'complete' : '')}>{job.output ? <Check size={20}/> : <Icon size={20}/>}</div><div className="file-details"><strong title={job.name}>{job.name}</strong><span className={job.error ? 'text-destructive' : ''}>{job.status === 'Ready' ? state.compress && job.compressionSupported === false ? 'Compression unavailable · use Convert instead' : job.size + ' · Ready to ' + (state.compress ? 'compress' : 'convert') : job.status}</span>{job.error && <details className="error-detail"><summary>View details</summary><p>{job.error}</p></details>}</div>{job.status === 'Converting' ? <Loader2 className="animate-spin text-primary" size={18}/> : job.output ? <Button variant="outline" size="sm" onClick={() => send('reveal', { id: job.id })}><Folder size={14}/> Show file</Button> : <><ArrowRight size={14} className="row-arrow"/>{state.compress ? <span className="keep-format">{job.extension.toUpperCase()}</span> : job.formats.length > 0 && <FormatPicker value={job.format} formats={job.formats} disabled={busy} name={job.name} onChange={format => send('format', { id: job.id, format })}/>}</>}<Button variant="ghost" size="icon" disabled={busy} aria-label={'Remove ' + job.name} onClick={() => send('remove', { id: job.id })}><X size={14}/></Button></div>{job.family === 'PDF' && !state.compress && <p className="pdf-route-note">{['png','jpg','webp','tiff','bmp'].includes(job.format) ? 'Every page is exported. Multipage PDFs save into a folder.' : ['docx','doc','odt','rtf','html','txt'].includes(job.format) ? 'Exports selectable text. Complex layouts and images are not preserved; scanned pages require OCR.' : 'Recompresses the PDF while retaining its pages.'}</p>}{job.family === 'Video' && ['png','jpg','webp'].includes(job.format) && <p className="pdf-route-note">Exports the first video frame as an image.</p>}{['Documents','Spreadsheets','Presentations','Ebooks & markup'].includes(job.family) && ['png','jpg','webp','tiff','bmp'].includes(job.format) && <p className="pdf-route-note">Exports every rendered page or slide. Multiple pages save into a folder.</p>}{job.family === 'Email' && <p className="pdf-route-note">Exports headers and readable message text. Attachments are listed, not extracted.</p>}<div className="file-settings">{(['Images', 'Video', 'Audio'].includes(job.family) || (job.family === 'PDF' && (state.compress || ['pdf','jpg'].includes(job.format)))) && <div className="quality-control"><label>QUALITY <span>{job.quality ?? 90}%</span></label><Slider aria-label={'Quality for ' + job.name} value={[job.quality ?? 90]} min={40} max={100} step={5} disabled={busy || job.output} onValueChange={v => { setState(s => ({...s, jobs: s.jobs.map(j => j.id === job.id ? {...j, quality: v[0], previewBytes: null, previewState: 'Calculating…'} : j)})); send('quality', {id: job.id, value: v[0]}) }}/></div>}<div className="file-size"><span>Original <strong>{job.size}</strong></span><ArrowRight size={12}/><span>{job.output ? 'Converted' : job.status === 'Converting' ? 'Written so far' : job.previewBytes != null ? job.previewState || 'Live preview' : 'Output'} <strong>{(job.outputBytes ?? job.previewBytes) != null ? new Intl.NumberFormat(undefined, {maximumFractionDigits: 1}).format((job.outputBytes ?? job.previewBytes)! / ((job.outputBytes ?? job.previewBytes)! >= 1000000 ? 1000000 : 1000)) + ((job.outputBytes ?? job.previewBytes)! >= 1000000 ? ' MB' : ' KB') : job.status === 'Converting' ? 'Measuring…' : job.previewState || 'Available after conversion'}</strong></span></div></div></div>
        })}</div></section>}
        <div className="workspace-spacer"/>
        <div className="options-block"><button className="options-toggle" aria-expanded={advanced} onClick={() => setAdvanced(!advanced)}><Settings2 size={14}/> Fine-tune your files <span>{advanced ? '−' : '+'}</span></button>{advanced && <div className="advanced-options"><div><label>Maximum dimension</label><Select value={String(state.maxDimension)} disabled={busy} onValueChange={v => setting('maxDimension', Number(v))}><SelectTrigger aria-label="Maximum dimension"><SelectValue/></SelectTrigger><SelectContent>{[[0, 'Keep original size'], [3840, '3840 px · 4K'], [1920, '1920 px · Full HD'], [1280, '1280 px · HD'], [640, '640 px · Compact']].map(([v,l]) => <SelectItem key={v} value={String(v)}>{l}</SelectItem>)}</SelectContent></Select></div><label className="checkbox-label"><Checkbox checked={state.stripMetadata} disabled={busy} onCheckedChange={v => setting('stripMetadata', v === true)}/><span>Remove metadata<small>Images, audio, and video</small></span></label><p>Resizing applies to images and video. Quality controls apply to image, media, and PDF output.</p></div>}</div>
        <footer><div className="destination"><label>SAVE TO</label><Tooltip><TooltipTrigger asChild><button onClick={() => send('chooseFolder')} disabled={busy}><Folder size={16}/><span>{state.destination}</span><MoreHorizontal size={14}/></button></TooltipTrigger><TooltipContent>{state.destinationPath || 'Choose an output folder'}</TooltipContent></Tooltip></div>{state.running ? <Button variant="outline" disabled={state.cancelling} onClick={() => send('cancel')}><Loader2 size={15} className="animate-spin"/>{state.cancelling ? 'Stopping…' : 'Cancel conversion'}</Button> : <Button className="convert-button" disabled={!pending.length || busy} onClick={() => send('convert')}>{state.compress ? 'Compress' : 'Convert'}{pending.length > 1 ? ` ${pending.length} files` : ' file'}<ArrowUpRight size={16}/></Button>}</footer>
      </>}
      {page === 'tools' && <div className="tools-list">{tools.map(([name, description, Icon]) => <button key={name} disabled={busy} onClick={() => send('tool', { name })}><span className="tool-icon"><Icon size={23}/></span><div><h2>{name}</h2><p>{description}</p></div><ArrowUpRight size={18}/></button>)}<p className="footnote">Results are saved in your selected output folder. PDF tools require unlocked documents; text extraction requires selectable text.</p></div>}
      {page === 'formats' && <div className="library"><div className="search-field"><Search size={16}/><input aria-label="Search formats" placeholder="Search formats, like HEIC, MP4, or PDF…" value={search} onChange={e => setSearch(e.target.value)}/>{search && <button aria-label="Clear search" onClick={() => setSearch('')}><X size={14}/></button>}</div><div className="library-scroll">{state.families.filter(f => [f.name,...f.inputs,...f.outputs].join(' ').toLowerCase().includes(search.toLowerCase())).map(f => <section key={f.name}><div><h2>{f.name}</h2><span className={'engine-status ' + (f.available ? '' : 'missing')}><span/>{f.available ? 'Engine available' : 'Engine missing'}</span></div><label>CONVERT FROM</label><p>{f.inputs.map(v => v.toUpperCase()).join(' · ')}</p><label>CONVERT TO</label><div className="format-tags">{f.outputs.map(v => <span key={v}>{v.toUpperCase()}</span>)}</div></section>)}<p className="footnote">Codec support depends on the installed engine and source file. MSG email conversion, OCR, vector tracing, and archive extraction are not available yet.</p></div></div>}
    </main>
  </div></TooltipProvider>
}
const root = document.getElementById('root'); if (root) createRoot(root).render(<App/>)
