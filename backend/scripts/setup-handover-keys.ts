import 'dotenv/config';
import {appendFileSync,readFileSync} from 'node:fs';
import {randomBytes} from 'node:crypto';
if(process.env.NODE_ENV!=='development')throw new Error('Local development setup only');
const file='.env',text=readFileSync(file,'utf8');
for(const name of ['HANDOVER_HMAC_KEY','HANDOVER_ENCRYPTION_KEY']){
  // Never overwrite an existing key, including a malformed/empty setting needing deliberate repair.
  if(new RegExp(`^${name}=`, 'm').test(text))continue;
  appendFileSync(file,`\n${name}=${randomBytes(32).toString('hex')}\n`,{mode:0o600});
}
console.log('Missing handover keys generated in private backend/.env. Existing keys were preserved. No secret values are printed.');
