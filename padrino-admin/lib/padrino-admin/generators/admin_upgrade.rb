module Padrino
  module Generators
    ##
    # Upgrades an admin app generated for Bootstrap 3 to Bootstrap 5.
    #
    # Every file still as the old generator wrote it is regenerated from the new templates.
    # Edited views are converted in place by Padrino::Admin::BootstrapUpgrade, so no work is
    # lost, and whatever needs a human is listed at the end. Running it twice changes nothing.
    #
    class AdminUpgrade < Thor::Group
      # Add this generator to our padrino-gen.
      Padrino::Generators.add_generator(:admin_upgrade, self)

      # Define the source template root.
      def self.source_root; __dir__; end
      # Defines the "banner" text for the CLI.
      def self.banner; 'padrino-gen admin_upgrade'; end

      # Include related modules.
      include Thor::Actions
      include Padrino::Generators::Actions
      include Padrino::Generators::Admin::Actions

      desc "Description:\n\n\tpadrino-gen admin_upgrade moves an admin app from Bootstrap 3 to Bootstrap 5"

      class_option :root,        type: :string, aliases: '-r', default: '.',       desc: 'The root destination'
      class_option :admin_model, type: :string, aliases: '-m', default: 'Account', desc: 'The name of model for access controlling'
      class_option :admin_name,  type: :string, aliases: '-a', default: 'admin',   desc: 'The admin application name and path'

      # Vendored files of Bootstrap 3, jQuery and Font Awesome 4, which nothing loads anymore.
      LEGACY_ASSETS = %w[javascripts/jquery-1.11.0.min.js javascripts/bootstrap stylesheets/fonts images/font].freeze
      VENDOR_ASSETS = %w[stylesheets/bootstrap.css stylesheets/fontawesome.css javascripts/bootstrap.bundle.min.js].freeze
      OWN_ASSETS    = %w[stylesheets/application.css javascripts/application.js].freeze
      APP_VIEWS     = %w[base/index layouts/application layouts/error sessions/new errors/403 errors/404 errors/500].freeze
      PAGE_VIEWS    = %w[_form edit index new].freeze

      # The old layout's asset includes, which edited layouts still carry.
      INCLUDES = {
        %r{'jquery-1\.11\.0\.min',\s*\(Padrino\.env == :production \? 'bootstrap/bootstrap\.min' : %w\[[^\]]*\]\)} => "'bootstrap.bundle.min'",
        /(stylesheet_link_tag\(?\s*['"]bootstrap['"])(?!\s*,\s*['"]fontawesome)/ => "\\1, 'fontawesome'"
      }.freeze

      def upgrade_admin
        self.destination_root = options[:root]
        return say 'You are not at the root of a Padrino application! (config/boot.rb not found)' unless in_app_root?

        @app_name     = fetch_app_name
        @admin_name   = options[:admin_name].classify
        @admin_path   = options[:admin_name].underscore
        @model_plural = options[:admin_model].underscore.pluralize
        @notes        = Hash.new { |notes, path| notes[path] = [] }
        @done         = []

        upgrade_assets
        upgrade_views
        report
      end

      private

      def upgrade_assets
        assets = "public/#{@admin_path}"
        LEGACY_ASSETS.each { |path| remove_file "#{assets}/#{path}" if File.exist?(destination_root(assets, path)) }
        VENDOR_ASSETS.each { |path| copy_file "templates/assets/#{path}", "#{assets}/#{path}", force: true }
        directory 'templates/assets/webfonts', "#{assets}/webfonts", force: true
        OWN_ASSETS.each do |path|
          next if upgrade_file("templates/assets/#{path}", "#{assets}/#{path}")

          @notes["#{assets}/#{path}"] << "edited, so kept as it is: merge it with the new #{File.expand_path("templates/assets/#{path}", __dir__)}"
        end
      end

      def upgrade_views
        views = "#{@admin_path}/views"
        APP_VIEWS.each { |view| upgrade_file("templates/#{ext}/app/#{view}.#{ext}.tt", "#{views}/#{view}.#{ext}") || convert("#{views}/#{view}.#{ext}") }
        scaffolds.each do |name, model|
          @orm = load_orm(name, model)
          PAGE_VIEWS.each do |view|
            path = "#{views}/#{name}/#{view}.#{ext}"
            next if @orm && upgrade_file("templates/#{ext}/page/#{view}.#{ext}.tt", path)

            convert(path)
            next unless read(path) =~ /list-row-action-delete-one|list-menu-link/

            @notes[path] << 'edited, so converted rather than regenerated, but its row menu and delete popovers ran on jQuery: ' \
                            "regenerate it with 'padrino g admin_page #{model}' and carry your changes over"
          end
        end
        (Dir[destination_root(@admin_path, '{views,helpers}', '**', '*')].map { |file| file.delete_prefix("#{destination_root}/") } - @done).each { |path| convert(path) }
      end

      # Controllers made by admin_page, with their models.
      def scaffolds
        Dir[destination_root(@admin_path, 'controllers', '*.rb')].sort.filter_map do |controller|
          name  = File.basename(controller, '.rb')
          model = File.read(controller)[/@#{name} = ([A-Z][\w:]*)\.all\b/, 1]
          [name, model] if model
        end
      end

      # The page generator's view of +model+, or nil when it can't be loaded.
      def load_orm(name, model)
        page = model == options[:admin_model].classify ? account_orm(model.underscore) : Padrino::Admin::Generators::Orm.new(model.underscore, orm)
        page.columns
        page
      rescue StandardError => e
        @notes["#{@admin_path}/controllers/#{name}.rb"] << "#{model} could not be loaded (#{e.message.lines.first.strip}), so its views were converted rather than regenerated"
        nil
      end

      # Regenerates +path+ from +template+ when it is still what the Bootstrap 3 or 5 template made of it.
      def upgrade_file(template, path)
        return true unless (current = read(path))
        return false unless [render(template), render(template.sub('templates/', 'templates/bootstrap3/'))].include?(current)

        write(path, render(template), :upgrade)
      end

      def convert(path)
        type = Padrino::Admin::BootstrapUpgrade.type_for(path)
        return if !type || @done.include?(path) || !File.file?(destination_root(path))

        result = Padrino::Admin::BootstrapUpgrade.convert(read(path), type)
        @notes[path].concat(result.notes)
        write(path, INCLUDES.reduce(result.source) { |text, (from, to)| text.gsub(from, to) }, :convert)
      end

      def write(path, content, status)
        @done << path
        status = :identical if read(path) == content
        create_file path, content, force: true, verbose: false
        say_status status, path, status == :identical ? :blue : :green
        true
      end

      def read(path)
        File.read(destination_root(path)) if File.exist?(destination_root(path))
      end

      def render(template)
        source = File.read(File.expand_path(template, __dir__))
        template.end_with?('.tt') ? ERB.new(source, trim_mode: '-').result(binding) : source
      end

      def report
        @notes.reject! { |_, notes| notes.empty? }
        say
        return say("The admin is on Bootstrap 5 now, and there's nothing left to check by hand.", :green) if @notes.empty?

        say 'The admin is on Bootstrap 5 now. Check these by hand:', :yellow
        @notes.each do |path, notes|
          say "  #{path}"
          notes.uniq.each { |note| say "    #{note}" }
        end
      end
    end
  end
end
