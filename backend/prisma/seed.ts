import 'dotenv/config';
import { createDatabase } from '../src/database/client';
import catalog from './catalog.json';
export const slug=(s:string)=>s.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'');
export async function seed(db:ReturnType<typeof createDatabase>){
  await db.$transaction(async tx=>{
    for(const [index,[name,imageKey]] of Object.entries(catalog.categories).entries()){
      const id=slug(name);await tx.category.upsert({where:{id},update:{},create:{id,name,slug:id,imageKey,displayOrder:index}});
    }
    for(const [index,record] of catalog.restaurants.entries()){
      const [id,name,cuisineDescription,description,imageKey,time,rating]=record as [string,string,string,string,string,string,number];
      const [min,max]=time.match(/\d+/g)!.map(Number);
      await tx.restaurant.upsert({where:{id},update:{},create:{id,name,slug:slug(name),description,imageKey,cuisineDescription,rating,estimatedDeliveryMinutes:min,estimatedDeliveryMaxMinutes:max,address:'Illustrative Bengaluru location',displayOrder:index,isDemo:true}});
      const cuisineNames=id==='tiffin'?['Indian','South Indian','North Indian']:[cuisineDescription.split(' · ')[0]];
      for(const cuisineName of cuisineNames){const cuisineId=slug(cuisineName);await tx.cuisine.upsert({where:{id:cuisineId},update:{},create:{id:cuisineId,name:cuisineName,slug:cuisineId}});await tx.restaurantCuisine.upsert({where:{restaurantId_cuisineId:{restaurantId:id,cuisineId}},update:{},create:{restaurantId:id,cuisineId}});}
    }
    for(const [index,record] of catalog.dishes.entries()){
      const [id,restaurantId,name,description,category,imageKey,rupees,section]=record as [string,string,string,string,string,string,number,string];
      const sectionId=`${restaurantId}-${slug(section)}`;
      await tx.menuSection.upsert({where:{id:sectionId},update:{},create:{id:sectionId,restaurantId,name:section,displayOrder:index}});
      await tx.menuItem.upsert({where:{id},update:{},create:{id,restaurantId,name,description,categoryId:slug(category),imageKey,basePricePaise:rupees*100,sectionId,displayOrder:index,isVegetarian:!['pizza','burger'].includes(id)}});
    }
    for(const name of ['Indiranagar','Koramangala','Whitefield']){
      const id=slug(name);await tx.deliveryZone.upsert({where:{id},update:{},create:{id,name:`${name}, Bengaluru`}});
    }
    // No real coverage is known: absence of an eligibility row means ineligible/unknown.
    // No invented variants, add-ons, fees, reviews or inventory quantities are seeded.
  });
}
if(require.main===module){
 const db=createDatabase(process.env.DATABASE_URL!);
 seed(db).then(async()=>{console.log(JSON.stringify({seed:'confirmed',restaurants:await db.restaurant.count(),menuItems:await db.menuItem.count(),categories:await db.category.count()}));}).catch(()=>{console.error('Seed failed; check database access and schema. Existing records were not overwritten.');process.exitCode=1;}).finally(()=>db.$disconnect());
}
