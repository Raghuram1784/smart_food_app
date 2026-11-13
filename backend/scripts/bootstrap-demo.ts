import 'dotenv/config';
import { randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
// Local bootstrap only. No endpoint, no plaintext console output, no production auto-initialization.
if(process.env.NODE_ENV!=='development') throw new Error('Bootstrap is development-only');
const file=require('node:path').resolve(process.cwd(),'.env');
let content=readFileSync(file,'utf8');
for(const key of ['DEMO_CUSTOMER_PASSWORD','DEMO_RESTAURANT_PASSWORD','DEMO_RIDER_PASSWORD','DEMO_ADMIN_PASSWORD']){
  if(!new RegExp(`^${key}=`, 'm').test(content)) content+=`\n${key}="${randomBytes(24).toString('base64url')}"\n`;
}
if(!/^DEMO_AUTH_ENABLED=/m.test(content)) content+='\nDEMO_AUTH_ENABLED=true\n';
writeFileSync(file,content,{mode:0o600});
console.log('Local credentials configured in ignored backend/.env. No existing password was replaced.');
