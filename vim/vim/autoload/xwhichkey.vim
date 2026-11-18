" Which-key style menu for Vim and vimpager (the Neovim configs use
" which-key.nvim): xwhichkey#open() lists the mappings under a prefix (e.g.
" <Space>, the leader) in a popup above the status bar.
"
" * a key opens that group or runs that mapping; the menu then reopens at the
"   prefix it was opened with (hydra mode) until <Esc> closes it
" * <BS>/<Left> go up a level; <Down>/<Up> scroll a row, <PageDown>/<PageUp>
"   (and <C-d>/<C-u>) a page, unless the group maps that key itself
" * keys without a mapping are ignored
"
" Vim mappings have no description: xwhichkey#map() makes a mapping and
" records one, xwhichkey#describe() describes an existing mapping and
" xwhichkey#group() names a group; other mappings show their right-hand side.

if exists('g:autoloaded_xwhichkey')
    finish
endif
let g:autoloaded_xwhichkey = 1

" {mode: {lhs: text}}, lhs as keytrans() prints it ("<Space>bd")
let s:desc = {}
let s:groups = {}
" the open menu (empty when closed) and the menu to reopen after a mapping ran
let s:menu = {}
let s:resume = {}

" icon and color per description (first matching pattern, ignoring case);
" Nerd Font glyphs in the U+E000-U+F8FF range are written as "\u" escapes
let s:rules = [
    \ ['which-key\|keymap', '󰌌', 'Purple'],
    \ ['split.*below', '󰤻', 'Blue'],
    \ ['split.*right', '󰤼', 'Blue'],
    \ ['delete', '󰆴', 'Red'],
    \ ['close', '󰅖', 'Red'],
    \ ['quit', '󰈆', 'Red'],
    \ ['other buffer', '󰬲', 'Cyan'],
    \ ['new tab', '󰝜', 'Purple'],
    \ ['next', '󰒭', 'Purple'],
    \ ['previous', '󰒮', 'Purple'],
    \ ['first', '󰒫', 'Purple'],
    \ ['last', '󰒬', 'Purple'],
    \ ['\<tabs\=\>', '󰓩', 'Purple'],
    \ ['window', "\ueb7f", 'Blue'],
    \ ['buffer', '󰈔', 'Cyan'],
    \ ['new file', '󰝒', 'Green'],
    \ ['file', '󰈔', 'Cyan'],
    \ ['terminal', "\ue795", 'Red'],
    \ ['action', '󰌵', 'Orange'],
    \ ['rename', '󰑕', 'Orange'],
    \ ['format', "\ue64e", 'Cyan'],
    \ ['code\|lsp', "\uf121", 'Orange'],
    \ ['keywordprg\|help', '󰋖', 'Azure'],
    \ ['man page', '󰗚', 'Azure'],
    \ ['info', '󰋼', 'Azure'],
    \ ['plugin', '󰏗', 'Azure'],
    \ ['less', '󰦨', 'Purple'],
    \ ['wrap', '󰖶', 'Yellow'],
    \ ['relative', '󰉻', 'Yellow'],
    \ ['number', '󰎠', 'Yellow'],
    \ ['spell', '󰓆', 'Yellow'],
    \ ['conceal', '󰈉', 'Yellow'],
    \ ['background', '󰔎', 'Yellow'],
    \ ['cursor line', '󰘤', 'Yellow'],
    \ ['highlight', '󰸱', 'Yellow'],
    \ ['redraw', '󰑓', 'Yellow'],
    \ ['^ui$\|toggle', '󰙵', 'Cyan'],
    \ ['inspect', '󰙅', 'Cyan'],
    \ ['quickfix\|diagnostic', '󰁨', 'Green'],
    \ ['location', '󰆋', 'Green'],
    \ ['search\|find\|word', "\uf002", 'Green'],
    \ ]

" keys shown as icons in the menu
let s:key_icons = {
    \ '<Space>': '󱁐', '<Tab>': '󰌒', '<CR>': '󰌑', '<BS>': '󰁮', '<Esc>': '󱊷',
    \ '<Up>': "\uf062", '<Down>': "\uf063", '<Left>': "\uf060", '<Right>': "\uf061",
    \ '<lt>': '<', '<Bar>': '|', '<Bslash>': '\',
    \ }

