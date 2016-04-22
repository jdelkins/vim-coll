" =============================================================================
" Filename: autoload/coll.vim
" Author: jdelkins
" License: MIT License
" =============================================================================

let s:save_cpo = &cpo
set cpo&vim


" Immutable list functions                                                  {{{

function! coll#reverse(l) abort
  let new_list = deepcopy(a:l)
  if type(a:l) == type([])
    call reverse(new_list)
  endif
  return new_list
endfunction

function! coll#append(l, val) abort
  let new_list = deepcopy(a:l)
  if type(a:l) == type([])
    call add(new_list, a:val)
  elseif type(a:l) == type({}) && type(a:val) == type([])
    let new_list[a:val[0]] = a:val[1]
  endif
  return new_list
endfunction

function! coll#assoc(l, i, val) abort
  let new_list = deepcopy(a:l)
  let new_list[a:i] = a:val
  return new_list
endfunction

function! coll#pop(l, i) abort
  let new_list = deepcopy(a:l)
  call remove(new_list, a:i)
  return new_list
endfunction

"}}}

" Function: lambda()                                                        {{{
" Purpose: create a dynamic, anonymous function
" Arguments:
"   ...    The commands (as strings) defining function. These commands can have
"          side effects, like setting globals, or can be calculations. If you
"          want your lambda function to return something, you have to provide
"          a "return" command.
" Returns: a Funcref for the function. When the function is
"          called, any provided arguments are available via with a:1, a:2,
"          etc. Also a:000 works, of course.
" Side Effects: The function is not really anonymous; it will be a real
"               function with a name defined with a random number. When you are
"               done using it, it would be a good idea to :delfunction it:
"                  :let F = Lambda("return 'hello world'")
"                  :echo F()
"                  :delfunction F
" TODO: This is pretty dangerous because there is basically no error checking.
"       It is done with simple string manipulation.

function! s:rand() abort
    return str2nr(matchstr(reltimestr(reltime()), '\v\.@<=\d+')[1:])
endfunction

if !exists('s:lambda_serial')
  let s:lambda_serial = s:rand()
endif

function! coll#lambda(...) abort
  return call('s:lambda', a:000)
endfunction

function! s:lambda(...) abort
  let s:lambda_serial += 1
  let statements = join(a:000, "\n")
  let funcname = 's:lambda_'.s:lambda_serial
  exe 'function! '.funcname."(...) abort\n".statements."\nendfunction"
  return function(funcname)
endfunction

" }}}

" Function: reduce()                                                        {{{
" Purpose:
"   Collapse a list into a single value by using the function provided in the
"   first argument (a string containing an expression). The lambda argument will
"   be called as a function in turn for each pair of list items. Three arguments
"   will be made available to this function:
"     acc: The accumulator, which starts out as the first list item, and is given
"        the result of each successive call of the function
"     key: The index of the item being processed
"     val: The next list item to process
"   These can also be accessed with a:1, a:2, and a:3 respectively
" Arguments:
"   lambda    A string expression to calculate the accumlator given a starting
"             accumulator and a value from the list. Described more above.
"   start_val A starting accumulator value. The type of this argument
"             necessarily defines the return type of the function call
"   list      A list or dictionary over which to iterate
" Returns:
"   A value of the type provided by start_val, which is the accumulated result
"   of the lambda calculation over the list.
" Side Effects: None intended.

function! coll#reduce(lambda, start_val, list) abort
  if empty(a:list)
    return v:null
  endif
  let F = s:lambda('let [acc,key,val]=a:000[:2]', 'return ('.a:lambda.')')
  if type(a:list) == type([])
    let acc = a:start_val
    let key = 0
    for val in a:list
      let acc = F(acc, key, val)
      let key += 1
    endfor
  elseif type(a:list) == type({})
    let acc = a:start_val
    for [key,val] in items(a:list)
      let acc = F(acc, key, val)
    endfor
  endif
  delfunction F
  return acc
endfunction

" }}}

