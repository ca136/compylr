#!/usr/bin/env coffee

# TODO:
#   - crawl full directory of templates and partials and output new tree of files
#   - partials (crawl and map directory this script gets pointed to)
#   - flask server render whole app backend a page at a time
#   - angular hook into page post-render
#   - prettify output
#
#   - options
#     - no prettify
#     - no strip comments
#


config =
  verbose: false

argv = require('optimist').argv
fs = require 'fs'
_ = require 'lodash'
beautifyHtml = require('js-beautify').html

verboseLog = (args...) ->
  console.info args... if config.verbose

stripComments = (str) ->
  str.replace(/<!--[\s\S]*?-->/g, '')

convert = (options) ->
  filePath = argv.file or options.file
  if filePath
    verboseLog 'filePath', filePath
    file = fs.readFileSync filePath, 'utf8'
  else
    file = options.string or options

  selfClosingTags = 'area, base, br, col, command, embed, hr, img, input,
  keygen, link, meta, param, source, track, wbr'.split /,\s*/

  escapeCurlyBraces = (str) ->
    str
      .replace(/\{/g, '&#123;')
      .replace(/\}/g, '&#125;')

  beautify = (str) ->
    str = str.replace /\{\{(#|\/)([\s\S]+?)\}\}/g, (match, type, body) ->
      modifier = if type is '#' then '' else '/'
      "<#{modifier}##{body}>"

    pretty = beautifyHtml str,
      indent_size: 2
      indent_inner_html: true
      preserve_newlines: false

    pretty = pretty
      .replace /<(\/?#)(.*)>/g, (match, modifier, body) ->
        modifier = '/' if modifier is '/#'
        "{{#{modifier}#{body}}}"

    pretty


  # TODO: pretty format
  #   replace '\n' with '\n  ' where '  ' is 2 spaces * depth
  #   Maybe prettify at very end instead
  getCloseTag = (string) ->
    index = 0
    depth = 0
    open = string.match(/<.*?>/)[0]
    tagName = string.match(/<\w+/)[0].substring 1
    string = string.replace open, ''

    if tagName in selfClosingTags
      out =
        before: open
        after: string.substr open.length
      return out


    for char, index in string
      # Close tag
      if char is '<' and string[index + 1] is '/'
        if not depth
          after = string.substr index
          close = after.match(/<\/.*?>/)[0]
          afterWithTag = after + close
          afterWithoutTag = after.substring close.length

          return (
            after: afterWithoutTag
            before: open + '\n' + string.substr(0, index) + close
          )
        else
          depth--
      # Open tag
      else if char is '<'
        selfClosing = false
        tag = string.substr(index).match(/\w+/)[0]
        # Check if self closing tag
        if tag and tag in selfClosingTags
          continue
        depth++

  # FIXME: this will break for pipes inside strings
  processFilters = (str) ->
    filterSplit = str.match /[^\|]+/
    filters: filterSplit.slice(1).join ' | '
    replaced: filterSplit[0]

  # FIXME: will breal if this is in words
  escapeReplacement = (str) ->
    convertNgToDataNg str

  convertNgToDataNg = (str) ->
    str.replace /\sng-/g, ' data-ng-'

  unescapeReplacements = (str) ->
    str
    # str.replace /__NG__/g, 'ng-'

  escapeBasicAttribute = (str) ->
    '__ATTR__' + str + '__ATTR__'

  unescapeBasicAttributes = (str) ->
    str.replace /__ATTR__/g, ''

  escapeBraces = (str) ->
    str
      .replace(/\{\{/g, '__{{__')
      .replace(/\}\}/g, '__}}__')

  unescapeBraces = (str) ->
    str
      .replace(/__\{\{__/g, '{{')
      .replace(/__\}\}__/g, '}}')

  updated = true
  interpolated = stripComments file
  i = 0
  maxIters = 10000

  while updated
    updated = false
    firstLoop = false

    throw new Error 'infinite update loop' if i++ > maxIters

    interpolated = interpolated
      .replace(/<[^>]*?\sng-repeat="(.*?)".*?>([\S\s]+)/gi, (match, text, post) ->
        verboseLog 'match 1'
        updated = true
        varName = text
        varNameSplit = varName.split ' '
        varNameSplit[0] = "'#{varNameSplit[0]}'"
        varName = varNameSplit.join ' '
        processedFilters = processFilters varName
        varName = processedFilters.replaced
        filters = processedFilters.filters
        # varName = text.split(' in ')[1]
        close = getCloseTag match
        filterStr = if filters.trim() then " filters=\"#{filters}\"" else ''
        if close
          "{{#forEach #{varName}#{filterStr}}}\n#{close.before.replace /\sng-repeat/, ' data-ng-repeat'}\n{{/forEach}}\n#{close.after}"
        else
          throw new Error 'Parse error! Could not find close tag for ng-repeat'
      )
      # TODO: 'ifExpression' separate from  'if'
      .replace(/<[^>]*?\sng-if="(.*?)".*?>([\S\s]+)/, (match, varName, post) ->
        verboseLog 'match 2'
        updated = true
        varName = varName.trim()
        # TODO: expressions
        tagName = if varName.split(' ')[1] then 'ifExpression' else 'if'
        if varName.indexOf('!') is 0 and tagName is 'if'
          tagName = 'unless'
          varName = varName.substr 1
        else if tagName is 'ifExpression'
          varName = "\"#{varName}\""

        close = getCloseTag match
        if close
          "{{##{tagName} #{varName}}}\n#{close.before.replace /\sng-if=/, " data-ng-if="}\n{{/#{tagName}}}\n#{close.after}"
        else
          throw new Error 'Parse error! Could not find close tag for ng-if\n\n' + match + '\n\n' + file
      )
      .replace(/<[^>]*?\sng-include="'(.*)'".*?>/, (match, includePath, post) ->
        verboseLog 'match 3'
        updated = true
        includePath = includePath.replace '.tpl.html', ''
        match = match.replace /\sng-include=/, ' data-ng-include='
        "#{match}\n{{> #{includePath}}}"
      )
      .replace(/\s(ng-src|ng-href|ng-value)="(.*)"/, (match, attrName, attrValue) ->
        verboseLog 'match 4'
        updated = true
        escapedMatch = escapeCurlyBraces match
        escapedAttrValue = escapeBraces attrValue
        """#{escapedMatch.replace ' ' + attrName, ' data-' + attrName} #{attrName.substring(3)}="#{escapedAttrValue}" """
      )
      # FIXME: this doesn't support multiple interpolations in one tag
      .replace(/<[^>]*?([\w\-]+)\s*=\s*"([^">_]*?\{\{[^">]+\}\}[^">_]*?)".*?>/, (match, attrName, attrVal) ->
        verboseLog 'match 5', attrName: attrName, attrVal: attrVal
        # Match without the final '#'
        trimmedMatch = match.substr 0, match.length - 1
        trimmedMatch = trimmedMatch.replace "#{attrName}=", escapeBasicAttribute "#{attrName}="
        if attrName.indexOf('data-ng-attr-') is 0 or _.contains attrVal, '__{{__'
          match
        else
          updated = true
          newAttrVal = attrVal.replace /\{\{([\s\S]+?)\}\}/g, (match, expression) ->
            match = match.trim()
            if expression.length isnt expression.match(/[\w\.]+/)[0].length
              "{{expression '#{expression.replace /'/g, "\\'"}'}}"
            else
              match

          trimmedMatch = trimmedMatch.replace attrVal, escapeBraces newAttrVal
          """#{trimmedMatch} data-ng-attr-#{attrName}="#{escapeCurlyBraces attrVal}">"""
      )
      .replace(/\s(ng-show|ng-hide)\s*=\s*"([^"]+)"/g, (match, showOrHide, expression) ->
        updated = true
        hbsTagType = if showOrHide is 'ng-show' then 'hbsShow' else 'hbsHide'
        match = match.replace ' ' + showOrHide, " data-#{showOrHide}"
        "#{match} {{#{hbsTagType} \"#{expression}\"}}"
      )

  i = 0
  updated = true
  while updated
    updated = false

    throw new Error 'infinite update loop' if i++ > maxIters

    interpolated = interpolated
      .replace(/\{\{([^#\/>_][\s\S]*?[^_])\}\}/g, (match, body) ->
        verboseLog 'match 7'
        updated = true
        body = body.trim()
        words = body.match /[\w\.]+/
        isHelper = words[0] in ['json', 'expression', 'hbsShow', 'hbsHide']
        if not isHelper
          prefix = ''
          suffix = ''
          if words and words[0].length isnt body.length
            verboseLog 'body', body
            prefix = 'expression "'
            suffix = '"'
          escapeBraces """<span data-ng-bind="#{body}">{{#{prefix}#{body}#{suffix}}}</span>"""
        else
          escapeBraces match
      )

    # .replace(/<[^>]*?ng\-show="(.*)".*?>([\S\s]+)/g, (match, varName, post) ->
    #   close = getCloseTag match
    #   if close
    #     "{{#if #{varName}}}\n#{close.before}\n{{/if}}\n#{close.after}"
    #   else
    #     throw new Error 'Parse error! Could not find close tag for ng-show'
    # )
    # .replace(/<[^>]*?ng\-hide="(.*)".*?>([\S\s]+)/g, (match, varName, post) ->
    #   close = getCloseTag match
    #   if close
    #     "{{#unless #{varName}}}\n#{close.before}\n{{/unless}}\n#{close.after}"
    #   else
    #     throw new Error 'Parse error! Could not find close tag for ng-hide'
    # )

  interpolated = unescapeReplacements interpolated
  interpolated = unescapeBraces interpolated
  interpolated = unescapeBasicAttributes interpolated
  interpolated = convertNgToDataNg interpolated
  beautified = beautify interpolated

  if argv.file and not argv['no-write']
    fs.writeFileSync 'template-output/output.html', beautified

  beautified

module.exports = convert