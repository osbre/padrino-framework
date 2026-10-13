module Padrino
  module Admin
    ##
    # Rewrites Bootstrap 3 markup to Bootstrap 5.
    #
    # Classes are rewritten wherever they live (class attributes, Ruby +class:+ options,
    # Haml/Slim shorthand, jQuery +addClass+ calls), Bootstrap data attributes move to the
    # +data-bs-+ namespace, and whatever needs a human comes back as a note with its line.
    # Interpolated parts (+#{...}+, +<%= %>+) are left untouched, line numbers never shift,
    # and converting already converted source is a no-op.
    #
    # @example
    #   result = Padrino::Admin::BootstrapUpgrade.convert(File.read(path), :haml)
    #   result.source # => the converted template
    #   result.notes  # => [#<struct line=12, message="...">]
    #
    module BootstrapUpgrade
      Result = Struct.new(:source, :notes)
      Note   = Struct.new(:line, :message) do
        def to_s
          "line #{line}: #{message}"
        end
      end

      RENAMES = {
        'btn-default' => 'btn-secondary', 'btn-xs' => 'btn-sm', 'btn-mini' => 'btn-sm', 'btn-small' => 'btn-sm', 'btn-large' => 'btn-lg', 'btn-block' => 'w-100',
        'pull-left' => 'float-start', 'pull-right' => 'float-end', 'text-left' => 'text-start', 'text-right' => 'text-end', 'center-block' => 'd-block mx-auto',
        'hidden' => 'd-none', 'hidden-xs' => 'd-none d-sm-block', 'hidden-sm' => 'd-sm-none d-md-block', 'hidden-md' => 'd-md-none d-lg-block', 'hidden-lg' => 'd-lg-none',
        'sr-only' => 'visually-hidden', 'sr-only-focusable' => 'visually-hidden-focusable', 'muted' => 'text-muted', 'text-error' => 'text-danger',
        'img-responsive' => 'img-fluid', 'img-rounded' => 'rounded', 'img-circle' => 'rounded-circle', 'thumbnail' => 'img-thumbnail',
        'in' => 'show', 'close' => 'btn-close', 'alert-dismissable' => 'alert-dismissible', 'alert-error' => 'alert-danger', 'table-condensed' => 'table-sm',
        'form-group' => 'mb-3', 'control-group' => 'mb-3', 'control-label' => 'form-label', 'help-block' => 'form-text', 'help-inline' => 'form-text',
        'checkbox' => 'form-check', 'radio' => 'form-check', 'checkbox-inline' => 'form-check form-check-inline', 'radio-inline' => 'form-check form-check-inline',
        'form-inline' => 'd-flex flex-wrap align-items-center gap-2', 'input-sm' => 'form-control-sm', 'input-lg' => 'form-control-lg',
        'input-small' => 'form-control-sm', 'input-large' => 'form-control-lg', 'input-group-addon' => 'input-group-text', 'input-group-btn' => '',
        'navbar-default' => 'navbar-light bg-light', 'navbar-inverse' => 'navbar-dark bg-dark', 'navbar-fixed-top' => 'fixed-top', 'navbar-fixed-bottom' => 'fixed-bottom',
        'navbar-static-top' => '', 'navbar-inner' => '', 'navbar-header' => '', 'navbar-btn' => '', 'navbar-toggle' => 'navbar-toggler',
        'navbar-right' => 'ms-auto', 'navbar-left' => 'me-auto', 'navbar-form' => 'd-flex', 'nav-stacked' => 'flex-column',
        'divider' => 'dropdown-divider', 'dropdown-menu-right' => 'dropdown-menu-end', 'dropdown-menu-left' => 'dropdown-menu-start', 'caret' => '',
        'panel' => 'card', 'panel-default' => '', 'panel-heading' => 'card-header', 'panel-title' => 'card-title', 'panel-body' => 'card-body', 'panel-footer' => 'card-footer',
        'well' => 'card card-body bg-light', 'well-sm' => 'p-2', 'well-lg' => 'p-4', 'popover-title' => 'popover-header', 'popover-content' => 'popover-body', 'arrow' => 'popover-arrow',
        'page-header' => 'pb-2 mt-4 mb-2 border-bottom', 'jumbotron' => 'p-5 mb-4 bg-light rounded-3', 'dl-horizontal' => 'row',
        'embed-responsive' => 'ratio', 'embed-responsive-16by9' => 'ratio-16x9', 'embed-responsive-4by3' => 'ratio-4x3', 'embed-responsive-item' => ''
      }.freeze

      PATTERNS = {
        /\Acol-xs-(\d+)\z/ => 'col-\1',
        /\Acol-xs-offset-(\d+)\z/ => 'offset-\1',
        /\Acol-(sm|md|lg)-offset-(\d+)\z/ => 'offset-\1-\2',
        /\Aprogress-bar-(success|info|warning|danger)\z/ => 'bg-\1',
        /\Apanel-(primary|success|info|warning|danger)\z/ => 'border-\1'
      }.freeze

      # Classes whose conversion needs a human; %s is the original class.
      CLASS_NOTES = {
        /\Aglyphicon/ => 'Glyphicons were removed; use tag_icon (Font Awesome) instead of .%s',
        /\Ahas-(error|warning|success)\z/ => '.%s moved to the field: add is-invalid or is-valid to the input itself',
        /\A(checkbox|radio)(-inline)?\z/ => '.%s is now .form-check: add form-check-input to the input and form-check-label to its label',
        /\Acol-\w+-(push|pull)-\d+\z/ => '.%s was removed; use order-* utilities',
        /\Avisible-/ => '.%s was removed; combine d-none with d-{breakpoint}-{display}',
        /\Aform-horizontal\z/ => '.%s: put .row on each group and col-form-label on its label',
        /\Ainput-group-btn\z/ => '.%s was removed: place the button directly inside .input-group',
        /\Aclose\z/ => '.btn-close draws its own icon: remove the &times; inside it',
        /\Adl-horizontal\z/ => '.%s: add col-sm-3 to each dt and col-sm-9 to each dd',
        /\Athumbnail\z/ => '.%s: if it wraps more than an image, use .card instead',
        /\A(pager|affix|btn-group-justified)\z/ => '.%s was removed in Bootstrap 4'
      }.freeze

      # Containers whose children need a class of their own, unless the source already has it.
      CHILD_CLASSES = {
        'dropdown-menu' => ['dropdown-item', 'give each link inside .dropdown-menu the dropdown-item class'],
        'nav-tabs' => ['nav-link', 'give each item in .nav-tabs nav-item, each link nav-link, and move .active onto the link'],
        'nav-pills' => ['nav-link', 'give each item in .nav-pills nav-item, each link nav-link, and move .active onto the link'],
        'navbar-nav' => ['nav-link', 'give each item in .navbar-nav nav-item, each link nav-link, and move .active onto the link'],
        'pagination' => ['page-link', 'give each item in .pagination page-item and each link page-link'],
        'breadcrumb' => ['breadcrumb-item', 'give each item in .breadcrumb the breadcrumb-item class'],
        'list-inline' => ['list-inline-item', 'give each item in .list-inline the list-inline-item class']
      }.freeze

      LINE_NOTES = {
        /\)\.(modal|tooltip|popover|dropdown|tab|collapse|alert|button|carousel|scrollspy)\(/ =>
          'jQuery .%s() only exists when jQuery loads before Bootstrap 5; prefer bootstrap.*.getOrCreateInstance(element)',
        /data-(?:bs-)?spy=\W*affix/ => 'Affix was removed; use the sticky-top class or position: sticky',
        /data-loading-text/ => 'the button loading state was removed; toggle the text and disabled state yourself'
      }.freeze

      PLACEMENTS   = { 'top' => 'top', 'right' => 'end', 'bottom' => 'bottom', 'left' => 'start' }.freeze
      BTN_VARIANT  = /\Abtn-(outline-)?(primary|secondary|success|info|warning|danger|light|dark|link)\z/.freeze
      DATA_KEYS    = %w[toggle target dismiss parent ride slide slide-to spy backdrop keyboard interval pause wrap].freeze
      TIP_KEYS     = %w[placement content trigger container html delay animation offset].freeze
      DATA_HASH    = /(?<![\w-])(?:data:|:data\s*=>)\s*\{[^{}]*\}/.freeze
      OPAQUE       = /#\{(?<b>(?:[^{}]|\{\g<b>\})*)\}|<%.*?%>/.freeze
      QUOTED_CLASS = /(?<pre>(?<![\w.:@$-])(?:class\s*=\s*|class:\s*|:class\s*=>\s*|(?<cq>['"])class\k<cq>\s*=>\s*|(?:add|remove|toggle|has)Class\(\s*))
                      (?<q>["'])(?<v>(?:\#\{(?<b>(?:[^{}]|\{\g<b>\})*)\}|<%.*?%>|(?!\k<q>).)*)\k<q>/x.freeze
      BARE_CLASS   = /(?<pre>(?<![\w.:@$-])class=)(?<q>)(?<v>[\w-]+)/.freeze
      SHORTHAND    = {
        haml: /\A(?<ind>[ \t]*)(?<tag>%[\w:-]+)?(?<sel>(?:[.#][\w-]+)+)/,
        slim: /\A(?<ind>[ \t]*)(?<tag>[a-z][\w:-]*)?(?<sel>(?:[.#][\w-]+)+)/
      }.freeze
      FILTER = /\A[ \t]*(?::\w+|\w+:)[ \t]*$/.freeze

      class << self
        ##
        # Converts +source+ written as +type+ (:erb, :haml, :slim, :js or :ruby).
        #
        def convert(source, type = :erb)
          notes = []
          source = rewrite_class_values(source, type, notes)
          source = rewrite_shorthand(source, type, notes) if SHORTHAND.key?(type)
          source = rewrite_data_attributes(source)
          source.each_line.with_index(1) do |line, number|
            LINE_NOTES.each { |pattern, message| notes << Note.new(number, message.sub('%s', ::Regexp.last_match(1))) if line =~ pattern }
          end
          Result.new(source, notes.uniq.sort_by(&:line))
        end

        ##
        # Guesses the type from a file name, nil when there's nothing to convert.
        #
        def type_for(path)
          case path
          when /\.haml(\.tt)?\z/ then :haml
          when /\.slim(\.tt)?\z/ then :slim
          when /\.(erb|html?)(\.tt)?\z/ then :erb
          when /\.js\z/ then :js
          when /\.rb\z/ then :ruby
          end
        end

        ##
        # Rewrites a list of class names, collecting notes for +line+.
        #
        def rewrite(classes, source = '', line = 1, notes = [])
          classes.each { |name| notes.concat(notes_for(name, source).map { |message| Note.new(line, message) }) }
          out = classes.flat_map { |name| RENAMES.fetch(name) { PATTERNS.reduce(name) { |result, (from, to)| result.sub(from, to) } }.split }

          if out.include?('label') && (variant = out.grep(/\Alabel-(default|primary|success|info|warning|danger)\z/).first)
            out.map! { |name| { 'label' => 'badge', variant => "bg-#{variant == 'label-default' ? 'secondary' : variant[6..]}" }.fetch(name, name) }
          end
          if (kind = (out & %w[popover tooltip]).first)
            out.map! { |name| PLACEMENTS.key?(name) ? "bs-#{kind}-#{PLACEMENTS[name]}" : name }
          end
          unless out.any? { |name| name.include?("\0") }
            out.push('rounded-pill', 'bg-secondary') if out.include?('badge') && out.none? { |name| name =~ /\A(text-)?bg-/ }
            out.push('btn-secondary') if out.include?('btn') && out.none? { |name| name =~ BTN_VARIANT }
            out.push('navbar-expand-md') if out.include?('navbar') && out.none? { |name| name.start_with?('navbar-expand') }
          end
          out.uniq
        end

        private

        def notes_for(name, source)
          CLASS_NOTES.filter_map { |pattern, message| message.sub('%s', name) if name =~ pattern } +
            CHILD_CLASSES.filter_map { |container, (child, message)| message if name == container && source !~ /(?<![\w-])#{child}(?![\w-])/ }
        end

        def rewrite_class_values(source, type, notes)
          [QUOTED_CLASS, (BARE_CLASS if type == :erb)].compact.reduce(source) do |text, pattern|
            text.gsub(pattern) do
              match = $~
              value = rewrite_value(match[:v], text, line_at(text, match.begin(0)), notes)
              quote = match[:q].empty? && value !~ /\A[\w-]+\z/ ? '"' : match[:q]
              "#{match[:pre]}#{quote}#{value}#{quote}"
            end
          end
        end

        def rewrite_value(value, source, line, notes)
          opaque = []
          tokens = value.gsub(OPAQUE) do
            opaque << ::Regexp.last_match(0)
            "\0#{opaque.size - 1}\0"
          end.split
          classes = rewrite(tokens, source, line, notes)
          classes == tokens ? value : classes.join(' ').gsub(/\0(\d+)\0/) { opaque[::Regexp.last_match(1).to_i] }
        end

        def rewrite_shorthand(source, type, notes)
          filter = nil
          source.each_line.with_index(1).map do |line, number|
            indent = line[/\A[ \t]*/].size
            next line if filter && (line.strip.empty? || indent > filter)

            filter = line =~ FILTER ? indent : nil
            line.sub(SHORTHAND[type]) do
              match = $~
              parts   = match[:sel].scan(/[.#][\w-]+/)
              classes = parts.grep(/\A\./).map { |part| part[1..] }
              converted = rewrite(classes, source, number, notes)
              next match[0] if converted == classes

              ids = parts.grep(/\A#/).join
              selector = converted.map { |name| ".#{name}" }.join
              selector = parts.first.start_with?('#') ? ids + selector : selector + ids
              tag = match[:tag] || (selector.empty? ? { haml: '%div', slim: 'div' }[type] : '')
              "#{match[:ind]}#{tag}#{selector}"
            end
          end.join
        end

        def rewrite_data_attributes(source)
          source.each_line.map do |line|
            keys = Regexp.union(line =~ /tooltip|popover|spy/ ? DATA_KEYS + TIP_KEYS : DATA_KEYS)
            line.gsub(/(?<![\w-])data-(#{keys})(?![\w-])/, 'data-bs-\1').gsub(DATA_HASH) do |hash|
              hash.gsub(/(?<![\w'":-])(#{keys}):(?!:)/, "'bs-\\1':")
                  .gsub(/:(#{keys})(\s*=>)/, ":'bs-\\1'\\2")
                  .gsub(/(['"])(#{keys})\1(\s*(?:=>|:))/, '\1bs-\2\1\3')
            end
          end.join
        end

        def line_at(text, offset)
          text[0, offset].count("\n") + 1
        end
      end
    end
  end
end
