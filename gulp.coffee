gulp = require 'gulp'
coffee = require 'gulp-coffee'
coffeelint = require 'gulp-coffeelint'

srcPath =
  coffee: '*.coffee'

destPath =
  js: '.'

gulp.task 'coffee', ->
  gulp.src srcPath.coffee
  .pipe coffee({ bare: true })
    #.on('error', util.log))
  #.pipe(concat('app.js'))
  #.pipe(if isProd then uglify() else util.noop())
  .pipe gulp.dest(destPath.js)

gulp.task 'lint', ->
  gulp.src srcPath.coffee
  .pipe coffeelint()
  .pipe coffeelint.reporter()

gulp.task 'coffeeBuild', gulp.series('lint', 'coffee')

gulp.task 'watchCoffee', ->
  gulp.watch '*.coffee', gulp.series('coffeeBuild')

gulp.task 'watch', gulp.series('coffeeBuild', 'watchCoffee')

gulp.task 'default', gulp.series('watch')