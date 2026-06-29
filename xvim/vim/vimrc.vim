" Disable vi compatibility settings
set nocompatible


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

" Space between vertical splits
set fillchars+=vert:\

" Make sure we can show icons
set encoding=UTF-8

" Set left side margin
function! SetWinMargin()
    if (HasNeighbor(4))
        set foldcolumn=0
    else
        set foldcolumn=1
    endif
endfunction
autocmd WinEnter * call SetWinMargin()
autocmd VimEnter * call SetWinMargin()
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

" Always show the status bar
set laststatus=2

" Max characters in a line highlighted
set synmaxcol=1000

" Time in ms that must be exceeded before syntax highlight processing stops
set redrawtime=5000

" Make the vertical split and left margin match status line (tender theme)
highlight VertSplit guifg=#999999 ctermfg=246 guibg=#444444 ctermbg=238 gui=NONE cterm=NONE
highlight FoldColumn guifg=#999999 ctermfg=246 guibg=#444444 ctermbg=238 gui=NONE cterm=NONE
"
" |======================================================================|


" |================== Key Bindings / Hotkey Mapping =====================|
" see :help map-modes for more info
"
" Make timeout for pressing keys shorter
set timeout timeoutlen=1000 ttimeoutlen=0

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

    " Render Ansi escape sequences
    autocmd BufReadPost * if search('\e\[[0-9;]*m', 'nw') | silent! AnsiEsc | endif
endif

" lua require("ftoverrides")
"
" |======================================================================|

