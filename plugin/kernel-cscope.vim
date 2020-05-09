"======================================================================
"
" kernel-cscope.vim - Connecting cscope db on demand for kernel dev.
" 		      Don't update db automatically becasue kernel
" 		      cscope db is huge
"
" Based on gutentags_plus.vim by skywind
" 	https://github.com/skywind3000/gutentags_plus
"
" Created-by: Jason Zeng
"
"======================================================================

set cscopequickfix=s+,c+,d+,i+,t+,e+,g+,f+,a+

" Strips the ending slash in a path.
function! s:stripslash(path)
    return fnamemodify(a:path, ':s?[/\\]$??')
endfunction

"----------------------------------------------------------------------
" strip heading and ending spaces 
"----------------------------------------------------------------------
function! s:string_strip(text)
	return substitute(a:text, '^\s*\(.\{-}\)\s*$', '\1', '')
endfunc


"----------------------------------------------------------------------
" display error message
"----------------------------------------------------------------------
function! s:ErrorMsg(msg)
	redraw! | echo "" | redraw!
	echohl ErrorMsg
	echom 'ERROR: '. a:msg
	echohl NONE
endfunc

function! s:get_project_root(path) abort
    let l:path = s:stripslash(a:path)
    let l:previous_path = ""
    let l:markers = ['.git']
    while l:path != l:previous_path
        for root in l:markers
            if !empty(globpath(l:path, root, 1))
                let l:proj_dir = simplify(fnamemodify(l:path, ':p'))
                let l:proj_dir = s:stripslash(l:proj_dir)
                if l:proj_dir != ''
                    return l:proj_dir
	        endif
            endif
        endfor
        let l:previous_path = l:path
        let l:path = fnamemodify(l:path, ':h')
    endwhile
    return ''
endfunction

"----------------------------------------------------------------------
" list cscope dbs
"----------------------------------------------------------------------
function! s:list_cscope_dbs()
	redir => cs_list
	noautocmd silent cs show
	redir END
	let records = []
	for text in split(cs_list, "\n")
		let text = s:string_strip(text)
		if text == ''
			continue
		endif
		if strpart(text, 0, 1) == '#'
			continue
		endif
		let p1 = stridx(text, ' ')
		if p1 < 0
			continue
		endif
		let p2 = stridx(text, ' ', p1 + 1)
		if p2 < 0
			continue
		endif
		let p3 = strridx(text, ' ', len(text) - 1)
		if p3 < 0 || p3 <= p2
			continue
		endif
		let db_id = strpart(text, 0, p1)
		let db_pid = strpart(text, p1 + 1, p2 - p1)
		let db_path = strpart(text, p2 + 1, p3 - p2)
		let item = {}
		let item.id = s:string_strip(db_id)
		let item.pid = s:string_strip(db_pid)
		let item.path = s:string_strip(db_path)
		let records += [item]
	endfor
	return records
endfunc

"----------------------------------------------------------------------
" check db is connected
"----------------------------------------------------------------------
function! s:db_connected(dbname)
	let record = s:list_cscope_dbs()
	for item in record
		let p1 = fnamemodify(item.path, ':p')
		let p2 = fnamemodify(a:dbname, ':p')
		let equal = 0
		if p1 == p2
			return 1
		endif
	endfor
	return 0
endfunc

function! s:cscope_db_add() abort
	if b:cscope_db_file == '' || b:cscope_project_root == ''
		call s:ErrorMsg("no database for this project, check documents")
		return
	endif
	if !filereadable(b:cscope_db_file)
		call s:ErrorMsg('cscope database is not ready yet')
		return
	endif
	let pwd = getcwd()
	let s:previous_pwd = get(s:, 'previous_pwd', '')
	if s:db_connected(b:cscope_db_file)
		if s:previous_pwd == pwd
			return
		endif
	endif
	let s:previous_pwd = pwd
	let value = &cscopeverbose
	let $CSCOPE_DB_PATH = fnamemodify(b:cscope_db_file, ':p:h')
	let $CSCOPE_DB = b:cscope_db_file
	let $CSCOPE_PRE_PATH = b:cscope_project_root
	set nocscopeverbose
	silent exec 'cs kill -1'
	"exec 'cs add '. fnameescape(b:cscope_db_file) . ' ' . fnameescape(b:cscope_project_root)
	exec 'cs add '. fnameescape(b:cscope_db_file)
	if value != 0
		set cscopeverbose
	endif
