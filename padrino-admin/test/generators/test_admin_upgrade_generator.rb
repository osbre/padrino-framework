require_relative '../helper'
require_relative '../fixtures/sequel'

describe 'AdminUpgradeGenerator' do
  templates = File.expand_path('../../lib/padrino-admin/generators/templates', __dir__)

  before do
    @apptmp = "#{Dir.tmpdir}/padrino-tests/#{SecureRandom.hex}"
    `mkdir -p #{@apptmp}`
  end

  after do
    `rm -rf #{@apptmp}`
  end

  # Generates an admin with a friends page, as Padrino did before Bootstrap 5 when +bootstrap3+ is set.
  define_method :admin do |dir, renderer, bootstrap3: false|
    root = "#{@apptmp}/#{dir}/sample_project"
    capture_io { generate(:project, 'sample_project', "--root=#{@apptmp}/#{dir}", '-d=sequel', "-e=#{renderer}") }
    if bootstrap3
      FileUtils.mkdir_p("#{root}/generators/templates")
      FileUtils.cp_r(Dir["#{templates}/bootstrap3/*"], "#{root}/generators/templates")
      FileUtils.cp_r("#{templates}/assets/images", "#{root}/generators/templates/assets")
    end
    capture_io { generate(:admin_app, "--root=#{root}") }
    capture_io { generate(:admin_page, 'friend', "--root=#{root}") }
    FileUtils.rm_rf("#{root}/generators")
    if bootstrap3
      %w[javascripts/jquery-1.11.0.min.js javascripts/bootstrap/modal.js stylesheets/bootstrap.css stylesheets/fonts/FontAwesome.otf images/font/FontAwesome.otf].each do |path|
        FileUtils.mkdir_p(File.dirname("#{root}/public/admin/#{path}"))
        File.write("#{root}/public/admin/#{path}", 'Bootstrap 3')
      end
    end
    root
  end

  def upgrade(root)
    capture_io { generate(:admin_upgrade, "--root=#{root}") }.first
  end

  def files(root)
    Dir.glob('{admin/views,public/admin}/**/*', base: root).sort.to_h { |path| [path, File.file?("#{root}/#{path}") && File.binread("#{root}/#{path}")] }
  end

  it 'should fail outside app root' do
    assert_match(/not at the root/, upgrade("#{@apptmp}/sample_project"))
  end

  %w[erb haml slim].each do |renderer|
    it "should turn an untouched #{renderer} admin into exactly what admin_app makes today" do
      old = admin('old', renderer, bootstrap3: true)
      assert_match_in_file 'jquery-1.11.0.min', "#{old}/admin/views/layouts/application.#{renderer}"

      assert_match(/nothing left to check by hand/, upgrade(old))
      assert_equal files(admin('new', renderer)), files(old)
      assert_match(/nothing left to check by hand/, upgrade(old))
    end
  end

  describe 'on an edited admin' do
    before do
      @root = admin('old', 'haml', bootstrap3: true)
      File.write("#{@root}/admin/views/layouts/application.haml", "-# ours\n", mode: 'a')
      File.write("#{@root}/admin/views/friends/index.haml", "-# ours\n", mode: 'a')
      File.write("#{@root}/admin/views/base/_stats.haml", ".pull-right\n  %span.label.label-info 3\n:javascript\n  $('.pull-right').hide();\n")
      File.write("#{@root}/admin/controllers/ghosts.rb", "SampleProject::Admin.controllers :ghosts do\n  get(:index) { @ghosts = Ghost.all }\nend\n")
      FileUtils.mkdir_p("#{@root}/admin/views/ghosts")
      File.write("#{@root}/admin/views/ghosts/index.haml", "%table.table-condensed\n")
      File.write("#{@root}/public/admin/javascripts/application.js", "// ours\n", mode: 'a')
      @out = upgrade(@root)
    end

    it 'should regenerate what is untouched and convert the rest in place' do
      assert_match_in_file 'list-bulk', "#{@root}/admin/views/accounts/index.haml"
      assert_match_in_file '%span.badge.bg-info 3', "#{@root}/admin/views/base/_stats.haml"
      assert_match_in_file '%table.table-sm', "#{@root}/admin/views/ghosts/index.haml"

      layout = File.read("#{@root}/admin/views/layouts/application.haml")
      assert_match(/-# ours/, layout)
      assert_match(/javascript_include_tag 'bootstrap.bundle.min', :application/, layout)
      assert_match(/stylesheet_link_tag 'bootstrap', 'fontawesome', 'application'/, layout)
      assert_match(/navbar-expand-md/, layout)

      assert_match_in_file '// ours', "#{@root}/public/admin/javascripts/application.js"
      assert_no_file_exists "#{@root}/public/admin/javascripts/jquery-1.11.0.min.js"
      assert_file_exists "#{@root}/public/admin/javascripts/bootstrap.bundle.min.js"
    end

    it 'should list what needs a human' do
      notes = @out.split('Check these by hand:').last.scan(/^  (\S+)\n((?:    .*\n)*)/).to_h
      assert_match(/row menu and delete popovers ran on jQuery: regenerate it with 'padrino g admin_page Friend'/, notes['admin/views/friends/index.haml'])
      assert_match(/line 4: jQuery is no longer loaded/, notes['admin/views/base/_stats.haml'])
      assert_match(/Ghost could not be loaded/, notes['admin/controllers/ghosts.rb'])
      assert_match(/edited, so kept as it is/, notes['public/admin/javascripts/application.js'])
      assert_equal ['admin/views/base/_stats.haml', 'admin/views/friends/index.haml', 'admin/views/layouts/application.haml',
                    'admin/controllers/ghosts.rb', 'public/admin/javascripts/application.js'].sort, notes.keys.sort
    end

    it 'should change nothing the second time' do
      before = files(@root)
      out = upgrade(@root)
      assert_equal before, files(@root)
      refute_match(/^\s*(upgrade|convert|remove|force|create)\s/, out)
      assert_equal @out.split('Check these by hand:').last, out.split('Check these by hand:').last
    end
  end

  describe 'the admin page generator' do
    it 'should suggest the upgrade on a Bootstrap 3 admin only' do
      root = admin('old', 'slim', bootstrap3: true)
      out, = capture_io { generate(:admin_page, 'page', "--root=#{root}") }
      assert_match(/still runs Bootstrap 3.*padrino g admin_upgrade/, out)

      upgrade(root)
      out, = capture_io { generate(:admin_page, 'section', "--root=#{root}") }
      refute_match(/Bootstrap 3/, out)
    end
  end
end
