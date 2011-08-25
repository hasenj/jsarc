arc = require "./arc"

process.stdout.write "type #oops to get unstuck\n\n"
(prompt = ->
    process.stdout.write "arc>")()

stdin = process.openStdin()
stdin.setEncoding('utf8')

stdin.on 'data', (chunk) ->
  process.stdout.write('data: ' + chunk)
  prompt()

stdin.on 'end', ->
  process.stdout.write('end')

