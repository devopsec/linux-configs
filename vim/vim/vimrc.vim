" Disable vi compatibility settings
set nocompatible

" Disable terminal capability queries that can leak their raw escape
" responses onto the screen before the first redraw happens (a version/DA
" query and OSC 10/11 foreground/background color queries -- these show up
" as garbage like "^[[2;2R^[[>61;8400;1c^[]10;rgb:...^G^[]11;rgb:...^G" that
" overwrites the bottom rows, including the airline status bar, until a
" keypress forces a redraw). None of these queries are needed since the
" colorscheme/background below are set explicitly.
set t_RV=
if exists('&t_u7')
    set t_u7=
endif
if exists('&t_RF')
    set t_RF=
endif
if exists('&t_RB')
    set t_RB=
endif

" Hide Vim's native statusline row entirely. Airline keeps computing its
" statusline text in the background (it only checks g:airline_disable_
" statusline, not &laststatus -- see airline#util#stl_disabled()), and
" XVimRenderStatusPopup() below paints that text into a popup pinned to
" the last screen row instead, reclaiming the row that used to sit blank
" between the statusline and the command line.
set laststatus=0


" |==================== vim-plug plugin manager config ==================|
"
" Check for vim-plug installation and download if not present
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  let g:plug_bootstrap = 1
endif

call plug#begin('~/.vim/plugged')

" Vim plugins managed by vim-plug
Plug 'inkarkat/vim-ingo-library'      " Useful vimscript functions
"Plug 'itchyny/lightline.vim'          " Lightline minimal statusbar
Plug 'vim-airline/vim-airline'        " Vim-airline improved statusbar
Plug 'ap/vim-css-color'               " CSS color previews shown
Plug 'powerman/vim-plugin-ansiesc'    " Highlight/Conceal ANSI escape seqs
Plug 'sheerun/vim-polyglot'           " All mainstream languages syntax +more
Plug 'kamailio/vim-kamailio-syntax'   " Kamailio config syntax highlighting
Plug 'devopsec/vim-opensips-syntax'   " opensips config syntax highlighting
"Plug 'jacoborus/tender.vim'           " Tender 24bit Color Scheme
Plug 'joshdick/onedark.vim'           " Onedark 24bit Color Scheme
"Plug 'morhetz/gruvbox'               " GruvBox 24bit Color Scheme
Plug 'ryanoasis/vim-devicons'         " NerdFont icons
Plug 'Konfekt/vim-alias'              " Simplified command aliasing
Plug 'PanagiotisS/LargeFile'          " Improved performance for large files

call plug#end()
filetype plugin indent on

" Automatically install plugins if vim-plug was just bootstrapped
if exists('g:plug_bootstrap')
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" vim-plug commands
"   :PlugInstall            - install plugins
"   :PlugUpdate             - install or update plugins
"   :PlugUpgrade            - upgrade vim-plug itself
"   :PlugStatus             - check the status of plugins
"   :PlugClean              - remove unlisted plugins
"   :PlugDiff               - examine changes from the previous update
"
" vim-plug references
"   :help plug              - vim-plug vimdocs
"   github                  - https://github.com/junegunn/vim-plug
"
" |======================================================================|


" |======================== Command Aliases =============================|
"
" Vim-alias commands
"   :Alias[!] [-range] [-buffer] <lhs> <rhs>    - create an alias
"   :UnAlias [-buffer] <lhs> ...                - remove an alias
"   :Aliases [-buffer] [lhs] ...                - list aliases
"
" Vim-alias references
"   :help alias         - Vim-alias vimdocs
"   github              - https://github.com/Konfekt/vim-alias
"
function! LoadCommandLineAliases()
    " Define command-line aliases here
    " Note that spaces in <rhs> must be escaped
    Alias           man     Man
    Alias           term    vsplit|terminal
    Alias           hterm   split|terminal
    Alias -range    tab     $tabnew
    Alias           qq      tabclose
endfunction

if exists('s:loaded_vimafter')
    silent doautocmd VimAfter VimEnter *
else
    let s:loaded_vimafter = 1
    augroup VimAfter
        autocmd!
        autocmd VimEnter * :call LoadCommandLineAliases()
    augroup END
endif
"
" |======================================================================|


" |======================== Utility Functions ===========================|
"
" Summary:  check if current window has neighboring window
" Args:     direction (1==Top|2==Right|3==Bottom|4==Left)
" Return:   1==True|0==False
function! HasNeighbor(direction)
    " Position of the current window
    let currentPosition = win_screenpos(winnr())

    if a:direction == 1
        " if we are looking for a top neigbour simply test if we are on the first line
        return currentPosition[0] != 1
    elseif a:direction == 4
        " if we are looking for a left neigbour simply test if we are on the first column
        return currentPosition[1] != 1
    endif

    " Number of windows on the screen
    let winNr = winnr('$')

    while winNr > 0
        " Get the position of each window
        let position = win_screenpos(winNr)
        let winNr = winNr - 1

        " Test for window on the right
        if ( a:direction == 2 && ( currentPosition[1] + winwidth(0) ) < position[1] )
            return 1
        " Test for windo on the bottom
        elseif ( a:direction == 3 && ( currentPosition[0] + winheight(0) ) < position[0] )
            return 1
        endif
    endwhile
endfunction

" Return indent (all whitespace at start of a line), converted from
" tabs to spaces if what = 1, or from spaces to tabs otherwise.
" When converting to tabs, result has no redundant spaces.
function! Indenting(indent, what, cols)
  let spccol = repeat(' ', a:cols)
  let result = substitute(a:indent, spccol, '\t', 'g')
  let result = substitute(result, ' \+\ze\t', '', 'g')
  if a:what == 1
    let result = substitute(result, '\t', spccol, 'g')
  endif
  return result
endfunction

" Convert whitespace used for indenting (before first non-whitespace).
" what = 0 (convert spaces to tabs), or 1 (convert tabs to spaces).
" cols = string with number of columns per tab, or empty to use 'tabstop'.
" The cursor position is restored, but the cursor will be in a different
" column when the number of characters in the indent of the line is changed.
function! IndentConvert(line1, line2, what, cols)
  let savepos = getpos('.')
  let cols = empty(a:cols) ? &tabstop : a:cols
  execute a:line1 . ',' . a:line2 . 's/^\s\+/\=Indenting(submatch(0), a:what, cols)/e'
  call histdel('search', -1)
  call setpos('.', savepos)
endfunction

command! -nargs=? -range=% Space2Tab call IndentConvert(<line1>,<line2>,0,<q-args>)
command! -nargs=? -range=% Tab2Space call IndentConvert(<line1>,<line2>,1,<q-args>)
command! -nargs=? -range=% RetabIndent call IndentConvert(<line1>,<line2>,&et,<q-args>)
"
" |======================================================================|


" |===================== General Configurations =========================|
"
" Backspace modification
set backspace=indent,eol,start

" Let statusline display mode,ruler,cmd,filename
set noshowmode
set noruler
set noshowcmd
set shortmess+=F
set cmdheight=1

" Disable audio bell on error
set noerrorbells

" Share the system clipboard w/ vim
set clipboard+=unnamedplus

" Show line numbers in a themed gutter, separate from the editor body
set number
set numberwidth=4

" Match neovim's default per-mode cursor shapes (block in normal/visual/
" select, vertical bar in insert/cmdline/visual-exclusive, horizontal bar
" in replace/cmdline-replace/operator-pending) so both editors look the same.
set guicursor=n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20,sm:block-blinkwait175-blinkoff150-blinkon175

" 'guicursor' only applies to GUI vims; terminal vim needs DECSCUSR escapes:
" steady block normally, steady bar in insert, steady underline in replace,
" and a bar while editing inside the cmdline text (block again at the end).
if !has('nvim') && !has('gui_running')
    let &t_SI = "\e[6 q"
    let &t_SR = "\e[4 q"
    let &t_EI = "\e[2 q"

    function! XVimCmdCursor(key) abort
        let l:pos = getcmdpos()
        let l:end = strlen(getcmdline()) + 1
        if a:key ==# 'left' || a:key ==# 'home'
            let l:bar = 1
        elseif a:key ==# 'right'
            let l:bar = (l:pos + 1 < l:end)
        else
            let l:bar = 0
        endif
        call echoraw(l:bar ? "\e[6 q" : "\e[2 q")
        return ''
    endfunction

    cnoremap <expr> <Left>  XVimCmdCursor('left')  . "\<Left>"
    cnoremap <expr> <Right> XVimCmdCursor('right') . "\<Right>"
    cnoremap <expr> <Home>  XVimCmdCursor('home')  . "\<Home>"
    cnoremap <expr> <End>   XVimCmdCursor('end')   . "\<End>"

    augroup xvim_term_cursor
        autocmd!
        autocmd VimEnter,CmdlineEnter,CmdlineLeave * call echoraw("\e[2 q")
        autocmd VimLeave * call echoraw("\e[0 q")
    augroup END
endif

" Show matching brackets
set showmatch

" Do smart case matching on searches
set smartcase

" Default tab settings when syntax does not override
set tabstop=4      " A TAB character looks like 4 spaces
set shiftwidth=4   " Number of spaces for auto-indent (<< and >>)
set softtabstop=4  " Number of spaces inserted when you hit TAB
set expandtab      " Convert TABs to spaces

" Turn off mouse support, it just gets in the way
set mouse=""

" Default split created below / right
set splitbelow splitright

" Make splits auto resize when host resizes
autocmd VimResized * wincmd =

" Use a visible box-drawing separator between vertical splits
set fillchars+=vert:┃

" Make sure we can show icons
set encoding=UTF-8

"
" |======================================================================|


" |================== Configure plugins / Colors ========================|

" LargeFile Plugin Settings
" minimum file size (in MB) to trigger optimizations
let g:LargeFile = 1

" Enable 24bit True Color
if (empty($TMUX))
    " For Neovim 0.1.3 and 0.1.4 < https://github.com/neovim/neovim/pull/2198 >
    if (has("nvim"))
        let $NVIM_TUI_ENABLE_TRUE_COLOR=1
    endif
    " For Neovim > 0.1.5 and Vim > patch 7.4.1799 < https://github.com/vim/vim/commit/61be73bb0f965a895bfb064ea3e55476ac175162 >
    " Based on Vim patch 7.4.1770 (`guicolors` option) < https://github.com/vim/vim/commit/8a633e3427b47286869aa4b96f2bfc1fe65b25cd >
    " < https://github.com/neovim/neovim/wiki/Following-HEAD#20160511 >
    if (has("termguicolors"))
        set termguicolors
    endif
endif

" Correct RGB escape codes for vim inside tmux/screen
" TODO: doesn't seem to be working
if !has('nvim') && $TERM ==# 'screen-256color'
    let &t_8f = "\e[38;2;%lu;%lu;%lum"
    let &t_8b = "\e[48;2;%lu;%lu;%lum"
    "let &t_8f = "\e[38;2;%ld;%ld;%ldm"
    "let &t_8b = "\e[48;2;%ld;%ld;%ldm"
endif

" Enable syntax highlighting
if (!exists("g:syntax_on"))
    syntax enable
endif

" Set vim color scheme
colorscheme onedark

" Configure lightline status bar
let g:lightline = { 
    \   'colorscheme': 'onedark',
    \   'active': {
    \       'left': [ [ 'mode', 'paste'], ['readonly', 'filename', 'modified' ] ]
    \   },
    \   'component_function': {
    \       'filename': 'LightlineFilename',
    \   },
    \ }

function! LightlineFilename()
    return &filetype ==# 'vimfiler' ? vimfiler#get_status_string() :
        \ &filetype ==# 'unite' ? unite#get_status_string() :
        \ &filetype ==# 'vimshell' ? vimshell#get_status_string() :
        \ expand('%:t') !=# '' ? expand('%:t') : '[No Name]'
endfunction

let g:unite_force_overwrite_statusline = 0
let g:vimfiler_force_overwrite_statusline = 0
let g:vimshell_force_overwrite_statusline = 0

" Center common command-line interactions in a lightweight popup. Vim cannot
" hide its native command line row, so this keeps that row available for
" messages while moving the interactive prompt out of the way.
let s:xvim_popup = {}

" Vim's popup windows are never focusable, so there is no real terminal
" text cursor to place inside them (popup_setcursor() does not exist).
" Fake a block cursor instead by highlighting the character at the cursor
" position with a text property; a trailing space is always appended so
" there is still something to highlight when the cursor sits at the end.
let s:xvim_cursor_prop_ready = 0

function! XVimPopupEnsureCursorProp() abort
    if s:xvim_cursor_prop_ready || !exists('*prop_type_add')
        return
    endif
    " Guard with a flag instead of relying on 'silent!' to hide the
    " "already defined" error: that error still gets echoed to the
    " message history (and briefly onto the screen) even when silenced.
    try
        call prop_type_add('XVimCursor', {'highlight': 'Cursor'})
    catch
    endtry
    let s:xvim_cursor_prop_ready = 1
endfunction

function! XVimPopupRenderCursor() abort
    if empty(s:xvim_popup) || !exists('*prop_add')
        return
    endif
    let l:bufnr = winbufnr(s:xvim_popup.id)
    if l:bufnr <= 0
        return
    endif
    call XVimPopupEnsureCursorProp()
    silent! call prop_remove({'type': 'XVimCursor', 'bufnr': l:bufnr}, 1)
    let l:col = strlen(s:xvim_popup.prompt) + byteidx(s:xvim_popup.value, s:xvim_popup.cursor) + 1
    call prop_add(1, l:col, {'type': 'XVimCursor', 'length': 1, 'bufnr': l:bufnr})
endfunction

function! XVimPopupRender() abort
    if empty(s:xvim_popup) || !exists('*popup_settext')
        return
    endif
    let l:text = s:xvim_popup.prompt . s:xvim_popup.value . ' '
    call popup_settext(s:xvim_popup.id, [l:text])
    call XVimPopupRenderCursor()
endfunction

function! XVimPopupClose() abort
    let l:had_popup = !empty(s:xvim_popup)
    if l:had_popup && exists('*popup_close')
        silent! call popup_close(s:xvim_popup.id)
    endif
    let s:xvim_popup = {}
    call XVimPopupMenuHide()
endfunction

function! XVimPopupAccept() abort
    if empty(s:xvim_popup)
        return
    endif
    let l:prefix = s:xvim_popup.prefix
    let l:value = s:xvim_popup.value
    let l:history = s:xvim_popup.history
    call XVimPopupClose()

    if empty(l:value)
        return
    endif

    call histadd(l:history, l:value)
    try
        if l:prefix ==# ':'
            execute l:value
        else
            call setreg('/', l:value)
            call search(l:value, l:prefix ==# '?' ? 'b' : '')
        endif
    catch
        if exists('*XVimShowMessage')
            call XVimShowMessage(v:exception)
        endif
    endtry
    if exists('*XVimScheduleUiRefresh')
        call XVimScheduleUiRefresh()
    endif
    " Show command/search output immediately instead of waiting on the poll
    " timer (search failures like "E486: Pattern not found" land here too).
    if exists('*XVimPollMessagesNow')
        call XVimPollMessagesNow()
    endif
endfunction

" Tab-complete the last word of the command line, cycling through matches
" like native wildmenu completion, with a small popup menu (attached below
" the command popup) listing the candidates so the current match is visible
" at a glance instead of only flashing in the input line.
let s:xvim_popup_menu_id = -1
let s:xvim_popup_menu_prop_ready = 0

function! XVimPopupMenuEnsureProp() abort
    if s:xvim_popup_menu_prop_ready || !exists('*prop_type_add')
        return
    endif
    try
        call prop_type_add('XVimPmenuSel', {'highlight': 'PmenuSel'})
    catch
    endtry
    let s:xvim_popup_menu_prop_ready = 1
endfunction

function! XVimPopupMenuHide() abort
    if s:xvim_popup_menu_id > 0 && exists('*popup_close')
        silent! call popup_close(s:xvim_popup_menu_id)
    endif
    let s:xvim_popup_menu_id = -1
endfunction

" Show (or update) the completion dropdown, attached directly under the
" command popup, with the currently-selected candidate highlighted.
function! XVimPopupMenuShow() abort
    if empty(s:xvim_popup) || empty(s:xvim_popup.completions) || !exists('*popup_create')
        call XVimPopupMenuHide()
        return
    endif
    let l:pos = popup_getpos(s:xvim_popup.id)
    if empty(l:pos)
        call XVimPopupMenuHide()
        return
    endif
    let l:max_visible = 10
    let l:total = len(s:xvim_popup.completions)
    let l:idx = max([0, s:xvim_popup.completion_index])
    let l:start = max([0, min([l:idx - (l:max_visible / 2), l:total - l:max_visible])])
    let l:end = min([l:total, l:start + l:max_visible])
    let l:lines = s:xvim_popup.completions[l:start : l:end - 1]
    let l:sel_offset = l:idx - l:start
    let l:opts = {
        \ 'line': l:pos.line + l:pos.height,
        \ 'col': l:pos.col,
        \ 'minwidth': l:pos.width - 2,
        \ 'maxwidth': l:pos.width - 2,
        \ 'minheight': len(l:lines),
        \ 'maxheight': l:max_visible,
        \ 'padding': [0, 1, 0, 1],
        \ 'border': [0, 1, 1, 1],
        \ 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
        \ 'borderhighlight': ['FloatBorder'],
        \ 'highlight': 'Pmenu',
        \ 'mapping': 0,
        \ 'cursorline': 0,
        \ 'wrap': 0,
        \ 'zindex': 199,
        \ }
    if s:xvim_popup_menu_id > 0 && !empty(popup_getpos(s:xvim_popup_menu_id))
        call popup_settext(s:xvim_popup_menu_id, l:lines)
        call popup_move(s:xvim_popup_menu_id, l:opts)
    else
        let s:xvim_popup_menu_id = popup_create(l:lines, l:opts)
    endif
    call XVimPopupMenuEnsureProp()
    let l:bufnr = winbufnr(s:xvim_popup_menu_id)
    silent! call prop_remove({'type': 'XVimPmenuSel', 'bufnr': l:bufnr, 'all': 1})
    if l:sel_offset >= 0 && l:sel_offset < len(l:lines)
        call prop_add(l:sel_offset + 1, 1, {'type': 'XVimPmenuSel', 'length': strlen(l:lines[l:sel_offset]), 'bufnr': l:bufnr})
    endif
endfunction

function! XVimPopupResetCompletion() abort
    let s:xvim_popup.completions = []
    let s:xvim_popup.completion_base = ''
    let s:xvim_popup.completion_index = -1
    call XVimPopupMenuHide()
endfunction

function! XVimPopupComplete(direction) abort
    if empty(s:xvim_popup) || s:xvim_popup.prefix !=# ':'
        return
    endif
    " Completion always applies to the whole line up to the cursor; only
    " offer it when the cursor is at the end, where native cmdline
    " completion would also operate.
    if s:xvim_popup.cursor !=# strchars(s:xvim_popup.value)
        return
    endif
    if empty(s:xvim_popup.completions)
        let l:candidates = getcompletion(s:xvim_popup.value, 'cmdline')
        if empty(l:candidates)
            return
        endif
        let s:xvim_popup.completions = l:candidates
        let s:xvim_popup.completion_base = s:xvim_popup.value
        let s:xvim_popup.completion_index = -1
    endif
    let l:count = len(s:xvim_popup.completions)
    let s:xvim_popup.completion_index = (s:xvim_popup.completion_index + a:direction + l:count) % l:count
    let l:base = s:xvim_popup.completion_base
    let l:lastword = matchstr(l:base, '\S*$')
    let l:head = strpart(l:base, 0, strlen(l:base) - strlen(l:lastword))
    let s:xvim_popup.value = l:head . s:xvim_popup.completions[s:xvim_popup.completion_index]
    let s:xvim_popup.cursor = strchars(s:xvim_popup.value)
    call XVimPopupRender()
    call XVimPopupMenuShow()
endfunction

function! XVimPopupFilter(id, key) abort
    if empty(s:xvim_popup) || a:id !=# s:xvim_popup.id
        return 0
    endif

    let l:keytrans = keytrans(a:key)
    let l:key = (a:key ==# ' ' || a:key ==# "\<Space>" || l:keytrans ==# '<Space>') ? ' ' : a:key
    if l:key !=# "\<Tab>" && l:key !=# "\<S-Tab>" && l:keytrans !=# '<Tab>' && l:keytrans !=# '<S-Tab>'
        call XVimPopupResetCompletion()
    endif
    let l:len = strchars(s:xvim_popup.value)
    if l:key ==# "\<Esc>" || l:key ==# "\<C-C>"
        call XVimPopupClose()
    elseif l:key ==# "\<CR>"
        call XVimPopupAccept()
    elseif l:key ==# "\<Tab>" || l:keytrans ==# '<Tab>'
        call XVimPopupComplete(1)
    elseif l:key ==# "\<S-Tab>" || l:keytrans ==# '<S-Tab>'
        call XVimPopupComplete(-1)
    elseif l:key ==# "\<Left>" || l:key ==# "\<C-B>"
        let s:xvim_popup.cursor = max([0, s:xvim_popup.cursor - 1])
        call XVimPopupRender()
    elseif l:key ==# "\<Right>" || l:key ==# "\<C-F>"
        let s:xvim_popup.cursor = min([l:len, s:xvim_popup.cursor + 1])
        call XVimPopupRender()
    elseif l:key ==# "\<Home>" || l:key ==# "\<C-A>"
        let s:xvim_popup.cursor = 0
        call XVimPopupRender()
    elseif l:key ==# "\<End>" || l:key ==# "\<C-E>"
        let s:xvim_popup.cursor = l:len
        call XVimPopupRender()
    elseif l:key ==# "\<BS>"
        if s:xvim_popup.cursor > 0
            let s:xvim_popup.value = strcharpart(s:xvim_popup.value, 0, s:xvim_popup.cursor - 1)
                \ . strcharpart(s:xvim_popup.value, s:xvim_popup.cursor)
            let s:xvim_popup.cursor -= 1
        endif
        call XVimPopupRender()
    elseif l:key ==# "\<Del>"
        if s:xvim_popup.cursor < l:len
            let s:xvim_popup.value = strcharpart(s:xvim_popup.value, 0, s:xvim_popup.cursor)
                \ . strcharpart(s:xvim_popup.value, s:xvim_popup.cursor + 1)
        endif
        call XVimPopupRender()
    elseif l:key ==# "\<C-U>"
        let s:xvim_popup.value = strcharpart(s:xvim_popup.value, s:xvim_popup.cursor)
        let s:xvim_popup.cursor = 0
        call XVimPopupRender()
    elseif l:key ==# "\<C-K>"
        let s:xvim_popup.value = strcharpart(s:xvim_popup.value, 0, s:xvim_popup.cursor)
        call XVimPopupRender()
    elseif l:key ==# "\<C-W>"
        let l:before = strcharpart(s:xvim_popup.value, 0, s:xvim_popup.cursor)
        let l:after = strcharpart(s:xvim_popup.value, s:xvim_popup.cursor)
        let l:trimmed = substitute(l:before, '\s*\S\+\s*$', '', '')
        let s:xvim_popup.value = l:trimmed . l:after
        let s:xvim_popup.cursor = strchars(l:trimmed)
        call XVimPopupRender()
    elseif l:key ==# "\<Up>" || l:key ==# "\<Down>"
        let l:limit = histnr(s:xvim_popup.history) + 1
        if l:key ==# "\<Up>"
            let s:xvim_popup.history_index = max([1, s:xvim_popup.history_index - 1])
        else
            let s:xvim_popup.history_index = min([l:limit, s:xvim_popup.history_index + 1])
        endif
        let s:xvim_popup.value = histget(s:xvim_popup.history, s:xvim_popup.history_index)
        let s:xvim_popup.cursor = strchars(s:xvim_popup.value)
        call XVimPopupRender()
    elseif l:key ==# ' ' || (l:keytrans !~# '^<.*>$' && strchars(l:key) > 0)
        let s:xvim_popup.value = strcharpart(s:xvim_popup.value, 0, s:xvim_popup.cursor) . l:key
            \ . strcharpart(s:xvim_popup.value, s:xvim_popup.cursor)
        let s:xvim_popup.cursor += 1
        call XVimPopupRender()
    endif
    return 1
endfunction

function! XVimPopupOpen(prefix) abort
    if !exists('*popup_create')
        call feedkeys(a:prefix, 'n')
        return
    endif

    if exists('s:xvim_heavy_timer') && s:xvim_heavy_timer > 0
        call timer_stop(s:xvim_heavy_timer)
        let s:xvim_heavy_timer = -1
    endif
    call XVimPopupClose()
    let l:history = a:prefix ==# ':' ? ':' : '/'
    let l:width = min([80, max([20, &columns - 8])])
    let l:title = a:prefix ==# ':' ? ' COMMAND ' : ' SEARCH '
    let l:icon = a:prefix ==# ':' ? '' : (a:prefix ==# '?' ? ' ' : ' ')
    let s:xvim_popup = {
        \ 'prefix': a:prefix,
        \ 'title': l:title,
        \ 'prompt': l:icon . '  ',
        \ 'value': '',
        \ 'history': l:history,
        \ 'history_index': histnr(l:history) + 1,
        \ 'cursor': 0,
        \ 'completions': [],
        \ 'completion_base': '',
        \ 'completion_index': -1,
        \ 'id': popup_create([''], {
        \     'line': max([1, (&lines - 1) / 2]),
        \     'col': max([1, (&columns - l:width - 2) / 2]),
        \     'minwidth': l:width,
        \     'maxwidth': l:width,
        \     'minheight': 1,
        \     'maxheight': 1,
        \     'padding': [0, 1, 0, 1],
        \     'border': [1],
        \     'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
        \     'title': l:title,
        \     'titlehighlight': 'FloatTitle',
        \     'borderhighlight': ['FloatBorder'],
        \     'highlight': 'Normal',
        \     'winhighlight': 'Normal:Normal,NormalNC:Normal,CursorLine:Normal',
        \     'filter': function('XVimPopupFilter'),
        \     'mapping': 0,
        \     'cursorline': 0,
        \     'zindex': 200,
        \ })
        \ }
    call XVimPopupRender()
endfunction

if exists('*popup_create')
    nnoremap <silent> : <Cmd>call XVimPopupOpen(':')<CR>
    nnoremap <silent> / <Cmd>call XVimPopupOpen('/')<CR>
    nnoremap <silent> ? <Cmd>call XVimPopupOpen('?')<CR>
endif

" Configure airline status bar
if !exists('g:airline_symbols')
    let g:airline_symbols = {}
endif
let g:airline_symbols.space = "\ua0"
let g:airline_theme = 'onedark'
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#formatter = 'unique_tail'
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#show_close_button = 0
let g:airline#extensions#tabline#tabs_label = ''
let g:airline#extensions#tabline#show_buffers = 0
let g:airline#extensions#tabline#show_splits = 0
let g:airline#extensions#tabline#show_tab_nr = 0

" vim-airline unconditionally forces 'laststatus' back to 2 the moment its
" plugin script loads (see plugin/airline.vim: "if &laststatus < 2 | set
" laststatus=2"), regardless of the laststatus=0 set at the top of this
" file. That re-enables Vim's own native statusline row for the window --
" which airline#util#stl_disabled() and airline#statusline() below know
" nothing about -- so it gets drawn independently of, and one row above,
" the XVimRenderStatusPopup() popup pinned to the very last screen row.
" The result is a duplicate/ghost status bar sitting above the real one,
" with the real one appearing to float instead of sitting flush at the
" bottom. Re-assert laststatus=0 on every event that can retrigger
" airline's own (re)initialization so its native row never reappears.
augroup XVimForceLaststatus
    autocmd!
    autocmd VimEnter,BufWinEnter,WinEnter,FileType,VimResized * if &laststatus != 0 | set laststatus=0 | endif
augroup END

" Vim cannot set cmdheight=0 (E487), so the only way to reclaim the blank
" row below the statusline is to hide the native statusline (laststatus=0,
" set above, and re-asserted just above) and paint airline's own text into
" a popup pinned to the last screen row ourselves. airline#util#stl_disabled()
" only looks at g:airline_disable_statusline (left unset here), so airline
" keeps building its statusline text in the background even though it is
" never actually displayed natively -- we just have to turn that %-format
" string into plain text, since there is no real statusline row left to
" read pixels from.
let s:xvim_heavy_timer = -1
let s:xvim_ui_refreshing = 0
let s:xvim_status_popup = -1
" Signature (text+highlight-group per segment) of what is currently
" painted into the popup, used to skip redundant popup_settext()/prop_add()
" calls when nothing actually changed.
let s:xvim_status_text = ''
let s:xvim_status_timer = -1
" Cache of text-property types created to mirror airline's own highlight
" groups (see XVimEnsureHlProp()), keyed by group name.
let s:xvim_hl_props = {}

" Evaluate the handful of statusline item codes airline's format string
" uses (see 'statusline' in :help), aside from %{...} and highlight groups
" (highlight markers are handled separately by XVimTokenizeStatusFormat()).
function! XVimEvalStatusExpr(s) abort
    let l:out = a:s
    " %{expr} items -- airline emits mostly these; eval() each in place.
    let l:out = substitute(l:out, '%{\(.\{-}\)}', '\=eval(submatch(1))', 'g')
    " Numbered user-highlight markers (%1*..%9*, %0*) -- unused by airline,
    " but strip them defensively since nothing here paints them.
    let l:out = substitute(l:out, '%[0-9]\+\*', '', 'g')
    let l:out = substitute(l:out, '%<', '', 'g')
    " Plain 'statusline' item codes.
    let l:out = substitute(l:out, '%-\?[0-9]*\.\?[0-9]*l', '\=line(".")', 'g')
    let l:out = substitute(l:out, '%L', '\=line("$")', 'g')
    let l:out = substitute(l:out, '%v', '\=virtcol(".")', 'g')
    let l:out = substitute(l:out, '%c', '\=col(".")', 'g')
    let l:out = substitute(l:out, '%p', '\=(line("$") <= 1 ? 100 : (line(".") * 100) / line("$"))', 'g')
    let l:out = substitute(l:out, '%F', '\=(expand("%:p") ==# "" ? "[No Name]" : expand("%:p"))', 'g')
    let l:out = substitute(l:out, '%f', '\=(expand("%") ==# "" ? "[No Name]" : expand("%"))', 'g')
    let l:out = substitute(l:out, '%m', '\=(&modified ? "[+]" : "")', 'g')
    let l:out = substitute(l:out, '%r', '\=(&readonly ? "[RO]" : "")', 'g')
    let l:out = substitute(l:out, '%h', '\=(&buftype ==# "help" ? "[Help]" : "")', 'g')
    let l:out = substitute(l:out, '%w', '\=(&previewwindow ? "[Preview]" : "")', 'g')
    let l:out = substitute(l:out, '%y', '\=(&filetype !=# "" ? "[" . &filetype . "]" : "")', 'g')
    let l:out = substitute(l:out, '%n', '\=bufnr("%")', 'g')
    let l:out = substitute(l:out, '%%', '%', 'g')
    return l:out
endfunction

" Airline's %( ... %) optional groups (readonly flag, paste indicator, etc)
" routinely span one or more %#group# highlight markers (e.g. the mode
" group wraps "%( %#airline_a_bold#%{...}%#airline_a#...%)"), so they must
" be resolved on the *whole* format string before it gets tokenized by
" highlight group below -- otherwise a %( and its matching %) would end up
" split across separate, differently-highlighted tokens. Only the %( / %)
" delimiters are dropped when the group renders to non-empty text; its
" inner %#group# markers are left intact so the tokenizer still sees them.
function! XVimResolveOptionalGroupContent(content) abort
    let l:plain = substitute(a:content, '%#[A-Za-z0-9_]*#', '', 'g')
    if trim(XVimEvalStatusExpr(l:plain)) ==# ''
        return ''
    endif
    return a:content
endfunction

function! XVimResolveOptionalGroups(fmt) abort
    return substitute(a:fmt, '%(\(.\{-}\)%)', '\=XVimResolveOptionalGroupContent(submatch(1))', 'g')
endfunction

" Split an airline statusline format string into an ordered list of
" {'group': highlight-group-name, 'raw': text} chunks on its %#group#
" highlight markers, plus bare {'sep': 1} markers for %= splits. This lets
" each rendered chunk keep its own highlight group instead of collapsing
" the whole line into a single flat color once the markers are stripped.
function! XVimTokenizeStatusFormat(fmt) abort
    let l:tokens = []
    let l:s = a:fmt
    let l:group = ''
    while l:s !=# ''
        let [l:match, l:start, l:end] = matchstrpos(l:s, '%#[A-Za-z0-9_]*#\|%=')
        if l:start == -1
            call add(l:tokens, {'group': l:group, 'raw': l:s})
            break
        endif
        if l:start > 0
            call add(l:tokens, {'group': l:group, 'raw': l:s[0 : l:start - 1]})
        endif
        if l:match ==# '%='
            call add(l:tokens, {'sep': 1})
        else
            let l:group = l:match[2:-2]
        endif
        let l:s = l:s[l:end :]
    endwhile
    return l:tokens
endfunction

" Build the list of {'text': ..., 'group': ...} segments to render for the
" active window's statusline, padding between the left/right halves (like
" airline's own %=) and falling back to a minimal, ungrouped hand-built
" line if airline is unavailable or the format could not be evaluated.
function! XVimBuildStatusSegments(width) abort
    let l:segments = []
    try
        if exists('*airline#update_statusline')
            call airline#update_statusline()
        endif
        if exists('*airline#statusline')
            let l:fmt = XVimResolveOptionalGroups(airline#statusline(winnr()))
            if !empty(l:fmt)
                let l:left = []
                let l:right = []
                let l:side = 0
                let l:left_width = 0
                let l:right_width = 0
                for l:tok in XVimTokenizeStatusFormat(l:fmt)
                    if get(l:tok, 'sep', 0)
                        let l:side = 1
                        continue
                    endif
                    let l:text = XVimEvalStatusExpr(l:tok.raw)
                    if l:text ==# ''
                        continue
                    endif
                    let l:seg = {'text': l:text, 'group': l:tok.group}
                    if l:side == 0
                        call add(l:left, l:seg)
                        let l:left_width += strdisplaywidth(l:text)
                    else
                        call add(l:right, l:seg)
                        let l:right_width += strdisplaywidth(l:text)
                    endif
                endfor
                if !empty(l:left) || !empty(l:right)
                    let l:pad = a:width - l:left_width - l:right_width
                    let l:segments = l:left
                    call add(l:segments, {'text': repeat(' ', max([1, l:pad])), 'group': ''})
                    call extend(l:segments, l:right)
                endif
            endif
        endif
    catch
        let l:segments = []
    endtry
    if empty(l:segments)
        let l:name = expand('%:t') ==# '' ? '[No Name]' : expand('%:t')
        let l:mod = &modified ? ' [+]' : ''
        let l:text = ' ' . toupper(mode()) . '  ' . l:name . l:mod . '  ' . line('.') . ':' . col('.')
        let l:segments = [{'text': l:text, 'group': ''}]
    endif
    " Trim trailing segments (and truncate the one that overflows) to fit.
    let l:trimmed = []
    let l:total = 0
    for l:seg in l:segments
        let l:w = strdisplaywidth(l:seg.text)
        if l:total + l:w > a:width
            let l:remaining = a:width - l:total
            if l:remaining > 0
                call add(l:trimmed, {'text': strcharpart(l:seg.text, 0, l:remaining), 'group': l:seg.group})
            endif
            break
        endif
        call add(l:trimmed, l:seg)
        let l:total += l:w
    endfor
    return l:trimmed
endfunction

" Lazily create (and cache) a text-property type that mirrors an airline
" highlight group's real colors, so segments in the popup can be painted
" the same way native airline theming would -- these are ordinary
" `:highlight` groups that airline itself defines/updates per mode, so
" linking a prop type straight to the group name keeps colors in sync.
function! XVimEnsureHlProp(group) abort
    if a:group ==# '' || !exists('*prop_type_add') || !exists('*prop_type_get')
        return ''
    endif
    if has_key(s:xvim_hl_props, a:group)
        return s:xvim_hl_props[a:group]
    endif
    let l:propname = ''
    if hlexists(a:group)
        let l:propname = 'XVimStl_' . a:group
        if empty(prop_type_get(l:propname))
            try
                call prop_type_add(l:propname, {'highlight': a:group})
            catch
                let l:propname = ''
            endtry
        endif
    endif
    let s:xvim_hl_props[a:group] = l:propname
    return l:propname
endfunction

function! XVimStatusPopupEnsure() abort
    if s:xvim_status_popup > 0 && !empty(popup_getpos(s:xvim_status_popup))
        return
    endif
    let s:xvim_status_popup = popup_create([''], {
        \ 'line': &lines,
        \ 'col': 1,
        \ 'minwidth': &columns,
        \ 'maxwidth': &columns,
        \ 'minheight': 1,
        \ 'maxheight': 1,
        \ 'padding': [0, 0, 0, 0],
        \ 'border': [0, 0, 0, 0],
        \ 'highlight': 'StatusLine',
        \ 'mapping': 0,
        \ 'cursorline': 0,
        \ 'wrap': 0,
        \ 'fixed': 1,
        \ 'zindex': 100,
        \ })
endfunction

function! XVimRenderStatusPopup() abort
    if !exists('*popup_create')
        return
    endif
    call XVimStatusPopupEnsure()
    call popup_move(s:xvim_status_popup, {'line': &lines, 'col': 1, 'minwidth': &columns, 'maxwidth': &columns})
    let l:segments = XVimBuildStatusSegments(&columns)
    let l:sig = join(map(copy(l:segments), 'v:val.text . "\x01" . v:val.group'), "\x02")
    if l:sig ==# s:xvim_status_text
        return
    endif
    let s:xvim_status_text = l:sig
    call popup_settext(s:xvim_status_popup, [join(map(copy(l:segments), 'v:val.text'), '')])
    let l:bufnr = winbufnr(s:xvim_status_popup)
    if l:bufnr <= 0
        return
    endif
    if exists('*prop_clear')
        silent! call prop_clear(1, 1, {'bufnr': l:bufnr})
    endif
    if exists('*prop_add')
        let l:col = 1
        for l:seg in l:segments
            let l:bytelen = strlen(l:seg.text)
            if l:seg.group !=# ''
                let l:propname = XVimEnsureHlProp(l:seg.group)
                if l:propname !=# ''
                    silent! call prop_add(1, l:col, {'type': l:propname, 'length': l:bytelen, 'bufnr': l:bufnr})
                endif
            endif
            let l:col += l:bytelen
        endfor
    endif
endfunction

function! XVimRunStatusUpdate(timer) abort
    let s:xvim_status_timer = -1
    call XVimRenderStatusPopup()
endfunction

" Debounced, lightweight status refresh -- only touches the status popup
" text, no full redraw!, so it is safe to call from CursorMoved/ModeChanged
" without risking the redraw storms/flicker seen previously.
function! XVimScheduleStatusUpdate() abort
    if !empty(s:xvim_popup) || !exists('*popup_create')
        return
    endif
    if !exists('*timer_start')
        call XVimRenderStatusPopup()
        return
    endif
    if s:xvim_status_timer > 0
        call timer_stop(s:xvim_status_timer)
    endif
    let s:xvim_status_timer = timer_start(30, function('XVimRunStatusUpdate'))
endfunction

" Refresh the startup and new-buffer UI without waiting for keyboard input.
function! XVimRefreshUi() abort
    if s:xvim_ui_refreshing || !empty(s:xvim_popup)
        return
    endif
    let s:xvim_ui_refreshing = 1
    if exists(':AirlineRefresh') == 2
        try
            silent AirlineRefresh
        catch
        endtry
    endif
    redraw!
    silent! redrawstatus
    call XVimRenderStatusPopup()
    let s:xvim_ui_refreshing = 0
endfunction

function! XVimRunHeavyRefresh(timer) abort
    let s:xvim_heavy_timer = -1
    call XVimRefreshUi()
endfunction

function! XVimScheduleUiRefresh() abort
    if !exists('*timer_start')
        call XVimRefreshUi()
        return
    endif
    if s:xvim_heavy_timer > 0
        call timer_stop(s:xvim_heavy_timer)
    endif
    let s:xvim_heavy_timer = timer_start(0, function('XVimRunHeavyRefresh'))
endfunction

" |------------------- noice-style message popup ------------------------|
" Route log/error output into a popup above the status bar instead of the
" command line. Vim has no message-filter hook, so this polls `:messages`
" (bounded to the single most-recent entry, so cost never grows with
" history size) on a light timer and whenever we run a command ourselves.
let s:xvim_msg_popup = -1
let s:xvim_msg_last = ''
let s:xvim_msg_poll_timer = -1
let s:xvim_msg_hide_timer = -1

function! XVimLatestMessage() abort
    let l:out = ''
    try
        redir => l:out
        silent! 1messages
        redir END
    catch
        silent! redir END
    endtry
    let l:lines = split(l:out, "\n")
    while !empty(l:lines) && trim(l:lines[-1]) ==# ''
        call remove(l:lines, -1)
    endwhile
    return join(l:lines, "\n")
endfunction

function! XVimMsgPopupHide() abort
    if s:xvim_msg_popup > 0 && exists('*popup_close')
        silent! call popup_close(s:xvim_msg_popup)
    endif
    let s:xvim_msg_popup = -1
    if s:xvim_msg_hide_timer > 0
        call timer_stop(s:xvim_msg_hide_timer)
        let s:xvim_msg_hide_timer = -1
    endif
endfunction

function! XVimMsgPopupAutoHide(timer) abort
    let s:xvim_msg_hide_timer = -1
    call XVimMsgPopupHide()
endfunction

function! XVimShowMessage(text) abort
    if !exists('*popup_create') || trim(a:text) ==# ''
        return
    endif
    let l:width = max([20, &columns - 4])
    let l:lines = split(a:text, "\n")
    if len(l:lines) > 6
        let l:lines = l:lines[-6:]
    endif
    let l:opts = {
        \ 'line': max([1, &lines - 1 - len(l:lines)]),
        \ 'col': max([1, (&columns - l:width) / 2 + 1]),
        \ 'minwidth': l:width,
        \ 'maxwidth': l:width,
        \ 'minheight': len(l:lines),
        \ 'maxheight': len(l:lines),
        \ 'padding': [0, 1, 0, 1],
        \ 'border': [1, 1, 1, 1],
        \ 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
        \ 'borderhighlight': ['FloatBorder'],
        \ 'title': ' MESSAGE ',
        \ 'titlehighlight': 'FloatTitle',
        \ 'highlight': 'Normal',
        \ 'mapping': 0,
        \ 'cursorline': 0,
        \ 'wrap': 1,
        \ 'zindex': 190,
        \ }
    if s:xvim_msg_popup > 0 && !empty(popup_getpos(s:xvim_msg_popup))
        call popup_settext(s:xvim_msg_popup, l:lines)
        call popup_move(s:xvim_msg_popup, l:opts)
    else
        let s:xvim_msg_popup = popup_create(l:lines, l:opts)
    endif
    if s:xvim_msg_hide_timer > 0
        call timer_stop(s:xvim_msg_hide_timer)
    endif
    let s:xvim_msg_hide_timer = timer_start(4000, function('XVimMsgPopupAutoHide'))
endfunction

function! XVimPollMessagesNow() abort
    let l:current = XVimLatestMessage()
    if l:current !=# s:xvim_msg_last
        let s:xvim_msg_last = l:current
        if l:current !=# ''
            call XVimShowMessage(l:current)
        endif
    endif
endfunction

function! XVimPollMessagesTimer(timer) abort
    let s:xvim_msg_poll_timer = -1
    call XVimPollMessagesNow()
    call XVimScheduleMsgPoll()
endfunction

function! XVimScheduleMsgPoll() abort
    if !exists('*timer_start') || !exists('*popup_create')
        return
    endif
    let s:xvim_msg_poll_timer = timer_start(200, function('XVimPollMessagesTimer'))
endfunction

" Prime the "last seen" message on startup so whatever plugins printed
" during load is not immediately flashed as a new message once polling
" begins.
function! XVimPrimeMessages() abort
    let s:xvim_msg_last = XVimLatestMessage()
    call XVimScheduleMsgPoll()
endfunction
" |------------------------------------------------------------------------|

function! XVimStopUiTimers() abort
    if s:xvim_heavy_timer > 0
        call timer_stop(s:xvim_heavy_timer)
        let s:xvim_heavy_timer = -1
    endif
    if s:xvim_status_timer > 0
        call timer_stop(s:xvim_status_timer)
        let s:xvim_status_timer = -1
    endif
    if s:xvim_msg_poll_timer > 0
        call timer_stop(s:xvim_msg_poll_timer)
        let s:xvim_msg_poll_timer = -1
    endif
    if !empty(s:xvim_popup) && exists('*popup_close')
        silent! call popup_close(s:xvim_popup.id)
    endif
    if s:xvim_status_popup > 0 && exists('*popup_close')
        silent! call popup_close(s:xvim_status_popup)
    endif
    call XVimMsgPopupHide()
    call XVimPopupMenuHide()
endfunction

augroup XVimUiRefresh
    autocmd!
    autocmd VimEnter * call XVimPrimeMessages()
    autocmd VimEnter,BufWinEnter,WinEnter,VimResized * call XVimScheduleUiRefresh()
    autocmd CursorMoved,CursorMovedI,ModeChanged,InsertEnter,InsertLeave * call XVimScheduleStatusUpdate()
    autocmd VimLeavePre * call XVimStopUiTimers()
augroup END

" Max characters in a line highlighted
set synmaxcol=1000

" Time in ms that must be exceeded before syntax highlight processing stops
set redrawtime=5000

" Give split separators a visible, understated onedark-style treatment.
highlight VertSplit guifg=#5c6370 ctermfg=241 guibg=#282c34 ctermbg=236 gui=NONE cterm=NONE
highlight FoldColumn guifg=#999999 ctermfg=246 guibg=#444444 ctermbg=238 gui=NONE cterm=NONE

" Kate-style separated gutter: number/sign columns share FoldColumn's panel
" background so the whole gutter reads as one shade distinct from Normal.
highlight LineNr guifg=#999999 ctermfg=246 guibg=#444444 ctermbg=238 gui=NONE cterm=NONE
highlight CursorLineNr guifg=#61afef ctermfg=39 guibg=#444444 ctermbg=238 gui=bold cterm=bold
highlight SignColumn guifg=#999999 ctermfg=246 guibg=#444444 ctermbg=238 gui=NONE cterm=NONE
"
" |======================================================================|


" |================== Key Bindings / Hotkey Mapping =====================|
" see :help map-modes for more info
"
" Make timeout for pressing keys shorter. NOTE: ttimeoutlen must stay above 0
" here -- at 0 Vim does not wait at all for the remaining bytes of a key
" code, so terminal response sequences (e.g. from 'termguicolors' queries)
" that arrive in more than one read get partially decoded and printed as
" literal control characters on the first screen until a real keypress
" forces Vim to re-sync and redraw.
set timeout timeoutlen=1000 ttimeoutlen=10

" Set the leader and local leader mappings
noremap <SPACE> <Nop>
let mapleader = " "
let maplocalleader = " "

" <ESC> (terminal mode)             to return to normal mode
tnoremap <Esc> <C-\><C-n>

" <F1>                              to clear search highlighting
nnoremap <silent> <F1> :nohlsearch<CR>

" <F2>                              toggle for insert paste mode
" TODO: broken in neovim (use regular insert mode to paste)
nnoremap <silent> <F2> :set invpaste<CR>
set pastetoggle=<F2>

" <F3>                              to replace tabs/spaces w/ correct type
nnoremap <silent> <F3> :RetabIndent<CR>

" <shift>+<tab>                     to un-indent
nnoremap <S-Tab> <<
inoremap <S-Tab> <C-D>

" <ctrl>+<arrow key>                to navigate window splits
nnoremap <silent> <C-Left> <C-W>h
nnoremap <silent> <C-Right> <C-W>l
nnoremap <silent> <C-Up> <C-W>k
nnoremap <silent> <C-Down> <C-W>j

" <ctrl>+<page up>|<page down>      to navigate tabs (contain splits)
nnoremap <silent> <C-PageDown> :tabnext<CR>
nnoremap <silent> <C-PageUp> :tabprevious<CR>

" <alt>+<arrow key>                 to resize splits
function! SetWinResize()
    if (HasNeighbor(2))
        nnoremap <silent> <A-Left> :vertical resize -5<CR>
        nnoremap <silent> <A-Right> :vertical resize +5<CR>
    else
        nnoremap <silent> <A-Left> :vertical resize +5<CR>
        nnoremap <silent> <A-Right> :vertical resize -5<CR>
    endif
    if (HasNeighbor(3))
        nnoremap <silent> <A-Up> :resize -5<CR>
        nnoremap <silent> <A-Down> :resize +5<CR>
    elseif (HasNeighbor(1))
        nnoremap <silent> <A-Up> :resize +5<CR>
        nnoremap <silent> <A-Down> :resize -5<CR>
    endif
endfunction
autocmd WinEnter * call SetWinResize()

" <ctrl>+<t>|<w>                    to create or close a tab
nnoremap <silent> <C-t> :$tabnew<CR>
nnoremap <silent> <C-w> :tabclose<CR>

" x|X                               to cut text
nnoremap x ""d
nnoremap X ""D
vnoremap x ""d
vnoremap X ""D

" d|D                               to delete text
nnoremap d "_d
nnoremap D "_D
vnoremap d "_d
vnoremap D "_D
"
" |======================================================================|


" |=================== Filetype Settings / Mappings =====================|
"
if has("autocmd")
    " jump to last position when reopening file
    autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
    
    " Disable adding comments when hitting enter
    autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o
    
    " Hard wrap git commit msg if too long
    autocmd Filetype gitcommit setlocal spell textwidth=120

    " for lua files use 2 spaces
    autocmd Filetype lua setlocal tabstop=2 shiftwidth=2 softtabstop=2 expandtab

    " for make files use tabs
    autocmd Filetype make setlocal tabstop=4 shiftwidth=4 softtabstop=0 noexpandtab

    " for kamaillio files use tabs
    autocmd Filetype kamailio setlocal tabstop=4 shiftwidth=4 softtabstop=0 noexpandtab
    
    " Edit filetypes not usually supported by using pandoc
    autocmd BufReadPost *.doc,*.docx,*.rtf,*.odp,*.odt silent %!pandoc "%" -tplain -o /dev/stdout

    " set filetype=log for files ending in .log 
    autocmd BufRead,BufNewFile *.log set filetype=log

    " Read-only pdf through pdftotext
    autocmd BufReadPre *.pdf silent set ro
    autocmd BufReadPost *.pdf silent %!pdftotext -nopgbrk -layout -q -eol unix "%" - | fmt -w78

    " Syntax highlighting for non-ascii chars
    autocmd BufReadPost * syntax match Error "[^\u0000-\u007F]"

    " Render Ansi escape sequences, then repaint airline and the bottom row.
    autocmd BufReadPost * if search('\e\[[0-9;]*m', 'nw') | silent! AnsiEsc | call XVimScheduleUiRefresh() | endif
endif

" lua require("ftoverrides")
"
" |======================================================================|

