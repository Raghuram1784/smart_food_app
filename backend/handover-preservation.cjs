require('dotenv').config({quiet:true});
const {Client}=require('pg'),{createHash}=require('node:crypto'),{writeFileSync,readFileSync}=require('node:fs');
(async()=>{const c=new Client({connectionString:process.env.DATABASE_URL});await c.connect();try{
if((await c.query('select current_database() as name')).rows[0].name!=='food_delivery_dev')throw Error('Unexpected database');
const result={};for(const table of ['Order','OrderItem','OrderItemAddOn','OrderEvent','DeliveryAssignment','PaymentAttempt','Restaurant','MenuItem','Locality']){
const rows=(await c.query('SELECT * FROM "'+table+'" ORDER BY id')).rows;result[table]={count:rows.length,sha256:createHash('sha256').update(JSON.stringify(rows)).digest('hex')};}
const path='../build/handover-before.json';if(process.argv[2]==='before')writeFileSync(path,JSON.stringify(result));else if(JSON.stringify(result)!==readFileSync(path,'utf8'))throw Error('Historical data changed');
console.log(JSON.stringify({mode:process.argv[2],counts:Object.fromEntries(Object.entries(result).map(([k,v])=>[k,v.count])),preserved:process.argv[2]!=='before'}));
}finally{await c.end();}})().catch(()=>{console.error('Preservation verification failed');process.exitCode=1;});
