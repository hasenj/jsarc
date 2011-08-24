# lisp expressions reader

_ = u = require "underscore"
alist = u.isArray

tok_re = 
    'ws': /\s+/
    'comment': /;.*/
    'num': /\d+/
    'paren': /[()\[\]{}]/ # special symbols
    'string': /"(([^"])|(\\"))*[^\\]"/ # a bitch to debug (stolen from sibilant)
    'sym': /(\w|[_+\-*/@=!?<>])+/ # aka identifier
    # 'quoting': /'|`|,@|,/ # reader macros .. 

class Skip
    constructor: ->

class Atom
    constructor: (@type, @value) ->

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
    return null # EOF

reader = (text) ->
    fn = () ->
        res = token(text)
        if not res
            return null #EOF
        [tok,text] = res
        if tok.constructor.name == 'Skip'
            return fn()
        return tok

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

# read a single lisp expression
read_lisp = (r) ->
    # r is a reader function
    read_list = () ->
        item = r()
        if item == '('
            cons(read_list(), read_list())
        else if item == ')' or item == null
            nil
        else
            cons(item, read_list())

    item = r()
    if item == '('
        read_list()
    else
        item

# takes a string and parses it into a "lisp" expression
read = (s) ->
    read_lisp(reader(s))

clog = console.log

Pair.prototype.repr = ->
    "( " + @car.repr() + " . " + @cdr.repr() + " )"
Atom.prototype.repr = ->
    @type + "(" + @value + ")"

# Generate a tester function
# A tester function takes a raw strig, processes it according to some function,
# and prints the string before and after processing
tester_fn = (name, fn) ->
    (str) ->
        clog name + ">", str
        clog fn(str)
        clog

# for debugging
test_read = tester_fn("read", (text) -> read(text).repr())

test_read('10')
test_read('()')
test_read('(a (1 2 34) "text" c de fgh i) ; comment')
test_read('(+ 1 2 ( * 3 4))')
test_read('(if (< a b) (+ a b) ( - b a))')
test_read('(= abc 23)')

global_bindings = {t, nil, cons, car, cdr} # builtins ..

class Env
    constructor: (@parent=null, bindings=global_bindings) ->
        # this is wrong, should do a copy
        @syms = global_bindings
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
    get: (sym) ->
        if sym of @syms
            @syms[sym]
        else if @parent
            @parent.get(sym)
        else
            null # for undefined

#TODO define some Function class too and somehow make it have its own Env

# -- time for eval !! ---


special_forms = {} # special form processors: a function that processes each form
# The function should expect to receive the cons cell for that form, and the environment in which it's evaluated
call_function = -> clog "dummy call handler"

eval = (exp, env) ->
    if exp.type == 'sym'
       env.get(exp.value)

    else if exp.type == 'cons' 
        if car(exp).type == 'sym' and car(exp).value of special_forms
                special_forms[car(exp).value](exp, env)
        else
            head = eval(car(exp), env)
            call_function(head, exp, env) # head might be a function, or anything else, (macro, etc), it's all the same from here on as far as we're concerned

    else # if exp.type in ['num', 'string']
        exp

special_forms['='] = (cons, env) ->
    # just assume that car(cons) is the symbol '=', don't even check for it
    # assume (= sym val) for now
    # later should extended so that it handles places, not just symbols, 
    # e.g. (= place val)
    sym = car(cdr(cons)).value
    val = eval(car(cdr(cdr(cons))), env)
    env.set(sym, val)
    return val

env = new Env
eval_test = tester_fn "eval", (text) -> eval(read(text), env)
eval_test '5'
eval_test '"hello"'
eval_test '(= x 5)'
eval_test 'x'

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

eval_test '(if)'
eval_test '(if 5)'
eval_test '(if 5 10)'
eval_test '(if 5 10 15)'
eval_test '(if nil 10 15)'
eval_test '(if nil 10 15 20 30)'
eval_test '(if nil 10 nil 20 30)'
eval_test '(cons 1 (cons 2 nil))'

# unit testing

uenv = new Env
utest = (name, text1, text2, equal=true) ->
    if true #verbose
        rel = if equal then " -> " else " != "
        clog "test>", text1, rel, text2
    v1 = eval(read(text1), env)
    v2 = eval(read(text2), env)
    if not equal == u.isEqual(v1, v2)
        clog "Test '#{name}' faild:"
        clog "     ", text1, "   ->    ", v1
        clog "     ", text2, "   ->    ", v2
        clog "------------------"


eval_test '(if)'
utest "if1", '(if)', 'nil'
utest "if2", '(if 5)', '5'
utest "if3", '(if 5 10)', '10'
utest "if4", '(if 5 10)', '5', false
utest "if5", '(if 5 10 15)', '10'
utest "if6", '(if nil 10 15)', '10', false
utest "if6", '(if nil 10 15)', '15'
utest "if7", '(if nil 10 15 20 30)', '20'
utest "if8", '(if nil 10 nil 20 30)', '30'

# a native datatype
class Lambda
    # parent_env: scope where the lambda is created
    constructor: (parent_env, @args_sym_name, @body) ->
        @type = 'lambda'
        @env = parent_env.spawn()
    call: (args_cons, call_env)->
        # assume each item in args_cons are already eval'ed
        @env.set(@args_sym_name, args_cons)
        do_ = (exp_list)->
            v = eval(car(exp_list), @env)
            if not is_nil(cdr(exp_list))
                return do_ cdr exp_list
            else
                return v
        do_ @body

    repr: ->
        'lambda(' + @args_sym_name + '){' + @body.repr() + '}'

special_forms['lambda'] = (exp, env) ->
    # (lambda args_var_name exp exp exp ...)
    # args_var_name is a symbol, unevaluated ..
    # assert (car cdr exp).type == 'sym' # TODO enable this when you decide how to build error reporting ..
    args_sym_name = (car cdr exp).value
    body = car cdr cdr exp # unevaluated ... only evaluates when function is called ..
    new Lambda(env, args_sym_name, body)
    
eval_test '(lambda args (+ args))'

class BuiltinFunction
    constructor: (@js_fn) ->
        # js_fn expects arguments to be lisp expressions, not js native types (e.g. atoms, not numbers)
        # js_fn returns a lisp expression
        @type = 'lambda' # cheating ..!!
    call: (args_cons, env) ->
        # assume each item in args_cons are already eval'ed
        @js_fn args_cons
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
        global_bindings[op] = new BuiltinFunction op_fn(fn)

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
        global_bindings[op] = new BuiltinFunction op_fn(fn)
)()