let s:scroll = {
    \ '<Down>': 1, '<ScrollWheelDown>': 1, '<Up>': -1, '<ScrollWheelUp>': -1,
    \ '<PageDown>': 'page', '<C-D>': 'page', '<PageUp>': '-page', '<C-U>': '-page',
    \ }

function! s:highlights() abort
    highlight default link XWhichKey Function
    highlight default link XWhichKeyGroup Keyword
    highlight default link XWhichKeyDesc Normal
    highlight default link XWhichKeySeparator Comment
    highlight default link XWhichKeyFooter Comment
    highlight default link XWhichKeyBorder Comment
    highlight default link XWhichKeyTitle Title
    highlight default link XWhichKeyNormal Normal
    highlight default link XWhichKeyIconAzure Function
    highlight default link XWhichKeyIconBlue Function
    highlight default link XWhichKeyIconCyan Constant
    highlight default link XWhichKeyIconGreen String
    highlight default link XWhichKeyIconOrange Number
    highlight default link XWhichKeyIconPurple Statement
    highlight default link XWhichKeyIconRed Identifier
    highlight default link XWhichKeyIconYellow Type
endfunction

call s:highlights()

augroup xwhichkey
    autocmd!
    autocmd ColorScheme * call s:highlights()
    autocmd SafeState * call s:on_safe_state()
augroup END

" printable key notation ("<leader>bd", "<Space>|") -> the keys themselves
function! s:raw(lhs) abort
    let l:lhs = substitute(a:lhs, '\c<\%(local\)\=leader>', '\=get(g:, "mapleader", "\\")', 'g')
    return eval('"' . substitute(escape(l:lhs, '\"'), '<[^<> ]\+>', '\\&', 'g') . '"')
endfunction

" the normalized notation used as the key of s:desc/s:groups
function! s:norm(lhs) abort
    return keytrans(s:raw(a:lhs))
endfunction

function! s:tokens(lhs) abort
    return split(a:lhs, '\%(<[^<>]\+>\|.\)\zs')
endfunction

" xwhichkey#map('n', '<leader>bd', '<Cmd>bdelete<CR>', 'Delete Buffer'[, opts])
" opts: buffer (0), remap (0), silent (1), nowait (0)
function! xwhichkey#map(modes, lhs, rhs, desc, ...) abort
    let l:opts = get(a:000, 0, {})
    let l:args = (get(l:opts, 'silent', 1) ? '<silent>' : '')
        \ . (get(l:opts, 'buffer', 0) ? '<buffer>' : '')
        \ . (get(l:opts, 'nowait', 0) ? '<nowait>' : '')
    for l:mode in split(a:modes, '\zs')
        execute l:mode . (get(l:opts, 'remap', 0) ? 'map ' : 'noremap ') . l:args . ' ' . a:lhs . ' ' . a:rhs
        call xwhichkey#describe(l:mode, a:lhs, a:desc, get(l:opts, 'buffer', 0))
    endfor
endfunction

" describes a mapping made elsewhere (buffer=1: the current buffer's mapping)
function! xwhichkey#describe(modes, lhs, desc, ...) abort
    let l:table = get(a:000, 0, 0) ? get(b:, 'xwhichkey_desc', {}) : s:desc
    for l:mode in split(a:modes, '\zs')
        let l:table[l:mode] = extend(get(l:table, l:mode, {}), {s:norm(a:lhs): a:desc})
    endfor
    if get(a:000, 0, 0)
        let b:xwhichkey_desc = l:table
    endif
endfunction

function! xwhichkey#group(modes, lhs, name) abort
    for l:mode in split(a:modes, '\zs')
        let s:groups[l:mode] = extend(get(s:groups, l:mode, {}), {s:norm(a:lhs): a:name})
    endfor
endfunction

function! s:in_mode(map, mode) abort
    return a:map.mode =~# '[' . a:mode . ' ]' || (a:mode ==# 'x' && a:map.mode =~# 'v')
