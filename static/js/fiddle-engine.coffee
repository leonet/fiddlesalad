root = global ? window
BackgroundWorker =
  previousError: new String

  loadWorker: (file) ->
    @compiler = new Worker([worker_url, 'compilers/', file, '.js', '?v=', 2012040912].join(''))
    @compiler.addEventListener(
      'message'
      (event) =>
        messageType = event.data.type
        switch messageType
          when ('result')
            code = event.data.resultText
            @previewCode code
          when ('error')
            @displayError event.data.errorText
      false
    )

  previewCode: (code) ->

  displayError: (message, settings=text: message) ->
    if message isnt @previousError
      noty _.defaults(settings, notyDefaults)
      @previousError = message

DynamicEditor = CodeCompleteEditor.$extend(
  __init__: (id) ->
    @$super id
    @observers = new Array
    @compiledCode = new String
    @codeMirrorContainer = '#' + @id + 'container'
    @tabCharaterLength = 4

  __include__: [BackgroundWorker]

  get_options: ->
    _.defaults(
      @$super()
      indentUnit: @tabCharaterLength
      indentWithTabs: true
    )

  previewCode: (code) ->
    @preview code
    @set_compiled_code code
    _.defer => @notify()

  attach: (observer) ->
    @observers.push(observer)

  detach: (observer) ->
    @observers = _.without(@observers, observer)

  notify: ->
    for observer in @observers
      observer.update(@)

  set_focus_listener: (listener) ->
    @focusListener = listener

  focusHandler: ->
    if @focusListener?
      @focusListener.focus_gained()

  changeHandler: ->
    @compiler.postMessage @get_code()

  get_compiled_code: ->
    @compiledCode

  set_compiled_code: (code) ->
    @compiledCode = code

  get_documentation: (name=@mode.name) ->
    page = IframeComponent name + 'ReferenceTab'
    page.set_source @documentationUrl
    {title: name, content: page.to_html_string()}
)
StyleEditor = DynamicEditor.$extend(
  __init__: (id) ->
    @$super id
    @bootstrapCode = new String
    @varClassName = 'cm-meta'
    keywords = KEYWORDS.CSS_PROPERTIES
    @addAutocomplete keywords
    @showAutocomplete = false
    @varStart = '$'
    @theme = 'stylish'
    @propertyEndKeyCode = 58

  set_framework: (code) ->
    return  if code is @bootstrapCode
    @bootstrapCode = code
    @changeHandler()

  get_framework: ->
    @bootstrapCode

  get_code: ->
    @bootstrapCode + @$super()

  keyHandler: (editor, event) ->
    ###
    This routine keeps track of when the cursor position. Autocomplete is only launched on an indented line that does
    not have the ":" symbol.
    ###
    # if a new line is started, set showAutocomplete to true
    if event.keyCode is 13 and event.type is 'keydown' and editor.getCursor().ch > 1 # Enter is not captured on keypress
      @showAutocomplete = true
      _.defer => @updateVars()
    if event.type isnt 'keypress'
      return
    # if colon is entered, set showAutocomplete to false
    if event.keyCode is @propertyEndKeyCode
      @showAutocomplete = false
    # for any other key on an indented line
    else if @showAutocomplete and not (event.keyCode < 41 and event.keyCode > 31)
      @popupAutocomplete(@keyCharacter(event))
    else
      cur = editor.getCursor()
      token = editor.getTokenAt(cur)
      return  unless token.string is @varStart
      @popupAutocomplete(@keyCharacter(event))

  preview: (css) ->
    $('#viewer').contents().find('#user_css').html StyleFix.fix(css)
)
LessEditor = StyleEditor.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'less'
    @loadWorker('less')
    @documentationUrl = base_url + '/files/documentation/lesscss.html'
    @varStart = '@'
)
StylusEditor = StyleEditor.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'stylus'
    @loadWorker('stylus')
    @documentationUrl = 'http://learnboost.github.com/stylus/'
    @propertyEndKeyCode = 32
)
ProgramEditor = DynamicEditor.$extend(
  preview: (javascript) ->
    codeRunner.execute(javascript)
)
lintEditor =
  debounceWaitSeconds: 2250 # When the editor is idle after changes, call changeHandler

  blockEndKeyCode: 13 # Enter

  changeHandler: _.throttle(
    ->
      code = @get_code()
      if @tokensMatch(code)
        if viewModel.lint_enabled(@mode.name)
          @compiler.postMessage code
        else
          @previewCode code
    750
  )

  tokensMatch: (code) ->
    code.count('[(]') is code.count('[)]') and code.count('{') is code.count('}') and (code.count('"') % 2) is 0 and (code.count("'") % 2) is 0

  keyHandler: (editor, event) ->
    if event.keyCode is @blockEndKeyCode and event.type is 'keydown'
      @changeHandler()
    else if event.type is 'keypress' and not (event.keyCode < 41 and event.keyCode > 31) # not a navigation key
      @popupAutocomplete(@keyCharacter(event))

