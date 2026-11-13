import 'dotenv/config';
import assert from 'node:assert/strict';
import {createDatabase} from '../src/database/client';
const db=createDatabase(process.env.DATABASE_URL!);
async function main(){
  const counts={restaurants:await db.restaurant.count(),menuItems:await db.menuItem.count(),localities:await db.locality.count(),categories:await db.category.count(),cuisines:await db.cuisine.count(),variants:await db.menuItemVariant.count(),addOns:await db.addOn.count()};
  assert.deepEqual(counts,{restaurants:28,menuItems:224,localities:10,categories:16,cuisines:25,variants:89,addOns:10});
  const users=await db.user.findMany({where:{isDemo:true},select:{email:true,passwordHash:true,status:true,roles:{select:{roleName:true}},memberships:{select:{restaurantId:true,membershipRole:true,status:true}}},orderBy:{email:'asc'}});
  assert.equal(users.length,4);assert.ok(users.every(u=>u.passwordHash.startsWith('$argon2id$')));
  const owner=users.find(u=>u.email==='restaurant@demo.test')!;
  assert.deepEqual(owner.memberships,[{restaurantId:'deccan-handi-gachi',membershipRole:'OWNER',status:'ACTIVE'}]);
  console.log(JSON.stringify({counts,users:users.map(({passwordHash,...safe})=>safe)},null,2));
}
main().catch(()=>{console.error('Authentication verification failed; inspect counts and configuration without resetting data.');process.exitCode=1;}).finally(()=>db.$disconnect());
