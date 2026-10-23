/// Why an automatic TikTok screen returned to the app's Home screen.
enum TikTokFlowResult {
  /// Signed up and retained the account session for future nurture.
  signupCompleted,

  /// Nurtured and kept the account signed in.
  nurtureCompleted,

  /// An automatic run could not finish this configuration.
  failed,
}