JavascriptEditor = ProgramEditor.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'javascript'
    @loadWorker('jshint')
    @documentationUrl = 'https://developer.mozilla.org/en/Core_JavaScript_1.5_Guide/'

  __include__: [lintEditor]

  updateVars: ->

  load: ->
    @$super()
    @hint = CodeMirror.javascriptHint

  selectionHandler: _.throttle(
    ->
      if @pad.somethingSelected()
        selectedText = @pad.getSelection()
        return  unless /^[\w$_.]+$/.test(selectedText)
        # get the character position of the last selected letter
        position = @pad.getCursor()
        # insert pretty print block after selection in the line
        selectedTextLine = @pad.getLine(position.line)
        # replace line in code
        lines = @get_code().split('\n')
        lines[position.line] = "#{ selectedTextLine }\ndocument.body.appendChild(prettyPrint(#{ selectedText }));"
        @previewCode lines.join('\n')
    500
  )
)
CssEditor = StyleEditor.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'css'
    @theme = 'default'
    @loadWorker('csslint')
    @documentationUrl = 'http://people.opera.com/rijk/panels/css3-online/prop-index.html'
    @blockEndKeyCode = 125

  __include__: [lintEditor]
)
CoffeescriptEditor = ProgramEditor.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'coffeescript'
    @loadWorker('coffeescript')
    @documentationUrl = 'http://coffeescript.org/'
    @tabCharaterLength = 2

  load: ->
    @$super()
    @hint = CodeMirror.coffeescriptHint
    converter = JavascriptConverter('javascriptConverter')
    converter.set_editor @
)
RoyEditor = ProgramEditor.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'roy'
    @loadWorker('roy')
    @documentationUrl = 'http://guide.roylang.org/en/latest/index.html'
    @tabCharaterLength = 2

  load: ->
    @$super()
    @hint = CodeMirror.javascriptHint
)
DocumentEditor = DynamicEditor.$extend(
  __init__: (id) ->
    @$super id
    attributes = [ 'abbr', 'accept-charset', 'accept', 'accesskey', 'action', 'align', 'alt', 'archive', 'axis', 'background', 'border', 'cellpadding', 'cellspacing', 'char', 'charoff', 'charset', 'checked', 'cite', 'class', 'clear', 'code', 'codebase', 'codetype', 'color', 'cols', 'colspan', 'content', 'coords', 'data', 'datetime', 'declare', 'defer', 'dir', 'disabled', 'enctype', 'for', 'frame', 'frameborder', 'headers', 'height', 'href', 'hreflang', 'http-equiv', 'id', 'ismap', 'label', 'lang', 'longdesc', 'longdesc', 'marginheight', 'marginwidth', 'maxlength', 'media', 'method', 'multiple', 'name', 'nohref', 'noresize', 'onblur', 'onchange', 'onclick', 'ondblclick', 'onfocus', 'onkeydown', 'onkeypress', 'onkeyup', 'onload', 'onmousedown', 'onmousemove', 'onmouseout', 'onmouseover', 'onmouseup', 'onreset', 'onselect', 'onsubmit', 'onunload', 'profile', 'readonly', 'rel', 'rev', 'rows', 'rowspan', 'rules', 'scheme', 'scope', 'scrolling', 'selected', 'shape', 'size', 'span', 'src', 'standby', 'style', 'summary', 'tabindex', 'target', 'title', 'type', 'usemap', 'valign', 'value', 'valuetype', 'width' ]
    @addAutocomplete attributes

  preview: (html) ->
    $('#viewer').contents().find('body').html html
    codeRunner.execute engine.get_code(LANGUAGE_TYPE.COMPILED_PROGRAM)

  keyHandler: (editor, event) -> # disable auto-complete
    if event.type isnt 'keypress'
      return
    @popupAutocomplete(@keyCharacter(event))

)
TemplateEditor = DocumentEditor.$extend(
  getViewerLocals: ->
    iframeWindow = document.getElementById('viewer').contentWindow
    if 'locals' of iframeWindow
      iframeWindow.locals
    else
      {}

  changeHandler: ->
    @compiler.postMessage code: @get_code(), locals: @getViewerLocals()
)
HamlEditor = TemplateEditor.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'haml'
    @loadWorker('haml')
    @documentationUrl = base_url + '/files/documentation/haml.html'
    @tabCharaterLength = 2

  load: ->
    @$super()
    converter = HtmlConverter('htmlConverter')
    converter.set_editor @

  get_options: ->
    _.defaults(
      @$super()
      indentWithTabs: false
    )
)
CoffeecupEditor = TemplateEditor.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'coffeescript'
    @loadWorker('coffeecup')
    @documentationUrl = base_url + '/files/documentation/coffeekup.html'

  get_documentation: ->
    @$super('coffeecup')
)
MarkdownEditor = TemplateEditor.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'markdown'
    @loadWorker('markdown')
    @documentationUrl = base_url + '/files/documentation/markdown.html'

  keyHandler: ->
)
JadeEditor = TemplateEditor.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'jade'
    @loadWorker('jade')
    @documentationUrl = base_url + '/files/documentation/jade.html'

  load: ->
    @$super()
    converter = HtmlJadeConverter('htmlConverter')
    converter.set_editor @
)
HtmlEditor = DocumentEditor.$extend(
  __init__: (id) ->
    @$super id
    @mode = 'htmlmixed'
    @loadWorker('htmlparser')
    @documentationUrl = 'http://people.opera.com/rijk/panels/html4.01-online/elem.html'
    @extraKeys["'>'"] = (cm) -> cm.closeTag cm, ">"
    @extraKeys["'/'"] = (cm) -> cm.closeTag cm, "/"

  load: ->
    @$super()
    $('#beautifyHtml').on(
      'click'
      (event) =>
        CodeMirror.commands["selectAll"] @pad
        @autoFormatSelection()
    )

  getSelectedRange: ->
    from: @pad.getCursor(true)
    to: @pad.getCursor(false)

  autoFormatSelection: ->
    range = @getSelectedRange()
    @pad.autoFormatRange range.from, range.to

  get_documentation: ->
    @$super('html')
)
ZencodingEditor = DocumentEditor.$extend(
  __init__: (id) ->
    @$super id
    @initialCode = ''
    @delayLoad = true
    @loadWorker('htmlparser')

  load: ->
    codemirror_path = if debug then base_url + '/js/build/lib/' else base_url + '/js/'
    $.getScript(codemirror_path + 'zencoding.js', =>
        @pad = ZenCodingCodeMirror.fromTextArea(@id,
          basefiles: [codemirror_path + 'codemirror1.min.js'],
          stylesheet: base_url + '/css/xmlcolors.css'
          continuousScanning: 500
          lineNumbers: false
          onChange: @get_options().onChange
          syntax: 'html'
          onLoad: (editor) =>
            if @delayLoad
              editor.setCode @initialCode
              @delayLoad = false
            zen_editor.bind editor
        )
    )

  get_code: (type) ->
    @pad.getCode()

  set_code: (code) ->
    if @delayLoad
      @initialCode = code
      return
    @pad.setCode code

  get_documentation: ->
    page = HtmlComponent 'zenReferenceTab'
    {title: 'zen coding', content: page.to_html_string()}
)
serverCompiler =
  compileSuccess: true

  loadThrottledExecution: ->
    @executeThrottledLong = _.throttle @execute, 3500
    @executeThrottledShort = _.throttle @execute, 1500
    @executeThrottled = =>
      # if the previous compile returned with error
      if not @compileSuccess
      # call execute in longer intervals
        @executeThrottledLong()
      # else
      else
      # call execute in shorter intervals
        @executeThrottledShort()

  markError: (error) ->
    linePattern = /line\s(\d+)/
    columnPattern = /column\s(\d+)/
    lineNumber = parseInt(linePattern.exec(error)[1]) - 1
    columnNumber = parseInt(columnPattern.exec(error)[1])
    lineString = @pad.getLine(lineNumber)
    scannerPosition = undefined
    scannerPosition = columnNumber
    while lineString.charAt(scannerPosition) is ' '
      scannerPosition++
    while scannerPosition < lineString.length and lineString.charAt(scannerPosition) isnt ' '
      scannerPosition++
    @pad.markText(
        line: lineNumber
        ch: columnNumber
      ,
        line: lineNumber
        ch: scannerPosition
      ,
      'syntax-error'
    )

  execute: ->
    ###
    This routine sends request to the server to compile code unless specified by the argument immediate. On success,
    it updates the editor with the compiled code. If the compiler issues an error, it highlights the error if the
    line and column numbers are given and notifies the user about the error.
    ###
    $.post(
      ['http://fiddlesalad.com/',  @mode.name, '/compile/'].join('')
      code: @get_code()
      (response) =>
        if response.success
          @compileSuccess = true
          if @compiler?
            @compiler.postMessage response.code
          else
            @previewCode response.code
        else
          @compileSuccess = false
          @markError response.error
          @displayError response.error
      'json'
    )
    $('span.syntax-error').removeClass 'syntax-error'

  changeHandler: (editor, change) ->
    ###
    This routine calls execute to compile code either when a major code block is completed or after a period of time.
    http://codemirror.net/doc/manual.html#option_onChange
    ###
    return  if _.isEmpty(editor) or _.isEmpty(change)
    # if a code block is completed
    if change.next? and change.next.from.ch is 0
      @execute()
      return
    else
      @executeThrottled()

