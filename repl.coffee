arc = require "./arc"
env = arc.new_env()

process.stdout.write "type #oops to get unstuck\n\n"
(prompt = ->
    process.stdout.write "jsarc>")()

stdin = process.openStdin()
stdin.setEncoding('utf8')

current_exp = ""

unmatched_braces = (text) ->
    r = arc.reader(text) 
    op_count = 0
    cl_count = 0
    while t = r()
        if t == '('
            op_count += 1
        if t == ')'
            cl_count += 1
    if op_count > cl_count
        return true
    else
        return false


stdin.on 'data', (chunk) ->
    # seems we receive this when user hits enter, 
    # so I'll just assume that to be the case
    current_exp += chunk
    if unmatched_braces(current_exp)
        process.stdout.write "...."
    else
        exp = current_exp
        current_exp = "" # not sure if this trick is needed ..
        val = arc.eval(arc.read(exp), env)
        # process.stdout.write val
        if val
            console.log arc.disp val
        else
            console.log "#ERROR"
        prompt()

stdin.on 'end', ->
    process.stdout.write('end')

