import 'dotenv/config';
import { createDatabase } from '../src/database/client';
import { settings } from '../src/config/settings';
import { PasswordService } from '../src/modules/auth/password.service';

/**
 * Development-only script to establish an authorized owner for Chaat Mandi (chaat-mandi-kondapur).
 *
 * Usage:
 *   npx tsx scripts/establish-chaat-owner.ts
 *     -> Creates/verifies dedicated owner account 'chaat.owner@demo.test' with active membership for Chaat Mandi.
 *
 *   npx tsx scripts/establish-chaat-owner.ts --link-demo
 *     -> Additionally links existing 'restaurant@demo.test' to Chaat Mandi for multi-restaurant development testing.
 */
async function main() {
  const db = createDatabase(settings().databaseUrl);
  const passwords = new PasswordService();
  const linkDemo = process.argv.includes('--link-demo');

  try {
    const restaurant = await db.restaurant.findUnique({
      where: { id: 'chaat-mandi-kondapur' },
    });
    if (!restaurant) {
      throw new Error("Restaurant 'chaat-mandi-kondapur' not found in database.");
    }

    console.log(`Found target restaurant: ${restaurant.name} (${restaurant.id})`);

    // Ensure RESTAURANT_OWNER role exists
    await db.role.upsert({
      where: { name: 'RESTAURANT_OWNER' },
      update: {},
      create: { name: 'RESTAURANT_OWNER' },
    });

    const password = process.env.DEMO_RESTAURANT_PASSWORD || 'Owner#Demo123';
    const passwordHash = await passwords.hash(password);

    // 1. Establish dedicated owner account: chaat.owner@demo.test
    const email = 'chaat.owner@demo.test';
    let user = await db.user.findUnique({ where: { email } });
    if (!user) {
      user = await db.user.create({
        data: {
          email,
          displayName: 'Chaat Mandi Kitchen Owner',
          passwordHash,
          isDemo: true,
          roles: { create: { roleName: 'RESTAURANT_OWNER' } },
        },
      });
      console.log(`Created new owner account: ${email} (ID: ${user.id})`);
    } else {
      console.log(`Owner account ${email} already exists (ID: ${user.id})`);
    }

    // Upsert membership for chaat.owner@demo.test
    const membership = await db.restaurantMembership.upsert({
      where: {
        userId_restaurantId: {
          userId: user.id,
          restaurantId: restaurant.id,
        },
      },
      update: { status: 'ACTIVE', membershipRole: 'OWNER' },
      create: {
        restaurantId: restaurant.id,
        userId: user.id,
        membershipRole: 'OWNER',
        status: 'ACTIVE',
      },
    });
    console.log(`Verified active owner membership for ${email} -> ${restaurant.name} (user: ${membership.userId}, restaurant: ${membership.restaurantId})`);

    // 2. Optionally link shared demo owner (restaurant@demo.test) if --link-demo requested
    if (linkDemo) {
      const demoOwner = await db.user.findUnique({
        where: { email: 'restaurant@demo.test' },
      });
      if (demoOwner) {
        await db.restaurantMembership.upsert({
          where: {
            userId_restaurantId: {
              userId: demoOwner.id,
              restaurantId: restaurant.id,
            },
          },
          update: { status: 'ACTIVE', membershipRole: 'OWNER' },
          create: {
            restaurantId: restaurant.id,
            userId: demoOwner.id,
            membershipRole: 'OWNER',
            status: 'ACTIVE',
          },
        });
        console.log(`Linked shared demo owner restaurant@demo.test -> ${restaurant.name} for multi-restaurant testing.`);
      }
    }

    // Inspect pending orders for Chaat Mandi
    const pendingOrders = await db.order.findMany({
      where: { restaurantId: restaurant.id },
      select: { id: true, orderNumber: true, status: true, paymentStatus: true, finalPayablePaise: true },
    });
    console.log(`Chaat Mandi currently has ${pendingOrders.length} orders:`, JSON.stringify(pendingOrders, null, 2));

  } finally {
    await db.$disconnect();
  }
}

main().catch((err) => {
  console.error('Failed to establish Chaat Mandi owner:', err);
  process.exit(1);
});