" Function: map()                                                           {{{
" Purpose:
"   Like the built-in map() but uses Lambda and operates on any number of lists.
"   Returns a new list; the arguments are not affected.
" Arguments:
"   lambda     A string expression defining the operation to be performed.
"              This will be made into an anonymous function and called for each
"              pair of list items. Inside the function, the elements can be
"              accessed with the "key", "val1", and "val2" variables.
"
"   ...        Either any number of lists or dicts to be operated on. All must
"              be the same type. If lists are given, the shortest one will
"              define the length of the result list. If dicts are given, the
"              intersection of all the keys will be the key set in the result
"              dict.
" Returns:
"  A new list or dict, depending on the type of the list arguments. The size is
"  the smallest of the given source lists. If the lists were actually dicts,
"  then the keys of the result will be the interesection of the two dicts'
"  keys.

function! coll#map(lambda, ...) abort
  if !a:0
    throw 'Map: Insufficient arguments: at least one list or dict required'
  endif
  for l in a:000
    if type(l) != type(a:1) || index([type([]), type({})], type(l)) < 0
      throw 'Map: Incompatible argument types (must be all lists or all dicts)'
    endif
  endfor
  if type(a:1) == type([])
    return call('s:map_lists', [a:lambda] + a:000)
  elseif type(a:1) == type({})
    return call('s:map_dicts', [a:lambda] + a:000)
  endif
endfunction

function! s:map_lists(lambda, ...) abort
  let stmts = ['let key = a:1']
  let lens = []
  let c = 1
  for l in a:000
    call add(lens, len(l))
    call add(stmts, 'let val'.c.' = a:'.(c+1))
    let c += 1
  endfor
  call add(stmts, 'return ('.a:lambda.')')
  let F = call('s:lambda', stmts)
  let res = []
  let key = 0
  while key < min(lens)
    let args = [key]
    for l in a:000
      call add(args, l[key])
    endfor
    call add(res, call(F, args))
    let key += 1
  endwhile
  delfunction F
  return res
endfunction

function! s:map_dicts(lambda, ...) abort
  let stmts = ['let key = a:1']
  if !a:0
    return {}
  endif
  let ks = keys(a:1)
  let c = 1
  for d in a:000
    call filter(ks, 'index(keys(d), v:val) >= 0')
    call add(stmts, 'let val'.c.' = a:'.(c+1))
    let c += 1
  endfor
  call add(stmts, 'return ('.a:lambda.')')
  let F = call('s:lambda', stmts)
  let res = {}
  for key in ks
    let args = [key]
    for d in a:000
      call add(args, d[key])
    endfor
    let res[key] = call(F, args)
  endfor
  delfunction F
  return res
endfunction

" }}}

" Function: filter()                                                        {{{
" Purpose:
"   Like the builtin filter(), but uses Lambda and returns a new list (not an
"   in place operation).
" Arguments:
"   lambda    A string expression which should be a true/false test as to
"             whether to include the item in the resulting list. In this
"             function, the variables "val" and "key" are available to test.
"   list      The originating list or dictionary
" Returns: A list or dictionary depending on the type of list provided

function! coll#filter(lambda, list) abort
  let res = []
  let F = s:lambda('let [key,val]=a:000[:1]', 'return ('.a:lambda.')')
  if type(a:list) == type([])
    let key = 0
    for val in a:list
      if F(key, val)
        call add(res, deepcopy(val))
      endif
      let key += 1
    endfor
  elseif type(a:list) == type({})
    let res = {}
    for [key,val] in items(a:list)
      if F(key, val)
        let res[key] = deepcopy(val)
      endif
    endfor
  endif
  delfunction F
  return res
endfunction

" }}}

" Function: sort()                                                          {{{
" Purpose:
"   Sort a list using a user-defined predicate. Returns a new list. Like the
"   built-in sort() but returns a copied list and takes the sorting predicate
"   as a code string rather than a funcref
" Arguments:
"   lambda    A string, which is a VimL expression comparing two values,
"             taken from the list. These can be accessed as val1 and val2.
"             The expression should yield <0, 0, or >0 depending based on
"             whether val1 <, =, or > val2.
"   list      The originating list or dictionary
" Returns: A list or dictionary depending on the type of list provided

function! coll#sort(lambda, list) abort
  let F = s:lambda('let [val1,val2]=a:000[:1]', 'return ('.a:lambda.')')
  let l = sort(copy(a:list), F)
  delfunction F
  return l
endfunction

" }}}

let &cpo = s:save_cpo
unlet s:save_cpo
" vim:set fdm=marker:
