#
#
# Everything to do with user <> user relationships should be here.
#
# "relationships" is the join table:
#    user has many users through relationships
#
module UserExtension::Users

  def self.included(base)

    base.send :include, InstanceMethods

    base.instance_eval do

      add_locks :see_contacts => 4
      add_locks({:request_contact => 5}, :without => :friends)
      # disabled for now: , :comment => 6

      serialize_as IntArray, :friend_id_cache, :foe_id_cache

      initialized_by :update_contacts_cache,
        :friend_id_cache, :foe_id_cache

      after_create :add_social_permissions

      ##
      ## PEERS
      ##

      # (peer_id_cache defined in UserExtension::Organize)
      has_many :peers, :class_name => 'User',
        :finder_sql => 'SELECT users.* FROM users WHERE users.id IN (#{peer_id_cache.to_sql})' do
        # will_paginate bug: Association with finder_sql raises TypeError
        #  http://sod.lighthouseapp.com/projects/17958/tickets/120-paginate-association-with-finder_sql-raises-typeerror#ticket-120-5
        def find(*args)
          options = args.extract_options!
          sql = @finder_sql

          sql += " ORDER BY " + sanitize_sql(options[:order]) if options[:order]
          sql += sanitize_sql [" LIMIT ?", options[:limit]] if options[:limit]
          sql += sanitize_sql [" OFFSET ?", options[:offset]] if options[:offset]

          User.find_by_sql(sql)
        end

        # keyring_codes used by acts_as_locked
        def keyring_code
          "%04d" % "9#{proxy_owner.id}"
        end

        def display_name
          "Peers of #{proxy_owner.name}"
        end

        def to_sym
          :peers
        end
      end

      # same as results as user.peers, but chainable with other named scopes
      named_scope(:peers_of, lambda do |user|
        {:conditions => ['users.id in (?)', user.peer_id_cache]}
      end)

      ##
      ## USER'S STATUS / PUBLIC WALL
      ##

      has_one :wall_discussion, :as => :commentable, :dependent => :destroy, :class_name => "Discussion"

      before_destroy :save_relationships
      attr_reader :peers_before_destroy, :contacts_before_destroy

      ##
      ## RELATIONSHIPS
      ##

      has_many :relationships, :dependent => :destroy do
        def with(user) find_by_contact_id(user.id) end
      end

      has_many :discussions, :through => :relationships, :order => 'discussions.replied_at DESC'
      has_many :contacts,    :through => :relationships

      has_many :friends, :through => :relationships, :conditions => "relationships.type = 'Friendship'", :source => :contact do
        def most_active(options = {})
          options[:limit] ||= 13
          max_visit_count = find(:first, :select => 'MAX(relationships.total_visits) as id').id || 1
          select = "users.*, " + quote_sql([MOST_ACTIVE_SELECT, 2.week.ago.to_i, 2.week.seconds.to_i, max_visit_count])
          find(:all, :limit => options[:limit], :select => select, :order => 'last_visit_weight + total_visits_weight DESC')
        end

        # keyring_codes used by acts_as_locked
        def keyring_code
          "%04d" % "7#{proxy_owner.id}"
        end

        def display_name
          "Friends of #{proxy_owner.display_name}"
        end

        def to_sym
          :friends
        end
      end

      # same result as user.friends, but chainable with other named scopes
      named_scope(:friends_of, lambda do |user|
        {:conditions => ['users.id in (?)', user.friend_id_cache]}
      end)

      named_scope(:friends_or_peers_of, lambda do |user|
        {:conditions => ['users.id in (?)', user.friend_id_cache + user.peer_id_cache]}
      end)

      # neither friends nor peers
      # used for autocomplete when we preloaded the friends and peers
      named_scope(:strangers_to, lambda do |user|
        {:conditions => ['users.id NOT IN (?)',
          user.friend_id_cache + user.peer_id_cache + [user.id]]}
      end)

      ##
      ## CACHE
      ##

      serialize_as IntArray, :friend_id_cache, :foe_id_cache, :peer_id_cache
      initialized_by :update_contacts_cache, :friend_id_cache, :foe_id_cache
      initialized_by :update_membership_cache, :peer_id_cache

      # this seems to be the only way to override the A/R created methods.
      # new accessor defined in user_extension/cache.rb
      remove_method :friend_ids
      #remove_method :foe_ids
      remove_method :peer_ids
    end
  end

  module InstanceMethods

    def add_social_permissions
      self.grant! self.friends, [:view, :pester]
      self.grant! self.peers, [:view, :pester]
      self.grant! :public, []
    end

    ##
    ## STATUS / PUBLIC WALL
    ##

    # returns the users current status by returning their latest status_posts.body
    def current_status
      @current_status ||= self.wall_discussion.posts.find(:first, :conditions => {'type' => 'StatusPost'}, :order => 'created_at DESC').body rescue ""
    end

    ##
    ## RELATIONSHIPS
    ##

    # Creates a relationship between self and other_user. This should be the ONLY
    # way that contacts are created.
    #
    # If type is :friend or "Friendship", then the relationship from self to other
    # user will be one of friendship.
    #
    # This method can be used to either add a new relationship or to update an
    # an existing one
    #
    # RelationshipObserver creates a new Discussion that is shared between the two relationship objects
    #
    # RelationshipObserver creates a new FriendActivity when a friendship is created.
    # As a side effect, this will create a profile for 'self' if it does not
    # already exist.
    def add_contact!(other_user, type=nil)
      type = 'Friendship' if type == :friend

      unless relationship = other_user.relationships.with(self)
        relationship = Relationship.new(:user => other_user, :contact => self)
      end
      relationship.type = type
      relationship.save!

      unless relationship = self.relationships.with(other_user)
        relationship = Relationship.new(:user => self, :contact => other_user)
      end
      relationship.type = type
      relationship.save!

      self.relationships.reset
      self.contacts.reset
      self.friends.reset
      self.update_contacts_cache

      other_user.relationships.reset
      other_user.contacts.reset
      other_user.friends.reset
      other_user.update_contacts_cache

      return relationship
    end

    # this should be the ONLY way contacts are deleted
    def remove_contact!(other_user)
      if self.relationships.with(other_user)
        self.contacts.delete(other_user)
        self.update_contacts_cache
      end
      if other_user.relationships.with(self)
         other_user.contacts.delete(self)
         other_user.update_contacts_cache
      end
    end

    # ensure a relationship between this and the other user exists
    # add a new post to the private discussion shared between this and the other_user.
    #
    # +in_reply_to+ is an optional argument for the post that this new post
    # is replying to.
    #
    # currently, this is not stored, but used to generate a more informative
    # notification on the user's wall.
    #
    def send_message_to!(other_user, body, in_reply_to = nil)
      relationship = self.relationships.with(other_user) || self.add_contact!(other_user)
      discussion = relationship.get_or_create_discussion

      if in_reply_to
        if in_reply_to.user_id == self.id
          # you cannot reply to oneself
          in_reply_to = nil
        elsif in_reply_to.user_id != other_user.id
          # we should never get here normally, this is just a sanity check
          raise ErrorMessage.new("Ugh. The user and the post you are replying to don't match.")
        end
      end

      discussion.increment_unread_for!(other_user)
      post = discussion.posts.create do |post|
        post.body = body
        post.user = self
        post.in_reply_to = in_reply_to
        post.type = "PrivatePost"
        post.recipient = other_user
      end
      post
    end


    def stranger_to?(user)
      !peer_of?(user) and !contact_of?(user)
    end

    def peer_of?(user)
      id = user.instance_of?(Integer) ? user : user.id
      peer_id_cache.include?(id)
    end

    def friend_of?(user)
      id = user.instance_of?(Integer) ? user : user.id
      friend_id_cache.include?(id)
    end
    alias :contact_of? :friend_of?

    def relationship_to(user)
      relationships_to(user).first
    end

    def relationships_to(user)
      return :stranger unless user

      @relationships_to_user_cache ||= {}
      @relationships_to_user_cache[user.login] ||= get_relationships_to(user)
      @relationships_to_user_cache[user.login].dup
    end

    def get_relationships_to(user)
      ret = []
      ret << :friend   if friend_of?(user)
      ret << :peer     if peer_of?(user)
  #   ret << :fof      if fof_of?(user)
      ret << :stranger
      ret
    end

    ##
    ## PERMISSIONS
    ##

    def may_be_pestered_by?(user)
      begin
        may_be_pestered_by!(user)
      rescue PermissionDenied
        false
      end
    end

    def may_be_pestered_by!(user)
      if has_access? :pester, user
        return true
      else
        raise PermissionDenied.new(I18n.t(:share_pester_error, :name => self.name))
      end
    end

    def may_pester?(entity)
      entity.may_be_pestered_by? self
    end
    def may_pester!(entity)
      entity.may_be_pestered_by! self
    end

    def may_show_status_to?(user)
      return true if user==self
      return true if friend_of?(user) or peer_of?(user)
      false
    end

  end # InstanceMethods

  private

  MOST_ACTIVE_SELECT = '((UNIX_TIMESTAMP(relationships.visited_at) - ?) / ?) AS last_visit_weight, (relationships.total_visits / ?) as total_visits_weight'

  def save_relationships
    @peers_before_destroy = peers.dup
    @contacts_before_destroy = contacts.dup
  end
end
