import 'dotenv/config';
import { createDatabase } from '../src/database/client';
import { PasswordService } from '../src/modules/auth/password.service';
import { RoleName } from '../src/generated/prisma/client';

export function getOwnerEmailForRestaurant(restaurantId: string): string {
  if (restaurantId === 'deccan-handi-gachi') return 'restaurant@demo.test';
  if (restaurantId === 'chaat-mandi-kondapur') return 'chaat.owner@demo.test';
  return `${restaurantId}.owner@demo.test`;
}

async function main() {
  if (process.env.NODE_ENV !== 'development' || process.env.DEMO_AUTH_ENABLED !== 'true') {
    throw new Error('Development demo owner provisioning only');
  }

  const url = process.env.DATABASE_URL;
  if (!url || new URL(url).pathname !== '/food_delivery_dev') {
    throw new Error('Expected local development database food_delivery_dev');
  }

  const demoPassword = process.env.DEMO_PASSWORD ?? process.env.DEMO_RESTAURANT_PASSWORD;
  if (!demoPassword || demoPassword.length < 8 || demoPassword.length > 128) {
    throw new Error('Configure demo passwords privately in local .env');
  }

  const db = createDatabase(url);
  const passwords = new PasswordService();

  try {
    const passwordHash = await passwords.hash(demoPassword);

    // Ensure all 4 standard roles exist
    const requiredRoles: RoleName[] = ['CUSTOMER', 'RESTAURANT_OWNER', 'DELIVERY_PARTNER', 'ADMIN'];
    for (const role of requiredRoles) {
      await db.role.upsert({
        where: { name: role },
        update: {},
        create: { name: role },
      });
    }

    // 1. Fetch all restaurants
    const restaurants = await db.restaurant.findMany({
      orderBy: { name: 'asc' },
    });

    console.log(`Discovered ${restaurants.length} restaurants in food_delivery_dev.`);

    const demoUsersToRevoke: string[] = [];

    // 2. Provision dedicated owners for each restaurant
    for (const r of restaurants) {
      const email = getOwnerEmailForRestaurant(r.id);
      const displayName = `${r.name} Owner`;

      await db.$transaction(async (tx) => {
        let user = await tx.user.findUnique({ where: { email } });
        if (user) {
          if (!user.isDemo) {
            throw new Error(`Refusing to modify non-demo account: ${email}`);
          }
          await tx.user.update({
            where: { id: user.id },
            data: {
              passwordHash,
              displayName: user.displayName || displayName,
              isDemo: true,
            },
          });
        } else {
          user = await tx.user.create({
            data: {
              email,
              displayName,
              passwordHash,
              isDemo: true,
            },
          });
        }

        demoUsersToRevoke.push(user.id);

        // Ensure RESTAURANT_OWNER role
        await tx.userRole.upsert({
          where: { userId_roleName: { userId: user.id, roleName: 'RESTAURANT_OWNER' } },
          update: {},
          create: { userId: user.id, roleName: 'RESTAURANT_OWNER' },
        });

        // Ensure user ONLY has membership for THIS restaurant
        await tx.restaurantMembership.deleteMany({
          where: {
            userId: user.id,
            restaurantId: { not: r.id },
          },
        });

        // Ensure no OTHER user is assigned as active owner for this restaurant
        await tx.restaurantMembership.deleteMany({
          where: {
            restaurantId: r.id,
            userId: { not: user.id },
          },
        });

        // Upsert dedicated active OWNER membership
        await tx.restaurantMembership.upsert({
          where: {
            userId_restaurantId: {
              userId: user.id,
              restaurantId: r.id,
            },
          },
          update: {
            membershipRole: 'OWNER',
            status: 'ACTIVE',
          },
          create: {
            userId: user.id,
            restaurantId: r.id,
            membershipRole: 'OWNER',
            status: 'ACTIVE',
          },
        });
      });
    }

    // 3. Update standard Customer, Rider, Admin demo accounts
    const standardDemoAccounts: { email: string; role: RoleName; displayName: string }[] = [
      { email: 'customer@demo.test', role: 'CUSTOMER', displayName: 'Demo Customer' },
      { email: 'rider@demo.test', role: 'DELIVERY_PARTNER', displayName: 'Demo Delivery Partner' },
      { email: 'admin@demo.test', role: 'ADMIN', displayName: 'Demo Administrator' },
    ];

    for (const acc of standardDemoAccounts) {
      await db.$transaction(async (tx) => {
        let user = await tx.user.findUnique({ where: { email: acc.email } });
        if (user) {
          if (!user.isDemo) {
            throw new Error(`Refusing to modify non-demo account: ${acc.email}`);
          }
          await tx.user.update({
            where: { id: user.id },
            data: {
              passwordHash,
              isDemo: true,
            },
          });
        } else {
          user = await tx.user.create({
            data: {
              email: acc.email,
              displayName: acc.displayName,
              passwordHash,
              isDemo: true,
            },
          });
        }

        demoUsersToRevoke.push(user.id);

        await tx.userRole.upsert({
          where: { userId_roleName: { userId: user.id, roleName: acc.role } },
          update: {},
          create: { userId: user.id, roleName: acc.role },
        });
      });
    }

    // 4. Revoke active sessions for all affected demo accounts
    const uniqueUserIds = Array.from(new Set(demoUsersToRevoke));
    const revoked = await db.authSession.updateMany({
      where: {
        userId: { in: uniqueUserIds },
        revokedAt: null,
      },
      data: {
        revokedAt: new Date(),
      },
    });

    console.log(`Revoked ${revoked.count} active sessions across ${uniqueUserIds.length} demo accounts.`);

    // 5. Verification: test password on key accounts
    const testSample = ['tiffin.owner@demo.test', 'restaurant@demo.test', 'chaat.owner@demo.test', 'customer@demo.test', 'rider@demo.test'];
    for (const email of testSample) {
      const u = await db.user.findUniqueOrThrow({ where: { email } });
      const valid = await passwords.verify(u.passwordHash, demoPassword);
      if (!valid) throw new Error(`Password verification failed for ${email}`);
    }

    console.log(`Successfully verified Argon2id credentials for sample accounts including The Tiffin Room owner.`);
    console.log(`All ${restaurants.length} restaurants have dedicated, single-membership active owners.`);
  } finally {
    await db.$disconnect();
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error('Provisioning failed:', err);
    process.exitCode = 1;
  });
}
