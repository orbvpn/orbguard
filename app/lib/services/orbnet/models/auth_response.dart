/// Authentication response returned by the OrbNet auth repository.
///
/// Ported from OrbX and stripped of `equatable`. Carries the access token and
/// the resolved [User]; the refresh token is persisted separately in secure
/// storage by the repository, so it is optional here.
library;

import 'user.dart';

class AuthResponse {
  final String accessToken;
  final String? refreshToken;
  final User user;

  const AuthResponse({
    required this.accessToken,
    this.refreshToken,
    required this.user,
  });

  @override
  String toString() => 'AuthResponse(user: ${user.email})';
}
