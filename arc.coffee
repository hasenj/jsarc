# lisp expressions reader

u = require "underscore"

clog = console.log

tok_re = 
    'ws': /\s+/
    'comment': /;.*/
    'num': /\d+/
    'paren': /[()\[\]{}\.]/ # special symbols
    'string': /"(([^"])|(\\"))*[^\\]"/ # a bitch to debug (stolen from sibilant)
    'sym': /(\w|[_+\-*/=!?<>:~\.!])+/ # aka identifier
    'quoting': /'|`|,@|,/ # reader macros .. 

class Skip
    constructor: ->

class Atom
    constructor: (@type, @value) ->

tok_skip = ['ws', 'comment']
tok_atom = ['num', 'sym', 'string']
tok_syntax = ['paren', 'quoting']

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

# helper
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

# helper
token = (text) ->
    # read a token and return the start of next token
    # returns [t, text] where t is the token and text is the new string
    for type, regex of tok_re
        res = readToken(text, regex, type)
        if res
            return res
    return null # EOF

# returns a reader function
reader = (text) ->
    fn = () ->
        res = token(text)
        if not res
            return null #EOF
        [tok,text] = res
        if tok.constructor.name == 'Skip'
            return fn()
        return tok

exports.reader = reader

class Pair
    constructor: (@car, @cdr) ->
        @type = 'cons'

cons = (car, cdr) -> new Pair car, cdr
car = (pair) -> pair.car
cdr = (pair) -> pair.cdr

sym = (name) -> new Atom('sym', name)

# empty lists are represented with nil, so that () is nil
t = sym('t')
nil = sym('nil')

quoting_map = 
    "'": 'quote'
    '`': 'quasiquote'
    ',': 'unquote'
    ',@': 'unquote-splicing'

# read a single lisp expression
read_lisp = (r) ->

    expand_quoting = (quote_char) ->
        s = new Atom 'sym', quoting_map[quote_char]
        exp = read_lisp(r)
        cons(s, cons(exp, nil))

    # r is a reader function
    read_list = () ->
        item = r()
        if item == '('
            cons(read_list(), read_list())
        else if item == ')' or item == null
            nil
        else if item == '.' # single dot must not be wrapped as a symbol by tokenizer above
            obj = read_lisp(r) # in recursion .. this element will be the cdr of the pair
            # potential problem can arise with things like ( . x) which should be illegal but would pass this parser
            close = r() # swallow the closing paren
            obj
        else if item of quoting_map
            cons(expand_quoting(item), read_list())
        else
            cons(item, read_list())

    item = r()
    if item == '('
        read_list()
    else if item of quoting_map
        expand_quoting(item)
    else
        item

# takes a string and parses it into a "lisp" expression
read = (s) ->
    read_lisp(reader(s))

exports.read = read

Pair.prototype.repr = ->
    "( " + @car.repr() + " . " + @cdr.repr() + " )"
Atom.prototype.repr = ->
    @type + "(" + @value + ")"

builtins = {t, nil} # builtins ..

class Env
    constructor: (@parent, bindings) ->
        @syms = u.clone bindings
    spawn: ->
        # spawns a child environment
        new Env(this, {})
    has: (sym) ->
        sym of @syms or (@parent and @parent.has(sym))
    set: (sym, val) ->
        # if symbol defined in a parent scope, set it there, not here
        if @parent and @parent.has(sym)
            @parent.set(sym, val)
        else
            @syms[sym] = val
    set_local: (sym, val) ->
        @syms[sym] = val
    get: (sym) ->
        if sym of @syms
            @syms[sym]
        else if @parent
            @parent.get(sym)
        else
            null # for undefined

new_env = -> new Env null, builtins
exports.new_env = new_env

# -- time for eval !! ---

special_forms = {} # special form processors: a function that processes each form
# The function should expect to receive the cons cell for that form, and the environment in which it's evaluated
# see '=' below

call_function = -> console.log "dummy call handler"
ssyntax = -> console.log "dummy ss checker"
ssexpand = -> console.log "dummy ss expander"

eval = (exp, env) ->
    if exp.type == 'sym'
        if ssyntax(exp) # special syntax, expand then eval the expansion
            eval ssexpand(exp), env
        else # regular symbol
            env.get(exp.value)

    else if exp.type == 'cons' 
        if car(exp).type == 'sym' and car(exp).value of special_forms
                special_forms[car(exp).value](exp, env)
        else
            head = eval(car(exp), env)
            call_function(head, exp, env) # head might be a function, or anything else, (macro, etc), it's all the same from here on as far as we're concerned

    else # if exp.type in ['num', 'string']
        exp

exports.eval = eval

special_forms['='] = (exp, env) ->
    # just assume that car(cons) is the symbol '=', don't even check for it
    # assume (= sym val) for now
    # later should extended so that it handles places, not just symbols, 
    # e.g. (= place val)
    place = car cdr exp
    val = eval(car(cdr(cdr(exp))), env)
    if place.type == 'sym'
        sym_name = place.value
        env.set(sym_name, val)
    else 
        place = eval(place, env)
        # delete all keys from place and replace them the keys from val
        # XXX this might be the wrong way to do it because it creates a copy (should it just refer to it??)
        # needs testing
        for k in u.keys(place)
            delete place[k]
        for k in u.keys(val)
            place[k] = val[k]
    return val

is_nil = (val) -> val.type == 'sym' and val.value == 'nil'

special_forms['if'] = (exp, env) ->
    # (if) : nil
    # (if x) : x
    # (if t a ...): a (where t means not nil)
    # (if nil a b): b
    # (if nil a b c ...): (if b c ....)
    if is_nil cdr(exp) # (if)
        nil
    else if is_nil (cdr(cdr(exp))) # (if x)
        car(cdr(exp))
    else
        cond = eval(car(cdr(exp)), env)
        if not is_nil(cond) # (if t a ...)
            car(cdr(cdr(exp))) # third element
        else # false!!
            if is_nil (cdr(cdr(cdr(cdr(exp))))) # list has 4 elements (a b c d) only
                car cdr cdr cdr exp # return the forth element
            else # transform (if nil a b c ...) to (if b c ...)
                if_exp = cons(car(exp), (cdr(cdr(cdr(exp)))))
                special_forms['if'](if_exp, env) # recurse with the transformed expression

destructuring_bind = (structure, exp, env) ->
    if structure.type == 'sym' # recursion's end
        env.set_local(structure.value, exp)
    else if structure.type == 'cons' # now recurse
        destructuring_bind(structure.car, exp.car, env)
        if not is_nil structure.cdr # what if exp.cdr is not nil??
            destructuring_bind(structure.cdr, exp.cdr, env)
    else # you fail!
        console.log "Error, expecting symbol, but got", structure.type
        console.log "###ERROR"


# a native datatype
class Lambda
    # parent_env: scope where the lambda is created
    constructor: (parent_env, @args_structure, @body) ->
        @type = 'lambda'
        @env = parent_env.spawn()
    call: (args_cons, call_env)->
        # whatever this call does to the environment should *not* affect
        # future calls
        call_env = u.clone @env
        # assume each item in args_cons are already eval'ed
        destructuring_bind(@args_structure, args_cons, call_env)
        do_ = (exp_list)=>
            v = eval(car(exp_list), call_env)
            if not is_nil(cdr(exp_list))
                return do_ cdr exp_list
            else
                return v
        do_ @body

    repr: ->
        'lambda(' + @args_structure + '){' + @body.repr() + '}'

special_forms['fn'] = (exp, env) ->
    # (fn args_structure . body)
    # args_structure is a symbol, unevaluated ..
    args_st = (car cdr exp)
    body = cdr cdr exp # unevaluated ... only evaluates when function is called ..
    new Lambda(env, args_st, body)

special_forms['quote'] = (exp, env) ->
    # exp is (quote x)
    # we're quoting the first argument, (car (cdr exp))
    car cdr exp

special_forms['quasiquote'] = (exp, env) ->
    # This one is tough!
    # start by acting like quote
    exp = car cdr exp
    # now traverse this tree to unquote things that need unquoting
    transform = (exp) ->
        # do things ..
        if exp.type != 'cons'
            return exp
        if car(exp).type == 'sym'
            if car(exp).value == 'unquote'
                return eval(car(cdr(exp)), env)
        if car(exp).type == 'cons'
            if car(car(exp)).type == 'sym'
                if car(car(exp)).value == 'unquote-splicing'
                    # ((unquote-splicing X)) -> X1 X2 X3
                    # car is: (unqote-splicing X)
                    # cdr of that is (X nil)
                    # car of that is X
                    # so, X is car of the cdr of the car of the expression
                    # TEMP for now, same as unquote
                    # unquote the cdr and replace the car with it ..
                    return eval(car(cdr(car(exp))), env)
        # then recurse
        exp.car = transform (car(exp))
        exp.cdr = transform (cdr(exp))
        return exp

    transform(exp)

special_forms['eval'] = (exp, env) ->
    # the arguments are unevaled at this point ..
    exp = eval(exp.cdr.car, env)
    eval exp, env
    
class BuiltinFunction
    constructor: (@js_fn) ->
        # js_fn expects arguments to be lisp expressions, not js native types (e.g. atoms, not numbers)
        # js_fn returns a lisp expression
        @type = 'lambda' # cheating ..!!
    call: (args_cons, env) ->
        # assume each item in args_cons are already eval'ed
        @js_fn args_cons, env
    repr: ->
        'builtin-function'

parseNumber = (atom) -> parseInt atom.value # placeholder, temporary or not?

# make builtin arithmetic operators
(->
    ops =
        '+': (a,b) -> a + b
        '-': (a,b) -> a - b
        '*': (a,b) -> a * b
        '/': (a,b) -> a / b

    # Note: there's some funny business with number values being passed around as "strings" ..

    op_fn = (fn) ->
        # turns a simple js function to a lispy builtin-function that deals with lisp lists
        (args) ->
            # arg is assumed to be a lisp list (cons)
            val = parseNumber car args # TODO error handling?
            args = cdr args # pop ..
            while not is_nil(args)
                v1 = parseNumber car args
                val = fn(val, v1)
                args = cdr args # pop ..
            # guess type
            new Atom('num', val.toString())

    for op, fn of ops
        builtins[op] = new BuiltinFunction op_fn(fn)

    ops = 
        '<': (a,b) -> a < b
        '>': (a,b) -> a > b
        '<=': (a,b) -> a <= b
        '>=': (a,b) -> a >= b
        
    op_fn = (fn) ->
        # turns a simple js function to a lispy builtin-function that deals with lisp lists
        (args) ->
            # arg is assumed to be a lisp list (cons)
            v0 = parseNumber car args # TODO error handling?
            args = cdr args # pop ..
            res = true
            while not is_nil(args)
                v1 = parseNumber car args
                res = fn(v0, v1)
                if not res # short-circuit
                    return nil
                v0 = v1
                args = cdr args # pop ..
            return t

    for op, fn of ops
        builtins[op] = new BuiltinFunction op_fn(fn)
)()

# implement function calls ..
call_function = (call_object, exp, env) ->
    # exp is the whole expression, including the function object at its head
    if not call_object
        clog "LISP ERROR!", car(exp).value,  "is not a function"
    if call_object.type == 'lambda' # if it's a function
        # call it
        # first, eval all remaining things in the expression
        do_eval_list = (exp) ->
            if is_nil exp
                nil
            else
                head = eval(car(exp), env)
                cons(head, do_eval_list(cdr exp))

        # then pass them to the function 
        evaled_list = do_eval_list(cdr exp)
        call_object.call(evaled_list)
    else if call_object.type == 'cons' # list, treat as index function, e.g.  (a b) -> a[b]
        index = eval(car(cdr(exp)), env)
        index = parseNumber index
        item = call_object
        while index > 0
            item = cdr item
            index -= 1
        car item

to_arc_bool = (bool) ->
    if bool then t else nil

to_lisp_list = (list) -> # takes a js list and turns it to a cons list
    if not list.length
        nil
    else
        cons(list[0], to_lisp_list(list[1...]))

# special syntax
# e.g. 
# a:b:~c
# a.b
# a!b
ssyntax = (symbol) -> symbol.value.match(/:|~|\.|!/)

ssexpand = (symbol) ->
    if symbol.value.match(/:|~/)
        list = symbol.value.split(':')
        expand_tilde = (s) ->
            # s is a plain string
            if s[0] == '~'
                to_lisp_list [sym('complement'), sym(s[1...])]
            else
                sym(s)
        list = u.map(list, expand_tilde)
        list.unshift(sym 'compose')
        to_lisp_list(list)
    else if symbol.value.match(/\.|!/)
        list = symbol.value.replace(/!/g, ".'").split('.')
        symify = (s)->
            if s[0] == '\''
                to_lisp_list [sym('quote'), sym(s[1...])]
            else
                sym(s)
        list = u.map(list, symify)
        expanded = list.shift()
        while list.length != 0
            expanded = to_lisp_list [expanded, list.shift()]
        expanded
    else
        symbol


# -----------------------
# add cons, car, cdr to global builtins
builtins['list'] = new BuiltinFunction( (exp) -> exp )
builtins['cons'] = new BuiltinFunction( (exp) -> cons(car(exp), car(cdr(exp))) )
builtins['car'] = new BuiltinFunction ( (exp) -> car car exp ) # exp is a list of one element, we want the car of that element
builtins['cdr'] = new BuiltinFunction ( (exp) -> cdr car exp ) # exp is a list of one element, we want the cdr of that element

builtins['ssyntax'] = new BuiltinFunction( (exp) -> to_arc_bool(ssyntax exp.car) )
builtins['ssexpand'] = new BuiltinFunction( (exp) -> ssexpand exp.car )


# ---------------------------------- display -------------------
disp = (lisp_object) ->

    disp_list_inner = (obj, sep='') ->
        if is_nil obj
            ''
        else if obj.type != 'cons'
            sep + '. ' + disp obj
        else
            sep + disp(obj.car) + disp_list_inner(obj.cdr, sep=' ')

    if lisp_object.type == 'cons'
        # display list .. 
        # HACK for now
        '(' + disp_list_inner(lisp_object) + ')'
    else if lisp_object.type == 'lambda'
        '<lambda>'
    else 
        lisp_object.value

exports.disp = disp

