
module Common::Application::BeforeFilters

  def self.included(base)
    base.class_eval do
      # the order of these filters matters. change with caution.
      before_filter :essential_initialization
      before_filter :set_session_locale
      before_filter :set_session_timezone
      before_filter :header_hack_for_ie6
      before_filter :redirect_unverified_user
      before_filter :enforce_ssl_if_needed
      before_filter :setup_theme
    end
  end

  protected

  # ensure that essential_initialization ALWAYS comes first
  def self.prepend_before_filter(*filters, &block)
    filter_chain.skip_filter_in_chain(:essential_initialization, &:before?)
    filter_chain.prepend_filter_to_chain(filters, :before, &block)
    filter_chain.prepend_filter_to_chain([:essential_initialization], :before, &block)
  end

  private

  def enforce_ssl_if_needed
    request.session_options[:secure] = current_site.enforce_ssl
  end

  def essential_initialization
    # current_site
  end

  def header_hack_for_ie6
    #
    # the default http header cache-control in rails is:
    #    Cache-Control: "private, max-age=0, must-revalidate"
    # on some versions of ie6, this break the back button.
    # so, for ie6, we set it to:
    #    Cache-Control: "max-age=Sun Aug 10 15:18:40 -0700 2008, private"
    # (where the date specified is right now)
    #
    expires_in Time.now if request.user_agent =~ /MSIE 6\.0/
  end

  def redirect_unverified_user
    if logged_in? and current_user.unverified?
      redirect_to account_url(:action => 'unverified')
    end
  end

  # if we have login_required this will be called and check the
  # permissions accordingly
  def authorized?
    check_permissions!
  end

  # 
  # sets the current locale
  #
  def set_session_locale
    if !language_allowed?(session[:language_code])
      session[:language_code] = nil
    end
    session[:language_code] ||= discover_language_code
    I18n.locale = session[:language_code].to_sym
  end

  #
  # set the current timezone, if the user has it configured.
  #
  def set_session_timezone
    Time.zone = current_user.time_zone if logged_in?
  end

  #
  # the theme needs a pointer to the controller for this request.
  # I am not sure if this will cause problems with multi-threaded servers.
  #
  def setup_theme
    current_theme.controller = self
  end

  private

  #
  # we only allow the session to set a language that has been
  # enabled in the crabgrass configuration.
  #
  def language_allowed?(lang_code)
    Conf.enabled_languages_hash[lang_code]
  end

  #
  # order of precedence in choosing a language:
  # (1) the current session
  # (2) the current_user's settings
  # (3) the request's Accept-Language header
  # (4) the site default
  # (5) english
  #
  def discover_language_code
    if I18n.available_locales.empty?
      'en'
    elsif !logged_in? || current_user.language.empty?
      if Conf.enabled_languages.any?
         code = request.compatible_language_from(Conf.enabled_languages)
      else
         code = request.user_preferred_languages.first
      end
      code ||= current_site.default_language
      code ||= 'en'
      code.to_s.sub('-', '_').sub(/_\w\w/, '')
    elsif language_allowed?(current_user.language)
      current_user.language
    else
      'en'
    end
  end

end

