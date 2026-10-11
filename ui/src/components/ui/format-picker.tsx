import * as React from 'react'
import { Popover } from 'radix-ui'
import { Check, ChevronsUpDown, Search } from 'lucide-react'
import { Button } from './button'

const descriptions: Record<string, string> = {
  epub: 'EPUB ebook', md: 'Markdown document', rst: 'reStructuredText document', xlsx: 'Excel workbook', xls: 'Excel 97–2003 workbook', pptx: 'PowerPoint presentation', ppt: 'PowerPoint 97–2003 presentation', jpg: 'JPEG image', png: 'PNG image', tiff: 'TIFF image', pdf: 'PDF document',
  docx: 'Word document', doc: 'Word 97–2003 document', txt: 'Plain text',
  rtf: 'Rich text document', html: 'Web page', odt: 'OpenDocument text',
  mp3: 'MP3 audio', mp4: 'MP4 video', webp: 'WebP image', heic: 'HEIC image',
}
export function FormatPicker({value, formats, disabled, name, onChange}: {
  value: string; formats: string[]; disabled?: boolean; name: string; onChange: (value: string) => void
}) {
  const [open, setOpen] = React.useState(false)
  const [query, setQuery] = React.useState('')
  const [active, setActive] = React.useState(0)
  const listId = React.useId()
  const filtered = formats.filter(format => `${format} ${descriptions[format] || ''}`.toLowerCase().includes(query.trim().toLowerCase()))
  React.useEffect(() => {
    if (open && filtered[active]) document.getElementById(`${listId}-${filtered[active]}`)?.scrollIntoView?.({block: 'nearest'})
  }, [active, query, open])
  function choose(format: string) { onChange(format); setOpen(false) }
  return <Popover.Root open={open} onOpenChange={next => { setOpen(next); setQuery(''); setActive(0) }}>
    <Popover.Trigger asChild><Button variant="outline" size="sm" disabled={disabled} role="combobox" aria-expanded={open} aria-controls={listId} aria-label={'Output format for ' + name} className="format-select">{value.toUpperCase()}<ChevronsUpDown size={12}/></Button></Popover.Trigger>
    <Popover.Portal><Popover.Content sideOffset={6} align="end" className="format-popover">
      <div className="format-search"><Search size={14}/><input autoFocus aria-label={'Search output formats for ' + name} role="combobox" aria-expanded="true" aria-controls={listId} aria-activedescendant={filtered[active] ? `${listId}-${filtered[active]}` : undefined} placeholder="Search formats…" value={query} onChange={e => { setQuery(e.target.value); setActive(0) }} onKeyDown={e => {
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); setActive(i => Math.max(0, Math.min(filtered.length - 1, i + (e.key === 'ArrowDown' ? 1 : -1)))) }
        if (e.key === 'Enter' && filtered[active]) { e.preventDefault(); choose(filtered[active]) }
      }}/></div>
      <div id={listId} role="listbox" aria-label="Output formats" className="format-results">
        {filtered.map((format, index) => <button key={format} id={`${listId}-${format}`} role="option" aria-selected={value === format} className={index === active ? 'active' : ''} onMouseMove={() => setActive(index)} onClick={() => choose(format)}><span><strong>{format.toUpperCase()}</strong><small>{descriptions[format] || format.toUpperCase() + ' format'}</small></span>{value === format && <Check size={14}/>}</button>)}
        {!filtered.length && <p>No matching formats</p>}
      </div>
    </Popover.Content></Popover.Portal>
  </Popover.Root>
}