RubyCompiler = StyleEditor.$extend(
  __init__: (id) ->
    @$super id
    @loadThrottledExecution()
    @tabCharaterLength = 2

  __include__: [serverCompiler]

  markError: ->

  displayError: (message, settings) ->
    @$super message, {text: message, timeout: 25000}

  previewCode: (code) ->
    @$super viewModel.reindentCss(code)

  load: ->
    @$super()
    converter = CssConverter('cssConverter')
    converter.set_editor @
)
SassEditor = RubyCompiler.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'sass'
    @documentationUrl = base_url + '/files/documentation/sass.html'
)
ScssEditor = RubyCompiler.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'scss'
    @documentationUrl = base_url + '/files/documentation/sass.html'
)
PythonEditor = ProgramEditor.$extend(
  __init__: (id) ->
    @$super id
    @mode =
      name: 'python'
      version: 2
      singleLineStringErrors: false

    keywords = [ 'and', 'break', 'class', 'continue', 'def', 'def():', 'del', 'elif', 'else', 'finally', 'for', 'for  in ', 'global', 'lambda', 'not', 'pass', 'print', 'return', 'try', 'while', 'with' ]
    jQuery_object_methods = KEYWORDS.JQUERY_OBJECT
    jQuery_prototype_methods = KEYWORDS.JQUERY_PROTOTYPE
    @addAutocomplete keywords
    @addAutocomplete jQuery_object_methods, '$'
    @addAutocomplete jQuery_prototype_methods, '$()'
    @loadWorker('javascript')
    @loadThrottledExecution()
    @documentationUrl = '/python/documentation/'

  __include__: [serverCompiler]

  load: ->
    @$super()
    viewModel.add_resource base_url + '/js/pylib.js'

  preview: (javascript) ->
    codeRunner.execute javascript

)
Viewer = Class.$extend(
  __init__: (id) ->
    @id = id

  set_code: (code) ->
    CodeMirror.runMode(code, @mode, document.getElementById(@id))

  observe: (editor) ->
    editor.attach @

  update: (editor) ->
    @set_code editor.get_compiled_code()
)
HtmlViewer = Viewer.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'htmlmixed'
)
CssViewer = Viewer.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'css'

  setIframeCss: (css) ->
    cssElement = document.getElementById(@id).contentWindow.css
    cssElement.textContent = css
    document.getElementById(@id).contentWindow.Highlight.init(cssElement)

  set_code: (css) ->
    if viewModel.newFiddle()
      @setIframeCss css
    else
      timer = setInterval(
        =>
          if document.getElementById(@id)?.contentWindow?.loaded
            @setIframeCss css
            clearInterval timer
        250
      )
)
JavascriptViewer = Viewer.$extend(
  __init__: (id) ->
    @$super id
    @mode = name: 'javascript'

  update: (editor) ->
    @$super editor
    $('#' + @id + ' .cm-property').each(
      ->
        if $(this).text() in KEYWORDS.JQUERY_OBJECT and $(this).prev().text() is '$'
          $(this).html "<a href='http://api.jquery.com/jQuery.#{ $(this).text() }/' target='_blank'>#{ $(this).text() }</a>"
        else if $(this).text() in KEYWORDS.JQUERY_PROTOTYPE and $(this).prev().prev().text() is '$'
          $(this).html "<a href='http://api.jquery.com/#{ $(this).text() }/' target='_blank'>#{ $(this).text() }</a>"
    )
)
BeautifiedJavascriptViewer = JavascriptViewer.$extend(
  set_code: (javascript) ->
    @$super js_beautify(javascript)
)
codeConverter =
  loadConverter: (id) ->
    @textarea = $('#' + id)
    @previousValue = new String
    @textarea.bind(
      'keyup blur'
      =>
        @changeHandler()
    )

  changeHandler: _.throttle(
    ->
      if @textarea.val() isnt @previousValue
        @previousValue = @textarea.val()
        $.post(
          ['http://fiddlesalad.com/',  @editor.mode.name, '/convert/'].join('')
          code: @textarea.val()
          (response) =>
            @previewCode(response[@editor.mode.name])
          'json'
        )
    500
  )

  set_editor: (@editor) ->

  previewCode: (convertedCode) ->
  # when the user pastes JavaScript code, it is inserted at the cursor position in the CoffeeScript editor
  # get the character position of the cursor
    position = @editor.pad.getCursor()
    # insert block after the cursor in the line
    cursorPositionLine = @editor.pad.getLine(position.line)
    # replace line in code
    lines = @editor.get_code().split('\n')
    # insert at the cursor position
    lines[position.line] = cursorPositionLine.slice(0, position.ch) + convertedCode + cursorPositionLine.slice(position.ch)
    @editor.set_code lines.join('\n')

