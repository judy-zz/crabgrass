module Common::Ui::LayoutHelper

  protected

  ##
  ## TITLE
  ##

  def html_title
    ([@html_title] + context_titles + [current_site.title]).compact.join(' - ')
  end

  ##
  ## STYLESHEET
  ##

  # as needed stylesheets:
  # rather than include every stylesheet in every request, some stylesheets are
  # only included if they are needed. See Application#stylesheet()

  def optional_stylesheets
    stylesheet = controller.class.stylesheet || {}
    return [stylesheet[:all], @stylesheet, stylesheet[params[:action].to_sym]].flatten.compact.collect{|i| "as_needed/#{i}"}
  end

  # crabgrass_stylesheets()
  # this is the main helper that is in charge of returning all the needed style
  # elements for HTML>HEAD.

  def crabgrass_stylesheets
    lines = []

    lines << stylesheet_link_tag( current_theme.stylesheet_url('screen') )
    lines << stylesheet_link_tag('icon_png')
    lines << optional_stylesheets.collect do |sheet|
       stylesheet_link_tag( current_theme.stylesheet_url(sheet) )
    end
    lines << '<style type="text/css">'
      lines << @content_for_style
    lines << '</style>'
    lines << '<!--[if IE 6]>'
      lines << stylesheet_link_tag('ie6')
      lines << stylesheet_link_tag('icon_gif')
    lines << '<![endif]-->'
    lines << '<!--[if IE 7]>'
      lines << stylesheet_link_tag('ie7')
      lines << stylesheet_link_tag('icon_gif')
    lines << '<![endif]-->'
    if language_direction == "rtl"
      lines << stylesheet_link_tag( current_theme.stylesheet_url('rtl') )
    end
    lines.join("\n")
  end

  def favicon_link
    if current_theme[:favicon_png] and current_theme[:favicon_ico]
    '<link rel="shortcut icon" href="%s" type="image/x-icon" /><link rel="icon" href="%s" type="image/x-icon" />' % [current_theme.url(:favicon_ico), current_theme.url(:favicon_png)]
    elsif current_theme[:favicon]
      '<link rel="icon" href="%s" type="image/x-icon" />' % current_theme.url(:favicon)
    end
  end

  def type_of_column_layout
    @layout_type ||= if @left_column.any? and @right_column.any?
      'three'
    elsif !@left_column.any? and !@right_column.any?
      'one'
    elsif @left_column.any?
      'left'
    elsif @right_column.any?
      'right'
    end
  end

  ##
  ## JAVASCRIPT
  ##

  # Core js that we always need.
  # Currently, effects.js and controls.js are required for autocomplete.js.
  # However, autocomplete uses very little of the controls.js code, which in turn
  # should not need the effects.js at all. So, with a little effort, effects and
  # controls could be moved to extra.
  MAIN_JS = {:main => ['prototype', 'application', 'modalbox', 'effects', 'controls', 'autocomplete']}

  # extra js that we might sometimes need
  EXTRA_JS = {:extra => ['dragdrop', 'builder', 'slider']}

  # needed whenever we want controls for editing a wiki
  WIKI_JS = {:wiki => ['wiki/html_editor', 'wiki/textile_editor', 'wiki/wiki_editing', 'wiki/xinha/XinhaCore']}

  JS_BUNDLES = [MAIN_JS, EXTRA_JS, WIKI_JS]

  JS_BUNDLE_LOAD_ORDER = JS_BUNDLES.collect{|b|b.keys.first}

  # eg: {:main => [...], :extra => [...]}
  JS_BUNDLES_COMBINED = JS_BUNDLES.inject({}){|a,b|a.merge(b)}

  # eg: {'dragdrop' => :extra, 'modalbox' => :main, ...}
  JS_BUNDLE_MAP = Hash[*JS_BUNDLES_COMBINED.collect{|k,v|v.collect{|u|[u,k]}}.flatten]

  # Includes the correct javascript tags for the current request.
  # See ApplicationController#javascript for details.
  #
  # In brief: the correct javascript is loaded for a particular controller and a
  # particular action. Some javascripts are defined in bundles. A bundle gets
  # activated if called by name (ie :extra) or if a file in the bundle is
  # included (ie 'dragdrop')
  def javascript_include_tags
    scripts = controller.class.javascript || {}
    files = [:main, scripts[:all], scripts[params[:action].to_sym]].flatten.compact
    return unless files.any?

    bundles = {}
    as_needed = {}
    includes = []

    files.each do |file|
      if JS_BUNDLE_MAP[file.to_s]                    # if a file in a bundle is specified
        bundles[JS_BUNDLE_MAP[file.to_s]] = true     # include the whole bundle
      elsif JS_BUNDLES_COMBINED[file.to_sym]         # if a bundle symbol is specified
        bundles[file.to_sym] = true                  # include the whole bundle
      else
        as_needed["as_needed/#{file}"] = true        # otherwise, include one file.
      end
    end

    bundles = JS_BUNDLE_LOAD_ORDER & bundles.keys    # sort the bundles
    bundles.each do |bundle|
      args = JS_BUNDLES_COMBINED[bundle] + [{:cache => bundle.to_s}]  # ie ['dragdrop', 'builder', {:cache => 'extra'}]
      includes << javascript_include_tag(*args)
    end
    if as_needed.any?
      includes << javascript_include_tag(*as_needed.keys)
    end
    return includes
  end

  def crabgrass_javascripts
    lines = javascript_include_tags

    # inline script code
    lines << '<script type="text/javascript">'
    #lines << localize_modalbox_strings
    lines << @content_for_script
    lines << 'document.observe("dom:loaded",function(){'
    lines << detect_browser_js
    lines << @content_for_dom_loaded
    lines << '});'
    lines << '</script>'

    # fixes for IE
    #lines << '<!--[if IE]>'
    #lines << '<script src="/javascripts/ie/html5.js"></script>'
    #lines << '<![endif]-->'
    #lines << '<!--[if lt IE 7.]>'
    # # make 24-bit pngs work in ie6
    #  lines << '<script defer type="text/javascript" src="/javascripts/ie/pngfix.js"></script>'
    #  # prevent flicker on background images in ie6
    #  lines << '<script>try {document.execCommand("BackgroundImageCache", false, true);} catch(err) {}</script>'
    #lines << '<![endif]-->'

    # make all IEs behave like IE 9
    lines << '<!--[if lt IE 9]>'
      lines << '<script src="/javascripts/ie/IE9.js"></script>'
    lines << '<![endif]-->'

    # run firebug lite in dev mode for ie
    #if true and RAILS_ENV == 'development'
    #  lines << '<!--[if IE]>'
    #  lines << "<script type='text/javascript' src='http://getfirebug.com/firebug-lite-beta.js'></script>"
    #  lines << '<![endif]-->'
    #end
    
    lines.join("\n")
  end

  ##
  ## BANNER
  ##

  # banner stuff
  #def banner_style
  #  "background: #{@banner_style.background_color}; color: #{@banner_style.color};" if @banner_style
  #end
  #def banner_background
  #  @banner_style.background_color if @banner_style
  #end
  #def banner_foreground
  #  @banner_style.color if @banner_style
  #end

  ##
  ## CONTEXT STYLES
  ##

  #def background_color
  #  "#ccc"
  #end
  #def background
  #  #'url(/images/test/grey-to-light-grey.jpg) repeat-x;'
  #  'url(/images/background/grey.png) repeat-x;'
  #end

  # return all the custom css which might apply just to this one group
