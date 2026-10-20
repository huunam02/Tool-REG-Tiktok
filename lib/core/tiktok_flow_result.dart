/// Why an automatic TikTok screen returned to the app's Home screen.
enum TikTokFlowResult {
  /// Signed up and retained the account session for future nurture.
  signupCompleted,

  /// Signed up, held the screen, then logged out.
  signupLoggedOut,

  /// Nurtured and kept the account signed in.
  nurtureCompleted,

  /// Nurtured, held the screen, then logged out.
  nurtureLoggedOut,

  /// An automatic run could not finish this configuration.
  failed,
}
