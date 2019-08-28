colors = require 'colors'
prompt = require 'prompt'
fs = require 'fs'
cheerio = require 'cheerio'
html5Lint = require 'html5-lint'
q = require 'q'
Entities = require('html-entities').XmlEntities
entities = new Entities()

module.exports = class App

  sourcePath: undefined

  constructor: ->
    console.log "process.cwd()".cyan, process.cwd()

    @showHtmFiles().then () =>
      @startPrompt()


  showHtmFiles: ->
    deferred = q.defer()
    fs.readdir process.cwd(), (err, files) ->
      if err
        console.log 'err:'.red, err
        deferred.reject err 
      else
        filesByExt = files.filter (file) ->
          file.indexOf('htm') isnt -1

        if filesByExt.length is 0
          console.log 'No HTML files found!'.red
          deferred.reject()
        else
          console.log 'HTML files:', (filesByExt.join(', ')).yellow
          deferred.resolve()

    deferred.promise


  startPrompt: ->
    console.log "Please enter directory path".blue.bold
    prompt.start()

    promptSchema =
      properties:
        source:
          pattern: /^[a-zA-Z0-9\/\\\-_.:]+$/
          message: 'Source must be only letters, numbers and/or dashes, dots'
          required: true
          #default: '../Vertbaudet/resadmin/VertbaudetFr/campagnes/96_S34_RDC_HEADER/_test.htm'
          default: '_test.htm'

    prompt.get promptSchema, (err, result) =>
      if err
        console.log "error:".red, err
      else
        console.log 'Command-line input received:'.green
        console.log 'source:', (result.source).cyan
        @sourcePath = process.cwd() + '/' + result.source

        console.log 'Source path is:', (@sourcePath).green

        @readFile()


  readFile: ->
    console.log '\n\nLook for <img >'.blue
    fs.readFile @sourcePath, 'utf8', (err, data) =>
      if err
        console.log 'err:'.red, err
      else
        regex = /<img[^\>]+>/ig
        imgs = data.match regex

        cheerioImgsObject = {}
        for img in imgs
          cheerioImgsObject[img] = cheerio.load img

          @imgHandle cheerioImgsObject[img]('img')
          #console.log ' ====> '.yellow, cheerioImgsObject[img]('body').html()

        for key, cImg of cheerioImgsObject
          imgHtml = cImg('body').html()
          imgHtml = imgHtml.replace /&quot;/g, "'"
          imgHtml = imgHtml.replace /([^\/])>/g, "$1/>"
          imgHtml = imgHtml.replace /data-image="{'src': '([^<]*)'}"/g, "data-image='{\"src\": \"$1\"}'"

          imgDecoded = entities.decode imgHtml

          escapedKey = key.replace /[\\[.+*?(){|^$]/g, "\\$&"
          console.log 'REPLACE:'.magenta, key, '<===>'.yellow, imgDecoded
          regexKey = new RegExp escapedKey, 'gi'
          data = data.replace regexKey, imgDecoded

        @writeHtml data


  imgHandle: (pChImg) ->

    if not pChImg.attr('alt')
      console.log 'This img has no "alt"!'

      if pChImg.attr('src') and pChImg.attr('src') isnt 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw=='
        imageName = pChImg.attr('src')
      else
        if pChImg.attr('data-src')
          imageName = pChImg.attr('data-src')
        else
          if pChImg.attr('data-image')
            imageName = pChImg.attr('data-image').match /data-image="{'src': '([^<]*)'}"/
            if not imageName
              imageName = pChImg.attr('data-image').match /data-image='{"src": "([^<]*)"}'/
            console.log ' alt imageName (from "data-image") :', imageName

      if imageName
        # Remove extension
        imageName = imageName.replace /\.[^.]*$/, ""
        # Remove - and _
        imageName = imageName.replace /[_]+|[\-]+/g, " "
        # Transform in lowercase
        imageName = imageName.toLowerCase()

        pChImg.attr 'alt', imageName
        console.log '"alt" replaced with:'.green, imageName
      else
        console.log 'No imageName found for "alt"'.red

    if pChImg.attr('title') is ''
      console.log ' Remove empty title attribute'
      pChImg.removeAttr 'title'

    if pChImg.attr('border')
      style = ''
      if pChImg.attr('style')
        style = pChImg.attr('style').trim()
        if style[style.length - 1] isnt ';'
          style = style + ';'
      console.log ' Remove border attribute', (style + 'border: ' + pChImg.attr('border') + ';')
      pChImg.attr 'style', style + 'border: ' + pChImg.attr('border') + ';'
      pChImg.removeAttr 'border'

    if pChImg.attr('data-src') and not pChImg.attr('src')
      console.log ' data-src is defined and src is not defined'
      console.log ' => We replace the src with 1px transparent'.magenta.bold
      pChImg.attr('src', 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==')

    if not pChImg.attr('data-src') and pChImg.attr('src') and pChImg.attr('src') isnt 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw=='
      console.log ' data-src is not defined and src is defined but isn\'t 1px transparent'
      console.log ' => We add new attributes for the lazy loading'.magenta.bold

      pChImg.attr 'data-loaded', 'false'

      pChImg.attr 'onload', 'javascript:LazyLoadHelper.loadElement(this);'

      pChImg.attr 'data-image', '{"src": "' + pChImg.attr('src') + '"}'
      pChImg.attr 'src', 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw=='


  writeHtml: (pData) ->
    console.log 'Overwrite file !!!'.yellow
    fs.writeFile @sourcePath, pData, 'utf8', (err, data) =>
      if err
        console.log ' Error to write the file'.red, err
      else
        console.log ' The file has been overwritten'.green

        @checkHtml5(@sourcePath).then () ->
          console.log 'Completed!'.green


  checkHtml5: (pPath) ->
    console.log '\nHTML5 LINTER'.blue
    deferred = q.defer()
    fs.readFile pPath, 'utf8', (err, html) ->
      if err
        throw err

      html5Lint html, (err, results) ->
        results.messages.forEach (msg) ->
          console.log 'HTML5 Lint message:'.red, msg.message
          console.log '           extract:'.red, msg.extract, (' (' + msg.lastLine + ')').blue

        deferred.resolve()

    deferred.promise

app = new App()
