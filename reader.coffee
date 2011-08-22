# lisp expressions reader

_ = u = require "underscore"

alist = u.isArray

tok_re = 
    'ws': /\s+/
    'comment': /;.*/
    'num': /\d+/
    'paren': /[()\[\]{}]/ # special symbols
    'string': /"(([^"])|(\\"))*[^\\]"/ # a bitch to debug (stolen from sibilant)
    'sym': /(\w|_)+/ # aka identifier
    # 'special': /['`,@]/ # reader macros .. 

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
    m = matchtok(regex, text)
    if m
        token = m[0]
        # convert strings into js format, and maybe lisp number into objects, etc!
        # token = process_<type>(token) 
        rem = text[token.length..]
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
    return null

reader = (text) ->
    fn = () ->
        res = token(text)
        if not res
            return null
        [tok,text] = res
        console.log tok
        # if tok.type == skip
        #    return fn() # recurse
        return tok

read_lisp = (r) ->
    # r is a reader function
    result = []
    while t = r()
        # debug:
        # console.log "read ", t
        if t == '('
            result.push(read_lisp(r))
        else if t == ')'
            break
        else if t[0] in [' ', '\t', ';'] # skip comments and whitespace
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

test_read('(a (1 2 3) "text" c d) ; comment')