JavascriptConverter = Class.$extend(
  __init__: (id) ->
    @loadWorker('js2coffee')
    @loadConverter(id)

  __include__: [BackgroundWorker, codeConverter]

  changeHandler: _.throttle(
    ->
      if @textarea.val() isnt @previousValue
        @compiler.postMessage @textarea.val()
        @previousValue = @textarea.val()
    500
  )
)
HtmlConverter = Class.$extend(
  __init__: (id) ->
    @loadConverter(id)

  __include__: [codeConverter]
)
HtmlJadeConverter = HtmlConverter.$extend(
  previewCode: (jade) ->
    jade = jade
      .replace('html\n', '')
      .replace(/.*body\n/, '')
      .replace(/^\s\s/, '')
      .replace(/\n\s\s/, '\n')
    @$super($.trim(jade))
)
CssConverter = Class.$extend(
  __init__: (id) ->
    @loadConverter(id)

  __include__: [codeConverter]
)
FiddleEditor = Class.$extend(
  __init__: (@settings) ->
    @id =
      document : 'document'
      style : 'style'
      program : 'program'
      css : 'cssViewer'
      javascript : 'javascriptViewer'
      html : 'htmlViewer'

    view_model.styleLanguage = @settings.get_language LANGUAGE_TYPE.STYLE
    view_model.documentLanguage = @settings.get_language LANGUAGE_TYPE.DOCUMENT
    view_model.programLanguage = @settings.get_language LANGUAGE_TYPE.PROGRAM

    @documentEditor = @settings.get_editor(LANGUAGE_TYPE.DOCUMENT) @id.document
    @styleEditor = @settings.get_editor(LANGUAGE_TYPE.STYLE) @id.style
    @programEditor = @settings.get_editor(LANGUAGE_TYPE.PROGRAM) @id.program

    @cssViewer = CssViewer @id.css
    @cssViewer.observe @styleEditor
    if @settings.get_editor(LANGUAGE_TYPE.PROGRAM) is LANGUAGE.PYTHON
      @javascriptViewer = BeautifiedJavascriptViewer @id.javascript
    else
      @javascriptViewer = JavascriptViewer @id.javascript
    @javascriptViewer.observe @programEditor
    if @showHtmlSource()
      @htmlViewer = HtmlViewer @id.html
      @htmlViewer.observe @documentEditor

    @codeStorage = CodeStorage(@settings)
    @diffViewer = DiffViewer 'compare', @settings

  load: ->
    @keyboradShortcutLetters = new Array
    @keyListener = new KeyListener
    @registerKeyboardShortcut @id.document, @documentEditor, @getKeyboardShortcut(@settings.get_language(LANGUAGE_TYPE.DOCUMENT))
    @registerKeyboardShortcut @id.style, @styleEditor, @getKeyboardShortcut(@settings.get_language(LANGUAGE_TYPE.STYLE))
    @registerKeyboardShortcut @id.program, @programEditor, @getKeyboardShortcut(@settings.get_language(LANGUAGE_TYPE.PROGRAM))

    viewModel.containers @layoutFrames()
    $('#viewer').appendTo('#result').show()
    root.codeRunner = CodeRunner()
    viewModel.add_resource(if debug then base_url + '/js/jquery-1.7.1.js' else 'http://ajax.googleapis.com/ajax/libs/jquery/1.7.1/jquery.min.js')

    @styleEditor.load()
    @documentEditor.load()
    @programEditor.load()

  get_code: (type) ->
    switch type
      when LANGUAGE_TYPE.STYLE
        @styleEditor.get_code()
      when LANGUAGE_TYPE.DOCUMENT
        @documentEditor.get_code()
      when LANGUAGE_TYPE.PROGRAM
        @programEditor.get_code()
      when LANGUAGE_TYPE.COMPILED_PROGRAM
        @programEditor.get_compiled_code()
      when LANGUAGE_TYPE.COMPILED_DOCUMENT
        @documentEditor.get_compiled_code()
      when LANGUAGE_TYPE.COMPILED_STYLE
        @styleEditor.get_compiled_code()
      else
        @codeStorage.set_code @programEditor.get_code(), LANGUAGE_TYPE.PROGRAM
        @codeStorage.set_code @programEditor.get_compiled_code(), LANGUAGE_TYPE.COMPILED_PROGRAM
        @codeStorage.set_code @documentEditor.get_code(), LANGUAGE_TYPE.DOCUMENT
        @codeStorage.set_code @styleEditor.get_code().replace(@styleEditor.get_framework(), ''), LANGUAGE_TYPE.STYLE
        @codeStorage.set_code ko.toJSON(viewModel.resources()), LANGUAGE_TYPE.RESOURCE
        @codeStorage.set_code ko.toJSON(viewModel.frameworks()), LANGUAGE_TYPE.FRAMEWORK
        @codeStorage.get_file()

  set_code: (code, type) ->
    return  unless code.length
    switch type
      when LANGUAGE_TYPE.STYLE
        @styleEditor.set_code code
      when LANGUAGE_TYPE.DOCUMENT
        @documentEditor.set_code code
      when LANGUAGE_TYPE.PROGRAM
        @programEditor.set_code code
      when LANGUAGE_TYPE.COMPILED_PROGRAM
        @javascriptViewer.set_code code
        @programEditor.set_compiled_code code
      when LANGUAGE_TYPE.COMPILED_DOCUMENT
        @documentEditor.set_code code
      when LANGUAGE_TYPE.COMPILED_STYLE
        @styleEditor.set_code code
      when LANGUAGE_TYPE.FRAMEWORK
        @styleEditor.set_framework code
      else
        @codeStorage.set_file code
        viewModel.resources []
        resources = @codeStorage.get_code(LANGUAGE_TYPE.RESOURCE)
        unless resources is '[]'
          _.each ko.utils.parseJson(resources), (resource) ->
            viewModel.add_resource resource.source
        frameworks = @codeStorage.get_code(LANGUAGE_TYPE.FRAMEWORK)
        unless frameworks is '[]'
          _.each ko.utils.parseJson(frameworks), (frameworkName) ->
            viewModel.add_framework frameworkName

        @documentEditor.set_code @codeStorage.get_code(LANGUAGE_TYPE.DOCUMENT)
        @styleEditor.set_code @codeStorage.get_code(LANGUAGE_TYPE.STYLE)
        @programEditor.set_code @codeStorage.get_code(LANGUAGE_TYPE.PROGRAM)

  execute: ->
    codeRunner.debug()

  get_primary_language: ->
    codeComplexity = {}
    codeComplexity[@documentEditor.get_code_complexity()] = @settings.get_language LANGUAGE_TYPE.DOCUMENT
    codeComplexity[@styleEditor.get_code_complexity()] = @settings.get_language LANGUAGE_TYPE.STYLE
    codeComplexity[@programEditor.get_code_complexity()] = @settings.get_language LANGUAGE_TYPE.PROGRAM
    codeComplexity[Math.max(_.keys(codeComplexity)...)]

  layoutFrames: ->
    if $(window).width() < 1200
      layout = ColumnLayout 2
    else
      layout = ColumnLayout 3

      frame = Frame 'documentation', 'Documentation'
      tabs = TabInterface 'documentation-tabs'
      for documentation in [@styleEditor.get_documentation(), @documentEditor.get_documentation(), @programEditor.get_documentation()]
        tabs.add documentation.title, documentation.content
      page = IframeComponent 'jqueryReferenceTab'
      page.set_source base_url + '/files/documentation/jquery/index.html'
      tabs.add 'jquery', page.to_html_string()
      frame.add tabs

      layout.add_column frame

    editor_frames = new Array
    for frame_setting, editorIndex in [[@id.document, @getLanguageHeading @settings.get_language(LANGUAGE_TYPE.DOCUMENT)], [@id.style, @getLanguageHeading @settings.get_language(LANGUAGE_TYPE.STYLE)], [@id.program, @getLanguageHeading @settings.get_language(LANGUAGE_TYPE.PROGRAM)]]
      frame = Frame frame_setting[0] + 'container', frame_setting[1]
      editor = EditorComponent frame_setting[0]
      if editorIndex is 0
        editor.focus_on_initialization()
      frame.add editor
      editor_frames.push frame
    layout.add_column editor_frames

    frames = new Array
    resultFrame = Frame 'result', 'Result'
    frames.push resultFrame

    # source preview tabs
    previewFrame = Frame 'source', 'Source'
    tabs = TabInterface 'source-tab'
    preview = IframeComponent @id.css
    preview.set_source if debug then base_url + '/files/csspreviewer.html' else 'http://fiddlesalad.com/home/files/csspreviewer.html?v=2012041516'
    index = tabs.add 'css', preview.to_html_string()
    @styleEditor.set_focus_listener PreviewListener('source', index)

    preview = PreviewComponent @id.javascript
    index = tabs.add 'javascript', preview.to_html_string()
    @programEditor.set_focus_listener PreviewListener('source', index)

    if @showHtmlSource()
      preview = PreviewComponent @id.html
      index = tabs.add 'html', preview.to_html_string()
      @documentEditor.set_focus_listener PreviewListener('source', index)

    previewFrame.add tabs
    frames.push previewFrame

    layout.add_column frames

    result_x = resultFrame.get_location().x
    preview_y = previewFrame.get_location().y
    shareFrame = Frame 'sharecontainer', 'Share'
    shareFrame.set_location(x: result_x, y: preview_y - 100)
    shareFrame.set_size(width: 200, height: 80)
    shareBox = TemplateComponent 'share'
    shareBox.set_template 'shareTemplate'
    shareFrame.add shareBox

    columnLayoutFrames = layout.get_frames()
    if not debug
      columnLayoutFrames.push shareFrame
    columnLayoutFrames

  compare_revisions: (older, newer) ->
    @diffViewer.set_revisions older, newer
    @diffViewer.compare_language_type LANGUAGE_TYPE.DOCUMENT

  showHtmlSource: ->
    not (@settings.get_language(LANGUAGE_TYPE.DOCUMENT) in COMPATIBLE_LANGUAGES.HTML)

  getRelatedLanguages: (primaryLanguage) ->
    relatedLanguages = new Array
    for language, languageType of LANGUAGE_CATEGORY
      if languageType is LANGUAGE_CATEGORY[primaryLanguage]
        relatedLanguages.push language
    _.reject relatedLanguages, (language) => language is primaryLanguage

  getLanguageHeading: (language) ->
    menuItemTemplate = _.template('<li><a><%= text %></a></li>')
    alternativeMenuItems = _.map(@getRelatedLanguages(language), (relatedLanguage) ->
        menuItemTemplate text: relatedLanguage
      )
    languageMenu = """
      <ul class="menu">
        <li class="primary"><a>#{ language }</a>
            <ul>
               #{ alternativeMenuItems.join('') }
            </ul>
        </li>
      </ul>"""
    heading = ['<div class="clearfix"><div class="left">', languageMenu, '</div>' ]
    unless bowser.opera
      heading.push '<div class="right"><span class="key-lite">', @getKeyboardShortcut(language), '</span></div>'
    heading.push '</div>'
    heading.join('')

  getKeyboardShortcut: _.memoize((language) ->
    languageFirstLetter = language.charAt(0).toUpperCase()
    if @keyboradShortcutLetters.indexOf(languageFirstLetter) is -1
      @keyboradShortcutLetters.push languageFirstLetter
      'Alt ' + language.charAt(0).toUpperCase()
    else
      'Alt Shift ' + language.charAt(0).toUpperCase()
  )

  registerKeyboardShortcut: (dialogId, editor, shortcut) ->
    @keyListener.on(
      shortcut
      ->
        $('#' + dialogId + 'container').parent().wijdialog 'moveToTop'
        editor.focus()
    )
)
DiffViewer = Class.$extend(
  __init__: (@id, @settings) ->
    @olderTimestamp = new String
    @newerTimestamp = new String

  set_revisions: (olderTimestamp, newerTimestamp) ->
    return  if @olderTimestamp is olderTimestamp and @newerTimestamp is newerTimestamp
    @olderTimestamp = olderTimestamp
    @newerTimestamp = newerTimestamp
    @olderRevision = CodeStorage @settings
    @newerRevision = CodeStorage @settings
    @olderRevision.set_file store.get(olderTimestamp)
    @newerRevision.set_file store.get(newerTimestamp)

  openCompareWindow: ->
    layout = ColumnLayout 1
    title = HtmlComponent 'compareLanguageSelection'
    layout.add_column Frame(@id, 'Compare Revisions' + title.to_html_string())
    viewModel.containers.push _.first(layout.get_frames())
    $('#compareLanguageSelection input').change =>
      @compare_language_type $('#compareLanguageSelection input:checked').val()

  compare_language_type: (type) ->
    if not $('#' + @id).length
      @openCompareWindow()
      $('#' + @id).mergely
        cmsettings:
          readOnly: false
          lineNumbers: true

        lhs: (setValue) =>
          setValue @olderRevision.get_code(type)

        rhs: (setValue) =>
          setValue @newerRevision.get_code(type)
    else
      $('#' + @id).mergely 'lhs', @olderRevision.get_code(type)
      $('#' + @id).mergely 'rhs', @newerRevision.get_code(type)

)
ColumnLayout = Class.$extend(
  __init__: (columns) ->
    panel_size = 195
    @column_width = (getDocumentWidth() - panel_size) / columns
    @document_height = getDocumentHeight()
    @frames = new Array

  add_column: (frames) ->
    if !_.isArray frames
      frames = new Array(frames)
    for frame in frames
      frame.set_size(
        width: @column_width,
        height: @document_height/frames.length
      )
      if @frames.length > 0
        frame.set_location_relative_to _.last(@frames)
      @frames.push frame

  get_frames: ->
    @frames
)
CodeRunner = Class.$extend(
  __init__: ->
    frame = document.getElementById('viewer')
    @window = (if frame.contentWindow then frame.contentWindow else (if frame.contentDocument.document then frame.contentDocument.document else frame.contentDocument))
    @scripts = [base_url + '/js/prettyprint.js']
    @synchronizeNextExecution()
    @template =
      css: _.template '<link rel="stylesheet" type="text/css" href="<%= source %>" />'
      js: _.template '<script type="text/javascript" src="<%= source %>"></script>'
      html: _.template """
            <!DOCTYPE html>
            <html>
              <head>
                <title>Fiddle Salad Debug View</title>
                <script src="http://leaverou.github.com/prefixfree/prefixfree.min.js"></script>
                <style>
                  <%= css %>
                </style>
              </head>
              <body>
                <%= body %>
                <%= headtags %>
                <script type="text/javascript">
                  <%= javascript %>
                </script>
              </body>
            </html>
            """

  execute: (code) ->
    return  unless code.length
    script = @window.document.createElement('script')
    script.type = 'text/javascript'
    script.text = [ 'head.js("', @scripts.join('", "'), '", function() {', code, '});' ].join('')
    @window.document.body.appendChild script

  filetype: (path) ->
    filePattern = /(css|js)$/
    path.match(filePattern)[0]

  add_javascript: (source) ->
    @scripts.push source

  add_css: (source) ->
    style = @window.document.createElement('link')
    style.rel = 'stylesheet'
    style.type = 'text/css'
    style.href = source
    @window.document.getElementsByTagName('head')[0].appendChild style

  add_file: (source) ->
    switch @filetype(source)
      when 'css'
        @add_css source
        true
      when 'js'
        @add_javascript source
        true
      else
        false

  remove_css: (source) ->
    css_links = @window.document.getElementsByTagName('link')
    @window.document.getElementsByTagName('head')[0].removeChild _.find(css_links, (link) ->
        link and link.getAttribute('href')? and link.getAttribute('href').indexOf(source) isnt -1
    )

  reset: ->
    code = engine.get_code()
    @window.location.reload()
    setTimeout =>
        @__init__()
        engine.set_code code
      , 750

  synchronizeNextExecution: ->
    @originalExecute = @execute
    @execute = _.after(2,
      (code) =>
        @originalExecute(code)
        @execute = @originalExecute
    )

  debug: ->
    ###
    Debug opens a new window with the code loaded in the page. External CSS and JS files are loaded through head tags.
    It assumes all external resources are stored in the view model.
    ###
    # initialize array of head tags
    headTags = new Array
    # for each external resource in view model
    _.each viewModel.resources(), (resource) =>
      # get the file type of the resource, call mapped template with resource, and append generated HTML to head tags
      headTags.push @template[@filetype resource.source()](source: resource.source())
    headtags = headTags.join('')
    # get JavaScript and CSS code from the engine
    javascript = engine.get_code LANGUAGE_TYPE.COMPILED_PROGRAM
    body = engine.get_code LANGUAGE_TYPE.COMPILED_DOCUMENT
    css = engine.get_code LANGUAGE_TYPE.COMPILED_STYLE
    # call the template for the window with the head tags and code
    html = @template.html {javascript, css, body, headtags}
    # open window with generated HTML 
    window.open 'data:text/html;charset=utf-8,' + encodeURIComponent(html)
    # display message about new window and links to browser console documentation
    if bowser.firefox
      documentationUrl = 'http://getfirebug.com/'
      consoleName = 'Firebug'
    else if bowser.opera
      documentationUrl = 'http://www.opera.com/dragonfly/'
      consoleName = 'Opera Dragonfly'
    else
      documentationUrl = 'http://code.google.com/chrome/devtools/docs/console.html'
      consoleName = 'Chrome Console'
    @window.document.body.innerHTML = """
      <h3>Console Debug</h3>
      <p>
        A new page has been created for you to debug JavaScript. Launch <a target="_blank" href="#{ documentationUrl }">#{ consoleName }</a>
        to start your debugging session.
      </p>
      """
)
FiddleFactory = Class.$extend(
  __init__: ->
    document.getElementById('progress')?.value = 30
    @display_browser_warning()
    @code = document.getElementById('snippet').value
    if @code.length
      settings = @loadLanguages(@code)
    else
      settings = @detectLanguages()
    @editor = FiddleEditor(settings)

  display_browser_warning: ->
    return  if bowser.chrome and bowser.version >= 3
    return  if bowser.firefox and bowser.version >= 3.5
    return  if bowser.safari and bowser.version >= 4
    return  if bowser.opera and bowser.version >= 10.6
    alert 'You are using an unsupported browser.\nTry Chrome, Firefox, Safari, or Opera.'

  get_url_path_language: ->
    languagePart = window.location.pathname.split('/')[1]
    if languagePart.length and languagePart.indexOf('-') is -1
      languagePart
    else
      'python'

  detectLanguages: ->
    ###
    This routine detects the programming languages to be loaded. It reads from the URL and retrieves comma-separated
    languages from storage. The URL segment can override one of the languages from storage. If no language setting is
    stored, it uses defaults. It returns a language setting object.
    ###
    #  read from the URL segment and storage
    primaryLanguage = @get_url_path_language()
    secondaryLanguages = if store.get('languages')? then store.get('languages').split(',') else [LANGUAGE.HTML, LANGUAGE.LESS, LANGUAGE.JAVASCRIPT]
    #  if language in URL overrides a language from storage in its category, then replace it
    for language, languageIndex in secondaryLanguages
      if LANGUAGE_CATEGORY[language] is LANGUAGE_CATEGORY[primaryLanguage]
        secondaryLanguages[languageIndex] = primaryLanguage
    Language secondaryLanguages

  loadLanguages: (storageJSON) ->
    Language _.keys(JSON.parse(storageJSON))

  layout: ->
    $('#snippet, #progress').remove()
    $('#documentation, #source').parent().scrollTop(0)
    $('#logo').click(-> window.open('/'))
    $('.menu').wijmenu(
      select: (event, data) ->
        selectedItem = data.item
        return  if 'primary' in selectedItem.attr('class').split(/\s+/)
        languages = new Array
        $('ul.menu li.primary > a').each(-> languages.push $(this).text())
        languages = _.without languages, selectedItem.parents('.primary').find('a:first').text()
        selectedLanguage = selectedItem.text()
        languages.push selectedLanguage
        store.set('languages', languages.join(','))
        window.open("/#{ selectedLanguage }/")
      showDelay: 0
    )
    $('.menu').show()
    unless bowser.webkit
      $('.ui-dialog-title').css(position: 'static', height: '1em')

  get_view_model: ->
    document.getElementById('progress')?.value = 90
    FiddleViewModel()

  load_threads: ->
    @editor.set_code @code

  execute: ->
    @editor.execute()

  reset: ->
    codeRunner.reset()
)
root.editor = {HtmlEditor, LessEditor, PythonEditor, JavascriptEditor, CssEditor, CoffeescriptEditor, SassEditor, ScssEditor, HamlEditor, StylusEditor, JadeEditor, ZencodingEditor, HtmlViewer, CoffeecupEditor, MarkdownEditor, RoyEditor}
root.engine = EngineFactory(FiddleFactory())