endfunc

command! -nargs=0 CscopeAdd call s:cscope_db_add()

"----------------------------------------------------------------------
" open quickfix
"----------------------------------------------------------------------
function! s:quickfix_open()
	function! s:WindowCheck(mode)
		if &buftype == 'quickfix'
			let s:quickfix_open = 1
			let s:quickfix_wid = winnr()
			return
		endif
		if a:mode == 0
			let w:quickfix_save = winsaveview()
		else
			if exists('w:quickfix_save')
				call winrestview(w:quickfix_save)
				unlet w:quickfix_save
			endif
		endif
	endfunc

	let s:quickfix_open = 0
	let l:winnr = winnr()			
	noautocmd windo call s:WindowCheck(0)
	noautocmd silent! exec ''.l:winnr.'wincmd w'
	if s:quickfix_open != 0
		noautocmd silent! exec ''.s:quickfix_wid.'wincmd w'
		return
	endif

	let l:qflist  = getqflist()
	let l:height = len(qflist)
	unlet l:qflist
	if l:height < g:cscope_quickfix_height_min
		let l:height = g:cscope_quickfix_height_min
	else
		let l:height = g:cscope_quickfix_height_max
	endif
	exec 'botright copen '. ((l:height > 0)? l:height : '')

	noautocmd windo call s:WindowCheck(1)
	noautocmd silent! exec ''.l:winnr.'wincmd w'
	noautocmd silent! exec ''.s:quickfix_wid.'wincmd w'

	if &buftype == 'quickfix'
		call cursor(2, 0)
	endif
endfunc

function! s:cscope_find(bang, what, ...)
	let keyword = (a:0 > 0)? a:1 : ''
	let dbname = b:cscope_db_file
	let root = b:cscope_project_root
	if dbname == '' || root == ''
		call s:ErrorMsg("no database for this project, check documents")
		return 0
	endif
	if a:0 == 0 || keyword == ''
		redraw! | echo '' | redraw!
		echohl ErrorMsg
		echom 'E560: Usage: CscopeFind a|c|d|e|f|g|i|s|t name'
		echohl NONE
		return 0
	endif
	if !filereadable(dbname)
		call s:ErrorMsg('database is not ready yet')
		return 0
	endif
	call s:cscope_db_add()
	let ncol = col('.')
	let nrow = line('.')
	let nbuf = winbufnr('%')
	let text = ''
	if a:what == '0' || a:what == 's'
		let text = 'symbol "'.keyword.'"'
	elseif a:what == '1' || a:what == 'g'
		let text = 'definition of "'.keyword.'"'
	elseif a:what == '2' || a:what == 'd'
		let text = 'functions called by "'.keyword.'"'
	elseif a:what == '3' || a:what == 'c'
		let text = 'functions calling "'.keyword.'"'
	elseif a:what == '4' || a:what == 't'
		let text = 'string "'.keyword.'"'
	elseif a:what == '6' || a:what == 'e'
		let text = 'egrep "'.keyword.'"'
	elseif a:what == '7' || a:what == 'f'
		let text = 'file "'.keyword.'"'
	elseif a:what == '8' || a:what == 'i'
		let text = 'files including "'.keyword.'"'
	elseif a:what == '9' || a:what == 'a'
		let text = 'assigned "'.keyword.'"'
	endif
	let text = "[cscope ".a:what.": ".text."]"
	let title = "CscopeFind ".a:what.' "'.keyword.'"'
	silent exec 'cexpr text'
	if has('nvim') == 0 && (v:version >= 800 || has('patch-7.4.2210'))
		call setqflist([], 'a', {'title':title})
	elseif has('nvim') && has('nvim-0.2.2')
		call setqflist([], 'a', {'title':title})
	elseif has('nvim')
		call setqflist([], 'a', title)
	else
		call setqflist([], 'a')
	endif
	" call setqflist([{'text':text}], 'a')
	let success = 1
	try
		exec 'cs find '.a:what.' '.fnameescape(keyword)
		redrawstatus
	catch /^Vim\%((\a\+)\)\=:E259/
		redrawstatus
		echohl ErrorMsg
		echo "E259: not find '".keyword."'"
		echohl NONE
		let success = 0
	catch /^Vim\%((\a\+)\)\=:E567/
		redrawstatus
		echohl ErrorMsg
		echo "E567: no cscope connections"
		echohl NONE
		let success = 0
	catch /^Vim\%((\a\+)\)\=:E/
		redrawstatus
		echohl ErrorMsg
		echo "ERROR: cscope error"
		echohl NONE
		let success = 0
	endtry
	if winbufnr('%') == nbuf
		call cursor(nrow, ncol)
	endif
	if success != 0 && a:bang == 0
		call s:quickfix_open()
	endif
