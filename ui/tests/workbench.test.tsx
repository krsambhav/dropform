// @vitest-environment jsdom
import React from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { App } from '../src/main'
vi.stubGlobal("ResizeObserver", class { observe() {} unobserve() {} disconnect() {} })
const postMessage = vi.fn()
const base = { jobs: [], running:false, cancelling:false, compress:false, quality:90, maxDimension:0, stripMetadata:false, automaticBasket:true, destination:'Test folder', destinationPath:'/tmp/test', toolMessage:null, toolRunning:false, families:[{name:'Images',inputs:['png','heic'],outputs:['png','jpg'],available:true,engine:'magick'},{name:'Audio',inputs:['wav'],outputs:['mp3'],available:true,engine:'ffmpeg'}] }
const file = {id:'fixture-1', name:'photo.png', extension:'png', size:'4 MB', format:'jpg',status:'Ready',error:null,output:false,formats:['png','jpg'],family:'Images'}
function publish(values = {}) { act(() => window.receiveState({...base, ...values})) }
beforeEach(() => { window.webkit = { messageHandlers:{dropform:{postMessage}} }; postMessage.mockClear(); render(<App/>); publish() })
afterEach(cleanup)
describe('Workbench', () => {
 it('requests native state and disables empty conversion', () => { expect(postMessage).toHaveBeenCalledWith({action:'ready'}); expect((screen.getByRole('button',{name:'Convert file'}) as HTMLButtonElement).disabled).toBe(true) })
 it('routes file and directory selection through the bridge', () => { fireEvent.click(screen.getByRole('button',{name:'Add files'})); expect(postMessage).toHaveBeenLastCalledWith({action:'chooseFiles'}); fireEvent.click(screen.getByRole('button',{name:'Test folder'})); expect(postMessage).toHaveBeenLastCalledWith({action:'chooseFolder'}) })
 it('converts a queued file and removes by ID', () => { publish({jobs:[file]}); fireEvent.click(screen.getByRole('button',{name:'Convert file'})); expect(postMessage).toHaveBeenLastCalledWith({action:'convert'}); fireEvent.click(screen.getByRole('button',{name:'Remove photo.png'})); expect(postMessage).toHaveBeenLastCalledWith({action:'remove',id:'fixture-1'}) })
 it('locks conversion controls during processing and allows cancellation', () => { publish({jobs:[{...file,status:'Converting'}],running:true}); expect((screen.getByRole('button',{name:'Remove photo.png'}) as HTMLButtonElement).disabled).toBe(true); fireEvent.click(screen.getByRole('button',{name:'Cancel conversion'})); expect(postMessage).toHaveBeenLastCalledWith({action:'cancel'}) })
 it('reveals a completed output without accepting a raw file path', () => { publish({jobs:[{...file,output:true,status:'Done · 50% smaller'}]}); fireEvent.click(screen.getByRole('button',{name:'Show file'})); expect(postMessage).toHaveBeenLastCalledWith({action:'reveal',id:'fixture-1'}) })
 it('filters the available format library', () => { fireEvent.click(screen.getByRole('button',{name:'Format library'})); fireEvent.change(screen.getByRole('textbox',{name:'Search formats'}),{target:{value:'heic'}}); expect(screen.getByRole('heading',{name:'Images'})).toBeTruthy(); expect(screen.queryByRole('heading',{name:'Audio'})).toBeNull() })
 it('routes tool actions by allowlisted name', () => { fireEvent.click(screen.getByRole('button',{name:'File toolkit'})); fireEvent.click(screen.getByRole('button',{name:/Merge PDFs/})); expect(postMessage).toHaveBeenLastCalledWith({action:'tool',name:'Merge PDFs'}) })
 it('switches back to the converter when a file arrives', () => { fireEvent.click(screen.getByRole('button',{name:'File toolkit'})); publish({jobs:[file]}); expect(screen.getByText('photo.png')).toBeTruthy() })
 it('renders hostile filenames as text', () => { publish({jobs:[{...file,name:'<img src=x onerror=alert(1)>.png'}]}); expect(document.querySelector('img')).toBeNull(); expect(screen.getByText('<img src=x onerror=alert(1)>.png')).toBeTruthy() })
 it('shows actionable errors and supports retry', () => { publish({jobs:[{...file,status:'Failed',error:'The source could not be decoded.'}]}); expect(screen.getByText('The source could not be decoded.')).toBeTruthy(); expect((screen.getByRole('button',{name:'Convert file'}) as HTMLButtonElement).disabled).toBe(false) })
 it('supports the native open keyboard shortcut', () => { fireEvent.keyDown(window,{key:'o',metaKey:true}); expect(postMessage).toHaveBeenLastCalledWith({action:'chooseFiles'}) })
 it('uses compression mode without offering unsupported inputs', () => { publish({compress:true,jobs:[{...file,compressionSupported:false}]}); expect((screen.getByRole('button',{name:'Compress file'}) as HTMLButtonElement).disabled).toBe(true); expect(screen.getByText('Compression unavailable · use Convert instead')).toBeTruthy() })
 it('updates metadata removal through the native bridge', () => { fireEvent.click(screen.getByRole('button',{name:/Fine-tune your files/})); fireEvent.click(screen.getByRole('checkbox',{name:/Remove metadata/})); expect(postMessage).toHaveBeenLastCalledWith({action:'setting',key:'stripMetadata',value:true}) })
 it('toggles automatic basket preference', () => { fireEvent.click(screen.getByRole('switch',{name:'Automatic drop basket'})); expect(postMessage).toHaveBeenLastCalledWith({action:'setting',key:'automaticBasket',value:false}) })

})

