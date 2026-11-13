import { RoleName } from '../../generated/prisma/client';
export interface AuthenticatedPrincipal { userId: string; sessionId: string; roles: RoleName[]; expiresAt: Date; }
// Replace this adapter when adding JWT; authorization still consumes this trusted principal.
export abstract class SessionVerifier {
  abstract authenticate(token: string): Promise<AuthenticatedPrincipal>;
}