eval_test "+"
eval_test "<"

# implement function calls ..
call_function = (call_object, exp, env) ->
    # exp is the whole expression, including the function object at its head
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


eval_test "(+ 1 2 3)"
utest "plus_call1", '(+ 1 2 3)', '6'
utest "plus_call2", '(+ 4 2 3)', '9'
utest "lt1", '(< 4 2 3)', 'nil'
utest "lt2", '(< 2 4 8)', 't'
utest "lt2", '(> 6 4 4 3)', 'nil'
utest "lt2", '(> 6 4 5 3)', 'nil'
utest "lt2", '(>= 6 4 4 3)', 't'

# -----------------------
# add cons, car, cdr to global builtins
global_bindings['list'] = new BuiltinFunction( (exp) -> exp )
global_bindings['cons'] = new BuiltinFunction( (exp) -> cons(car(exp), car(cdr(exp))) )
global_bindings['car'] = new BuiltinFunction ( (exp) -> car car exp ) # exp is a list of one element, we want the car of that element
global_bindings['cdr'] = new BuiltinFunction ( (exp) -> cdr car exp ) # exp is a list of one element, we want the cdr of that element

eval_test "(list 1 2 3 4)"
eval_test "(car (list 1 2 3))"
eval_test "(cdr (list 1 2 3))"
eval_test "(cons 1 (cons 2 nil))"
eval_test "(cons 1 2)"
eval_test "(car (cons 1 2))"

utest "listcons", "(cons 1 (cons 2 (cons 3 nil)))", "(list 1 2 3)"
utest "carlist", "(car (list 1 2 3))", "1"

utest "set", "(= y 5)", "5"
utest "var", "(+ y 3)", "8"

eval_test "((list 4 5 6 7 8 9) 2)"

utest "index1", "((list 4 5 6 7 8 9) 2)", "6"

uenv = new Env
utest "setlist", "(= z (list 1 2 3 4))", "(list 1 2 3 4)"
utest "index2", "(z 1)", "2"
