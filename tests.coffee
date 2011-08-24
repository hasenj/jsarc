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

# for debugging
test_read = tester_fn("read", (text) -> arc.read(text).repr())

test_read('10')
test_read('()')
test_read('(a (1 2 34) "text" c de fgh i) ; comment')
test_read('(+ 1 2 ( * 3 4))')
test_read('(if (< a b) (+ a b) ( - b a))')
test_read('(= abc 23)')

env = arc.new_env()

eval_test = tester_fn "eval", (text) -> arc.eval(arc.read(text), env)
eval_test '5'
eval_test '"hello"'
eval_test '(= x 5)'
eval_test 'x'

eval_test '(if)'
eval_test '(if 5)'
eval_test '(if 5 10)'
eval_test '(if 5 10 15)'
eval_test '(if nil 10 15)'
eval_test '(if nil 10 15 20 30)'
eval_test '(if nil 10 nil 20 30)'
eval_test '(cons 1 (cons 2 nil))'

# unit testing

test_fails = []
utest = (name, text1, text2, equal=true) ->
    if true #verbose
        rel = if equal then " -> " else " != "
        clog "test>", text1, rel, text2
    v1 = arc.eval(arc.read(text1), env)
    v2 = arc.eval(arc.read(text2), env)
    if not equal == u.isEqual(v1, v2)
        clog "Test '#{name}' faild:"
        clog "     ", text1, "   ->    ", v1
        clog "     ", text2, "   ->    ", v2
        clog "------------------"
        test_fails.push(name)


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

eval_test '(lambda args (+ args))'

eval_test "+"
eval_test "<"

eval_test "(+ 1 2 3)"
utest "plus_call1", '(+ 1 2 3)', '6'
utest "plus_call2", '(+ 4 2 3)', '9'
utest "arith_calls", '(+ (+ 3 1) 4 2)', '10'
utest "arith_calls", '(+ (+ 3 1) 2 (- 4 3))', '7'
utest "lt1", '(< 4 2 3)', 'nil'
utest "lt2", '(< 2 4 8)', 't'
utest "lt2", '(> 6 4 4 3)', 'nil'
utest "lt2", '(> 6 4 5 3)', 'nil'
utest "lt2", '(>= 6 4 4 3)', 't'

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

utest "setlist", "(= z (list 1 2 3 4))", "(list 1 2 3 4)"
utest "index2", "(z 1)", "2"

eval_test "(= f (lambda args (+ (car args) (car (cdr args)))))"
eval_test "(f 3 4)"
utest "lambda", "(f 3 4)", "7"


# -------------------------------------------------------------------
# ---------   Leave this at the end      ----------------------------

if test_fails.length
    clog "Failed tests: ", test_fails.length
    for fail in test_fails
        clog "    ", fail
else
    clog ".."
    clog "All tests passed"