#  def context_styles
#    style = []
#     if @banner
#       style << '#banner {%s}' % banner_style
#       style << '#banner a.name_link {color: %s; text-decoration: none;}' %
#                banner_foreground
#       style << '#topmenu li.selected span a {background: %s; color: %s}' %
#                [banner_background, banner_foreground]
#     end
#    style.join("\n")
#  end

  ##
  ## LAYOUT STRUCTURE
  ##

  # builds and populates a table with the specified number of columns
  def column_layout(cols, items, options = {}, &block)
    lines = []
    count = items.size
    rows = (count.to_f / cols).ceil
    if options[:balanced]
      width= (100.to_f/cols.to_f).to_i
    end
    lines << "<table class='#{options[:class]}'>" unless options[:skip_table_tag]
    if options[:header]
      lines << options[:header]
    end
    for r in 1..rows
      lines << ' <tr>'
      for c in 1..cols
         cell = ((r-1)*cols)+(c-1)
         next unless items[cell]
         lines << "  <td valign='top' #{"style='width:#{width}%'" if options[:balanced]}>"
         if block
           lines << yield(items[cell])
         else
           lines << '  %s' % items[cell]
         end
         #lines << "r%s c%s i%s" % [r,c,cell]
         lines << '  </td>'
      end
      lines << ' </tr>'
    end
    lines << '</table>' unless options[:skip_table_tag]
    lines.join("\n")
  end

  ##
  ## PARTIALS
  ##

  def dialog_page(options = {}, &block)
    block_to_partial('common/dialog_page', options, &block)
  end

  ##
  ## MISC. LAYOUT HELPERS
  ##

  #
  # takes an array of objects and splits it into two even halves. If the count
  # is odd, the first half has one more than the second.
  # 
  def even_split(arry)
    cutoff = (arry.count + 1) / 2
    return [arry[0..cutoff-1], arry[cutoff..-1]]
  end

  #
  # acts like haml_tag, capture_haml, or haml_concat, depending on how it is called.
  #
  # two or more args             --> like haml_tag
  # one arg and a block          --> like haml_tag
  # zero args and a block        --> like capture_haml
  # one arg and no block         --> like haml_concat
  # 
  # additionally, we allow the use of more than one class.
  #
  # some examples of these usages:
  #
  #   def display_robot(robot)
  #     haml do                                # like capture_haml
  #       haml '.head', robot.head_html        # like haml_tag
  #       haml '.body.metal', robot.body_html  # like haml_tag, but with multiple classes
  #       haml '<a href="/x">link</a>'         # like haml_concat
  #     end
  #   end
  #
  # wrapping the helper in a capture_haml call is very useful, because then
  # the helper can be used wherever a normal helper would be. 
  #
  def haml(name=nil, *args, &block)
    if name.any?
      if args.empty? and block.nil?
        haml_concat name
      else
        if name =~ /^(.*?\.[^\.]*)(\..*)$/
          # allow chaining of classes if there are multiple '.' in the first arg
          name = $1
          classes = $2.gsub('.',' ')
          hsh = args.detect{|i| i.is_a?(Hash)}
          unless hsh
            hsh = {}
            args << hsh
          end
          hsh[:class] = classes
        end
        haml_tag(name, *args, &block)
      end
    else
      capture_haml(&block)
    end
  end

  #
  # joins an array of elements together using commas.
  #
  def comma_join(*args)
    args.select(&:any?).join(', ')
  end

  #
  # *NEWUI
  #
  # provides a block for main container
  #
  # content_starts_here do
  #   %h1 my page
  #
  #def content_starts_here(&block)
  #  capture_haml do
  #    haml_tag :div, :id =>'main-content' do
  #      haml_concat capture_haml(&block)
  #    end
  #  end
  #end

  ##
  ## CUSTOMIZED STUFF
  ##

  # build a masthead, using a custom image if available
 # def custom_masthead_site_title
 #   appearance = current_site.custom_appearance
 #   if appearance and appearance.masthead_asset
 #     # use an image
 #     content_tag :div, '', :id => 'site_logo_wrapper' do
 #       content_tag :a, :href => '/', :alt => current_site.title do
 #         image_tag(appearance.masthead_asset.url, :id => 'site_logo')
 #       end
 #     end
 #   else
      # no image
 #     content_tag :h2, current_site.title
      # <h2><%= current_site.title %></h2>
 #   end
 # end

 # def masthead_container
 #   locals = {}
