arc = require "./arc"
u = require "underscore"

clog = console.log

# Generate a tester function
# A tester function takes a raw strig, processes it according to some function,
# and prints the string before and after processing
tester_fn = (name, fn) ->
    (str) ->
        clog name + ">", str
        clog fn(str)
        clog

env = arc.new_env()

eval = (text) ->
    arc.eval(arc.read(text), env)

safe_eval = (text) ->
    try
        arc.disp eval(text)
    catch e
        if e.constructor.name == 'LispError'
            e.msg.join ''
        else
            e.stack

ueval = tester_fn "eval", safe_eval

ueval '5'
ueval '"hello"'
ueval '(= x 5)'
ueval 'x'

# unit testing

test_fails = []
utest = (name, text1, text2, equal=true) ->
    if true #verbose
        rel = if equal then " -> " else " != "
        clog "test>", text1, rel, text2
    try
        v1 = eval(text1)
        v2 = eval(text2)
        if not equal == u.isEqual(v1, v2)
            clog "Test '#{name}' faild:"
            clog "     ", text1, "   ->    ", v1.repr()
            clog "     ", text2, "   ->    ", v2.repr()
            clog "------------------"
            test_fails.push(name)
    catch e
        clog "Test '#{name}' faild:"
        clog "Error was raised: ", e.constructor.name
        if e.constructor.name == 'LispError'
            clog e.msg...
        else
            clog e.stack
        test_fails.push(name)


ueval "(= a 5 b 10 c 15 d 20)"
utest "=0", "a", "5"
utest "=1", "b", "10"
utest "=2", "c", "15"
utest "=3", "d", "20"
utest "if1", '(if)', 'nil'
utest "if2", '(if a)', 'a'
utest "if3", '(if a b)', 'b'
utest "if4", '(if a b)', 'a', false
utest "if5", '(if a b c)', 'b'
utest "if6", '(if nil a b)', 'a', false
utest "if6", '(if nil a b)', 'b'
utest "if7", '(if nil a b c d)', 'c'
utest "if8", '(if nil a nil b c)', 'c'

utest "=4", "(= a 1)", "1"
utest "=5", "(= a 1 b 2)", "2"
utest "=6", "(= a 1 b)", "nil"
utest "=7", "b", "nil"

ueval '(fn args (+ args))'

ueval "+"
ueval "<"

ueval "(+ 1 2 3)"
utest "plus_call1", '(+ 1 2 3)', '6'
utest "plus_call2", '(+ 4 2 3)', '9'
utest "arith_calls", '(+ (+ 3 1) 4 2)', '10'
utest "arith_calls", '(+ (+ 3 1) 2 (- 4 3))', '7'
utest "lt1", '(< 4 2 3)', 'nil'
utest "lt2", '(< 2 4 8)', 't'
utest "lt2", '(> 6 4 4 3)', 'nil'
utest "lt2", '(> 6 4 5 3)', 'nil'
utest "lt2", '(>= 6 4 4 3)', 't'

ueval "(list 1 2 3 4)"
ueval "(car (list 1 2 3))"
ueval "(cdr (list 1 2 3))"
ueval "(cons 1 (cons 2 nil))"
ueval "(cons 1 2)"
ueval "(car (cons 1 2))"

utest "listcons", "(cons 1 (cons 2 (cons 3 nil)))", "(list 1 2 3)"
utest "carlist", "(car (list 1 2 3))", "1"

utest "set", "(= y 5)", "5"
utest "var", "(+ y 3)", "8"

ueval "((list 4 5 6 7 8 9) 2)"

utest "index1", "((list 4 5 6 7 8 9) 2)", "6"

utest "setlist", "(= z (list 1 2 3 4))", "(list 1 2 3 4)"
utest "index2", "(z 1)", "2"

ueval "(= f (fn args (+ (car args) (car (cdr args)))))"
ueval "(f 3 4)"
utest "fn", "(f 3 4)", "7"

ueval "(= c 10)"
ueval "(= d (list 4 5 3))"
ueval "(quote a)"
ueval "(quote (a b c d))"
ueval "(list `a)"
ueval "c"
ueval "`(a b ,c)"
 
utest "quote", "(quote (a b c d))", "(list (quote a) (quote b) (quote c) (quote d))"

utest "qquote0", "`a", "(quasiquote a)"

utest "quote0", "'a", "(quote a)"
utest "quote1", "(list 'a 1)", "(list (quote a) 1)"
utest "quote2", "'''a", "(quote (quote (quote a)))"
utest "quote3", "'(a b ,c)", "(quote (a b (unquote c)))"
utest "quote4", "`(a b ,c)", "(quasiquote (a b (unquote c)))"
utest "quote5", "`(a b ,c)", "`(a b 10)"
utest "quote6", "`(a b ,c ,@d)", "(quasiquote (a b (unquote c) (unquote-splicing d)))"
utest "quote6", "`(a b ,c ,@d)", "`(a b 10 4 5 3)"

utest "eval0", "(eval 'c)", "c"
utest "eval1", "(eval 'c)", "10"
utest "eval2", "(eval '(+ 1 2 3))", "(+ 1 2 3)"
utest "eval3", "(eval '(+ 1 2 3))", "6"


utest "ss0", "(ssexpand 'a:b)", "'(compose a b)"
utest "ss1", "(ssexpand 'a:~b)", "'(compose a (complement b))"
utest "ss2", "(ssexpand 'a:~b:c)", "'(compose a (complement b) c)"

utest "ss10", "(ssexpand 'a.b)", "'(a b)"
utest "ss11", "(ssexpand 'a!b)", "'(a (quote b))"
# I ran this in arc, and got:
# arc> (ssexpand 'a.b.c!d!f.t.y)
# ((((((a b) c) (quote d)) (quote f)) t) y)
utest "ss12", "(ssexpand 'a.b.c!d!f.t.y)", "'((((((a b) c) (quote d)) (quote f)) t) y)"

ueval "(= a (list 9 8 7 6 5))"
ueval "(= b 2)"
utest "ss20", "a.b", "(a b)"
utest "ss21", "a.b", "7"

utest "fn0", "((fn (a b) (+ b 4)) 5 6)", "10"
utest "fn1", "((fn (a b . c) c) 5 6 1 2 3 4)", "(list 1 2 3 4)"

ueval "(= a (fn (a b) (+ a b)))"
utest "scope0", "(a 3 4)", "7"
utest "scope1", "(a 3 4)", "7" # test that setting 'a' inside the function doesn't disturb the global 'a'

ueval "(mac def (name args . body) `(= ,name (fn ,args ,@body)))"
ueval "(def avg (x y) (/ (+ x y) 2))"
utest "macdef", "(avg 20 10)", "15"
utest "macdef", "(avg 30 20)", "25"

ueval "(def avg2 (a b) (/ (+ b a) 2))"
utest "macdef2", "(avg2 30 10)", "20"

ueval "(= a 10)"
ueval "(def local_test (k) (+ k (if (> k 6) a (var a 20))))" # if param given <= 6 it declares a local a = 20 and adds it to k, else just adds global a to k
utest "var0", "(local_test 8)", "18"
utest "var1", "(local_test 2)", "22"
utest "var2", "a", "10"

utest "var3", "(var a 10 b 20 c)", "nil"
utest "var4", "a", "10"
utest "var5", "b", "20"


# -------------------------------------------------------------------
# ---------   Leave this at the end      ----------------------------

if test_fails.length
    clog "Failed tests: ", test_fails.length
    for fail in test_fails
        clog "    ", fail
else
    clog "........"
    clog "All tests passed"
