module Groups::MembersPermission

  protected

  def may_list_group_members?
    current_user.may? :see_members, @group
  end

  def may_destroy_group_members?(membership = @membership)
    group = membership.group
    user = membership.user

    group.council != group and
    current_user.may?(:admin, group) and
    user != current_user and
    !user.may?(:admin, group)
  end

  def may_edit_group_members?(group=@group)
    current_user.may? :admin, group
  end

end
