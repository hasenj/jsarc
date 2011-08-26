arc = require "./arc"
env = arc.new_env()

process.stdout.write "type #oops to get unstuck\n\n"
(prompt = ->
    process.stdout.write "jsarc> ")()

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
    if chunk.match(/#oops\n$/)
        current_exp = ""
        console.log "No worries"
        prompt()
        return

    current_exp += chunk

    if current_exp == "#reload\n"
        current_exp = ""
        arc = require "./arc"
        console.log "not here yet :/"
        prompt()
        return

    if unmatched_braces(current_exp)
        process.stdout.write "...."
    else
        exp = current_exp
        current_exp = "" # not sure if this trick is needed ..
        try
            val = arc.eval(arc.read(exp), env)
            # process.stdout.write val
            if val
                console.log arc.disp val
            else
                console.log "#ERROR"
        catch e
            console.log "eval barfed"
            console.log e.stack
        prompt()

stdin.on 'end', ->
    console.log "\nend of input\n"

