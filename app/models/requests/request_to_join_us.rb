#
# Otherwise known as a group membership invitation
#
# recipient: person who may be added to group
# requestable: the group
# created_by: person who sent the invite
#
class RequestToJoinUs < Request

  validates_format_of :requestable_type, :with => /Group/
  validates_format_of :recipient_type, :with => /User/

  def validate_on_create
    if Membership.find_by_user_id_and_group_id(recipient_id, requestable_id)
      errors.add_to_base(I18n.t(:membership_exists_error, :member => recipient.name))
    end
    if RequestToJoinUs.having_state(state).find_by_recipient_id_and_requestable_id_and_state(recipient_id, requestable_id, state)
      errors.add_to_base(I18n.t(:request_exists_error, :recipient => recipient.name))
    end
  end

  def group() requestable end

  def may_create?(user)
    user.may?(:admin,group)
  end

  def may_approve?(user)
    user == recipient
  end

  def may_destroy?(user)
    user.may?(:admin, group)
  end

  def may_view?(user)
    may_create?(user) or may_approve?(user)
  end

  def after_approval
    group.add_user! recipient
  end

  def description
    I18n.t(:request_to_join_us_description, :user => user_span(recipient), :group => group_span(group))
  end

  def short_description
    I18n.t(:request_to_join_us_short, :user => user_span(recipient), :group => group_span(group))
  end

end

