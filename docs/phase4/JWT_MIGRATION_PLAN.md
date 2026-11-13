# Future JWT migration (not implemented)

Keep User, Role, UserRole and RestaurantMembership, CurrentUser, RolesGuard and ownership policy. Add RESTAURANT_STAFF to RoleName when needed; existing many-to-many role mappings and STAFF membership support multiple restaurants without restructuring ownership.

Replace the SessionVerifier binding with a JWT verifier that strictly checks issuer, audience, signature algorithm, expiry and key rotation. Keep the trusted principal contract. Continue database checks for disabled users, changing roles and memberships; never accept client role selection or assume a stale JWT role is sufficient authorization.

Evolve AuthSession or add refresh-session records with hashed refresh tokens, token family, rotation, reuse detection and revocation. Choose and document short access-token lifetimes and immediate logout/disable policy; stateless JWT expiry alone does not provide the current immediate revocation guarantee. Introduce refresh endpoints and test concurrent refresh/replay explicitly.

Keep Flutter AuthRepository, TokenStorage, login/account screens and authProvider interfaces. Change their implementation to persist refresh credentials securely, hold/access short-lived access tokens, serialize refresh requests and retry an eligible request at most once. Distinguish expired access tokens from revoked refresh sessions. No passwords belong in token storage. Update session response parsing and expiry timers to the new lifecycle.

Future addresses and orders reference User.id as customer ownership; restaurant orders reference Restaurant.id and require active memberships; delivery assignments reference the assigned User.id with DELIVERY_PARTNER role. Add these foreign keys and policies with those modules, not before. Admin privileges remain explicit per endpoint.

Before deployment: TLS termination, distributed rate limits, secret management, audit events without credentials, session cleanup/retention, key rotation and adversarial refresh tests. None of these future JWT capabilities are claimed in Phase 4.