it('shows quality only after adding a supported file and scopes changes to that file', () => {
 expect(screen.queryByRole('slider')).toBeNull()
 publish({jobs:[{...file,quality:80},{...file,id:'second',name:'second.png',quality:60}]})
 const slider = screen.getByRole('slider',{name:'Quality for photo.png'})
 fireEvent.keyDown(slider,{key:'ArrowRight'})
 expect(postMessage).toHaveBeenLastCalledWith({action:'quality',id:'fixture-1',value:85})
 expect(screen.getByRole('slider',{name:'Quality for second.png'}).getAttribute('aria-valuenow')).toBe('60')
})
it('shows live output bytes then the final converted size', () => {
 publish({jobs:[{...file,status:'Converting',outputBytes:125000}],running:true})
 expect(screen.getByText('Written so far')).toBeTruthy()
 expect(screen.getByText('125 KB')).toBeTruthy()
 publish({jobs:[{...file,status:'Done',output:true,outputBytes:250000}]})
 expect(screen.getByText('Converted')).toBeTruthy()
 expect(screen.getByText('250 KB')).toBeTruthy()
 expect(screen.queryByText('Written so far')).toBeNull()
})
it('explains multipage PDF images and text-only Word conversion', () => {
 const pdf = {...file, name:'pages.pdf',family:'PDF',extension:'pdf',formats:['png','jpg','docx','doc','pdf'],format:'png'}
 publish({jobs:[pdf]})
 expect(screen.getByText('Every page is exported. Multipage PDFs save into a folder.')).toBeTruthy()
 expect(screen.queryByRole('slider')).toBeNull()
 publish({jobs:[{...pdf,format:'docx'}]})
 expect(screen.getByText(/Exports selectable text/)).toBeTruthy()
})
it('searches format names and selects Word using the keyboard', () => {
 publish({jobs:[{...file,formats:['png','jpg','docx'],format:'png'}]})
 fireEvent.click(screen.getByRole('combobox',{name:'Output format for photo.png'}))
 const search = screen.getByRole('combobox',{name:'Search output formats for photo.png'})
 fireEvent.change(search,{target:{value:'word'}})
 expect(screen.queryByRole('option',{name:/JPEG/})).toBeNull()
 expect(screen.getByRole('option',{name:/Word document/})).toBeTruthy()
 fireEvent.keyDown(search,{key:'Enter'})
 expect(postMessage).toHaveBeenLastCalledWith({action:'format',id:'fixture-1',format:'docx'})
})
it('shows actual live preview size before saving a conversion', () => {
 publish({jobs:[{...file,previewBytes:123000,previewState:'Live preview'}]})
 expect(screen.getByText('Live preview')).toBeTruthy()
 expect(screen.getByText('123 KB')).toBeTruthy()
 expect((screen.getByRole('button',{name:'Convert file'}) as HTMLButtonElement).disabled).toBe(false)
 publish({jobs:[{...file,previewBytes:null,previewState:'Calculating…'}]})
 expect(screen.queryByText('123 KB')).toBeNull()
 expect(screen.getByText('Calculating…')).toBeTruthy()
})
it('opens the ready live preview by job id and disables it during recalculation', () => {
 publish({jobs:[{...file,previewAvailable:true,previewBytes:123000,previewState:'Live preview'}]})
 fireEvent.click(screen.getByRole('button',{name:'Open live preview for photo.png'}))
 expect(postMessage).toHaveBeenLastCalledWith({action:'preview',id:'fixture-1'})
 publish({jobs:[{...file,previewAvailable:false,previewState:'Calculating…'}]})
 expect((screen.getByRole('button',{name:'Open live preview for photo.png'}) as HTMLButtonElement).disabled).toBe(true)
})
it('defaults Open at login on and sends changes through the native bridge', () => {
 fireEvent.click(screen.getByRole('button',{name:'Settings'}))
 const toggle = screen.getByRole('switch',{name:'Open at login'})
 expect(toggle.getAttribute('aria-checked')).toBe('true')
 fireEvent.click(toggle)
 expect(postMessage).toHaveBeenLastCalledWith({action:'setting',key:'openAtLogin',value:false})
 publish({openAtLogin:true,loginNeedsApproval:true})
 fireEvent.click(screen.getByRole('button',{name:'Open Login Items'}))
 expect(postMessage).toHaveBeenLastCalledWith({action:'loginSettings'})
})
