#
# All the controllers that have sidebar and popup controls inherit from
# this controller.
#
class Pages::SidebarsController < Pages::BaseController

  layout nil

  def show
    render :template => 'pages/sidebar/reset'
  end

  protected

  def close_popup
    render :template => 'pages/sidebar/reset'
  end
  
end
