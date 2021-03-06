# lisp expressions reader

u = require "underscore"

clog = console.log

class LispError 
    constructor:(@msg...) ->
        

err = (msg...) ->
    # the ... is so we can call it like console.log
    throw new LispError(msg.join ' ')


tok_re = 
    'ws': /\s+/
    'comment': /;.*/
    'num': /\d+/
    'paren': /[()\[\]{}\.]/ # syntactic symbols
    'string': /"(([^"])|(\\"))*[^\\]"/ # a bitch to debug (stolen from sibilant)
    'sym': /(\w|[_+\-*\/=!?<>:~\.!])+/ # aka identifier
    'quoting': /'|`|,@|,/ 

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
    # r is a reader function

    expand_quoting = (quote_char) ->
        s = sym quoting_map[quote_char]
        exp = read_lisp(r)
        cons(s, cons(exp, nil))

    make_anon_fn = (exp) ->
        # turn exp into the body of an anon function
        # do it like arc:
        # [x] -> (make-br-fn (x))
        m = sym 'make-br-fn'
        to_lisp_list [m, exp]

    read_list = () ->
        item = r()
        if item == '('
            cons(read_list(), read_list())
        else if item == '['
            cons(make_anon_fn(read_list()), read_list())
        else if item == ')' or item == ']' or item == null # why do we check for null?
            nil
        else if item == '.' # single dot must not be wrapped as a symbol by tokenizer above
            obj = read_lisp(r) # in recursion .. this element will be the cdr of the pair
            # potential problem can arise with things like ( . x) which should be illegal but would pass this parser
            close = r() # we need to swallow the closing paren
            # because we too "end" the recursion, if we don't swallow it, it will end the recursion of the outer list
            obj
        else if item of quoting_map
            cons(expand_quoting(item), read_list())
        else
            cons(item, read_list())

    item = r()
    if item == '('
        read_list()
    else if item == '['
        make_anon_fn(read_list())
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
        # XXX this needs a better thought out way to handle it
        if @has_local(sym)
            @set_local(sym, val)
        else
            # if sym is not bound in this scope, look for it in parent scope
            if @parent 
                @parent.set(sym, val)
            else # no more outer scopes; this is the global scope; set it here
                @set_local(sym, val)
    set_local: (sym, val) ->
        @syms[sym] = val
    has_local: (sym) ->
        sym of @syms
    get: (sym) ->
        if sym of @syms
            @syms[sym]
        else if @parent
            @parent.get(sym)
        else
            err 'symbol', sym, 'is not bound.'
    disp: ->
        ("(#{a}: #{disp b})" for a, b of @syms).join('') + (if @parent then (" # " + @parent.disp()) else "")
        

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
        if exp.car.type == 'sym' and exp.car.value of special_forms
                special_forms[exp.car.value](exp, env)
        else
            head = eval(exp.car, env)
            call_function(head, exp, env) # head might be a function, or anything else, (macro, etc), it's all the same from here on as far as we're concerned

    else # if exp.type in ['num', 'string']
        exp

exports.eval = eval

is_nil = (val) -> val.type == 'sym' and val.value == 'nil'
js_bool = (val) -> not is_nil val

special_forms['='] = (exp, env) ->
    # just assume that car(cons) is the symbol '=', don't even check for it
    # (= place val ...)
    assign = (exp) ->
        # exp is now (place val ...) or (place)
        place = exp.car
        if not is_nil exp.cdr
            val = eval(exp.cdr.car, env)
        else
            val = nil
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
        # shift (a b c d) to (c d)
        # unless it's (a) then just change it to nil
        if exp.cdr.cdr? and not is_nil exp.cdr.cdr
            assign exp.cdr.cdr
        else
            val
    assign(exp.cdr)

special_forms['if'] = (exp, env) ->
    # (if) : nil
    # (if x) : x
    # (if t a ...): a (where t means not nil)
    # (if nil a b): b
    # (if nil a b c ...): (if b c ....)
    if is_nil exp.cdr # (if)
        nil
    else if is_nil exp.cdr.cdr # (if x)
        eval exp.cdr.car, env
    else
        cond = eval(exp.cdr.car, env)
        if not is_nil(cond) # (if t a ...)
            eval exp.cdr.cdr.car, env # third element
        else # false!!
            if is_nil exp.cdr.cdr.cdr.cdr # list has 4 elements (a b c d) only
                eval exp.cdr.cdr.cdr.car, env # return the forth element
            else # transform (if nil a b c ...) to (if b c ...)
                if_exp = cons(exp.car, exp.cdr.cdr.cdr)
                special_forms['if'](if_exp, env) # recurse with the transformed expression

destructuring_bind = (structure, exp, env) ->
    if structure.type == 'sym' # recursion's end
        env.set_local(structure.value, exp)
    else if structure.type == 'cons' # now recurse
        destructuring_bind(structure.car, exp.car, env)
        if not is_nil structure.cdr # what if exp.cdr is not nil??
            destructuring_bind(structure.cdr, exp.cdr, env)
    else # you fail!
        err "Expecting symbol, but got", structure.repr()


# a native datatype
class Lambda
    # parent_env: scope where the lambda is created
    constructor: (@parent_env, @args_structure, @body) ->
        @type = 'lambda'
    call: (args_cons)->
        # assume each item in args_cons are already eval'ed
        call_env = @parent_env.spawn()
        destructuring_bind(@args_structure, args_cons, call_env)
        do_ = (exp_list)=>
            v = eval(exp_list.car, call_env)
            if not is_nil(exp_list.cdr)
                return do_ exp_list.cdr
            else
                return v
        do_ @body

    repr: ->
        'lambda' 

class Macro
    constructor: (@parent_env, @arg_st, @body) ->
        @type = 'mac'
    call: (args_cons, env) ->
        # args_cons is not evaled, and @lambda.call won't eval it (assumes already evaled)
        # exp should be the quoted code generated by @lambda
        lambda = new Lambda(@parent_env, @arg_st, @body)
        exp = lambda.call(args_cons) # macro expansion
        eval(exp, env)

    repr: ->
        'mac'

special_forms['fn'] = (exp, env) ->
    # (fn args_structure . body)
    # args_structure is a symbol, unevaluated ..
    args_st = exp.cdr.car
    body = exp.cdr.cdr # unevaluated ... only evaluates when function is called ..
    new Lambda(env, args_st, body)

special_forms['quote'] = (exp, env) ->
    # exp is (quote x)
    # we're quoting the first argument, (car (cdr exp))
    exp.cdr.car

special_forms['quasiquote'] = (exp, env) ->
    # This one is tough!
    # start by acting like quote
    exp = exp.cdr.car
    # now traverse this tree to unquote things that need unquoting
    transform = (exp) ->
        if exp.type != 'cons'
            return exp
        if exp.car.type == 'sym'
            if exp.car.value == 'unquote'
                return eval(exp.cdr.car, env)
        if exp.car.type == 'cons'
            if exp.car.car.type == 'sym'
                if exp.car.car.value == 'unquote-splicing'
                    # ((unquote-splicing X)) -> X1 X2 X3
                    # car is: (unqote-splicing X)
                    # cdr of that is (X nil)
                    # car of that is X
                    # so, X is car of the cdr of the car of the expression
                    return eval(exp.car.cdr.car, env)
        # then recurse
        new_car = transform exp.car
        new_cdr = transform exp.cdr
        return cons(new_car, new_cdr)

    exp = transform(exp)

special_forms['eval'] = (exp, env) ->
    # the arguments are unevaled at this point ..
    exp = eval(exp.cdr.car, env)
    eval exp, env

special_forms['var'] = (exp, env) ->
    # not in arc:
    # (var sym val)
    # binds sym to val locally and returns val
    bind = (exp) ->
        # exp is (a b ..) or (a)
        ident = exp.car.value
        if js_bool exp.cdr
            val = eval(exp.cdr.car, env)
        else
            val = nil
        env.set_local(ident, val)
        if exp.cdr.cdr? and not is_nil exp.cdr.cdr
            bind exp.cdr.cdr
        else
            val
    bind exp.cdr
    
    
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
        err exp.car.value,  "is not a function"
    if call_object.type == 'lambda' # if it's a function
        # call it
        # first, eval all remaining things in the expression
        do_eval_list = (exp) ->
            if is_nil exp
                nil
            else
                head = eval(exp.car, env)
                cons(head, do_eval_list(exp.cdr))

        # then pass them to the function 
        evaled_list = do_eval_list(exp.cdr)
        call_object.call(evaled_list)

    else if call_object.type == 'mac' 
        call_object.call(exp.cdr, env)

    else if call_object.type == 'cons' # list, treat as index function, e.g.  (a b) -> a[b]
        index = eval(exp.cdr.car, env)
        index = parseNumber index
        item = call_object
        while index > 0
            item = cdr item
            index -= 1
        car item
    else
        err (disp call_object), "can't be used as a function"

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



special_forms['mac'] = (exp, env) ->
    # (mac name args . body)
    name = exp.cdr.car # assumed to be a sym
    args = exp.cdr.cdr.car
    body = exp.cdr.cdr.cdr
    m = new Macro(env, args, body)
    env.set(name.value, m)
    m


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
    else if lisp_object.type == 'mac'
        '<macro>'
    else if lisp_object.disp?
        lisp_object.disp()
    else if lisp_object.value?
        lisp_object.value
    else
        "<??!#{lisp_object}!!?>"

exports.disp = disp

