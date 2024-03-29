=begin
    create_table "requests", :force => true do |t|
      t.integer  "created_by_id"
      t.integer  "approved_by_id"

      t.integer  "recipient_id"
      t.string   "recipient_type", :limit => 5

      t.string   "email"
      t.string   "code", :limit => 8

      t.integer  "requestable_id"
      t.string   "requestable_type", :limit => 10

      t.integer  "shared_discussion_id"
      t.integer  "private_discussion_id"

      t.string   "state", :limit => 10
      t.string   "type"
      t.datetime "created_at"
      t.datetime "updated_at"

      t.integer  "site_id"
    end
=end

#
# Anytime an action needs approval, a Request is made.
# This includes invitations, requests to join, RSVP, etc.
#
class Request < ActiveRecord::Base

  ##
  ## ASSOCIATIONS
  ##

  belongs_to :created_by, :class_name => 'User'
  belongs_to :approved_by, :class_name => 'User'

  belongs_to :recipient, :polymorphic => true
  belongs_to :requestable, :polymorphic => true

  belongs_to :shared_discussion, :class_name => 'Discussion', :dependent => :destroy
  belongs_to :private_discussion, :class_name => 'Discussion', :dependent => :destroy

  # most requests are non-vote based. they just need a single 'approve' action
  # to get approved
  # some requests (ex: RequestToDestroyOurGroup) are approved only
  # when they get sufficient votes for approval and (in some cases)
  # when a period of time has passed
  # 'ignore' is another vote that could be use by otherwise non-votable requests
  # so that each person has a distinct 'ignore'/'non-ignore' state
  has_many :votes, :as => :votable, :class_name => "RequestVote", :dependent => :delete_all

  validates_presence_of :created_by_id
  validates_presence_of :recipient_id,   :if => :recipient_required?
  validates_presence_of :requestable_id, :if => :requestable_required?

  ##
  ## FINDERS
  ##

  named_scope :having_state, lambda { |state|
    {:conditions => [ "requests.state = ?", state.to_s]}
  }

  # i think this is a nice idea, but... i am not sure about the UI for this. by making the view dependent
  # on the user, you make it hard to find requests that are still pending but have been approved by you
  # and not others. I think it is better to show these requests as pending, but indicate in the view
  # that you have already voted on this. so, i am commented out this complicated bit of code:

  ## same as having_state, but take into account
  ## that user can vote reject/approve on some requests without changing the state
  #named_scope :having_state_for_user, lambda { |state, user|
  #  votes_conditions = if state == :pending
  #    "votes.value IS NULL AND requests.state = 'pending'"
  #  else
  #    ["votes.value = ? OR requests.state = ?", vote_value_for_state(state), state.to_s]
  #  end
  #  { :conditions => votes_conditions,
  #    :select => "requests.*",
  #    :joins => "LEFT OUTER JOIN votes ON `votes`.votable_id = `requests`.id AND `votes`.votable_type = 'Request'AND `votes`.`type` = 'RequestVote' AND votes.user_id = #{user.id}"}
  #}

  named_scope :pending, :conditions => "state = 'pending'"
  named_scope :by_created_at, :order => 'created_at DESC'
  named_scope :by_updated_at, :order => 'updated_at DESC'
  named_scope :created_by, lambda { |user|
    {:conditions => {:created_by_id => user.id}}
  }
  named_scope :to_user, lambda { |user|
    # you only get to approve group requests for groups that you are an admin for
    {:conditions => ["(recipient_id = ? AND recipient_type = 'User') OR (recipient_id IN (?) AND recipient_type = 'Group')", user.id, user.admin_for_group_ids]}
  }

  named_scope :to_or_created_by_user, lambda { |user|
    # you only get to approve group requests for groups that you are an admin for
    {:conditions => [
      "(recipient_id = ? AND recipient_type = 'User') OR (recipient_id IN (?) AND recipient_type = 'Group') OR (created_by_id = ?)",
      user.id, user.admin_for_group_ids, user.id]}
  }

  named_scope :to_group, lambda { |group|
    {:conditions => ['recipient_id = ? AND recipient_type = ?', group.id, 'Group']}
  }
  named_scope :from_group, lambda { |group|
    {:conditions => ['requestable_id = ? and requestable_type = ?', group.id, 'Group']}
  }

  named_scope :regarding_group, lambda { |group|
    {:conditions => ['(recipient_id = ? AND recipient_type = ?) OR (requestable_id = ? AND requestable_type = ?)', group.id, 'Group', group.id, 'Group']}
  }

  named_scope :for_recipient, lambda { |recipient|
    {:conditions => {:recipient_id => recipient.id}}
  }
  named_scope :with_requestable, lambda { |requestable|
    {:conditions => {:requestable_id => requestable.id}}
  }

  # maybe we should add an "invite?" column?
  named_scope :invites, :conditions => {:type => ['RequestToJoinOurNetwork','RequestToJoinUs','RequestToJoinViaEmail', 'RequestToJoinYou', 'RequestToJoinYourNetwork']}

  ##
  ## VALIDATIONS
  ##

  before_validation_on_create :set_default_state
  def set_default_state
    self.state = "pending" # needed despite FSM so that validations on create will work.
  end

  def validate
    unless may_create?(created_by)
      errors.add_to_base(I18n.t(:permission_denied))
    end
  end

  ##
  ## ATTRIBUTES
  ##

  def name
    self.class.name.underscore
  end

  #
  # Allows Request.create(..., :message => 'hi')
  #
  def message=(msg)
    @initial_post = msg   # see build_discussion
  end

  before_save :build_discussion
  def build_discussion
    if @initial_post.any?
      self.build_shared_discussion(:post => {:body => @initial_post, :user => created_by})
    end
  end

  ##
  ## ACTIONS
  ##

  #
  # change the state of the request, testing to see if the user is allowed to.
  #
  def set_state!(newstate, user=nil)
    if new_record?
      raise Exception.new('record must be saved first')
    end

    command = case newstate
      when 'approved' then 'approve!'
      when 'rejected' then 'reject!'
      else raise Exception.new('state must be approved or rejected')
    end

    self.approved_by = user  # optional
    self.send(command)       # FSM call, eg approve!()

    unless self.state == newstate
      raise PermissionDenied.new(I18n.t(:not_allowed_to_respond_to_request, :user => user.name, :command => command))
    end

    save!
  end

  #
  # an easy method to record a user's response to this request.
  # one of :approve, :reject, :destroy
  # (todo: add support for :ignore)
  #
  def mark!(as, user)
    case as
    when :approve
      approve_by!(user)
    when :reject
      reject_by!(user)
    when :destroy
      destroy_by!(user)
    end
  end

  def approve_by!(user)
    set_state!('approved',user)
  end

  def reject_by!(user)
    set_state!('rejected',user)
  end

  def destroy_by!(user)
    if may_destroy?(user)
      destroy
    else
      raise PermissionDenied.new(I18n.t(:not_allowed_to_respond_to_request, :user => user.name, :command => 'destroy'))
    end
  end

  # triggered by FSM
  def approval_allowed()
    may_approve?(approved_by)
  end

  ##
  ## TO OVERRIDE
  ##

  def description() end
  def short_description() end
  def votable?() false end

  def may_create?(user)  false end
  def may_destroy?(user) false end
  def may_approve?(user) false end
  def may_view?(user)    false end

  def after_approval() end

  def recipient_required?()   true end
  def requestable_required?() true end

  ##
  ## finite state machine
  ##
  ## There’s a time when the operation of the machine becomes so odious, makes
  ## you so sick at heart, that you can't take part, you can’t even passively
  ## take part, and you’ve got to put your bodies upon the gears and upon the
  ## wheels, upon the levers, upon all the apparatus, and you’ve got to make it
  ## stop! And you’ve got to indicate to the people who run it, to the people
  ## who own it, that unless you’re free, the machine will be prevented from
  ## working at all! --Mario Savio
  ##

  acts_as_state_machine :initial => :pending
  state :pending
  state :approved, :after => :after_approval
  state :rejected

  event :approve do
    transitions :from => :pending,  :to => :approved, :guard => :approval_allowed
    transitions :from => :rejected, :to => :approved, :guard => :approval_allowed
  end
  event :reject do
    transitions :from => :pending,  :to => :rejected, :guard => :approval_allowed
  end

  ##
  ## MISC
  ##

  # used by subclass's description()
  # if you change this to display_name, make sure to escape it!
  def user_span(user)
    '<span class="user">%s</span>' % user.name
  end
  def group_span(group)
    '<span class="group">%s</span>' % group.name
  end

  # destroy all requests relating to this user
  def self.destroy_for_user(user)
    destroy_all ['created_by_id = ?', user.id]
    destroy_all ["recipient_id = ? AND recipient_type = 'User'", user.id]
  end

  # destroy all requests relating to this group
  # except the request to destroy the group
  def self.destroy_for_group(group)
    destroy_all ["recipient_id = ? AND recipient_type = 'Group' AND type != 'RequestToDestroyOurGroup'", group.id]
    destroy_all ["requestable_id = ? AND requestable_type = 'Group' AND type != 'RequestToDestroyOurGroup'", group.id]
  end


  protected

  def self.vote_value_for_action(vote_state)
    case vote_state.to_s
      when 'reject' then 0;
      when 'approve' then 1;
      when 'ignore' then 2;
    end
  end

  def add_vote!(response, user)
    value = self.class.vote_value_for_action(response)
    votes.by_user(user).delete_all
    votes.create!(:value => value, :user => user)
  end

end