#    appearance = current_site.custom_appearance
#    if appearance and appearance.masthead_asset and current_site.custom_appearance.masthead_enabled
#      height = appearance.masthead_asset.height
#      bgcolor = (appearance.masthead_background_parameter == 'white') ? '' : '#'
#      bgcolor = bgcolor+appearance.masthead_background_parameter
#      locals[:section_style] = "height: #{height}px"
#      locals[:style] = "background: url(#{appearance.masthead_asset.url}) no-repeat; height: #{height}px;"
#      locals[:render_title] = false
#    else
 #     locals[:section_style] = ''
 #     locals[:style] = ''
 #     locals[:render_title] = true
#    end
 #   render :partial => 'layouts/base/masthead', :locals => locals
 # end

  ##
  ## declare strings used for logins
  ##
  def login_context
    @login_context ||={
      :strings => {
        :login           => I18n.t(:login),
        :username        => I18n.t(:username),
        :password        => I18n.t(:password),
        :forgot_password => I18n.t(:forgot_password_link),
        :create_account  => I18n.t(:signup_link),
        :redirect        => params[:redirect] || request.request_uri,
        :token           => form_authenticity_token
      }
    }
  end

  #
  # rails 3.0 has "content_for?"
  # i want it too!
  # this takes advantage of deprecated member variables,
  # but that is ok since this method won't be needed under v3.
  #
  def content_for?(block_name)
    instance_variable_get("@content_for_#{block_name}")
  end

  private

  # for susy to work, we need to add class 'webkit' to body when the browser
  # is a webkit browser. I am not sure if this should be done on dom:loaded or
  # before. 
  def detect_browser_js
    # "document.observe('dom:loaded',function(){if(/khtml|webkit/i.test(navigator.userAgent)){$$('body').first().addClassName('webkit');}});"
    "if(/khtml|webkit/i.test(navigator.userAgent)){$$('body').first().addClassName('webkit');}"
  end

end
