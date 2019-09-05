colors = require 'colors'
prompt = require 'prompt'
fs = require 'fs'
cheerio = require 'cheerio'
html5Lint = require 'html5-lint'
q = require 'q'
commandLineArgs = require 'command-line-args'
Entities = require('html-entities').XmlEntities
entities = new Entities()

module.exports = class App

  sourcePath: undefined

  scssFilePath: undefined
  scssData: undefined
  scssAnalyse: undefined

  constructor: ->
    console.log "process.cwd()".cyan, process.cwd()

    optionDefinitions = [
      { name: 'scss', alias: 's', type: String }
    ]

    options = commandLineArgs optionDefinitions
    console.log 'options:', options

    @getFilesByExt('htm').then () =>

      if options.scss
        @scssProcessus options.scss

      else
        @getFilesByExt('scss').then (scssFiles) =>
          if scssFiles.length is 1
            @scssFilePath = scssFiles[0]
            @scssProcessus @scssFilePath
          else
            console.log ('0 or more than 1 scss files found! (' + scssFiles + ')').red
            @startPrompt()


  scssProcessus: (pPath) ->
    @getBackgroundsInScss pPath
    .then (pScssData) =>
      @scssData = pScssData
      @startPrompt()


  getFilesByExt: (pExt) ->
    deferred = q.defer()
    fs.readdir process.cwd(), (err, files) ->
      if err
        console.log 'err:'.red, err
        deferred.reject err
      else
        filesByExt = files.filter (file) ->
          file.indexOf('.' + pExt) isnt -1

        if filesByExt.length is 0
          console.log ('No .' + pExt + ' files found!').red
          deferred.reject()
        else
          console.log ' => .' + pExt + ' files:', (filesByExt.join(', ')).yellow
          deferred.resolve filesByExt

    deferred.promise


  getBackgroundsInScss: (pPath) ->
    console.log 'Background images SCSS analyse start!'.magenta
    deferred = q.defer()

    fs.readFile pPath, 'utf8', (err, data) =>
      if err
        console.log 'err:'.red, err
      else
        regex = /background(\-image)?[\s]*:[\s]*url\(([^)]*)\)[;]?/gi
        bgs = data.match regex

        @scssAnalyse = {}

        for bg in bgs
          #console.log '\nbg:'.blue, bg
          bgEsc = bg.replace /[\\[.+*?(){|^$]/g, "\\$&"
          re = new RegExp '&?([.#]{1}[^.# {\)]+)[^.#]*{[^{]*' + bgEsc + '[^}]*}', 'gi'
          regData = re.exec data

          if regData and regData[0]
            bloc = regData[0]
            #console.log 'bloc:', bloc

          if regData and regData[1]
            classOrId = regData[1]
            #console.log 'classOrId:'.green, classOrId
            @scssAnalyse[classOrId] =
              background: bg
              block: bloc
          else
            #console.log 'regData:'.red, regData

          if bloc.indexOf('lazy-bg') is -1
            #console.log 'The block doesn\'t contains ".lazy-bg" ?'
            if classOrId then @scssAnalyse[classOrId]['lazy-bg'] = no
          else
            #console.log 'The block already contains ".lazy-bg" ? ', bloc.indexOf 'lazy-bg'
            if classOrId then @scssAnalyse[classOrId]['lazy-bg'] = yes

        deferred.resolve data

    deferred.promise


  addLazyPartInScssPart: (pVal) ->
    if not pVal['lazy-bg']
      # Be really careful with \s or \(, we need to protect the \
      # And sure we need to protect the ' too.
      regBg = new RegExp '(([ \\t]*)background[^;]*:[\\s]*url\\([^)]*\\)[^;]*;)', 'gi'
      newPart = pVal.block.replace regBg, '$1\n$2&.lazy-bg {\n$2  background-image: none;\n$2}'
      console.log '=====> newPart'.yellow, newPart
      @scssData = @scssData.replace pVal.block, newPart


  analyseHtmlForBackground: (pHtmlData) ->
    console.log '\nAnalyse background images'

    cheerioElemsObject = {}
    for key, val of @scssAnalyse
      #console.log '\nkey, val =>', key, val

      if key and key.substr(0, 1) is '.'
        className = key.substr 1
        # Be really careful with \s, we need to protect the \
        # And sure we need to protect the ' too.
        classRe = new RegExp '<[^>]*class=[^>]*[\\s|"|\']{1}' + className + '[\\s|"|\']{1}[^>]*>', 'gi'
        classElems = pHtmlData.match classRe

        if classElems
          for elem in classElems
            cheerioElemsObject[elem] = cheerio.load elem
            cheerEl = cheerioElemsObject[elem]('.' + className)
            cheerEl.addClass 'lazy-bg'
            cheerEl.attr 'data-loaded', 'false'

          @addLazyPartInScssPart val
        else
          console.log ('No DOM elements found for ' + className + ' class!').red

      if key and key.substr(0, 1) is '#'
        idName = key.substr 1
        # Be really careful with \s, we need to protect the \
        # And sure we need to protect the ' too.
        idRe = new RegExp '<[^>]*id=[^>]*[\\s|"|\']{1}' + idName + '[\\s|"|\']{1}[^>]*>', 'gi'
        idElems = pHtmlData.match idRe

        if idElems
          for elem in idElems
            cheerioElemsObject[elem] = cheerio.load elem
            cheerEl = cheerioElemsObject[elem]('#' + idName)
            cheerEl.addClass 'lazy-bg'
            cheerEl.attr 'data-loaded', 'false'

          @addLazyPartInScssPart val
        else
          console.log ('No DOM elements found for  ' + idName + '  id!').red

    for key, cEl of cheerioElemsObject
      elHtml = cEl('body').html()
      elHtml = elHtml.replace /&quot;/g, "'"
      # Remove close tag
      elHtml = elHtml.replace /<\/[^>]+>/g, ''

      elDecoded = entities.decode elHtml

      escapedKey = key.replace /[\\[.+*?(){|^$]/g, "\\$&"

      if key isnt elDecoded
        console.log 'REPLACE:'.magenta, key, '<===>'.yellow, elDecoded
        regexKey = new RegExp escapedKey, 'gi'
        pHtmlData = pHtmlData.replace regexKey, elDecoded
      #else
        #console.log ' Old and New elements are same!'.blue


    console.log '\n'
    @writeDataInFile 'html', @sourcePath, pHtmlData
    .then () =>
      #@checkHtml5(@sourcePath).then () ->
      #  console.log 'Completed!'.green
      @writeDataInFile 'scss', @scssFilePath, @scssData
      #.then () =>
      #  console.log 'Completed!'.green


  startPrompt: ->
    console.log "Please enter directory path".blue.bold
    prompt.start()

    promptSchema =
      properties:
        source:
          pattern: /^[a-zA-Z0-9\/\\\-_.:]+$/
          message: 'Source must be only letters, numbers and/or dashes, dots'
          required: true
          default: '_test.htm'

    prompt.get promptSchema, (err, result) =>
      if err
        console.log "error:".red, err
      else
        console.log 'Command-line input received:'.green
        console.log 'source:', (result.source).cyan
        @sourcePath = process.cwd() + '/' + result.source

        console.log 'Source path is:', (@sourcePath).green

        @lazyImg()


  lazyImg: ->
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

          if key isnt imgDecoded
            console.log 'REPLACE:'.magenta, key, '<===>'.yellow, imgDecoded
            regexKey = new RegExp escapedKey, 'gi'
            data = data.replace regexKey, imgDecoded
          #else
          #  console.log ' Old and New elements are same!'.blue

        @analyseHtmlForBackground data
        #@writeHtml data


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


  writeDataInFile: (pType, pPath, pData) ->
    console.log ('Overwrite ' + pType + ' file !!!').yellow
    deferred = q.defer()
    fs.writeFile pPath, pData, 'utf8', (err, data) =>
      if err
        console.log (' Error to write ' + pType + ' the file').red, err
        deferred.reject err
      else
        console.log (' The ' + pType + ' file has been overwritten').green
        deferred.resolve()

    deferred.promise


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
