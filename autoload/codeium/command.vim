function! codeium#command#BrowserCommand() abort
  if has('win32') && executable('rundll32')
    return 'rundll32 url.dll,FileProtocolHandler'
  elseif isdirectory('/private') && executable('/usr/bin/open')
    return '/usr/bin/open'
  elseif executable('xdg-open')
    return 'xdg-open'
  else
    return ''
  endif
endfunction

function! codeium#command#XdgConfigDir() abort
  let config_dir = $XDG_CONFIG_HOME
  if empty(config_dir)
    let config_dir = $HOME . '/.config'
  endif
  return config_dir . '/codeium'
endfunction

function! codeium#command#HomeDir() abort
  let data_dir = $XDG_DATA_HOME
  if empty(data_dir)
    let data_dir = $HOME . '/.codeium'
  else
    let data_dir = data_dir . '/.codeium'
  endif
  return data_dir
endfunction

function! codeium#command#LoadConfig(dir) abort
  let config_path = a:dir . '/config.json'
  if filereadable(config_path)
    let contents = join(readfile(config_path), '')
    if !empty(contents)
      return json_decode(contents)
    endif
  endif

  return {}
endfunction

function! s:ApiKeyFromConfig(config) abort
  return get(a:config, 'apiKey', get(a:config, 'api_key', ''))
endfunction

function! s:ResolveApiKey() abort
  for dir in [$HOME . '/.config/Codeium', codeium#command#HomeDir(), $HOME . '/.codeium', codeium#command#XdgConfigDir()]
    let key = s:ApiKeyFromConfig(codeium#command#LoadConfig(dir))
    if !empty(key)
      return key
    endif
  endfor
  return ''
endfunction

let s:api_key = s:ResolveApiKey()

let s:commands = {}

function! s:commands.Auth(...) abort
  if !codeium#util#HasSupportedVersion()
    if has('nvim')
      let min_version = 'NeoVim 0.6'
    else
      let min_version = 'Vim 9.0.0185'
    endif
    echoerr 'This version of Vim is unsupported. Install ' . min_version . ' or greater to use Codeium.'
    return
  endif
  if a:0 > 0 && !empty(a:1)
    let api_key = trim(a:1)
  else
    call inputsave()
    let api_key = trim(input('Paste your Codeium API key (dari ~/.config/Codeium/config.json): '))
    call inputrestore()
    echom ''
  endif
  if empty(api_key)
    echomsg 'Codeium: API key kosong, dibatalkan.'
    return
  endif
  let s:api_key = api_key
  for config_dir in [$HOME . '/.config/Codeium', codeium#command#HomeDir()]
    let config_path = config_dir . '/config.json'
    let config = codeium#command#LoadConfig(config_dir)
    let config.apiKey = api_key
    try
      call mkdir(config_dir, 'p')
      call writefile([json_encode(config)], config_path)
    catch
      call codeium#log#Error('Could not persist api key to ' . config_path)
    endtry
  endfor
  echomsg 'Codeium: API key disimpan ke ~/.config/Codeium/config.json (tanpa call server).'
endfunction

function s:commands.Chat(...) abort
  call codeium#Chat()
endfunction

function! s:commands.Disable(...) abort
  let g:codeium_enabled = 0
endfunction

function! s:commands.DisableBuffer(...) abort
  let b:codeium_enabled = 0
endfunction

" Run codeium server only if its not already started
function! codeium#command#StartLanguageServer() abort
  if !get(g:, 'codeium_server_started', v:false)
    call timer_start(0, function('codeium#server#Start'))
    let g:codeium_server_started = v:true
  endif
endfunction

function! s:commands.Enable(...) abort
  let g:codeium_enabled = 1
  call codeium#command#StartLanguageServer()
endfunction

function! s:commands.EnableBuffer(...) abort
  let b:codeium_enabled = 1
  call codeium#command#StartLanguageServer()
endfunction

function! s:commands.Toggle(...) abort
  if exists('g:codeium_enabled') && g:codeium_enabled == v:false
      call s:commands.Enable()
  else
      call s:commands.Disable()
  endif
endfunction

function! codeium#command#ApiKey() abort
  if empty(s:api_key)
    let s:api_key = s:ResolveApiKey()
  endif
  if empty(s:api_key)
    echom 'Codeium: No API key found di ~/.config/Codeium/config.json; jalankan `:Codeium Auth <api_key>`'
  endif
  return s:api_key
endfunction

function! codeium#command#Complete(arg, lead, pos) abort
  let args = matchstr(strpart(a:lead, 0, a:pos), 'C\%[odeium][! ] *\zs.*')
  return sort(filter(keys(s:commands), { k -> strpart(k, 0, len(a:arg)) ==# a:arg }))
endfunction

function! codeium#command#Command(arg) abort
  let cmd = matchstr(a:arg, '^\%(\\.\|\S\)\+')
  let arg = matchstr(a:arg, '\s\zs\S.*')
  if !has_key(s:commands, cmd)
    return 'echoerr ' . string("Codeium: command '" . string(cmd) . "' not found")
  endif
  let res = s:commands[cmd](arg)
  if type(res) == v:t_string
    return res
  else
    return ''
  endif
endfunction
