#
# An outside user requests to join a group they are not part of.
#
# recipient: the group
# requestable: not used
# created_by: person who wants in
#
class RequestToJoinYou < Request

  validates_format_of :recipient_type, :with => /Group/

  def validate_on_create
    if Membership.find_by_user_id_and_group_id(created_by_id, recipient_id)
      errors.add_to_base(I18n.t(:you_are_a_member_already_error))
    end
    if RequestToJoinYou.having_state(state).find_by_created_by_id_and_recipient_id_and_state(created_by_id, recipient_id, state)
      errors.add_to_base(I18n.t(:request_exists_error, :recipient => recipient.name))
    end
  end

  def requestable_required?() false end

  def group() recipient end

  def may_create?(user)
    created_by == user
  end

  def may_approve?(user)
    user.may?(:admin,group)
  end

  def may_destroy?(user)
    user.may?(:admin, group) or user == created_by
  end

  def may_view?(user)
    may_create?(user) or may_approve?(user)
  end

  def after_approval
    group.add_user! created_by
  end

  def description
    I18n.t(:request_to_join_you_description,
      :user => user_span(created_by), :group => group_span(group))
  end

  def short_description
    I18n.t(:request_to_join_you_short,
      :user => user_span(created_by), :group => group_span(group))
  end

end

