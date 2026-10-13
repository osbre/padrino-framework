require_relative 'helper'

describe 'BootstrapUpgrade' do
  def convert(source, type = :erb)
    Padrino::Admin::BootstrapUpgrade.convert(source, type)
  end

  def classes(*names)
    Padrino::Admin::BootstrapUpgrade.rewrite(names).join(' ')
  end

  describe 'classes' do
    it 'should rename, split and drop classes' do
      assert_equal 'btn btn-secondary btn-sm', classes('btn', 'btn-default', 'btn-xs')
      assert_equal 'card card-body bg-light', classes('well')
      assert_equal 'dropdown-toggle', classes('dropdown-toggle', 'caret')
      assert_equal 'alert alert-info fade show', classes('alert', 'alert-info', 'fade', 'in')
      assert_equal 'my-own-class', classes('my-own-class')
    end

    it 'should rewrite grid and offset classes' do
      assert_equal 'col-12 col-md-6 offset-md-3 offset-1', classes('col-xs-12', 'col-md-6', 'col-md-offset-3', 'col-xs-offset-1')
    end

    it 'should turn labels into badges' do
      assert_equal 'badge bg-danger', classes('label', 'label-danger')
      assert_equal 'badge bg-secondary', classes('label', 'label-default')
      assert_equal 'badge rounded-pill bg-secondary', classes('badge')
    end

    it 'should turn panels into cards' do
      assert_equal 'card border-success', classes('panel', 'panel-success')
      assert_equal 'card-header', classes('panel-heading')
    end

    it 'should map popover and tooltip placements' do
      assert_equal 'popover bs-popover-start', classes('popover', 'left')
      assert_equal 'tooltip bs-tooltip-end', classes('tooltip', 'right')
      assert_equal 'menu left', classes('menu', 'left')
    end

    it 'should give bare buttons and navbars their Bootstrap 5 defaults' do
      assert_equal 'btn btn-secondary', classes('btn')
      assert_equal 'btn btn-outline-danger', classes('btn', 'btn-outline-danger')
      assert_equal 'navbar navbar-dark bg-dark navbar-expand-md', classes('navbar', 'navbar-inverse')
    end
  end

  describe 'erb and html' do
    it 'should rewrite quoted, single quoted and bare class attributes' do
      assert_equal '<p class="float-end">', convert('<p class="pull-right">').source
      assert_equal "<p class='text-end'>", convert("<p class='text-right'>").source
      assert_equal '<p class=float-start>', convert('<p class=pull-left>').source
      assert_equal '<p class="card card-body bg-light">', convert('<p class=well>').source
      assert_equal '<p class="">', convert('<p class=navbar-inner>').source
    end

    it 'should rewrite Ruby class options in every hash style' do
      assert_equal %(<%= link_to 'x', '#', class: 'btn btn-secondary' %>), convert(%(<%= link_to 'x', '#', class: 'btn btn-default' %>)).source
      assert_equal %(link_to 'x', :class => "float-end"), convert(%(link_to 'x', :class => "pull-right"), :ruby).source
      assert_equal %(tag :p, 'class' => 'float-end'), convert(%(tag :p, 'class' => 'pull-right'), :ruby).source
    end

    it 'should leave interpolations and erb tags alone' do
      source = %(<div class="alert alert-<%= kind %> in">)
      assert_equal %(<div class="alert alert-<%= kind %> show">), convert(source).source
      source = %(flash_tag(type, class: "alert alert-\#{name} fade in"))
      assert_equal %(flash_tag(type, class: "alert alert-\#{name} fade show")), convert(source, :ruby).source
    end

    it 'should not add defaults next to dynamic classes' do
      assert_equal %(class: "btn btn-\#{kind}"), convert(%(class: "btn btn-\#{kind}"), :ruby).source
    end

    it 'should not touch things that merely look like classes' do
      source = %(<%= record.class == Post %> <%= @klass = 'hidden' %> el.className = 'hidden')
      assert_equal source, convert(source).source
    end
  end

  describe 'haml' do
    it 'should rewrite shorthand and keep ids, tags and content' do
      assert_equal "%table#list.table.table-sm\n", convert("%table#list.table.table-condensed\n", :haml).source
      assert_equal "#main.card.card-body.bg-light= yield\n", convert("#main.well= yield\n", :haml).source
      assert_equal "  .float-end{title: 'x'} Hello\n", convert("  .pull-right{title: 'x'} Hello\n", :haml).source
    end

    it 'should keep an element whose only class was dropped' do
      assert_equal "%span\n%div\n", convert("%span.caret\n.navbar-inner\n", :haml).source
    end

    it 'should not touch filters' do
      source = ":javascript\n  modal.close()\n  $('.in').hide()\n%p.text-right\n"
      assert_equal ":javascript\n  modal.close()\n  $('.in').hide()\n%p.text-end\n", convert(source, :haml).source
    end
  end

  describe 'slim' do
    it 'should rewrite shorthand and class attributes' do
      assert_equal "span\nul.list-unstyled class='float-end'\n", convert("span.caret\nul.list-unstyled class='pull-right'\n", :slim).source
    end

    it 'should treat unquoted values as Ruby and leave them alone' do
      assert_equal "p class=hidden_class\n", convert("p class=hidden_class\n", :slim).source
    end

    it 'should rewrite around nested quotes inside interpolation' do
      source = "fieldset class='form-group\#{error ? ' has-error' : ''} pull-right'\n"
      assert_equal "fieldset class='form-group\#{error ? ' has-error' : ''} float-end'\n", convert(source, :slim).source
    end
  end

  describe 'data attributes' do
    it 'should namespace Bootstrap attributes and selectors' do
      assert_equal '<a data-bs-toggle="modal" data-bs-target="#x" data-id="1">', convert('<a data-toggle="modal" data-target="#x" data-id="1">').source
      assert_equal %($('[data-bs-toggle="tooltip"]')), convert(%($('[data-toggle="tooltip"]')), :js).source
    end

    it 'should namespace keys of data hashes' do
      assert_equal %(link_to 'x', data: { 'bs-toggle': :dropdown, id: 1 }), convert(%(link_to 'x', data: { toggle: :dropdown, id: 1 }), :ruby).source
      assert_equal %(link_to 'x', :data => { :'bs-toggle' => :dropdown }), convert(%(link_to 'x', :data => { :toggle => :dropdown }), :ruby).source
      assert_equal %(%a{'data-bs-toggle' => :dropdown}), convert(%(%a{'data-toggle' => :dropdown}), :haml).source
    end

    it 'should namespace tooltip options only next to a tooltip' do
      assert_equal '<a data-bs-toggle="tooltip" data-bs-placement="left">', convert('<a data-toggle="tooltip" data-placement="left">').source
      assert_equal '<div data-content="mine">', convert('<div data-content="mine">').source
    end
  end

  describe 'notes' do
    it 'should report what needs a human with its line' do
      notes = convert("<div>\n  <span class=\"glyphicon glyphicon-star\"></span>\n</div>\n").notes
      assert_equal [2, 2], notes.map(&:line)
      assert_match(/glyphicon-star/, notes.last.message)
    end

    it 'should report missing child classes until they are added' do
      assert_equal 1, convert(%(<ul class="dropdown-menu"><li><a href="#">x</a></li></ul>)).notes.size
      assert_empty convert(%(<ul class="dropdown-menu"><li><a class="dropdown-item">x</a></li></ul>)).notes
    end

    it 'should report jQuery plugin calls' do
      assert_match(/\.modal\(\)/, convert(%($('#x').modal('show');), :js).notes.first.message)
    end

    it 'should report any jQuery left, but not Ruby globals' do
      assert_match(/jQuery is no longer loaded/, convert(%(jQuery.ajax('/x');), :js).notes.first.message)
      assert_empty convert(%(<%= $stdout.sync %>)).notes
    end

    it 'should report removed plugins without a class to name' do
      assert_match(/sticky-top/, convert(%(<div data-spy="affix">)).notes.first.message)
      assert_match(/loading state/, convert(%(<button data-loading-text="...">)).notes.first.message)
    end
  end

  describe 'Bootstrap 3 admin templates' do
    templates = File.expand_path('../lib/padrino-admin/generators/templates/bootstrap3', __dir__)
    Dir["#{templates}/**/*.{tt,js}"].sort.each do |file|
      it "should convert #{file.sub("#{templates}/", '')} once and for all" do
        type = Padrino::Admin::BootstrapUpgrade.type_for(file)
        source = File.read(file)
        result = convert(source, type)
        assert_equal source.lines.size, result.source.lines.size
        assert_equal result.source, convert(result.source, type).source
        refute_match(/(?<![\w-])(btn-default|btn-small|pull-(left|right)|table-condensed|popover-(title|content)|data-toggle)(?![\w-])/, result.source)
      end
    end
  end

  describe 'shipped Bootstrap 5 admin templates' do
    templates = File.expand_path('../lib/padrino-admin/generators/templates', __dir__)
    Dir["#{templates}/{erb,haml,slim}/**/*.tt", "#{templates}/assets/javascripts/application.js"].sort.each do |file|
      it "should leave #{file.sub("#{templates}/", '')} as it is" do
        source = File.read(file)
        result = convert(source, Padrino::Admin::BootstrapUpgrade.type_for(file))
        assert_equal source, result.source
        assert_empty result.notes
      end
    end
  end
end
