colors = require 'colors'
prompt = require 'prompt'
fs = require 'fs'
cheerio = require 'cheerio'
html5Lint = require 'html5-lint'
q = require 'q'
commandLineArgs = require 'command-line-args'
path = require 'path'
Entities = require('html-entities').XmlEntities
entities = new Entities()

module.exports = class App

  sourcePath: undefined

  scssFilePath: undefined
  scssData: undefined
  scssAnalyse: undefined

  options: undefined
  htmlPromptId: -1

  constructor: ->
    console.log "process.cwd()".cyan, process.cwd()

    optionDefinitions = [
      { name: 'scss', alias: 's', type: String }
      { name: 'ignore-scss', alias: 'i', type: Boolean }
      { name: 'noscss', alias: 'n', type: Boolean }
      { name: 'ignore-class', alias: 'g', type: String }
    ]

    @options = commandLineArgs optionDefinitions
    console.log 'options:', @options

    if @options.scss
      @scssProcessus @options.scss

    else
      if @options['ignore-scss'] or @options['noscss']
        @startHtmPrompt()
      else
        @getFilesByExt('scss', no).then (scssFiles) =>
          if scssFiles.length is 1
            @scssProcessus scssFiles[0]
          else
            console.log ('0 or more than 1 scss files found! (' + scssFiles + ')').red
            @startHtmPrompt()


  scssProcessus: (pPath) ->
    @scssFilePath = pPath
    @getBackgroundsInScss pPath
    .then (pScssData) =>
      @scssData = pScssData
      @startHtmPrompt()


  getFilesByExt: (pExt, pWithUnderscore) ->
    deferred = q.defer()
    fs.readdir process.cwd(), (err, files) ->
      if err
        console.log 'err:'.red, err
        deferred.reject err
      else
        filesByExt = files.filter (file) ->
          if pWithUnderscore
            return file.indexOf('.' + pExt) isnt -1
          else
            return file.indexOf('.' + pExt) isnt -1 and file.substr(0, 1) isnt '_'

        if filesByExt.length is 0
          console.log ('No .' + pExt + ' files found!').red
          deferred.resolve []
        else
          console.log ' => .' + pExt + ' files:', (filesByExt.join(', ')).yellow
          deferred.resolve filesByExt

    deferred.promise


  getParentSelector: (pBlocks, pData, pRemBrakToOpenArr = [1], pResult = ['']) ->
    #console.log '\ngetParentSelector pResult'.magenta, pResult

    results = []
    blocks = []
    braks = []
    count = -1
    for pTarget in pBlocks
      count++

      if (typeof pTarget) is 'string'
        #console.log ' pTarget:'.green, pTarget.substr(0, 200), '(...)'
        regTarget = pTarget.replace /[\\[.+*?(){|^$]/g, "\\$&"
      else
        #console.log ' pTarget:'.green, pTarget
        tarRegEx = String(pTarget).replace /\\\//g, ''
        regTarget = tarRegEx.replace /\/([^]*)\/([\w]{0,2}$)/, '$1'

      re = new RegExp '([\\w-#.&:*% >)(@$\\[\\]]+)[\\s]*{[^{]*' + regTarget , 'gi'

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
            #console.log ' bloc:'.magenta, bloc.substr(0, 100), '(...)'

            diffBlock = bloc.replace pTarget, ''
            #console.log ' diffBlock:'.magenta, diffBlock
            #console.log '  Count of {  =>', (diffBlock.match(/{/g) or []).length,
            #  ' /  Count of }  =>', (diffBlock.match(/}/g) or []).length

          if regData[1]
            parentSel = String(regData[1]).trim()
            #console.log (' parentSel: "' + parentSel + '"').cyan

            openBrakCount = (diffBlock.match(/{/g) or []).length
            closeBrakCount = (diffBlock.match(/}/g) or []).length
            brakDiff = closeBrakCount - openBrakCount + pRemBrakToOpen
            #console.log ' brakDiff:', brakDiff

            mediaMatchBool = parentSel.match(/@media[^}]*/) isnt null
            #console.log ' mediaMatchBool:'.yellow, mediaMatchBool

            if brakDiff < 1 and not mediaMatchBool
              pResult2 = parentSel + ' ' + rEl
              brakDiff = 1 # We look for the top level

              results.push pResult2.trim()
              blocks.push bloc.substr(0, 1000)
              braks.push brakDiff
            else
              #console.log ' Ignore this element'.blue
              results.push rEl
              blocks.push bloc.substr(0, 1000)
              braks.push brakDiff

      #console.log ' whileCount:', whileCount
      if not currentWhileHappends
        results = results.concat [rEl]
        blocks = blocks.concat [pTarget]
        braks = braks.concat [pRemBrakToOpen]

    if whileCount is 0
      #console.log ' COMPLETE'
      return pResult
    else
      selectResult = @getParentSelector blocks, pData, braks, results
      #console.log ' selectResult', count, ' => ', selectResult
      return selectResult


  getBackgroundsInScss: (pPath) ->
    console.log 'Background images SCSS analyse start!'.magenta
    deferred = q.defer()

    fs.readFile pPath, 'utf8', (err, data) =>
      if err
        console.log 'err:'.red, err
        deferred.reject err
      else
        regex = /background(\-image)?[\s]*:[\s]*url\(([^)]*)\)[^;]*;/gi
        bgs = data.match regex

        @scssAnalyse = []

        if bgs
          # Remove doubloons, (@getParentSelector will manage duplicate items)
          bgs = bgs.filter (item, index) ->
            bgs.indexOf(item) is index

          for bg in bgs
            console.log '\nbg:'.green, bg

            jSelectors = @getParentSelector [bg], data
            jSelectors = jSelectors.filter (item, index) ->
              jSelectors.indexOf(item) is index
            console.log 'jSelectors:'.green, jSelectors

            for jSel in jSelectors
              @scssAnalyse.push
                scssFile: pPath
                background: bg
                selector: jSel
                lazyBg: no

          console.log '\n'
          lazyBgRegEx = new RegExp '/\\.lazy-bg[\\s]*{/', 'gi'
          jLazyBgSelectors = @getParentSelector [lazyBgRegEx], data
          for lazyBgSel in jLazyBgSelectors
            #console.log 'lazyBgSel :'.cyan, lazyBgSel
            for bgEl in @scssAnalyse
              if bgEl.selector is lazyBgSel
                bgEl.lazyBg = yes

          #console.log '@scssAnalyse:', @scssAnalyse
        else
          console.log 'No backgrounds found!'.red

        deferred.resolve data

    deferred.promise


  addLazyPartInScssPart: (pScssObj) ->
    if not pScssObj.lazyBg
      scssBackgroundUrl = pScssObj.background.replace /[\\[.+*?(){|^$]/g, "\\$&"

      selRx = String pScssObj.selector
      selRx = selRx.replace /[\s]*([^\s]+)/g, '$1[\\s{]+[^<]*'
      selRx = selRx.slice(0, -5) + '[^]*?' # Be sure to get the fist found, use '?' special char
      selRx += scssBackgroundUrl
      selRx += '[^}]*}' # Get the last part after background***
      #console.log 'selRx:'.cyan, selRx

      scssBlock = @scssData.match selRx
      #console.log 'scssBlock[0]:', scssBlock[0]

      if scssBlock[0]
        goodBlock = scssBlock[0]
        console.log 'Add ".lazy-bg" part in SCSS file!'.blue

        # Manage Line form
        regBgBreakLines = new RegExp '(\\n([ \\t]*)([\/]*)([\\w -.#]+){[ ]*([^\\n]*' + scssBackgroundUrl + '[^.]*)$)', 'gi'
        match = regBgBreakLines.exec goodBlock

        if match
          breakLines = match[5].replace /;[ ]*/g, ';\n' + match[2] + match[3] + '  '
          tmpBlock = goodBlock.replace match[0], '\n' + match[2] + match[3] + match[4] + '{\n' + match[2] + match[3] + '  ' + breakLines

          regExL = new RegExp match[2] + match[3] + '  }$', ''
          tmpBlock = tmpBlock.replace regExL, match[2] + match[3] + '}'
        else
          #console.log '(Not a line form) match:'.red, match
          tmpBlock = goodBlock

        regBg = new RegExp '(([ \t]*)([\/]*)([ ]*)' + scssBackgroundUrl + '([^.]*)$)', 'gi'
        newPart = tmpBlock.replace regBg, '$2$3$4' + pScssObj.background + '\n$2$3$4&.lazy-bg {\n$2$3$4  background-image: none;\n$2$3$4}$5'
        #console.log '=====> newPart:'.yellow, newPart
        @scssData = @scssData.replace goodBlock, newPart

        pScssObj.lazyBg = yes
      else
        console.log 'No scss block found!'.red
    else
      console.log ' ".lazy-bg" part already present in SCSS file for this element!'.cyan


  htmlReplacingWithCheerio: ($, elem) ->
    parentHtml = $(elem).parent().parent().html()
    srcElHtml = $(elem).parent().html()
    $(elem).addClass 'lazy-bg'
    $(elem).attr 'data-loaded', 'false'
    elHtml = $(elem).parent().html()
    newEl = parentHtml.replace srcElHtml, elHtml
    [parentHtml, newEl]


  analyseHtmlForBackground: (pHtmlData) ->
    console.log '\nAnalyse background images'.blue

    for scssObj in @scssAnalyse
      console.log ''
      #console.log 'scssObj:', scssObj

      if scssObj.selector.indexOf(':before') isnt -1
        console.log 'Ignore :before'.red
        continue

      if scssObj.selector.indexOf(':after') isnt -1
        console.log 'Ignore :after'.red
        continue

      jRegEx = new RegExp ' \\&', 'g'
      jSelect = String(scssObj.selector).replace jRegEx, ''
      console.log 'jSelect:', jSelect

      ignoreClass = @options['ignore-class']
      if ignoreClass
        ignoreClass = ignoreClass.replace /[\\[.+*?(){|^$]/g, "\\$&"
        regExIgnClass = new RegExp '[\\s]*[.]*' + ignoreClass + '[\\w]*' , 'gi'
        jSelect = jSelect.replace regExIgnClass, ''
        console.log 'jSelect without'.magenta, ignoreClass, '=>', jSelect

      $ = cheerio.load pHtmlData
      elems = $ jSelect

      if not elems or elems.length is 0
        console.log ('No DOM elements found for ' + scssObj.background + ' in ' + jSelect + ' !').red
      else
        elems.each (i, elem) =>
          resArr = @htmlReplacingWithCheerio $, elem
          pHtmlData = pHtmlData.replace resArr[0], resArr[1]

        #console.log ' UPDATE HTML:'.magenta,
          #firstElement.replace(/[\r\n\t][\s]*/g, '').replace(/>[\s]+</g, '><').substr(0, 50) + '...',
          #'<===>'.yellow,
          #finalReplacement.replace(/[\r\n\t][\s]*/g, '').replace(/>[\s]+</g, '><').substr(0, 50) + '...'

        @addLazyPartInScssPart scssObj

    console.log '\n'
    @writeDataInFile 'html', @sourcePath, pHtmlData
    .then () =>
      #@checkHtml5(@sourcePath).then () ->
      #  console.log 'Completed!'.green
      @writeDataInFile 'scss', @scssFilePath, @scssData
      .then () =>
      #  console.log 'Completed!'.green
        @startHtmPrompt()


  startHtmPrompt: ->
    console.log ''

    @getFilesByExt('htm', yes).then (htmFiles) =>
      if htmFiles.length >= 1
        @htmlPromptId++
        if htmFiles[@htmlPromptId]
          htmlFile = htmFiles[@htmlPromptId]
        else
          console.log 'All HTML files have been analysed!'.magenta
          return
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
        if imgs
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


      if @scssFilePath
        @analyseHtmlForBackground data
      else
        console.log '\n'
        @writeDataInFile 'html', @sourcePath, data
        .then () =>
          #@checkHtml5(@sourcePath).then () ->
          #  console.log 'Completed!'.green
          @startHtmPrompt()


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
            imageName = pChImg.attr('data-image').match /{[ ]*['"]src['"]:[ ]*['"]([^<]*)['"][ ]*}/
            imageName = imageName[1]
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

    relative = path.relative process.cwd(), pPath
    console.log (' relative path:').blue, relative

    try
      fs.writeFile pPath, pData, 'utf8', (err, data) ->
        if err
          console.log (' Error to write ' + pType + ' the file').red, err
          deferred.reject err
        else
          console.log (' The ' + pType + ' file has been overwritten').green
          deferred.resolve()
    catch error
      console.log 'catch error'.red, error
      deferred.reject error

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
