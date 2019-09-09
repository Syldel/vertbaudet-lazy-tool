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
      { name: 'ignore-scss', alias: 'i', type: Boolean }
    ]

    options = commandLineArgs optionDefinitions
    console.log 'options:', options

    if options.scss
      @scssProcessus options.scss

    else
      if options['ignore-scss']
        @startHtmPrompt()
      else
        @getFilesByExt('scss').then (scssFiles) =>
          if scssFiles.length is 1
            @scssFilePath = scssFiles[0]
            @scssProcessus @scssFilePath
          else
            console.log ('0 or more than 1 scss files found! (' + scssFiles + ')').red
            @startHtmPrompt()


  scssProcessus: (pPath) ->
    @getBackgroundsInScss pPath
    .then (pScssData) =>
      @scssData = pScssData
      @startHtmPrompt()


  getFilesByExt: (pExt) ->
    deferred = q.defer()
    fs.readdir process.cwd(), (err, files) ->
      if err
        console.log 'err:'.red, err
        deferred.reject err
      else
        filesByExt = files.filter (file) ->
          file.indexOf('.' + pExt) isnt -1 # and file.substr(0, 1) isnt '_'

        if filesByExt.length is 0
          console.log ('No .' + pExt + ' files found!').red
          deferred.reject()
        else
          console.log ' => .' + pExt + ' files:', (filesByExt.join(', ')).yellow
          deferred.resolve filesByExt

    deferred.promise


  getParentSelector: (pBlocks, pData, pRemBrakToOpenArr = [1], pResult = ['']) ->
    #console.log '\nLook Parent Of '.magenta, pTarget
    #console.log '\ngetParentSelector pResult'.magenta, pResult

    results = []
    blocks = []
    braks = []
    count = -1
    for pTarget in pBlocks
      count++

      regTarget = pTarget.replace /[\\[.+*?(){|^$]/g, "\\$&"
      re = new RegExp '([\\s\\w-#.&:]+){[^{]*' + regTarget , 'gi' # + '[^}]*}', 'gi'

      pRemBrakToOpen = pRemBrakToOpenArr[count]
      rEl = pResult[count]
      #console.log ' ' + count + ' rEl:', rEl

      whileCount = 0
      currentWhileHappends = no
      while(regData = re.exec pData)
        whileCount++
        currentWhileHappends = yes
        if regData
          #console.log '\nregData.index:'.yellow, regData.index
          if regData[0]
            bloc = regData[0]

            diffBlock = bloc.replace pTarget, ''
            #console.log 'diffBlock:'.magenta, diffBlock
            #console.log '  Count of {  =>', (diffBlock.match(/{/g) or []).length,
            #  ' /  Count of }  =>', (diffBlock.match(/}/g) or []).length

          if regData[1]
            parentSel = String(regData[1]).trim()
            #console.log 'regData[1] parentSel:'.cyan, parentSel

            openBrakCount = (diffBlock.match(/{/g) or []).length
            closeBrakCount = (diffBlock.match(/}/g) or []).length
            brakDiff = closeBrakCount - openBrakCount + pRemBrakToOpen
            #console.log 'brakDiff:', brakDiff

            if brakDiff < 1
              pResult2 = parentSel + ' ' + rEl
              brakDiff = 1 # We look for the top level
              results.push pResult2.trim()
              blocks.push bloc
              braks.push brakDiff
            else
              #console.log ' Ignore this element'.blue
              results.push rEl
              blocks.push bloc
              braks.push brakDiff

      #console.log 'whileCount:', whileCount
      if not currentWhileHappends
        results = results.concat [rEl]
        blocks = blocks.concat [pTarget]
        braks = braks.concat [pRemBrakToOpen]

    if whileCount is 0
      #console.log ' COMPLETE'
      return pResult
    else
      selectResult = @getParentSelector blocks, pData, braks, results
      #console.log 'selectResult', count, ' => ', selectResult
      return selectResult


  getBackgroundsInScss: (pPath) ->
    console.log 'Background images SCSS analyse start!'.magenta
    deferred = q.defer()

    fs.readFile pPath, 'utf8', (err, data) =>
      if err
        console.log 'err:'.red, err
        deferred.reject err
      else
        regex = /background(\-image)?[\s]*:[\s]*url\(([^)]*)\)[;]?/gi
        bgs = data.match regex

        @scssAnalyse = []

        for bg in bgs
          console.log '\nbg:'.green, bg

          @scssAnalyse.push
            scssFile: pPath
            background: bg

          jSelectors = @getParentSelector [bg], data
          console.log 'jSelectors:'.green, jSelectors

        console.log '\n'
        jLazyBgSelectors = @getParentSelector ['.lazy-bg'], data
        for lazyBg in jLazyBgSelectors
          console.log 'lazyBg :'.green, lazyBg
        return

        ###
        if bloc.indexOf('lazy-bg') is -1
          #console.log 'The block doesn\'t contains ".lazy-bg" ?'
          if classOrId then @scssAnalyse[classOrId]['lazy-bg'] = no
        else
          #console.log 'The block already contains ".lazy-bg" ? ', bloc.indexOf 'lazy-bg'
          if classOrId then @scssAnalyse[classOrId]['lazy-bg'] = yes
        ###

        #deferred.resolve data

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


  startHtmPrompt: ->

    @getFilesByExt('htm').then (htmFiles) =>
      if htmFiles.length is 1
        htmlFile = htmFiles[0]
      else
        htmlFile = '_test.htm'

      console.log "Please enter directory path".blue.bold
      prompt.start()

      promptSchema =
        properties:
          source:
            pattern: /^[a-zA-Z0-9\/\\\-_.:]+$/
            message: 'Source must be only letters, numbers and/or dashes, dots'
            required: true
            default: htmlFile

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
        # Get Last element in path
        imageName = imageName.split('/').pop()
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
    fs.writeFile pPath, pData, 'utf8', (err, data) ->
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