endfunc
command! -nargs=+ -bang CscopeFind call s:cscope_find(<bang>0, <f-args>)

"----------------------------------------------------------------------
" Kill all connections
"----------------------------------------------------------------------
function! s:cscope_kill()
	silent cs kill -1
	echo "All cscope connections have been closed."
endfunc

command! -nargs=0 CscopeKill call s:cscope_kill()

function! s:setup_cscope() abort
	if &buftype != ''
		return
	endif

	let b:cscope_project_root = s:get_project_root(expand('%:p:h', 1))
	if b:cscope_project_root != ''
		let b:cscope_db_file = b:cscope_project_root . "/cscope.out"
	else
		let b:cscope_db_file = ''
	endif
endfunc

augroup cscope_detect
    autocmd!
    autocmd BufNewFile,BufReadPost,BufEnter *  call s:setup_cscope()
    autocmd VimEnter               *  if expand('<amatch>')==''|call s:setup_cscope()|endif
augroup end

"----------------------------------------------------------------------
" setup keymaps
"----------------------------------------------------------------------
func! s:FindCwordCmd(cmd, is_file)
    let cmd = ":\<C-U>" . a:cmd
    if a:is_file == 1
        let cmd .= " " . expand('<cfile>')
    else
        let cmd .= " " . expand('<cword>')
    endif
    let cmd .= "\<CR>"
    return cmd
endf

nnoremap <silent> <expr> <Plug>CscopeFindSymbol     <SID>FindCwordCmd('CscopeFind s', 0)
nnoremap <silent> <expr> <Plug>CscopeFindDefinition <SID>FindCwordCmd('CscopeFind g', 0)
nnoremap <silent> <expr> <Plug>CscopeFindCalledFunc <SID>FindCwordCmd('CscopeFind d', 0)
nnoremap <silent> <expr> <Plug>CscopeFindCallingFunc <SID>FindCwordCmd('CscopeFind c', 0)
nnoremap <silent> <expr> <Plug>CscopeFindText       <SID>FindCwordCmd('CscopeFind t', 0)
nnoremap <silent> <expr> <Plug>CscopeFindEgrep      <SID>FindCwordCmd('CscopeFind e', 0)
nnoremap <silent> <expr> <Plug>CscopeFindFile       <SID>FindCwordCmd('CscopeFind f', 1)
nnoremap <silent> <expr> <Plug>CscopeFindInclude    <SID>FindCwordCmd('CscopeFind i', 1)
nnoremap <silent> <expr> <Plug>CscopeFindAssign     <SID>FindCwordCmd('CscopeFind a', 0)
nnoremap <silent> <expr> <Plug>CscopeFindCtag       <SID>FindCwordCmd('CscopeFind z', 0)

nmap <silent> <C-\>s <Plug>CscopeFindSymbol
nmap <silent> <C-\>g <Plug>CscopeFindDefinition
nmap <silent> <C-\>c <Plug>CscopeFindCallingFunc
nmap <silent> <C-\>t <Plug>CscopeFindText
nmap <silent> <C-\>e <Plug>CscopeFindEgrep
nmap <silent> <C-\>f <Plug>CscopeFindFile
nmap <silent> <C-\>i <Plug>CscopeFindInclude
nmap <silent> <C-\>d <Plug>CscopeFindCalledFunc
nmap <silent> <C-\>a <Plug>CscopeFindAssign
nmap <silent> <C-\>z <Plug>CscopeFindCtag
nmap <silent> <C-\>k :CscopeKill<cr>

