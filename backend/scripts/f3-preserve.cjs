require('dotenv').config({quiet:true});
const {Client}=require('pg'),{createHash}=require('node:crypto'),{writeFileSync,readFileSync}=require('node:fs');
(async()=>{const c=new Client({connectionString:process.env.DATABASE_URL});await c.connect();try{
 if((await c.query('select current_database() as name')).rows[0].name!=='food_delivery_dev')throw Error('Unexpected database');
 const result={};const omit=['deliveryMode','scheduledDeliveryAt','deliveryWindowStart','deliveryWindowEnd','preparationStartAt','expectedPickupAt','dispatchReleaseAt','actualDeliveryAt','scheduleOpenMinute','scheduleCloseMinute','schedulePrepMinutes','scheduleCapacity','scheduleWeekdays'];
 for(const table of ['Order','OrderItem','OrderEvent','DeliveryAssignment','PaymentAttempt','DeliveryHandover','Restaurant','MenuItem','Locality','GroupOrder','GroupProposal']){
 const rows=(await c.query('SELECT to_jsonb(t) - $1::text[] AS data FROM "'+table+'" t ORDER BY id',[omit])).rows;
 result[table]={count:rows.length,sha256:createHash('sha256').update(JSON.stringify(rows)).digest('hex')};}
 const path='../build/f3-preservation.json';if(process.argv[2]==='before')writeFileSync(path,JSON.stringify(result));else if(JSON.stringify(result)!==readFileSync(path,'utf8'))throw Error('Historical data changed');
 console.log(JSON.stringify({mode:process.argv[2],counts:Object.fromEntries(Object.entries(result).map(([k,v])=>[k,v.count])),unchanged:process.argv[2]!=='before'}));
 }finally{await c.end();}})().catch(()=>{console.error('Preservation check failed');process.exitCode=1;});
