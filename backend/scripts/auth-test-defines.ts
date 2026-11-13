import 'dotenv/config';
import {mkdirSync,writeFileSync} from 'node:fs';
import {demoAccounts} from '../prisma/seed_auth';
if(process.env.NODE_ENV!=='development'||process.env.DEMO_AUTH_ENABLED!=='true')throw new Error('Development only');
const values:Record<string,string>={API_BASE_URL:process.env.ANDROID_TEST_API_URL??'http://10.0.2.2:5001/api/v1/'};
for(const account of demoAccounts){const value=process.env[account.env];if(!value)throw new Error('Missing private demo credential');values[account.env]=value;}
mkdirSync('../build',{recursive:true});writeFileSync('../build/auth-test-defines.json',JSON.stringify(values),{mode:0o600});
console.log('Private Android test configuration written under ignored build/. Never distribute the integration-test APK.');
