class CanvasUserProfileProxy < CanvasProxy

  def user_profile
    request("users/sis_login_id:#{@uid}/profile", "_user_profile")
  end

end
