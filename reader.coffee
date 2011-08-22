# lisp expressions reader

_ = u = require "underscore"
alist = u.isArray

tok_re = 
    'ws': /\s+/
    'comment': /;.*/
    'num': /\d+/
    'paren': /[()\[\]{}]/ # special symbols
    'string': /"(([^"])|(\\"))*[^\\]"/ # a bitch to debug (stolen from sibilant)
    'sym': /(\w|[_+\-*/@!?<>])+/ # aka identifier
    # 'quoting': /'|`|,@|,/ # reader macros .. 

class Skip
    constructor: ->

class Atom
    constructor: (@type, @value) ->
    toString: @value

tok_skip = ['ws', 'comment']
tok_atom = ['num', 'sym', 'string']
tok_syntax = ['paren'] #, 'quoting']

matchtok = (regex, text) ->
    if m = text.match('^(' + regex.source + ')')
        m[0]
    else
        false

toktype = (text, type) ->
    regex = alref(tok_re, type)
    if matchtok(regex, text)
        return true
    return false

readToken = (text, regex, type) ->
    token = matchtok(regex, text)
    if token
        rem = text[token.length..]
        # process tokens
        if type in tok_skip
            token = new Skip
        else if type in tok_atom
            token = new Atom type, token
        else if type in tok_syntax
            token = token # keep ..
        return [token, rem]
    else
        return null

token = (text) ->
    # read a token and return the start of next token
    # returns [t, text] where t is the token and text is the new string
    for type, regex of tok_re
        res = readToken(text, regex, type)
        if res
            return res
    return null # what's this for?

reader = (text) ->
    () ->
        res = token(text)
        if not res
            return null
        [tok,text] = res
        return tok

read_lisp = (r) ->
    # r is a reader function
    result = []
    while t = r()
        # debug:
        if t == '('
            result.push(read_lisp(r))
        else if t == ')'
            break
        else if t.constructor.name == 'Skip'
            continue
        else
            result.push(t) # atom
    return result

read = (s) ->
    read_lisp(reader(s))[0]

clog = console.log

# Generate a tester function
# A tester function takes a raw strig, processes it according to some function,
# and prints the string before and after processing
tester_fn = (name, fn) ->
    (str) ->
        clog name + ">", str
        clog fn(str)
        clog

# for debugging
test_read = tester_fn("read", read)

test_read('(a (1 2 34) "text" c de fgh i) ; comment')
test_read('(+ 1 2 (* 3 4))')
test_read('(if (< a b) (+ a b) (- b a))')