endfunction

" short text for a mapping without a description: its right-hand side
function! s:rhs_text(rhs) abort
    let l:text = substitute(a:rhs, '<SNR>\d\+_\|^<Plug>', '', 'g')
    let l:text = substitute(l:text, '^\%(<Cmd>\|:\)\s*\|<CR>$', '', 'g')
    return strchars(l:text) > 36 ? strcharpart(l:text, 0, 35) . '…' : l:text
endfunction

function! s:describe(mode, map) abort
    let l:lhs = keytrans(a:map.lhsraw)
    return get(get(get(b:, 'xwhichkey_desc', {}), a:mode, {}), l:lhs,
        \ get(get(s:desc, a:mode, {}), l:lhs, s:rhs_text(a:map.rhs)))
endfunction

" the entries one key below path: [{key, group, desc}]
function! s:entries(mode, path, buffer_only) abort
    let l:depth = len(a:path)
    let l:found = {}
    for l:map in maplist()
        if !s:in_mode(l:map, a:mode) || l:map.rhs ==? '<Nop>' || l:map.rhs =~# 'xwhichkey#open'
            \ || (a:buffer_only && !l:map.buffer)
            continue
        endif
        let l:keys = s:tokens(keytrans(l:map.lhsraw))
        if len(l:keys) <= l:depth || (l:depth > 0 && l:keys[: l:depth - 1] !=# a:path)
            \ || l:keys[0] ==# '<Plug>' || l:keys[0] =~# '^<SNR>'
            continue
        endif
        let l:key = l:keys[l:depth]
        let l:entry = get(l:found, l:key, {'key': l:key, 'group': 0, 'map': {}, 'count': 0})
        if len(l:keys) == l:depth + 1
            if empty(l:entry.map) || l:map.buffer
                let l:entry.map = l:map
            endif
        else
            let l:entry.group = 1
            let l:entry.count += 1
            let l:entry.child = l:map
        endif
        let l:found[l:key] = l:entry
    endfor

    let l:entries = []
    for l:entry in values(l:found)
        let l:lhs = join(a:path + [l:entry.key], '')
        if l:entry.group
            " an unnamed group of one mapping shows that mapping
            let l:only = l:entry.count == 1
                \ ? strpart(keytrans(l:entry.child.lhsraw), strlen(l:lhs)) . ' ' . s:describe(a:mode, l:entry.child) : ''
            let l:desc = get(get(s:groups, a:mode, {}), l:lhs, l:only !=# '' ? l:only : l:entry.count . ' keymaps')
        else
            let l:desc = s:describe(a:mode, l:entry.map)
        endif
        call add(l:entries, {'key': l:entry.key, 'group': l:entry.group, 'desc': l:desc})
    endfor
    return sort(l:entries, function('s:compare'))
endfunction

" mappings before groups; letters (lowercase first), then symbols, then <Keys>
function! s:sort_key(entry) abort
    let l:key = a:entry.key
    let l:class = l:key =~# '^<.\+>$' ? 2 : (l:key =~# '^\a$' ? 0 : 1)
    return printf('%d%d%s %d', a:entry.group, l:class, tolower(l:key), l:key =~# '^\u$')
endfunction

function! s:compare(a, b) abort
    let l:a = s:sort_key(a:a)
    let l:b = s:sort_key(a:b)
    return l:a ==# l:b ? 0 : (l:a ># l:b ? 1 : -1)
endfunction

function! s:icon(desc) abort
    for [l:pattern, l:icon, l:color] in s:rules
        if a:desc =~? l:pattern
            return [l:icon, 'XWhichKeyIcon' . l:color]
        endif
    endfor
    return ['', '']
endfunction

function! s:prop(group) abort
    let l:name = 'xwhichkey_' . a:group
    if empty(prop_type_get(l:name))
        call prop_type_add(l:name, {'highlight': a:group})
    endif
    return l:name
endfunction

" the menu's lines and text properties for the current level and scroll offset
function! s:render() abort
    let l:entries = s:menu.entries
    let l:cells = []
    for l:entry in l:entries
        let [l:icon, l:icon_hl] = s:icon(l:entry.desc)
        let l:parts = [
            \ [' ' . get(s:key_icons, l:entry.key, l:entry.key), 'XWhichKey'],
            \ [' → ', 'XWhichKeySeparator'],
            \ [empty(l:icon) ? '' : l:icon . ' ', l:icon_hl],
            \ [(l:entry.group ? '+' : '') . l:entry.desc, l:entry.group ? 'XWhichKeyGroup' : 'XWhichKeyDesc'],
            \ ]
        call add(l:cells, l:parts)
    endfor

    let l:gap = 3
    let l:cell_width = 20
    for l:parts in l:cells
        let l:cell_width = max([l:cell_width, strdisplaywidth(join(map(copy(l:parts), 'v:val[0]'), ''))])
    endfor
    let l:cell_width = min([l:cell_width, 44])
    let l:max_width = max([30, &columns - 8])
    let l:cols = max([1, min([len(l:cells), (l:max_width + l:gap) / (l:cell_width + l:gap)])])
    let l:rows = max([1, (len(l:cells) + l:cols - 1) / l:cols])
    let l:visible = min([l:rows, max([3, &lines / 2 - 4])])
    let s:menu.rows = l:rows
    let s:menu.visible = l:visible
    let s:menu.top = max([0, min([s:menu.top, l:rows - l:visible])])

    let l:lines = []
    for l:row in range(s:menu.top, s:menu.top + l:visible - 1)
        let l:text = ''
        let l:props = []
        for l:col in range(l:cols)
            let l:index = l:col * l:rows + l:row
            if l:index >= len(l:cells)
                break
            endif
            if l:col > 0
                let l:text .= repeat(' ', l:gap)
            endif
            let l:used = 0
            for [l:piece, l:hl] in l:cells[l:index]
                let l:piece = strdisplaywidth(l:piece) + l:used > l:cell_width
                    \ ? strcharpart(l:piece, 0, max([0, l:cell_width - l:used - 1])) . '…' : l:piece
                if !empty(l:hl) && !empty(l:piece)
                    call add(l:props, [strlen(l:text) + 1, strlen(l:piece), l:hl])
                endif
                let l:text .= l:piece
                let l:used += strdisplaywidth(l:piece)
            endfor
            let l:text .= repeat(' ', l:cell_width - l:used)
        endfor
        call add(l:lines, {'text': l:text, 'props': l:props})
    endfor

    let l:width = l:cols * l:cell_width + (l:cols - 1) * l:gap
    let l:footer = '󱊷 close   󰁮 back' . (l:rows > l:visible
        \ ? printf('   ↑↓ scroll (%d-%d/%d)', s:menu.top + 1, s:menu.top + l:visible, l:rows) : '')
    let l:footer = repeat(' ', max([0, (l:width - strdisplaywidth(l:footer)) / 2])) . l:footer
    call add(l:lines, {'text': '', 'props': []})
    call add(l:lines, {'text': l:footer, 'props': [[1, strlen(l:footer), 'XWhichKeyFooter']]})

    for l:line in l:lines
        call map(l:line.props, {_, p -> {'col': p[0], 'length': p[1], 'type': s:prop(p[2])}})
    endfor
    return [l:lines, l:width]
endfunction

function! s:title() abort
    if has_key(s:menu.opts, 'title')
        return ' ' . s:menu.opts.title . ' '
    endif
    return ' ' . join(map(copy(s:menu.path), 'get(s:key_icons, v:val, v:val)'), ' » ') . ' '
endfunction

" the screen line right above the status bar and the command line
function! s:bottom() abort
    let l:status = &laststatus == 2 || (&laststatus == 1 && winnr('$') > 1)
    return &lines - &cmdheight - l:status
endfunction

function! s:show() abort
    let s:menu.entries = s:entries(s:menu.mode, s:menu.path, get(s:menu.opts, 'buffer', 0))
    let [l:lines, l:width] = s:render()
    let l:opts = {
        \ 'pos': 'botleft',
        \ 'line': s:bottom(),
        \ 'col': max([1, (&columns - l:width - 4) / 2 + 1]),
        \ 'minwidth': l:width,
        \ 'maxwidth': l:width,
        \ 'minheight': len(l:lines),
        \ 'maxheight': len(l:lines),
        \ 'padding': [0, 1, 0, 1],
        \ 'border': [],
        \ 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
        \ 'borderhighlight': ['XWhichKeyBorder'],
        \ 'title': s:title(),
        \ 'highlight': 'XWhichKeyNormal',
        \ 'wrap': 0,
        \ 'scrollbar': 0,
        \ 'mapping': 0,
        \ 'zindex': 250,
        \ }
    if get(s:menu, 'id', 0) > 0 && !empty(popup_getpos(s:menu.id))
        call popup_settext(s:menu.id, l:lines)
        call popup_setoptions(s:menu.id, l:opts)
    else
        let l:opts.filter = function('s:filter')
        let l:opts.callback = function('s:closed')
        let s:menu.id = popup_create(l:lines, l:opts)
    endif
endfunction

function! s:closed(id, result) abort
    if get(s:menu, 'id', 0) == a:id
        let s:menu = {}
    endif
endfunction

function! s:close() abort
    if get(s:menu, 'id', 0) > 0
        call popup_close(s:menu.id)
    endif
    let s:menu = {}
endfunction

" xwhichkey#open('n', '<leader>'[, {'buffer': 1, 'title': '...'}])
function! xwhichkey#open(mode, prefix, ...) abort
    if !exists('*popup_create') || !exists('*maplist')
        return
    endif
    call s:close()
    let s:resume = {}
    let l:opts = get(a:000, 0, {})
    let s:menu = {'mode': a:mode, 'prefix': a:prefix, 'opts': l:opts, 'top': 0,
        \ 'root': s:tokens(s:norm(a:prefix))}
    let s:menu.path = copy(s:menu.root)
    if empty(s:entries(a:mode, s:menu.path, get(l:opts, 'buffer', 0)))
        let s:menu = {}
        echo 'No keymaps' . (get(l:opts, 'buffer', 0) ? ' in this buffer' : ' under ' . s:norm(a:prefix))
        return
    endif
    call s:show()
endfunction

function! s:filter(id, key) abort
    let l:key = keytrans(a:key)
    let l:entry = {}
    for l:candidate in s:menu.entries
        if l:candidate.key ==# l:key
            let l:entry = l:candidate
            break
        endif
    endfor

    if !empty(l:entry)
        if l:entry.group
            call add(s:menu.path, l:key)
            let s:menu.top = 0
            call s:show()
        else
            call s:run(l:entry)
        endif
    elseif l:key ==# '<Esc>' || l:key ==# '<C-C>'
        call s:close()
    elseif l:key ==# '<BS>' || l:key ==# '<Left>'
        if len(s:menu.path) > len(s:menu.root)
            call remove(s:menu.path, -1)
            let s:menu.top = 0
            call s:show()
        endif
    elseif has_key(s:scroll, l:key)
        let l:step = s:scroll[l:key]
        let l:page = max([1, s:menu.visible - 1])
        let s:menu.top += l:step is# 'page' ? l:page : (l:step is# '-page' ? -l:page : l:step)
        call s:show()
    endif
    " every other key is ignored while the menu is open
    return 1
endfunction

" runs the mapping by typing its keys (the full left-hand side wins over the
" <nowait> trigger), then reopens the menu once Vim is idle again
function! s:run(entry) abort
    let l:keys = s:raw(join(s:menu.path + [a:entry.key], ''))
    let s:resume = {'mode': s:menu.mode, 'prefix': s:menu.prefix, 'opts': s:menu.opts}
    call s:close()
    call feedkeys(l:keys, 'm')
endfunction

function! s:on_safe_state() abort
    if empty(s:resume)
        return
    endif
    let l:resume = s:resume
    let s:resume = {}
    " a mapping that started a command line, insert mode, ... ends the menu
    if mode(1) ==# 'n' && empty(s:menu)
        call xwhichkey#open(l:resume.mode, l:resume.prefix, l:resume.opts)
    endif
endfunction
